--[[
    ColorRushMinigame (ModuleScript)
    ================================
    LOCATION: ReplicatedStorage/Modules/Minigames
    
    Color Rush minigame where players must remember a target color
    shown briefly, then select the correct color from a 5×5 grid.
    First player to select the correct color wins instantly.
    
    POLISHED VERSION - Professional UI, smooth animations, unique colors.
]]

local ColorRushMinigame = {}

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remote events (will be set on init)
local colorRushPreviewEvent = nil
local colorRushShowGridEvent = nil
local playerColorSelectedEvent = nil
local endColorRushGameEvent = nil

-- State
local isActive = false
local hasWon = false -- Only lock input when someone wins
local screenGui = nil
local previewContainer = nil
local gridContainer = nil
local currentTargetColorIndex = nil

-- Extended color palette (25 distinct colors for unique grid)
local COLORS = {
	{ name = "Crimson", color = Color3.fromRGB(220, 20, 60) },
	{ name = "DeepBlue", color = Color3.fromRGB(30, 60, 180) },
	{ name = "Emerald", color = Color3.fromRGB(46, 204, 113) },
	{ name = "Gold", color = Color3.fromRGB(255, 215, 0) },
	{ name = "Tangerine", color = Color3.fromRGB(255, 140, 0) },
	{ name = "Violet", color = Color3.fromRGB(138, 43, 226) },
	{ name = "Teal", color = Color3.fromRGB(0, 128, 128) },
	{ name = "HotPink", color = Color3.fromRGB(255, 105, 180) },
	{ name = "Lime", color = Color3.fromRGB(50, 205, 50) },
	{ name = "Magenta", color = Color3.fromRGB(255, 0, 144) },
	{ name = "SkyBlue", color = Color3.fromRGB(135, 206, 235) },
	{ name = "Coral", color = Color3.fromRGB(255, 127, 80) },
	{ name = "Orchid", color = Color3.fromRGB(218, 112, 214) },
	{ name = "Mint", color = Color3.fromRGB(62, 180, 137) },
	{ name = "Peach", color = Color3.fromRGB(255, 218, 185) },
	{ name = "Lavender", color = Color3.fromRGB(230, 190, 255) },
	{ name = "SlateBlue", color = Color3.fromRGB(106, 90, 205) },
	{ name = "SeaGreen", color = Color3.fromRGB(32, 178, 170) },
	{ name = "Salmon", color = Color3.fromRGB(250, 128, 114) },
	{ name = "Turquoise", color = Color3.fromRGB(64, 224, 208) },
	{ name = "Amber", color = Color3.fromRGB(255, 191, 0) },
	{ name = "Maroon", color = Color3.fromRGB(128, 0, 0) },
	{ name = "Navy", color = Color3.fromRGB(0, 0, 128) },
	{ name = "Olive", color = Color3.fromRGB(128, 128, 0) },
	{ name = "Plum", color = Color3.fromRGB(221, 160, 221) },
}

local GRID_SIZE = 5 -- 5x5 grid
local colorButtons = {} -- Store button references

-- Track which buttons have been clicked (for visual feedback)
local clickedButtons = {}

-- ============================================
-- UI CREATION
-- ============================================
local function createUI()
	-- Reference the pre-built UI from StarterGui (replicated to PlayerGui)
	screenGui = playerGui:WaitForChild("ColorRushUI")
	previewContainer = screenGui:WaitForChild("PreviewContainer")
	gridContainer = screenGui:WaitForChild("GridContainer")
end

