# Model helpers

The Luau every model starts with: math, shape helpers (`box`, `cylinder`,
plates, tubes, machine shapes), the warp (`imperfect`), the `parts` list,
`part()` and `chunkedPart()`. They are mechanics only. A game's look comes
from its style kit (`art/style/` in the game), which fills in the names and
functions below. A game's engine may also carry style plugins that add mesh
methods; the helpers here call only the base script API.

## The contract between these helpers and a style kit

The helpers and the kit's files are joined into one script, so a name must be
defined before the first file that reads it.

### (a) Names a kit defines

| Name | Type | Meaning | Read by, so define before |
| --- | --- | --- | --- |
| `WARP` | number | Strength of the low-frequency warp that bends panels and dents them; `0` keeps faces flat and square. | `imperfect` in `50-warp.luau` |
| `SMOOTH_ANGLE` | number or boolean | Default auto-smooth for `part()` and `chunkedPart()` when the model gives none: an angle in degrees, `true` (all smooth) or `false` (flat). | `60-parts.luau`, `70-chunks.luau` |
| `TEXTURE` | number | Texture size in pixels (square) for a part, used when no texel density is set (`useTexelDensity`) and the part gives no `texture` size. | `60-parts.luau` |

The engine provides `Mesh`, `Image`, `model` and `TEXEL_SCALE`; an item's
assembled script also starts with `CACHE_KEY`.

### (b) Functions a kit provides

`setLook(entry, color, rust)`, defined before `60-parts.luau`.
Called by `part()` for every part it makes, and by `chunkedPart()` again on
each chunk after its `part()` call. It must set `entry.paint` to a colour
function `(x, y, z, nx, ny, nz) -> r, g, b` (position and normal of a surface
point; colour in 0-1), which `part()` uses at once with `mesh:paint` for a
glowing part. `color` is the part's `{r, g, b}`. `rust` is whatever the model
passed as `part()`'s sixth argument (nil, a number or a function); what it
means is the kit's business. The helpers read it in one place only: `0`
skips the warp.

`finishParts()`, defined before the model body (it is not read by any
helper). Called once at the end of a model. `part()` has already built,
smoothed and unwrapped each mesh and made its image; `finishParts()` paints
every entry in `parts` (an entry with `emissive` is already painted) and
hands each to the engine with
`model.part(entry.name, entry.mesh, entry.image, { bone = entry.bone, preview = true, emissive = entry.emissive })`.

`parts` (defined in `50-warp.luau`) lists the parts in the order they were
made. Each entry holds:

| Field | Type | Set by | Meaning |
| --- | --- | --- | --- |
| `name` | string | `part()` | The part's name; a chunk is `<name>_<cx>_<cy>_<cz>`. |
| `bone` | string? | `part()` | The bone it follows, or nil. |
| `mesh` | Mesh | `part()` | Built, warped unless `rust == 0` or `flat`, smoothed, unwrapped. |
| `image` | Image | `part()` | Square, filled with `color`; sized by the `texture` argument, else the texel density, else `TEXTURE`. |
| `emissive` | number? | `part()` | Glow strength; such a part is already painted with `entry.paint`. |
| `edge`, `shade`, `lit`, `wide` | number? | `part()` | Passed through from `part()`'s arguments; the helpers never read them. A kit may. |
| `paint` and anything else | | `setLook()` | The kit's own. |
| `group`, `chunkOf` | string | `chunkedPart()` | The `chunkedPart()` name every chunk of one surface shares. |
| `heightRange` | `{bottom, top}` | `chunkedPart()` | The z-range of the whole surface, shared by its chunks. |

Models may set more fields on entries (`parts[#parts].<key> = ...`). A kit
reads the ones it knows and ignores the rest.

### (c) Order

The order of the files lives in the game's `art/style/assembly.txt`, read by
`framework/scripts/assemble-model.sh`. A typical `[helpers]` list:

```
framework:art/lib/00-math.luau
style:05-amounts.luau            WARP, SMOOTH_ANGLE, TEXTURE
framework:art/lib/10-texel-density.luau
framework:art/lib/20-shapes.luau
framework:art/lib/21-plates-tubes.luau
framework:art/lib/22-machine-shapes.luau
framework:art/lib/50-warp.luau
style:51-look.luau               setLook
framework:art/lib/60-parts.luau
framework:art/lib/70-chunks.luau
style:80-finish.luau             finishParts
```

A kit may put more of its own files between these, as long as each name is
defined before it is read.
