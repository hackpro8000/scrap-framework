//! The mechanical front of a texture bake: unwrapping, finding the surface
//! point behind each texel, dilating over seams, and the geometry lookups the
//! shading layers build on. Makes no look decisions. Depends only on the kernel.

pub mod texels;
