# framework

The part of a game that is shared between games. A game holds an exact copy
of one release here and **never edits it**. Changes are made in the framework
repository and come back with `framework/scripts/framework-update.sh`
(planned).

| Folder | Holds |
|---|---|
| `engine/` | `modelkit`, the Rust engine that builds, paints and bakes models from Luau scripts |
| `modelcheck/` | model checks: floating parts, clipping, plan differences (run with Lune) |
| `uikit/` | the UI painter (Rust) |
| `studio/` | Studio command-bar scripts that place models and maps |
| `hive/` | the machine hive: the hub (`hive/hub/`) and the machine agent (`hive/agent/`) |
| `scripts/` | pipeline, build-machine and agent-team scripts |
| `docs/` | process docs: the model pipeline and critic rules (`framework/docs/art/`), design notes (`framework/docs/plans/`) |

Rules for everything in this folder:

- Name no game, repository, account, model or layout. Game names and numbers
  come from the game's `game.toml`, read through `scripts/lib/game.sh` (Bash)
  and `hive/game_settings.py` (Python).
- Game files (`art/src`, `art/models`, `src/`, caches, results) live under
  the game's root, never here.
- No look of its own. A game's look lives in its `art/style/` and
  `art/plugins/` (planned).

Planned: a `VERSION` file, release marks (safe, look-changing,
plugin-breaking), `framework/scripts/framework-check.sh`, and an engine split
into a small kernel and plugins.
