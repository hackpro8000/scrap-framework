--!strict
--[[
	KitButton

	A rounded, outlined button in one Theme color with a centred label. It
	swells a touch under the cursor and sinks while held. A disabled button
	turns grey and ignores taps.

	Props: text?, textSize?, onClick, size? (pixels, default
	Theme.ButtonSize.Medium), color?, enabled?, position?, anchor?, zIndex?,
	layoutOrder?, visible?, children?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local KitText = require(script.Parent.KitText)

local e = React.createElement

local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.9
local REACT_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad)
-- Letting go springs the button back past its size before it settles.
local RELEASE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DISABLED_COLOR = Color3.fromRGB(110, 110, 115)

export type Props = {
	text: string?,
	textSize: number?,
	onClick: () -> (),
	size: Vector2?,
	color: Color3?,
	enabled: boolean?,
	position: UDim2?,
	anchor: Vector2?,
	zIndex: number?,
	layoutOrder: number?,
	visible: boolean?,
	children: any?,
}

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function KitButton(props: Props)
	local size = props.size or Theme.ButtonSize.Medium
	local enabled = props.enabled ~= false

	local scaleRef = React.useRef(nil :: UIScale?)
	local hovered = React.useRef(false)
	local pressed = React.useRef(false)
	local enabledRef = React.useRef(enabled)
	enabledRef.current = enabled

	local react = React.useCallback(function()
		local scale = scaleRef.current
		if not scale then
			return
		end
		local live = enabledRef.current
		local down = pressed.current and live
		local target = if down then PRESS_SCALE elseif hovered.current and live then HOVER_SCALE else 1
		local released = not down and scale.Scale < 1
		TweenService:Create(scale, if released then RELEASE_TWEEN else REACT_TWEEN, { Scale = target }):Play()
	end, {})

	return e("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = if enabled then props.color or Theme.Colors.PanelLight else DISABLED_COLOR,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		ZIndex = props.zIndex or 1,
		LayoutOrder = props.layoutOrder or 0,
		Visible = if props.visible == nil then true else props.visible,
		[React.Event.MouseEnter] = function()
			hovered.current = true
			react()
		end,
		[React.Event.MouseLeave] = function()
			hovered.current, pressed.current = false, false
			react()
		end,
		[React.Event.InputBegan] = function(_gui, input: InputObject)
			if isPointer(input) then
				pressed.current = true
				react()
			end
		end,
		[React.Event.InputEnded] = function(_gui, input: InputObject)
			if not isPointer(input) then
				return
			end
			pressed.current = false
			-- A finger lifting leaves no hover behind.
			if input.UserInputType == Enum.UserInputType.Touch then
				hovered.current = false
			end
			react()
		end,
		[React.Event.Activated] = function()
			if enabledRef.current then
				props.onClick()
			end
		end,
	}, {
		Scale = e("UIScale", { ref = scaleRef }),
		Corner = e("UICorner", { CornerRadius = Theme.CornerRadius }),
		Ink = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Colors.Ink,
			Thickness = Theme.StrokeThickness,
		}),
		Label = if props.text and props.text ~= ""
			then e(KitText, {
				text = props.text,
				textSize = props.textSize or Theme.TextSize.Body,
				align = Enum.TextXAlignment.Center,
				zIndex = (props.zIndex or 1) + 1,
			})
			else nil,
		Content = if props.children then e(React.Fragment, nil, props.children) else nil,
	})
end

return KitButton
