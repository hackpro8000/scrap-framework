# Template framework: design spec

Draft, started 2026-11-13. Nothing here is built yet. Sections marked OPEN are not decided.

## Goal

A template repository built on Scrap Heist's framework, so a new game starts with the same game code skeleton, modelling pipeline, build machines and agent team, and none of Scrap Heist's content or look.

## Decided

- **Contents:** all four layers go in the template: the game code skeleton, the modelling pipeline, the build machines, and the agent team and rules.
- **Repository:** public on GitHub for now (changed from private on 2026-11-13 so GitHub's machines are free without limit), fresh history (no Scrap Heist history). Everything pushed is visible to anyone: no tokens, addresses or account details in it.
- **Scrap Heist is not changed.** All the work happens in this folder, `scrap-framework`, a sibling of `scrap-heist`. Scrap Heist is read from, never written to.
- **Working remote:** the repository `hackpro8000/scrap-framework` exists from the start, so the engine can be compiled and proven on machines (nothing compiles on the user's computer). Publishing is the later step of declaring it ready.
- **No art style in the pipeline.** Like Blender, the pipeline is not built for one style; a style is defined by how the pipeline is used. Style lives in the top layer, owned by each game.
- **Plugins in Rust.** Where a game needs engine-level speed, it adds a plugin written in Rust. The pipeline must be extensible and easy to adapt.
- **Plugins can do whatever the engine can.** There is no reduced plugin interface.
- **Current base features are plugins too.** The engine becomes a small kernel; meshes, baking, painting, rendering, file output and the rest are plugins on the same footing as a game's own.

- **The machine hive is its own entity.** The hub, the machine agents and the cloud workers form a separate system that knows nothing about models. The modelling pipeline talks to it through a base plugin.

## The hive and the pipeline

- **Hive:** connects machines, keeps the roster, hands out units of work, re-deals units from lost machines, relays small messages, updates itself, reports status and alerts. A unit is "run this command on this commit and report back". It has no notion of models, bakes, previews or layouts.
- **Pipeline's hive plugin:** turns a model build into units, decides share weights, runs the bake swap between machines, collects previews and results. Everything model-shaped that the hub does today moves here: preview jobs, bake claims, the "all bakes pushed" signal, the engine compile-and-share unit, the Roblox uploader, the `ServerMap` layout default.
- Without the hive plugin the pipeline still builds on one machine. With another plugin, the hive could serve other work (tests, UI painting).
- OPEN: whether the hive lives in its own repository or as its own top-level folder in the template (item 9), and the exact interface between the two (what a unit is, how a plugin on the hub side adds model-specific coordination such as bake claims).

## Sharing updates across projects (decided 2026-11-13: pinned copy)

A GitHub template only copies files when a project is created, so it cannot carry later updates. A git submodule was considered and ruled out by the user.

- Everything shared lives in one folder, `framework/`, with a `framework/VERSION` file. A game holds an exact copy of one release and never edits it.
- `framework/scripts/framework-update.sh <release>` replaces the folder with that release from this repository, compiles on the machines and runs the proof.
- A check (`framework/scripts/framework-check.sh`) fails when `framework/` differs from the release it claims to be.
- Each release is marked safe, look-changing, or plugin-breaking. A game updates when it chooses.
- This repository is both the framework's source and the template: its root is laid out as a new game, so "Use this template" on GitHub gives a working starter.

## Repository layout

| Path | Owner | Holds |
|---|---|---|
| `framework/` | shared, pinned | engine (kernel and base plugins), model checks, UI painter, shared model helpers, pipeline and hive scripts, the hive, process docs |
| `game.toml` | game | every name the framework needs: game name, repository, default layout, cache folder, upload display name, character size, camera height, texture caps |
| `art/style/`, `art/plugins/`, `art/src/` | game | style kit, the game's Rust plugins, model sources |
| `engine/` | game | the small binary crate that lists which plugins this game's engine is built from |
| `src/`, `tests/` | game | game code, starting from the skeleton (copied, not shared) |
| `CLAUDE.md`, `.claude/`, `docs/team/` | game | agent team and rules (copied, not shared) |
| `proof/scrap-heist/` | this repository only | Scrap Heist's style plugins, kit and sample models, plus a frozen copy of its engine, used to prove the split. Removed from a new game by `framework/scripts/init-game.sh`. |

## Decided while building (reversible; say if you want any changed)

- Work happens on the branch `build`. When the template is ready, `main` is made as one fresh commit, so the published history has no Scrap Heist content in it.
- The proof runs on GitHub machines in this repository (`.github/workflows/proof.yml`): it compiles the frozen engine and the current one and compares sample models byte for byte with `bake-proof.sh`.
- Game code skeleton and agent rules are copied into a new game, not shared through `framework/`.
- The hive starts as `framework/hive/` with no dependencies on the rest, so it can become its own repository later.
- Scrap Heist's style plugins stay in `proof/scrap-heist/`, outside what a new game receives.
- The template's default look is a plain kit: flat colour and simple edge shading, one example model.

## Layers

| Layer | Language | Holds |
|---|---|---|
| Kernel | Rust | Only what plugins need in order to exist: the plugin registry, shared data types, the Luau script host, command dispatch. |
| Base plugins | Rust | Today's engine features with no look of their own: meshes and UVs, baking, free-form painting, rendering, file output, caching. Shipped in the template. |
| Style plugins | Rust | Effects that carry a look and need engine speed. Scrap Heist's rust and grime coats, hand-painting and brush stamps become its style plugins. |
| Style kit | Luau | Palette, finish recipes, wear amounts, stamp images, the critic's style rules. Calls base and style plugins. |
| Models | Luau | Each item, built from the kit. |

A new game can work at any level: write a kit in Luau only, reuse an existing style plugin with its own kit, or write a plugin.

## Plugins

- Compiled in: each plugin is a Rust crate in a Cargo workspace, built together with the kernel into one engine binary per game. No loadable libraries (fragile across compiler versions) and no WebAssembly (slower, no GPU).
- Plugins may depend on other plugins and offer hook points of their own (a paint effect adds a layer inside the bake plugin's loop).
- The engine fingerprint that decides when machines recompile covers the kernel and every plugin folder.
- Each plugin's fingerprint enters the bake cache key, so a plugin change never leaves stale bakes.
- Accepted trade: with full reach, a plugin is tied to the internals of the plugins it builds on and may need changes when they change.

## Where the look lives today (audit, 2026-11-13)

- **Engine:** rust, grime, dust and highlight colours fixed in `coat.rs`, `hand.rs`, `bake.rs`; rock, wood and metal presets in `hand.rs`; 12 stamp images compiled into `brush.rs`; stroke, bristle, taper and wear constants in `bake.rs` with copies in the shaders; preview backdrop, glow, lighting and field of view in `render.rs`.
- **Shared model code:** look amounts and rust colours in `art/src/common.luau`; the palette in `art/src/rarity.luau`, glued into every build by `scripts/assemble-model.sh`; presets in `art/src/shared/HandFinish.luau`; paint recipes in the island and sky modules.
- **Critic and docs:** a few lines only (the settled-look list, "scrap looks like scrap", "our cartoony style", `critic-settled.md`), plus game numbers such as the 4 × 5.5 character capsule and the camera height.
- **Already neutral:** shape helpers, `chunkedPart`, mesh editing, `tools/modelcheck`, the model scripts, the review process.

## What is Scrap Heist-specific outside the pipeline (audit, 2026-11-13)

From headers, requires, exports and searches; most function and script bodies were not read.

- **Gameplay (all stays out):** combat; saves and currency; inventory; trading; belt and capsules; junkrots; yard and build mode; raiding; rebirth; storm rounds; shop; daily rewards; leaderboard; atmosphere and effects; admin and showcase; settings; HUD and prompts. Plus the ToyKit UI art and palette, the config tables, animations, asset table and map chunks.
- **General game code (the skeleton's core):** `Util/Boot` (`init()` then `start()`), `Signal`, `Trove`, `RateLimiter`, `Validate`, `Format`, `Net`, `Security/RemoteGuard`, `UI/Windows`, the test runner and engine fakes, tooling config.
- **Mixed game code (about 25 files, general mechanism with game content):** profile saving, settings, toasts, prompts, the HUD menu grid, the UI kit components, debug commands, inventory rules, round clock, grid maths.
- **Tools:** `tools/uikit` (UI painter) is general, though its build output is committed; `tools/coordinator` is general apart from names; `tools/studio` placement scripts are a general pattern with this game's model and folder names; `tools/pacing` is this game's economy simulator.
- **Scripts and workflows:** about 30 scripts are general as they stand. About 30 more are general except for names: the default layout `ServerMap`, the repository `hackpro8000/scrap-heist`, cache and config folders under `~/.cache/scrap-heist` and `~/.config/scrap-heist`, host names starting `scrap-`, the cloud environment name, "Scrap Heist" as the upload display name, a default Roblox creator id in `tools/coordinator/uploader.py`, and sample model lists. `paint-clouds.py` and `paint-sky.py` are game art.
- **Content:** `art/ui`, `art/concepts`, `art/sounds`, `art/archive`, `previews` are all game content.
- **Docs:** `docs/team/*` and the agent-team plans are general; `docs/systems`, `docs/testing`, the gameplay and map plans, bugs and clips are the game's.
- **Agent setup:** the roles in `.claude/agents` and the hooks are general; `CLAUDE.md`, `AGENTS.md` and `.claude/settings.json` are general with a few lines naming this game, its roadmap and `ServerMap`.

## How it gets built

- The engine and pipeline are copied from Scrap Heist into this folder and split here. Scrap Heist keeps running on its current engine.
- Proof for every slice: Scrap Heist's models, built with this folder's engine, give previews byte-identical to the ones Scrap Heist's own engine gives. The first pass moves code and does not rewrite behaviour.
- For that proof this folder needs Scrap Heist's style plugins, kit and some model sources while the work is under way. Where they end up afterwards is open (item 3).
- Scrap Heist's model sources are used as they are; the kit translates today's keys (`rust`, `hand`, `handTune`).

## Kernel and plugin boundary (proposed, from a read-only mapping on 2026-11-13)

Reasoned from reading the code; nothing was compiled. Some function bodies were only searched, not read (`shade_pass` in `bake.rs`, the second half of `render.rs`, the bodies of `hand.rs` and `marks.rs`).

**Kernel.** Shared data types (mesh, image, part, bone, texel), the deterministic primitives every plugin uses (hash, parallel loops, colour-space conversion), the plugin registry, the Luau host, the command-line skeleton and run-phase order, the layer cache store and its key hasher, progress output and the deferred job queue.

**Base plugins** (template): mesh operations; unwrap and texels (with free-form `paint`); GPU pass service; rig and animation; glTF in and out; render; part cache; build sharing between machines; texture output.

**Scrap Heist style plugins:** paint (brushes, marks, hand-painting, coats, stamps); shading (`paintShading`, the highlight, shadow, normal, roughness and metalness layers); preview look (backdrop, glow, field of view, light).

**Hook points:** script functions and mesh methods; command-line flags; run phases; bake layers (how one plugin adds a layer inside another's loop); combine and map output; option parsing; output writers; preview shading; GPU passes. Plugins are registered in an explicit ordered list, so the output never depends on link order.

**Findings that shape the plan:**

- The engine's modules depend on each other in circles (brush, marks, hand and coat on each other; bake with each of them, with the cache and with the GPU code). Crates cannot, so the circles are broken first, inside the current single crate.
- Moves alone make the engine plugin-shaped, but the bake loop itself is written around Scrap Heist's shading. A neutral bake loop needs two behaviour-preserving rewrites after the moves: a generic layer loop, and splitting the `paintShading` options per plugin. Until those are done, "no style in the base" is not yet true.
- Some constants exist twice, in Rust and in the shaders. Each shader moves with its Rust twin; removing the duplication is optional and later.
- Cache keys stay unchanged through the moves so warm machines keep their bakes. Plugin identity enters the key in one late slice, with a one-time full invalidation.
- The scripts that decide whether the engine needs recompiling fingerprint `src`, `Cargo.toml` and `Cargo.lock` only. A workspace breaks that silently, so they change in the same slice that creates it.
- Not confirmed: whether the build machines bake on the GPU or CPU path (they give slightly different numbers, so the proof must cover the one in use), and how much a workspace lengthens the compile.

**Slice order (15):** 1-3 break the circles; 4 creates the workspace and kernel crate; 5 moves the leaf plugins (animation, glTF, render, GPU), which can go to separate workers; 6-7 move paint and split the bake; 8-10 add the registry and move script functions, flags, phases and the preview look behind hooks; 11 extracts the combine step; 12-13 are the two rewrites; 14 puts plugin identity in the cache key; 15 (optional) generates shader constants.

## OPEN

1. **Kernel contents.** The mapping keeps the layer cache store, progress output and job queue in the kernel. Confirm, or make them plugins too.
8. **Machines for this repository.** How compiles and proof builds run here: GitHub machines only, or the hub and cloud machines set up for it too.
7. **Scope of the other three layers.** What "skeleton" means for game code, and which agent rules are general, are not yet specified.
