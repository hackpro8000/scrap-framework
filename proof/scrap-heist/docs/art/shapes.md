# Scrap Heist shapes, with examples

The game's own copy of the shape list, with the models that use each one. The general guidance is in `framework/docs/art/shapes.md`. Paths are relative to the game root (`proof/scrap-heist`). Counts are how many sources used each one when this was written.

## Shared helpers (in every item and bot)

The shapes come from `framework/art/lib/` (`20-shapes.luau`, `21-plates-tubes.luau`, `22-machine-shapes.luau`), `part()` and `chunkedPart()` from `60-parts.luau` and `70-chunks.luau` there, and `finishParts()` from this game's `art/style/80-finish.luau`.

| Helper | Makes | Examples |
| --- | --- | --- |
| `box(mesh, cx, cy, cz, sx, sy, sz)` | axis-aligned box [72] | ArenaDrone, BigSpanner, BillboardFrame |
| `cylinder(mesh, cx, cy, cz, r, length, axis, sides)` | cylinder along x, y or z [57] | Barrels, BentBolt |
| `sphere(mesh, cx, cy, cz, rx, ry, rz, rings, sides)` | squashable UV sphere [21] | Zapper, BuildBay |
| `ring(mesh, cx, cy, cz, inner, outer, depth, axis, sides)` | washer: rims, hubs, clamps [42] | ArenaDrone, Barrels |
| `bolt(mesh, cx, cy, cz, axis, size)` | hex bolt head on a flat face [23] | Bruiser, CapsuleRefurbished |
| `stud(mesh, x, y, z, nx, ny, nz, size)` | bolt head on a curved face | Zapper, GearPanel |
| `strut(mesh, x0, y0, z0, x1, y1, z1, thick)` | square beam between two points: limbs, antennae [42] | BillboardFrame, all bots |
| `tube(mesh, points, radius, sides)` | round tube along points, capped [37] | BentBolt, all bots |
| `arc(cx, cz, radius, a0, a1, steps)` | points on an arc, for `plate` outlines | SimpleCar |
| `plate(mesh, outline, y, depth, bevel)` | any flat silhouette, bevelled: signs, blades, brackets | BigSpanner, SimpleCar |
| `sheet(mesh, axis, at, sign, a0, a1, z0, z1, thick, boltSize)` | bolted panel on a box side | Bruiser, JunkrotDingDingDingDongo |
| `cornerBracket(mesh, x, y, sx, sy, z, height, size)` | angle bracket round a box corner | Bruiser, Scrapper |
| `gear(mesh, cx, cy, cz, radius, thick, teeth, axis)` | spur gear with shaft hole [10] | GearPanel, GoldenCog |
| `belt(mesh, axis, ax, ay, az, ra, bx, by, bz, rb, thick)` | drive belt round two pulleys | bots |
| `engine(mesh, cx, cy, cz, size)` | small finned engine block | bots |
| `exhaust(mesh, points, radius)` | pipe ending in a sooty flared lip | bots, ScrapTreeExhaust |
| `rope(mesh, points, radius)` / `lashing(...)` | twisted rope / rope round a box | Zapper / Bruiser |
| `part(name, bone, color, build, ...)` | adds a part with its look | everything |
| `chunkedPart(...)` | large meshes split into texture-sized chunks | IslandStudy, ShopConceptContainer |
| `finishParts()` | shades parts with each other as occluders, then adds them | everything |

## Edit Mesh examples

The junkrots are built with Edit Mesh (`art/src/shared/EditMesh.luau`, `EditShapes.luau`, `EditOps.luau`): JunkrotKit and JunkrotScrap (`spin`, `sweep`), JunkrotRusteliRustela (`arch`, `tube`), JunkrotPressurwashoSprizzo (`coil`, `torus`), JunkrotHolofonoShimmerra (`sphere`, `capsule`).

`imperfect` tilts, tapers, bends or dents parts, the usual fix for "stiff" (`framework/docs/art/feedback-words.md`).
