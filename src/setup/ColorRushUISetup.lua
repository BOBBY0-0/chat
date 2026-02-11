--[[
	ColorRushUISetup (Command Script)
	===================================
	PURPOSE: Run once in Roblox Studio Command Bar to create the permanent
	Color Rush minigame GUI hierarchy inside StarterGui.

	HIERARCHY CREATED:
	StarterGui
	 └─ ColorRushUI (ScreenGui) -- separate from MinigameUI
	     ├─ PreviewContainer (Frame) -- Phase 1: shows target color
	     │   ├─ UICorner
	     │   ├─ UIStroke (OuterStroke)
	     │   ├─ Title (TextLabel)
	     │   ├─ TargetColorBox (Frame)
	     │   │   ├─ UICorner
	     │   │   ├─ UIStroke (OuterStroke)
	     │   │   └─ Glow (Frame + UICorner)
	     │   ├─ Instruction (TextLabel)
	     │   └─ CountdownBar (Frame + UICorner)
	     └─ GridContainer (Frame) -- Phase 2: 5x5 color grid
	         ├─ UICorner
	         ├─ UIStroke
	         ├─ Title (TextLabel)
	         ├─ GridArea (Frame)
	         │   └─ UIGridLayout
	         └─ Feedback (TextLabel + UICorner + UIStroke)

	USAGE: Paste into the Roblox Studio Command Bar and press Enter.
	       Grid color buttons are created dynamically at runtime by game logic.

	NOTE: Color Rush uses its OWN ScreenGui (separate from MinigameUI)
	      with DisplayOrder = 100 and starts Enabled = false.
]]

local StarterGui = game:GetService("StarterGui")

-- Safety check: don't duplicate
if StarterGui:FindFirstChild("ColorRushUI") then
	warn("[ColorRushUISetup] ColorRushUI already exists in StarterGui. Aborting to avoid duplicates.")
	return
end

-- ============================================
-- SCREENGUI (separate from MinigameUI)
-- ============================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ColorRushUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 100
screenGui.Enabled = false
screenGui.Parent = StarterGui

-- ============================================
-- PREVIEW CONTAINER (Phase 1 - shows target color)
-- ============================================
local previewContainer = Instance.new("Frame")
previewContainer.Name = "PreviewContainer"
previewContainer.Size = UDim2.fromScale(0.45, 0.55)
previewContainer.Position = UDim2.fromScale(0.275, 0.225)
previewContainer.AnchorPoint = Vector2.new(0, 0)
previewContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
previewContainer.BackgroundTransparency = 0.05
previewContainer.BorderSizePixel = 0
previewContainer.Visible = false
previewContainer.Parent = screenGui

local previewCorner = Instance.new("UICorner")
previewCorner.CornerRadius = UDim.new(0, 24)
previewCorner.Parent = previewContainer

local previewOuterStroke = Instance.new("UIStroke")
previewOuterStroke.Name = "OuterStroke"
previewOuterStroke.Color = Color3.fromRGB(80, 80, 140)
previewOuterStroke.Thickness = 4
previewOuterStroke.Transparency = 0.3
previewOuterStroke.Parent = previewContainer

-- Preview title
local previewTitle = Instance.new("TextLabel")
previewTitle.Name = "Title"
previewTitle.Size = UDim2.fromScale(1, 0.15)
previewTitle.Position = UDim2.fromScale(0, 0.06)
previewTitle.BackgroundTransparency = 1
previewTitle.Font = Enum.Font.GothamBlack
previewTitle.TextSize = 34
previewTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
previewTitle.Text = "🎨 REMEMBER THIS COLOR! 🎨"
previewTitle.Parent = previewContainer

-- Target color box (centered with strong visual emphasis)
local targetColorBox = Instance.new("Frame")
targetColorBox.Name = "TargetColorBox"
targetColorBox.Size = UDim2.fromScale(0.45, 0.48)
targetColorBox.Position = UDim2.fromScale(0.275, 0.26)
targetColorBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
targetColorBox.BorderSizePixel = 0
targetColorBox.Parent = previewContainer

local targetCorner = Instance.new("UICorner")
targetCorner.CornerRadius = UDim.new(0, 18)
targetCorner.Parent = targetColorBox

local targetOuterStroke = Instance.new("UIStroke")
targetOuterStroke.Name = "OuterStroke"
targetOuterStroke.Color = Color3.fromRGB(255, 255, 255)
targetOuterStroke.Thickness = 6
targetOuterStroke.Transparency = 0
targetOuterStroke.Parent = targetColorBox

-- Inner glow effect
local targetGlow = Instance.new("Frame")
targetGlow.Name = "Glow"
targetGlow.Size = UDim2.fromScale(1.12, 1.12)
targetGlow.Position = UDim2.fromScale(-0.06, -0.06)
targetGlow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
targetGlow.BackgroundTransparency = 0.7
targetGlow.BorderSizePixel = 0
targetGlow.ZIndex = -1
targetGlow.Parent = targetColorBox

local glowCorner = Instance.new("UICorner")
glowCorner.CornerRadius = UDim.new(0, 22)
glowCorner.Parent = targetGlow

