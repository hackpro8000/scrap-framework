--!strict
local Source = require("../../Source")
local Test = require("../../Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local ProfileSchema = Source.require("src/server/Data/ProfileSchema")

describe("ProfileSchema.reconcile", function()
	it("fills a new template field into an old save without touching the rest", function()
		local oldSave = { version = 1, coins = 750 }

		ProfileSchema.reconcile(oldSave)

		expect(oldSave.coins).toBe(750)
		expect(oldSave.settings).toEqual(ProfileSchema.TEMPLATE.settings)
	end)

	it("fills missing fields inside nested tables", function()
		local save = { settings = { music = 0.1 } }

		ProfileSchema.reconcile(save)

		expect(save.settings.music).toBe(0.1)
		expect(save.settings.sounds).toBe(ProfileSchema.TEMPLATE.settings.sounds)
	end)

	it("changes nothing when run twice", function()
		local save = ProfileSchema.newData()
		save.coins = 10
		ProfileSchema.reconcile(save)
		local once = table.clone(save)

		ProfileSchema.reconcile(save)

		expect(save).toEqual(once)
	end)

	it("copies defaults, so saves never share a table with the template", function()
		local first = ProfileSchema.newData()
		local second = ProfileSchema.newData()
		first.settings.music = 0

		expect(second.settings.music).toBe(ProfileSchema.TEMPLATE.settings.music)
		expect(ProfileSchema.TEMPLATE.settings.music ~= 0).toBe(true)
	end)
end)

describe("ProfileSchema.migrate", function()
	local migrations = {
		[1] = function(data)
			data.credits = data.coins
			data.coins = nil
			return data
		end,
		[2] = function(data)
			data.credits *= 2
			return data
		end,
	}

	it("runs each step from the save's version to the target", function()
		local save = ProfileSchema.migrate({ version = 1, coins = 5 }, migrations, 3)

		expect(save).toEqual({ version = 3, credits = 10 })
	end)

	it("skips steps a save already has", function()
		local save = ProfileSchema.migrate({ version = 2, credits = 5 }, migrations, 3)

		expect(save.credits).toBe(10)
	end)

	it("treats unversioned saves as version 1", function()
		local save = ProfileSchema.migrate({ coins = 1 }, migrations, 2)

		expect(save).toEqual({ version = 2, credits = 1 })
	end)

	it("fails loudly on a missing step instead of loading a half-migrated save", function()
		expect(function()
			ProfileSchema.migrate({ version = 1 }, {}, 2)
		end).toThrow("no migration from version 1")
	end)

	it("has a migration for every version below the current one", function()
		for version = 1, ProfileSchema.VERSION - 1 do
			expect(ProfileSchema.MIGRATIONS[version] ~= nil).toBe(true)
		end
	end)
end)
