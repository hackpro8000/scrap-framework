// The script's globals: TEXEL_SCALE, the eye-preview helpers, Mesh.new,
// Image.new, the model table (bone, clip, part, cached) and require.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

use mlua::{AnyUserData, Lua, Table, Value};

use crate::image::Image;
use crate::mesh::{self, Mesh};
use crate::{anim, cache, detail, plugin, progress, work, Bone, ImageHandle, MeshHandle, Part};

#[allow(clippy::too_many_arguments)]
pub(crate) fn install_api(lua: &Lua, dir: &Path, parts: Rc<RefCell<Vec<Part>>>, bones: Rc<RefCell<Vec<Bone>>>, clips: Rc<RefCell<Vec<anim::Clip>>>, used: Rc<RefCell<Vec<PathBuf>>>, search: Vec<PathBuf>, texel_scale: f64, detail_eyes: &[(mesh::Vec3, mesh::Vec3)], size: usize) -> mlua::Result<()> {
	let globals = lua.globals();
	// Scales every texel density a layout asks for: 1 for final builds, less for previews.
	globals.set("TEXEL_SCALE", texel_scale)?;
	// Eye previews shrink each texture before shading it (see detail.rs).
	// previewBand(x, y, z) names a placement's distance band, and
	// previewPlacing(x, y, z, turn) tells the shrinking where place() puts the
	// model it is building at the origin; previewPlacing() clears it. Both are
	// absent outside eye previews.
	if !detail_eyes.is_empty() {
		lua.set_app_data(detail::PreviewDetail { eyes: detail_eyes.to_vec(), size, placing: Cell::new(None) });
		globals.set(
			"previewBand",
			lua.create_function(|lua, (x, y, z): (f64, f64, f64)| {
				Ok(lua.app_data_ref::<detail::PreviewDetail>().map(|detail| detail.band([x, y, z])))
			})?,
		)?;
		globals.set(
			"previewPlacing",
			lua.create_function(|lua, (x, y, z, turn): (Option<f64>, Option<f64>, Option<f64>, Option<f64>)| {
				if let Some(detail) = lua.app_data_ref::<detail::PreviewDetail>() {
					let placing = x.map(|x| ([x, y.unwrap_or(0.0), z.unwrap_or(0.0)], turn.unwrap_or(0.0)));
					detail.placing.set(placing);
				}
				Ok(())
			})?,
		)?;
	}
	// Eye previews size textures by where the eyes stand, so the eyes key the cache.
	let eye_key: String = detail_eyes.iter().map(|(e, t)| format!(" {},{},{}>{},{},{}", e[0], e[1], e[2], t[0], t[1], t[2])).collect();
	let eye_key = if detail_eyes.is_empty() { String::new() } else { format!(" eyes{eye_key} {size}") };

	let mesh_api = lua.create_table()?;
	mesh_api.set("new", lua.create_function(|_, ()| Ok(MeshHandle(Rc::new(RefCell::new(Mesh::new())))))?)?;
	globals.set("Mesh", mesh_api)?;

	let image_api = lua.create_table()?;
	image_api.set(
		"new",
		lua.create_function(|_, (width, height, r, g, b): (usize, usize, Option<f32>, Option<f32>, Option<f32>)| {
			if width == 0 || height == 0 {
				return Err(mlua::Error::runtime("image needs a nonzero size"));
			}
			let color = [r.unwrap_or(1.0), g.unwrap_or(1.0), b.unwrap_or(1.0)];
			Ok(ImageHandle(Rc::new(RefCell::new(Image::new(width, height, color)))))
		})?,
	)?;
	globals.set("Image", image_api)?;

	let model_api = lua.create_table()?;
	// model.bone(name, {at = {x, y, z}, parent = "Name"?}) adds a joint whose
	// pivot sits at `at`; bones without a parent are roots.
	// model.clip(name, {length = seconds, keys = {Bone = {{t = 0, rot = {x, y, z}?,
	// pos = {x, y, z}?}, ...}}}) adds an animation; see anim.rs.
	let rig = bones.clone();
	model_api.set(
		"clip",
		lua.create_function(move |_, (name, options): (String, Table)| {
			let length: f64 = options.get("length")?;
			let rig = rig.borrow();
			let mut tracks = Vec::new();
			for pair in options.get::<Table>("keys")?.pairs::<String, Table>() {
				let (bone, list) = pair?;
				let index = rig.iter().position(|b| b.name == bone).ok_or_else(|| mlua::Error::runtime(format!("clip {name}: no bone {bone}")))?;
				let mut keys = Vec::new();
				for key in list.sequence_values::<Table>() {
					let key = key?;
					let vector = |field: &str| -> mlua::Result<[f64; 3]> {
						Ok(match key.get::<Option<Vec<f64>>>(field)? {
							None => [0.0; 3],
							Some(v) if v.len() == 3 => [v[0], v[1], v[2]],
							Some(_) => return Err(mlua::Error::runtime(format!("clip {name}: {field} needs {{x, y, z}}"))),
						})
					};
					keys.push(anim::Key { time: key.get("t")?, rotation: vector("rot")?, offset: vector("pos")? });
				}
				keys.sort_by(|a, b| a.time.total_cmp(&b.time));
				tracks.push((index, keys));
			}
			clips.borrow_mut().push(anim::Clip { name: name.clone(), length, tracks });
			Ok(name)
		})?,
	)?;
	let rig = bones.clone();
	model_api.set(
		"bone",
		lua.create_function(move |_, (name, options): (String, Table)| {
			let at: Vec<f64> = options.get("at")?;
			if at.len() != 3 {
				return Err(mlua::Error::runtime("bone at needs {x, y, z}"));
			}
			let mut rig = rig.borrow_mut();
			if rig.iter().any(|b| b.name == name) {
				return Err(mlua::Error::runtime(format!("bone {name} already exists")));
			}
			let parent = match options.get::<Option<String>>("parent")? {
				None => None,
				Some(p) => Some(rig.iter().position(|b| b.name == p).ok_or_else(|| mlua::Error::runtime(format!("no bone {p}")))?),
			};
			rig.push(Bone { name: name.clone(), parent, head: [at[0], at[1], at[2]] });
			Ok(name)
		})?,
	)?;
	model_api.set(
		"part",
		lua.create_function(move |_, (name, mesh, image, options): (String, AnyUserData, AnyUserData, Option<Table>)| {
			let group = options.as_ref().map(|o| o.get::<Option<String>>("group")).transpose()?.flatten();
			let preview = options.as_ref().map(|o| o.get::<Option<bool>>("preview")).transpose()?.flatten().unwrap_or(true);
			let emissive = options.as_ref().map(|o| o.get::<Option<f32>>("emissive")).transpose()?.flatten().unwrap_or(0.0);
			let bone = match options.as_ref().map(|o| o.get::<Option<String>>("bone")).transpose()?.flatten() {
				None => None,
				Some(b) => Some(bones.borrow().iter().position(|x| x.name == b).ok_or_else(|| mlua::Error::runtime(format!("no bone {b} (add it before its parts)")))?),
			};
			parts.borrow_mut().push(Part {
				bone,
				name,
				group,
				preview,
				emissive,
				mesh: mesh.borrow::<MeshHandle>()?.0.clone(),
				image: image.borrow::<ImageHandle>()?.0.clone(),
			});
			Ok(())
		})?,
	)?;
	// model.cached(key, build) returns the parts build() returns, as a list of
	// {name, mesh, image, preview, emissive}, loading them from the cache when this key
	// was built before. The key must change whenever the result would.
	let folder = dir.to_path_buf();
	// With --share-bakes a part's save waits for its paint, so a later placement
	// of the same key takes the first one's parts from here, not from the file.
	let built_this_run: RefCell<HashMap<PathBuf, Table>> = RefCell::new(HashMap::new());
	model_api.set(
		"cached",
		lua.create_function(move |lua, (key, build): (String, mlua::Function)| {
			// A preview build is kept apart from the final one, which it differs from.
			let key = if texel_scale == 1.0 { key } else { format!("{key} @{texel_scale}{eye_key}") };
			// What a plugin's settings change in a build is part of the key (plugin.rs).
			let key = plugin::cache_key(key);
			let path = cache::path(&folder, &key);
			used.borrow_mut().push(path.clone());
			if let Some(list) = built_this_run.borrow().get(&path) {
				return Ok(list.clone());
			}
			if let Some(saved) = cache::load(&path) {
				progress::say(&format!("cached {}", progress::label(&key)));
				let list = lua.create_table()?;
				for part in saved {
					let entry = lua.create_table()?;
					entry.set("name", part.name)?;
					entry.set("mesh", MeshHandle(Rc::new(RefCell::new(part.mesh))))?;
					entry.set("image", ImageHandle(Rc::new(RefCell::new(part.image))))?;
					entry.set("preview", part.preview)?;
					entry.set("emissive", part.emissive)?;
					list.push(entry)?;
				}
				return Ok(list);
			}
			let label = progress::label(&key);
			progress::say(&format!("building {label}"));
			let started = Instant::now();
			let list: Table = progress::nested(|| build.call(()))?;
			progress::say(&format!("built {label}: {} parts in {:.1}s", list.raw_len(), started.elapsed().as_secs_f64()));
			let mut built = Vec::new();
			for entry in list.sequence_values::<Table>() {
				let entry = entry?;
				let mesh = entry.get::<AnyUserData>("mesh")?.borrow::<MeshHandle>()?.0.clone();
				let image = entry.get::<AnyUserData>("image")?.borrow::<ImageHandle>()?.0.clone();
				built.push((entry.get::<String>("name")?, entry.get::<Option<bool>>("preview")?.unwrap_or(true), entry.get::<Option<f32>>("emissive")?.unwrap_or(0.0), mesh, image));
			}
			let saved_at = path.clone();
			let save = move || {
				let borrowed: Vec<_> = built.iter().map(|(n, p, e, m, i)| (n.clone(), *p, *e, m.borrow(), i.borrow())).collect();
				let refs: Vec<_> = borrowed.iter().map(|(n, p, e, m, i)| (n.clone(), *p, *e, &**m, &**i)).collect();
				cache::save(&path, &refs).map_err(|e| e.to_string())
			};
			if cache::sharing() {
				built_this_run.borrow_mut().insert(saved_at, list.clone());
				work::defer_save(Box::new(save));
			} else {
				save().map_err(mlua::Error::external)?;
			}
			Ok(list)
		})?,
	)?;
	globals.set("model", model_api)?;

	// require("Name") loads Name.luau from the model's folder, then the shared
	// library, once per build.
	let cache: Rc<RefCell<HashMap<String, Value>>> = Rc::new(RefCell::new(HashMap::new()));
	globals.set(
		"require",
		lua.create_function(move |lua, name: String| {
			if let Some(value) = cache.borrow().get(&name) {
				return Ok(value.clone());
			}
			let path = search
				.iter()
				.map(|dir| dir.join(format!("{name}.luau")))
				.find(|p| p.exists())
				.ok_or_else(|| mlua::Error::runtime(format!("no module {name}.luau")))?;
			let source = std::fs::read_to_string(&path).map_err(mlua::Error::external)?;
			let value: Value = lua.load(source).set_name(format!("@{}", path.display())).eval()?;
			cache.borrow_mut().insert(name, value.clone());
			Ok(value)
		})?,
	)?;
	Ok(())
}
