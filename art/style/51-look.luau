-- The plain kit's version of setLook(), which part() and chunkedPart() call
-- for every part: the coat is the part's flat colour, or the colour fn given
-- in place of a wear amount. Wear amounts mean nothing in this kit.
local function setLook(entry, color, rust)
	if type(rust) == "function" then
		entry.paint = rust
		return
	end
	entry.paint = function()
		return color[1], color[2], color[3]
	end
end