-- ============================================
-- ANIMATION HELPERS
-- ============================================
local function animatePreviewIn()
	previewContainer.Size = UDim2.fromScale(0, 0)
	previewContainer.Position = UDim2.fromScale(0.5, 0.5)
	previewContainer.BackgroundTransparency = 1
	previewContainer.Visible = true

	local tween =
		TweenService:Create(previewContainer, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(0.45, 0.55),
			Position = UDim2.fromScale(0.275, 0.225),
			BackgroundTransparency = 0.05,
		})
	tween:Play()

	-- Animate countdown bar
	local countdownBar = previewContainer:FindFirstChild("CountdownBar")
	if countdownBar then
		countdownBar.Size = UDim2.fromScale(0.8, 0.025)
		local countdownTween = TweenService:Create(
			countdownBar,
			TweenInfo.new(3, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(0, 0.025) }
		)
		task.delay(0.5, function()
			countdownTween:Play()
		end)
	end

	return tween
end

local function animatePreviewOut()
	local tween =
		TweenService:Create(previewContainer, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.fromScale(0, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
		})
	tween:Play()
	tween.Completed:Connect(function()
		previewContainer.Visible = false
	end)
	return tween
end

local function animateGridIn()
	gridContainer.Position = UDim2.fromScale(0.225, 1.2)
	gridContainer.BackgroundTransparency = 1
	gridContainer.Visible = true

	local tween =
		TweenService:Create(gridContainer, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.225, 0.125),
			BackgroundTransparency = 0.05,
		})
	tween:Play()
	return tween
end

-- Shake animation for wrong selection
local function shakeButton(button)
	local originalRotation = button.Rotation
	local shakeTween1 = TweenService:Create(button, TweenInfo.new(0.05), { Rotation = 8 })
	local shakeTween2 = TweenService:Create(button, TweenInfo.new(0.05), { Rotation = -8 })
	local shakeTween3 = TweenService:Create(button, TweenInfo.new(0.05), { Rotation = 6 })
	local shakeTween4 = TweenService:Create(button, TweenInfo.new(0.05), { Rotation = -6 })
	local shakeTween5 = TweenService:Create(button, TweenInfo.new(0.05), { Rotation = originalRotation })

	shakeTween1:Play()
	shakeTween1.Completed:Connect(function()
		shakeTween2:Play()
	end)
	shakeTween2.Completed:Connect(function()
		shakeTween3:Play()
	end)
	shakeTween3.Completed:Connect(function()
		shakeTween4:Play()
	end)
	shakeTween4.Completed:Connect(function()
		shakeTween5:Play()
	end)
end

-- Pulse animation for correct selection
local function pulseCorrectButton(button, stroke)
	-- Create expanding glow effect
	local originalSize = button.Size

	local pulseTween = TweenService:Create(
		button,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(originalSize.X.Scale * 1.15, 0, originalSize.Y.Scale * 1.15, 0) }
	)
	pulseTween:Play()

	-- Make stroke glow green
	TweenService:Create(stroke, TweenInfo.new(0.1), {
		Color = Color3.fromRGB(100, 255, 150),
		Thickness = 8,
		Transparency = 0,
	}):Play()
end

-- Hover animation
local function setupButtonHover(button, originalColor, stroke)
	button.MouseEnter:Connect(function()
		if hasWon then
			return
		end
		TweenService:Create(
			button,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad),
			{ BackgroundColor3 = originalColor:Lerp(Color3.fromRGB(255, 255, 255), 0.2) }
		):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Thickness = 4, Transparency = 0.2 }):Play()
	end)

	button.MouseLeave:Connect(function()
		if hasWon or clickedButtons[button] then
			return
		end
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { BackgroundColor3 = originalColor })
			:Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Thickness = 3, Transparency = 0.4 }):Play()
	end)
end