-- Instruction text
local instructionText = Instance.new("TextLabel")
instructionText.Name = "Instruction"
instructionText.Size = UDim2.fromScale(1, 0.12)
instructionText.Position = UDim2.fromScale(0, 0.82)
instructionText.BackgroundTransparency = 1
instructionText.Font = Enum.Font.GothamMedium
instructionText.TextSize = 22
instructionText.TextColor3 = Color3.fromRGB(180, 180, 210)
instructionText.Text = "Find this color in the grid!"
instructionText.Parent = previewContainer

-- Countdown timer visual
local countdownBar = Instance.new("Frame")
countdownBar.Name = "CountdownBar"
countdownBar.Size = UDim2.fromScale(0.8, 0.025)
countdownBar.Position = UDim2.fromScale(0.1, 0.77)
countdownBar.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
countdownBar.BorderSizePixel = 0
countdownBar.Parent = previewContainer

local countdownCorner = Instance.new("UICorner")
countdownCorner.CornerRadius = UDim.new(1, 0)
countdownCorner.Parent = countdownBar

-- ============================================
-- GRID CONTAINER (Phase 2 - 5x5 color grid)
-- ============================================
local gridContainer = Instance.new("Frame")
gridContainer.Name = "GridContainer"
gridContainer.Size = UDim2.fromScale(0.55, 0.75)
gridContainer.Position = UDim2.fromScale(0.225, 0.125)
gridContainer.AnchorPoint = Vector2.new(0, 0)
gridContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
gridContainer.BackgroundTransparency = 0.05
gridContainer.BorderSizePixel = 0
gridContainer.Visible = false
gridContainer.Parent = screenGui

local gridCorner = Instance.new("UICorner")
gridCorner.CornerRadius = UDim.new(0, 24)
gridCorner.Parent = gridContainer

local gridStroke = Instance.new("UIStroke")
gridStroke.Color = Color3.fromRGB(80, 80, 140)
gridStroke.Thickness = 4
gridStroke.Transparency = 0.3
gridStroke.Parent = gridContainer

-- Grid title
local gridTitle = Instance.new("TextLabel")
gridTitle.Name = "Title"
gridTitle.Size = UDim2.fromScale(1, 0.08)
gridTitle.Position = UDim2.fromScale(0, 0.02)
gridTitle.BackgroundTransparency = 1
gridTitle.Font = Enum.Font.GothamBlack
gridTitle.TextSize = 30
gridTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
gridTitle.Text = "⚡ FIND THE COLOR! ⚡"
gridTitle.Parent = gridContainer

-- Grid area (where color buttons will be placed at runtime)
local gridArea = Instance.new("Frame")
gridArea.Name = "GridArea"
gridArea.Size = UDim2.fromScale(0.92, 0.82)
gridArea.Position = UDim2.fromScale(0.04, 0.12)
gridArea.BackgroundTransparency = 1
gridArea.Parent = gridContainer

-- UIGridLayout for the 5x5 grid
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromScale(0.175, 0.175)
gridLayout.CellPadding = UDim2.fromScale(0.0125, 0.0125)
gridLayout.FillDirection = Enum.FillDirection.Horizontal
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridArea

-- Feedback label (for correct/wrong selections)
local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "Feedback"
feedbackLabel.Size = UDim2.fromScale(0.5, 0.1)
feedbackLabel.Position = UDim2.fromScale(0.25, 0.45)
feedbackLabel.AnchorPoint = Vector2.new(0, 0)
feedbackLabel.BackgroundColor3 = Color3.fromRGB(50, 200, 80)
feedbackLabel.BackgroundTransparency = 0.1
feedbackLabel.Font = Enum.Font.GothamBlack
feedbackLabel.TextSize = 36
feedbackLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
feedbackLabel.Text = ""
feedbackLabel.Visible = false
feedbackLabel.ZIndex = 10
feedbackLabel.Parent = gridContainer

local feedbackCorner = Instance.new("UICorner")
feedbackCorner.CornerRadius = UDim.new(0, 15)
feedbackCorner.Parent = feedbackLabel

local feedbackStroke = Instance.new("UIStroke")
feedbackStroke.Color = Color3.fromRGB(255, 255, 255)
feedbackStroke.Thickness = 3
feedbackStroke.Transparency = 0.5
feedbackStroke.Parent = feedbackLabel

-- ============================================
-- DONE
-- ============================================
print("[ColorRushUISetup] ✅ Color Rush UI hierarchy created successfully in StarterGui > ColorRushUI")
print("[ColorRushUISetup] Hierarchy:")
print("  ColorRushUI (ScreenGui, DisplayOrder=100, Enabled=false)")
print("    ├─ PreviewContainer (Frame) -- Phase 1")
print("    │   ├─ Title, TargetColorBox (+ Glow), Instruction")
print("    │   └─ CountdownBar")
print("    └─ GridContainer (Frame) -- Phase 2")
print("        ├─ Title")
print("        ├─ GridArea (+ UIGridLayout) -- buttons spawn here")
print("        └─ Feedback")
