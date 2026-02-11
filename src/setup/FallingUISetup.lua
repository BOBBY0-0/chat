--[[
	FallingUISetup (Command Script)
	================================
	PURPOSE: Run once in Roblox Studio Command Bar to create the permanent
	Falling minigame GUI hierarchy inside the existing MinigameUI ScreenGui.

	HIERARCHY CREATED:
	MinigameUI (ScreenGui) -- must already exist from MazeUISetup
	 └─ FallingContainer (Frame)
	     ├─ UICorner
	     ├─ UIStroke
	     ├─ Title (TextLabel)
	     ├─ Instructions (TextLabel)
	     ├─ PlayArea (Frame) -- falling elements spawn here at runtime
	     └─ ScoreContainer (Frame)
	         └─ UIListLayout

	USAGE: Run MazeUISetup FIRST (creates MinigameUI), then paste this into
	       the Roblox Studio Command Bar and press Enter.

	NOTE: Falling elements (stars) and score labels are created dynamically
	      at runtime by game logic — only the static containers are set up here.
]]

local StarterGui = game:GetService("StarterGui")

-- Find existing MinigameUI (created by MazeUISetup)
local screenGui = StarterGui:FindFirstChild("MinigameUI")
if not screenGui then
	warn("[FallingUISetup] MinigameUI not found in StarterGui. Run MazeUISetup first!")
	return
end

-- Safety check: don't duplicate
if screenGui:FindFirstChild("FallingContainer") then
	warn("[FallingUISetup] FallingContainer already exists. Aborting to avoid duplicates.")
	return
end

-- ============================================
-- FALLING CONTAINER
-- ============================================
local fallingContainer = Instance.new("Frame")
fallingContainer.Name = "FallingContainer"
fallingContainer.Size = UDim2.new(0.7, 0, 0.75, 0)
fallingContainer.Position = UDim2.new(0.15, 0, 0.12, 0)
fallingContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
fallingContainer.BackgroundTransparency = 0.1
fallingContainer.BorderSizePixel = 0
fallingContainer.ClipsDescendants = true
fallingContainer.Visible = false
fallingContainer.Parent = screenGui

local fallingCorner = Instance.new("UICorner")
fallingCorner.CornerRadius = UDim.new(0, 15)
fallingCorner.Parent = fallingContainer

local fallingStroke = Instance.new("UIStroke")
fallingStroke.Color = Color3.fromRGB(100, 100, 150)
fallingStroke.Thickness = 3
fallingStroke.Parent = fallingContainer

-- ============================================
-- TITLE
-- ============================================
local fallingTitle = Instance.new("TextLabel")
fallingTitle.Name = "Title"
fallingTitle.Size = UDim2.new(1, 0, 0.08, 0)
fallingTitle.Position = UDim2.new(0, 0, 0.01, 0)
fallingTitle.BackgroundTransparency = 1
fallingTitle.Font = Enum.Font.GothamBold
fallingTitle.TextSize = 28
fallingTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
fallingTitle.Text = "CATCH THE FALLING STARS!"
fallingTitle.Parent = fallingContainer

-- ============================================
-- INSTRUCTIONS
-- ============================================
local fallingInstructions = Instance.new("TextLabel")
fallingInstructions.Name = "Instructions"
fallingInstructions.Size = UDim2.new(1, 0, 0.05, 0)
fallingInstructions.Position = UDim2.new(0, 0, 0.085, 0)
fallingInstructions.BackgroundTransparency = 1
fallingInstructions.Font = Enum.Font.Gotham
fallingInstructions.TextSize = 16
fallingInstructions.TextColor3 = Color3.fromRGB(180, 180, 200)
fallingInstructions.Text = "Click the falling stars! First to 10 wins!"
fallingInstructions.Parent = fallingContainer

-- ============================================
-- PLAY AREA (falling elements spawn here at runtime)
-- ============================================
local fallingPlayArea = Instance.new("Frame")
fallingPlayArea.Name = "PlayArea"
fallingPlayArea.Size = UDim2.new(0.95, 0, 0.72, 0)
fallingPlayArea.Position = UDim2.new(0.025, 0, 0.15, 0)
fallingPlayArea.BackgroundTransparency = 1
fallingPlayArea.ClipsDescendants = true
fallingPlayArea.Parent = fallingContainer

-- ============================================
-- SCORE CONTAINER (score labels created dynamically per player)
-- ============================================
local fallingScoreContainer = Instance.new("Frame")
fallingScoreContainer.Name = "ScoreContainer"
fallingScoreContainer.Size = UDim2.new(0.9, 0, 0.1, 0)
fallingScoreContainer.Position = UDim2.new(0.05, 0, 0.88, 0)
fallingScoreContainer.BackgroundTransparency = 1
fallingScoreContainer.Parent = fallingContainer

local fallingScoreLayout = Instance.new("UIListLayout")
fallingScoreLayout.FillDirection = Enum.FillDirection.Horizontal
fallingScoreLayout.Padding = UDim.new(0.02, 0)
fallingScoreLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
fallingScoreLayout.Parent = fallingScoreContainer

-- ============================================
-- DONE
-- ============================================
print("[FallingUISetup] ✅ Falling UI hierarchy created successfully in MinigameUI > FallingContainer")
print("[FallingUISetup] Hierarchy:")
print("  FallingContainer (Frame)")
print("    ├─ Title (TextLabel)")
print("    ├─ Instructions (TextLabel)")
print("    ├─ PlayArea (Frame) -- elements spawn here")
print("    └─ ScoreContainer (Frame)")
print("        └─ UIListLayout")
