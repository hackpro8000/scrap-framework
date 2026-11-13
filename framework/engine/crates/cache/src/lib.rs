//! The layer cache: baked paint layers stored on disk under a key hashed from
//! everything that shapes them, shared between machines. Depends only on the
//! kernel.

pub mod cache;
