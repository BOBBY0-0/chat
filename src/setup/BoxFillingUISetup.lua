--[[
	BoxFillingUISetup (Command Script)
	====================================
	PURPOSE: Run once in Roblox Studio Command Bar to create the permanent
	Box Filling minigame GUI hierarchy inside the existing MinigameUI ScreenGui.

	HIERARCHY CREATED:
	MinigameUI (ScreenGui) -- must already exist from MazeUISetup
	 └─ BoxFillingContainer (Frame)
	     ├─ UICorner
	     ├─ UIStroke
	     ├─ TargetLabel (TextLabel)
	     ├─ TotalLabel (TextLabel)
	     ├─ Instructions (TextLabel)
	     ├─ BoxesFrame (Frame)
	     │   ├─ UIListLayout
	     │   ├─ Box1 (TextButton + UICorner + LimitLabel)
	     │   ├─ Box2 (TextButton + UICorner + LimitLabel)
	     │   ├─ Box3 (TextButton + UICorner + LimitLabel)
	     │   └─ Box4 (TextButton + UICorner + LimitLabel)
	     └─ SubmitButton (TextButton)
	         └─ UICorner

	USAGE: Run MazeUISetup FIRST (creates MinigameUI), then paste this into
	       the Roblox Studio Command Bar and press Enter.

	NOTE: Game logic (click handlers, submit, Enter key) remains in
	      TableUIHandler.client.lua — this script is UI structure only.
]]

local StarterGui = game:GetService("StarterGui")

-- Find existing MinigameUI (created by MazeUISetup)
local screenGui = StarterGui:FindFirstChild("MinigameUI")
if not screenGui then
	warn("[BoxFillingUISetup] MinigameUI not found in StarterGui. Run MazeUISetup first!")
	return
end

-- Safety check: don't duplicate
if screenGui:FindFirstChild("BoxFillingContainer") then
	warn("[BoxFillingUISetup] BoxFillingContainer already exists. Aborting to avoid duplicates.")
	return
end

-- ============================================
-- BOX FILLING CONTAINER
-- ============================================
local boxFillingContainer = Instance.new("Frame")
boxFillingContainer.Name = "BoxFillingContainer"
boxFillingContainer.Size = UDim2.new(0.6, 0, 0.6, 0)
boxFillingContainer.Position = UDim2.new(0.2, 0, 0.2, 0)
boxFillingContainer.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
boxFillingContainer.BackgroundTransparency = 0.05
boxFillingContainer.BorderSizePixel = 0
boxFillingContainer.Visible = false
boxFillingContainer.Parent = screenGui

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 20)
boxCorner.Parent = boxFillingContainer

local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Color3.fromRGB(80, 120, 180)
boxStroke.Thickness = 3
boxStroke.Parent = boxFillingContainer

-- ============================================
-- TARGET LABEL
-- ============================================
local targetLabel = Instance.new("TextLabel")
targetLabel.Name = "TargetLabel"
targetLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
targetLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
targetLabel.BackgroundTransparency = 1
targetLabel.Font = Enum.Font.GothamBold
targetLabel.TextSize = 32
targetLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
targetLabel.Text = "TARGET: 0"
targetLabel.Parent = boxFillingContainer

-- ============================================
-- TOTAL LABEL
-- ============================================
local totalLabel = Instance.new("TextLabel")
totalLabel.Name = "TotalLabel"
totalLabel.Size = UDim2.new(0.9, 0, 0.1, 0)
totalLabel.Position = UDim2.new(0.05, 0, 0.17, 0)
totalLabel.BackgroundTransparency = 1
totalLabel.Font = Enum.Font.GothamBold
totalLabel.TextSize = 26
totalLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
totalLabel.Text = "YOUR TOTAL: 0"
totalLabel.Parent = boxFillingContainer

