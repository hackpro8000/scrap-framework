--!strict
--[[
	Game config

	The top-level knobs for a server: who counts as an admin and how the
	economy starts. Detailed config tables read their headline values from
	here, so tuning a whole server starts in this file.

	Public API: the constants below.
]]

local Game = {}

-- User IDs allowed to use debug commands outside Studio. In Studio
-- everyone is allowed.
Game.ADMIN_USER_IDS = {} :: { number }

-- Coins a brand-new player starts with.
Game.STARTING_COINS = 0

return Game
