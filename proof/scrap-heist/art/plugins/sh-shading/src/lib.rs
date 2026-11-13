//! A style plugin: the shading bake. Edge highlights, contact shadows, the
//! soft highlight, and the combined colour, normal, roughness and metalness
//! layers, with every look constant. Depends on kernel, gpu, cache, texels,
//! render and the host (modelkit-app), and on sh-paint.
//!
//! It registers mesh:paintShading (script.rs), the --normals and --roughness
//! flags, the normal strength in model.cached keys, the roughness parts export
//! with, and the bake's layer timings.

pub mod bake;
mod script;

use std::sync::atomic::Ordering;

use modelkit_app::{Plugin, Registry};

struct Shading;

impl Plugin for Shading {
	fn id(&self) -> &'static str {
		"sh-shading"
	}

	fn version(&self) -> u32 {
		1
	}

	fn register(&self, registry: &mut Registry) {
		registry.mesh_method("paintShading", script::paint_shading_method);
		registry.flag("--normals", normals_flag);
		registry.flag("--roughness", roughness_flag);
		registry.cache_key(normal_key);
		registry.export_roughness(bake::roughness);
		registry.profile(layer_timings);
	}
}

pub fn plugin() -> Box<dyn Plugin> {
	Box::new(Shading)
}

// --normals STRENGTH bakes a normal map per part from the edge field the
// highlights come from; 1 tilts a sharp edge's rim 45 degrees.
fn normals_flag(value: Option<&str>) {
	let strength = value.and_then(|n| n.parse().ok()).unwrap_or(1.0);
	bake::set_normal_strength(strength);
}

// --roughness R exports every part at that roughness instead of fully
// rough, to see how the light takes a normal map.
fn roughness_flag(value: Option<&str>) {
	if let Some(value) = value.and_then(|n| n.parse().ok()) {
		bake::set_roughness(value);
	}
}

// A normal map is part of what was built, so it is part of the key.
fn normal_key(key: String) -> String {
	match bake::normal_strength() {
		Some(strength) => format!("{key} ~n{strength}"),
		None => key,
	}
}

// Seconds spent in each bake layer (MODELKIT_PROFILE=1).
fn layer_timings() -> Vec<(&'static str, f64)> {
	bake::PROFILE_LAYERS.iter().enumerate().map(|(layer, &label)| (label, bake::PROFILE[layer].load(Ordering::Relaxed) as f64 / 1e6)).collect()
}
