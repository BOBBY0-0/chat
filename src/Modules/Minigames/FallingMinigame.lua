--[[
    FallingMinigame (ModuleScript)
    ==============================
    LOCATION: ReplicatedStorage/Modules/Minigames
    
    Falling elements minigame where players race to click
    falling UI buttons. First to 10 clicks wins.
]]

local FallingMinigame = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remote events (will be set on init)
local playerCaughtElementEvent = nil
local updateFallingProgressEvent = nil
local spawnFallingElementEvent = nil
local endFallingGameEvent = nil

-- State
local isActive = false
local screenGui = nil
local gameContainer = nil
local scoreLabels = {}
local fallingElements = {}
local myScore = 0
local GOAL = 10

-- Colors for falling elements
local ELEMENT_COLORS = {
	Color3.fromRGB(0, 200, 255), -- Cyan
	Color3.fromRGB(255, 100, 200), -- Pink
	Color3.fromRGB(255, 220, 50), -- Yellow
	Color3.fromRGB(100, 255, 150), -- Green
	Color3.fromRGB(200, 150, 255), -- Purple
}

-- ============================================
-- UI CREATION
-- ============================================
local function createUI()
	-- Main screen GUI
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FallingMinigameUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Game container (main play area)
	gameContainer = Instance.new("Frame")
	gameContainer.Name = "GameContainer"
	gameContainer.Size = UDim2.new(0.7, 0, 0.75, 0)
	gameContainer.Position = UDim2.new(0.15, 0, 0.12, 0)
	gameContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	gameContainer.BackgroundTransparency = 0.1
	gameContainer.BorderSizePixel = 0
	gameContainer.ClipsDescendants = true
	gameContainer.Parent = screenGui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 15)
	containerCorner.Parent = gameContainer

	local containerStroke = Instance.new("UIStroke")
	containerStroke.Color = Color3.fromRGB(100, 100, 150)
	containerStroke.Thickness = 3
	containerStroke.Parent = gameContainer

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.08, 0)
	title.Position = UDim2.new(0, 0, 0.01, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "⚡ CATCH THE FALLING STARS! ⚡"
	title.Parent = gameContainer

	-- Instructions
	local instructions = Instance.new("TextLabel")
	instructions.Name = "Instructions"
	instructions.Size = UDim2.new(1, 0, 0.05, 0)
	instructions.Position = UDim2.new(0, 0, 0.085, 0)
	instructions.BackgroundTransparency = 1
	instructions.Font = Enum.Font.Gotham
	instructions.TextSize = 16
	instructions.TextColor3 = Color3.fromRGB(180, 180, 200)
	instructions.Text = "Click the falling elements! First to " .. GOAL .. " wins!"
	instructions.Parent = gameContainer

	-- Score display container (top bar)
	local scoreContainer = Instance.new("Frame")
	scoreContainer.Name = "ScoreContainer"
	scoreContainer.Size = UDim2.new(0.9, 0, 0.08, 0)
	scoreContainer.Position = UDim2.new(0.05, 0, 0.02, 0)
	scoreContainer.BackgroundTransparency = 1
	scoreContainer.Parent = screenGui

	local scoreLayout = Instance.new("UIListLayout")
	scoreLayout.FillDirection = Enum.FillDirection.Horizontal
	scoreLayout.Padding = UDim.new(0.02, 0)
	scoreLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	scoreLayout.Parent = scoreContainer

	-- Play area (where elements fall)
	local playArea = Instance.new("Frame")
	playArea.Name = "PlayArea"
	playArea.Size = UDim2.new(0.95, 0, 0.82, 0)
	playArea.Position = UDim2.new(0.025, 0, 0.15, 0)
	playArea.BackgroundTransparency = 1
	playArea.ClipsDescendants = true
	playArea.Parent = gameContainer

	-- Store references
	gameContainer:SetAttribute("ScoreContainer", "ScoreContainer")
	gameContainer:SetAttribute("PlayArea", "PlayArea")
end

-- Create a score label for a player
local function createScoreLabel(playerName, index, total)
	local scoreContainer = screenGui:FindFirstChild("ScoreContainer") or gameContainer:FindFirstChild("ScoreContainer")
	if not scoreContainer then
		return
	end

	local labelWidth = math.min(0.2, 0.9 / math.max(total, 1))

	local frame = Instance.new("Frame")
	frame.Name = playerName
	frame.Size = UDim2.new(labelWidth, -10, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	frame.Parent = scoreContainer

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 8)
	frameCorner.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
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
	scoreLabel.TextSize = 18
	scoreLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
	scoreLabel.Text = "0/" .. GOAL
	scoreLabel.Parent = frame

	scoreLabels[playerName] = { frame = frame, scoreLabel = scoreLabel }
end

-- Create a falling element
local function createFallingElement(elementId, xPosition, colorIndex)
	if not isActive then
		return
	end

	local playArea = gameContainer:FindFirstChild("PlayArea")
	if not playArea then
		return
	end

	local color = ELEMENT_COLORS[colorIndex] or ELEMENT_COLORS[1]
	local size = 50

	-- Create element button
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
	element.Parent = playArea

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = element

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = element

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, color),
	})
	gradient.Rotation = 45
	gradient.Parent = element

	-- Store reference
	fallingElements[elementId] = element

	-- Click handler
	element.MouseButton1Click:Connect(function()
		if not isActive then
			return
		end
		if not element.Visible then
			return
		end

		-- Visual feedback - pop effect
		element.Visible = false

		local popEffect = Instance.new("Frame")
		popEffect.Size = UDim2.new(0, size * 1.5, 0, size * 1.5)
		popEffect.Position = element.Position + UDim2.new(0, -size * 0.25, 0, -size * 0.25)
		popEffect.BackgroundColor3 = color
		popEffect.BackgroundTransparency = 0.5
		popEffect.BorderSizePixel = 0
		popEffect.Parent = playArea

		local popCorner = Instance.new("UICorner")
		popCorner.CornerRadius = UDim.new(0.5, 0)
		popCorner.Parent = popEffect

		TweenService:Create(popEffect, TweenInfo.new(0.3), {
			Size = UDim2.new(0, size * 2.5, 0, size * 2.5),
			Position = popEffect.Position + UDim2.new(0, -size * 0.5, 0, -size * 0.5),
			BackgroundTransparency = 1,
		}):Play()

		game:GetService("Debris"):AddItem(popEffect, 0.3)

		-- Increment local score
		myScore = myScore + 1

		-- Fire to server
		if playerCaughtElementEvent then
			playerCaughtElementEvent:FireServer(elementId)
		end

		-- Remove from tracking
		fallingElements[elementId] = nil
		element:Destroy()
	end)

	-- Animate falling
	local fallTime = 2.5 + math.random() * 0.5 -- 2.5-3 seconds
	local tween = TweenService:Create(element, TweenInfo.new(fallTime, Enum.EasingStyle.Linear), {
		Position = UDim2.new(xPosition, -size / 2, 1.1, 0),
	})
	tween:Play()

	-- Remove when off screen
	tween.Completed:Connect(function()
		if fallingElements[elementId] then
			fallingElements[elementId] = nil
			element:Destroy()
		end
	end)
