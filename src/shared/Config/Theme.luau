--!strict
--[[
	Theme

	UI styling: colors, fonts, sizes and the layout grid every UI module
	reads. The kit draws everything as plain frames in these colors, so
	restyling the game's UI starts (and mostly ends) here.
]]

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(24, 26, 32),
	Panel = Color3.fromRGB(40, 44, 54),
	PanelLight = Color3.fromRGB(70, 130, 220),
	Text = Color3.fromRGB(240, 240, 240),
	TextDim = Color3.fromRGB(170, 175, 185),
	Accent = Color3.fromRGB(250, 200, 70),
	Good = Color3.fromRGB(80, 200, 110),
	Bad = Color3.fromRGB(230, 80, 90),
	Warning = Color3.fromRGB(245, 150, 50),
	Ink = Color3.fromRGB(10, 10, 14),
}

Theme.Font = Enum.Font.GothamBold
Theme.BodyFont = Enum.Font.Gotham
Theme.CornerRadius = UDim.new(0, 10)
-- The outline every panel and button wears.
Theme.StrokeThickness = 2
Theme.Padding = 8

-- Text sizes scale with the screen but stay readable on phones.
Theme.TextSize = {
	Small = 14,
	Body = 18,
	Title = 24,
	Banner = 40,
}

-- Layout grid shared by every window: MARGIN in from the panel's edge, GAP
-- between blocks, the header HEADER_H tall and content from BODY_Y.
Theme.MARGIN = 20
Theme.GAP = 12
Theme.HEADER_H = 44
Theme.BODY_Y = 64

-- Button sizes in pixels.
Theme.ButtonSize = {
	Large = Vector2.new(200, 52),
	Medium = Vector2.new(160, 44),
	Small = Vector2.new(44, 44),
}

-- Seconds a window takes to pop open.
Theme.POP_SECONDS = 0.2

return Theme
