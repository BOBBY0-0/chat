--[[
    AimHighlightHandler (Server Script)
    ====================================
    LOCATION: ServerScriptService
    
    Handles:
    - Receiving aim target updates from the gun holder
    - Broadcasting highlight updates to all clients
    - Creating/removing Highlight objects on players
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Shared active players registry for validating targets
local ActivePlayersRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ActivePlayersRegistry"))

-- Wait for RemoteEvents folder
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
if not remoteEvents then
	warn("RemoteEvents folder not found!")
	return
end

-- Create remote events if they don't exist
local function createRemoteEvent(name)
	local event = remoteEvents:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = remoteEvents
	end
	return event
end

local aimTargetEvent = createRemoteEvent("AimTargetUpdate")
local updateHighlightEvent = createRemoteEvent("UpdateHighlight")

-- Current highlighted player
local currentHighlightedPlayer = nil
local currentHighlight = nil

-- Remove existing highlight
local function removeHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
	if currentHighlightedPlayer then
		-- Notify all clients to remove highlight
		updateHighlightEvent:FireAllClients(nil)
		currentHighlightedPlayer = nil
	end
end

-- Add highlight to a player
local function addHighlightToPlayer(targetPlayer)
	if not targetPlayer then
		return
	end
	if not targetPlayer.Character then
		return
	end

	-- Don't re-highlight the same player
	if currentHighlightedPlayer == targetPlayer then
		return
	end

	-- Remove old highlight
	removeHighlight()

	-- Create new highlight
	currentHighlightedPlayer = targetPlayer

	-- Create Highlight instance on the server
	currentHighlight = Instance.new("Highlight")
	currentHighlight.Name = "AimHighlight"
	currentHighlight.FillColor = Color3.fromRGB(255, 255, 255) -- White (hidden)
	currentHighlight.OutlineColor = Color3.fromRGB(255, 255, 255) -- White outline
	currentHighlight.FillTransparency = 1 -- Fully transparent (outline only)
	currentHighlight.OutlineTransparency = 0
	currentHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	currentHighlight.Parent = targetPlayer.Character

	-- Notify all clients about the highlight
	updateHighlightEvent:FireAllClients(targetPlayer)

	print("[HIGHLIGHT] Added highlight to " .. targetPlayer.Name)
end

-- Listen for aim target updates from clients
aimTargetEvent.OnServerEvent:Connect(function(shooter, targetPlayer)
	-- Verify the shooter has the gun
	local hasGun = false
	if shooter.Character then
		local tool = shooter.Character:FindFirstChild("TheFiveGun")
		if tool then
			hasGun = true
		end
	end
	if shooter.Backpack then
		local tool = shooter.Backpack:FindFirstChild("TheFiveGun")
		if tool then
			hasGun = true
		end
	end

	if not hasGun then
		return -- Ignore if player doesn't have the gun
	end

	-- If target is nil, remove highlight
	if targetPlayer == nil then
		removeHighlight()
		return
	end

	-- Verify target is a valid player and not the shooter
	if targetPlayer and targetPlayer ~= shooter then
		-- IMPORTANT: Only allow highlighting of ACTIVE players in the current round
		if not ActivePlayersRegistry:IsPlayerActive(targetPlayer) then
			local activeNames = ActivePlayersRegistry:GetActivePlayerNames()
			print(
				"[HIGHLIGHT] Blocked - target "
					.. targetPlayer.Name
					.. " is not active. Active players: "
					.. table.concat(activeNames, ", ")
			)
			return
		end
		addHighlightToPlayer(targetPlayer)
	end
end)

-- Clean up highlight when player leaves
Players.PlayerRemoving:Connect(function(player)
	if player == currentHighlightedPlayer then
		removeHighlight()
	end
end)

-- Clean up highlight when highlighted player's character is removed
Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		if player == currentHighlightedPlayer then
			removeHighlight()
		end
	end)
end)

-- Also connect for existing players
for _, player in pairs(Players:GetPlayers()) do
	player.CharacterRemoving:Connect(function()
		if player == currentHighlightedPlayer then
			removeHighlight()
		end
	end)
end

-- ============================================
-- CLEANUP INTEGRATION: Gun removal & Round reset
-- ============================================

-- Listen for ForceGunReset event (fired on gun removal, miss, timeout, round reset)
local forceGunResetEvent = remoteEvents:FindFirstChild("ForceGunReset")
if forceGunResetEvent then
	forceGunResetEvent.OnServerEvent:Connect(function()
		-- When gun is reset/removed, immediately clear highlight
		removeHighlight()
		print("[HIGHLIGHT] Cleared highlight due to ForceGunReset")
	end)
end

-- Also listen on the server-side for when ForceGunReset is fired to all clients
-- We need to hook into when the event is FIRED, not received (since server fires it)
-- Create a BindableEvent for internal server-to-server highlight reset
local highlightResetEvent = ReplicatedStorage:WaitForChild("Events", 10)
if highlightResetEvent then
	local clearHighlightEvent = highlightResetEvent:FindFirstChild("ClearHighlightEvent")
	if not clearHighlightEvent then
		clearHighlightEvent = Instance.new("BindableEvent")
		clearHighlightEvent.Name = "ClearHighlightEvent"
		clearHighlightEvent.Parent = highlightResetEvent
	end

	clearHighlightEvent.Event:Connect(function()
		removeHighlight()
		print("[HIGHLIGHT] Cleared highlight via ClearHighlightEvent")
	end)
end

-- Track death of highlighted player
local currentDeathConnection = nil

local function setupDeathTracking(player)
	-- Disconnect previous death tracking
	if currentDeathConnection then
		currentDeathConnection:Disconnect()
		currentDeathConnection = nil
	end

	if not player then
		return
	end

	if player.Character then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			currentDeathConnection = humanoid.Died:Connect(function()
				if player == currentHighlightedPlayer then
					removeHighlight()
					print("[HIGHLIGHT] Cleared highlight - targeted player died")
				end
			end)
		end
	end
end

-- Override addHighlightToPlayer to include death tracking
local originalAddHighlight = addHighlightToPlayer
addHighlightToPlayer = function(targetPlayer)
	originalAddHighlight(targetPlayer)

	-- Set up death tracking for the newly highlighted player
	if currentHighlightedPlayer then
		setupDeathTracking(currentHighlightedPlayer)
	end
end

-- ============================================
-- BINDABLE FUNCTION: Allow other server scripts to query the highlighted player
-- Used by TheFiveGunServer for highlight-locked elimination
-- ============================================
if highlightResetEvent then
	local getHighlightedPlayerFunc = highlightResetEvent:FindFirstChild("GetHighlightedPlayer")
	if not getHighlightedPlayerFunc then
		getHighlightedPlayerFunc = Instance.new("BindableFunction")
		getHighlightedPlayerFunc.Name = "GetHighlightedPlayer"
		getHighlightedPlayerFunc.Parent = highlightResetEvent
	end

	getHighlightedPlayerFunc.OnInvoke = function()
		return currentHighlightedPlayer
	end
end

print("[AimHighlightHandler] Loaded successfully!")
