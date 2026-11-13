--!strict
local Source = require("../../Source")
local Test = require("../../Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local CounterRules = Source.require("src/server/Counter/CounterRules")

local function pack(...)
	return { ... }
end

describe("CounterRules", function()
	it("adds a valid step", function()
		expect(pack(CounterRules.bump(3, 2))).toEqual({ true, 5 })
	end)

	it("refuses zero, negative, fractional, too large and non-number steps", function()
		for _, bad in { 0, -1, 1.5, CounterRules.MAX_STEP + 1, 0 / 0, math.huge, "1", nil } do
			expect(pack(CounterRules.bump(3, bad :: any))).toEqual({ false, 3 })
		end
	end)

	it("caps the count", function()
		local _, count = CounterRules.bump(CounterRules.MAX_COUNT, 1)
		expect(count).toBe(CounterRules.MAX_COUNT)
	end)
end)
