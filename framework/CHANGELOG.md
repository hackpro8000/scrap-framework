# Framework changelog

Newest first. `framework/scripts/framework-release.sh` adds each entry. Every
release is marked:

- **safe**: models build the same; nothing for a game to change.
- **look-changing**: models may look different; rebuild and review previews.
- **plugin-breaking**: a game's plugins or style kit must change to build.

## 0.1.1 (safe) - 2026-11-13

Previews built with --normals send their normal and roughness maps back (the copy looked in an empty path).

## 0.1.0 (safe) - 2026-11-13

First release: host-and-plugins model engine, shared model helpers, generic hive with the model pipeline plugin, pipeline scripts, process docs.
