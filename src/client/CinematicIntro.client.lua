local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Animation IDs
local ANIM_SEATED_IDLE = "rbxassetid://76129862168914"
local ANIM_WAKE_UP = "rbxassetid://90761287039919"
local ANIM_READY_IDLE = "rbxassetid://82343077486319"

-- Services & Events
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
if not remoteEvents then
	warn("CinematicIntro: RemoteEvents folder not found!")
	return
end

local showTypingTextEvent = remoteEvents:WaitForChild("ShowTypingText")

-- Sequential intro events
local showIntroBackgroundEvent = remoteEvents:WaitForChild("ShowIntroBackground")
local playPlayerIntroEvent = remoteEvents:WaitForChild("PlayPlayerIntro")
local playerIntroFinishedEvent = remoteEvents:WaitForChild("PlayerIntroFinished")

-- State
local introTracks = {} -- Tracks for intro-only animations (Seated, Wake) - cleaned on round reset
local introActive = false
local introThread = nil
local seatedTrack = nil -- Specifically track the seated idle for persistent looping
local readyIdleTrack = nil -- PERSISTENT: Animation 3 lives independently from intro cleanup
local backgroundTransitionActive = false -- Guards against cleanup during background-masked lighting transition

-- ============================================
-- CLIENT-SIDE LIGHTING SYSTEM (preset-based, per-player)
-- ============================================
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local DifferentLighting = ReplicatedStorage:FindFirstChild("DifferentLighting")

-- Remove ALL existing lighting children (Sky, Atmosphere, PostEffects) but NOT the fade CC
local function clearLightingChildren()
	for _, child in pairs(Lighting:GetChildren()) do
		if child.Name == "_LightingFade" then
			continue
		end
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("PostEffect") then
			child:Destroy()
		end
	end
end

-- Apply a lighting preset fully from its folder (Settings + children)
-- Works for BOTH "Default" and "GameLightingTheFive"
local function applyLightingPreset(presetName)
	if not DifferentLighting then
		warn("[CLIENT] DifferentLighting folder not found!")
		return
	end

	local preset = DifferentLighting:FindFirstChild(presetName)
	if not preset then
		warn("[CLIENT] Lighting preset '" .. presetName .. "' not found!")
		return
	end

	-- Step 1: Clear ALL existing lighting children (no leftovers)
	clearLightingChildren()

	-- Step 2: Clone effect objects (Atmosphere, Sky, ColorCorrection, DepthOfField, etc.)
	-- Only clone non-Settings children (skip the Settings folder itself)
	for _, obj in pairs(preset:GetChildren()) do
		if obj.Name ~= "Settings" then
			local clone = obj:Clone()
			clone.Parent = Lighting
		end
	end

	-- Step 3: Apply Lighting service properties from Settings folder
	local settings = preset:FindFirstChild("Settings")
	if settings then
		for _, valueObj in pairs(settings:GetChildren()) do
			-- Read the .Value from any ValueObject type (NumberValue, Color3Value, BoolValue, etc.)
			if not valueObj:IsA("ValueBase") then
				continue
			end

			-- Map Settings names to Lighting property names (handle naming differences)
			local propName = valueObj.Name
			local lightingPropName = propName
			if propName == "ColorShiftBottom" then
				lightingPropName = "ColorShift_Bottom"
			elseif propName == "ColorShiftTop" then
				lightingPropName = "ColorShift_Top"
			end

			pcall(function()
				Lighting[lightingPropName] = valueObj.Value
			end)
		end
	end

	print("[CLIENT] Applied lighting preset: " .. presetName)
end

-- Cinematic fade transition when applying a preset
local function applyLightingWithFade(presetName, useFade)
	if useFade then
		-- Create temporary fade effect
		local fadeCC = Instance.new("ColorCorrectionEffect")
		fadeCC.Name = "_LightingFade"
		fadeCC.Brightness = 0
		fadeCC.Parent = Lighting

		-- Fade to black
		local fadeOut =
			TweenService:Create(fadeCC, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Brightness = -1,
			})
		fadeOut:Play()
		fadeOut.Completed:Wait()

		-- Apply preset while screen is dark
		applyLightingPreset(presetName)

		-- Re-create fade CC if it was removed during preset swap
		local existingFade = Lighting:FindFirstChild("_LightingFade")
		if not existingFade then
			fadeCC = Instance.new("ColorCorrectionEffect")
			fadeCC.Name = "_LightingFade"
			fadeCC.Brightness = -1
			fadeCC.Parent = Lighting
		else
			fadeCC = existingFade
		end

		-- Fade back in
		local fadeIn =
			TweenService:Create(fadeCC, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Brightness = 0,
			})
		fadeIn:Play()
		fadeIn.Completed:Wait()

		fadeCC:Destroy()
	else
		applyLightingPreset(presetName)
	end
