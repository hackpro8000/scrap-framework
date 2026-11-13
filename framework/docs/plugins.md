# Writing an engine plugin

A game's model engine is the framework's host (`framework/engine/crates/app`, the `modelkit-app` crate) plus the plugins the game lists. A plugin is a Rust crate compiled into that one binary. There are no loadable libraries.

## Plugin or Luau kit

- Start with the Luau style kit (`art/style/`, contract in `framework/art/lib/README.md`). It needs no compile, and `mesh:paint` with a colour function covers flat colours, stripes, gradients and anything worked out per surface point.
- Write a plugin when Luau is too slow for the job (a pass over every texel of every part, a search through nearby geometry), when it needs the GPU, or when it needs what the script API does not expose (other meshes, the layer cache, the export settings).
- A plugin adds script methods and flags. The kit calls the methods, usually from `finishParts()`.

## Adding one

1. Make `art/plugins/my-style/Cargo.toml`. Depend only on the crates you use; all of them are in `framework/engine/crates/` (`app`, `kernel`, `texels`, `gpu`, `cache`, `render`, `anim`):
   ```toml
   [package]
   name = "my-style"
   version = "0.1.0"
   edition = "2021"

   [dependencies]
   modelkit-app = { path = "../../../framework/engine/crates/app" }
   modelkit-kernel = { path = "../../../framework/engine/crates/kernel" }
   modelkit-texels = { path = "../../../framework/engine/crates/texels" }
   ```
2. In the game's `Cargo.toml`, add `"art/plugins/*"` to `members` (it is left out until the first plugin exists, because a glob that matches nothing is an error).
3. In `engine/Cargo.toml`: `my-style = { path = "../art/plugins/my-style" }`.
4. In `engine/src/main.rs`: `modelkit_app::run(vec![my_style::plugin()]);`

The crate's `src/lib.rs`:

```rust
use modelkit_app::{Plugin, Registry};

struct MyStyle;

impl Plugin for MyStyle {
	fn id(&self) -> &'static str { "my-style" }
	fn version(&self) -> u32 { 1 }
	fn register(&self, registry: &mut Registry) {
		registry.mesh_method("paintBands", bands::paint_bands);
	}
}

pub fn plugin() -> Box<dyn Plugin> { Box::new(MyStyle) }
```

`run` calls every plugin's `register` once, in the order of the list in `main.rs` (never link order), before it reads the command line or makes the Lua state. The list order is the order hooks run in. The host does not read `id` or `version` yet.

## Hooks

Each hook is a plain function pointer (`framework/engine/crates/app/src/plugin.rs`), so a plugin keeps its settings in statics.

**Mesh methods.** `registry.mesh_method(name, f)`, with `f: fn(&Lua, &MeshHandle, MultiValue) -> mlua::Result<MultiValue>`. It becomes `mesh:<name>(...)` in model scripts, added after the host's own methods, and gets the arguments as the script passed them. Use the host's `mlua` (`modelkit_app::mlua`).

```rust
pub fn paint_bands(lua: &Lua, this: &MeshHandle, args: MultiValue) -> mlua::Result<MultiValue> {
	let (image, step) = <(AnyUserData, f64) as FromLuaMulti>::from_lua_multi(args, lua)?;
	let image = image.borrow::<ImageHandle>()?.0.clone();
	let mut image = image.borrow_mut();
	let (width, height) = (image.width, image.height);
	for t in texels::texels(&this.0.borrow(), width, height) {
		let dark = (t.position[2] / step).floor() as i64 % 2 == 0;
		image.pixels[t.pixel] = image.pixels[t.pixel].map(|c| if dark { c * 0.8 } else { c });
	}
	Ok(MultiValue::new())
}
```

**Flags.** `registry.flag(name, f)`, with `f: fn(Option<&str>)`. Called once, after the host has read its own flags and before the build, when the flag is on the command line, with the argument after it (`None` when it comes last). Flags no one registered are ignored.

```rust
static STEP: AtomicU64 = AtomicU64::new(0);
fn step_flag(value: Option<&str>) {
	let step: f64 = value.and_then(|v| v.parse().ok()).unwrap_or(1.0);
	STEP.store(step.to_bits(), Ordering::Relaxed);
}
```

**Cache keys.** `registry.cache_key(f)`, with `f: fn(String) -> String`. Called on the key of every `model.cached(key, build)`, after the host adds its preview suffix; each plugin extends the key in list order. Add only what changes the result, and return the key unchanged at the default so existing caches stay valid.

```rust
fn step_key(key: String) -> String {
	match STEP.load(Ordering::Relaxed) {
		0 => key,
		bits => format!("{key} ~bands{}", f64::from_bits(bits)),
	}
}
```

**Export roughness.** `registry.export_roughness(f)`, with `f: fn() -> f64`. The roughness a part exports with when it has no roughness map: the flat `<Part>_Roughness.png` and the `.glb` material's factor. One value; the last plugin to set it wins; without one it is 1.0 (fully rough).

```rust
registry.export_roughness(|| 0.8);
```

**Profile.** `registry.profile(f)`, with `f: fn() -> Vec<(&'static str, f64)>`, giving seconds per layer. Read at the end of a build when `MODELKIT_PROFILE=1`, printed one line per label on stderr and joined into the `TIMING` line.

```rust
static BANDS_MICROS: AtomicU64 = AtomicU64::new(0);
registry.profile(|| vec![("bands", BANDS_MICROS.load(Ordering::Relaxed) as f64 / 1e6)]);
```

## A worked example

The proof game (`proof/` in the framework repository) has two style plugins, `art/plugins/sh-paint` and `art/plugins/sh-shading`, listed in that order. `sh-shading/src/lib.rs` registers every hook kind: the `paintShading` method, the `--normals` and `--roughness` flags, the normal strength in cache keys, the export roughness and the bake's layer timings. `sh-shading/src/script.rs` reads the method's options table and hands the paint to the bake, deferred through `modelkit_app::work` when bakes are shared between machines. `sh-paint` registers nothing; it is a library the shading plugin calls.

## Compiling

Plugins are compiled on the build machines, never on your own computer. `framework/scripts/build-model.sh` fingerprints the base crates and the game's `Cargo.toml`, `Cargo.lock`, `engine/` and `art/plugins/`, and recompiles when any of them changes. `framework/scripts/engine-check.sh` compiles the working tree on a GitHub machine and prints the errors. A change to the base crates is proven on the proof game (`framework/scripts/proof.sh`, `.github/workflows/proof.yml`).

## Current limits

- There is no neutral bake loop in the base crates yet. The shading loop, the edge and crease fields and the layer logic live in the proof game's `sh-shading` plugin. A new style plugin starts from the base texel, unwrap and paint API (`modelkit-texels`, `mesh:paint`) or copies what it needs from that plugin.
- Plugin identity is not part of cache keys yet: changing a plugin's code leaves cached builds in place. Build cold (`--no-cache` or `MODELKIT_NO_CACHE=1`) to see a change.
- The base GPU crate (`framework/engine/crates/gpu`) still holds two shaders, `crease.wgsl` and `canvas.wgsl`, that belong to the proof game's shading plugin.
- A plugin can reach any public part of the crates it builds on, so it may need changes when they change. Releases that break plugins are marked plugin-breaking in `framework/CHANGELOG.md`.
