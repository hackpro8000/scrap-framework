--!strict
--[[
	Counter (the example feature)

	The counter window: the current count and a button that asks the server
	to add one.

	Props: count, onBump()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Kit = require(script.Parent.Parent.Kit)

local e = React.createElement

local PANEL = Vector2.new(320, 200)

export type Props = {
	count: number,
	onBump: () -> (),
}

local function Counter(props: Props)
	return e(Kit.Window, { name = "Counter", size = PANEL, title = "COUNTER" }, {
		Count = e(Kit.Text, {
			text = tostring(props.count),
			textSize = Theme.TextSize.Banner,
			color = Theme.Colors.Accent,
			align = Enum.TextXAlignment.Center,
			position = UDim2.fromOffset(Theme.MARGIN, Theme.BODY_Y),
			size = UDim2.fromOffset(PANEL.X - 2 * Theme.MARGIN, 56),
		}),
		Bump = e(Kit.Button, {
			text = "+1",
			onClick = props.onBump,
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -Theme.MARGIN),
		}),
	})
end

return Counter
