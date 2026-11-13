-- `rust` can also be a paint fn for surfaces with their own look.
-- `texture` overrides the texture size for parts that need more detail.
-- `emissive` is a glow strength (like SurfaceAppearance.EmissiveStrength);
-- glowing parts skip painted shading. `flat` skips the warp, for parts so
-- thin it would visibly bend them. `edge` is how far highlights and contact
-- shadows reach from an edge, in studs: bigger surfaces take a wider band.
-- `shade` multiplies the contact shadow strength, for parts that should sit in
-- heavier shadow than the standard wear. `lit` scales the highlight strength
-- and `wide` the width of the highlight brush strokes. Set `painted` on an entry
-- to paint its highlights as bold, fully loaded strokes instead of dry ones,
-- `blend` (0-1) to tint them from cream toward a lighter part colour, and
-- `taper` (studs) to run them full width at corners, thinning along each edge.
-- `softLit` (0-1) adds a wide, very soft highlight under the strokes, fading
-- out over `softEdge` studs from each edge; `softUneven` (0-1) makes its width
-- wander along the edge and `softTaper` (studs) thins it away from corners.
-- `softToZero` lets that thinning reach nothing, and `softPower` steepens the fade.
-- `strokes` lists brush strokes painted over the coat ({start, along, normal,
-- length, width, tail, color, brush}, color in sRGB), such as cracks or dabs;
-- `brush` is "taper" (crisp lines, the default), "round" or "sponge".
-- `stamps` lays the coat with scanned stroke shapes instead of the flat brush.
-- `hand` ("rock", "wood" or "metal") paints the coat the way a hand would, and
-- `handFocus` ({x, y, z, radius}) is where it gathers its finest strokes.
-- `handTune` sets any of its numbers by name (settings! in tools/modelkit/src/hand.rs).
-- `litMotion` draws the hard edge highlight with a moving hand, `litTune` sets its
-- numbers by name (tools/modelkit/src/marks.rs). A hand-painted part gets its
-- material's motion unless it names another, or `false` for the default strokes.
-- `brushes` draws any layer with a motion: edge, shade, soft, coat, grime, rust,
-- drip or scratch, each {motion = "press", tune = {name = value}}. A `strokes`
-- entry takes `motion` and `tune` the same way.
-- With `hand` as well, `crisp` keeps the shapes exact and takes only the brushwork's tone.
-- `crisp` lays the coat on texel by texel in the paint fn's exact colours
-- instead of brush strokes, for machine finishes (hazard tape, ribbed
-- rubber) that strokes would smear; shading still goes over it.
local function part(name, bone, color, build, smooth, rust, texture: number?, emissive: number?, flat: boolean?, edge: number?, shade: number?, lit: number?, wide: number?)
	local mesh = Mesh.new()
	build(if rust == 0 or flat then mesh else imperfect(mesh, name))
	mesh:setSmooth(if smooth ~= nil then smooth else SMOOTH_ANGLE)
	local fit = mesh:unwrap()
	local size = if texture then texture
		elseif texelDensity then math.clamp(math.ceil(texelDensity / fit / 4) * 4, 16, 1024)
		else TEXTURE
	local image = Image.new(size, size, color[1], color[2], color[3])
	local entry = { name = name, bone = bone, mesh = mesh, image = image, emissive = emissive, edge = edge, shade = shade, lit = lit, wide = wide }
	setLook(entry, color, rust)
	-- Glowing parts skip the painted bake, so their colors go on as they are.
	if emissive then
		mesh:paint(image, entry.paint)
	end
	table.insert(parts, entry)
end

