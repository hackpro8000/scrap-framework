// Texels: the mechanical front of a texture bake. Unwrapping lays a mesh's
// faces out in UV space; rasterizing finds the surface point behind every
// texel; dilating spreads painted texels over seams. Plus the geometry and
// lookup plumbing the shading layers build on. No look decisions live here.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

use modelkit_kernel::image::Image;
use modelkit_kernel::kernel::{to_linear, Texel};
use modelkit_kernel::mesh::{add, cross, dot, normalize, scale, sub, Mesh, Vec3};

// --- Unwrap -----------------------------------------------------------------

// Shared edges between faces, keyed by their sorted vertex pair.
fn edge_faces(mesh: &Mesh) -> HashMap<(usize, usize), Vec<usize>> {
	let mut edges: HashMap<(usize, usize), Vec<usize>> = HashMap::new();
	for (index, face) in mesh.faces.iter().enumerate() {
		for (k, &a) in face.verts.iter().enumerate() {
			let b = face.verts[(k + 1) % face.verts.len()];
			edges.entry((a.min(b), a.max(b))).or_default().push(index);
		}
	}
	edges
}

// Box-projection unwrap: faces are grouped by the axis they face most, each
// connected group is projected flat onto that axis' plane, and the groups are
// packed into the unit square with `margin` between them.
// Returns the scale from studs to UV units, so callers can size textures
// for a texel density.
pub fn unwrap(mesh: &mut Mesh, margin: f64) -> f64 {
	let normals: Vec<Vec3> = mesh.faces.iter().map(|face| mesh.face_normal(face)).collect();
	let side: Vec<usize> = normals
		.iter()
		.map(|n| {
			let axis = (0..3).max_by(|&a, &b| n[a].abs().total_cmp(&n[b].abs())).unwrap();
			axis * 2 + (n[axis] < 0.0) as usize
		})
		.collect();
	let edges = edge_faces(mesh);
	let mut neighbours: Vec<Vec<usize>> = vec![Vec::new(); mesh.faces.len()];
	for faces in edges.values() {
		for &a in faces {
			for &b in faces {
				if a != b && side[a] == side[b] {
					neighbours[a].push(b);
				}
			}
		}
	}

	// Flood-fill charts, then project each one onto its plane.
	let mut chart_of = vec![usize::MAX; mesh.faces.len()];
	let mut charts: Vec<Vec<usize>> = Vec::new();
	for start in 0..mesh.faces.len() {
		if chart_of[start] != usize::MAX {
			continue;
		}
		let mut members = vec![start];
		chart_of[start] = charts.len();
		let mut next = 0;
		while next < members.len() {
			for &other in &neighbours[members[next]] {
				if chart_of[other] == usize::MAX {
					chart_of[other] = charts.len();
					members.push(other);
				}
			}
			next += 1;
		}
		charts.push(members);
	}
	let flat = |side: usize, p: Vec3| -> [f64; 2] {
		match side {
			0 => [p[1], p[2]],
			1 => [-p[1], p[2]],
			2 => [-p[0], p[2]],
			3 => [p[0], p[2]],
			4 => [p[0], p[1]],
			_ => [p[0], -p[1]],
		}
	};
	let mut boxes: Vec<([f64; 2], [f64; 2])> = Vec::new();
	for members in &charts {
		let mut low = [f64::MAX; 2];
		let mut high = [f64::MIN; 2];
		for &face in members {
			for &vert in &mesh.faces[face].verts {
				let q = flat(side[face], mesh.positions[vert]);
				for k in 0..2 {
					low[k] = low[k].min(q[k]);
					high[k] = high[k].max(q[k]);
				}
			}
		}
		boxes.push((low, [high[0] - low[0], high[1] - low[1]]));
	}

	// Shelf pack, tallest first, shrinking until everything fits.
	let mut order: Vec<usize> = (0..charts.len()).collect();
	order.sort_by(|&a, &b| boxes[b].1[1].total_cmp(&boxes[a].1[1]));
	let area: f64 = boxes.iter().map(|(_, size)| (size[0] + 1e-6) * (size[1] + 1e-6)).sum();
	let mut fit = (0.9 / area).sqrt();
	let mut offsets = vec![[0.0; 2]; charts.len()];
	loop {
		let (mut x, mut y, mut row) = (margin, margin, 0.0f64);
		let mut fits = true;
		for &chart in &order {
			let [w, h] = boxes[chart].1.map(|s| s * fit);
			if x + w + margin > 1.0 && x > margin {
				x = margin;
				y += row + margin;
				row = 0.0;
			}
			offsets[chart] = [x, y];
			x += w + margin;
			row = row.max(h);
			fits &= x <= 1.0 + 1e-9;
		}
		if fits && y + row + margin <= 1.0 {
			break;
		}
		fit *= 0.97;
	}
	for (index, face) in mesh.faces.iter_mut().enumerate() {
		let chart = chart_of[index];
		let (low, _) = boxes[chart];
		let offset = offsets[chart];
		let uvs = face
			.verts
			.iter()
			.map(|&vert| {
				let q = flat(side[index], mesh.positions[vert]);
				[offset[0] + (q[0] - low[0]) * fit, offset[1] + (q[1] - low[1]) * fit]
			})
			.collect();
		face.uvs = Some(uvs);
	}
	fit
}