end

-- Listen for server lighting events
local applyGameLightingEvent = remoteEvents:WaitForChild("ApplyGameLighting", 10)
local restoreDefaultLightingEvent = remoteEvents:WaitForChild("RestoreDefaultLighting", 10)

if applyGameLightingEvent then
	applyGameLightingEvent.OnClientEvent:Connect(function()
		print("[CLIENT] ApplyGameLighting received")
		applyLightingWithFade("GameLightingTheFive", true)
	end)
end

if restoreDefaultLightingEvent then
	restoreDefaultLightingEvent.OnClientEvent:Connect(function()
		print("[CLIENT] RestoreDefaultLighting received")
		applyLightingWithFade("Default", true)
	end)
end

-- Background-masked lighting restore event (handler connected below after getIntroUI is defined)
local restoreDefaultWithBackgroundEvent = remoteEvents:WaitForChild("RestoreDefaultWithBackground", 10)

-- ============================================
-- ANIMATION HELPERS
-- ============================================

-- Stop intro-only animations (Seated + Wake). Does NOT touch Ready Idle.
local function stopIntroAnimations()
	for _, track in pairs(introTracks) do
		if track then
			track:Stop()
		end
	end
	table.clear(introTracks)
	seatedTrack = nil
end

-- Stop Ready Idle (Animation 3). Only called on TRUE game end.
local function stopReadyIdle()
	if readyIdleTrack then
		readyIdleTrack:Stop()
		readyIdleTrack = nil
	end
end

-- Stop everything (intro + ready idle). Only for hard stops.
local function stopAllAnimations()
	stopIntroAnimations()
	stopReadyIdle()
end

-- ============================================
-- UI HELPERS
-- ============================================

local function getIntroUI()
	local startIntro = playerGui:WaitForChild("StartIntro", 5)
	if not startIntro then
		return nil
	end

	local background = startIntro:WaitForChild("Background", 5)
	local announcements = startIntro:WaitForChild("Announcements", 5)
	local sound = startIntro:FindFirstChild("Start")
	if not sound then
		sound = startIntro:FindFirstChild("Start", true)
	end

	return {
		ScreenGui = startIntro,
		Background = background,
		Announcements = announcements,
		Sound = sound,
	}
end

-- Helper: Text Typewriter Effect
local function typeText(label, text)
	label.RichText = false
	label.Text = ""
	label.Visible = true

	for i = 1, #text do
		if not introActive then
			return
		end
		label.Text = string.sub(text, 1, i)
		task.wait(0.05)
	end
end

