// Soft skin in the .glb: a softly skinned part's per-vertex JOINTS_0 and
// WEIGHTS_0 as glb::write stores them, and the way back for scene::read. The
// weights themselves are worked out in the kernel (kernel/src/skin.rs).

use std::collections::HashMap;
use std::rc::Rc;

use modelkit_kernel::skin::{key, Influences, Skin, MOST_INFLUENCES};

use crate::mesh::Corner;
use crate::Bone;

// glTF component types for JOINTS_0.
const BYTES: u32 = 5121;
const SHORTS: u32 = 5123;

// A soft part's joints (four per corner: bytes, or shorts past 256 bones),
// their glTF component type, and its weights (four floats per corner).
// Influences come strongest first; unused ones are joint 0 at weight 0.
pub fn streams(skin: &Skin, corners: &[Corner], bones: &[Bone]) -> (Vec<u8>, u32, Vec<u8>) {
	let component = if bones.len() > 256 { SHORTS } else { BYTES };
	let mut joints = Vec::new();
	let mut weights = Vec::new();
	for corner in corners {
		// Only a vertex the weights never saw has none; it stays with bone 0.
		let influences = skin.influences(corner.position, bones).unwrap_or([(0, 1.0), (0, 0.0), (0, 0.0), (0, 0.0)]);
		for (bone, weight) in influences {
			if component == SHORTS {
				joints.extend((bone as u16).to_le_bytes());
			} else {
				joints.push(bone as u8);
			}
			weights.extend(weight.to_le_bytes());
		}
	}
	(joints, component, weights)
}

// A skinned part read back: rigid (its one bone) when every corner follows
// the same bone alone, as glb::write stores a rigid part, else soft with each
// corner's influences. `joints` and `weights` hold four per corner.
pub fn read_back(corners: &[Corner], joints: &[usize], weights: &[f32]) -> Result<(Option<usize>, Option<Rc<Skin>>), String> {
	if joints.len() < corners.len() * MOST_INFLUENCES || weights.len() < corners.len() * MOST_INFLUENCES {
		return Err("joints and weights don't line up with the vertices".into());
	}
	let mut map = HashMap::new();
	let mut one_bone: Option<usize> = None;
	let mut rigid = true;
	for (at, corner) in corners.iter().enumerate() {
		let slots = at * MOST_INFLUENCES..(at + 1) * MOST_INFLUENCES;
		let mut pairs: Vec<(usize, f32)> = joints[slots.clone()].iter().copied().zip(weights[slots].iter().copied()).filter(|&(_, w)| w > 0.0).collect();
		pairs.sort_by(|a, b| b.1.total_cmp(&a.1));
		let alone = match pairs[..] {
			[(bone, weight)] if weight == 1.0 => Some(bone),
			_ => None,
		};
		rigid = rigid && alone.is_some() && (one_bone.is_none() || one_bone == alone);
		one_bone = one_bone.or(alone);
		let mut influences: Influences = [(0, 0.0); MOST_INFLUENCES];
		for (slot, pair) in influences.iter_mut().zip(pairs) {
			*slot = pair;
		}
		map.entry(key(corner.position)).or_insert(influences);
	}
	if rigid {
		return Ok((one_bone, None));
	}
	Ok((None, Some(Rc::new(Skin::Weights(map)))))
}

#[cfg(test)]
mod tests {
	use std::cell::RefCell;

	use crate::image::Image;
	use crate::mesh::{Face, Mesh};
	use crate::{glb, scene, Part};

	use super::*;

	// A unit cube on the origin, z up, one quad per side.
	fn cube() -> Mesh {
		let mut mesh = Mesh::new();
		for z in [0.0, 1.0] {
			for y in [-0.5, 0.5] {
				for x in [-0.5, 0.5] {
					mesh.positions.push([x, y, z]);
				}
			}
		}
		for verts in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]] {
			mesh.faces.push(Face { verts: verts.to_vec(), uvs: None });
		}
		mesh.smooth_angle = 0.0;
		mesh
	}

	fn corner_bones() -> Vec<Bone> {
		cube().positions.iter().enumerate().map(|(i, &head)| Bone { name: format!("Corner{i}"), parent: None, head }).collect()
	}

	fn part(name: &str, bone: Option<usize>, skin: Option<Skin>) -> Part {
		Part {
			name: name.into(),
			group: None,
			preview: true,
			emissive: 0.0,
			mesh: Rc::new(RefCell::new(cube())),
			image: Rc::new(RefCell::new(Image::new(4, 4, [0.5; 3]))),
			bone,
			skin: skin.map(Rc::new),
		}
	}

	// The skin as the build hands it to export: weighed over its mesh.
	fn weighed(part: Part, bones: &[Bone]) -> Part {
		let skin = part.skin.as_ref().map(|skin| Rc::new(skin.weigh(&part.mesh.borrow(), bones)));
		Part { skin, ..part }
	}

	#[test]
	fn soft_skin_comes_back_from_the_glb() {
		let bones = corner_bones();
		// A middle bone too, so smooth weights blend more than one corner.
		let mut bones = bones;
		bones.push(Bone { name: "Middle".into(), parent: None, head: [0.0, 0.0, 0.5] });
		let parts = vec![
			weighed(part("Nearest", None, Some(Skin::Rule { smooth: false, bones: vec![] })), &bones),
			weighed(part("Smooth", None, Some(Skin::Rule { smooth: true, bones: vec![8, 0, 7] })), &bones),
			part("Rigid", Some(3), None),
		];
		let file = glb::write(&parts, &bones, &[]);
		let scene = scene::read(file).unwrap();
		assert_eq!(scene.bones.len(), 9);
		for (written, read) in parts.iter().zip(&scene.parts) {
			assert_eq!(written.bone, read.bone, "part {}", written.name);
			assert_eq!(written.skin.is_some(), read.skin.is_some(), "part {}", written.name);
			let (Some(before), Some(after)) = (&written.skin, &read.skin) else {
				continue;
			};
			for &position in &written.mesh.borrow().positions {
				let want = before.influences(position, &bones).unwrap();
				assert_eq!(after.influences(position, &[]), Some(want), "part {} at {position:?}", written.name);
				assert!((want.iter().map(|(_, w)| w).sum::<f32>() - 1.0).abs() < 1e-6);
			}
		}
		// Each nearest corner follows its own corner bone.
		let nearest = scene.parts[0].skin.as_ref().unwrap();
		for (index, &position) in cube().positions.iter().enumerate() {
			assert_eq!(nearest.influences(position, &[]).unwrap()[0], (index, 1.0));
		}
	}

	#[test]
	fn rigid_parts_write_as_before() {
		let bones = corner_bones();
		let file = glb::write(&[part("Rigid", Some(2), None)], &bones, &[]);
		let text = String::from_utf8_lossy(&file);
		assert!(text.contains("\"componentType\":5121,\"count\":24,\"type\":\"VEC4\""));
		let scene = scene::read(file).unwrap();
		assert_eq!(scene.parts[0].bone, Some(2));
		assert!(scene.parts[0].skin.is_none());
	}
}
