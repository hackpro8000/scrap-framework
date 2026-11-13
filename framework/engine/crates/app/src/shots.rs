// Review renders: which shots a build or a render-only run makes, in the fixed
// order machines share them by, how each is drawn and saved, and --views files.

use std::path::{Path, PathBuf};
use std::time::Instant;

use crate::{image, mesh, progress, render, scene, Part};

pub(crate) fn write_png(path: &Path, size: usize, data: &[u8]) -> std::io::Result<()> {
	std::fs::write(path, image::encode_render(size, size, data))
}

// A close-up: focus point x, y, z, framing radius, and camera spin in degrees.
pub(crate) type Closeup = (f64, f64, f64, f64, f64);

// Review renders: part colours, side views and their stud grid, and which
// share of all the renders this machine makes (--renders INDEX/COUNT).
pub(crate) struct Review {
	pub(crate) parts: bool,
	pub(crate) sides: Vec<render::Side>,
	pub(crate) grid: Option<f64>,
	pub(crate) share: Option<(usize, usize)>,
	pub(crate) work_port: Option<u16>,
	// --glb-check: render every view again from the written .glb and log how far apart they come.
	pub(crate) glb_check: bool,
}

// One picture a review render writes: its file under the output folder and
// where the camera stands for it.
pub(crate) struct Shot {
	pub(crate) file: String,
	size: usize,
	spin: f64,
	focus: Option<(mesh::Vec3, f64)>,
	eye: Option<(mesh::Vec3, mesh::Vec3)>,
	side: Option<render::Side>,
	parts: bool,
	grid: Option<f64>,
	// parts.png also writes its colour legend (parts.txt, and on stdout) and cells.txt.
	legend: bool,
}

impl Shot {
	fn new(file: String, size: usize) -> Shot {
		Shot { file, size, spin: 0.0, focus: None, eye: None, side: None, parts: false, grid: None, legend: false }
	}

	fn view(&self) -> render::View {
		render::View { size: self.size, spin: self.spin, focus: self.focus, eye: self.eye, side: self.side, parts: self.parts, grid: self.grid, ..Default::default() }
	}

	// Whether a ball at `centre` with `radius` can show in this shot; only an
	// eye camera leaves anything out, the orthographic views frame it all.
	fn sees(&self, centre: mesh::Vec3, radius: f64) -> bool {
		match self.eye {
			Some((eye, target)) => render::in_view(eye, target, centre, radius),
			None => true,
		}
	}
}

// The review renders as jobs in a fixed order (machines sharing the renders
// count on it): preview, parts, side views (each with its parts view),
// turntable frames, close-ups, eyes. A job's shots are claimed together.
// Without `whole` (a shard, a scattered share of a layout nobody looks at
// whole) the preview and parts view are left out.
pub(crate) fn review_jobs(size: usize, turntable: usize, closeups: &[Closeup], eyes: &[(mesh::Vec3, mesh::Vec3)], review: &Review, whole: bool) -> Vec<Vec<Shot>> {
	let mut jobs = Vec::new();
	if whole {
		jobs.push(vec![Shot::new("preview.png".into(), size)]);
	}
	if whole && review.parts {
		jobs.push(vec![Shot { parts: true, legend: true, ..Shot::new("parts.png".into(), size) }]);
	}
	for &side in &review.sides {
		let mut job = vec![Shot { side: Some(side), grid: review.grid, ..Shot::new(format!("face_{}.png", side.name()), size) }];
		if review.parts {
			job.push(Shot { side: Some(side), grid: review.grid, parts: true, ..Shot::new(format!("face_{}_parts.png", side.name()), size) });
		}
		jobs.push(job);
	}
	for frame in 0..turntable {
		let spin = frame as f64 / turntable as f64 * std::f64::consts::TAU;
		jobs.push(vec![Shot { spin, ..Shot::new(format!("turntable/{frame:04}.png"), size) }]);
	}
	for (n, &(x, y, z, radius, degrees)) in closeups.iter().enumerate() {
		jobs.push(vec![Shot { spin: degrees.to_radians(), focus: Some(([x, y, z], radius)), ..Shot::new(format!("closeup_{}.png", n + 1), size) }]);
	}
	for (n, &(eye, target)) in eyes.iter().enumerate() {
		jobs.push(vec![Shot { eye: Some((eye, target)), ..Shot::new(format!("eye_{}.png", n + 1), size) }]);
	}
	jobs
}

// Draws a shot; parts.png keeps which part shows where, for cells.txt.
pub(crate) fn draw_shot(parts: &[&Part], shot: &Shot) -> render::Frame {
	if shot.legend {
		return render::render_frame(parts, &shot.view());
	}
	render::Frame { pixels: render::render(parts, &shot.view()), owner: Vec::new(), owner_size: 0 }
}

pub(crate) fn save_shot(out: &Path, parts: &[&Part], shot: &Shot, frame: &render::Frame) -> Result<(), String> {
	let path = out.join(&shot.file);
	if let Some(folder) = path.parent() {
		std::fs::create_dir_all(folder).map_err(|e| e.to_string())?;
	}
	write_png(&path, shot.size, &frame.pixels).map_err(|e| format!("{}: {e}", path.display()))?;
	if !shot.legend {
		return Ok(());
	}
	let legend = render::legend(parts);
	print!("{legend}");
	std::fs::write(out.join("parts.txt"), legend).map_err(|e| e.to_string())?;
	std::fs::write(out.join("cells.txt"), render::cells(frame, parts, 6)).map_err(|e| e.to_string())
}

