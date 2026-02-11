--[[
    TableUIHandler (Local Script)
    ==============================
    LOCATION: StarterPlayerScripts
    
    Handles all UI for the minigame:
    - Table billboard text
    - Typing effect intro
    - Maze game UI (drag box through path)
    - Falling elements game (modular)
    - Kill timer
    - Winner display
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local workspace = game:GetService("Workspace")

-- Wait for RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
if not remoteEvents then
	warn("RemoteEvents folder not found!")
	return
end

-- Get all remote events
local updateUIEvent = remoteEvents:WaitForChild("UpdateTableUI")
local showTypingTextEvent = remoteEvents:WaitForChild("ShowTypingText")
local startMazeGameEvent = remoteEvents:WaitForChild("StartMazeGame")
local updateMazeProgressEvent = remoteEvents:WaitForChild("UpdateMazeProgress")
local endMazeGameEvent = remoteEvents:WaitForChild("EndMazeGame")
local playerMazeCompleteEvent = remoteEvents:WaitForChild("PlayerMazeComplete")
local showCenterTextEvent = remoteEvents:WaitForChild("ShowCenterText") -- Legacy
local showGameAnnouncementEvent = remoteEvents:WaitForChild("ShowGameAnnouncement")
local showKillTimerEvent = remoteEvents:WaitForChild("ShowKillTimer")
local hideAllUIEvent = remoteEvents:WaitForChild("HideAllUI")
local forceGunResetEvent = remoteEvents:WaitForChild("ForceGunReset")

-- Falling minigame events
local startFallingGameEvent = remoteEvents:WaitForChild("StartFallingGame")
local endFallingGameEvent = remoteEvents:WaitForChild("EndFallingGame")
local playerCaughtElementEvent = remoteEvents:WaitForChild("PlayerCaughtElement")
local updateFallingProgressEvent = remoteEvents:WaitForChild("UpdateFallingProgress")
local spawnFallingElementEvent = remoteEvents:WaitForChild("SpawnFallingElement")

-- Box filling minigame events
local startBoxFillingGameEvent = remoteEvents:WaitForChild("StartBoxFillingGame")
local playerBoxSubmitEvent = remoteEvents:WaitForChild("PlayerBoxSubmit")
local endBoxFillingGameEvent = remoteEvents:WaitForChild("EndBoxFillingGame")

-- Equilibrium (balance) minigame events
local startEquilibriumGameEvent = remoteEvents:WaitForChild("StartEquilibriumGame")
local equilibriumWinEvent = remoteEvents:WaitForChild("EquilibriumWin")
local endEquilibriumGameEvent = remoteEvents:WaitForChild("EndEquilibriumGame")
local updateEquilibriumProgressEvent = remoteEvents:WaitForChild("UpdateEquilibriumProgress")

-- Color Rush minigame events
local startColorRushGameEvent = remoteEvents:WaitForChild("StartColorRushGame")
local endColorRushGameEvent = remoteEvents:WaitForChild("EndColorRushGame")

-- Load Color Rush module (initialization happens after UI is created)
local ColorRushMinigame =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Minigames"):WaitForChild("ColorRushMinigame"))

-- ============================================
-- UI CREATION
-- ============================================

-- Reference the pre-built MinigameUI from StarterGui
local screenGui = playerGui:WaitForChild("MinigameUI")


-- Center text label (for typing effect and messages)
local centerTextLabel = Instance.new("TextLabel")
centerTextLabel.Name = "CenterText"
centerTextLabel.Size = UDim2.new(0.8, 0, 0.15, 0)
centerTextLabel.Position = UDim2.new(0.1, 0, 0.2, 0)
centerTextLabel.BackgroundTransparency = 1
centerTextLabel.Font = Enum.Font.GothamBold
centerTextLabel.TextSize = 48
centerTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
centerTextLabel.TextStrokeTransparency = 0.5
centerTextLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
centerTextLabel.Text = ""
centerTextLabel.Visible = false
centerTextLabel.Parent = screenGui

-- Initialize Color Rush module (after centerTextLabel is created)
ColorRushMinigame:Init()

-- ============================================
-- GAME ANNOUNCEMENTS LABEL (from StartIntro ScreenGui)
-- ============================================
local gameAnnouncementsLabel = nil
local announcementHideThread = nil

task.spawn(function()
	local startIntro = playerGui:WaitForChild("StartIntro", 10)
	if startIntro then
		gameAnnouncementsLabel = startIntro:WaitForChild("GameAnnouncements", 10)
		if gameAnnouncementsLabel then
			gameAnnouncementsLabel.Text = ""
			gameAnnouncementsLabel.Visible = false
			-- Ensure text is always readable, wraps properly, and stays centered
			gameAnnouncementsLabel.TextWrapped = true
			gameAnnouncementsLabel.TextScaled = true
			gameAnnouncementsLabel.TextXAlignment = Enum.TextXAlignment.Center
			gameAnnouncementsLabel.TextYAlignment = Enum.TextYAlignment.Center
			-- Constrain auto-scaling: min 16px (readable), max 28px (clear)
			if not gameAnnouncementsLabel:FindFirstChildOfClass("UITextSizeConstraint") then
				local sizeConstraint = Instance.new("UITextSizeConstraint")
				sizeConstraint.MinTextSize = 16
				sizeConstraint.MaxTextSize = 28
				sizeConstraint.Parent = gameAnnouncementsLabel
			end
			print("[CLIENT] GameAnnouncements label found")
		else
			warn("[CLIENT] GameAnnouncements TextLabel not found in StartIntro!")
		end
	else
		warn("[CLIENT] StartIntro ScreenGui not found!")
	end
end)

-- Helper: Show game announcement with auto-hide
local function showGameAnnouncement(message, duration)
	if not gameAnnouncementsLabel then
		warn("[CLIENT] GameAnnouncements label not available")
		return
	end

	-- Cancel any existing hide timer
	if announcementHideThread then
		task.cancel(announcementHideThread)
		announcementHideThread = nil
	end

	gameAnnouncementsLabel.Text = message
	gameAnnouncementsLabel.Visible = true

	local hideDelay = duration or 3
	announcementHideThread = task.delay(hideDelay, function()
		if gameAnnouncementsLabel then
			gameAnnouncementsLabel.Visible = false
			gameAnnouncementsLabel.Text = ""
		end
		announcementHideThread = nil
	end)
end

local function hideGameAnnouncement()
	if announcementHideThread then
		task.cancel(announcementHideThread)
		announcementHideThread = nil
	end
	if gameAnnouncementsLabel then
		gameAnnouncementsLabel.Visible = false
		gameAnnouncementsLabel.Text = ""
	end
end

-- Connect Color Rush events
startColorRushGameEvent.OnClientEvent:Connect(function(participatingPlayers)
	print("[CLIENT] Received StartColorRushGame! Players: " .. #participatingPlayers)
	hideGameAnnouncement()
	ColorRushMinigame:Start(participatingPlayers)
end)

endColorRushGameEvent.OnClientEvent:Connect(function(winnerName)
	print("[CLIENT] Color Rush ended - winner: " .. tostring(winnerName))
	ColorRushMinigame:Stop()
	showGameAnnouncement(winnerName .. " wins Color Rush!")
end)

-- ============================================
-- MAZE GAME UI
-- ============================================

-- ============================================
-- MAZE GAME UI (references pre-built GUI from StarterGui)
-- ============================================

-- Maze container (main game area)
local mazeContainer = screenGui:WaitForChild("MazeContainer")

-- Maze path area (where the actual maze is drawn)
local mazeArea = mazeContainer:WaitForChild("MazeArea")

-- Start zone (green) - TOP LEFT
local startZone = mazeArea:WaitForChild("StartZone")

-- End zone (gold) - BOTTOM LEFT
local endZone = mazeArea:WaitForChild("EndZone")

-- Collect wall frames from MazeArea
local walls = {}
for _, child in pairs(mazeArea:GetChildren()) do
	if child:IsA("Frame") and child.Name:match("^Wall") then
		table.insert(walls, child)
	end
end

-- Draggable box (player's game piece)
local dragBox = mazeArea:WaitForChild("DragBox")

-- Feedback label (shows "RESET!" or "SUCCESS!")
local feedbackLabel = mazeArea:WaitForChild("Feedback")

-- Progress container (shows all players' progress)
local progressContainer = mazeContainer:WaitForChild("ProgressContainer")

-- Kill timer display
local killTimerLabel = Instance.new("TextLabel")
killTimerLabel.Name = "KillTimer"
killTimerLabel.Size = UDim2.new(0.4, 0, 0.1, 0)
killTimerLabel.Position = UDim2.new(0.3, 0, 0.05, 0)
killTimerLabel.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
killTimerLabel.BackgroundTransparency = 0.3
killTimerLabel.Font = Enum.Font.GothamBold
killTimerLabel.TextSize = 36
killTimerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
killTimerLabel.Text = "30.0"
killTimerLabel.Visible = false
killTimerLabel.Parent = screenGui

local killTimerCorner = Instance.new("UICorner")
killTimerCorner.CornerRadius = UDim.new(0, 10)
killTimerCorner.Parent = killTimerLabel

-- ============================================
-- TABLE UI (BILLBOARD)
-- ============================================
local function findTextLabel()
	local theFive = workspace:WaitForChild("TheFive", 10)
	if not theFive then
		return nil
	end

	local tableUIFolder = theFive:WaitForChild("TableUI", 10)
	if not tableUIFolder then
		return nil
	end

	local billboardGui = tableUIFolder:WaitForChild("TableUI", 10)
	if not billboardGui then
		return nil
	end

	return billboardGui:WaitForChild("TXT", 10)
end

local tableTextLabel = findTextLabel()

updateUIEvent.OnClientEvent:Connect(function(message)
	if tableTextLabel then
		tableTextLabel.Text = message
	end
end)

-- ============================================
-- TYPING EFFECT (REMOVED - Handled by CinematicIntro)
-- ============================================
-- Legacy code removed to prevent conflict with CinematicIntro system

-- ============================================
-- CENTER TEXT (LEGACY - Now handled by GameAnnouncements)
-- ============================================

-- ShowGameAnnouncement handler (new centralized system)
showGameAnnouncementEvent.OnClientEvent:Connect(function(message, duration)
	print("[CLIENT] Received ShowGameAnnouncement: " .. message)
	showGameAnnouncement(message, duration)
end)

-- ============================================
-- MAZE GAME LOGIC
-- ============================================
local progressBars = {} -- {playerName = {frame, bar, label, percent}}
local mazeActive = false
local isDragging = false
local startPosition = UDim2.new(0.04, 0, 0.05, 0)

-- Get absolute position and size of a UI element
local function getAbsoluteRect(element)
	return {
		x = element.AbsolutePosition.X,
		y = element.AbsolutePosition.Y,
		width = element.AbsoluteSize.X,
		height = element.AbsoluteSize.Y,
	}
end

-- Check if two rectangles overlap
local function rectsOverlap(r1, r2)
	return not (r1.x + r1.width < r2.x or r2.x + r2.width < r1.x or r1.y + r1.height < r2.y or r2.y + r2.height < r1.y)
end

-- Check if box is inside a zone
local function isInsideZone(boxRect, zoneRect)
	local boxCenterX = boxRect.x + boxRect.width / 2
	local boxCenterY = boxRect.y + boxRect.height / 2
	return boxCenterX >= zoneRect.x
		and boxCenterX <= zoneRect.x + zoneRect.width
		and boxCenterY >= zoneRect.y
		and boxCenterY <= zoneRect.y + zoneRect.height
end

-- Reset box to start position with feedback
local function resetBox()
	isDragging = false

	-- Show reset feedback
	feedbackLabel.Text = "RESET!"
	feedbackLabel.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	feedbackLabel.Visible = true

	-- Flash the box red
	local originalColor = dragBox.BackgroundColor3
	dragBox.BackgroundColor3 = Color3.fromRGB(255, 80, 80)

	-- Animate box back to start
	local tween = TweenService:Create(dragBox, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = startPosition,
	})
	tween:Play()

	task.delay(0.3, function()
		dragBox.BackgroundColor3 = originalColor
	end)

	task.delay(0.8, function()
		feedbackLabel.Visible = false
	end)
end

-- Calculate progress (distance from start to end)
local function calculateProgress()
	local boxPos = dragBox.AbsolutePosition
	local startPos = startZone.AbsolutePosition
	local endPos = endZone.AbsolutePosition

	local totalDistance = math.sqrt((endPos.X - startPos.X) ^ 2 + (endPos.Y - startPos.Y) ^ 2)
	local currentDistance = math.sqrt((boxPos.X - startPos.X) ^ 2 + (boxPos.Y - startPos.Y) ^ 2)

	return math.clamp(currentDistance / totalDistance, 0, 1)
end

-- Check for wall collisions
local function checkWallCollision()
	local boxRect = getAbsoluteRect(dragBox)

	for _, wall in pairs(walls) do
		local wallRect = getAbsoluteRect(wall)
		if rectsOverlap(boxRect, wallRect) then
			return true
		end
	end

	return false
end

-- Check for end zone
local function checkEndZone()
	local boxRect = getAbsoluteRect(dragBox)
	local endRect = getAbsoluteRect(endZone)
	return isInsideZone(boxRect, endRect)
end

-- Create progress bar for a player
local function createProgressBar(playerName, index, total)
	local barWidth = math.min(0.2, 0.9 / math.max(total, 1))

	local frame = Instance.new("Frame")
	frame.Name = playerName
	frame.Size = UDim2.new(barWidth, -10, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = progressContainer

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Text = playerName
	nameLabel.Parent = frame

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0.4, 0)
	barBg.Position = UDim2.new(0, 0, 0.45, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	barBg.Parent = frame

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0, 6)
	barBgCorner.Parent = barBg

	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
	bar.Parent = barBg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = bar

	progressBars[playerName] = { frame = frame, bar = bar }
end

-- Handle drag start
dragBox.InputBegan:Connect(function(input)
	if not mazeActive then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = true
	end
end)

-- Handle drag end
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = false
	end
end)

-- Handle drag movement
UserInputService.InputChanged:Connect(function(input)
	if not mazeActive or not isDragging then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local mousePos = input.Position
		local areaPos = mazeArea.AbsolutePosition
		local areaSize = mazeArea.AbsoluteSize
		local boxSize = dragBox.AbsoluteSize

		-- Calculate new position relative to maze area
		local relX = (mousePos.X - areaPos.X - boxSize.X / 2) / areaSize.X
		local relY = (mousePos.Y - areaPos.Y - boxSize.Y / 2) / areaSize.Y

		-- Clamp to stay within maze area
		relX = math.clamp(relX, 0, 1 - boxSize.X / areaSize.X)
		relY = math.clamp(relY, 0, 1 - boxSize.Y / areaSize.Y)

		dragBox.Position = UDim2.new(relX, 0, relY, 0)

		-- Check for wall collision
		if checkWallCollision() then
			resetBox()
			return
		end

		-- Check for end zone
		if checkEndZone() then
			mazeActive = false
			isDragging = false

			-- Show success feedback
			feedbackLabel.Text = "SUCCESS!"
			feedbackLabel.BackgroundColor3 = Color3.fromRGB(50, 200, 80)
			feedbackLabel.Visible = true

			-- Flash green
			dragBox.BackgroundColor3 = Color3.fromRGB(50, 200, 80)

			-- Fire completion event
			playerMazeCompleteEvent:FireServer()
			print("[CLIENT] Maze completed!")
		end

		-- Update progress
		local progress = calculateProgress()
		updateMazeProgressEvent:FireServer(progress)
	end
end)

-- Start maze game event
startMazeGameEvent.OnClientEvent:Connect(function(participatingPlayers)
	print("[CLIENT] Received StartMazeGame! Players: " .. tostring(#participatingPlayers))

	-- Clear old progress bars
	for _, data in pairs(progressBars) do
		if data.frame then
			data.frame:Destroy()
		end
	end
	progressBars = {}

	-- Hide game announcement
	hideGameAnnouncement()

	-- Reset drag box
	dragBox.Position = startPosition
	dragBox.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
	feedbackLabel.Visible = false

	-- Create progress bars for each player
	for i, p in ipairs(participatingPlayers) do
		createProgressBar(p.DisplayName, i, #participatingPlayers)
	end

	-- Show maze UI
	mazeContainer.Visible = true
	mazeActive = true
end)

-- Update progress event
updateMazeProgressEvent.OnClientEvent:Connect(function(progressPlayer, progress)
	local playerName = progressPlayer.DisplayName
	if progressBars[playerName] then
		local bar = progressBars[playerName].bar
		TweenService:Create(bar, TweenInfo.new(0.1), { Size = UDim2.new(progress, 0, 1, 0) }):Play()
	end
end)

-- End maze game event
endMazeGameEvent.OnClientEvent:Connect(function(winnerName)
	mazeActive = false
	isDragging = false
	mazeContainer.Visible = false

	centerTextLabel.Visible = false

	showGameAnnouncement(winnerName .. " wins the maze challenge!")
end)

-- ============================================
-- KILL TIMER
-- ============================================
showKillTimerEvent.OnClientEvent:Connect(function(remaining)
	killTimerLabel.Visible = true
	killTimerLabel.Text = string.format("%.1f", remaining)

	-- Change color when low
	if remaining <= 10 then
		killTimerLabel.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	else
		killTimerLabel.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	end
end)

-- ============================================
-- HIDE ALL UI
-- ============================================
hideAllUIEvent.OnClientEvent:Connect(function()
	-- Cancel any pending announcement hide timer
	if announcementHideThread then
		task.cancel(announcementHideThread)
		announcementHideThread = nil
	end

	hideGameAnnouncement()
	centerTextLabel.Visible = false
	centerTextLabel.Text = ""
	mazeContainer.Visible = false
	killTimerLabel.Visible = false
	mazeActive = false
	isDragging = false
end)

-- ============================================
-- FORCE GUN RESET (Comprehensive cleanup)
-- ============================================
forceGunResetEvent.OnClientEvent:Connect(function()
	print("[CLIENT] Force gun reset received - cleaning up all gun-related state")

	-- Hide kill timer immediately
	killTimerLabel.Visible = false

	local camera = workspace.CurrentCamera
	local character = player.Character

	-- Reset UserInputService settings
	local uis = game:GetService("UserInputService")
	uis.MouseIconEnabled = true
	uis.MouseDeltaSensitivity = 1

	-- Reset camera settings
	if camera then
		camera.FieldOfView = 70 -- Default FOV
	end

	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			-- Reset humanoid camera offset
			humanoid.CameraOffset = Vector3.new()
			-- Restore auto-rotate
			humanoid.AutoRotate = true
		end

		-- Reset limb transparency for all body parts
		local limbNames = {
			"Head",
			"Torso",
			"Left Arm",
			"Right Arm",
			"Left Leg",
			"Right Leg",
			"UpperTorso",
			"LowerTorso",
			"LeftUpperArm",
			"LeftLowerArm",
			"LeftHand",
			"RightUpperArm",
			"RightLowerArm",
			"RightHand",
			"LeftUpperLeg",
			"LeftLowerLeg",
			"LeftFoot",
			"RightUpperLeg",
			"RightLowerLeg",
			"RightFoot",
		}

		for _, limbName in ipairs(limbNames) do
			local limb = character:FindFirstChild(limbName)
			if limb and limb:IsA("BasePart") then
				limb.LocalTransparencyModifier = 0
			end
		end

		-- Reset accessory/hat visibility
		for _, child in pairs(character:GetDescendants()) do
			if child:IsA("BasePart") and child.Name == "Handle" then
				child.LocalTransparencyModifier = 0
			end
		end

		-- Clean up any leftover aim parts
		local aimPart = character:FindFirstChild("aimpartjudge")
		if aimPart then
			aimPart:Destroy()
		end
	end

	print("[CLIENT] Gun state cleanup complete")
end)

-- ============================================
-- RESET BUTTON TOGGLE (disable during game)
-- ============================================
local StarterGui = game:GetService("StarterGui")
local toggleResetEvent = remoteEvents:WaitForChild("ToggleResetButton", 10)

if toggleResetEvent then
	toggleResetEvent.OnClientEvent:Connect(function(enabled)
		-- Retry a few times in case StarterGui isn't ready
		task.spawn(function()
			local success = false
			for i = 1, 5 do
				local ok, err = pcall(function()
					StarterGui:SetCore("ResetButtonCallback", enabled)
				end)
				if ok then
					success = true
					print("[CLIENT] Reset button " .. (enabled and "ENABLED" or "DISABLED"))
					break
				else
					task.wait(0.5)
				end
			end
			if not success then
				warn("[CLIENT] Failed to toggle reset button")
			end
		end)
	end)
	print("[CLIENT] ToggleResetButton handler connected")
else
	warn("[CLIENT] ToggleResetButton event not found")
end

print("MinigameUI (Maze) loaded successfully!")

-- ============================================
-- FALLING MINIGAME
-- ============================================
local FALLING_GOAL = 10
local fallingActive = false
local fallingElements = {}
local fallingMyScore = 0
local fallingScoreLabels = {}

local ELEMENT_COLORS = {
	Color3.fromRGB(0, 200, 255),
	Color3.fromRGB(255, 100, 200),
	Color3.fromRGB(255, 220, 50),
	Color3.fromRGB(100, 255, 150),
	Color3.fromRGB(200, 150, 255),
}


-- Reference pre-built Falling UI
local fallingContainer = screenGui:WaitForChild("FallingContainer")
local fallingPlayArea = fallingContainer:WaitForChild("PlayArea")
local fallingScoreContainer = fallingContainer:WaitForChild("ScoreContainer")

local function createFallingScoreLabel(playerName, total)
	local labelWidth = math.min(0.2, 0.9 / math.max(total, 1))
	local frame = Instance.new("Frame")
	frame.Name = playerName
	frame.Size = UDim2.new(labelWidth, -10, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	frame.Parent = fallingScoreContainer

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 8)
	frameCorner.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Text = playerName
	nameLabel.Parent = frame

	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.Name = "Score"
	scoreLabel.Size = UDim2.new(1, 0, 0.5, 0)
	scoreLabel.Position = UDim2.new(0, 0, 0.5, 0)
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.Font = Enum.Font.GothamBold
	scoreLabel.TextSize = 16
	scoreLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
	scoreLabel.Text = "0/" .. FALLING_GOAL
	scoreLabel.Parent = frame

	fallingScoreLabels[playerName] = { frame = frame, scoreLabel = scoreLabel }
end

local function createFallingElement(elementId, xPosition, colorIndex)
	if not fallingActive then
		return
	end
	local color = ELEMENT_COLORS[colorIndex] or ELEMENT_COLORS[1]
	local size = 50

	local element = Instance.new("TextButton")
	element.Name = "Element_" .. elementId
	element.Size = UDim2.new(0, size, 0, size)
	element.Position = UDim2.new(xPosition, -size / 2, -0.1, 0)
	element.BackgroundColor3 = color
	element.BorderSizePixel = 0
	element.Text = "★"
	element.TextSize = 28
	element.TextColor3 = Color3.fromRGB(255, 255, 255)
	element.Font = Enum.Font.GothamBold
	element.AutoButtonColor = false
	element.Parent = fallingPlayArea

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = element

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = element

	fallingElements[elementId] = element

	element.MouseButton1Click:Connect(function()
		if not fallingActive or not element.Visible then
			return
		end
		element.Visible = false

		local popEffect = Instance.new("Frame")
		popEffect.Size = UDim2.new(0, size * 1.5, 0, size * 1.5)
		popEffect.Position = element.Position + UDim2.new(0, -size * 0.25, 0, -size * 0.25)
		popEffect.BackgroundColor3 = color
		popEffect.BackgroundTransparency = 0.5
		popEffect.BorderSizePixel = 0
		popEffect.Parent = fallingPlayArea

		local popCorner = Instance.new("UICorner")
		popCorner.CornerRadius = UDim.new(0.5, 0)
		popCorner.Parent = popEffect

		TweenService:Create(popEffect, TweenInfo.new(0.3), {
			Size = UDim2.new(0, size * 2.5, 0, size * 2.5),
			Position = popEffect.Position + UDim2.new(0, -size * 0.5, 0, -size * 0.5),
			BackgroundTransparency = 1,
		}):Play()

		game:GetService("Debris"):AddItem(popEffect, 0.3)
		fallingMyScore = fallingMyScore + 1
		playerCaughtElementEvent:FireServer(elementId)
		fallingElements[elementId] = nil
		element:Destroy()
	end)

	local fallTime = 2.5 + math.random() * 0.5
	local tween = TweenService:Create(element, TweenInfo.new(fallTime, Enum.EasingStyle.Linear), {
		Position = UDim2.new(xPosition, -size / 2, 1.1, 0),
	})
	tween:Play()

	tween.Completed:Connect(function()
		if fallingElements[elementId] then
			fallingElements[elementId] = nil
			element:Destroy()
		end
	end)
end

local function updateFallingScore(playerName, score)
	if fallingScoreLabels[playerName] then
		fallingScoreLabels[playerName].scoreLabel.Text = score .. "/" .. FALLING_GOAL
		local label = fallingScoreLabels[playerName].scoreLabel
		label.TextColor3 = Color3.fromRGB(255, 255, 100)
		task.delay(0.1, function()
			if label and label.Parent then
				label.TextColor3 = Color3.fromRGB(100, 255, 150)
			end
		end)
	end
end

startFallingGameEvent.OnClientEvent:Connect(function(participatingPlayers)
	print("[CLIENT] StartFallingGame! Players: " .. #participatingPlayers)
	fallingActive = true
	fallingMyScore = 0

	for _, el in pairs(fallingElements) do
		if el and el.Parent then
			el:Destroy()
		end
	end
	fallingElements = {}

	for _, data in pairs(fallingScoreLabels) do
		if data.frame and data.frame.Parent then
			data.frame:Destroy()
		end
	end
	fallingScoreLabels = {}

	for _, p in ipairs(participatingPlayers) do
		createFallingScoreLabel(p.DisplayName, #participatingPlayers)
	end

	hideGameAnnouncement()
	centerTextLabel.Visible = false
	mazeContainer.Visible = false
	fallingContainer.Visible = true
end)

spawnFallingElementEvent.OnClientEvent:Connect(function(elementId, xPos, colorIndex)
	createFallingElement(elementId, xPos, colorIndex)
end)

updateFallingProgressEvent.OnClientEvent:Connect(function(progressPlayer, score)
	updateFallingScore(progressPlayer.DisplayName, score)
end)

endFallingGameEvent.OnClientEvent:Connect(function(winnerName)
	fallingActive = false
	fallingContainer.Visible = false
	showGameAnnouncement(winnerName .. " wins!")
end)

print("FallingMinigame handlers loaded!")

-- ============================================
-- BOX FILLING MINIGAME
-- ============================================
local BOX_MAX_CLICKS = 10
local boxFillingActive = false
local boxFillingTarget = 0
local boxValues = { 0, 0, 0, 0 }

-- Reference pre-built Box Filling UI
local boxFillingContainer = screenGui:WaitForChild("BoxFillingContainer")
local targetLabel = boxFillingContainer:WaitForChild("TargetLabel")
local totalLabel = boxFillingContainer:WaitForChild("TotalLabel")
local boxesFrame = boxFillingContainer:WaitForChild("BoxesFrame")
local submitButton = boxFillingContainer:WaitForChild("SubmitButton")

local BOX_COLORS = {
	Color3.fromRGB(255, 100, 120),
	Color3.fromRGB(100, 200, 255),
	Color3.fromRGB(150, 255, 150),
	Color3.fromRGB(255, 200, 100),
}

local boxButtons = {}
for i = 1, 4 do
	boxButtons[i] = boxesFrame:WaitForChild("Box" .. i)
end

-- Set up click handlers for each box
for i = 1, 4 do
	local box = boxButtons[i]
	box.MouseButton1Click:Connect(function()
		if not boxFillingActive then
			return
		end
		boxValues[i] = boxValues[i] + 1
		if boxValues[i] > BOX_MAX_CLICKS then
			boxValues[i] = 0
			TweenService:Create(box, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(100, 50, 50) }):Play()
			task.delay(0.15, function()
				TweenService:Create(box, TweenInfo.new(0.15), { BackgroundColor3 = BOX_COLORS[i] }):Play()
			end)
		else
			TweenService:Create(box, TweenInfo.new(0.1), { Size = UDim2.new(0.22, 0, 1.05, 0) }):Play()
			task.delay(0.1, function()
				TweenService:Create(box, TweenInfo.new(0.1), { Size = UDim2.new(0.2, 0, 1, 0) }):Play()
			end)
		end
		box.Text = tostring(boxValues[i])
		local total = boxValues[1] + boxValues[2] + boxValues[3] + boxValues[4]
		totalLabel.Text = "YOUR TOTAL: " .. total
		totalLabel.TextColor3 = (total == boxFillingTarget) and Color3.fromRGB(100, 255, 100)
			or Color3.fromRGB(100, 255, 150)
	end)
end

local function submitAnswer()
	if not boxFillingActive then
		return
	end
	local total = boxValues[1] + boxValues[2] + boxValues[3] + boxValues[4]
	playerBoxSubmitEvent:FireServer(total)
	TweenService:Create(submitButton, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(150, 200, 150) }):Play()
	task.delay(0.2, function()
		TweenService:Create(submitButton, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(80, 180, 120) })
			:Play()
	end)
end

submitButton.MouseButton1Click:Connect(submitAnswer)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not boxFillingActive then
		return
	end
	if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		submitAnswer()
	end
end)

startBoxFillingGameEvent.OnClientEvent:Connect(function(participatingPlayers, target)
	print("[CLIENT] StartBoxFillingGame! Target: " .. target)
	boxFillingActive = true
	boxFillingTarget = target
	boxValues = { 0, 0, 0, 0 }
	for i = 1, 4 do
		boxButtons[i].Text = "0"
	end
	targetLabel.Text = "TARGET: " .. target
	totalLabel.Text = "YOUR TOTAL: 0"
	totalLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
	hideGameAnnouncement()
	centerTextLabel.Visible = false
	mazeContainer.Visible = false
	fallingContainer.Visible = false
	boxFillingContainer.Visible = true
end)

endBoxFillingGameEvent.OnClientEvent:Connect(function(winnerName)
	boxFillingActive = false
	boxFillingContainer.Visible = false
	showGameAnnouncement(winnerName .. " wins!")
end)

print("BoxFillingMinigame handlers loaded!")

-- ============================================
-- EQUILIBRIUM (BALANCE) MINIGAME
-- ============================================
local EQUILIBRIUM_HOLD_TIME = 3 -- Seconds to hold balance to win
local EQUILIBRIUM_DRIFT_SPEED = 0.5 -- Drift speed (balanced with tap strength)

local equilibriumActive = false
local equilibriumUI = nil
local equilibriumHoldTimer = 0
local equilibriumMaxHoldTime = 0 -- Track best hold time for fallback

-- TAP-BASED movement system (no holding!)
local TAP_MOVE_AMOUNT = 0.09 -- Strong tap movement (responsive)
local equilibriumPendingMove = 0 -- Accumulated movement from taps (consumed each frame)

-- UI references (populated when cloning)
local equilibriumMainBar = nil
local equilibriumHitbox = nil
local equilibriumPlayerMover = nil
local equilibriumIndicator = nil
local equilibriumHoldTimeLabel = nil
local equilibriumLdivider = nil
local equilibriumRdivider = nil

-- Check if running on mobile
local function isMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Check if PlayerMover center is inside Hitbox
local function isInsideHitbox()
	if not equilibriumPlayerMover or not equilibriumHitbox then
		return false
	end

	local moverPos = equilibriumPlayerMover.AbsolutePosition
	local moverSize = equilibriumPlayerMover.AbsoluteSize
	local hitboxPos = equilibriumHitbox.AbsolutePosition
	local hitboxSize = equilibriumHitbox.AbsoluteSize

	-- Get center of PlayerMover
	local moverCenterX = moverPos.X + moverSize.X / 2

	-- Check if center is within hitbox X range
	local inHitbox = moverCenterX >= hitboxPos.X and moverCenterX <= hitboxPos.X + hitboxSize.X
	return inHitbox
end

-- Update indicator text and color
local function updateIndicator(isBalanced)
	if not equilibriumIndicator then
		return
	end

	local textLabel = equilibriumIndicator:FindFirstChild("TextLabel")
	if textLabel then
		if isBalanced then
			textLabel.Text = "BALANCED"
			textLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			textLabel.Text = "TOPPLING"
			textLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		end
	end
end

-- Update hold time display
local function updateHoldTimeDisplay(timeRemaining, visible)
	local displayText = string.format("%.3f", math.max(0, timeRemaining))

	if equilibriumHoldTimeLabel then
		equilibriumHoldTimeLabel.Text = displayText
		equilibriumHoldTimeLabel.Visible = visible
	end
end

-- Create mobile control buttons
local mobileLeftButton = nil
local mobileRightButton = nil

local function createMobileControls()
	if not isMobile() or not equilibriumUI then
		return
	end

	-- Left button (TAP-based - each tap applies one movement impulse)
	mobileLeftButton = Instance.new("TextButton")
	mobileLeftButton.Name = "LeftButton"
	mobileLeftButton.Size = UDim2.new(0.15, 0, 0.12, 0)
	mobileLeftButton.Position = UDim2.new(0.05, 0, 0.8, 0)
	mobileLeftButton.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
	mobileLeftButton.BackgroundTransparency = 0.3
	mobileLeftButton.Text = "◀ Q"
	mobileLeftButton.TextSize = 24
	mobileLeftButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	mobileLeftButton.Font = Enum.Font.GothamBold
	mobileLeftButton.AutoButtonColor = false
	mobileLeftButton.Parent = equilibriumUI

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 10)
	leftCorner.Parent = mobileLeftButton

	-- TAP handler - each tap applies one movement impulse
	mobileLeftButton.MouseButton1Click:Connect(function()
		if equilibriumActive then
			equilibriumPendingMove = equilibriumPendingMove - TAP_MOVE_AMOUNT
			-- Visual feedback
			mobileLeftButton.BackgroundColor3 = Color3.fromRGB(120, 120, 180)
			task.delay(0.08, function()
				if mobileLeftButton then
					mobileLeftButton.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
				end
			end)
		end
	end)

	-- Right button (TAP-based - each tap applies one movement impulse)
	mobileRightButton = Instance.new("TextButton")
	mobileRightButton.Name = "RightButton"
	mobileRightButton.Size = UDim2.new(0.15, 0, 0.12, 0)
	mobileRightButton.Position = UDim2.new(0.8, 0, 0.8, 0)
	mobileRightButton.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
	mobileRightButton.BackgroundTransparency = 0.3
	mobileRightButton.Text = "E ▶"
	mobileRightButton.TextSize = 24
	mobileRightButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	mobileRightButton.Font = Enum.Font.GothamBold
	mobileRightButton.AutoButtonColor = false
	mobileRightButton.Parent = equilibriumUI

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 10)
	rightCorner.Parent = mobileRightButton

	-- TAP handler - each tap applies one movement impulse
	mobileRightButton.MouseButton1Click:Connect(function()
		if equilibriumActive then
			equilibriumPendingMove = equilibriumPendingMove + TAP_MOVE_AMOUNT
			-- Visual feedback
			mobileRightButton.BackgroundColor3 = Color3.fromRGB(120, 120, 180)
			task.delay(0.08, function()
				if mobileRightButton then
					mobileRightButton.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
				end
			end)
		end
	end)
end

local function destroyMobileControls()
	if mobileLeftButton then
		mobileLeftButton:Destroy()
		mobileLeftButton = nil
	end
	if mobileRightButton then
		mobileRightButton:Destroy()
		mobileRightButton = nil
	end
end

-- Keyboard controls - TAP-BASED (Q = left, E = right)
-- Each key press adds a movement impulse - holding does NOT continuously move
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not equilibriumActive then
		return
	end

	-- TAP handler - each press applies one movement impulse
	if input.KeyCode == Enum.KeyCode.Q then
		equilibriumPendingMove = equilibriumPendingMove - TAP_MOVE_AMOUNT
	elseif input.KeyCode == Enum.KeyCode.E then
		equilibriumPendingMove = equilibriumPendingMove + TAP_MOVE_AMOUNT
	end
end)

-- Note: No InputEnded handler needed - we only care about taps, not releases

-- Main game loop (runs on RenderStepped when active)
local RunService = game:GetService("RunService")
local equilibriumConnection = nil

local function startEquilibriumLoop()
	if equilibriumConnection then
		equilibriumConnection:Disconnect()
	end

	local lastTime = tick()

	equilibriumConnection = RunService.RenderStepped:Connect(function()
		if not equilibriumActive or not equilibriumPlayerMover or not equilibriumMainBar then
			return
		end

		local currentTime = tick()
		local deltaTime = currentTime - lastTime
		lastTime = currentTime

		-- Get current position
		local currentX = equilibriumPlayerMover.Position.X.Scale
		local moverWidthScale = equilibriumPlayerMover.Size.X.Scale

		-- TAP-BASED MOVEMENT: Apply any pending tap impulses INSTANTLY
		local tapMove = equilibriumPendingMove
		equilibriumPendingMove = 0 -- Consume all pending movement

		-- DRIFT is ALWAYS active and FAST (no freeze exploit possible)
		-- Center is adjusted to account for mover width (true center position)
		local centerX = (1.0 - moverWidthScale) / 2
		local distFromCenter = currentX - centerX
		local driftDirection = distFromCenter >= 0 and 1 or -1
		local driftStrength = math.abs(distFromCenter) + 0.15
		local driftMove = driftDirection * EQUILIBRIUM_DRIFT_SPEED * driftStrength * deltaTime

		-- Calculate bounds using Ldivider and Rdivider positions
		local minX, maxX
		if equilibriumLdivider and equilibriumRdivider then
			-- Use divider positions directly as movement limits
			-- minX: PlayerMover's left edge can go as far left as Ldivider's position
			-- maxX: PlayerMover's left edge can go as far right as Rdivider's position minus mover width
			local ldivPos = equilibriumLdivider.Position.X.Scale
			local rdivPos = equilibriumRdivider.Position.X.Scale

			-- Simple approach: use divider positions directly
			minX = ldivPos
			maxX = rdivPos - moverWidthScale

			-- If still invalid, just use simple 0 to 1-width range
			if maxX <= minX then
				minX = 0
				maxX = 1.0 - moverWidthScale
			end
		else
			-- Fallback to calculated bounds
			minX = 0
			maxX = 1.0 - moverWidthScale
		end

		-- Apply BOTH drift and tap movement INSTANTLY (no lerp)
		local newX = math.clamp(currentX + driftMove + tapMove, minX, maxX)

		-- Apply final position
		equilibriumPlayerMover.Position = UDim2.new(newX, 0, equilibriumPlayerMover.Position.Y.Scale, 0)

		-- Check if inside hitbox
		local isBalanced = isInsideHitbox()
		updateIndicator(isBalanced)

		-- Update hold timer and visibility
		if isBalanced then
			equilibriumHoldTimer = equilibriumHoldTimer + deltaTime
			equilibriumMaxHoldTime = math.max(equilibriumMaxHoldTime, equilibriumHoldTimer)

			-- Update display (countdown from 3 to 0) - VISIBLE when balanced
			local timeRemaining = EQUILIBRIUM_HOLD_TIME - equilibriumHoldTimer
			updateHoldTimeDisplay(timeRemaining, true)

			-- Report progress to server periodically
			if math.floor(equilibriumHoldTimer * 10) % 5 == 0 then
				updateEquilibriumProgressEvent:FireServer(equilibriumMaxHoldTime)
			end

			-- Check win condition
			if equilibriumHoldTimer >= EQUILIBRIUM_HOLD_TIME then
				equilibriumActive = false
				equilibriumWinEvent:FireServer()
				print("[CLIENT] Won equilibrium game!")
				updateHoldTimeDisplay(0, true)
			end
		else
			-- Reset timer when outside hitbox - HIDE timer
			equilibriumHoldTimer = 0
			updateHoldTimeDisplay(EQUILIBRIUM_HOLD_TIME, false)
		end
	end)
end

local function stopEquilibriumLoop()
	if equilibriumConnection then
		equilibriumConnection:Disconnect()
		equilibriumConnection = nil
	end
end

-- Start equilibrium game event
startEquilibriumGameEvent.OnClientEvent:Connect(function(participatingPlayers)
	print("[CLIENT] StartEquilibriumGame received!")

	-- Clone UI from ReplicatedStorage
	local uiTemplate = ReplicatedStorage:FindFirstChild("EquilibriumRush")
	if not uiTemplate then
		warn("[CLIENT] EquilibriumRush UI not found in ReplicatedStorage!")
		return
	end

	-- Create ScreenGui if cloning a Frame
	equilibriumUI = Instance.new("ScreenGui")
	equilibriumUI.Name = "EquilibriumRushUI"
	equilibriumUI.ResetOnSpawn = false
	equilibriumUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	equilibriumUI.Parent = playerGui

	-- Clone the template as child of ScreenGui
	local clonedUI = uiTemplate:Clone()
	clonedUI.Parent = equilibriumUI

	-- The cloned UI is the MainBar itself or contains it
	if clonedUI:IsA("Frame") then
		equilibriumMainBar = clonedUI
		-- Center it on screen if it's not already positioned
		if equilibriumMainBar.Position == UDim2.new(0, 0, 0, 0) then
			equilibriumMainBar.Position = UDim2.new(0.5, 0, 0.4, 0)
			equilibriumMainBar.AnchorPoint = Vector2.new(0.5, 0.5)
		end
	else
		equilibriumMainBar = clonedUI:FindFirstChild("MainBar") or clonedUI
	end

	-- Find UI elements
	equilibriumHitbox = equilibriumMainBar:FindFirstChild("Hitbox")
	equilibriumPlayerMover = equilibriumMainBar:FindFirstChild("PlayerMover")
	equilibriumIndicator = equilibriumMainBar:FindFirstChild("Indicator")
	equilibriumHoldTimeLabel = equilibriumMainBar:FindFirstChild("HoldTime")
	equilibriumLdivider = equilibriumMainBar:FindFirstChild("Ldivider")
	equilibriumRdivider = equilibriumMainBar:FindFirstChild("Rdivider")

	-- Reset state
	equilibriumActive = true
	equilibriumHoldTimer = 0
	equilibriumMaxHoldTime = 0
	equilibriumPendingMove = 0 -- Clear any pending movement

	-- Position PlayerMover at left edge (Ldivider) initially
	if equilibriumPlayerMover and equilibriumLdivider then
		local leftX = equilibriumLdivider.Position.X.Scale
		equilibriumPlayerMover.Position = UDim2.new(leftX, 0, equilibriumPlayerMover.Position.Y.Scale, 0)
	elseif equilibriumPlayerMover then
		-- Fallback: start at position 0
		equilibriumPlayerMover.Position = UDim2.new(0, 0, equilibriumPlayerMover.Position.Y.Scale, 0)
	end

	-- Initialize display (hidden until player enters hitbox)
	updateHoldTimeDisplay(EQUILIBRIUM_HOLD_TIME, false)
	updateIndicator(isInsideHitbox())

	-- Hide other minigame UIs
	hideGameAnnouncement()
	centerTextLabel.Visible = false
	mazeContainer.Visible = false
	fallingContainer.Visible = false
	boxFillingContainer.Visible = false

	-- Create mobile controls if needed
	createMobileControls()

	-- Start game loop
	startEquilibriumLoop()

	print("[CLIENT] Equilibrium game started!")
end)

-- End equilibrium game event
endEquilibriumGameEvent.OnClientEvent:Connect(function(winnerName)
	print("[CLIENT] EndEquilibriumGame: " .. winnerName)

	equilibriumActive = false
	stopEquilibriumLoop()
	destroyMobileControls()

	-- Cleanup UI
	if equilibriumUI then
		equilibriumUI:Destroy()
		equilibriumUI = nil
	end

	-- Reset references
	equilibriumMainBar = nil
	equilibriumHitbox = nil
	equilibriumPlayerMover = nil
	equilibriumIndicator = nil
	equilibriumHoldTimeLabel = nil

	-- Show winner message
	showGameAnnouncement(winnerName .. " wins the balance challenge!")
end)

-- Also hide equilibrium UI when hideAllUI is fired
hideAllUIEvent.OnClientEvent:Connect(function()
	if equilibriumUI then
		equilibriumActive = false
		stopEquilibriumLoop()
		destroyMobileControls()
		equilibriumUI:Destroy()
		equilibriumUI = nil
	end
end)

print("EquilibriumMinigame handlers loaded!")
