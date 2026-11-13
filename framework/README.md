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

## Releases and updates

`VERSION` names the release this copy is; `MANIFEST` holds the sha256 of
every file in it; `CHANGELOG.md` lists releases, each marked safe,
look-changing or plugin-breaking.

| Command | Where | Does |
|---|---|---|
| `scripts/framework-release.sh <version> <kind> "<summary>"` | framework repository | writes VERSION, MANIFEST and a changelog entry; prints the commit and `framework-v<version>` tag commands (runs none) |
| `scripts/framework-check.sh` | any game | `FRAMEWORK OK <version>`, or lists changed, missing and extra files |
| `scripts/framework-update.sh <version> [--from <url or path>] [--force]` | a game | replaces this folder with that release (source: `--from` or `framework_source` in `game.toml`), keeps build folders, prints the changes; never commits |
| `scripts/init-game.sh <name> "<Display Name>" <owner/repository>` | a fresh copy of the template | names the game in `game.toml`, `default.project.json`, `wally.toml`; removes `proof/` |
| `scripts/test-framework-copy.sh` | anywhere | end-to-end test of the above in a temporary folder |