// Two RGB pictures apart: the largest difference in any channel (0-255), the
// mean one, and how many pixels differ by more than 2 in some channel.
pub(crate) fn difference(a: &[u8], b: &[u8]) -> (u8, f64, usize) {
	if a.len() != b.len() || a.is_empty() {
		return (255, 255.0, a.len().max(b.len()) / 3);
	}
	let mut largest = 0;
	let mut sum = 0u64;
	let mut over2 = 0;
	for (x, y) in a.chunks_exact(3).zip(b.chunks_exact(3)) {
		let gap = (0..3).map(|c| x[c].abs_diff(y[c])).max().unwrap_or(0);
		largest = largest.max(gap);
		over2 += (gap > 2) as usize;
		sum += (0..3).map(|c| x[c].abs_diff(y[c]) as u64).sum::<u64>();
	}
	(largest, sum as f64 / a.len() as f64, over2)
}

// Reads a .glb back and decodes only the textures of parts some shot can see.
pub(crate) fn load_for(bytes: Vec<u8>, jobs: &[Vec<Shot>]) -> Result<scene::Scene, String> {
	let started = Instant::now();
	let scene = scene::read(bytes)?;
	let wanted = |part: usize| {
		let (centre, radius) = scene.bounds[part];
		scene.parts[part].preview && jobs.iter().flatten().any(|shot| shot.sees(centre, radius))
	};
	let decoded = scene.load_textures(wanted)?;
	progress::say(&format!("read {} parts back, {decoded} textures decoded, in {:.2?}", scene.parts.len(), started.elapsed()));
	Ok(scene)
}

// Render-only: reads each .glb once and renders every shot from memory into `out`.
pub(crate) fn render_saved(files: &[PathBuf], out: &Path, jobs: &[Vec<Shot>], share: Option<(usize, usize)>) -> Result<(), String> {
	let started = Instant::now();
	let mut scenes = Vec::new();
	for file in files {
		let bytes = std::fs::read(file).map_err(|e| format!("{}: {e}", file.display()))?;
		scenes.push(load_for(bytes, jobs).map_err(|e| format!("{}: {e}", file.display()))?);
	}
	let shown: Vec<&Part> = scenes.iter().flat_map(|scene| scene.parts.iter()).filter(|p| p.preview).collect();
	std::fs::create_dir_all(out).map_err(|e| e.to_string())?;
	for (at, job) in jobs.iter().enumerate() {
		if share.is_some_and(|(index, count)| at % count != index - 1) {
			continue;
		}
		for shot in job {
			progress::say(&format!("rendering {} of {} parts", shot.file, shown.len()));
			save_shot(out, &shown, shot, &draw_shot(&shown, shot))?;
		}
	}
	eprintln!("rendered {} files, {} parts, total {:.2?}", files.len(), shown.len(), started.elapsed());
	Ok(())
}

// A --views file: one shot per line, its flags then its output file, like
//   --eye 0,-40,6,0,0,4 eye_gate.png
//   --closeup 0,0,4,6,30 --size 1024 closeup_door.png
//   --view front --grid 1 --parts face_front_parts.png
//   --spin 90 side_quarter.png
// --size defaults to the command line's; blank lines and # lines are skipped.
pub(crate) fn read_views(path: &Path, size: usize) -> Result<Vec<Vec<Shot>>, String> {
	let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
	let mut jobs = Vec::new();
	for (number, line) in text.lines().enumerate() {
		let line = line.trim();
		if line.is_empty() || line.starts_with('#') {
			continue;
		}
		let shot = parse_shot(line, size).map_err(|e| format!("{} line {}: {e}", path.display(), number + 1))?;
		jobs.push(vec![shot]);
	}
	Ok(jobs)
}

fn parse_shot(line: &str, size: usize) -> Result<Shot, String> {
	let words: Vec<&str> = line.split_whitespace().collect();
	let Some((&file, flags)) = words.split_last() else {
		return Err("empty view".into());
	};
	if file.starts_with("--") {
		return Err("a view line ends with its output file name".into());
	}
	let mut shot = Shot::new(file.to_string(), size);
	let mut at = 0;
	while at < flags.len() {
		let flag = flags[at];
		if flag == "--parts" {
			shot.parts = true;
			at += 1;
			continue;
		}
		let value = *flags.get(at + 1).ok_or(format!("{flag} needs a value"))?;
		let numbers: Vec<f64> = value.split(',').filter_map(|n| n.parse().ok()).collect();
		match flag {
			"--size" => shot.size = value.parse().map_err(|_| format!("--size takes PIXELS, not {value}"))?,
			"--spin" => {
				let [degrees] = numbers[..] else {
					return Err("--spin takes DEGREES".into());
				};
				shot.spin = degrees.to_radians();
			}
			"--eye" => {
				let [ex, ey, ez, tx, ty, tz] = numbers[..] else {
					return Err("--eye takes EX,EY,EZ,TX,TY,TZ".into());
				};
				shot.eye = Some(([ex, ey, ez], [tx, ty, tz]));
			}
			"--closeup" => {
				let [x, y, z, radius, spin] = numbers[..] else {
					return Err("--closeup takes X,Y,Z,RADIUS,SPIN".into());
				};
				shot.focus = Some(([x, y, z], radius));
				shot.spin = spin.to_radians();
			}
			"--view" => shot.side = Some(render::Side::parse(value).ok_or("--view takes front, back, left, right, top or bottom")?),
			"--grid" => shot.grid = Some(value.parse().ok().filter(|&n: &f64| n > 0.0).ok_or("--grid takes STUDS above 0")?),
			_ => return Err(format!("unknown view flag {flag}")),
		}
		at += 2;
	}
	Ok(shot)
}
