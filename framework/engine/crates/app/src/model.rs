// One model build, in its run phases: the script, the shared bakes, the .glb
// and its texture files (and upload chunks), the review renders, a clip's
// frames and the closing timings.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

use mlua::Lua;

use crate::api::install_api;
use crate::image::Image;
use crate::shots::{difference, draw_shot, load_for, review_jobs, save_shot, write_png, Closeup, Review};
use crate::{anim, cache, glb, mesh, plugin, progress, render, scene, work, Part};

#[allow(clippy::too_many_arguments)]
pub(crate) fn run(dir: &Path, turntable: usize, size: usize, closeups: &[Closeup], eyes: &[(mesh::Vec3, mesh::Vec3)], shown_clip: Option<&str>, texel_scale: f64, detail_eyes: &[(mesh::Vec3, mesh::Vec3)], chunks: bool, shard: Option<(usize, usize)>, review: &Review) -> Result<(), String> {
	let started = Instant::now();
	let name = dir.file_name().and_then(|n| n.to_str()).ok_or("bad model folder")?.to_string();
	let script = dir.join("model.luau");
	let source = std::fs::read_to_string(&script).map_err(|e| format!("{}: {e}", script.display()))?;
	let library = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("lib");

	let lua = Lua::new();
	lua.enable_jit(true);
	let parts = Rc::new(RefCell::new(Vec::new()));
	let bones = Rc::new(RefCell::new(Vec::new()));
	let clips = Rc::new(RefCell::new(Vec::new()));
	let used = Rc::new(RefCell::new(Vec::new()));
	cache::enable_paint_cache(dir, used.clone());
	install_api(&lua, dir, parts.clone(), bones.clone(), clips.clone(), used.clone(), vec![dir.to_path_buf(), library], texel_scale, detail_eyes, size).map_err(|e| e.to_string())?;
	// The layout prelude reads these to build only this shard's placements.
	if let Some((index, count)) = shard {
		lua.globals().set("SHARD_INDEX", index).map_err(|e| e.to_string())?;
		lua.globals().set("SHARD_COUNT", count).map_err(|e| e.to_string())?;
	}
	// Marks the globals safe once the API is in: Luau then caches lookups like
	// math.noise, takes its fast paths for builtins and runs the JIT's native
	// code. Without it a paint fn runs several times slower. A safe chunk
	// resolves a path like model.part once, as it loads, so the API tables
	// scripts write into (prelude and IslandStudy swap model.part) are
	// declared mutable and looked up each time instead.
	lua.set_compiler(mlua::chunk::Compiler::new().set_mutable_globals(["model", "Mesh", "Image"]));
	// SAFETY: only sets the safe flag on the globals table.
	unsafe { lua.exec_raw::<()>((), |state| mlua::ffi::lua_setsafeenv(state, mlua::ffi::LUA_GLOBALSINDEX, 1)) }.map_err(|e| e.to_string())?;
	progress::say(&format!("running {name}/model.luau"));
	lua.load(source).set_name(format!("@{}", script.display())).exec().map_err(|e| e.to_string())?;
	progress::total(&format!("TIMING script: {:.1}s", started.elapsed().as_secs_f64()));
	// A shard uses only part of the cache, so pruning would throw away the
	// other shards' entries, unless the cache is the shard's own
	// (MODELKIT_PRUNE=1, as the build-map-shards workflow sets).
	if cache::sharing() {
		work::bake_and_swap(review.work_port.ok_or("--share-bakes needs --work-port")?)?;
	}
	if shard.is_none() || std::env::var("MODELKIT_PRUNE").is_ok_and(|v| v == "1") {
		cache::prune(dir, &used.borrow());
	}
	let scripted = started.elapsed();

	let parts = parts.borrow();
	if parts.is_empty() {
		return Err("model.luau added no parts (call model.part)".into());
	}
	let bones = bones.borrow();
	if !bones.is_empty() {
		if let Some(loose) = parts.iter().find(|p| p.bone.is_none()) {
			return Err(format!("part {} has no bone; a rigged model needs one on every part", loose.name));
		}
	}
	progress::say(&format!("writing {name}.glb and {} textures", parts.len()));
	let writing = Instant::now();
	let glb = dir.join(format!("{name}.glb"));
	let glb_bytes = glb::write(&parts, &bones, &clips.borrow());
	std::fs::write(&glb, &glb_bytes).map_err(|e| e.to_string())?;
	// --glb-check reads the file back below; otherwise its bytes go now.
	let written = review.glb_check.then_some(glb_bytes);
	if !clips.borrow().is_empty() {
		std::fs::write(dir.join(format!("{name}Clips.luau")), anim::write_luau(&name, &bones, &clips.borrow())).map_err(|e| e.to_string())?;
	}
	if chunks {
		let tag = shard.map_or(String::new(), |(index, _)| format!("S{index}_"));
		write_chunks(dir, &name, &tag, &parts, !bones.is_empty())?;
	}
	for part in parts.iter() {
		let png = dir.join(format!("{}.png", part.name));
		std::fs::write(png, part.image.borrow().encode_png()).map_err(|e| e.to_string())?;
		// The normal map (--normals), beside the colour map.
		let normal_png = dir.join(format!("{}_Normal.png", part.name));
		match part.image.borrow().encode_normal_png() {
			Some(bytes) => std::fs::write(normal_png, bytes).map_err(|e| e.to_string())?,
			None => {
				let _ = std::fs::remove_file(normal_png);
			}
		}
		// Flat maps for the SurfaceAppearance: no metal, fully rough (unless a
		// plugin sets the roughness, plugin.rs), so Roblox adds no highlights
		// over the painted shading.
		for (map, value) in [("Metalness", 0.0), ("Roughness", plugin::export_roughness() as f32)] {
			let flat = Image::new(4, 4, [value; 3]).encode_png();
			std::fs::write(dir.join(format!("{}_{map}.png", part.name)), flat).map_err(|e| e.to_string())?;
		}
		// Baked roughness and metalness maps replace the flat ones.
		if let Some(bytes) = part.image.borrow().encode_roughness_png() {
			std::fs::write(dir.join(format!("{}_Roughness.png", part.name)), bytes).map_err(|e| e.to_string())?;
		}
		if let Some(bytes) = part.image.borrow().encode_metalness_png() {
			std::fs::write(dir.join(format!("{}_Metalness.png", part.name)), bytes).map_err(|e| e.to_string())?;
		}
		// Glowing parts glow all over: a white EmissiveMaskContent, with the
		// strength set on the SurfaceAppearance's EmissiveStrength.
		if part.emissive > 0.0 {
			let mask = Image::new(4, 4, [1.0; 3]).encode_png();
			std::fs::write(dir.join(format!("{}_Emissive.png", part.name)), mask).map_err(|e| e.to_string())?;
		}
	}
	progress::total(&format!("TIMING {name}.glb and {} parts' texture files written: {:.1}s", parts.len(), writing.elapsed().as_secs_f64()));
	let shown: Vec<&Part> = parts.iter().filter(|p| p.preview).collect();
	// Every render below counts as one job, in a fixed order; with a share
	// this machine makes only its jobs, so machines split one model's renders,
	// and with a work port it claims each next job as it comes free.
	let jobs = review_jobs(size, turntable, closeups, eyes, review, shard.is_none());
	let mut claims = review.work_port.map(|port| work::RenderClaims::connect(port, jobs.len())).transpose()?;
	// --glb-check: the .glb just written, read back, renders every view again.
	let reloaded = match written {
		Some(bytes) => Some(load_for(bytes, &jobs)?),
		None => None,
	};
	// Both lists keep the build's part order, and each shot's one View draws all three.
	let reloaded_shown: Vec<&Part> = reloaded.as_ref().map_or(Vec::new(), |scene| scene.parts.iter().filter(|p| p.preview).collect());
	// The shown parts rounded as the .glb stores them (f32 corners, 8-bit
	// textures): the reference the reader must match, so the pass bar is
	// on max_f32, not on the format's own precision.
	let rounded: Vec<Part> = if reloaded.is_some() { scene::rounded(&shown)? } else { Vec::new() };
	let rounded_shown: Vec<&Part> = rounded.iter().collect();
	let rendering = Instant::now();
	let mut taken = 0;
	for (at, job) in jobs.iter().enumerate() {
		let mine = match claims.as_mut() {
			Some(claims) => claims.mine(at),
			None => review.share.map_or(true, |(index, count)| at % count == index - 1),
		};
		if !mine {
			continue;
		}
		taken += 1;
		for shot in job {
			progress::say(&format!("rendering {} of {} parts", shot.file, shown.len()));
			let started = Instant::now();
			let frame = draw_shot(&shown, shot);
			let direct = started.elapsed().as_secs_f64();
			save_shot(dir, &shown, shot, &frame)?;
			progress::total(&format!("TIMING render {}: drawn in {direct:.1}s, {:.1}s with its save", shot.file, started.elapsed().as_secs_f64()));
			if reloaded.is_none() {
				continue;
			}
			let started = Instant::now();
			let again = draw_shot(&reloaded_shown, shot);
			let from_glb = started.elapsed().as_secs_f64();
			let (max, mean, over2) = difference(&frame.pixels, &again.pixels);
			let (max_f32, mean_f32, over2_f32) = difference(&draw_shot(&rounded_shown, shot).pixels, &again.pixels);
			eprintln!("GLB_CHECK {} max={max} mean={mean:.3} over2={over2} max_f32={max_f32} mean_f32={mean_f32:.3} over2_f32={over2_f32} direct={direct:.2} glb={from_glb:.2}", shot.file);
		}
	}
	progress::total(&format!("TIMING renders: {taken} of {} jobs made here, {:.1}s with the waits to claim", jobs.len(), rendering.elapsed().as_secs_f64()));
	if let Some(wanted) = shown_clip {
		let clips = clips.borrow();
		let clip = clips.iter().find(|c| c.name == wanted).ok_or(format!("no clip {wanted}"))?;
		// Frame the rest pose once, so the camera holds still while it moves.
		let mut low = [f64::MAX; 3];
		let mut high = [f64::MIN; 3];
		for part in &shown {
			for corner in part.mesh.borrow().triangles().iter().flatten() {
				for axis in 0..3 {
					low[axis] = low[axis].min(corner.position[axis]);
					high[axis] = high[axis].max(corner.position[axis]);
				}
			}
		}
		let center = [0, 1, 2].map(|a| (low[a] + high[a]) / 2.0);
		let radius = (0..3).map(|a| high[a] - low[a]).fold(0.0, f64::max) * 0.6;
		let frames = dir.join(format!("clip_{wanted}"));
		std::fs::create_dir_all(&frames).map_err(|e| e.to_string())?;
		for frame in 0..clip.frames() {
			let skin = clip.skin(&bones, frame as f64 / anim::FPS);
			let data = render::render_posed(&shown, &skin, &render::View { size, spin: 0.0, focus: Some((center, radius)), eye: None, ..Default::default() });
			write_png(&frames.join(format!("{frame:04}.png")), size, &data).map_err(|e| e.to_string())?;
		}
	}
	eprintln!("{name}: {} parts, script {:.2?}, total {:.2?}", parts.len(), scripted, started.elapsed());
	if std::env::var("MODELKIT_PROFILE").is_ok_and(|v| v == "1") {
		// The plugins' layer timings (plugin.rs).
		for (label, seconds) in plugin::profile_layers() {
			eprintln!("  {label}: {seconds:.2}s");
		}
		// The stage totals again, on stdout: build-model.sh shows the script's
		// output after the progress lines, and a build machine keeps only the
		// end of a log, so said on stderr alone they would be cut away.
		for line in progress::totals() {
			println!("{line}");
		}
		let layers: Vec<String> = plugin::profile_layers().iter().map(|(label, seconds)| format!("{label} {seconds:.1}s")).collect();
		println!("TIMING {name}: {} parts, total {:.1}s; {}", parts.len(), started.elapsed().as_secs_f64(), layers.join(", "));
	}
	Ok(())
}