-- ============================================
-- INSTRUCTIONS
-- ============================================
local boxInstructions = Instance.new("TextLabel")
boxInstructions.Name = "Instructions"
boxInstructions.Size = UDim2.new(0.9, 0, 0.06, 0)
boxInstructions.Position = UDim2.new(0.05, 0, 0.27, 0)
boxInstructions.BackgroundTransparency = 1
boxInstructions.Font = Enum.Font.Gotham
boxInstructions.TextSize = 14
boxInstructions.TextColor3 = Color3.fromRGB(180, 180, 200)
boxInstructions.Text = "Click boxes to add! Over 10 clicks = reset. Match the target!"
boxInstructions.Parent = boxFillingContainer

-- ============================================
-- BOXES FRAME (holds the 4 clickable boxes)
-- ============================================
local boxesFrame = Instance.new("Frame")
boxesFrame.Name = "BoxesFrame"
boxesFrame.Size = UDim2.new(0.9, 0, 0.35, 0)
boxesFrame.Position = UDim2.new(0.05, 0, 0.35, 0)
boxesFrame.BackgroundTransparency = 1
boxesFrame.Parent = boxFillingContainer

local boxLayout = Instance.new("UIListLayout")
boxLayout.FillDirection = Enum.FillDirection.Horizontal
boxLayout.Padding = UDim.new(0.03, 0)
boxLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
boxLayout.VerticalAlignment = Enum.VerticalAlignment.Center
boxLayout.Parent = boxesFrame

-- ============================================
-- BOX BUTTONS (4 clickable boxes with colors)
-- ============================================
local BOX_COLORS = {
	Color3.fromRGB(255, 100, 120), -- Box1: Red-pink
	Color3.fromRGB(100, 200, 255), -- Box2: Light blue
	Color3.fromRGB(150, 255, 150), -- Box3: Light green
	Color3.fromRGB(255, 200, 100), -- Box4: Orange-gold
}

for i = 1, 4 do
	local box = Instance.new("TextButton")
	box.Name = "Box" .. i
	box.Size = UDim2.new(0.2, 0, 1, 0)
	box.BackgroundColor3 = BOX_COLORS[i]
	box.BorderSizePixel = 0
	box.Text = "0"
	box.TextSize = 36
	box.TextColor3 = Color3.fromRGB(255, 255, 255)
	box.Font = Enum.Font.GothamBold
	box.AutoButtonColor = false
	box.Parent = boxesFrame

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 12)
	bCorner.Parent = box

	local limitLabel = Instance.new("TextLabel")
	limitLabel.Name = "LimitLabel"
	limitLabel.Size = UDim2.new(1, 0, 0.25, 0)
	limitLabel.Position = UDim2.new(0, 0, 0.75, 0)
	limitLabel.BackgroundTransparency = 1
	limitLabel.Font = Enum.Font.Gotham
	limitLabel.TextSize = 12
	limitLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	limitLabel.Text = "/10"
	limitLabel.Parent = box
end

-- ============================================
-- SUBMIT BUTTON
-- ============================================
local submitButton = Instance.new("TextButton")
submitButton.Name = "SubmitButton"
submitButton.Size = UDim2.new(0.4, 0, 0.12, 0)
submitButton.Position = UDim2.new(0.3, 0, 0.75, 0)
submitButton.BackgroundColor3 = Color3.fromRGB(80, 180, 120)
submitButton.BorderSizePixel = 0
submitButton.Text = "SUBMIT (Enter)"
submitButton.TextSize = 20
submitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
submitButton.Font = Enum.Font.GothamBold
submitButton.AutoButtonColor = false
submitButton.Parent = boxFillingContainer

local submitCorner = Instance.new("UICorner")
submitCorner.CornerRadius = UDim.new(0, 10)
submitCorner.Parent = submitButton

-- ============================================
-- DONE
-- ============================================
print("[BoxFillingUISetup] ✅ Box Filling UI hierarchy created successfully in MinigameUI > BoxFillingContainer")
print("[BoxFillingUISetup] Hierarchy:")
print("  BoxFillingContainer (Frame)")
print("    ├─ TargetLabel, TotalLabel, Instructions")
print("    ├─ BoxesFrame (Frame)")
print("    │   ├─ UIListLayout")
print("    │   ├─ Box1..Box4 (TextButtons + UICorner + LimitLabel)")
print("    └─ SubmitButton (TextButton + UICorner)")
