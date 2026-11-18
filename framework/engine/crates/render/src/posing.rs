// How a part moves in a posed render (a clip preview): not at all, whole with
// its one bone (rigid skin), or vertex by vertex by linear blend skinning
// over its weights (soft skin, kernel/src/skin.rs).

use modelkit_anim::anim::Pose;
use modelkit_kernel::mesh::{add, scale, Corner, Vec3};
use modelkit_kernel::part::Part;
use modelkit_kernel::skin::Skin;

#[derive(Clone, Copy)]
pub enum Posing<'a> {
	Still,
	Rigid(&'a Pose),
	// The part's weights and every bone's skinning transform.
	Soft(&'a Skin, &'a [Pose]),
}

impl<'a> Posing<'a> {
	// A part's posing under `skin` (one transform per bone; empty for the rest pose).
	pub fn of(part: &'a Part, skin: &'a [Pose]) -> Posing<'a> {
		if let Some(pose) = part.bone.and_then(|b| skin.get(b)) {
			return Posing::Rigid(pose);
		}
		match part.skin.as_deref() {
			Some(weights) if !skin.is_empty() => Posing::Soft(weights, skin),
			_ => Posing::Still,
		}
	}

	pub fn is_still(&self) -> bool {
		matches!(self, Posing::Still)
	}

	// Where a rest-pose position moves to.
	pub fn position(&self, p: Vec3) -> Vec3 {
		match *self {
			Posing::Still => p,
			Posing::Rigid(pose) => pose.apply(p),
			Posing::Soft(weights, poses) => {
				let Some(influences) = weights.influences(p, &[]) else {
					return p;
				};
				let mut moved = [0.0; 3];
				for (bone, weight) in influences {
					if weight > 0.0 {
						let pose = poses.get(bone).unwrap_or(&Pose::IDENTITY);
						moved = add(moved, scale(pose.apply(p), weight as f64));
					}
				}
				moved
			}
		}
	}

	// Moves a corner; a soft corner's normal turns with its strongest bone.
	pub fn corner(&self, corner: &mut Corner) {
		let turn = match *self {
			Posing::Still => return,
			Posing::Rigid(pose) => pose,
			Posing::Soft(weights, poses) => match weights.influences(corner.position, &[]) {
				Some(influences) => poses.get(influences[0].0).unwrap_or(&Pose::IDENTITY),
				None => return,
			},
		};
		corner.normal = turn.turn(corner.normal);
		corner.position = self.position(corner.position);
	}
}

#[cfg(test)]
mod tests {
	use std::cell::RefCell;
	use std::collections::HashMap;
	use std::rc::Rc;

	use modelkit_kernel::image::Image;
	use modelkit_kernel::mesh::Mesh;
	use modelkit_kernel::skin::key;

	use super::*;

	#[test]
	fn soft_vertices_blend_their_bones() {
		let p = [1.0, 0.0, 0.0];
		let weights = Skin::Weights(HashMap::from([(key(p), [(0, 0.25), (1, 0.75), (0, 0.0), (0, 0.0)])]));
		let part = Part {
			name: "Blob".into(),
			group: None,
			preview: true,
			emissive: 0.0,
			mesh: Rc::new(RefCell::new(Mesh::new())),
			image: Rc::new(RefCell::new(Image::new(1, 1, [1.0; 3]))),
			bone: None,
			skin: Some(Rc::new(weights)),
		};
		let poses = [Pose::IDENTITY, Pose { translation: [0.0, 4.0, 0.0], ..Pose::IDENTITY }];
		let posing = Posing::of(&part, &poses);
		assert_eq!(posing.position(p), [1.0, 3.0, 0.0]);
		// Not in the weights: stays put. The rest pose moves nothing.
		assert_eq!(posing.position([9.0, 9.0, 9.0]), [9.0, 9.0, 9.0]);
		assert!(Posing::of(&part, &[]).is_still());
	}
}
