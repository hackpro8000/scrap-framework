-- The plain kit's version of finishParts(), called once at the end of a model.
-- part() has already unwrapped each mesh and sized its image; this paints
-- every part its coat (entry.paint, flat colour) and hands it to the engine.
-- No shading: edge highlights and contact shadows need a style plugin. Look
-- keys a model sets on a part are ignored.
local function finishParts()
	for _, entry in parts do
		-- Glowing parts were painted by part() already.
		if not entry.emissive then
			entry.mesh:paint(entry.image, entry.paint)
		end
		model.part(entry.name, entry.mesh, entry.image, { bone = entry.bone, preview = true, emissive = entry.emissive })
	end
end
