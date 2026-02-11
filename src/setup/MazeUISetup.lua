--[[
	MazeUISetup (Command Script)
	============================
	PURPOSE: Run once in Roblox Studio Command Bar to create the permanent
	Maze minigame GUI hierarchy inside StarterGui.

	HIERARCHY CREATED:
	StarterGui
	 └─ MinigameUI (ScreenGui)
	     └─ MazeContainer (Frame)
	         ├─ UICorner
	         ├─ UIStroke
	         ├─ Title (TextLabel)
	         ├─ Instructions (TextLabel)
	         ├─ MazeArea (Frame)
	         │   ├─ UICorner
	         │   ├─ UIStroke
	         │   ├─ StartZone (Frame)
	         │   │   ├─ UICorner
	         │   │   ├─ UIStroke
	         │   │   └─ StartLabel (TextLabel)
	         │   ├─ EndZone (Frame)
	         │   │   ├─ UICorner
	         │   │   ├─ UIStroke
	         │   │   └─ EndLabel (TextLabel)
	         │   ├─ Wall1..Wall5 (Frames with UICorner, UIGradient, UIStroke)
	         │   ├─ DragBox (Frame)
	         │   │   ├─ UICorner
	         │   │   ├─ UIStroke
	         │   │   └─ UIGradient
	         │   └─ Feedback (TextLabel)
	         │       └─ UICorner
	         └─ ProgressContainer (Frame)
	             └─ UIListLayout

	USAGE: Paste this entire script into the Roblox Studio Command Bar and press Enter.
	       It will skip creation if MinigameUI already exists in StarterGui.
	       After running, the client script (TableUIHandler) should use :WaitForChild()
	       to reference these objects instead of Instance.new().
]]

local StarterGui = game:GetService("StarterGui")

-- Safety check: don't duplicate
if StarterGui:FindFirstChild("MinigameUI") then
	warn("[MazeUISetup] MinigameUI already exists in StarterGui. Aborting to avoid duplicates.")
	return
end

-- ============================================
-- SCREENGUI
-- ============================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MinigameUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = StarterGui

-- ============================================
-- MAZE CONTAINER
-- ============================================
local mazeContainer = Instance.new("Frame")
mazeContainer.Name = "MazeContainer"
mazeContainer.Size = UDim2.new(0.6, 0, 0.7, 0)
mazeContainer.Position = UDim2.new(0.2, 0, 0.15, 0)
mazeContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
mazeContainer.BackgroundTransparency = 0.1
mazeContainer.BorderSizePixel = 0
mazeContainer.Visible = false
mazeContainer.Parent = screenGui

local mazeCorner = Instance.new("UICorner")
mazeCorner.CornerRadius = UDim.new(0, 15)
mazeCorner.Parent = mazeContainer

local mazeStroke = Instance.new("UIStroke")
mazeStroke.Color = Color3.fromRGB(100, 100, 140)
mazeStroke.Thickness = 3
mazeStroke.Parent = mazeContainer

-- ============================================
-- TITLE
-- ============================================
local mazeTitle = Instance.new("TextLabel")
mazeTitle.Name = "Title"
mazeTitle.Size = UDim2.new(1, 0, 0.08, 0)
mazeTitle.Position = UDim2.new(0, 0, 0.01, 0)
mazeTitle.BackgroundTransparency = 1
mazeTitle.Font = Enum.Font.GothamBold
mazeTitle.TextSize = 28
mazeTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
mazeTitle.Text = "🎯 DRAG THE BOX TO THE END! 🎯"
mazeTitle.Parent = mazeContainer

-- ============================================
-- INSTRUCTIONS
-- ============================================
local instructionsLabel = Instance.new("TextLabel")
instructionsLabel.Name = "Instructions"
instructionsLabel.Size = UDim2.new(1, 0, 0.05, 0)
instructionsLabel.Position = UDim2.new(0, 0, 0.085, 0)
instructionsLabel.BackgroundTransparency = 1
instructionsLabel.Font = Enum.Font.Gotham
instructionsLabel.TextSize = 16
instructionsLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
instructionsLabel.Text = "Touch the walls = RESET! First to finish wins!"
instructionsLabel.Parent = mazeContainer