// --- Rasterize --------------------------------------------------------------

// The directions along a triangle's surface that U and V increase in. A
// triangle without usable UVs takes any frame on its surface.
fn tangent_frame(corners: &[modelkit_kernel::mesh::Corner; 3], normal: Vec3) -> (Vec3, Vec3) {
	let e1 = sub(corners[1].position, corners[0].position);
	let e2 = sub(corners[2].position, corners[0].position);
	let (du1, dv1) = (corners[1].uv[0] - corners[0].uv[0], corners[1].uv[1] - corners[0].uv[1]);
	let (du2, dv2) = (corners[2].uv[0] - corners[0].uv[0], corners[2].uv[1] - corners[0].uv[1]);
	let det = du1 * dv2 - du2 * dv1;
	if det.abs() < 1e-12 {
		let side = if normal[2].abs() < 0.9 { [0.0, 0.0, 1.0] } else { [1.0, 0.0, 0.0] };
		let tangent = normalize(cross(side, normal));
		return (tangent, cross(normal, tangent));
	}
	let tangent = scale(sub(scale(e1, dv2), scale(e2, dv1)), 1.0 / det);
	let bitangent = scale(sub(scale(e2, du1), scale(e1, du2)), 1.0 / det);
	// Flat on the surface, each a unit long.
	let flatten = |v: Vec3| normalize(sub(v, scale(normal, dot(v, normal))));
	(flatten(tangent), flatten(bitangent))
}

pub fn texels(mesh: &Mesh, width: usize, height: usize) -> Vec<Texel> {
	samples(mesh, width, height, 1)
}

// Like texels, but tests a grid × grid pattern of points inside each pixel, so
// a pixel can come back several times, once per covered sample.
pub fn samples(mesh: &Mesh, width: usize, height: usize, grid: usize) -> Vec<Texel> {
	samples_in(mesh, width, height, grid, None)
}

// Like samples, but given which pixels are wanted, skips each triangle whose
// pixel rect holds none of them. Every texel on a wanted pixel still comes
// back, in the same order.
pub fn samples_in(mesh: &Mesh, width: usize, height: usize, grid: usize, wanted: Option<&[bool]>) -> Vec<Texel> {
	// One thread finds the texels: handing triangles to the other threads,
	// singly or in batches, was measured slower on the map (2026-11-11).
	let mut found = Vec::new();
	for corners in mesh.triangles() {
		let face_normal = normalize(cross(sub(corners[1].position, corners[0].position), sub(corners[2].position, corners[0].position)));
		let (tangent, bitangent) = tangent_frame(&corners, face_normal);
		let p = corners.map(|c| [c.uv[0] * width as f64 - 0.5, c.uv[1] * height as f64 - 0.5]);
		let area = (p[1][0] - p[0][0]) * (p[2][1] - p[0][1]) - (p[2][0] - p[0][0]) * (p[1][1] - p[0][1]);
		if area.abs() < 1e-12 {
			continue;
		}
		let x0 = p.iter().map(|q| q[0]).fold(f64::MAX, f64::min).floor().max(0.0) as usize;
		let x1 = (p.iter().map(|q| q[0]).fold(f64::MIN, f64::max).ceil() as usize).min(width - 1);
		let y0 = p.iter().map(|q| q[1]).fold(f64::MAX, f64::min).floor().max(0.0) as usize;
		let y1 = (p.iter().map(|q| q[1]).fold(f64::MIN, f64::max).ceil() as usize).min(height - 1);
		if wanted.is_some_and(|wanted| !(y0..=y1).any(|y| x0 <= x1 && wanted[y * width + x0..=y * width + x1].contains(&true))) {
			continue;
		}
		for y in y0..=y1 {
			for x in x0..=x1 {
			for sample in 0..grid * grid {
				let (fx, fy) = (
					x as f64 + ((sample % grid) as f64 + 0.5) / grid as f64 - 0.5,
					y as f64 + ((sample / grid) as f64 + 0.5) / grid as f64 - 0.5,
				);
				let w0 = ((p[1][0] - fx) * (p[2][1] - fy) - (p[2][0] - fx) * (p[1][1] - fy)) / area;
				let w1 = ((p[2][0] - fx) * (p[0][1] - fy) - (p[0][0] - fx) * (p[2][1] - fy)) / area;
				let w2 = 1.0 - w0 - w1;
				if w0 < -1e-6 || w1 < -1e-6 || w2 < -1e-6 {
					continue;
				}
				let blend = |f: &dyn Fn(usize) -> Vec3| add(add(scale(f(0), w0), scale(f(1), w1)), scale(f(2), w2));
				found.push(Texel {
					pixel: y * width + x,
					position: blend(&|k| corners[k].position),
					normal: normalize(blend(&|k| corners[k].normal)),
					face_normal,
					tangent,
					bitangent,
				});
			}
			}
		}
	}
	found
}

