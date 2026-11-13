--!strict
--[[
	KitText

	A label in one of the kit's two voices:
		"label"  Theme.Font in Theme text color with an ink outline (default)
		"note"   Theme.BodyFont, dimmer and wrapped, for body copy

	`fit` sizes the label to its text across, for rows.

	Props: text, textSize, kind?, align?, alignY?, position?, size?, anchor?,
	color?, fit?, height?, zIndex?, layoutOrder?, visible?, transparency?,
	wrap?, scaled?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local e = React.createElement

export type Props = {
	text: string,
	textSize: number,
	kind: ("label" | "note")?,
	align: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	position: UDim2?,
	size: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	fit: boolean?,
	height: number?,
	zIndex: number?,
	layoutOrder: number?,
	visible: boolean?,
	transparency: number?,
	wrap: boolean?,
	-- Shrinks the text to fit its box, never past textSize.
	scaled: boolean?,
}

local function KitText(props: Props)
	local isLabel = props.kind ~= "note"
	local size = props.size or UDim2.fromScale(1, 1)
	if props.fit then
		size = UDim2.fromOffset(0, props.height or props.textSize + 8)
	end
	return e("TextLabel", {
		BackgroundTransparency = 1,
		Text = props.text,
		Font = if isLabel then Theme.Font else Theme.BodyFont,
		TextSize = props.textSize,
		TextScaled = props.scaled == true,
		TextColor3 = props.color or if isLabel then Theme.Colors.Text else Theme.Colors.TextDim,
		TextTransparency = props.transparency or 0,
		TextWrapped = if props.wrap == nil then not isLabel else props.wrap,
		TextXAlignment = props.align or Enum.TextXAlignment.Left,
		TextYAlignment = props.alignY or Enum.TextYAlignment.Center,
		AutomaticSize = if props.fit then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
		Size = size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		ZIndex = props.zIndex or 1,
		LayoutOrder = props.layoutOrder or 0,
		Visible = if props.visible == nil then true else props.visible,
	}, {
		Fit = if props.scaled then e("UITextSizeConstraint", { MaxTextSize = props.textSize }) else nil,
		Ink = if isLabel
			then e("UIStroke", {
				Color = Theme.Colors.Ink,
				Thickness = 1,
				Transparency = props.transparency or 0,
				LineJoinMode = Enum.LineJoinMode.Round,
			})
			else nil,
	})
end

return KitText
