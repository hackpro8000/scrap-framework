--!strict
--[[
	CounterRules

	The rules for the example counter, kept apart from CounterService so
	they can be tested without Roblox. A step must be a whole number from 1
	to MAX_STEP; the count never goes past MAX_COUNT.

	Public API:
		CounterRules.MAX_STEP
		CounterRules.MAX_COUNT
		CounterRules.isValidStep(step): boolean
		CounterRules.bump(count, step): (ok, newCount)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CounterRules = {}

CounterRules.MAX_STEP = 5
CounterRules.MAX_COUNT = 1000

function CounterRules.isValidStep(step: any): boolean
	return Validate.isPositiveInteger(step) and step <= CounterRules.MAX_STEP
end

function CounterRules.bump(count: number, step: any): (boolean, number)
	if not CounterRules.isValidStep(step) then
		return false, count
	end

	return true, math.min(CounterRules.MAX_COUNT, count + step)
end

return CounterRules
