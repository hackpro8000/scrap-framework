--!strict
--[[
	Client entry point

	The only client LocalScript. Requires every controller in boot order and
	hands them to Boot, which calls all init()s and then all start()s.

	To add a controller: require it below and add it to CONTROLLERS in the
	spot where its dependencies have already booted.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boot = require(ReplicatedStorage.Shared.Util.Boot)

local Controllers = script.Controllers

local CONTROLLERS: { Boot.Entry } = {
	{ name = "NotifyController", module = require(Controllers.NotifyController) },
	{ name = "HudController", module = require(Controllers.HudController) },
	{ name = "PromptController", module = require(Controllers.PromptController) },
	{ name = "SettingsController", module = require(Controllers.SettingsController) },
	{ name = "CounterController", module = require(Controllers.CounterController) },
}

Boot.run("Client", CONTROLLERS)
