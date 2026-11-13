# Scrap Heist style rules

The look of Scrap Heist, taken out of the shared framework docs so they stay neutral. The general process is in `framework/docs/art/pipeline.md` and the general critic rules in `framework/docs/art/critic-rules.md`. For the critic these rules play the part of the game's style rules (`art/style/critic-style.md` in a game laid out on the framework). Paths below are relative to `proof/scrap-heist`.

## The look

- A cartoony style: chunky, readable shapes, judged against our other models. "Chunkiness" and "style drift" (`framework/docs/art/feedback-words.md`) mean against this style.
- Flat material maps are deliberate: zero metal and full roughness on every part. Never flag them or propose real maps.
- Metal keeps hand-painted wear: brush strokes, wear and tapered highlights. Only printed markings (tape, labels) stay crisp.
- Items carry the rarity accent color from `art/src/rarity.luau`. The legendary glow is painted only, with no light objects.

## Shading amounts

Set in `art/src/common.luau` and used by every item, bot and layout:

| Setting | Value | What it does |
|---|---|---|
| `EDGE_HIGHLIGHT` | 0.6 | strength of the painted edge highlight |
| `CONTACT_SHADOW` | 0.425 | strength of the contact shadow where parts meet |
| `GRADIENT` | 0.5 | top-lit falloff toward the base |
| `EDGE_BLEND` | 0.7 | how far highlights feather and take the part's colour |
| `WARP` | 0.0385 | how far shapes are warped off true |
| `WEAR` | 0.57 | scales every part's rust, grime and scratches |

Shading layers: warp, weathering, edge highlights, contact shadows, gradient. A part with `rust` 0 gets no warp or weathering; use it for glow cores. A finish fix for one model sets the part's numbers before `handFinish`; a number moves into `art/src/shared/HandFinish.luau` (`PRESETS`) only under the rule in the pipeline's "Fixing finish without side effects".

## Critic rules for this look

**Settled, not defects:** flat material maps with no metal and full roughness; the family look of riveted dark steel, bronze, amber lamps and hazard tape; footprints in whole cells; black shading inside mouths; the cool violet tint every contact shadow and base gradient carries, which is the family's shadow colour, judged only for width and placement.

### The base paint layers are all there
Every painted part, from the largest mass to a lone prop on open ground, needs three layers, each visible from where a player stands: a contact shadow wherever it meets the ground or another part, edge wear along its hard edges, and a hand-drawn gradient, light at the top and stepping down to dark at the base in visible brush tiers. Go through the parts and name any layer missing in your RULES line. A smooth airbrushed fade or flat colour is not the gradient, rust specks are not edge wear, and a foot that meets the ground with no darkening around it has no contact shadow. Any missing layer is MED, on any part.

### Wear is uneven
Edge highlights and wear must vary in width, strength and length, with gaps. Flag the same stroke outlining every edge, and metal with no wear at all: clean doesn't mean new. Only printed markings stay crisp.

### Scrap looks like scrap
Most junk should be torn, crushed, bent or partial. One or two readable pieces are fine. A pile of intact icons is not scrap. Loose pieces must lie as if dropped: clusters and gaps, mixed sizes, pieces resting on and leaning against each other at unrelated angles. Pieces may bed into the heap's own body, but must never pass through one another, and a few pieces that truly rest beat many that clip. The check can't see clipping inside one part, so look for it; a visible clip is MED. Pieces spread evenly, one to a region or in a row, are at least MED where a player can see them. Ask for a close view of every pile or container of loose pieces, however small it looks, and never skip one as low stakes.

## Settled findings and map notes

- `critic-settled.md`: findings earlier critics withdrew after checking proof.
- `map-changes.md`: the list of map changes for the default layout, `ServerMap`.
- `studio-import.md`: where each Scrap Heist model goes in Studio.
- `shapes.md`: the shape helpers with the models that use them.
