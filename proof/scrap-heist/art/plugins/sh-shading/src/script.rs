// mesh:paintShading(image, options), the method this plugin adds to the
// script API (lib.rs registers it): it paints the part stroke by stroke (a
// coat in the colors `paint` returns, then grime, rust or dust, and
// scratches), then edge highlights and contact shadows over it. Without
// `paint` the coat takes the colors already in the image.

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;
use std::time::Instant;

use modelkit_app::mlua::{self, AnyUserData, FromLuaMulti, Lua, MultiValue, Table};
use modelkit_app::{work, ImageHandle, MeshHandle};
use modelkit_cache::cache;
use modelkit_kernel::image::Image;
use modelkit_kernel::mesh::{self, dot, scale, Mesh};
use modelkit_kernel::progress;
use modelkit_render::detail;
use modelkit_texels::texels;
use sh_paint::{brush, coat, hand, marks};

use crate::bake;

// The numbers set by name in a `tune` table.
fn tune_numbers(tune: Option<Table>) -> mlua::Result<Vec<(String, f64)>> {
	match tune {
		Some(table) => table.pairs::<String, f64>().collect(),
		None => Ok(Vec::new()),
	}
}

// One brush: {motion = "press", tune = {name = value, ...}}.
fn brush_spec(spec: &Table) -> mlua::Result<Arc<marks::Marks>> {
	let motion: String = spec.get("motion")?;
	let overrides = tune_numbers(spec.get("tune")?)?;
	marks::Marks::new(&motion, &overrides).map(Arc::new).map_err(mlua::Error::RuntimeError)
}

// The brush a part names for one of its layers in its `brushes` table.
fn brush_slot(options: Option<&Table>, slot: &str) -> mlua::Result<Option<Arc<marks::Marks>>> {
	let Some(brushes) = options.map(|o| o.get::<Option<Table>>("brushes")).transpose()?.flatten() else {
		return Ok(None);
	};
	brushes.get::<Option<Table>>(slot)?.map(|spec| brush_spec(&spec)).transpose()
}

// The edge highlight's shorthand: `litMotion` and `litTune`.
fn edge_shorthand(options: &Table) -> mlua::Result<Option<Arc<marks::Marks>>> {
	let Some(motion) = options.get::<Option<String>>("highlightMotion")? else {
		return Ok(None);
	};
	let overrides = tune_numbers(options.get("highlightMotionTune")?)?;
	marks::Marks::new(&motion, &overrides).map(|marks| Some(Arc::new(marks))).map_err(mlua::Error::RuntimeError)
}

// The registered method: the script's arguments as the host passes them, then
// the paint. It returns nothing.
pub fn paint_shading_method(lua: &Lua, this: &MeshHandle, args: MultiValue) -> mlua::Result<MultiValue> {
	let (image, options) = <(AnyUserData, Option<Table>) as FromLuaMulti>::from_lua_multi(args, lua)?;
	paint_shading(lua, this, image, options)?;
	Ok(MultiValue::new())
}

