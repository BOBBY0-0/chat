--[[
    ChairWaitingSystem (Server Script)
    ==================================
    LOCATION: ServerScriptService
    
    Complete minigame flow:
    1. Wait for players to sit
    2. Countdown
    3. Intro text (typing effect)
    4. Maze minigame (drag box through path)
    5. Give gun to winner
    6. Kill challenge (30 seconds)
    7. Determine final winner
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Shared active players registry for cross-script validation
local ActivePlayersRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ActivePlayersRegistry"))

-- Round protection system (border wall + chair locking)
local RoundProtectionSystem = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RoundProtectionSystem"))

-- Configuration
local MIN_PLAYERS_REQUIRED = 2
local COUNTDOWN_TIME = 5
local MAZE_TIMEOUT = 45 -- Seconds for maze minigame
local FALLING_TIMEOUT = 45 -- Seconds for falling minigame
local FALLING_GOAL = 10 -- Clicks needed to win falling game
local BOXFILLING_TIMEOUT = 60 -- Seconds for box filling minigame
local EQUILIBRIUM_TIMEOUT = 45 -- Seconds for equilibrium balance minigame
local EQUILIBRIUM_GOAL = 3 -- Seconds to hold balance to win
local KILL_CHALLENGE_TIME = 30 -- Seconds to get a kill
local COLORRUSH_TIMEOUT = 30 -- Seconds for Color Rush minigame
local COLORRUSH_PREVIEW_TIME = 3 -- Seconds to show target color

-- ================================================
-- TESTING: Set to true to force Color Rush as first minigame
-- Set to false after testing is complete
-- ================================================
local TESTING_FORCE_COLOR_RUSH = false

-- Minigame types for random selection
local MINIGAMES = { "maze", "falling", "boxfilling", "equilibrium", "colorrush" }

-- ============================================
-- REMOTE EVENTS SETUP
-- ============================================
local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not remoteEvents then
	remoteEvents = Instance.new("Folder")
	remoteEvents.Name = "RemoteEvents"
	remoteEvents.Parent = ReplicatedStorage
end

-- Create all remote events
local function createRemoteEvent(name)
	local event = remoteEvents:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = remoteEvents
	end
	return event
end

local updateUIEvent = createRemoteEvent("UpdateTableUI")
local showTypingTextEvent = createRemoteEvent("ShowTypingText")
local startMazeGameEvent = createRemoteEvent("StartMazeGame")
local updateMazeProgressEvent = createRemoteEvent("UpdateMazeProgress")
local endMazeGameEvent = createRemoteEvent("EndMazeGame")
local playerMazeCompleteEvent = createRemoteEvent("PlayerMazeComplete")
local playerMazeResetEvent = createRemoteEvent("PlayerMazeReset")
local showCenterTextEvent = createRemoteEvent("ShowCenterText") -- Legacy, kept for compat
local showGameAnnouncementEvent = createRemoteEvent("ShowGameAnnouncement") -- Gameplay updates
local showWinnerAnnouncementEvent = createRemoteEvent("ShowWinnerAnnouncement") -- Cinematic winner display
local showKillTimerEvent = createRemoteEvent("ShowKillTimer")
local hideAllUIEvent = createRemoteEvent("HideAllUI")
local updateHighlightEvent = createRemoteEvent("UpdateHighlight")
local forceGunResetEvent = createRemoteEvent("ForceGunReset")
local toggleResetButtonEvent = createRemoteEvent("ToggleResetButton")

-- Falling minigame events
local startFallingGameEvent = createRemoteEvent("StartFallingGame")
local endFallingGameEvent = createRemoteEvent("EndFallingGame")
local playerCaughtElementEvent = createRemoteEvent("PlayerCaughtElement")
local updateFallingProgressEvent = createRemoteEvent("UpdateFallingProgress")
local spawnFallingElementEvent = createRemoteEvent("SpawnFallingElement")

-- Box filling minigame events
local startBoxFillingGameEvent = createRemoteEvent("StartBoxFillingGame")
local playerBoxSubmitEvent = createRemoteEvent("PlayerBoxSubmit")
local endBoxFillingGameEvent = createRemoteEvent("EndBoxFillingGame")

-- Equilibrium (balance) minigame events
local startEquilibriumGameEvent = createRemoteEvent("StartEquilibriumGame")
local equilibriumWinEvent = createRemoteEvent("EquilibriumWin")
local endEquilibriumGameEvent = createRemoteEvent("EndEquilibriumGame")
local updateEquilibriumProgressEvent = createRemoteEvent("UpdateEquilibriumProgress")

-- Color Rush minigame events
local startColorRushGameEvent = createRemoteEvent("StartColorRushGame")
local colorRushPreviewEvent = createRemoteEvent("ColorRushPreview")
local colorRushShowGridEvent = createRemoteEvent("ColorRushShowGrid")
local playerColorSelectedEvent = createRemoteEvent("PlayerColorSelected")
local endColorRushGameEvent = createRemoteEvent("EndColorRushGame")

-- Game fully ended event (signals client to hard-stop all animations including Animation 3)
local gameFullyEndedEvent = createRemoteEvent("GameFullyEnded")

-- Lighting events (client-side per-player lighting)
local applyGameLightingEvent = createRemoteEvent("ApplyGameLighting")
local restoreDefaultLightingEvent = createRemoteEvent("RestoreDefaultLighting")
local restoreDefaultWithBackgroundEvent = createRemoteEvent("RestoreDefaultWithBackground")

-- Client→Server callback: client fires this when full intro sequence completes
local introSequenceCompleteEvent = createRemoteEvent("IntroSequenceComplete")

-- Sequential intro events
local showIntroBackgroundEvent = createRemoteEvent("ShowIntroBackground") -- Server→Client: show static background curtain
local playPlayerIntroEvent = createRemoteEvent("PlayPlayerIntro") -- Server→Client: play this player's intro sequence
local playerIntroFinishedEvent = createRemoteEvent("PlayerIntroFinished") -- Client→Server: player's intro animation done

-- BindableEvent for server-to-server highlight clearing
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
local clearHighlightEvent = eventsFolder and eventsFolder:FindFirstChild("ClearHighlightEvent")
if not clearHighlightEvent and eventsFolder then
	clearHighlightEvent = Instance.new("BindableEvent")
	clearHighlightEvent.Name = "ClearHighlightEvent"
	clearHighlightEvent.Parent = eventsFolder
end

-- Helper function to clear all highlights
local function clearAllHighlights()
	-- Fire the UpdateHighlight event with nil to clear client-side highlights
	updateHighlightEvent:FireAllClients(nil)

	-- Fire the ClearHighlightEvent for server-side highlight cleanup
	if clearHighlightEvent then
		clearHighlightEvent:Fire()
	end
end

-- ============================================
-- GAME STATE
-- ============================================
local gameState = {
	isWaiting = true,
	isCountingDown = false,
	isGameRunning = false,
	currentPlayers = {}, -- Players participating in this round
	mazeProgress = {}, -- {player = progressPercent}
	fallingScores = {}, -- {player = clickCount}
	equilibriumHoldTimes = {}, -- {player = holdTimeInSeconds}
	gunHolder = nil, -- Player who has the gun
	killChallengeActive = false,
	winner = nil,
	gunRoundCounter = 0, -- Tracks rounds for alternating bullet/empty gun
}

-- ============================================
-- ACTIVE PLAYER TARGETING HELPERS
-- ============================================
-- Fire a RemoteEvent ONLY to active players in the current round
-- This ensures spectators and eliminated players don't receive UI events
local function fireToActivePlayers(remoteEvent, ...)
	local args = { ... }
	for _, activePlayer in pairs(gameState.currentPlayers) do
		if activePlayer and activePlayer.Parent then
			remoteEvent:FireClient(activePlayer, table.unpack(args))
		end
	end
end

-- Fire to a specific list of players (for cases where we have a custom list)
local function fireToPlayerList(remoteEvent, playerList, ...)
	local args = { ... }
	for _, targetPlayer in pairs(playerList) do
		if targetPlayer and targetPlayer.Parent then
			remoteEvent:FireClient(targetPlayer, table.unpack(args))
		end
	end
end

-- Remove an eliminated player from the active players list
-- Updates both gameState.currentPlayers and ActivePlayersRegistry
local function removeEliminatedPlayer(eliminatedPlayer)
	if not eliminatedPlayer then
		return
	end

	-- Remove from currentPlayers array
	for i = #gameState.currentPlayers, 1, -1 do
		if gameState.currentPlayers[i] == eliminatedPlayer then
			table.remove(gameState.currentPlayers, i)
			break
		end
	end

	-- Remove from registry
	ActivePlayersRegistry:RemovePlayer(eliminatedPlayer)

	print("[SERVER] Eliminated " .. eliminatedPlayer.Name .. " | Players remaining: " .. #gameState.currentPlayers)
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
local workspace = game:GetService("Workspace")

local function findChairsFolder()
	local theFive = workspace:WaitForChild("TheFive", 10)
	if theFive then
		return theFive:WaitForChild("Chairs", 10)
	end
	return nil
end

local function getAllSeats(chairsFolder)
	local seats = {}
	if not chairsFolder then
		return seats
	end

	for _, chair in pairs(chairsFolder:GetChildren()) do
		local seat = chair:FindFirstChild("Seat")
		if seat and seat:IsA("Seat") then
			table.insert(seats, seat)
		end
	end
	return seats
end

local function getSeatedPlayers(seats)
	local players = {}
	for _, seat in pairs(seats) do
		local occupant = seat.Occupant
		if occupant then
			local character = occupant.Parent
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				table.insert(players, player)
			end
		end
	end
	return players
end

local function broadcastTableUI(message)
	updateUIEvent:FireAllClients(message)
end

-- Store original jump powers to restore later
local originalJumpPowers = {}
local lockedPlayers = {}

-- Lock players in seats: disable jump (reset button disabled via client)
local function lockPlayersInSeats(players)
	print("[SERVER] Locking " .. #players .. " players in seats...")

	for _, player in pairs(players) do
		lockedPlayers[player] = true

		-- Disable jumping
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				originalJumpPowers[player] = humanoid.JumpPower
				humanoid.JumpPower = 0
				humanoid.JumpHeight = 0
				print("[SERVER] Disabled jump for " .. player.Name)
			end
		end
	end

	-- Tell ONLY participating clients to disable the reset button
	for _, player in pairs(players) do
		toggleResetButtonEvent:FireClient(player, false) -- false = disable reset button
		print("[SERVER] Disabled reset button for " .. player.Name)
	end
end

-- Unlock players: restore jump and re-enable reset button
local function unlockPlayers()
	print("[SERVER] Unlocking all players...")

	-- Store players before clearing to re-enable their reset buttons
	local playersToUnlock = {}
	for player, _ in pairs(lockedPlayers) do
		table.insert(playersToUnlock, player)

		-- Restore jump power
		if player and player.Parent and player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.JumpPower = originalJumpPowers[player] or 50
				humanoid.JumpHeight = 7.2 -- Default Roblox value
				print("[SERVER] Restored jump for " .. player.Name)
			end
		end
	end

	-- Clear stored data
	originalJumpPowers = {}
	lockedPlayers = {}

	-- Tell ONLY previously locked clients to re-enable the reset button
	for _, player in pairs(playersToUnlock) do
		if player and player.Parent then
			toggleResetButtonEvent:FireClient(player, true) -- true = enable reset button
			print("[SERVER] Enabled reset button for " .. player.Name)
		end
	end
end

-- Unseat all players from chairs
local function unseatAllPlayers(seats)
	for _, seat in pairs(seats) do
		local occupant = seat.Occupant
		if occupant then
			-- The occupant is a Humanoid
			occupant.Sit = false
			-- Also give a small wait to ensure the unseat processes
			task.defer(function()
				if occupant and occupant.Parent then
					occupant.Jump = true
				end
			end)
		end
	end
end

-- ============================================
-- MINIGAME PHASES
-- ============================================

-- Phase 1: Sequential player-by-player intro
local function showIntroText()
	print("[SERVER] Starting sequential intro phase...")

	-- Step 1: Show static background to ALL active players
	print("[SERVER] Showing intro background to all players")
	fireToActivePlayers(showIntroBackgroundEvent)

	-- Step 1.5: Tell active players to apply game lighting (client-side, per-player)
	print("[SERVER] Firing ApplyGameLighting to active players")
	fireToActivePlayers(applyGameLightingEvent)
	task.wait(1) -- Wait for clients to apply lighting

	-- Step 2: Play intro for each player one at a time
	for i, activePlayer in ipairs(gameState.currentPlayers) do
		if not activePlayer or not activePlayer.Parent then
			print("[SERVER] Skipping disconnected player at index " .. i)
			continue
		end

		print(
			"[SERVER] Playing intro for player " .. i .. "/" .. #gameState.currentPlayers .. ": " .. activePlayer.Name
		)

		-- Fire PlayPlayerIntro to ONLY this player
		playPlayerIntroEvent:FireClient(activePlayer)

		-- Wait for this player's PlayerIntroFinished callback
		local playerDone = false
		local finishedConnection
		finishedConnection = playerIntroFinishedEvent.OnServerEvent:Connect(function(signalingPlayer)
			if signalingPlayer == activePlayer then
				print("[SERVER] Intro finished for " .. activePlayer.Name)
				playerDone = true
			end
		end)

		-- Safety timeout per player (15 seconds)
		local PLAYER_INTRO_TIMEOUT = 15
		local elapsed = 0
		while not playerDone and elapsed < PLAYER_INTRO_TIMEOUT do
			-- Also break if player disconnected mid-intro
			if not activePlayer or not activePlayer.Parent then
				print(
					"[SERVER] Player "
						.. (activePlayer and activePlayer.Name or "?")
						.. " disconnected mid-intro, skipping"
				)
				break
			end
			task.wait(0.1)
			elapsed = elapsed + 0.1
		end

		finishedConnection:Disconnect()

		if not playerDone then
			warn("[SERVER] Intro timed out for " .. (activePlayer and activePlayer.Name or "?") .. " - moving to next")
		end
	end

	print("[SERVER] All player intros complete. Showing announcement text...")

	-- Step 3: Announcement text to all players (after all intros done)
	local message = "The game begins now.\n"
		.. "Each of you will face a challenge.\n"
		.. "The first to succeed will claim the weapon — and with it, 30 seconds to act.\n"
		.. "If no one falls, or no shot is taken, the cycle resets.\n"
		.. "The game continues until only one player remains.\n"
		.. "Prepare yourselves."
	print("[SERVER] Sending announcement text")

	fireToActivePlayers(showTypingTextEvent, message)

	-- Wait for any active player to confirm announcement text is done
	local introCompleted = false
	local connection
	connection = introSequenceCompleteEvent.OnServerEvent:Connect(function(signalingPlayer)
		for _, ap in pairs(gameState.currentPlayers) do
			if ap == signalingPlayer then
				print("[SERVER] Announcement complete signal from " .. signalingPlayer.Name)
				introCompleted = true
				break
			end
		end
	end)

	local MAX_WAIT = 30
	local elapsed = 0
	while not introCompleted and elapsed < MAX_WAIT do
		task.wait(0.1)
		elapsed = elapsed + 0.1
	end

	connection:Disconnect()

	if introCompleted then
		print("[SERVER] Announcement confirmed complete! Starting minigame...")
	else
		warn("[SERVER] Announcement timed out after " .. MAX_WAIT .. "s - proceeding anyway")
	end
end

-- Phase 2: Maze minigame (drag box through path)
local function runMazeMinigame()
	-- Reset progress
	gameState.mazeProgress = {}
	for _, player in pairs(gameState.currentPlayers) do
		gameState.mazeProgress[player] = 0
	end

	-- Start maze game on active players only
	fireToActivePlayers(startMazeGameEvent, gameState.currentPlayers)

	local winner = nil
	local gameEnded = false

	-- Listen for maze completion events
	local completeConnection
	completeConnection = playerMazeCompleteEvent.OnServerEvent:Connect(function(player)
		if gameEnded then
			return
		end
		if not gameState.mazeProgress[player] then
			return
		end

		-- First player to complete wins!
		winner = player
		gameEnded = true
		print("[SERVER] " .. player.Name .. " completed the maze!")
	end)

	-- Listen for progress updates (for broadcasting to other players)
	local progressConnection
	progressConnection = updateMazeProgressEvent.OnServerEvent:Connect(function(player, progress)
		if gameEnded then
			return
		end
		if gameState.mazeProgress[player] then
			gameState.mazeProgress[player] = progress
			-- Broadcast progress to active players
			fireToActivePlayers(updateMazeProgressEvent, player, progress)
		end
	end)

	-- Wait for winner or timeout
	local startTime = tick()
	while not gameEnded and (tick() - startTime) < MAZE_TIMEOUT do
		task.wait(0.1)
	end

	completeConnection:Disconnect()
	progressConnection:Disconnect()

	-- If no winner (timeout), pick the one with most progress
	if not winner then
		local maxProgress = 0
		for player, progress in pairs(gameState.mazeProgress) do
			if progress > maxProgress then
				maxProgress = progress
				winner = player
			end
		end
	end

	-- End maze game
	fireToActivePlayers(endMazeGameEvent, winner and winner.Name or "No one")
	task.wait(2)

	return winner
end

-- Phase 2 (alternate): Falling minigame (click falling elements)
local function runFallingMinigame()
	-- Reset scores
	gameState.fallingScores = {}
	for _, player in pairs(gameState.currentPlayers) do
		gameState.fallingScores[player] = 0
	end

	-- Start falling game on active players only
	fireToActivePlayers(startFallingGameEvent, gameState.currentPlayers)

	local winner = nil
	local gameEnded = false
	local elementIdCounter = 0

	-- Listen for element catch events
	local catchConnection
	catchConnection = playerCaughtElementEvent.OnServerEvent:Connect(function(player, elementId)
		if gameEnded then
			return
		end
		if not gameState.fallingScores[player] then
			return
		end

		gameState.fallingScores[player] = gameState.fallingScores[player] + 1
		local score = gameState.fallingScores[player]

		-- Broadcast progress to active players
		fireToActivePlayers(updateFallingProgressEvent, player, score)

		-- Check for winner
		if score >= FALLING_GOAL then
			winner = player
			gameEnded = true
			print("[SERVER] " .. player.Name .. " won the falling game with " .. score .. " catches!")
		end
	end)

	-- Spawn falling elements periodically
	local spawnConnection
	spawnConnection = task.spawn(function()
		while not gameEnded do
			elementIdCounter = elementIdCounter + 1
			local xPos = 0.1 + math.random() * 0.8 -- Random X position (10%-90%)
			local colorIndex = math.random(1, 5)

			-- Spawn on active players only
			fireToActivePlayers(spawnFallingElementEvent, elementIdCounter, xPos, colorIndex)

			-- Wait before next spawn (faster as time goes on)
			task.wait(0.4 + math.random() * 0.3) -- 0.4-0.7 seconds
		end
	end)

	-- Wait for winner or timeout
	local startTime = tick()
	while not gameEnded and (tick() - startTime) < FALLING_TIMEOUT do
		task.wait(0.1)
	end

	catchConnection:Disconnect()
	gameEnded = true -- Stop spawning

	-- If no winner (timeout), pick the one with most catches
	if not winner then
		local maxScore = 0
		for player, score in pairs(gameState.fallingScores) do
			if score > maxScore then
				maxScore = score
				winner = player
			end
		end
	end

	-- End falling game
	fireToActivePlayers(endFallingGameEvent, winner and winner.Name or "No one")
	task.wait(2)

	return winner
end

-- Phase 2 (alternate): Box filling minigame (match target number)
local function runBoxFillingMinigame()
	-- Generate random target (1-40)
	local targetNumber = math.random(1, 40)
	print("[SERVER] Box filling target: " .. targetNumber)

	-- Start box filling game on active players only with the target
	fireToActivePlayers(startBoxFillingGameEvent, gameState.currentPlayers, targetNumber)

	local winner = nil
	local gameEnded = false

	-- Listen for submit events
	local submitConnection
	submitConnection = playerBoxSubmitEvent.OnServerEvent:Connect(function(player, submittedTotal)
		if gameEnded then
			return
		end

		-- Check if player is in game
		local inGame = false
		for _, p in pairs(gameState.currentPlayers) do
			if p == player then
				inGame = true
				break
			end
		end
		if not inGame then
			return
		end

		print("[SERVER] " .. player.Name .. " submitted: " .. submittedTotal .. " (target: " .. targetNumber .. ")")

		-- Check if correct
		if submittedTotal == targetNumber then
			winner = player
			gameEnded = true
			print("[SERVER] " .. player.Name .. " won the box filling game!")
		end
	end)

	-- Wait for winner or timeout
	local startTime = tick()
	while not gameEnded and (tick() - startTime) < BOXFILLING_TIMEOUT do
		task.wait(0.1)
	end

	submitConnection:Disconnect()

	-- End box filling game
	fireToActivePlayers(endBoxFillingGameEvent, winner and winner.Name or "No one")
	task.wait(2)

	return winner
end

-- Phase 2 (alternate): Equilibrium balance minigame (hold balance for 3 seconds)
local function runEquilibriumMinigame()
	-- Reset hold times
	gameState.equilibriumHoldTimes = {}
	for _, player in pairs(gameState.currentPlayers) do
		gameState.equilibriumHoldTimes[player] = 0
	end

	-- Start equilibrium game on active players only
	fireToActivePlayers(startEquilibriumGameEvent, gameState.currentPlayers)

	local winner = nil
	local gameEnded = false

	-- Listen for win events (first player to hold 3 seconds continuous)
	local winConnection
	winConnection = equilibriumWinEvent.OnServerEvent:Connect(function(player)
		if gameEnded then
			return
		end
		-- Check if player is in game
		local inGame = false
		for _, p in pairs(gameState.currentPlayers) do
			if p == player then
				inGame = true
				break
			end
		end
		if not inGame then
			return
		end

		-- First player to win!
		winner = player
		gameEnded = true
		print("[SERVER] " .. player.Name .. " won the equilibrium game!")
	end)

	-- Listen for progress updates (for leaderboard/fallback)
	local progressConnection
	progressConnection = updateEquilibriumProgressEvent.OnServerEvent:Connect(function(player, holdTime)
		if gameEnded then
			return
		end
		if gameState.equilibriumHoldTimes[player] then
			gameState.equilibriumHoldTimes[player] = holdTime
		end
	end)

	-- Wait for winner or timeout
	local startTime = tick()
	while not gameEnded and (tick() - startTime) < EQUILIBRIUM_TIMEOUT do
		task.wait(0.1)
	end

	winConnection:Disconnect()
	progressConnection:Disconnect()

	-- If no winner (timeout), pick the one with most hold time
	if not winner then
		local maxHoldTime = 0
		for player, holdTime in pairs(gameState.equilibriumHoldTimes) do
			if holdTime > maxHoldTime then
				maxHoldTime = holdTime
				winner = player
			end
		end
	end

	-- End equilibrium game
	fireToActivePlayers(endEquilibriumGameEvent, winner and winner.Name or "No one")
	task.wait(2)

	return winner
end

-- Phase 2 (alternate): Color Rush minigame (fast reaction color matching)
local function runColorRushMinigame()
	print("[SERVER] Starting Color Rush minigame...")

	-- Generate random target color (1-25, now using extended palette)
	local targetColorIndex = math.random(1, 25)
	print("[SERVER] Target color index: " .. targetColorIndex)

	-- Start Color Rush game on active players only
	fireToActivePlayers(startColorRushGameEvent, gameState.currentPlayers)

	local winner = nil
	local gameEnded = false

	-- Send preview phase to active players (show target color)
	fireToActivePlayers(colorRushPreviewEvent, targetColorIndex)
	print("[SERVER] Preview phase started (3 seconds)")

	-- Wait for preview phase
	task.wait(COLORRUSH_PREVIEW_TIME)

	-- Generate 25 UNIQUE colors using Fisher-Yates shuffle
	-- Create array of all 25 color indices
	local availableColors = {}
	for i = 1, 25 do
		availableColors[i] = i
	end

	-- Fisher-Yates shuffle
	for i = 25, 2, -1 do
		local j = math.random(1, i)
		availableColors[i], availableColors[j] = availableColors[j], availableColors[i]
	end

	-- Ensure target color is in the grid (replace one random position with target)
	local targetFound = false
	local correctPosition = 0
	for i = 1, 25 do
		if availableColors[i] == targetColorIndex then
			targetFound = true
			correctPosition = i
			break
		end
	end

	-- If target wasn't in shuffled array (shouldn't happen but safety check)
	if not targetFound then
		correctPosition = math.random(1, 25)
		availableColors[correctPosition] = targetColorIndex
	end

	local colorDistribution = availableColors
	print("[SERVER] Correct position: " .. correctPosition)

	-- Send grid reveal to active players
	fireToActivePlayers(colorRushShowGridEvent, targetColorIndex, colorDistribution)
	print("[SERVER] Grid phase started with unique colors")

	-- Listen for player color selection events
	-- ALLOW multiple wrong guesses, only lock on correct
	local selectConnection
	selectConnection = playerColorSelectedEvent.OnServerEvent:Connect(function(player, isCorrect)
		if gameEnded then
			return
		end

		-- Check if player is in the game
		local inGame = false
		for _, p in pairs(gameState.currentPlayers) do
			if p == player then
				inGame = true
				break
			end
		end
		if not inGame then
			return
		end

		print("[SERVER] " .. player.Name .. " selected color. Correct: " .. tostring(isCorrect))

		if isCorrect then
			-- First correct selection wins!
			winner = player
			gameEnded = true
			print("[SERVER] " .. player.Name .. " wins Color Rush!")
		end
	end)

	-- Wait for winner or timeout
	local startTime = tick()
	while not gameEnded and (tick() - startTime) < COLORRUSH_TIMEOUT do
		task.wait(0.1)
	end

	selectConnection:Disconnect()

	-- If no winner (timeout), pick random player from participants
	if not winner and #gameState.currentPlayers > 0 then
		winner = gameState.currentPlayers[math.random(1, #gameState.currentPlayers)]
		print("[SERVER] Timeout - random winner: " .. winner.Name)
	end

	-- End Color Rush game
	fireToActivePlayers(endColorRushGameEvent, winner and winner.Name or "No one")
	task.wait(2)

	return winner
end

-- Phase 3: Prepare gun winner (gun is given later when timer starts)
local function prepareGunWinner(winner)
	if not winner then
		return false
	end

	-- Set the gun holder but don't give gun yet
	gameState.gunHolder = winner

	-- Show message that they won the maze challenge
	fireToActivePlayers(showGameAnnouncementEvent, winner.DisplayName .. " won the maze challenge!")
	task.wait(2)

	return true
end

-- Helper: Hide the table gun model (Workspace > TheFive > Gun)
local function hideTableGun()
	local theFive = workspace:FindFirstChild("TheFive")
	if theFive then
		local tableGun = theFive:FindFirstChild("Gun")
		if tableGun then
			for _, part in pairs(tableGun:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Transparency = 1
				end
			end
			print("[SERVER] Table gun hidden")
		end
	end
end

-- Helper: Show the table gun model (Workspace > TheFive > Gun)
local function showTableGun()
	local theFive = workspace:FindFirstChild("TheFive")
	if theFive then
		local tableGun = theFive:FindFirstChild("Gun")
		if tableGun then
			for _, part in pairs(tableGun:GetDescendants()) do
				if part:IsA("BasePart") then
					-- Restore to default (fully visible)
					part.Transparency = 0
				end
			end
			print("[SERVER] Table gun visible")
		end
	end
end

-- Helper: Actually give the gun to the holder
local function giveGunToHolder()
	local winner = gameState.gunHolder
	if not winner then
		return nil
	end

	-- Hide the table gun model when giving gun to player
	hideTableGun()

	-- Find the gun in ServerStorage
	local gunTemplate = ServerStorage:FindFirstChild("TheFiveGun")
	if not gunTemplate then
		warn("TheFiveGun not found in ServerStorage! Creating a placeholder.")
		gunTemplate = Instance.new("Tool")
		gunTemplate.Name = "TheFiveGun"
		gunTemplate.Parent = ServerStorage
	end

	-- Clone gun to winner's backpack
	local gunClone = gunTemplate:Clone()
	gunClone.Parent = winner.Backpack

	-- Increment round counter and determine if this should be an empty gun
	gameState.gunRoundCounter = gameState.gunRoundCounter + 1
	local isEmptyGun = (gameState.gunRoundCounter % 2 == 0) -- Even rounds = empty gun

	-- Set ammo via Tool Attribute (gun script reads this on equip)
	if isEmptyGun then
		print("[SERVER] Round " .. gameState.gunRoundCounter .. ": Giving EMPTY gun")
		gunClone:SetAttribute("InitialAmmo", 0)
	else
		print("[SERVER] Round " .. gameState.gunRoundCounter .. ": Giving gun with 1 bullet")
		gunClone:SetAttribute("InitialAmmo", 1)
	end

	-- Auto-equip the gun
	if winner.Character then
		local humanoid = winner.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:EquipTool(gunClone)
			print("[SERVER] Auto-equipped gun for " .. winner.Name)
		end
	end

	return gunClone
end

-- Remove gun only (for quick restart, keeps players seated)
local function removeGunOnly()
	-- Show the table gun model again
	showTableGun()

	-- Clear any active highlights immediately
	clearAllHighlights()

	-- Fire force reset to active players
	fireToActivePlayers(forceGunResetEvent)

	-- Remove gun from gun holder
	if gameState.gunHolder then
		local character = gameState.gunHolder.Character
		local backpack = gameState.gunHolder.Backpack

		-- First, unequip the tool
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:UnequipTools()
				task.wait(0.1)
			end

			local gunInChar = character:FindFirstChild("TheFiveGun")
			if gunInChar then
				gunInChar:Destroy()
			end
		end

		-- Destroy gun from backpack
		if backpack then
			local gunInBackpack = backpack:FindFirstChild("TheFiveGun")
			if gunInBackpack then
				gunInBackpack:Destroy()
			end
		end
	end

	-- Reset gun holder but keep players
	gameState.gunHolder = nil
	gameState.mazeProgress = {}
end

-- Phase 4: Kill challenge (ONE BULLET SYSTEM)
local function runKillChallenge()
	gameState.killChallengeActive = true
	local gunHolder = gameState.gunHolder

	if not gunHolder then
		return nil
	end

	-- Track kill and shot status
	local gotKill = false
	local shotUsed = false
	local killedPlayer = nil -- Track WHO was killed for progressive elimination

	-- Get ShotUsedEvent and EmptyClickEvent for shot/click detection
	local gameEventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local shotUsedEvent = gameEventsFolder and gameEventsFolder:FindFirstChild("ShotUsedEvent")
	local emptyClickEvent = gameEventsFolder and gameEventsFolder:FindFirstChild("EmptyClickEvent")

	-- Set up death connections BEFORE giving gun
	-- Also mark all targets with IsHighlightedTarget attribute for guaranteed headshot kills
	local deathConnections = {}
	for _, player in pairs(gameState.currentPlayers) do
		if player ~= gunHolder and player.Character then
			-- Mark this player as a highlighted target (guaranteed headshot kill)
			player.Character:SetAttribute("IsHighlightedTarget", true)
			print("[SERVER] Marked " .. player.Name .. " as highlighted target")

			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				local conn = humanoid.Died:Connect(function()
					if gameState.killChallengeActive then
						gotKill = true
						killedPlayer = player -- Track the eliminated player
						print("[SERVER] Player killed: " .. player.Name)
					end
				end)
				table.insert(deathConnections, conn)
			end
		end
	end

	-- Set up shot detection - handles both real shots and empty clicks
	local shotConnection = nil
	local emptyClickConnection = nil

	if shotUsedEvent then
		shotConnection = shotUsedEvent.Event:Connect(function(player)
			if player == gunHolder and gameState.killChallengeActive then
				shotUsed = true
				print("[SERVER] Real shot used by " .. gunHolder.Name)
			end
		end)
	end

	-- Empty click detection - treat same as shot used for flow purposes
	if emptyClickEvent then
		emptyClickConnection = emptyClickEvent.Event:Connect(function(player)
			if player == gunHolder and gameState.killChallengeActive then
				shotUsed = true -- Use same flag for unified handling
				print("[SERVER] Empty click by " .. gunHolder.Name)
			end
		end)
	end

	-- Show kill challenge message to gun holder
	showGameAnnouncementEvent:FireClient(gunHolder, "ONE BULLET - Make it count!")

	-- Give the gun NOW (when timer is about to start)
	giveGunToHolder()
	fireToActivePlayers(showGameAnnouncementEvent, gunHolder.DisplayName .. " received the gun!")

	-- Start countdown timer
	-- Loop exits when: time runs out OR kill happens OR shot is used
	local startTime = tick()
	while (tick() - startTime) < KILL_CHALLENGE_TIME and not gotKill and not shotUsed do
		local remaining = KILL_CHALLENGE_TIME - (tick() - startTime)
		if gunHolder then
			showKillTimerEvent:FireClient(gunHolder, remaining)
		end
		task.wait(0.1)
	end

	-- IMMEDIATELY stop kill challenge when shot is used (timer stops instantly)
	gameState.killChallengeActive = false

	-- Cleanup connections IMMEDIATELY
	for _, conn in pairs(deathConnections) do
		conn:Disconnect()
	end
	if shotConnection then
		shotConnection:Disconnect()
	end
	if emptyClickConnection then
		emptyClickConnection:Disconnect()
	end

	-- Clear IsHighlightedTarget attribute from all players
	for _, player in pairs(gameState.currentPlayers) do
		if player.Character then
			player.Character:SetAttribute("IsHighlightedTarget", nil)
		end
	end
	print("[SERVER] Cleared highlighted target attributes")

	-- Wait 1 second after shot (real or empty) before proceeding
	if shotUsed then
		task.wait(1)

		-- Check if kill happened during the 1 second delay
		-- (gotKill may have been set by death connection)
	end

	-- Determine outcome
	if gotKill then
		-- Gun holder successfully eliminated someone
		-- Return info about who was killed for progressive elimination
		return { result = "kill", gunHolder = gunHolder, victim = killedPlayer }
	elseif shotUsed then
		-- Shot was fired (real bullet or empty click) but no kill
		-- 1. Remove the gun after 1 second delay (already waited above)
		removeGunOnly()

		-- 2. Fire the ForceGunReset event
		fireToActivePlayers(forceGunResetEvent)

		-- 3. Return "miss" for quick restart (no unseat, no full cleanup)
		return "miss"
	else
		-- Time ran out without firing
		fireToActivePlayers(showGameAnnouncementEvent, "Time's up! No one was eliminated. Restarting round...")
		task.wait(2)
		return "timeout"
	end
end

-- Phase 5: Show winner via cinematic Announcements UI (typing effect)
local function showWinner(winner)
	if winner then
		local winnerText = "Congratulations.\n"
			.. "You have outlasted them all and claimed victory.\n"
			.. "Well done, champion."
		fireToActivePlayers(showWinnerAnnouncementEvent, winnerText)
	else
		fireToActivePlayers(showWinnerAnnouncementEvent, "No Winner This Round")
	end
	-- Wait for cinematic typing effect to complete
	task.wait(10)
end

-- Cleanup after round
local function cleanupRound(seats)
	-- Restore lighting: winner gets background-masked transition
	-- Non-winners get their lighting restored via hardCleanup (GameFullyEnded below)
	if gameState.winner then
		restoreDefaultWithBackgroundEvent:FireClient(gameState.winner)
	end

	-- Deactivate round protection (border wall + unlock chairs)
	RoundProtectionSystem:EndRoundProtection()

	-- Signal clients that game has FULLY ended (hard-stop Animation 3 + all animations)
	gameFullyEndedEvent:FireAllClients()

	fireToActivePlayers(hideAllUIEvent)

	-- Show the table gun model (in case it was hidden)
	showTableGun()

	-- Unlock players: restore jump and respawn abilities
	unlockPlayers()

	-- Clear any active highlights immediately
	clearAllHighlights()

	-- Fire force reset to active players to ensure cleanup
	fireToActivePlayers(forceGunResetEvent)

	-- Remove gun from gun holder - MUST unequip before destroying
	if gameState.gunHolder then
		local character = gameState.gunHolder.Character
		local backpack = gameState.gunHolder.Backpack

		-- First, unequip the tool (this triggers the Unequipped event on the client)
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:UnequipTools()
				task.wait(0.1) -- Small delay to allow unequip event to process
			end

			-- Destroy gun from character (shouldn't be there after unequip, but just in case)
			local gunInChar = character:FindFirstChild("TheFiveGun")
			if gunInChar then
				gunInChar:Destroy()
			end
		end

		-- Destroy gun from backpack
		if backpack then
			local gunInBackpack = backpack:FindFirstChild("TheFiveGun")
			if gunInBackpack then
				gunInBackpack:Destroy()
			end
		end
	end

	-- Force all players to stand up from chairs
	if seats then
		print("[SERVER] Unseating all players...")
		unseatAllPlayers(seats)
	end

	-- Reset state
	gameState.currentPlayers = {}
	gameState.mazeProgress = {}
	gameState.gunHolder = nil
	gameState.winner = nil
	gameState.isGameRunning = false
	gameState.isWaiting = true

	-- Reset UI to waiting mode (will show player count on next loop iteration)
	broadcastTableUI("Round ended - Waiting for players...")
end

-- ============================================
-- MAIN GAME LOOP
-- ============================================
local function runWaitingSystem()
	local chairsFolder = findChairsFolder()
	if not chairsFolder then
		warn("Could not find Chairs folder!")
		return
	end

	local seats = getAllSeats(chairsFolder)
	print("Found " .. #seats .. " seats")

	while true do
		-- WAITING STATE
		while gameState.isWaiting do
			local seatedPlayers = getSeatedPlayers(seats)
			local count = #seatedPlayers

			broadcastTableUI("Waiting for players: " .. count .. "/" .. MIN_PLAYERS_REQUIRED)

			if count >= MIN_PLAYERS_REQUIRED then
				gameState.currentPlayers = seatedPlayers
				-- Update the shared registry for cross-script access
				ActivePlayersRegistry:SetActivePlayers(seatedPlayers)
				gameState.isWaiting = false
				gameState.isCountingDown = true
			end

			task.wait(0.1)
		end

		-- COUNTDOWN STATE
		if gameState.isCountingDown then
			broadcastTableUI("Game starting...")
			task.wait(1)

			local countdownStart = tick()
			local countdownEnd = countdownStart + COUNTDOWN_TIME

			while tick() < countdownEnd do
				local remaining = countdownEnd - tick()
				local seatedPlayers = getSeatedPlayers(seats)

				if #seatedPlayers < MIN_PLAYERS_REQUIRED then
					broadcastTableUI("Player left! Returning to lobby...")
					task.wait(1)
					gameState.isWaiting = true
					gameState.isCountingDown = false
					break
				end

				gameState.currentPlayers = seatedPlayers
				-- Keep registry synced during countdown as players may join/leave
				ActivePlayersRegistry:SetActivePlayers(seatedPlayers)
				local formattedTime = string.format("Starting in %.2f", remaining)
				broadcastTableUI(formattedTime)

				task.wait(0.01)
			end

			if gameState.isCountingDown then
				gameState.isCountingDown = false
				gameState.isGameRunning = true
				-- FINAL sync of registry before game runs
				ActivePlayersRegistry:SetActivePlayers(gameState.currentPlayers)
				print("[SERVER] Final active player list set: " .. #gameState.currentPlayers .. " players")
			end
		end

		-- GAME RUNNING STATE
		if gameState.isGameRunning then
			print("[SERVER] ==========================================")
			print("[SERVER] GAME RUNNING STATE STARTED")
			print("[SERVER] Current players: " .. #gameState.currentPlayers)

			broadcastTableUI("In Progress")

			-- Lock players in seats: disable jump and block respawn
			lockPlayersInSeats(gameState.currentPlayers)

			-- Activate round protection (border wall + lock empty chairs)
			RoundProtectionSystem:StartRoundProtection()

			-- Players stay seated during the game
			print("[SERVER] Players remain seated...")
			task.wait(0.5)

			-- Phase 1: Intro text
			print("[SERVER] === PHASE 1: INTRO TEXT ===")
			showIntroText()

			local roundComplete = false
			while not roundComplete do
				-- Select minigame (testing flag forces Color Rush, otherwise random)
				local selectedMinigame
				if TESTING_FORCE_COLOR_RUSH then
					selectedMinigame = "colorrush"
				else
					selectedMinigame = MINIGAMES[math.random(1, #MINIGAMES)]
				end
				print("[SERVER] === PHASE 2: " .. string.upper(selectedMinigame) .. " MINIGAME ===")

				local minigameWinner = nil

				if selectedMinigame == "maze" then
					minigameWinner = runMazeMinigame()
				elseif selectedMinigame == "falling" then
					minigameWinner = runFallingMinigame()
				elseif selectedMinigame == "boxfilling" then
					minigameWinner = runBoxFillingMinigame()
				elseif selectedMinigame == "equilibrium" then
					minigameWinner = runEquilibriumMinigame()
				elseif selectedMinigame == "colorrush" then
					minigameWinner = runColorRushMinigame()
				end

				print("[SERVER] Minigame winner: " .. (minigameWinner and minigameWinner.Name or "nil"))

				if minigameWinner then
					-- Phase 3: Prepare gun winner (show message, don't give gun yet)
					print("[SERVER] === PHASE 3: PREPARE GUN WINNER ===")
					prepareGunWinner(minigameWinner)

					-- Phase 4: Kill challenge
					print("[SERVER] === PHASE 4: KILL CHALLENGE ===")
					local killResult = runKillChallenge()

					-- Handle the result based on type
					if type(killResult) == "string" then
						-- Timeout or miss - quick restart without elimination
						if killResult == "timeout" or killResult == "miss" then
							print("[SERVER] Kill challenge ended - quick restart!")
							if killResult == "timeout" then
								removeGunOnly()
							end
							fireToActivePlayers(showGameAnnouncementEvent, "Restarting round...")
							task.wait(1)
							-- Loop continues - back to minigame
						end
					elseif type(killResult) == "table" and killResult.result == "kill" then
						-- Someone was eliminated!
						local victim = killResult.victim
						local shooter = killResult.gunHolder

						print("[SERVER] === ELIMINATION ===")
						print(
							"[SERVER] "
								.. (shooter and shooter.Name or "???")
								.. " eliminated "
								.. (victim and victim.Name or "???")
						)

						-- Remove the eliminated player from active players
						if victim then
							removeEliminatedPlayer(victim)
						end

						-- Remove the gun from the shooter
						removeGunOnly()
						fireToActivePlayers(forceGunResetEvent)

						-- Check if only 1 player remains → THEY WIN!
						if #gameState.currentPlayers == 1 then
							local finalWinner = gameState.currentPlayers[1]
							gameState.winner = finalWinner
							print("[SERVER] === FINAL WINNER: " .. finalWinner.Name .. " ===")
							-- Final winner uses cinematic Announcements UI (not GameAnnouncements)
							showWinner(finalWinner)
							roundComplete = true
						elseif #gameState.currentPlayers > 1 then
							-- More players remain - announce elimination and continue
							print("[SERVER] " .. #gameState.currentPlayers .. " players remaining - continuing...")
							fireToActivePlayers(
								showGameAnnouncementEvent,
								(victim and victim.DisplayName or "Player")
									.. " eliminated! "
									.. #gameState.currentPlayers
									.. " remaining"
							)
							task.wait(2)
						-- Loop continues to next minigame round
						else
							-- No players left (shouldn't happen)
							print("[SERVER] ERROR: No players remaining!")
							roundComplete = true
						end
					else
						-- Unknown result
						print("[SERVER] Unknown kill challenge result")
						roundComplete = true
					end
				else
					print("[SERVER] No maze winner found!")
					fireToActivePlayers(showGameAnnouncementEvent, "No winner - not enough participation!")
					task.wait(2)
					roundComplete = true -- Exit loop on no participation
				end
			end

			-- Cleanup and reset (only after actual completion)
			print("[SERVER] Cleaning up round...")
			broadcastTableUI("Game Over! Resetting...")
			task.wait(2)
			cleanupRound(seats)
			print("[SERVER] Round cleanup complete!")
		end

		task.wait()
	end
end

-- Start the system
runWaitingSystem()
