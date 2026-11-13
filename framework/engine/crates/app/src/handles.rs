// The script's handles on a mesh and an image, and their methods. Plugins add
// mesh methods of their own through the registry (plugin.rs).

use std::cell::RefCell;
use std::rc::Rc;

use mlua::{AnyUserData, UserData, UserDataMethods};

use crate::image::Image;
use crate::mesh::{dot, scale, sub, Face, Mesh};
use crate::{detail, plugin, texels};

#[derive(Clone)]
pub struct MeshHandle(pub Rc<RefCell<Mesh>>);

#[derive(Clone)]
pub struct ImageHandle(pub Rc<RefCell<Image>>);

impl UserData for MeshHandle {
	fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
		// Adds a vertex and returns its 1-based index.
		methods.add_method("vertex", |_, this, (x, y, z): (f64, f64, f64)| {
			let mut mesh = this.0.borrow_mut();
			mesh.positions.push([x, y, z]);
			Ok(mesh.positions.len())
		});
		// Adds a polygon from 1-based vertex indices, with optional UVs given
		// flat as {u1, v1, u2, v2, ...}.
		methods.add_method("face", |_, this, (verts, uvs): (Vec<usize>, Option<Vec<f64>>)| {
			let mut mesh = this.0.borrow_mut();
			let count = mesh.positions.len();
			if verts.len() < 3 || verts.iter().any(|&v| v == 0 || v > count) {
				return Err(mlua::Error::runtime(format!("face needs 3+ valid vertex indices (mesh has {count})")));
			}
			let uvs = match uvs {
				None => None,
				Some(flat) if flat.len() == verts.len() * 2 => Some(flat.chunks(2).map(|c| [c[0], c[1]]).collect()),
				Some(_) => return Err(mlua::Error::runtime("face uvs need one (u, v) pair per vertex")),
			};
			mesh.faces.push(Face { verts: verts.iter().map(|v| v - 1).collect(), uvs });
			Ok(())
		});
		methods.add_method("weld", |_, this, distance: Option<f64>| {
			this.0.borrow_mut().weld(distance.unwrap_or(1e-5));
			Ok(())
		});
		// true smooths everything, false is flat, a number smooths only across
		// edges sharper than that many degrees (auto smooth).
		methods.add_method("setSmooth", |_, this, smooth: mlua::Value| {
			let angle = match smooth {
				mlua::Value::Boolean(on) => if on { 180.0 } else { 0.0 },
				mlua::Value::Number(n) => n,
				mlua::Value::Integer(n) => n as f64,
				_ => return Err(mlua::Error::runtime("setSmooth takes a bool or an angle in degrees")),
			};
			this.0.borrow_mut().smooth_angle = angle;
			Ok(())
		});
		// Thickens an open surface; negative thickness grows inward.
		methods.add_method("solidify", |_, this, thickness: f64| {
			this.0.borrow_mut().solidify(thickness);
			Ok(())
		});
		// Returns a copy turned about z by `turn` radians, then moved by (x, y, z),
		// so a cached build can be placed anywhere without rebuilding it.
		methods.add_method("moved", |_, this, (turn, x, y, z): (f64, f64, f64, f64)| {
			let mesh = this.0.borrow();
			let (c, s) = (turn.cos(), turn.sin());
			let positions = mesh.positions.iter().map(|p| [p[0] * c - p[1] * s + x, p[0] * s + p[1] * c + y, p[2] + z]).collect();
			let normals = mesh.normals.as_ref().map(|list| list.iter().map(|n| [n[0] * c - n[1] * s, n[0] * s + n[1] * c, n[2]]).collect());
			let moved = Mesh { positions, faces: mesh.faces.clone(), smooth_angle: mesh.smooth_angle, normals };
			Ok(MeshHandle(Rc::new(RefCell::new(moved))))
		});
		methods.add_method("vertexCount", |_, this, ()| Ok(this.0.borrow().positions.len()));
		// The centre of the box around every vertex, and the radius of the
		// ball around that box: cx, cy, cz, radius.
		methods.add_method("bounds", |_, this, ()| {
			let mesh = this.0.borrow();
			let mut low = [f64::MAX; 3];
			let mut high = [f64::MIN; 3];
			for p in &mesh.positions {
				for axis in 0..3 {
					low[axis] = low[axis].min(p[axis]);
					high[axis] = high[axis].max(p[axis]);
				}
			}
			if mesh.positions.is_empty() {
				return Ok((0.0, 0.0, 0.0, 0.0));
			}
			let half = scale(sub(high, low), 0.5);
			let centre = scale([low[0] + high[0], low[1] + high[1], low[2] + high[2]], 0.5);
			Ok((centre[0], centre[1], centre[2], dot(half, half).sqrt()))
		});
		// Lays every face out in UV space, packed with a margin between charts.
		methods.add_method("unwrap", |_, this, margin: Option<f64>| {
			Ok(texels::unwrap(&mut this.0.borrow_mut(), margin.unwrap_or(0.01)))
		});
		// Paints each texel the color fn(x, y, z, nx, ny, nz) returns for the
		// surface point behind it, averaged over a 2×2 grid of points per texel
		// so stripes and edges come out anti-aliased.
		methods.add_method("paint", |lua, this, (image, color): (AnyUserData, mlua::Function)| {
			let image = image.borrow::<ImageHandle>()?.0.clone();
			// Shrunk before painting too, so a far part calls `color` less.
			if let Some(detail) = lua.app_data_ref::<detail::PreviewDetail>() {
				detail.shrink(&this.0.borrow(), &mut image.borrow_mut());
			}
			let (width, height) = {
				let image = image.borrow();
				(image.width, image.height)
			};
			let samples = texels::samples(&this.0.borrow(), width, height, 2);
			// `color` may return a fourth value, an opacity, which gives the
			// image an alpha channel for a see-through part.
			let mut sums = vec![[0.0f32; 5]; width * height];
			let mut has_alpha = false;
			for t in &samples {
				let [x, y, z] = t.position;
				let [nx, ny, nz] = t.normal;
				let (r, g, b, a) = color.call::<(f32, f32, f32, Option<f32>)>((x, y, z, nx, ny, nz))?;
				has_alpha |= a.is_some();
				let sum = &mut sums[t.pixel];
				*sum = [sum[0] + r, sum[1] + g, sum[2] + b, sum[3] + a.unwrap_or(1.0), sum[4] + 1.0];
			}
			let mut image = image.borrow_mut();
			let mut covered = vec![false; width * height];
			let mut opacity = vec![[1.0f32; 3]; width * height];
			for (pixel, [r, g, b, a, n]) in sums.into_iter().enumerate() {
				if n > 0.0 {
					image.pixels[pixel] = [r / n, g / n, b / n];
					opacity[pixel] = [a / n; 3];
					covered[pixel] = true;
				}
			}
			let mut alpha_covered = covered.clone();
			texels::dilate(&mut image.pixels, &mut covered, width, height, 8);
			if has_alpha {
				texels::dilate(&mut opacity, &mut alpha_covered, width, height, 8);
				image.alpha = Some(opacity.into_iter().map(|a| a[0]).collect());
			}
			Ok(())
		});
		// The methods the game's plugins add (plugin.rs), after the host's own.
		for &(name, method) in plugin::mesh_methods() {
			methods.add_method(name, method);
		}
	}
}

impl UserData for ImageHandle {
	fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
		// Pixels are 0-based with y = 0 at the bottom, matching UV v.
		methods.add_method("set", |_, this, (x, y, r, g, b): (usize, usize, f32, f32, f32)| {
			let mut image = this.0.borrow_mut();
			if x >= image.width || y >= image.height {
				return Err(mlua::Error::runtime(format!("pixel ({x}, {y}) outside {}x{}", image.width, image.height)));
			}
			let width = image.width;
			image.pixels[y * width + x] = [r, g, b];
			Ok(())
		});
		methods.add_method("width", |_, this, ()| Ok(this.0.borrow().width));
		methods.add_method("height", |_, this, ()| Ok(this.0.borrow().height));
		methods.add_method("get", |_, this, (x, y): (usize, usize)| {
			let image = this.0.borrow();
			let [r, g, b] = image.pixels[y.min(image.height - 1) * image.width + x.min(image.width - 1)];
			Ok((r, g, b))
		});
		methods.add_method("size", |_, this, ()| {
			let image = this.0.borrow();
			Ok((image.width, image.height))
		});
	}
}