-- Create color buttons in grid with staggered animation
local function createColorButtons(correctColorIndex, colorDistribution)
	local gridArea = gridContainer:FindFirstChild("GridArea")
	if not gridArea then
		return
	end

	-- Clear existing buttons
	for _, data in pairs(colorButtons) do
		if data.button and data.button.Parent then
			data.button:Destroy()
		end
	end
	colorButtons = {}
	clickedButtons = {}

	-- Create 25 buttons (5x5 grid)
	for i = 1, GRID_SIZE * GRID_SIZE do
		local colorData = COLORS[colorDistribution[i]]
		if not colorData then
			colorData = COLORS[1] -- Fallback
		end
		local isCorrect = (colorDistribution[i] == correctColorIndex)

		local button = Instance.new("TextButton")
		button.Name = "ColorBtn_" .. i
		button.LayoutOrder = i
		button.BackgroundColor3 = colorData.color
		button.BorderSizePixel = 0
		button.Text = ""
		button.AutoButtonColor = false
		button.Size = UDim2.fromScale(1, 1) -- Will be controlled by grid layout
		button.BackgroundTransparency = 1 -- Start invisible for animation
		button.Parent = gridArea

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = button

		-- Semi-transparent stroke for modern look
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 3
		stroke.Transparency = 0.4
		stroke.Parent = button

		-- Store reference with original color for feedback reset
		colorButtons[i] = {
			button = button,
			isCorrect = isCorrect,
			colorIndex = colorDistribution[i],
			originalColor = colorData.color,
			stroke = stroke,
		}

		-- Setup hover effects
		setupButtonHover(button, colorData.color, stroke)

		-- Click handler - ALLOWS MULTIPLE CLICKS until someone wins
		button.MouseButton1Click:Connect(function()
			if not isActive or hasWon then
				return
			end

			if isCorrect then
				-- CORRECT! First correct click wins
				hasWon = true
				print("[ColorRush] Correct color selected!")

				-- Visual feedback - pulse and glow
				pulseCorrectButton(button, stroke)

				-- Show feedback
				local feedback = gridContainer:FindFirstChild("Feedback")
				if feedback then
					feedback.Text = "✓ CORRECT!"
					feedback.BackgroundColor3 = Color3.fromRGB(50, 200, 80)
					feedback.Visible = true

					-- Animate feedback in
					feedback.Size = UDim2.fromScale(0, 0)
					feedback.Position = UDim2.fromScale(0.5, 0.5)
					TweenService:Create(feedback, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
						Size = UDim2.fromScale(0.5, 0.1),
						Position = UDim2.fromScale(0.25, 0.45),
					}):Play()
				end

				-- Fire to server
				if playerColorSelectedEvent then
					playerColorSelectedEvent:FireServer(true)
				end
			else
				-- WRONG! Give feedback but ALLOW more clicks
				print("[ColorRush] Wrong color - try again!")
				clickedButtons[button] = true

				-- Visual feedback - shake and red flash
				shakeButton(button)

				-- Brief red flash
				local originalColor = colorData.color
				TweenService:Create(button, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(255, 80, 80),
				}):Play()

				-- Red stroke flash
				TweenService:Create(stroke, TweenInfo.new(0.1), {
					Color = Color3.fromRGB(255, 50, 50),
					Thickness = 5,
					Transparency = 0,
				}):Play()

				-- Brief wrong feedback
				local feedback = gridContainer:FindFirstChild("Feedback")
				if feedback then
					feedback.Text = "✗ TRY AGAIN!"
					feedback.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
					feedback.Visible = true

					task.delay(0.8, function()
						if feedback and feedback.Parent and not hasWon then
							feedback.Visible = false
						end
					end)
				end

				-- Fade button to dim (mark as tried)
				task.delay(0.3, function()
					if button and button.Parent and not hasWon then
						TweenService:Create(button, TweenInfo.new(0.3), {
							BackgroundColor3 = originalColor:Lerp(Color3.fromRGB(60, 60, 60), 0.5),
							BackgroundTransparency = 0.3,
						}):Play()
						TweenService:Create(stroke, TweenInfo.new(0.3), {
							Color = Color3.fromRGB(150, 150, 150),
							Thickness = 2,
							Transparency = 0.6,
						}):Play()
					end
				end)

				-- Fire to server (incorrect - for tracking)
				if playerColorSelectedEvent then
					playerColorSelectedEvent:FireServer(false)
				end
			end
		end)

		-- Staggered pop-in animation with scale effect
		task.delay(i * 0.025, function()
			if button and button.Parent then
				-- Start small
				button.Size = UDim2.fromScale(0.01, 0.01)
				button.BackgroundTransparency = 0

				local popTween = TweenService:Create(
					button,
					TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromScale(1, 1) }
				)
				popTween:Play()
			end
		end)
	end
