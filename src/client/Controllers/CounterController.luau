--!strict
--[[
	CounterController (the example feature)

	Adds a "Counter" button to the HUD menu that opens the counter window
	(UI/Screens/Counter), sends bumps to CounterService and shows the count
	the server sends back. The client never changes the count itself.

	Public API: none.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Remotes = require(ReplicatedStorage.Shared.Net.Counter)

local HudController = require(script.Parent.HudController)
local Kit = require(script.Parent.Parent.UI.Kit)
local CounterScreen = require(script.Parent.Parent.UI.Screens.Counter)
local Windows = require(script.Parent.Parent.UI.Windows)

local WINDOW = "Counter"
local MENU_ORDER = 1

local CounterController = {}

local root: Kit.Root
local count = 0

local function render()
	root.render(React.createElement(CounterScreen, {
		count = count,
		onBump = function()
			Remotes.Bump:FireServer(1)
		end,
	}))
end

function CounterController.init()
	root = Kit.mount(WINDOW, 10)
	render()
end

function CounterController.start()
	HudController.addButton("Counter", MENU_ORDER, function()
		Windows.toggle(WINDOW)
	end)
	Remotes.CountChanged.OnClientEvent:Connect(function(newCount: any)
		if type(newCount) == "number" then
			count = newCount
			render()
		end
	end)
	Remotes.RequestCount:FireServer()
end

return CounterController
