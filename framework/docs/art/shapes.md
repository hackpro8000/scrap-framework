# Shapes to build from

Read this before drafting a model (`framework/docs/art/pipeline.md`, "First build"). Reach
for an existing shape before writing vertices by hand, and open a model that
uses it to see it in use. A game's shared model code may list more helpers,
or use other names; check its own docs first.

## Shared helpers (the game's shared model code, in every item and bot)

| Helper | Makes |
| --- | --- |
| `box(mesh, cx, cy, cz, sx, sy, sz)` | axis-aligned box |
| `cylinder(mesh, cx, cy, cz, r, length, axis, sides)` | cylinder along x, y or z |
| `sphere(mesh, cx, cy, cz, rx, ry, rz, rings, sides)` | squashable UV sphere |
| `ring(mesh, cx, cy, cz, inner, outer, depth, axis, sides)` | washer: rims, hubs, clamps |
| `bolt(mesh, cx, cy, cz, axis, size)` | hex bolt head on a flat face |
| `stud(mesh, x, y, z, nx, ny, nz, size)` | bolt head on a curved face |
| `strut(mesh, x0, y0, z0, x1, y1, z1, thick)` | square beam between two points: limbs, antennae |
| `tube(mesh, points, radius, sides)` | round tube along points, capped |
| `arc(cx, cz, radius, a0, a1, steps)` | points on an arc, for `plate` outlines |
| `plate(mesh, outline, y, depth, bevel)` | any flat silhouette, bevelled: signs, blades, brackets |
| `sheet(mesh, axis, at, sign, a0, a1, z0, z1, thick, boltSize)` | bolted panel on a box side |
| `cornerBracket(mesh, x, y, sx, sy, z, height, size)` | angle bracket round a box corner |
| `gear(mesh, cx, cy, cz, radius, thick, teeth, axis)` | spur gear with shaft hole |
| `belt(mesh, axis, ax, ay, az, ra, bx, by, bz, rb, thick)` | drive belt round two pulleys |
| `rope(mesh, points, radius)` / `lashing(...)` | twisted rope / rope round a box |
| `part(name, bone, color, build, ...)` | adds a part with its look |
| `chunkedPart(...)` | large meshes split into texture-sized chunks |
| `finishParts()` | shades parts with each other as occluders, then adds them |

## Edit Mesh (`EditMesh.luau` + `EditShapes.luau` + `EditOps.luau`, by `-- include:`)

Quad meshes you can select from and reshape. Use them for organic or
sculpted forms.

Shapes: `lattice`, `box`, `grid`, `disk`, `circle`, `cylinder`, `cone`,
`sphere`, `capsule`, `torus`, `tube`, `prism`, `wedge`, `arch`, `spin`
(lathe a profile), `sweep` (profile along a path, with scale and twist),
`coil`.

Operations (`EditOps.luau`, header lists them all): `extrude`, `inset`,
`loopCut`, `subdivide`, `smoothSubdivide`, `bridge`, `bridgeFaces`, `bevel`,
`poke`, `bend`/`taper`/`twist`, `smooth`, `push`, `toCircle`, `toSphere`,
`dissolve`, `weld`, `fill`, `mirror`, `solidify`, `array`, `transform`.

## Picking one

- A flat outline (blade, sign, bracket): `plate`, not stacked boxes.
- Mirrored halves: build one side, `mirror` it (Edit Mesh), or loop over `{-1, 1}`.
- Repeats (rivets, slats, teeth): one helper call in a loop, or `array`.
- A rounded or organic body: Edit Mesh `sphere`/`capsule`/`spin`, then
  `smoothSubdivide` and `push`.
- Small detail (seams, scratches, rivet rows on a flat panel): paint it with
  `paintShading` rather than modelling it.
- No helper cuts one shape out of another yet. Make holes with `inset` and
  `extrude` inward, or with `ring`/`tube` walls.