// Open Cloud takes at most 20 MB per upload; stay a little under.
const CHUNK_LIMIT: usize = 19_000_000;

// Writes chunks/<Name>_<tag>NN.glb, each small enough to upload, and
// chunks/<Name>Chunks.luau listing them with their anchor parts, in Roblox
// coordinates (Y up), for the Studio placer (framework/studio/PlaceMap.luau).
// A shard's tag (S3_) keeps its files and keys apart from the other shards'.
fn write_chunks(dir: &Path, name: &str, tag: &str, parts: &[Part], rigged: bool) -> Result<(), String> {
	if rigged {
		return Err("--chunks is for layouts; a rigged model can't be split".into());
	}
	let out = dir.join("chunks");
	if out.exists() {
		std::fs::remove_dir_all(&out).map_err(|e| e.to_string())?;
	}
	std::fs::create_dir_all(&out).map_err(|e| e.to_string())?;
	let chunks = glb::write_chunks(parts, CHUNK_LIMIT);
	let mut manifest = format!("--!strict\n-- Generated by modelkit --chunks for {name}: one entry per uploaded chunk,\n-- with two anchor parts and where their middles stand (studs, Y up).\nreturn {{\n");
	for (n, chunk) in chunks.iter().enumerate() {
		if chunk.glb.len() > CHUNK_LIMIT {
			return Err(format!("chunk {} is {} bytes even alone; a single part is over the upload limit", n + 1, chunk.glb.len()));
		}
		let file = format!("{name}_{tag}{:02}.glb", n + 1);
		std::fs::write(out.join(&file), &chunk.glb).map_err(|e| e.to_string())?;
		let anchors: Vec<String> = chunk
			.anchors
			.iter()
			.map(|(part, p)| format!("{{ name = \"{part}\", position = Vector3.new({}, {}, {}) }}", p[0], p[1], p[2]))
			.collect();
		manifest.push_str(&format!(
			"\t{{ key = \"{name}{tag}{:02}\", file = \"{file}\", parts = {}, anchors = {{ {} }} }},\n",
			n + 1,
			chunk.parts,
			anchors.join(", ")
		));
		progress::say(&format!("chunk {file}: {} parts, {:.1} MB", chunk.parts, chunk.glb.len() as f64 / 1e6));
	}
	manifest.push_str("}\n");
	std::fs::write(out.join(format!("{name}Chunks.luau")), manifest).map_err(|e| e.to_string())?;
	Ok(())
}