fn paint_shading(lua: &Lua, this: &MeshHandle, image: AnyUserData, options: Option<Table>) -> mlua::Result<()> {
	let get = |key: &str, default: f64| -> mlua::Result<f64> {
		Ok(options.as_ref().map(|o| o.get::<Option<f64>>(key)).transpose()?.flatten().unwrap_or(default))
	};
	let shading = bake::Shading {
		highlight: get("highlight", 0.7)?,
		shadow: get("shadow", 0.75)?,
		bands: get("bands", 0.0)? as usize,
		blend: get("blend", 0.0)?.clamp(0.0, 1.0),
		highlight_ramp: get("highlightRamp", 0.0)?.max(0.0),
		reach: get("reach", bake::CONTACT_REACH)?.clamp(0.02, 4.0),
		bevel_reach: get("bevelReach", 0.0)?.clamp(0.0, 8.0),
		bevel_fold: get("bevelFold", bake::CONTACT_MIN_FOLD)?.clamp(0.0, 0.49),
		bevel_tilt: get("bevelTilt", 1.0)?.clamp(0.0, 8.0),
		roughness_base: get("roughnessBase", 0.0)?.clamp(0.0, 1.0),
		roughness_edge: get("roughnessEdge", 0.0)?.clamp(-1.0, 1.0),
		roughness_crease: get("roughnessCrease", 0.0)?.clamp(-1.0, 1.0),
		roughness_wear: get("roughnessWear", 0.0)?.clamp(-1.0, 1.0),
		metalness_on: options.as_ref().map(|o| o.get::<Option<bool>>("metalnessOn")).transpose()?.flatten().unwrap_or(false),
		metalness_base: get("metalnessBase", 0.0)?.clamp(0.0, 1.0),
		metalness_edge: get("metalnessEdge", 0.0)?.clamp(-1.0, 1.0),
		metalness_crease: get("metalnessCrease", 0.0)?.clamp(-1.0, 1.0),
		metalness_wear: get("metalnessWear", 0.0)?.clamp(-1.0, 1.0),
		highlight_width: get("highlightWidth", 1.0)?.clamp(0.1, 8.0),
		highlight_uneven: get("highlightUneven", 0.0)?.clamp(0.0, 1.0),
		highlight_uneven_step: get("highlightUnevenStep", 0.5)?.clamp(0.01, 16.0),
		edge_marks: match brush_slot(options.as_ref(), "edge")? {
			Some(marks) => Some(marks),
			None => options.as_ref().map(edge_shorthand).transpose()?.flatten(),
		},
		shade_marks: brush_slot(options.as_ref(), "shade")?,
		soft_marks: brush_slot(options.as_ref(), "soft")?,
		highlight_to_zero: options.as_ref().map(|o| o.get::<Option<bool>>("highlightToZero")).transpose()?.flatten().unwrap_or(false),
		highlight_end: get("highlightEnd", 3.0)?.clamp(0.1, 16.0),
		painted_highlights: options.as_ref().map(|o| o.get::<Option<bool>>("paintedHighlights")).transpose()?.flatten().unwrap_or(false),
		crisp: options.as_ref().map(|o| o.get::<Option<bool>>("crisp")).transpose()?.flatten().unwrap_or(false),
		corner_taper: get("cornerTaper", 0.0)?.clamp(0.0, 16.0),
		soft_highlight: get("softHighlight", 0.0)?.clamp(0.0, 1.0),
		soft_reach: get("softReach", 1.0)?.clamp(0.02, 8.0),
		soft_uneven: get("softUneven", 0.0)?.clamp(0.0, 1.0),
		soft_taper: get("softTaper", 0.0)?.clamp(0.0, 16.0),
		soft_to_zero: options.as_ref().map(|o| o.get::<Option<bool>>("softToZero")).transpose()?.flatten().unwrap_or(false),
		soft_power: get("softPower", 1.0)?.clamp(0.25, 8.0),
		soft_end: get("softEnd", 3.0)?.clamp(0.1, 16.0),
		// heightRange = {bottom, top}: share one gradient across chunks.
		height_range: match options.as_ref().map(|o| o.get::<Option<Vec<f64>>>("heightRange")).transpose()?.flatten().as_deref() {
			Some(&[bottom, top]) if top > bottom => Some([bottom, top]),
			_ => None,
		},
		// strokes = {{start, along, normal, length, width, tail, color, brush, seed}, ...}:
		// lines drawn over the coat, color in sRGB. brush is "taper"
		// (the default, crisp lines), "round" (a bristly mark pointed at
		// both ends) or "sponge" (a lobed dab).
		strokes: match options.as_ref().map(|o| o.get::<Option<Vec<Table>>>("strokes")).transpose()?.flatten() {
			Some(list) => list
				.iter()
				.enumerate()
				.map(|(index, stroke)| -> mlua::Result<brush::Stroke> {
					let along: mesh::Vec3 = stroke.get::<[f64; 3]>("along")?;
					let normal: mesh::Vec3 = stroke.get::<[f64; 3]>("normal")?;
					let across = mesh::cross(normal, along);
					let length = dot(across, across).sqrt().max(1e-9);
					Ok(brush::Stroke {
						brush: match stroke.get::<Option<String>>("brush")?.as_deref() {
							None | Some("taper") => brush::Brush::Taper,
							Some("round") => brush::Brush::Round,
							Some("sponge") => brush::Brush::Sponge,
							Some(other) => return Err(mlua::Error::RuntimeError(format!("unknown stroke brush {other}"))),
						},
						start: stroke.get::<[f64; 3]>("start")?,
						along,
						across: scale(across, 1.0 / length),
						normal,
						length: stroke.get("length")?,
						width: stroke.get("width")?,
						color: stroke.get::<[f32; 3]>("color")?.map(bake::to_linear),
						opacity: 1.0,
						// A stroke keeps the seed it is given, so a list cut down
						// to the strokes near a chunk draws each as the whole list would.
						seed: stroke.get::<Option<u32>>("seed")?.unwrap_or(index as u32),
						tail: stroke.get::<Option<f64>>("tail")?.unwrap_or(0.0).clamp(0.0, 1.0),
						marks: if stroke.contains_key("motion")? { Some(brush_spec(stroke)?) } else { None },
					})
				})
				.collect::<mlua::Result<Vec<_>>>()?,
			None => Vec::new(),
		},
	};
	let image = image.borrow::<ImageHandle>()?.0.clone();
	let mesh = this.0.borrow();
	let brush = match lua.app_data_ref::<detail::PreviewDetail>() {
		Some(detail) => detail.shrink(&mesh, &mut image.borrow_mut()),
		None => 1.0,
	};
	let hand = match options.as_ref().map(|o| o.get::<Option<String>>("hand")).transpose()?.flatten().as_deref() {
		None => None,
		Some("rock") => Some(coat::Hand::Rock),
		Some("wood") => Some(coat::Hand::Wood),
		Some("metal") => Some(coat::Hand::Metal),
		Some(other) => return Err(mlua::Error::RuntimeError(format!("unknown hand style {other}"))),
	};
	let overrides: Vec<(String, f64)> = match options.as_ref().map(|o| o.get::<Option<Table>>("handTune")).transpose()?.flatten() {
		Some(table) => table.pairs::<String, f64>().collect::<mlua::Result<_>>()?,
		None => Vec::new(),
	};
	let tuning = hand.map(|h| hand::Tuning::new(h, &overrides)).transpose().map_err(mlua::Error::RuntimeError)?;
	let look = coat::Look {
		rust: get("rust", 0.0)?.clamp(0.0, 1.0),
		rubber: options.as_ref().map(|o| o.get::<Option<bool>>("rubber")).transpose()?.flatten().unwrap_or(false),
		rust_edges: options.as_ref().map(|o| o.get::<Option<bool>>("rustEdges")).transpose()?.flatten().unwrap_or(false),
		gradient: get("gradient", 0.0)?.clamp(0.0, 1.0),
		brush,
		stamps: options.as_ref().map(|o| o.get::<Option<bool>>("stamps")).transpose()?.flatten().unwrap_or(false),
		hand,
		tuning,
		focus: options.as_ref().map(|o| o.get::<Option<Vec<f64>>>("handFocus")).transpose()?.flatten().filter(|f| f.len() == 4).map(|f| ([f[0], f[1], f[2]], f[3])),
		brushes: coat::Brushes {
			coat: brush_slot(options.as_ref(), "coat")?,
			grime: brush_slot(options.as_ref(), "grime")?,
			rust: brush_slot(options.as_ref(), "rust")?,
			drip: brush_slot(options.as_ref(), "drip")?,
			scratch: brush_slot(options.as_ref(), "scratch")?,
		},
	};
	let paint = options.as_ref().map(|o| o.get::<Option<mlua::Function>>("paint")).transpose()?.flatten();
	// A custom paint fn is keyed by `salt`, the item's source key, since its code can't be hashed.
	let custom = options.as_ref().map(|o| o.get::<Option<bool>>("custom")).transpose()?.flatten().unwrap_or(false);
	let salt = options.as_ref().map(|o| o.get::<Option<String>>("salt")).transpose()?.flatten();
	let mut occluders = Vec::new();
	if let Some(list) = options.as_ref().map(|o| o.get::<Option<Vec<AnyUserData>>>("occluders")).transpose()?.flatten() {
		for handle in list {
			occluders.push(handle.borrow::<MeshHandle>()?.0.clone());
		}
	}
	// Other chunks of this part: their edges count as this part's own.
	let mut group = Vec::new();
	if let Some(list) = options.as_ref().map(|o| o.get::<Option<Vec<AnyUserData>>>("group")).transpose()?.flatten() {
		for handle in list {
			group.push(handle.borrow::<MeshHandle>()?.0.clone());
		}
	}
	// groupSizes = {{w, h}, ...}, one per group mesh (the part itself
	// included): each chunk's texture size, for its shade layer.
	let group_sizes: Vec<(usize, usize)> = options
		.as_ref()
		.map(|o| o.get::<Option<Vec<Vec<f64>>>>("groupSizes"))
		.transpose()?
		.flatten()
		.unwrap_or_default()
		.iter()
		.map(|size| (size.first().copied().unwrap_or(0.0) as usize, size.get(1).copied().unwrap_or(0.0) as usize))
		.collect();
	// groupIndex: this part's place in the group list (1-based in Lua).
	let group_index = options.as_ref().map(|o| o.get::<Option<usize>>("groupIndex")).transpose()?.flatten().map_or(0, |n| n.saturating_sub(1));
	let name = options.as_ref().map(|o| o.get::<Option<String>>("name")).transpose()?.flatten().unwrap_or_default();
	let source = cache::Source { custom, salt };
	if cache::sharing() {
		let chunk = cache::bake_chunk(&name, &mesh);
		let mesh = (*mesh).clone();
		work::defer(chunk, Box::new(move || paint_part(&name, &mesh, &group, &group_sizes, group_index, &occluders, &image, &shading, &look, paint.as_ref(), &source).map_err(|e| e.to_string())));
		return Ok(());
	}
	paint_part(&name, &mesh, &group, &group_sizes, group_index, &occluders, &image, &shading, &look, paint.as_ref(), &source)
}

