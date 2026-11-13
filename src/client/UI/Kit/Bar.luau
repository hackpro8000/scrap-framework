--!strict
--[[
	Bar

	A rounded trough with a fill showing a fraction (0 to 1). `fraction`
	may be a number or a React binding.

	Props: fraction, size (pixels), color?, position?, anchor?, layoutOrder?,
	zIndex?, children?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local e = React.createElement

-- The fill sits this many pixels inside the trough on every side.
local INSET = 4

export type Props = {
	fraction: any,
	size: Vector2,
	color: Color3?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	children: any?,
}

local function Bar(props: Props)
	local w, h = props.size.X, props.size.Y
	local function fillSize(fraction: number): UDim2
		return UDim2.fromOffset(math.round((w - 2 * INSET) * math.clamp(fraction, 0, 1)), h - 2 * INSET)
	end
	local fraction = props.fraction
	local fill = if type(fraction) == "number" then fillSize(fraction) else fraction:map(fillSize)
	local z = props.zIndex or 1
	return e("Frame", {
		BackgroundColor3 = Theme.Colors.Background,
		Size = UDim2.fromOffset(w, h),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		LayoutOrder = props.layoutOrder or 0,
		ZIndex = z,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Ink = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Colors.Ink,
			Thickness = Theme.StrokeThickness,
		}),
		Fill = e("Frame", {
			BackgroundColor3 = props.color or Theme.Colors.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(INSET, INSET),
			Size = fill,
			ZIndex = z + 1,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		}),
		Content = if props.children then e(React.Fragment, nil, props.children) else nil,
	})
end

return Bar