// Spreads painted texels outward into unpainted ones so UV seams and mipmaps
// don't pull in background.
pub fn dilate(pixels: &mut [[f32; 3]], covered: &mut [bool], width: usize, height: usize, passes: usize) {
	dilate_within(pixels, covered, width, height, passes, None);
}

// Like dilate, but only spreads into the wanted pixels when given. A wanted
// pixel whose neighbours `passes` pixels round are all wanted comes out as
// from dilate; the rest are left as they are.
pub fn dilate_within(pixels: &mut [[f32; 3]], covered: &mut [bool], width: usize, height: usize, passes: usize, wanted: Option<&[bool]>) {
	let threads = std::thread::available_parallelism().map_or(4, |n| n.get());
	let rows = height.div_ceil(threads).max(1);
	for _ in 0..passes {
		let (before, colors) = (covered.to_vec(), pixels.to_vec());
		// Each thread fills its own band of rows, reading the previous pass.
		std::thread::scope(|scope| {
			for (band, (pixels, covered)) in pixels.chunks_mut(rows * width).zip(covered.chunks_mut(rows * width)).enumerate() {
				let (before, colors) = (&before, &colors);
				scope.spawn(move || {
					for (local, (pixel, done)) in pixels.iter_mut().zip(covered.iter_mut()).enumerate() {
						let at = band * rows * width + local;
						if before[at] || wanted.is_some_and(|wanted| !wanted[at]) {
							continue;
						}
						let (x, y) = ((at % width) as i64, (at / width) as i64);
						let mut sum = [0.0f32; 3];
						let mut count = 0.0;
						for (dx, dy) in [(-1i64, 0i64), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
							let (nx, ny) = (x + dx, y + dy);
							if nx < 0 || ny < 0 || nx >= width as i64 || ny >= height as i64 {
								continue;
							}
							let neighbour = ny as usize * width + nx as usize;
							if before[neighbour] {
								for k in 0..3 {
									sum[k] += colors[neighbour][k];
								}
								count += 1.0;
							}
						}
						if count > 0.0 {
							*pixel = sum.map(|s| s / count);
							*done = true;
						}
					}
				});
			}
		});
	}
}

