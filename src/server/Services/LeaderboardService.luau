--!strict
--[[
	LeaderboardService

	The player list leaderboard (leaderstats): each player's coins. Roblox
	shows any folder named "leaderstats" under a Player in the player list,
	so this just keeps a value in step with the profile.

	Nothing needs cleaning up: the folder is destroyed with the Player.

	Public API: none.
]]

local DataService = require(script.Parent.DataService)

local STAT = "Coins"

local LeaderboardService = {}

local function createStats(player: Player, data: any)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = STAT
	coins.Value = data.coins
	coins.Parent = folder

	folder.Parent = player
end

local function setCoins(player: Player, balance: number)
	local folder = player:FindFirstChild("leaderstats")
	local value = folder and folder:FindFirstChild(STAT)
	if value and value:IsA("IntValue") then
		value.Value = math.floor(balance)
	end
end

function LeaderboardService.init() end

function LeaderboardService.start()
	DataService.forEachLoaded(createStats)
	DataService.coinsChanged:connect(setCoins)
end

return LeaderboardService
