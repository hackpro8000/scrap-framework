--!strict
--[[
	Hud

	The always-on HUD at the left edge: the coin count on a panel, and under
	it a two-column grid of menu buttons other controllers add.

	Props: coins (number?), buttons ({ { text, order, onClick } })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Kit = require(script.Parent.Parent.Kit)

local e = React.createElement

local GAP = 8
local COUNTER_SIZE = Vector2.new(200, 52)
local MENU_CELL = Vector2.new(96, 44)
local MENU_COLUMNS = 2
local MENU_ROWS = 3
local MENU_TOP = COUNTER_SIZE.Y + GAP

export type MenuButton = { text: string, order: number, onClick: () -> () }

export type Props = {
	coins: number?,
	buttons: { MenuButton },
}

local function Hud(props: Props)
	local buttons = {}
	for _, button in props.buttons do
		buttons[button.text] = e(Kit.Button, {
			text = string.upper(button.text),
			textSize = Theme.TextSize.Small,
			size = MENU_CELL,
			layoutOrder = button.order,
			onClick = button.onClick,
		})
	end
	return e("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(COUNTER_SIZE.X, MENU_TOP + MENU_ROWS * (MENU_CELL.Y + GAP)),
	}, {
		Counter = e("Frame", {
			BackgroundColor3 = Theme.Colors.Panel,
			Size = UDim2.fromOffset(COUNTER_SIZE.X, COUNTER_SIZE.Y),
		}, {
			Corner = e("UICorner", { CornerRadius = Theme.CornerRadius }),
			Ink = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Ink,
				Thickness = Theme.StrokeThickness,
			}),
			Coins = e(Kit.Text, {
				text = if props.coins then Format.short(math.floor(props.coins)) else "...",
				textSize = 32,
				color = Theme.Colors.Accent,
				align = Enum.TextXAlignment.Center,
			}),
		}),
		Menu = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, MENU_TOP),
			Size = UDim2.new(1, 0, 1, -MENU_TOP),
		}, {
			Grid = e("UIGridLayout", {
				CellSize = UDim2.fromOffset(MENU_CELL.X, MENU_CELL.Y),
				CellPadding = UDim2.fromOffset(GAP, GAP),
				FillDirectionMaxCells = MENU_COLUMNS,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Buttons = e(React.Fragment, nil, buttons),
		}),
	})
end

return Hud