// Paints one part's shading onto its image.
#[allow(clippy::too_many_arguments)]
fn paint_part(name: &str, mesh: &Mesh, group: &[Rc<RefCell<Mesh>>], group_sizes: &[(usize, usize)], group_index: usize, occluders: &[Rc<RefCell<Mesh>>], image: &Rc<RefCell<Image>>, shading: &bake::Shading, look: &coat::Look, paint: Option<&mlua::Function>, source: &cache::Source) -> mlua::Result<()> {
	let borrowed: Vec<_> = occluders.iter().map(|m| m.borrow()).collect();
	let refs: Vec<&Mesh> = borrowed.iter().map(|m| &**m).collect();
	let borrowed_group: Vec<_> = group.iter().map(|m| m.borrow()).collect();
	let group_refs: Vec<&Mesh> = borrowed_group.iter().map(|m| &**m).collect();
	let sampling = Instant::now();
	let painted = texels::ImageSampler::new(mesh, &image.borrow());
	cache::spent(cache::SAMPLER_MICROS, sampling);
	let mut failed = None;
	let mut base = |p: mesh::Vec3, n: mesh::Vec3| -> [f64; 3] {
		let Some(paint) = paint else {
			return painted.color(p, n);
		};
		match paint.call::<(f64, f64, f64)>((p[0], p[1], p[2], n[0], n[1], n[2])) {
			Ok((r, g, b)) => [r, g, b],
			Err(error) => {
				failed.get_or_insert(error);
				[1.0, 0.0, 1.0]
			}
		}
	};
	let started = Instant::now();
	bake::paint_shading(mesh, &group_refs, group_sizes, group_index, &refs, &mut image.borrow_mut(), shading, look, &mut base, source);
	let (width, height) = (image.borrow().width, image.borrow().height);
	progress::say(&format!("shaded {name} {width}×{height} in {:.2}s", started.elapsed().as_secs_f64()));
	match failed {
		Some(error) => Err(error),
		None => Ok(()),
	}
}
