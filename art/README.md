# Art

This game's models: Luau scripts that the framework's model engine turns into
meshes, textures and previews. The pipeline itself is described in
`framework/docs/art/pipeline.md`.

## Folders

- `art/style/` is the style kit, the game's look: the palette (`palette.luau`),
  the amounts the helpers read (`05-amounts.luau`: warp, smoothing angle,
  texture size), `setLook()` (`51-look.luau`) and `finishParts()`
  (`80-finish.luau`), the critic's style rules (`critic-style.md`), and
  `assembly.txt`, which says in what order the kit's files and the framework's
  helpers (`framework/art/lib/`) are joined in front of every model.
  `framework/art/lib/README.md` lists what a kit must define.
- `art/src/` holds the model sources: `items/<Name>.luau` for props,
  `bots/<Name>/` for characters, `layouts/` for maps, `shared/` for code
  several models include.
- `art/models/` is generated output: `<Name>/model.luau` (the assembled script),
  the `.glb`, textures and previews. Never edit it by hand.

The starter kit is deliberately plain: each part is painted its flat colour,
with no edge highlights, contact shadows, wear or warp. It uses only the
engine's base script API. `art/src/items/ExampleCrate.luau` is the
pattern to copy.

## Adding a model

1. Copy `art/src/items/ExampleCrate.luau` to `art/src/items/<Name>.luau` and
   change the shapes: one `part()` per colour, built from `box()`,
   `cylinder()` and the other helpers in `framework/art/lib/`, ending with
   `finishParts()`. Size it against the player's capsule in `game.toml`.
2. Check it assembles: `framework/scripts/assemble-model.sh <Name>`.
3. Build and preview it on a build machine, never locally (see the pipeline doc;
   the `starter` workflow builds every item and uploads the previews).

## Changing the look

Edit the kit: colours in `palette.luau`, amounts in `05-amounts.luau`, the
coat in `51-look.luau` and `80-finish.luau`, and the rules in
`critic-style.md` to match. Painted shading (edge highlights, contact shadows,
wear, brush strokes) needs a style plugin: a Rust plugin in `art/plugins/` that
adds its own mesh methods, which the kit's `finishParts()` then calls.
