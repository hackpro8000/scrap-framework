// Soft skin: a part whose vertices each follow their own bones, blended by
// weight, where rigid skin (Part::bone) moves the whole part with one bone.
// model.part's `skin` option gives the rule (Skin::Rule); once the script has
// ended, the build weighs every vertex by where it sits (Skin::weigh), and
// export, rendering and scene reading all use those weights.

use std::collections::HashMap;

use crate::mesh::{dot, sub, Mesh, Vec3};
use crate::part::Bone;

// The most bones one vertex follows, as glTF's JOINTS_0 holds them.
pub const MOST_INFLUENCES: usize = 4;
// Influences lighter than this are dropped, and the rest renormalised.
pub const LEAST_WEIGHT: f64 = 0.02;
// A vertex this close (squared studs) to a bone's head follows that bone alone.
const ON_HEAD: f64 = 1e-12;

// A vertex's (bone, weight) pairs, strongest first, weights summing to 1.
// Unused slots are (0, 0.0), as glTF stores them.
pub type Influences = [(usize, f32); MOST_INFLUENCES];

pub enum Skin {
	// As model.part asked: `smooth` blends up to four nearest bones, otherwise
	// each vertex follows its nearest bone alone. Only `bones` are candidates;
	// empty means every bone.
	Rule { smooth: bool, bones: Vec<usize> },
	// Each vertex's influences, keyed by its position rounded to f32 (as a
	// .glb stores it), so a part read back from its file keys the same way.
	Weights(HashMap<[u32; 3], Influences>),
}

// The key a position's influences are kept under.
pub fn key(position: Vec3) -> [u32; 3] {
	position.map(|x| (x as f32).to_bits())
}

impl Skin {
	// A vertex's influences: weighed by the rule over `bones`, or as stored.
	// None when there is nothing to follow (a rule with no bones, or a
	// position the stored weights don't hold); such a vertex stays put.
	pub fn influences(&self, position: Vec3, bones: &[Bone]) -> Option<Influences> {
		match self {
			Skin::Rule { smooth, bones: candidates } => weigh(position, bones, candidates, *smooth),
			Skin::Weights(map) => map.get(&key(position)).copied(),
		}
	}

	// The weights of every vertex of `mesh` under this skin.
	pub fn weigh(&self, mesh: &Mesh, bones: &[Bone]) -> Skin {
		let mut map = HashMap::new();
		for &position in &mesh.positions {
			if let Some(influences) = self.influences(position, bones) {
				map.entry(key(position)).or_insert(influences);
			}
		}
		Skin::Weights(map)
	}
}

// A vertex's influences under a rule: the nearest candidate's head alone, or
// (smooth) up to four nearest heads weighted by inverse squared distance.
pub fn weigh(position: Vec3, bones: &[Bone], candidates: &[usize], smooth: bool) -> Option<Influences> {
	let all: Vec<usize>;
	let candidates = if candidates.is_empty() {
		all = (0..bones.len()).collect();
		&all
	} else {
		candidates
	};
	// (squared distance, bone), nearest first; ties keep the candidates' order.
	let mut near: Vec<(f64, usize)> = candidates.iter().filter(|&&b| b < bones.len()).map(|&b| (dot(sub(position, bones[b].head), sub(position, bones[b].head)), b)).collect();
	near.sort_by(|a, b| a.0.total_cmp(&b.0));
	let &(closest, nearest) = near.first()?;
	let mut out = [(0, 0.0); MOST_INFLUENCES];
	if !smooth || closest < ON_HEAD {
		out[0] = (nearest, 1.0);
		return Some(out);
	}
	let mut pairs: Vec<(usize, f64)> = near.iter().take(MOST_INFLUENCES).map(|&(d2, b)| (b, 1.0 / d2)).collect();
	normalise(&mut pairs);
	pairs.retain(|&(_, w)| w >= LEAST_WEIGHT);
	normalise(&mut pairs);
	for (slot, (bone, weight)) in out.iter_mut().zip(pairs) {
		*slot = (bone, weight as f32);
	}
	Some(out)
}

fn normalise(pairs: &mut [(usize, f64)]) {
	let total: f64 = pairs.iter().map(|(_, w)| w).sum();
	for (_, w) in pairs.iter_mut() {
		*w /= total;
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn rig() -> Vec<Bone> {
		[[0.0, 0.0, 0.0], [2.0, 0.0, 0.0], [0.0, 2.0, 0.0], [0.0, 0.0, 2.0], [5.0, 5.0, 5.0]]
			.iter()
			.enumerate()
			.map(|(i, &head)| Bone { name: format!("B{i}"), parent: None, head })
			.collect()
	}

	fn total(influences: &Influences) -> f32 {
		influences.iter().map(|(_, w)| w).sum()
	}

	#[test]
	fn nearest_picks_the_nearest_head() {
		let bones = rig();
		let found = weigh([1.6, 0.1, 0.0], &bones, &[], false).unwrap();
		assert_eq!(found, [(1, 1.0), (0, 0.0), (0, 0.0), (0, 0.0)]);
		let found = weigh([0.2, 1.5, 0.3], &bones, &[], false).unwrap();
		assert_eq!(found[0], (2, 1.0));
	}

	#[test]
	fn smooth_sums_to_one_over_at_most_four() {
		let bones = rig();
		let found = weigh([0.7, 0.6, 0.5], &bones, &[], true).unwrap();
		assert!((total(&found) - 1.0).abs() < 1e-6);
		assert!(found.iter().all(|&(_, w)| w == 0.0 || f64::from(w) >= LEAST_WEIGHT));
		assert!(found.windows(2).all(|pair| pair[0].1 >= pair[1].1), "strongest first");
		// The far bone (4) is the fifth candidate, so it is never among the four.
		assert!(found.iter().all(|&(b, w)| b != 4 || w == 0.0));
	}

	#[test]
	fn smooth_on_a_head_follows_that_bone_alone() {
		let bones = rig();
		assert_eq!(weigh([2.0, 0.0, 0.0], &bones, &[], true).unwrap(), [(1, 1.0), (0, 0.0), (0, 0.0), (0, 0.0)]);
	}

	#[test]
	fn only_the_listed_bones_are_candidates() {
		let bones = rig();
		// Nearest to bone 1, but only bones 3 and 4 may hold it.
		let found = weigh([1.9, 0.0, 0.0], &bones, &[3, 4], true).unwrap();
		assert!(found.iter().all(|&(b, w)| w == 0.0 || b == 3 || b == 4));
		assert!((total(&found) - 1.0).abs() < 1e-6);
		assert_eq!(weigh([1.9, 0.0, 0.0], &bones, &[4], false).unwrap()[0], (4, 1.0));
	}

	#[test]
	fn light_influences_are_dropped() {
		let bones = rig();
		// Right beside bone 0: the others weigh far under 2%.
		let found = weigh([0.01, 0.0, 0.0], &bones, &[], true).unwrap();
		assert_eq!(found[0], (0, 1.0));
	}

	#[test]
	fn no_bones_weighs_nothing() {
		assert!(weigh([0.0; 3], &[], &[], true).is_none());
	}
}