-- ============================================
-- MAZE AREA
-- ============================================
local mazeArea = Instance.new("Frame")
mazeArea.Name = "MazeArea"
mazeArea.Size = UDim2.new(0.9, 0, 0.65, 0)
mazeArea.Position = UDim2.new(0.05, 0, 0.14, 0)
mazeArea.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
mazeArea.BorderSizePixel = 0
mazeArea.ClipsDescendants = true
mazeArea.Parent = mazeContainer

local mazeAreaCorner = Instance.new("UICorner")
mazeAreaCorner.CornerRadius = UDim.new(0, 10)
mazeAreaCorner.Parent = mazeArea

local mazeAreaStroke = Instance.new("UIStroke")
mazeAreaStroke.Color = Color3.fromRGB(80, 80, 110)
mazeAreaStroke.Thickness = 2
mazeAreaStroke.Parent = mazeArea

-- ============================================
-- START ZONE (green, top-left)
-- ============================================
local startZone = Instance.new("Frame")
startZone.Name = "StartZone"
startZone.Size = UDim2.new(0.10, 0, 0.12, 0)
startZone.Position = UDim2.new(0.03, 0, 0.03, 0)
startZone.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
startZone.BorderSizePixel = 0
startZone.Parent = mazeArea

local startZoneCorner = Instance.new("UICorner")
startZoneCorner.CornerRadius = UDim.new(0, 8)
startZoneCorner.Parent = startZone

local startGlow = Instance.new("UIStroke")
startGlow.Color = Color3.fromRGB(100, 255, 150)
startGlow.Thickness = 2
startGlow.Parent = startZone

local startLabel = Instance.new("TextLabel")
startLabel.Name = "StartLabel"
startLabel.Size = UDim2.new(1, 0, 1, 0)
startLabel.BackgroundTransparency = 1
startLabel.Font = Enum.Font.GothamBold
startLabel.TextSize = 12
startLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
startLabel.Text = "START"
startLabel.Parent = startZone

-- ============================================
-- END ZONE (gold, bottom-left)
-- ============================================
local endZone = Instance.new("Frame")
endZone.Name = "EndZone"
endZone.Size = UDim2.new(0.10, 0, 0.12, 0)
endZone.Position = UDim2.new(0.03, 0, 0.85, 0)
endZone.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
endZone.BorderSizePixel = 0
endZone.Parent = mazeArea

local endZoneCorner = Instance.new("UICorner")
endZoneCorner.CornerRadius = UDim.new(0, 8)
endZoneCorner.Parent = endZone

local endGlow = Instance.new("UIStroke")
endGlow.Color = Color3.fromRGB(255, 230, 100)
endGlow.Thickness = 2
endGlow.Parent = endZone

local endLabel = Instance.new("TextLabel")
endLabel.Name = "EndLabel"
endLabel.Size = UDim2.new(1, 0, 1, 0)
endLabel.BackgroundTransparency = 1
endLabel.Font = Enum.Font.GothamBold
endLabel.TextSize = 12
endLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
endLabel.Text = "END"
endLabel.Parent = endZone

-- ============================================
-- MAZE WALLS (Reverse C-shape corridor)
-- PATH WIDTH: ~0.17 (17% of maze area)
-- Path: Start (top-left) → Right → Down → Left → End (bottom-left)
-- ============================================

local function createWall(name, xPos, yPos, width, height)
	local wall = Instance.new("Frame")
	wall.Name = name
	wall.Size = UDim2.new(width, 0, height, 0)
	wall.Position = UDim2.new(xPos, 0, yPos, 0)
	wall.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	wall.BorderSizePixel = 0
	wall.Parent = mazeArea

	local wallCorner = Instance.new("UICorner")
	wallCorner.CornerRadius = UDim.new(0, 4)
	wallCorner.Parent = wall

	local wallGradient = Instance.new("UIGradient")
	wallGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 60)),
	})
	wallGradient.Rotation = 45
	wallGradient.Parent = wall

	local wallStroke = Instance.new("UIStroke")
	wallStroke.Color = Color3.fromRGB(100, 100, 130)
	wallStroke.Thickness = 1
	wallStroke.Parent = wall

	return wall
