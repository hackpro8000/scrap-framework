--!strict
--[[
	SettingsController

	The settings window, opened from the HUD menu: music and sound volume
	sliders. Settings apply at once on this client and are saved to the
	player's profile (SettingsService), so they follow them to any server.

	Volumes drive two SoundGroups in SoundService, "Music" and "Effects";
	every sound the game plays goes in one of them.

	Public API: none.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local React = require(ReplicatedStorage.Packages.React)
local Remotes = require(ReplicatedStorage.Shared.Net.Settings)

local HudController = require(script.Parent.HudController)
local Kit = require(script.Parent.Parent.UI.Kit)
local SettingsScreen = require(script.Parent.Parent.UI.Screens.Settings)
local Windows = require(script.Parent.Parent.UI.Windows)

local WINDOW = "Settings"
local MENU_ORDER = 100

local ROWS: { SettingsScreen.Row } = {
	{ key = "music", label = "MUSIC" },
	{ key = "sounds", label = "SOUNDS" },
}

local SettingsController = {}

local settings: { [string]: number } = {
	music = 0.6,
	sounds = 0.85,
}
local root: Kit.Root

local function soundGroup(name: string): SoundGroup
	local group = SoundService:FindFirstChild(name)
	if group and group:IsA("SoundGroup") then
		return group
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Parent = SoundService
	return created
end

local function render()
	root.render(React.createElement(SettingsScreen, {
		rows = ROWS,
		values = settings,
		onChange = function(key: string, value: number)
			settings[key] = value
			soundGroup("Music").Volume = settings.music
			soundGroup("Effects").Volume = settings.sounds
			render()
		end,
		onCommit = function()
			Remotes.SaveSettings:FireServer(settings)
		end,
	}))
end

function SettingsController.init()
	root = Kit.mount(WINDOW, 10)
	soundGroup("Music").Volume = settings.music
	soundGroup("Effects").Volume = settings.sounds
	render()
end

function SettingsController.start()
	HudController.addButton("Settings", MENU_ORDER, function()
		Windows.toggle(WINDOW)
	end)
	Remotes.SettingsLoaded.OnClientEvent:Connect(function(saved: any)
		if type(saved) ~= "table" then
			return
		end
		for _, row in ROWS do
			local value = saved[row.key]
			if type(value) == "number" then
				settings[row.key] = value
			end
		end
		soundGroup("Music").Volume = settings.music
		soundGroup("Effects").Volume = settings.sounds
		render()
	end)
	Remotes.RequestSettings:FireServer()
end

return SettingsController
