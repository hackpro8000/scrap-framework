// Kernel: the shared low-level pieces every plugin uses. A seeded hash for
// repeatable noise, the texel a bake paints, sRGB/linear colour conversion,
// the batched thread pool that runs work over texels, and the box test for
// which meshes are near enough to shade each other. It depends on nothing in
// the engine but the mesh types.

use std::sync::atomic::{AtomicUsize, Ordering};

use crate::mesh::{Mesh, Vec3};

pub fn hash(mut x: u32) -> f64 {
	x ^= x >> 16;
	x = x.wrapping_mul(0x7feb_352d);
	x ^= x >> 15;
	x = x.wrapping_mul(0x846c_a68b);
	x ^= x >> 16;
	x as f64 / u32::MAX as f64
}

// The surface point painted by one texel.
#[derive(Clone, Copy)]
pub struct Texel {
	pub pixel: usize,
	pub position: Vec3,
	pub normal: Vec3,
	pub face_normal: Vec3,
	// The surface directions the texture's U and V run along, unit length, so
	// a tilt in the world turns into a tangent-space normal.
	pub tangent: Vec3,
	pub bitangent: Vec3,
}

pub fn to_linear(c: f32) -> f64 {
	let c = c as f64;
	if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
}

pub(crate) fn to_srgb(c: f64) -> f32 {
	let c = c.clamp(0.0, 1.0);
	(if c <= 0.003_130_8 { c * 12.92 } else { 1.055 * c.powf(1.0 / 2.4) - 0.055 }) as f32
}

// Texels a bake thread takes at a time. Threads take the next batch as they
// finish one, so a thread that drew slow texels (along creases) doesn't leave
// the others idle while it catches up.
const BATCH: usize = 1024;

pub fn parallel<I: Sync, T: Send, F: Fn(&I) -> T + Sync>(texels: &[I], work: F) -> Vec<T> {
	parallel_with(texels, || (), |_, texel| work(texel))
}

// Like parallel, with scratch state each thread keeps from texel to texel.
pub(crate) fn parallel_with<I: Sync, T: Send, S, N: Fn() -> S + Sync, F: Fn(&mut S, &I) -> T + Sync>(texels: &[I], new: N, work: F) -> Vec<T> {
	let threads = std::thread::available_parallelism().map_or(4, |n| n.get());
	let batches: Vec<&[I]> = texels.chunks(BATCH).collect();
	let next = AtomicUsize::new(0);
	let mut done: Vec<(usize, Vec<T>)> = std::thread::scope(|scope| {
		let handles: Vec<_> = (0..threads.min(batches.len()))
			.map(|_| {
				scope.spawn(|| {
					let mut mine = Vec::new();
					let mut state = new();
					loop {
						let at = next.fetch_add(1, Ordering::Relaxed);
						let Some(batch) = batches.get(at) else { break };
						mine.push((at, batch.iter().map(|texel| work(&mut state, texel)).collect::<Vec<T>>()));
					}
					mine
				})
			})
			.collect();
		handles.into_iter().flat_map(|h| h.join().expect("bake thread")).collect()
	});
	done.sort_unstable_by_key(|(at, _)| *at);
	done.into_iter().flat_map(|(_, values)| values).collect()
}

// Whether another mesh is close enough to a mesh's surfaces to shade or be
// shaded by them. The paint only reads occluders this close.
pub fn within_reach(own: &Mesh, other: &Mesh, reach: f64) -> bool {
	let (own_low, own_high) = bounds(own);
	let (low, high) = bounds(other);
	let gap = (0..3).map(|k| (low[k] - own_high[k]).max(own_low[k] - high[k]).max(0.0)).fold(0.0, |sum, g| sum + g * g);
	gap <= reach * reach
}

// Corners of the box round a mesh's positions.
pub(crate) fn bounds(mesh: &Mesh) -> (Vec3, Vec3) {
	let mut low = [f64::MAX; 3];
	let mut high = [f64::MIN; 3];
	for p in &mesh.positions {
		for k in 0..3 {
			low[k] = low[k].min(p[k]);
			high[k] = high[k].max(p[k]);
		}
	}
	(low, high)
}
