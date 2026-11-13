--!strict
--[[
	Counter remotes (the example feature)

	Client to server:
		Bump(step)        -- add `step` to my count, see CounterRules
		RequestCount()    -- "send me my count" (on join)

	Server to client:
		CountChanged(count)
]]

local Net = require(script.Parent.Net)

local SYSTEM = "Counter"

return {
	Bump = Net.event(SYSTEM, "Bump"),
	RequestCount = Net.event(SYSTEM, "RequestCount"),
	CountChanged = Net.event(SYSTEM, "CountChanged"),
}
