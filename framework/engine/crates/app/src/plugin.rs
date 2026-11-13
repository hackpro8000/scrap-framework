// The plugin registry. A game's engine binary lists its plugins; each one
// registers what it adds to the host, in that order (never link order), before
// the host reads the command line or makes the Lua state. The hooks are plain
// function pointers, so the registry is one process-wide value that the Lua
// methods can reach (handles.rs).

use std::sync::OnceLock;

use mlua::{Lua, MultiValue};

use crate::MeshHandle;

// A compiled-in extension of the engine.
pub trait Plugin {
	// A short stable name, such as the crate's.
	fn id(&self) -> &'static str;
	// Raised when the plugin changes what it builds.
	fn version(&self) -> u32;
	// Adds the plugin's hooks.
	fn register(&self, registry: &mut Registry);
}

// mesh:<name>(...), called with the arguments as the script passed them.
pub type MeshMethod = fn(&Lua, &MeshHandle, MultiValue) -> mlua::Result<MultiValue>;

// A command-line flag: called with the argument after it (None when it comes
// last) whenever the flag is given. Flags nobody knows are ignored.
pub type FlagHook = fn(Option<&str>);

// Extends model.cached's key with what the plugin's settings change in a build.
pub type CacheKeyHook = fn(String) -> String;

// The roughness a part exports with when it has no roughness map.
pub type RoughnessHook = fn() -> f64;

// Time spent per layer, as (label, seconds), for MODELKIT_PROFILE=1.
pub type ProfileHook = fn() -> Vec<(&'static str, f64)>;

#[derive(Default)]
pub struct Registry {
	mesh_methods: Vec<(&'static str, MeshMethod)>,
	flags: Vec<(&'static str, FlagHook)>,
	cache_keys: Vec<CacheKeyHook>,
	roughness: Option<RoughnessHook>,
	profiles: Vec<ProfileHook>,
}

impl Registry {
	pub fn mesh_method(&mut self, name: &'static str, method: MeshMethod) {
		self.mesh_methods.push((name, method));
	}

	pub fn flag(&mut self, name: &'static str, apply: FlagHook) {
		self.flags.push((name, apply));
	}

	pub fn cache_key(&mut self, extend: CacheKeyHook) {
		self.cache_keys.push(extend);
	}

	// One value: the last plugin to set it wins.
	pub fn export_roughness(&mut self, roughness: RoughnessHook) {
		self.roughness = Some(roughness);
	}

	pub fn profile(&mut self, layers: ProfileHook) {
		self.profiles.push(layers);
	}
}

static REGISTRY: OnceLock<Registry> = OnceLock::new();

pub(crate) fn install(plugins: &[Box<dyn Plugin>]) {
	let mut registry = Registry::default();
	for plugin in plugins {
		plugin.register(&mut registry);
	}
	let _ = REGISTRY.set(registry);
}

fn registry() -> &'static Registry {
	REGISTRY.get_or_init(Registry::default)
}

pub(crate) fn mesh_methods() -> &'static [(&'static str, MeshMethod)] {
	&registry().mesh_methods
}

pub(crate) fn apply_flags(args: &[String]) {
	for &(name, apply) in &registry().flags {
		if let Some(at) = args.iter().position(|a| a == name) {
			apply(args.get(at + 1).map(String::as_str));
		}
	}
}

pub(crate) fn cache_key(key: String) -> String {
	registry().cache_keys.iter().fold(key, |key, extend| extend(key))
}

// Fully rough unless a plugin says otherwise.
pub(crate) fn export_roughness() -> f64 {
	registry().roughness.map_or(1.0, |roughness| roughness())
}

pub(crate) fn profile_layers() -> Vec<(&'static str, f64)> {
	registry().profiles.iter().flat_map(|layers| layers()).collect()
}