end

-- Update score display
local function updateScore(playerName, score)
	if scoreLabels[playerName] then
		scoreLabels[playerName].scoreLabel.Text = score .. "/" .. GOAL

		-- Flash effect on score increase
		local label = scoreLabels[playerName].scoreLabel
		local originalColor = label.TextColor3
		label.TextColor3 = Color3.fromRGB(255, 255, 100)
		task.delay(0.1, function()
			if label and label.Parent then
				label.TextColor3 = originalColor
			end
		end)
	end
end

-- ============================================
-- PUBLIC INTERFACE
-- ============================================

function FallingMinigame:Init()
	createUI()

	-- Get remote events
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if remoteEvents then
		playerCaughtElementEvent = remoteEvents:FindFirstChild("PlayerCaughtElement")
		updateFallingProgressEvent = remoteEvents:FindFirstChild("UpdateFallingProgress")
		spawnFallingElementEvent = remoteEvents:FindFirstChild("SpawnFallingElement")
		endFallingGameEvent = remoteEvents:FindFirstChild("EndFallingGame")

		-- Listen for spawn events
		if spawnFallingElementEvent then
			spawnFallingElementEvent.OnClientEvent:Connect(function(elementId, xPos, colorIndex)
				createFallingElement(elementId, xPos, colorIndex)
			end)
		end

		-- Listen for progress updates
		if updateFallingProgressEvent then
			updateFallingProgressEvent.OnClientEvent:Connect(function(progressPlayer, score)
				updateScore(progressPlayer.DisplayName, score)
			end)
		end

		-- Listen for game end
		if endFallingGameEvent then
			endFallingGameEvent.OnClientEvent:Connect(function(winnerName)
				self:Stop()
			end)
		end
	end

	print("[FallingMinigame] Initialized")
end

function FallingMinigame:Start(participatingPlayers)
	print("[FallingMinigame] Starting with " .. #participatingPlayers .. " players")

	-- Reset state
	isActive = true
	myScore = 0

	-- Clear old elements
	for id, element in pairs(fallingElements) do
		if element and element.Parent then
			element:Destroy()
		end
	end
	fallingElements = {}

	-- Clear old score labels
	for name, data in pairs(scoreLabels) do
		if data.frame and data.frame.Parent then
			data.frame:Destroy()
		end
	end
	scoreLabels = {}

	-- Create score labels for each player
	for i, p in ipairs(participatingPlayers) do
		createScoreLabel(p.DisplayName, i, #participatingPlayers)
	end

	-- Show UI
	if screenGui then
		screenGui.Enabled = true
	end
end

function FallingMinigame:Stop()
	isActive = false

	-- Hide UI
	if screenGui then
		screenGui.Enabled = false
	end

	-- Clear elements
	for id, element in pairs(fallingElements) do
		if element and element.Parent then
			element:Destroy()
		end
	end
	fallingElements = {}
end

function FallingMinigame:Hide()
	if screenGui then
		screenGui.Enabled = false
	end
end

return FallingMinigame
