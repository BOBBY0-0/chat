--[[
    ActivePlayersRegistry (ModuleScript)
    =====================================
    LOCATION: ReplicatedStorage/Modules
    
    Shared registry for tracking which players are active in the current round.
    Used by ChairWaitingSystem to set active players and by AimHighlightHandler
    to validate targets.
]]

local ActivePlayersRegistry = {}

-- Current active players table (set by ChairWaitingSystem)
local activePlayers = {}

-- Set the list of active players (called by ChairWaitingSystem when round starts)
function ActivePlayersRegistry:SetActivePlayers(playerList)
	activePlayers = {}
	local names = {}
	for _, player in pairs(playerList) do
		activePlayers[player] = true
		if player and player.Name then
			table.insert(names, player.Name)
		end
	end
	print("[ActivePlayersRegistry] Updated active players (" .. #playerList .. "): " .. table.concat(names, ", "))
end

-- Check if a player is active in the current round
function ActivePlayersRegistry:IsPlayerActive(player)
	if not player then
		return false
	end
	return activePlayers[player] == true
end

-- Remove a player from active list (for elimination mid-round)
function ActivePlayersRegistry:RemovePlayer(player)
	if player and activePlayers[player] then
		activePlayers[player] = nil
		print("[ActivePlayersRegistry] Removed player: " .. player.Name)
	end
end

-- Clear all active players (called on round end)
function ActivePlayersRegistry:Clear()
	activePlayers = {}
	print("[ActivePlayersRegistry] Cleared all active players")
end

-- Get count of active players
function ActivePlayersRegistry:GetActiveCount()
	local count = 0
	for _ in pairs(activePlayers) do
		count = count + 1
	end
	return count
end

-- Get list of active player names (for debugging)
function ActivePlayersRegistry:GetActivePlayerNames()
	local names = {}
	for player in pairs(activePlayers) do
		if player and player.Name then
			table.insert(names, player.Name)
		end
	end
	return names
end

return ActivePlayersRegistry
