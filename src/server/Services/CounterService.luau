--!strict
--[[
	CounterService (the example feature)

	Holds a per-player count for this session. The client asks to bump it;
	the server checks the step (CounterRules), owns the number and sends it
	back. Copy this shape for a new feature: remotes in Shared/Net, rules in
	a testable module, every remote through RemoteGuard.

	Public API:
		CounterService.getCount(player): number
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Counter)

local CounterRules = require(script.Parent.Parent.Counter.CounterRules)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local SYSTEM = "Counter"
local BUMP_RATE = 5
local REQUEST_RATE = 1

local CounterService = {}

local counts: { [Player]: number } = {}

function CounterService.getCount(player: Player): number
	return counts[player] or 0
end

function CounterService.init() end

function CounterService.start()
	RemoteGuard.listen(SYSTEM, Remotes.Bump, BUMP_RATE, function(player: Player, step: any)
		-- SECURITY: the client only names a step; the rules decide whether
		-- it is allowed and the server works out the new count.
		local ok, count = CounterRules.bump(CounterService.getCount(player), step)
		if not ok then
			return "BadStep"
		end
		counts[player] = count
		Remotes.CountChanged:FireClient(player, count)
		return nil
	end)
	RemoteGuard.listen(SYSTEM, Remotes.RequestCount, REQUEST_RATE, function(player: Player)
		Remotes.CountChanged:FireClient(player, CounterService.getCount(player))
		return nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		counts[player] = nil
	end)
end

return CounterService
