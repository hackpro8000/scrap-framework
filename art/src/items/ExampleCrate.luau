-- Example Crate: the starter's one model, a pattern to copy. A lidded box
-- 3 x 3 studs and about 3.1 tall (a player's capsule is 4 across and 5.5
-- tall), standing on the origin, z up. It shows the usual shape: one part()
-- per colour, each built from box() calls, colours from the kit's palette,
-- then finishParts() to paint them all and hand them to the engine.
part("Base", nil, DARK_GREY, function(mesh)
	box(mesh, 0, 0, 0, 3.0, 3.0, 0.2)
end)
part("Body", nil, ACCENT_BLUE, function(mesh)
	box(mesh, 0, 0, 0.2, 2.5, 2.5, 2.3)
end)
part("Posts", nil, DARK_GREY, function(mesh)
	for _, x in { -1.3, 1.3 } do
		for _, y in { -1.3, 1.3 } do
			box(mesh, x, y, 0.2, 0.4, 0.4, 2.3)
		end
	end
end)
part("Lid", nil, LIGHT_GREY, function(mesh)
	box(mesh, 0, 0, 2.5, 3.0, 3.0, 0.25)
end)
part("Handle", nil, DARK_GREY, function(mesh)
	-- Two feet on the lid and a bar across them.
	for _, x in { -0.5, 0.5 } do
		box(mesh, x, 0, 2.75, 0.15, 0.2, 0.2)
	end
	box(mesh, 0, 0, 2.95, 1.15, 0.2, 0.12)
end)
part("Label", nil, ACCENT_YELLOW, function(mesh)
	-- A plate on the front face (-y).
	box(mesh, 0, -1.29, 1.1, 0.8, 0.08, 0.6)
end)
finishParts()
