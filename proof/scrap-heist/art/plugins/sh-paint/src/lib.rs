//! A style plugin: the hand-painted coat. Brush strokes and their stamps, the
//! moving-hand marks, the hand-laid coat and the coat and wear layers. The
//! modules use each other, so they are one crate. Depends on kernel, gpu and
//! the host (modelkit-app, for the plugin trait).
//!
//! It registers no hook of its own: sh-shading's paintShading drives the coat.

pub mod brush;
pub mod coat;
pub mod hand;
pub mod marks;

use modelkit_app::{Plugin, Registry};

struct Paint;

impl Plugin for Paint {
	fn id(&self) -> &'static str {
		"sh-paint"
	}

	fn version(&self) -> u32 {
		1
	}

	fn register(&self, _registry: &mut Registry) {}
}

pub fn plugin() -> Box<dyn Plugin> {
	Box::new(Paint)
}
