//! GPU compute passes for the shading bake (contact creases, the coat and the
//! wear over it), with their WGSL shaders. Every pass returns None without a
//! usable GPU, so callers fall back to the CPU. Depends only on the kernel.

pub mod gpu;
