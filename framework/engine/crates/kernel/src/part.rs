// The model's shared data: a Part (one mesh with its painted texture) and a
// Bone (one rig joint). Scripts build them, and export, rendering, scene
// reading and animation all read them, so they live here rather than in main.

use std::cell::RefCell;
use std::rc::Rc;

use crate::image::Image;
use crate::mesh::Mesh;
use crate::skin::Skin;

#[derive(Clone)]
pub struct Part {
	pub name: String,
	pub group: Option<String>,
	pub preview: bool,
	// Glow strength, like SurfaceAppearance.EmissiveStrength; 0 doesn't glow.
	pub emissive: f32,
	pub mesh: Rc<RefCell<Mesh>>,
	pub image: Rc<RefCell<Image>>,
	// Rigid skin: the one bone the whole part follows.
	pub bone: Option<usize>,
	// Soft skin: each vertex follows its own bones (skin.rs). A part has a
	// bone or a skin, never both.
	pub skin: Option<Rc<Skin>>,
}

// A rig joint. A rigidly skinned part follows one bone whole; a softly
// skinned part's vertices each follow their own (skin.rs).
pub struct Bone {
	pub name: String,
	pub parent: Option<usize>,
	pub head: [f64; 3],
}
