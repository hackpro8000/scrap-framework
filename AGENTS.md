# AGENTS.md

This repository supports two coding agents that share the same rules and
workflow:

- **Claude Code**: subagents and hooks live in `.claude/`, rules in `CLAUDE.md`.
- **DeepSeek Harness (DSH)**: skills live in `.dsh/skills/`, and DSH loads
  this file plus `CLAUDE.md` as workspace instructions.

See [CLAUDE.md](CLAUDE.md) for the agent rules that apply to this repository.
`ROADMAP.md` is the authority on tooling, folder layout, lifecycle, naming,
comments, server authority and commit format.

On Claude Code, the main session does model work itself, and previews may go
to the `model-previewer` subagent under `.claude/agents/`. DeepSeek Harness
does model work directly in the main session. Both follow
`framework/docs/art/pipeline.md`.

The `sd`-instead-of-`sed` and `rg`-instead-of-`grep` rules in
`CLAUDE.md` are enforced for Claude Code by the PreToolUse hook in
`.claude/settings.json`. DeepSeek Harness has no per-project hook file, so
there they are soft rules the agent must follow from the instructions.
