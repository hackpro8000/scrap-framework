// The model's shared data: a Part (one mesh with its painted texture) and a
// Bone (one rig joint). Scripts build them, and export, rendering, scene
// reading and animation all read them, so they live here rather than in main.

use std::cell::RefCell;
use std::rc::Rc;

use crate::image::Image;
use crate::mesh::Mesh;

#[derive(Clone)]
pub struct Part {
	pub name: String,
	pub group: Option<String>,
	pub preview: bool,
	// Glow strength, like SurfaceAppearance.EmissiveStrength; 0 doesn't glow.
	pub emissive: f32,
	pub mesh: Rc<RefCell<Mesh>>,
	pub image: Rc<RefCell<Image>>,
	pub bone: Option<usize>,
}

// A rig joint. Parts follow exactly one bone each (rigid skin), so moving a
// bone in Studio moves its parts whole.
pub struct Bone {
	pub name: String,
	pub parent: Option<usize>,
	pub head: [f64; 3],
}