end

-- ============================================
-- PUBLIC INTERFACE
-- ============================================

function ColorRushMinigame:Init()
	createUI()

	-- Get remote events
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if remoteEvents then
		colorRushPreviewEvent = remoteEvents:FindFirstChild("ColorRushPreview")
		colorRushShowGridEvent = remoteEvents:FindFirstChild("ColorRushShowGrid")
		playerColorSelectedEvent = remoteEvents:FindFirstChild("PlayerColorSelected")
		endColorRushGameEvent = remoteEvents:FindFirstChild("EndColorRushGame")

		-- Listen for preview event
		if colorRushPreviewEvent then
			colorRushPreviewEvent.OnClientEvent:Connect(function(colorIndex)
				if not isActive then
					return
				end

				currentTargetColorIndex = colorIndex
				local colorData = COLORS[colorIndex]
				if not colorData then
					return
				end

				-- Update preview color
				local targetColorBox = previewContainer:FindFirstChild("TargetColorBox")
				if targetColorBox then
					targetColorBox.BackgroundColor3 = colorData.color

					-- Update glow color to match
					local glow = targetColorBox:FindFirstChild("Glow")
					if glow then
						glow.BackgroundColor3 = colorData.color
					end
				end

				-- Show preview with animation
				animatePreviewIn()
			end)
		end

		-- Listen for grid reveal event
		if colorRushShowGridEvent then
			colorRushShowGridEvent.OnClientEvent:Connect(function(correctColorIndex, colorDistribution)
				if not isActive then
					return
				end

				-- Hide preview with animation
				animatePreviewOut()

				-- Wait for preview to disappear
				task.wait(0.4)

				-- Show grid with animation
				animateGridIn()

				-- Create color buttons
				createColorButtons(correctColorIndex, colorDistribution)
			end)
		end

		-- Listen for game end
		if endColorRushGameEvent then
			endColorRushGameEvent.OnClientEvent:Connect(function(_winnerName)
				self:Stop()
			end)
		end
	end

	print("[ColorRushMinigame] Initialized (Polished Version)")
end

function ColorRushMinigame:Start(participatingPlayers)
	print("[ColorRushMinigame] Starting with " .. #participatingPlayers .. " players")

	-- Reset state
	isActive = true
	hasWon = false
	currentTargetColorIndex = nil
	clickedButtons = {}

	-- Clear old buttons
	for _, data in pairs(colorButtons) do
		if data.button and data.button.Parent then
			data.button:Destroy()
		end
	end
	colorButtons = {}

	-- Hide feedback
	local feedback = gridContainer:FindFirstChild("Feedback")
	if feedback then
		feedback.Visible = false
	end

	-- Show UI
	if screenGui then
		screenGui.Enabled = true
	end
end

function ColorRushMinigame:Stop()
	isActive = false
	hasWon = false

	-- Hide UI with slight delay for feedback visibility
	task.delay(1.5, function()
		if screenGui then
			screenGui.Enabled = false
		end

		-- Reset visibility
		if previewContainer then
			previewContainer.Visible = false
		end
		if gridContainer then
			gridContainer.Visible = false
		end

		-- Clear buttons
		for _, data in pairs(colorButtons) do
			if data.button and data.button.Parent then
				data.button:Destroy()
			end
		end
		colorButtons = {}
		clickedButtons = {}
	end)
end

function ColorRushMinigame:Hide()
	if screenGui then
		screenGui.Enabled = false
	end
end

return ColorRushMinigame
