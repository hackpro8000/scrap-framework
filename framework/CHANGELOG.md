# Framework changelog

Newest first. `framework/scripts/framework-release.sh` adds each entry. Every
release is marked:

- **safe**: models build the same; nothing for a game to change.
- **look-changing**: models may look different; rebuild and review previews.
- **plugin-breaking**: a game's plugins or style kit must change to build.

## 0.4.1 (safe) - 2026-11-22

Add framework/scripts/code-map.sh to generate .codemap/overview.md and .codemap/modules.txt

## 0.4.0 (safe) - 2026-11-22

agent-watch and agent-stats read Antigravity subagent transcripts too; agent-watch flags SLOW actions (lib/action-times.tsv) and can watch the Lead (--session)

## 0.3.0 (safe) - 2026-11-18

modelkit: image:setAlpha for drawn atlases, and skin = "given" naming each vertex's bone

## 0.2.0 (safe) - 2026-11-18

Rigging: a part's vertices can each follow their own bone. model.part takes skin = "nearest" or "smooth" (and bones = {...} to limit which), beside the rigid bone = "Name"; the GLB carries per-vertex joints and weights, and scene reading and clip previews bend soft parts. Existing models build byte-identical.

## 0.1.1 (safe) - 2026-11-13

Previews built with --normals send their normal and roughness maps back (the copy looked in an empty path).

## 0.1.0 (safe) - 2026-11-13

First release: host-and-plugins model engine, shared model helpers, generic hive with the model pipeline plugin, pipeline scripts, process docs.
