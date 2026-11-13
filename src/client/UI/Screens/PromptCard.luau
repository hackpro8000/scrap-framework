--!strict
--[[
	PromptCard

	One ProximityPrompt drawn as a kit card floating over what it acts on:
	what it is (ObjectText), the action on a button (ActionText) and the
	key to press beside it. It pops up when shown and shrinks away when
	hidden. Holding the key or the button fills the button as the hold runs;
	tapping the button works on touch.

	Props: prompt, inputType, closing (shrink away, then onGone()), onGone()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Kit = require(script.Parent.Parent.Kit)

local e = React.createElement

local CARD = Vector2.new(240, 116)
local INSET = 14
local CARD_LIFT = 4.5
local KEY_W, KEY_H = 44, 40
local BUTTON = Theme.ButtonSize.Medium
local BUTTON_Y = 58
local POP_IN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

export type Props = {
	prompt: ProximityPrompt,
	inputType: Enum.ProximityPromptInputType,
	closing: boolean,
	onGone: () -> (),
}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string?
	if inputType == Enum.ProximityPromptInputType.Touch then
		return nil
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

-- Pops the card in on mount; shrinks it away when closing.
local function usePop(scaleRef: { current: UIScale? }, closing: boolean, onGone: () -> ())
	React.useEffect(function()
		local scale = scaleRef.current
		if not scale then
			return nil
		end
		if not closing then
			scale.Scale = 0
			TweenService:Create(scale, POP_IN, { Scale = 1 }):Play()
			return nil
		end
		local tween = TweenService:Create(scale, POP_OUT, { Scale = 0 })
		local done = tween.Completed:Connect(onGone)
		tween:Play()
		return function()
			done:Disconnect()
			tween:Cancel()
		end
	end, { closing })
end

-- The hold fills the button from the left as the prompt's hold runs.
local function useHoldFill(prompt: ProximityPrompt, fillRef: { current: Frame? })
	React.useEffect(function()
		local tween: Tween? = nil
		local began = prompt.PromptButtonHoldBegan:Connect(function()
			local fill = fillRef.current
			if not fill then
				return
			end
			fill.Size = UDim2.fromScale(0, 1)
			local info = TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear)
			local started = TweenService:Create(fill, info, { Size = UDim2.fromScale(1, 1) })
			started:Play()
			tween = started
		end)
		local ended = prompt.PromptButtonHoldEnded:Connect(function()
			if tween then
				tween:Cancel()
			end
			local fill = fillRef.current
			if fill then
				fill.Size = UDim2.fromScale(0, 1)
			end
		end)
		return function()
			began:Disconnect()
			ended:Disconnect()
			if tween then
				tween:Cancel()
			end
		end
	end, { prompt })
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function PromptCard(props: Props)
	local prompt = props.prompt
	local scaleRef = React.useRef(nil :: UIScale?)
	local fillRef = React.useRef(nil :: Frame?)
	usePop(scaleRef, props.closing, props.onGone)
	useHoldFill(prompt, fillRef)

	local key = keyText(prompt, props.inputType)
	-- No key on touch: the button sits in the middle of the card.
	local buttonX = if key then INSET else (CARD.X - BUTTON.X) / 2

	return e("BillboardGui", {
		Adornee = prompt.Parent,
		AlwaysOnTop = true,
		Active = true,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		StudsOffset = Vector3.new(0, CARD_LIFT, 0),
		ResetOnSpawn = false,
	}, {
		Card = e("Frame", {
			BackgroundColor3 = Theme.Colors.Panel,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(CARD.X, CARD.Y),
		}, {
			Pop = e("UIScale", { ref = scaleRef }),
			Corner = e("UICorner", { CornerRadius = Theme.CornerRadius }),
			Heading = e(Kit.Text, {
				text = string.upper(prompt.ObjectText),
				textSize = 20,
				color = Theme.Colors.Accent,
				position = UDim2.fromOffset(INSET, 12),
				size = UDim2.fromOffset(CARD.X - 2 * INSET, 28),
			}),
			Button = e("TextButton", {
				Text = "",
				AutoButtonColor = false,
				ClipsDescendants = true,
				BackgroundColor3 = Theme.Colors.Good,
				Position = UDim2.fromOffset(buttonX, BUTTON_Y),
				Size = UDim2.fromOffset(BUTTON.X, BUTTON.Y),
				[React.Event.InputBegan] = function(_gui, input: InputObject)
					if isPointer(input) then
						prompt:InputHoldBegin()
					end
				end,
				[React.Event.InputEnded] = function(_gui, input: InputObject)
					if isPointer(input) then
						prompt:InputHoldEnd()
					end
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = Theme.CornerRadius }),
				Label = e(Kit.Text, {
					text = string.upper(prompt.ActionText),
					textSize = 20,
					align = Enum.TextXAlignment.Center,
					zIndex = 3,
				}),
				Hold = e("Frame", {
					ref = fillRef,
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 0.6,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(0, 1),
					ZIndex = 2,
				}),
			}),
			Key = if key
				then e("Frame", {
					BackgroundColor3 = Theme.Colors.Background,
					Position = UDim2.fromOffset(CARD.X - INSET - KEY_W, BUTTON_Y + (BUTTON.Y - KEY_H) / 2),
					Size = UDim2.fromOffset(KEY_W, KEY_H),
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
					Text = e(Kit.Text, { text = key, textSize = 20, align = Enum.TextXAlignment.Center }),
				})
				else nil,
		}),
	})
end

return PromptCard
