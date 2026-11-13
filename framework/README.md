# framework

The part of a game that is shared between games. A game holds an exact copy
of one release here and **never edits it**. Changes are made in the framework
repository and come back with `framework/scripts/framework-update.sh`.

| Folder | Holds |
|---|---|
| `engine/` | the model engine's base crates in `engine/crates/`: `app` (the host, `modelkit-app`, with the plugin registry and the script API), `kernel`, `gpu`, `anim`, `render`, `cache` and `texels`. Each game builds its own `modelkit` binary from them and its plugins (`docs/plugins.md`) |
| `art/lib/` | the model helpers every model starts with: math, shapes, warp, `part()`, `chunkedPart()`. `art/lib/README.md` is the contract with a game's style kit |
| `art/shared/` | Luau files a model can include (`-- include: <Name>`): Edit Mesh and the warped mesh |
| `modelcheck/` | model checks: floating parts, clipping, plan differences (run with Lune) |
| `uikit/` | the UI painter (Rust) |
| `studio/` | Studio command-bar scripts that place models and maps |
| `hive/` | the machine hive: the hub (`hive/hub/`) and the machine agent (`hive/agent/`) |
| `scripts/` | pipeline, build-machine, agent-team and pinned-copy scripts |
| `tests/` | specs for the model helpers |
| `docs/` | process docs: the model pipeline and critic rules (`docs/art/`), writing plugins (`docs/plugins.md`), design notes (`docs/plans/`) |

Rules for everything in this folder:

- Name no game, repository, account, model or layout. Game names and numbers
  come from the game's `game.toml`, read through `scripts/lib/game.sh` (Bash)
  and `hive/game_settings.py` (Python). The `names` job in
  `.github/workflows/ci.yml` checks it; the few leftovers still allowed are
  listed in `.names-allowed`, each with its reason.
- Game files (`art/src`, `art/models`, `src/`, caches, results) live under
  the game's root, never here.
- No look of its own. A game's look lives in its `art/style/` and
  `art/plugins/`.

An engine or helper change is proven on the framework repository's proof
game before release: `scripts/proof.sh` (run by `proof.yml`) builds its
models and compares every output file byte for byte with its baseline.

Not done yet: plugin identity in the cache keys, a neutral bake loop in the
base crates (the shading loop still lives in the proof game's plugin), the
hive split into a model-free hive and a pipeline plugin, and the first
release (there is no `MANIFEST` yet).

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
| `scripts/test-new-game.sh [--build]` | framework repository | makes a new game from the committed tree in a temporary folder and checks it; `--build` (build machines only) also builds its example model |
