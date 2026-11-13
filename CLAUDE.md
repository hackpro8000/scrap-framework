# CLAUDE.md

Supplementary rules for agents working on this game.

`ROADMAP.md` is the authority. It decides tooling, dependencies, folder layout, lifecycle (`init()`/`start()`), naming, comments, server authority and commit format. This file only adds style rules the roadmap doesn't cover. If anything here conflicts with the roadmap, the roadmap wins.

## Framework
- `framework/` is a pinned copy shared between games. Never edit it here. Changes go to the framework repository and come back with `framework/scripts/framework-update.sh` (planned).
- Game names and numbers live in `game.toml`. The game's look lives in `art/style/` and `art/plugins/` (planned).

## Code style
- Indent with tabs.
- Prefix private fields with `_` (`self._connections`), and unused parameters too (`_inputObject`).
- Use guard clauses and early returns instead of deep nesting.
- Use `if a then b else c` expressions where they read cleanly.
- Keep type annotations practical. Avoid theoretical type complexity.
- Shared types live in `<System>Types.luau` modules using `export type`.
- Import order: Roblox services, then packages, then shared modules, then local (`script.Parent`) modules.
- Keep dependencies, ownership, state, control flow and cleanup traceable within the file.
- No `WaitForChild` in server module requires.

## Tooling
- Search with `rg`, never `grep`.
- Edit files with `sd`, never `sed`. Pass `--` before patterns that start with `-`.
- `framework/scripts/ensure-tools.sh` installs `rg`, `sd` and `jq` in `~/.local/bin`. A session hook and the standby agent run it, so every machine hosting the repo has them.

## Design
- Prefer obvious over clever, and simple over comprehensive.
- Prefer composition over inheritance.
- Generalize only when reuse actually recurs. No speculative or empty abstractions.
- One job per file. Aim for under 300 lines and never go over 500; split by responsibility before a file gets there, so agents can read one file cheaply and work on separate files at once. Data files (animation clips, asset tables, map chunk tables, assembled `art/models/*/model.luau`) are exempt. `framework/scripts/file-sizes.sh` lists the files over the limits.
- Names say what things mean in the game. No generic names that hide meaning.
- Dependencies point one way: `shared` never requires `server` or `client`, and reusable systems never require game-specific modules.

## Model work
- After every model change, run `framework/scripts/checkpoint-model.sh` (see `framework/docs/art/pipeline.md`) and send the user the screenshot. Never batch changes or leave progress unpushed.
- Keep model builds cached: layout slabs go through `placeSlab`, prop textures stay at or under `texture_cap` (`game.toml`) on a side, and an unchanged rebuild finishes in seconds. See the caching rules in `framework/docs/art/pipeline.md`.
- Split large meshes (terrain, roads, floors) into cubic chunks via `chunkedPart`: `chunk_studs` studs, or `texture_cap` texels at the layout's texel density if smaller, with textures at or under `texture_cap` on a side (both in `game.toml`).
- Model work routing: the main session does model work itself, editing `art/src`, building and checkpointing, following `framework/docs/art/pipeline.md`. Previews may go to the `model-previewer` subagent (`.claude/agents/model-previewer.md`); relay its screenshot to the user.
- Quick tweaks: for changes to existing settings in a model's `art/src` source (numbers such as sizes, counts, spreads, densities and colours), run `framework/scripts/watch-model.sh <Name>` so the preview re-renders on every save, then checkpoint the result once the user likes it.
- Before a change that grows textures or part counts, estimate the cache size (each paint layer is stored raw at 6 bytes per texel, several layers per part) and keep it within the limit the user sets.
- A character is a capsule `character_width` studs across and `character_height` tall (`game.toml`). Size every space a player uses (gates, doors, walkways, bridges, lifts, interiors, headroom) against it, and state the clearance in sketches and reviews.
- A new item or bot: the sketch and its part plan are approved together. Then comes the first build: draft, then up to 3 rounds of `framework/scripts/review-model.sh` checked by the `model-critic` subagent (`.claude/agents/model-critic.md`), then one checkpoint (`framework/docs/art/pipeline.md`, "First build"). After that, one change per checkpoint, gridded screenshot to the user, ending with "Where we are" from the model's notes file. This applies to every harness, Claude Code and DeepSeek Harness alike.
- The critic's rules grow by themselves. When the user points out a model defect the critic's last list didn't have, add a general rule to `framework/docs/art/critic-rules.md` (or, for a rule about this game's look, to `art/style/critic-style.md`) in that same turn without being asked, prove a fresh critic now catches it, then fix the defect (`framework/docs/art/pipeline.md`, "When the critic misses something").
- Vague feedback ("something's off"): don't guess. Look up a pointed-at cell in `cells.txt`, or offer plain-words choices and then A/B/C variants to pick from (`framework/docs/art/pipeline.md`, "When the feedback is vague").
- If a model task can't be done, stop and report why to the user. Don't fall back to doing it a different way.
- Before a build of the default layout (`default_layout` in `game.toml`), run `framework/scripts/coordinator.sh status` and `framework/scripts/standby-status.sh`. Builds go to the build machines with `framework/scripts/send-build.sh <commit>` (unfinished work: `framework/scripts/push-wip.sh` first). To warm machines, start the coordinator (`framework/scripts/coordinator.sh start`) and then `framework/scripts/standby-start.sh 20`, so tasks and results stream live; see the Layouts section of `framework/docs/art/pipeline.md`. Standby is started with the build-standby workflow (`.github/workflows/build-standby.yml`); keep its defaults, which let machines idle for up to an hour (the countdown restarts with each build; 5 hours at most).

## Team
- Work that is more than a step or two runs through the agent team: `docs/team/core.md` (fixed, only the user changes it) and `docs/team/playbook.md` (the team's own, rewritten as it learns). The main session is the Lead.
- Team roles are the agent types `worker`, `worker-hard`, `specialist`, `checker`, `observer` and `scout` in `.claude/agents/`. Never use `general-purpose` for team work.
- While agents run, `framework/scripts/agent-watch.sh --until-flag` runs beside them. After a task, `framework/scripts/agent-stats.sh` gives the numbers and one line goes in `docs/team/log.md`.
- Objective calls are made automatically; subjective ones (look, feel, style, design, naming, tone) go to the user. If the user is away, decide reversibly and list it under "Decided while you were away" in `docs/team/log.md`.

## Cloud builds
- Claude cloud machines build map shards one prompt at a time: a Haiku cloud session per shard runs one command, `framework/scripts/cloud-shard.sh <task> <index> <count>`, which prepares the machine, builds the shard, and commits and pushes the result to the branch `cloud-results/<task>/s<index>` itself. `framework/scripts/cloud-results.sh <task> <count>` collects the branches into `.standby-results/<task>/` for `framework/scripts/merge-shards.sh`. The objects stay on the machine (no uploads on this route yet). Proven at 25 machines, output identical to the GitHub build. Details and what was tried (including why cloud machines cannot be persistent hub workers) are in `framework/docs/plans/multi-machine.md`.
