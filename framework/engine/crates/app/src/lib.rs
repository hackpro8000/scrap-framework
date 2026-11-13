// modelkit: builds a model from its Luau script. This crate is the engine's
// host; a game's engine binary (<game>/engine) calls run() with the plugins it
// is built from, and their flags and script methods join the ones below.
//
//   modelkit art/models/<Name>                   build <Name>.glb and preview.png
//   modelkit art/models/<Name> --turntable 48
//                                                also write turntable frames
//   modelkit art/models/<Name> --size 2048
//                                                render previews at 2048px square
//   modelkit art/models/<Rig> --clip Idle
//                                                also write the clip's frames
//   modelkit art/models/<Name> --parts
//                                                also write parts.png (each part in its
//                                                own flat colour), parts.txt (the colour
//                                                legend, also on stdout) and cells.txt
//                                                (the parts in each cell of a 6×6 grid
//                                                over the preview, A1 at the top left)
//   modelkit art/models/<Name> --view front --view top --grid 1
//                                                also write square-on side views,
//                                                face_front.png ... (and face_front_parts.png
//                                                with --parts), with stud lines every
//                                                --grid studs
//   modelkit art/models/<Name> --eye ... --renders 3/8
//                                                render only this machine's share of the
//                                                renders (every 8th, from the 3rd, in a
//                                                fixed order), under their usual names
//   modelkit art/models/<Layout> --chunks
//                                                also split the GLB into uploadable
//                                                chunks (see write_chunks)
//   modelkit art/models/<Layout> --chunks --shard 3/8
//                                                build only this machine's share of
//                                                a layout's placements (SHARD_INDEX
//                                                and SHARD_COUNT in the script), with
//                                                chunks tagged S3 so shards don't clash
//   modelkit art/models/<Name> --view front --glb-check
//                                                also read the .glb back and render every
//                                                view from it too, logging GLB_CHECK <file>
//                                                max= mean= direct= glb= per view
//   modelkit --render a.glb b.glb --out DIR --eye ... --view front
//                                                render-only: the same views and file names
//                                                as a build, from saved .glb files (no
//                                                script, no bake); --views FILE instead
//                                                takes one view per line (see read_views)
//
// The script (model.luau) builds meshes and paints textures through the API
// (api.rs, handles.rs); this engine does the heavy, generic work (triangulating,
// export, rendering) so scripts change without a recompile.

mod api;
mod glb;
mod handles;
mod model;
mod plugin;
mod scene;
mod shots;
pub mod work;

use std::path::{Path, PathBuf};

// The kernel crate's modules, named at the root so `crate::mesh::...` and the
// like keep resolving in every module of this crate.
use modelkit_kernel::{image, mesh, part, progress};
// The plugin crates' modules, named at the root the same way.
use modelkit_anim::anim;
use modelkit_cache::cache;
use modelkit_render::{detail, render};
use modelkit_texels::texels;

pub use handles::{ImageHandle, MeshHandle};
pub use part::{Bone, Part};
pub use plugin::{MeshMethod, Plugin, Registry};
// Plugins write their script methods with the host's own mlua.
pub use mlua;

use shots::{read_views, render_saved, review_jobs, Review};

const DEFAULT_PREVIEW_SIZE: usize = 768;

// A flag's INDEX/COUNT value, or None when the flag isn't given.
fn share_flag(args: &[String], flag: &str) -> Option<(usize, usize)> {
	let at = args.iter().position(|a| a == flag)?;
	let parsed = args.get(at + 1).and_then(|s| s.split_once('/')).and_then(|(i, n)| Some((i.parse::<usize>().ok()?, n.parse::<usize>().ok()?)));
	match parsed {
		Some((index, count)) if index >= 1 && index <= count => Some((index, count)),
		_ => {
			eprintln!("error: {flag} needs INDEX/COUNT with 1 <= INDEX <= COUNT, like 3/8");
			std::process::exit(2);
		}
	}
}

