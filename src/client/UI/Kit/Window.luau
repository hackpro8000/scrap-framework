--!strict
--[[
	Window

	A window: a dimmed backdrop, a panel centred on screen with a header
	bar holding the title and a close button. The panel pops open from its
	centre and shrinks away on close. The whole window scales down evenly to
	fit small screens, so the pixel layout inside holds on phones.

	Open state lives in Windows; tapping close or the backdrop calls
	`onClose` if given, else closes the window.

	Props: name, size (panel pixels), title, sticky?, onClose?, children
	(laid out in the panel's pixels; content starts at Theme.BODY_Y)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Windows = require(script.Parent.Parent.Windows)
local KitButton = require(script.Parent.KitButton)
local KitText = require(script.Parent.KitText)

local e = React.createElement

local SCREEN_PAD = 24
local POP_FROM = 0.85
local CLOSE_INSET = 6

export type Props = {
	name: string,
	size: Vector2,
	title: string,
	sticky: boolean?,
	onClose: (() -> ())?,
	children: any?,
}

local function useFitScale(size: Vector2): number
	local function fit(): number
		local camera = Workspace.CurrentCamera
		if not camera then
			return 1
		end
		local viewport = camera.ViewportSize
		return math.min(1, (viewport.X - SCREEN_PAD * 2) / size.X, (viewport.Y - SCREEN_PAD * 2) / size.Y)
	end
	local scale, setScale = React.useState(fit)
	React.useEffect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return nil
		end
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			setScale(fit())
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	return scale
end

local function Window(props: Props)
	local isOpen = Windows.useOpen(props.name)
	-- Stays true through the closing shrink, so the panel animates out.
	local shown, setShown = React.useState(isOpen)
	local popRef = React.useRef(nil :: UIScale?)
	local size = props.size
	local fitScale = useFitScale(size)

	React.useEffect(function()
		if isOpen then
			setShown(true)
			return nil
		end
		local pop = popRef.current
		if not pop then
			setShown(false)
			return nil
		end
		local tween = TweenService:Create(pop, TweenInfo.new(Theme.POP_SECONDS * 0.6), { Scale = POP_FROM })
		local connection = tween.Completed:Connect(function()
			setShown(false)
		end)
		tween:Play()
		return function()
			connection:Disconnect()
			tween:Cancel()
		end
	end, { isOpen })

	React.useEffect(function()
		local pop = popRef.current
		if not (isOpen and shown and pop) then
			return
		end
		pop.Scale = POP_FROM
		local info = TweenInfo.new(Theme.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(pop, info, { Scale = 1 }):Play()
	end, { isOpen, shown })

	if not shown then
		return nil
	end

	local function close()
		if props.onClose then
			props.onClose()
		else
			Windows.close(props.name)
		end
	end

	local closeSize = Theme.HEADER_H - 2 * CLOSE_INSET
	return e(React.Fragment, nil, {
		Backdrop = e("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.5,
			Size = UDim2.fromScale(1, 1),
			[React.Event.Activated] = function()
				if not props.sticky then
					close()
				end
			end,
		}),
		Holder = e("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size.X, size.Y),
			ZIndex = 2,
		}, {
			Fit = e("UIScale", { Scale = fitScale }),
			-- The panel pops inside the holder, from its centre, so the pop
			-- and the fit don't fight over one UIScale.
			Panel = e("Frame", {
				Active = true,
				BackgroundColor3 = Theme.Colors.Panel,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size.X, size.Y),
			}, {
				Pop = e("UIScale", { ref = popRef }),
				Corner = e("UICorner", { CornerRadius = Theme.CornerRadius }),
				Ink = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Theme.Colors.Ink,
					Thickness = Theme.StrokeThickness,
				}),
				Header = e("Frame", {
					BackgroundColor3 = Theme.Colors.Background,
					Size = UDim2.new(1, 0, 0, Theme.HEADER_H),
					ZIndex = 2,
				}, {
					Corner = e("UICorner", { CornerRadius = Theme.CornerRadius }),
					Title = e(KitText, {
						text = props.title,
						textSize = Theme.TextSize.Title,
						position = UDim2.fromOffset(Theme.MARGIN, 0),
						size = UDim2.new(1, -Theme.MARGIN - Theme.HEADER_H, 1, 0),
						zIndex = 3,
					}),
					Close = e(KitButton, {
						text = "X",
						onClick = close,
						size = Vector2.new(closeSize, closeSize),
						color = Theme.Colors.Bad,
						anchor = Vector2.new(1, 0.5),
						position = UDim2.new(1, -CLOSE_INSET, 0.5, 0),
						zIndex = 3,
					}),
				}),
				Body = e(React.Fragment, nil, props.children),
			}),
		}),
	})
end

return Window
