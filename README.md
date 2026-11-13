# Game framework and starter

This repository is two things at once:

- **A game framework** for Roblox games, shared between games as a pinned
  copy in `framework/`. It holds the model pipeline (a Rust engine that builds,
  paints and bakes models from Luau scripts, which each game extends with its
  own compiled-in plugins), the model helpers, the model checks, the UI
  painter, the machine hive that spreads builds over many machines, and the
  process docs.
- **A starter game.** The root is laid out as a new game: a game code
  skeleton, the agent team and its rules, its own engine package, and a plain
  style kit with one example model in `art/`.

## Layout

| Path | Owner | Holds |
|---|---|---|
| `framework/` | shared, pinned | engine base crates, model helpers, model checks, UI painter, Studio scripts, pipeline and hive scripts, the hive, process docs |
| `game.toml` | game | the names and numbers the framework reads: game name, repository, default layout, character size, camera height, texture limits, where framework releases come from |
| `Cargo.toml`, `engine/` | game | the game's engine: a Cargo workspace whose `engine` package builds the `modelkit` binary from the framework's crates and the plugins listed in `engine/src/main.rs` |
| `art/style/` | game | the style kit (palette, amounts, `setLook()`, `finishParts()`), the critic's style rules, and `assembly.txt`, the order the kit and the framework's helpers are joined in |
| `art/plugins/` | game | the game's Rust plugins, one crate per folder (none in the starter; see `framework/docs/plugins.md`) |
| `art/src/`, `art/models/` | game | model sources, and the models generated from them |
| `src/`, `tests/` | game | game code and tests, starting from the skeleton (copied, not shared) |
| `CLAUDE.md`, `AGENTS.md`, `.claude/`, `docs/team/` | game | agent team and rules (copied, not shared) |
| `ROADMAP.md` | game | the game's roadmap, a template to fill in |
| `proof/` | this repository only | the test game used to prove engine and helper changes |

## Starting a new game

1. Use this repository as a template on GitHub.
2. Run `framework/scripts/init-game.sh <name> "<Display Name>" <owner/repository>`.
   It fills in `game.toml`, `default.project.json` and `wally.toml`, and
   removes `proof/`.
3. Fill in `ROADMAP.md`, then follow `CLAUDE.md`.

`.github/workflows/new-game.yml` proves these steps on a GitHub machine
(`framework/scripts/test-new-game.sh --build`): it makes a new game from the
committed tree, runs its tests and builds its example model with its own
engine.

## How updates arrive

A game holds an exact copy of one framework release in `framework/` and never
edits it. `framework/scripts/framework-update.sh <release>` replaces the
folder with that release. `framework/scripts/framework-check.sh` fails when
the folder differs from the release it claims to be; until the first release
there is no `framework/MANIFEST`, and it says so. A game updates when it
chooses. Framework changes are made in this repository.

## The proof game

`proof/` holds the game the framework was taken from, kept as a test. Its
models are built with this repository's engine and compared byte for byte
with a recorded baseline (`framework/scripts/proof.sh`, run by
`.github/workflows/proof.yml`). Every change to the engine crates or the model
helpers is proven this way. A new game does not receive it.

## Checks on GitHub

| Workflow | Runs |
|---|---|
| `ci.yml` | on every push to `build` and `main`: Luau tests, the hive's queue tests, the pinned-copy commands, script syntax, and that `framework/` names no game (leftovers in `framework/.names-allowed`) |
| `proof.yml` | by hand: compiles the proof game's engine and compares its models with the baseline |
| `starter.yml` | by hand: builds the root game's models and keeps their previews |
| `new-game.yml` | on push to `build`, or by hand: makes and builds a new game |

## More

- `framework/README.md`: what is in the shared folder.
- `framework/docs/art/pipeline.md`: how models are made.
- `framework/art/lib/README.md`: what a style kit must define.
- `framework/docs/plugins.md`: how to write an engine plugin.
- `framework/docs/plans/multi-machine.md`: how the build machines work.
- `docs/team/core.md`: how the agent team works.