-- Helper: Random Letter Disappearance
local function randomDisappear(label)
	label.RichText = true
	local text = label.Text
	local length = #text
	local indices = {}
	for i = 1, length do
		table.insert(indices, i)
	end

	for i = length, 2, -1 do
		local j = math.random(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end

	local currentTextTable = {}
	for i = 1, length do
		table.insert(currentTextTable, string.sub(text, i, i))
	end

	for _, indexToRemove in ipairs(indices) do
		if not introActive then
			return
		end
		local char = currentTextTable[indexToRemove]
		currentTextTable[indexToRemove] = '<font transparency="1">' .. char .. "</font>"
		label.Text = table.concat(currentTextTable)
		task.wait(0.05)
	end

	label.Visible = false
	label.RichText = false
end

-- ============================================
-- SEATED ANIMATION (Immediate on sit)
-- ============================================

local function onSeated(active, seatPart)
	if not active then
		-- Player stood up - stop seated animation
		if seatedTrack then
			seatedTrack:Stop()
			seatedTrack = nil
		end
		-- Also stop Animation 3 (Ready Idle) when unseated - game has ended
		stopReadyIdle()
		return
	end

	if not seatPart or not seatPart:IsDescendantOf(Workspace:WaitForChild("TheFive"):WaitForChild("Chairs")) then
		return
	end

	if introActive then
		return
	end

	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator")
	if not animator then
		return
	end

	if seatedTrack then
		seatedTrack:Stop()
	end

	local animSeated = Instance.new("Animation")
	animSeated.AnimationId = ANIM_SEATED_IDLE
	seatedTrack = animator:LoadAnimation(animSeated)
	seatedTrack.Looped = true
	seatedTrack:Play()
end

-- ============================================
-- SEQUENTIAL INTRO HANDLERS
-- ============================================

-- Handler 1: Show static background "waiting curtain" to this player
-- Called when server fires ShowIntroBackground to ALL players at once
local function onShowIntroBackground()
	print("[CLIENT] ShowIntroBackground received - showing static background")
	introActive = true

	-- Lighting is applied via server ApplyGameLighting event (no local override clearing needed)

	local ui = getIntroUI()
	if not ui or not ui.Background then
		warn("CinematicIntro: StartIntro UI not found for background!")
		return
	end

	-- Show background at full opacity (no animation, just static)
	ui.Background.BackgroundTransparency = 0
	ui.Background.Visible = true

	-- Hide announcements
	if ui.Announcements then
		ui.Announcements.Visible = false
		-- Ensure text is always readable, wraps properly, and stays centered
		ui.Announcements.TextWrapped = true
		ui.Announcements.TextScaled = true
		ui.Announcements.TextXAlignment = Enum.TextXAlignment.Center
		ui.Announcements.TextYAlignment = Enum.TextYAlignment.Center
		-- Constrain auto-scaling: min 18px (readable), max 36px (cinematic)
		if not ui.Announcements:FindFirstChildOfClass("UITextSizeConstraint") then
			local sizeConstraint = Instance.new("UITextSizeConstraint")
			sizeConstraint.MinTextSize = 18
			sizeConstraint.MaxTextSize = 36
			sizeConstraint.Parent = ui.Announcements
		end
	end

	-- Ensure seated animation is playing
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		local animator = humanoid and humanoid:FindFirstChild("Animator")
		if animator then
			if not seatedTrack then
				local animSeated = Instance.new("Animation")
				animSeated.AnimationId = ANIM_SEATED_IDLE
				seatedTrack = animator:LoadAnimation(animSeated)
				seatedTrack.Looped = true
				seatedTrack:Play()
				table.insert(introTracks, seatedTrack)
			elseif not table.find(introTracks, seatedTrack) then
				table.insert(introTracks, seatedTrack)
			end
		end
	end
end

-- Handler 2: Play this player's intro sequence (wake up)
-- Called when server fires PlayPlayerIntro to ONLY THIS player
local function onPlayPlayerIntro()
	print("[CLIENT] PlayPlayerIntro received - playing intro sequence")

	if introThread then
		task.cancel(introThread)
	end

	introThread = task.spawn(function()
		local ui = getIntroUI()
		if not ui or not ui.Background then
			warn("CinematicIntro: StartIntro UI not found for player intro!")
			-- Still notify server so the sequence doesn't stall
			local finEvent = remoteEvents:FindFirstChild("PlayerIntroFinished")
			if finEvent then
				finEvent:FireServer()
			end
			return
		end

		local character = player.Character or player.CharacterAdded:Wait()
		local humanoid = character:WaitForChild("Humanoid")
		local animator = humanoid:WaitForChild("Animator")

		-- Pre-load animations
		local animWake = Instance.new("Animation")
		animWake.AnimationId = ANIM_WAKE_UP
		local trackWake = animator:LoadAnimation(animWake)
		table.insert(introTracks, trackWake)

		local animReady = Instance.new("Animation")
		animReady.AnimationId = ANIM_READY_IDLE
		local trackReady = animator:LoadAnimation(animReady)

		-- 1. Play sound while background is still fully visible
		if ui.Sound then
			ui.Sound:Play()
		end

		-- 2. Wait 2 seconds (sound plays over visible background)
		task.wait(2)

		-- 3. Fade out background, then continue sequence
		local fadeOutTween = TweenService:Create(
			ui.Background,
			TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		fadeOutTween:Play()
		fadeOutTween.Completed:Wait()
		ui.Background.Visible = false

		-- Stop seated animation, play wake
		if seatedTrack then
			seatedTrack:Stop()
		end
		trackWake:Play()

		if trackWake.Length > 0 then
			task.wait(trackWake.Length)
		else
			trackWake.Stopped:Wait()
		end

		-- 3. Ready Idle (PERSISTENT - stored separately)
		trackWake:Stop()
		stopReadyIdle() -- Stop any previous ready idle

		trackReady.Looped = true
		trackReady:Play()
		readyIdleTrack = trackReady -- Store persistently, NOT in introTracks

		-- 4. Wait for sound to finish if still playing
		if ui.Sound and ui.Sound.IsPlaying then
			ui.Sound.Ended:Wait()
		end

		-- 5. Notify server that this player's intro is done
		local finEvent = remoteEvents:FindFirstChild("PlayerIntroFinished")
		if finEvent then
			finEvent:FireServer()
			print("[CLIENT] Fired PlayerIntroFinished to server")
		end

		-- Ready Idle keeps playing - it persists until hard stop
	end)
end

-- Handler 3: Show announcement text only (no background, no animations)
-- Called AFTER all players have finished their individual intros
local function onShowAnnouncementText(announcementText)
	print("[CLIENT] ShowTypingText received (announcement only) - text: " .. tostring(announcementText))

	if introThread then
		task.cancel(introThread)
	end

	introActive = true

	introThread = task.spawn(function()
		local ui = getIntroUI()
		if not ui or not ui.Announcements then
			warn("CinematicIntro: Announcements UI not found!")
			introActive = false
			return
		end

		-- Make sure background is hidden (it should be already)
		if ui.Background then
			ui.Background.Visible = false
		end

		if not introActive then
			return
		end

		-- Type announcement text
		ui.Announcements.Text = ""
		ui.Announcements.RichText = false
		typeText(ui.Announcements, announcementText)

		task.wait(2)

		if introActive then
			randomDisappear(ui.Announcements)
		end

		-- Extra 2s pause after text disappears before minigame starts
		task.wait(2)

		-- Signal server that announcement sequence is complete
		local introCompleteEvent = remoteEvents:FindFirstChild("IntroSequenceComplete")
		if introCompleteEvent then
			introCompleteEvent:FireServer()
			print("[CLIENT] Fired IntroSequenceComplete to server")
		end

		introActive = false
		-- Ready Idle keeps playing - it persists until hard stop
	end)
end

-- ============================================
-- CLEANUP FUNCTIONS
-- ============================================

-- Soft cleanup: stops intro sequence + hides UI, but KEEPS Animation 3 alive.
-- Called on: HideAllUI, ForceGunReset, round resets, kill phase timeout
local function softCleanup()
	introActive = false
	if introThread then
		task.cancel(introThread)
		introThread = nil
	end
	stopIntroAnimations() -- Only stops Seated + Wake, NOT Ready Idle

	local ui = getIntroUI()
	if ui then
		-- Skip background hide if background-masked transition is running
		if ui.Background and not backgroundTransitionActive then
			ui.Background.Visible = false
		end
		if ui.Announcements then
			ui.Announcements.Visible = false
		end
		if ui.Sound then
			ui.Sound:Stop()
		end
	end
end

-- Hard cleanup: stops EVERYTHING including Animation 3.
-- Called on: player dies, player leaves, character removing, game cancelled
local function hardCleanup()
	introActive = false
	if introThread then
		task.cancel(introThread)
		introThread = nil
	end
	stopAllAnimations() -- Stops intro tracks AND Ready Idle

	-- Skip lighting restore if background-masked transition is handling it
	if not backgroundTransitionActive then
		applyLightingPreset("Default")
	end

	local ui = getIntroUI()
	if ui then
		-- Skip background hide if background-masked transition is running
		if ui.Background and not backgroundTransitionActive then
			ui.Background.Visible = false
		end
		if ui.Announcements then
			ui.Announcements.Visible = false
		end
		if ui.Sound then
			ui.Sound:Stop()
		end
	end
end

-- ============================================
-- EVENT CONNECTIONS
-- ============================================

-- Sequential intro events
showIntroBackgroundEvent.OnClientEvent:Connect(onShowIntroBackground)
playPlayerIntroEvent.OnClientEvent:Connect(onPlayPlayerIntro)

-- Announcement text (replaces old playIntroSequence binding)
showTypingTextEvent.OnClientEvent:Connect(onShowAnnouncementText)

-- Winner announcement (cinematic typing effect, NO IntroSequenceComplete callback)
local showWinnerAnnouncementEvent = remoteEvents:WaitForChild("ShowWinnerAnnouncement", 10)
if showWinnerAnnouncementEvent then
	showWinnerAnnouncementEvent.OnClientEvent:Connect(function(winnerText)
		print("[CLIENT] ShowWinnerAnnouncement received - text: " .. tostring(winnerText))

		if introThread then
			task.cancel(introThread)
		end

		introActive = true

		introThread = task.spawn(function()
			local ui = getIntroUI()
			if not ui or not ui.Announcements then
				warn("CinematicIntro: Announcements UI not found for winner!")
				introActive = false
				return
			end

			-- Hide background if visible
			if ui.Background then
				ui.Background.Visible = false
			end

			if not introActive then
				return
			end

			-- Type winner announcement text
			ui.Announcements.Text = ""
			ui.Announcements.RichText = false
			typeText(ui.Announcements, winnerText)

			task.wait(3)

			if introActive then
				randomDisappear(ui.Announcements)
			end

			task.wait(1)

			introActive = false
			-- No IntroSequenceComplete fired — this is end-game, not intro
		end)
	end)
end

-- Background-masked lighting restore (used at end of round for smooth transition)
if restoreDefaultWithBackgroundEvent then
	restoreDefaultWithBackgroundEvent.OnClientEvent:Connect(function()
		print("[CLIENT] RestoreDefaultWithBackground received")

		-- Set flag to prevent hardCleanup/softCleanup from interfering
		backgroundTransitionActive = true

		local ui = getIntroUI()
		if not ui or not ui.Background then
			-- Fallback: no UI available, just swap lighting directly
			applyLightingPreset("Default")
			backgroundTransitionActive = false
			return
		end

		-- Step 1: Fade background IN (covers screen)
		ui.Background.BackgroundTransparency = 1
		ui.Background.Visible = true

		local fadeIn = TweenService:Create(
			ui.Background,
			TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ BackgroundTransparency = 0 }
		)
		fadeIn:Play()
		fadeIn.Completed:Wait()

		-- Step 2: Swap lighting behind the fully opaque background
		applyLightingPreset("Default")

		-- Small pause to let lighting fully settle
		task.wait(0.3)

		-- Step 3: Fade background OUT (reveals default-lit scene)
		local fadeOut = TweenService:Create(
			ui.Background,
			TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ BackgroundTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Wait()

		ui.Background.Visible = false
		backgroundTransitionActive = false
		print("[CLIENT] Background-masked lighting restore complete")
	end)
end

-- Hard cleanup: game fully ended (Animation 3 stops)
if remoteEvents:FindFirstChild("GameFullyEnded") then
	remoteEvents.GameFullyEnded.OnClientEvent:Connect(hardCleanup)
end

-- Soft cleanup events (Animation 3 survives these)
if remoteEvents:FindFirstChild("HideAllUI") then
	remoteEvents.HideAllUI.OnClientEvent:Connect(softCleanup)
end

if remoteEvents:FindFirstChild("ForceGunReset") then
	remoteEvents.ForceGunReset.OnClientEvent:Connect(softCleanup)
end

-- Hard cleanup events (Animation 3 stops on these)
local function onCharacterAdded(newChar)
	local humanoid = newChar:WaitForChild("Humanoid")
	humanoid.Died:Connect(hardCleanup)
	humanoid.Seated:Connect(onSeated)
end

player.CharacterRemoving:Connect(hardCleanup)
if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

script.Destroying:Connect(hardCleanup)

-- Initial UI Hide
task.spawn(function()
	local ui = getIntroUI()
	if ui then
		if ui.Background then
			ui.Background.Visible = false
		end
		if ui.Announcements then
			ui.Announcements.Visible = false
		end
	end
end)
