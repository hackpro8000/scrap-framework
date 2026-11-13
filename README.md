# Game framework and starter

This repository is two things at once:

- **A game framework** for Roblox games, shared between games as a pinned
  copy in `framework/`. It holds the model pipeline (a Rust engine that builds,
  paints and bakes models from Luau scripts, with plugins planned), the model
  checks, the UI painter, the machine hive that spreads builds over many
  machines, and the process docs.
- **A starter game.** The root is laid out as a new game: a game code
  skeleton, the agent team and its rules, and an empty `art/`.

## Layout

| Path | Owner | Holds |
|---|---|---|
| `framework/` | shared, pinned | engine, model checks, UI painter, Studio scripts, pipeline and hive scripts, the hive, process docs |
| `game.toml` | game | the names and numbers the framework reads: game name, repository, default layout, character size, camera height, texture limits |
| `art/src/`, `art/models/` | game | model sources, and the models generated from them |
| `art/style/`, `art/plugins/` | game | the game's style kit and style rules, and its Rust plugins (planned) |
| `src/`, `tests/` | game | game code and tests, starting from the skeleton (copied, not shared) |
| `CLAUDE.md`, `AGENTS.md`, `.claude/`, `docs/team/` | game | agent team and rules (copied, not shared) |
| `ROADMAP.md` | game | the game's roadmap, a template to fill in |
| `proof/scrap-heist/` | this repository only | Scrap Heist, the test game used to prove engine changes |

## Starting a new game

1. Use this repository as a template on GitHub.
2. Run `framework/scripts/init-game.sh <name>` (planned). It fills in
   `game.toml` and removes `proof/`.
3. Fill in `ROADMAP.md`, then follow `CLAUDE.md`.

## How updates arrive

A game holds an exact copy of one framework release in `framework/` and never
edits it. `framework/scripts/framework-update.sh <release>` (planned) replaces
the folder with that release. `framework/scripts/framework-check.sh` (planned)
fails when the folder differs from the release it claims to be. A game
updates when it chooses. Framework changes are made in this repository.

## The proof game

`proof/scrap-heist/` is Scrap Heist, the game the framework was taken from,
kept as a test. Its models are built with this repository's engine and
compared byte for byte with the ones its own engine gives
(`framework/scripts/proof.sh`, `framework/scripts/bake-proof.sh`, run by
`.github/workflows/proof.yml`). A new game does not receive it.

## More

- `framework/README.md`: what is in the shared folder.
- `framework/docs/art/pipeline.md`: how models are made.
- `framework/docs/plans/multi-machine.md`: how the build machines work.
- `docs/team/core.md`: how the agent team works.