// Point of the triangle nearest p (Ericson, Real-Time Collision Detection 5.1.5).
pub fn closest_on_triangle(p: Vec3, [a, b, c]: [Vec3; 3]) -> Vec3 {
	let (ab, ac) = (sub(b, a), sub(c, a));
	let ap = sub(p, a);
	let (d1, d2) = (dot(ab, ap), dot(ac, ap));
	if d1 <= 0.0 && d2 <= 0.0 {
		return a;
	}
	let bp = sub(p, b);
	let (d3, d4) = (dot(ab, bp), dot(ac, bp));
	if d3 >= 0.0 && d4 <= d3 {
		return b;
	}
	let vc = d1 * d4 - d3 * d2;
	if vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0 {
		return add(a, scale(ab, d1 / (d1 - d3)));
	}
	let cp = sub(p, c);
	let (d5, d6) = (dot(ab, cp), dot(ac, cp));
	if d6 >= 0.0 && d5 <= d6 {
		return c;
	}
	let vb = d5 * d2 - d1 * d6;
	if vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0 {
		return add(a, scale(ac, d2 / (d2 - d6)));
	}
	let va = d3 * d6 - d5 * d4;
	if va <= 0.0 && d4 - d3 >= 0.0 && d5 - d6 >= 0.0 {
		return add(b, scale(sub(c, b), (d4 - d3) / ((d4 - d3) + (d5 - d6))));
	}
	let denom = 1.0 / (va + vb + vc);
	add(a, add(scale(ab, vb * denom), scale(ac, vc * denom)))
}

// The contact grid hashes millions of small integer cell keys; std's default
// hasher guards against crafted keys, which only slows that down.
#[derive(Default)]
pub struct CellHasher(u64);

impl Hasher for CellHasher {
	fn write(&mut self, bytes: &[u8]) {
		for chunk in bytes.chunks(8) {
			let mut word = [0u8; 8];
			word[..chunk.len()].copy_from_slice(chunk);
			self.0 = (self.0.rotate_left(5) ^ u64::from_le_bytes(word)).wrapping_mul(0x517c_c1b7_2722_0a95);
		}
	}

	fn finish(&self) -> u64 {
		self.0
	}
}

pub type CellMap<V> = HashMap<[i64; 3], V, BuildHasherDefault<CellHasher>>;

// Corner positions only, fanned the way Mesh::triangles fans each face, but
// without working out the smoothed normals nobody here reads.
pub fn mesh_triangles(mesh: &Mesh) -> Vec<[Vec3; 3]> {
	let at = |vert: usize| mesh.positions[vert];
	mesh.faces
		.iter()
		.flat_map(|face| (1..face.verts.len() - 1).map(move |k| [at(face.verts[0]), at(face.verts[k]), at(face.verts[k + 1])]))
		.collect()
}

// A layer image holding one value per texel, placed at the texel's pixel.
pub fn layer_image(width: usize, height: usize, texels: &[Texel], values: &[[f32; 3]]) -> Image {
	let mut image = Image::new(width, height, [0.0; 3]);
	for (texel, value) in texels.iter().zip(values) {
		image.pixels[texel.pixel] = *value;
	}
	image
}

pub fn to_f32(c: [f64; 3]) -> [f32; 3] {
	c.map(|x| x as f32)
}

pub fn to_linear_f64(c: f64) -> f64 {
	to_linear(c as f32)
}

// Looks up the color an image already holds at a surface point, from the
// nearest texel facing the same way, for coats painted over existing colors.
pub struct ImageSampler {
	texels: Vec<(Vec3, Vec3, [f32; 3])>,
	grid: HashMap<[i64; 3], Vec<usize>>,
}

const SAMPLER_CELL: f64 = 0.1;

impl ImageSampler {
	pub fn new(mesh: &Mesh, image: &Image) -> ImageSampler {
		let key = |p: Vec3| p.map(|c| (c / SAMPLER_CELL).floor() as i64);
		let mut sampler = ImageSampler { texels: Vec::new(), grid: HashMap::new() };
		for texel in texels(mesh, image.width, image.height) {
			sampler.grid.entry(key(texel.position)).or_default().push(sampler.texels.len());
			sampler.texels.push((texel.position, texel.face_normal, image.pixels[texel.pixel]));
		}
		sampler
	}

	// sRGB color at p on a surface with normal n.
	pub fn color(&self, p: Vec3, n: Vec3) -> [f64; 3] {
		let home = p.map(|c| (c / SAMPLER_CELL).floor() as i64);
		let mut best = (f64::MAX, [0.5f32; 3]);
		for x in -1..=1 {
			for y in -1..=1 {
				for z in -1..=1 {
					for &index in self.grid.get(&[home[0] + x, home[1] + y, home[2] + z]).into_iter().flatten() {
						let (at, normal, color) = self.texels[index];
						let offset = sub(p, at);
						let d = dot(offset, offset) + if dot(n, normal) < 0.5 { 1.0 } else { 0.0 };
						if d < best.0 {
							best = (d, color);
						}
					}
				}
			}
		}
		best.1.map(f64::from)
	}
}