end

-- Top wall (gap at start area)
createWall("Wall1_Top", 0.15, 0, 0.85, 0.04)

-- Left wall (between start and end gaps)
-- createWall("Wall2_Left", 0, 0.17, 0.04, 0.65)

-- Bottom wall (gap at end area)
createWall("Wall3_Bottom", 0.15, 0.96, 0.85, 0.04)

-- Right wall (full height)
createWall("Wall4_Right", 0.96, 0, 0.04, 1)

-- Inner block (central rectangle that creates the reverse C corridor)
createWall("Wall5_Inner", 0.18, 0.20, 0.72, 0.60)

-- ============================================
-- DRAG BOX (player's game piece)
-- ============================================
local dragBox = Instance.new("Frame")
dragBox.Name = "DragBox"
dragBox.Size = UDim2.new(0, 32, 0, 32)
dragBox.Position = UDim2.new(0.04, 0, 0.05, 0)
dragBox.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
dragBox.BorderSizePixel = 0
dragBox.Parent = mazeArea

local dragBoxCorner = Instance.new("UICorner")
dragBoxCorner.CornerRadius = UDim.new(0, 6)
dragBoxCorner.Parent = dragBox

local dragBoxStroke = Instance.new("UIStroke")
dragBoxStroke.Color = Color3.fromRGB(255, 255, 255)
dragBoxStroke.Thickness = 3
dragBoxStroke.Parent = dragBox

local dragBoxGradient = Instance.new("UIGradient")
dragBoxGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 220, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 140, 220)),
})
dragBoxGradient.Rotation = 45
dragBoxGradient.Parent = dragBox

-- ============================================
-- FEEDBACK LABEL (shows "RESET!" or "SUCCESS!")
-- ============================================
local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "Feedback"
feedbackLabel.Size = UDim2.new(0.4, 0, 0.1, 0)
feedbackLabel.Position = UDim2.new(0.3, 0, 0.45, 0)
feedbackLabel.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
feedbackLabel.BackgroundTransparency = 0.2
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.TextSize = 32
feedbackLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
feedbackLabel.Text = "RESET!"
feedbackLabel.Visible = false
feedbackLabel.Parent = mazeArea

local feedbackCorner = Instance.new("UICorner")
feedbackCorner.CornerRadius = UDim.new(0, 10)
feedbackCorner.Parent = feedbackLabel

-- ============================================
-- PROGRESS CONTAINER (shows all players' progress bars)
-- ============================================
local progressContainer = Instance.new("Frame")
progressContainer.Name = "ProgressContainer"
progressContainer.Size = UDim2.new(0.9, 0, 0.12, 0)
progressContainer.Position = UDim2.new(0.05, 0, 0.82, 0)
progressContainer.BackgroundTransparency = 1
progressContainer.Parent = mazeContainer

local progressLayout = Instance.new("UIListLayout")
progressLayout.FillDirection = Enum.FillDirection.Horizontal
progressLayout.Padding = UDim.new(0.02, 0)
progressLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
progressLayout.Parent = progressContainer

-- ============================================
-- DONE
-- ============================================
print("[MazeUISetup] ✅ Maze UI hierarchy created successfully in StarterGui > MinigameUI > MazeContainer")
print("[MazeUISetup] Hierarchy:")
print("  MinigameUI (ScreenGui)")
print("    └─ MazeContainer (Frame)")
print("      ├─ Title (TextLabel)")
print("      ├─ Instructions (TextLabel)")
print("      ├─ MazeArea (Frame)")
print("      │   ├─ StartZone, EndZone")
print("      │   ├─ Wall1_Top..Wall5_Inner")
print("      │   ├─ DragBox")
print("      │   └─ Feedback")
print("      └─ ProgressContainer (Frame)")
