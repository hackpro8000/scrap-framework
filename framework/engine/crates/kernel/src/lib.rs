//! The engine's kernel: the shared model data (mesh, image, part and bone)
//! and the low-level helpers every plugin uses (hashing, colour conversion,
//! the texel thread pool, progress lines). It depends on no other engine crate.

pub mod image;
pub mod kernel;
pub mod mesh;
pub mod part;
pub mod progress;
