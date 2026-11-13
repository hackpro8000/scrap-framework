# Pack: model work

`framework/docs/art/pipeline.md` and the "Model work" section of `CLAUDE.md` are the rules; this pack only points at them.

- The main session does model edits, builds and checkpoints itself. Previews may go to `model-previewer`; reviews go to `model-critic` with a neutral prompt.
- One change per checkpoint (`framework/scripts/checkpoint-model.sh`), screenshot to the user.
- Builds and renders go to the build machines, spread across all of them (`framework/scripts/send-build.sh`), never the user's computer.
- Sources are in `art/src`; `art/models` holds generated copies. Never edit or quote the copies.
- Layout slabs go through `placeSlab`; large meshes through `chunkedPart`. Textures stay at or under `texture_cap` (`game.toml`) on a side.
- What the game's look does on purpose is in its style rules (`art/style/critic-style.md`). Do not flag or "fix" those.
