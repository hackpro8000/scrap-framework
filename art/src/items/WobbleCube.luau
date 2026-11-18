-- Wobble Cube: the soft skin example. A 1-stud cube standing on the origin,
-- z up, with a bone at each of its eight corners and the cube skinned
-- { skin = "nearest" }, so every vertex follows its nearest corner and each
-- corner can wobble on its own. Bones are named Corner<Left|Right><Front|Back>
-- <Bottom|Top> (front is -y), apart from the part's name "Cube", since Studio
-- turns a bone sharing a part's name into a Motor6D. The Wobble clip pulls
-- the right-back-top corner out and back.
for _, x in { { "Left", -0.5 }, { "Right", 0.5 } } do
	for _, y in { { "Front", -0.5 }, { "Back", 0.5 } } do
		for _, z in { { "Bottom", 0 }, { "Top", 1 } } do
			model.bone(`Corner{x[1]}{y[1]}{z[1]}`, { at = { x[2], y[2], z[2] } })
		end
	end
end
part("Cube", { skin = "nearest" }, ACCENT_BLUE, function(mesh)
	box(mesh, 0, 0, 0, 1, 1, 1)
end, nil, 0)
model.clip("Wobble", {
	length = 1,
	keys = {
		CornerRightBackTop = {
			{ t = 0, pos = { 0, 0, 0 } },
			{ t = 0.5, pos = { 0.4, 0.4, 0.4 } },
			{ t = 1, pos = { 0, 0, 0 } },
		},
	},
})
finishParts()
