--!strict
--[[
	ProfileSchema

	What a player's save looks like, and how old saves are brought up to
	date when they load.

	Two tools keep old saves working:
	- reconcile() fills in any field the template has and the save doesn't.
	  Adding a new field to TEMPLATE is all it takes for existing players to
	  get it, with its default value, without touching anything else.
	- migrate() runs one function per version step for changes reconcile
	  can't express (renaming a field, changing its shape). Each step takes
	  a save at version N and returns it at version N + 1.

	Keep keys in saved maps as strings, never numbers: DataStores save
	tables as JSON, and a table with gaps in its number keys doesn't survive
	that round trip.

	Public API:
		ProfileSchema.VERSION
		ProfileSchema.TEMPLATE
		ProfileSchema.MIGRATIONS
		ProfileSchema.newData(): ProfileData
		ProfileSchema.reconcile(data, template?)
		ProfileSchema.migrate(data, migrations?, targetVersion?)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require(ReplicatedStorage.Shared.Config.Game)

local ProfileSchema = {}

export type Settings = {
	music: number,
	sounds: number,
}

export type ProfileData = {
	version: number,
	coins: number,
	settings: Settings,
}

ProfileSchema.VERSION = 1

ProfileSchema.TEMPLATE = {
	version = ProfileSchema.VERSION,
	coins = Game.STARTING_COINS,
	settings = {
		music = 0.6,
		sounds = 0.85,
	},
} :: ProfileData

-- MIGRATIONS[n] upgrades a save from version n to n + 1. Add one each time
-- VERSION goes up.
ProfileSchema.MIGRATIONS = {} :: { [number]: (any) -> any }

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end

	return copy
end

function ProfileSchema.newData(): ProfileData
	return deepCopy(ProfileSchema.TEMPLATE)
end

-- Fills in missing fields from the template, recursing into nested tables.
-- DUPE-SAFE: only ever adds missing keys; never overwrites or removes
-- anything a save already has, so reconciling twice changes nothing.
function ProfileSchema.reconcile(data: { [any]: any }, template: { [any]: any }?)
	local source = template or (ProfileSchema.TEMPLATE :: any)
	for key, default in source do
		local current = data[key]
		if current == nil then
			data[key] = deepCopy(default)
		elseif type(current) == "table" and type(default) == "table" then
			ProfileSchema.reconcile(current, default)
		end
	end
end

function ProfileSchema.migrate(
	data: { [any]: any },
	migrations: { [number]: (any) -> any }?,
	targetVersion: number?
): any
	local steps = migrations or ProfileSchema.MIGRATIONS
	local target = targetVersion or ProfileSchema.VERSION
	-- Saves from before versioning existed count as version 1.
	local version = data.version or 1

	while version < target do
		local step = steps[version]
		assert(step, `ProfileSchema: no migration from version {version}`)
		data = step(data)
		version += 1
		data.version = version
	end
	data.version = version

	return data
end

return ProfileSchema