// The engine's main: registers the plugins in the order given, then reads the
// command line and builds (or renders) as it asks.
pub fn run(plugins: Vec<Box<dyn Plugin>>) {
	plugin::install(&plugins);
	let args: Vec<String> = std::env::args().skip(1).collect();
	let Some(dir) = args.first() else {
		eprintln!("usage: modelkit <model folder> [--turntable FRAMES] [--size PIXELS] [--closeup X,Y,Z,RADIUS,SPIN]... [--eye EX,EY,EZ,TX,TY,TZ]... [--clip NAME] [--parts] [--view SIDE]... [--grid STUDS] [--chunks] [--shard INDEX/COUNT] [--renders INDEX/COUNT] [--share-bakes] [--work-port PORT] [--glb-check]");
		eprintln!("       modelkit --render <a.glb> [<b.glb>...] --out DIR [view flags as above | --views FILE] [--renders INDEX/COUNT]");
		std::process::exit(2);
	};
	let turntable = match args.iter().position(|a| a == "--turntable") {
		Some(at) => args.get(at + 1).and_then(|n| n.parse().ok()).unwrap_or(48),
		None => 0,
	};
	let size = match args.iter().position(|a| a == "--size") {
		Some(at) => args.get(at + 1).and_then(|n| n.parse().ok()).unwrap_or(DEFAULT_PREVIEW_SIZE),
		None => DEFAULT_PREVIEW_SIZE,
	};
	let mut closeups = Vec::new();
	for (at, _) in args.iter().enumerate().filter(|(_, a)| *a == "--closeup") {
		let numbers: Vec<f64> = args.get(at + 1).map_or(vec![], |list| list.split(',').filter_map(|n| n.parse().ok()).collect());
		let [x, y, z, radius, spin] = numbers[..] else {
			eprintln!("--closeup takes X,Y,Z,RADIUS,SPIN");
			std::process::exit(2);
		};
		closeups.push((x, y, z, radius, spin));
	}
	let mut eyes = Vec::new();
	for (at, _) in args.iter().enumerate().filter(|(_, a)| *a == "--eye") {
		let numbers: Vec<f64> = args.get(at + 1).map_or(vec![], |list| list.split(',').filter_map(|n| n.parse().ok()).collect());
		let [ex, ey, ez, tx, ty, tz] = numbers[..] else {
			eprintln!("--eye takes EX,EY,EZ,TX,TY,TZ");
			std::process::exit(2);
		};
		eyes.push(([ex, ey, ez], [tx, ty, tz]));
	}
	let clip = args.iter().position(|a| a == "--clip").and_then(|at| args.get(at + 1));
	// --preview builds texels at half the density, for quick looks, and with
	// --eye bakes far parts at less detail still.
	let preview = args.iter().any(|a| a == "--preview");
	// --max-detail raises the density so far that every part's texture hits
	// the 1024 cap, for previews judged up close on the build machines.
	let max_detail = args.iter().any(|a| a == "--max-detail");
	let texel_scale = if max_detail { 64.0 } else if preview { 0.5 } else { 1.0 };
	let detail_eyes = if preview { eyes.clone() } else { Vec::new() };
	let chunks = args.iter().any(|a| a == "--chunks");
	let shard = share_flag(&args, "--shard");
	let mut sides = Vec::new();
	for (at, _) in args.iter().enumerate().filter(|(_, a)| *a == "--view") {
		let Some(side) = args.get(at + 1).and_then(|name| render::Side::parse(name)) else {
			eprintln!("--view takes front, back, left, right, top or bottom");
			std::process::exit(2);
		};
		sides.push(side);
	}
	let grid = args.iter().position(|a| a == "--grid").and_then(|at| args.get(at + 1)).and_then(|n| n.parse().ok()).filter(|&n: &f64| n > 0.0);
	let share = share_flag(&args, "--renders");
	if args.iter().any(|a| a == "--share-bakes") {
		cache::set_sharing();
	}
	let work_port = args.iter().position(|a| a == "--work-port").and_then(|at| args.get(at + 1)).and_then(|p| p.parse().ok());
	// The plugins' own flags, in registration order (plugin.rs).
	plugin::apply_flags(&args);
	// --no-cache builds as if nothing were cached and writes nothing, like
	// MODELKIT_NO_CACHE=1, for timing a cold build.
	if args.iter().any(|a| a == "--no-cache") {
		std::env::set_var("MODELKIT_NO_CACHE", "1");
	}
	let review = Review { parts: args.iter().any(|a| a == "--parts"), sides, grid, share, work_port, glb_check: args.iter().any(|a| a == "--glb-check") };
	if dir == "--render" {
		// The .glb files come first, up to the first flag.
		let files: Vec<PathBuf> = args[1..].iter().take_while(|a| !a.starts_with("--")).map(PathBuf::from).collect();
		let Some(out) = args.iter().position(|a| a == "--out").and_then(|at| args.get(at + 1)) else {
			eprintln!("--render needs --out DIR");
			std::process::exit(2);
		};
		if files.is_empty() {
			eprintln!("--render needs at least one .glb");
			std::process::exit(2);
		}
		let jobs = match args.iter().position(|a| a == "--views").and_then(|at| args.get(at + 1)) {
			Some(list) => read_views(Path::new(list), size),
			None => Ok(review_jobs(size, turntable, &closeups, &eyes, &review, true)),
		};
		if let Err(error) = jobs.and_then(|jobs| render_saved(&files, Path::new(out), &jobs, share)) {
			eprintln!("error: {error}");
			std::process::exit(1);
		}
		return;
	}
	if let Err(error) = model::run(Path::new(dir), turntable, size, &closeups, &eyes, clip.map(|c| c.as_str()), texel_scale, &detail_eyes, chunks, shard, &review) {
		eprintln!("error: {error}");
		std::process::exit(1);
	}
}
