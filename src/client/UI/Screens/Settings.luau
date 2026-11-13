--!strict
--[[
	Settings

	The settings window: one volume slider per row, the label on the left
	margin and the slider ending on the right margin.

	Props: rows ({ { key, label } }), values, onChange(key, value) while
	dragging, onCommit() when a drag is done
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Kit = require(script.Parent.Parent.Kit)

local e = React.createElement

local WINDOW = "Settings"
local ROW_H = 44
local ROW_STEP = 52
local SLIDER = Vector2.new(180, 24)
local KNOB_W, KNOB_H = 18, 32

export type Row = { key: string, label: string }

export type Props = {
	rows: { Row },
	values: { [string]: number },
	onChange: (key: string, value: number) -> (),
	onCommit: () -> (),
}

local PANEL_W = 400

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Dragging anywhere on the bar or knob sets the value; letting go commits it.
local function Slider(props: { value: number, y: number, onChange: (number) -> (), onCommit: () -> () })
	local barRef = React.useRef(nil :: Frame?)
	local dragging = React.useRef(false)
	local x = PANEL_W - Theme.MARGIN - SLIDER.X

	local function setFrom(screenX: number)
		local bar = barRef.current
		if not bar then
			return
		end
		props.onChange(math.clamp((screenX - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1))
	end

	React.useEffect(function()
		local moved = UserInputService.InputChanged:Connect(function(input)
			local moving = input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			if dragging.current and moving then
				setFrom(input.Position.X)
			end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input)
			if dragging.current and isPointer(input) then
				dragging.current = false
				props.onCommit()
			end
		end)
		return function()
			moved:Disconnect()
			ended:Disconnect()
		end
	end, { props.onChange, props.onCommit } :: { any })

	local function begin(_gui, input: InputObject)
		if isPointer(input) then
			dragging.current = true
			setFrom(input.Position.X)
		end
	end

	return e(React.Fragment, nil, {
		Bar = e("Frame", {
			ref = barRef,
			BackgroundTransparency = 1,
			Active = true,
			Position = UDim2.fromOffset(x, props.y + (ROW_H - SLIDER.Y) / 2),
			Size = UDim2.fromOffset(SLIDER.X, SLIDER.Y),
			[React.Event.InputBegan] = begin,
		}, {
			Trough = e(Kit.Bar, { fraction = props.value, size = SLIDER }),
		}),
		Knob = e("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Colors.Text,
			Position = UDim2.fromOffset(x + SLIDER.X * props.value - KNOB_W / 2, props.y + (ROW_H - KNOB_H) / 2),
			Size = UDim2.fromOffset(KNOB_W, KNOB_H),
			ZIndex = 3,
			[React.Event.InputBegan] = begin,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Ink = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Ink,
				Thickness = Theme.StrokeThickness,
			}),
		}),
	})
end

local function Settings(props: Props)
	local rows = {}
	for index, row in props.rows do
		local y = Theme.BODY_Y + (index - 1) * ROW_STEP
		rows[row.key] = e(React.Fragment, nil, {
			Label = e(Kit.Text, {
				text = row.label,
				textSize = Theme.TextSize.Body,
				position = UDim2.fromOffset(Theme.MARGIN, y),
				size = UDim2.fromOffset(PANEL_W - 2 * Theme.MARGIN, ROW_H),
			}),
			Control = e(Slider, {
				value = props.values[row.key] or 0,
				y = y,
				onChange = function(newValue: number)
					props.onChange(row.key, newValue)
				end,
				onCommit = props.onCommit,
			}),
		})
	end

	local footY = Theme.BODY_Y + #props.rows * ROW_STEP + 6
	return e(Kit.Window, {
		name = WINDOW,
		size = Vector2.new(PANEL_W, footY + 20 + Theme.MARGIN),
		title = "SETTINGS",
	}, {
		Rows = e(React.Fragment, nil, rows),
		Footnote = e(Kit.Text, {
			text = "Saved to your profile",
			textSize = Theme.TextSize.Small,
			kind = "note",
			align = Enum.TextXAlignment.Center,
			position = UDim2.fromOffset(Theme.MARGIN, footY),
			size = UDim2.fromOffset(PANEL_W - 2 * Theme.MARGIN, 20),
		}),
	})
end

return Settings
