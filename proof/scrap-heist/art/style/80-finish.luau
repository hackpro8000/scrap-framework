-- Shades every part with all the others as occluders, so parts darken where
-- they touch or tuck under each other, then adds them to the model.
local function finishParts()
	for _, entry in parts do
		if entry.emissive then
			model.part(entry.name, entry.mesh, entry.image, { bone = entry.bone, preview = true, emissive = entry.emissive })
			continue
		end
		-- A grouped part (the chunks of one chunkedPart) is painted with every
		-- member of its group, itself included and in this order, so the bake
		-- lays one set of strokes over the whole part and each chunk takes the
		-- ones that fall on it; each member's texture size goes along for its
		-- shade layer.
		local occluders, group, groupSizes, groupIndex = {}, {}, {}, nil
		for _, other in parts do
			if entry.group and other.group == entry.group then
				table.insert(group, other.mesh)
				table.insert(groupSizes, { other.image:width(), other.image:height() })
				if other == entry then
					groupIndex = #group
				end
			elseif other ~= entry then
				table.insert(occluders, other.mesh)
			end
		end
		entry.mesh:paintShading(entry.image, {
			highlight = EDGE_HIGHLIGHT * (entry.lit or 1),
			shadow = CONTACT_SHADOW * (entry.shade or 1),
			gradient = entry.gradient or GRADIENT,
			blend = entry.blend or EDGE_BLEND,
			occluders = occluders,
			group = group,
			groupSizes = groupSizes,
			groupIndex = groupIndex,
			name = entry.name,
			paint = entry.paint,
			-- A custom paint fn is cached under the item's key, since its code is not hashed.
			custom = entry.custom,
			salt = if entry.custom then CACHE_KEY else nil,
			rust = entry.rust * WEAR,
			stamps = entry.stamps,
			hand = entry.hand,
			handFocus = entry.handFocus,
			handTune = entry.handTune,
			rubber = entry.rubber,
			rustEdges = entry.rustEdges,
			reach = entry.edge,
			bevelReach = entry.bevelReach,
			bevelFold = entry.bevelFold,
			bevelTilt = entry.bevelTilt,
			roughnessBase = entry.roughnessBase,
			roughnessEdge = entry.roughnessEdge,
			roughnessCrease = entry.roughnessCrease,
			roughnessWear = entry.roughnessWear,
			metalnessOn = entry.metalnessBase ~= nil,
			metalnessBase = entry.metalnessBase,
			metalnessEdge = entry.metalnessEdge,
			metalnessCrease = entry.metalnessCrease,
			metalnessWear = entry.metalnessWear,
			highlightWidth = entry.wide,
			highlightUneven = entry.litUneven,
			highlightUnevenStep = entry.litUnevenStep,
			highlightMotion = if entry.litMotion == nil then (entry.hand and HAND_EDGE_MOTION[entry.hand]) else (entry.litMotion or nil),
			highlightMotionTune = entry.litTune,
			highlightToZero = entry.litToZero,
			highlightEnd = entry.litEnd,
			paintedHighlights = entry.painted,
			cornerTaper = entry.taper,
			softHighlight = entry.softLit,
			softReach = entry.softEdge,
			softUneven = entry.softUneven,
			softTaper = entry.softTaper,
			softToZero = entry.softToZero,
			softPower = entry.softPower,
			softEnd = entry.softEnd,
			strokes = entry.strokes,
			brushes = entry.brushes,
			heightRange = entry.heightRange,
			crisp = entry.crisp,
		})
		model.part(entry.name, entry.mesh, entry.image, { bone = entry.bone, preview = true })
	end
end
