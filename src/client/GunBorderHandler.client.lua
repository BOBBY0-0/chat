--[[
    GunBorderHandler (Client)
    =========================
    LOCATION: StarterPlayerScripts
    
    Manages local border collision for the gun holder.
    - If Player has Gun AND Protection is Active -> Border Collision = FALSE
    - Otherwise -> Border Collision = TRUE (if Protection Active) or FALSE (if Inactive)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local theFive = Workspace:WaitForChild("TheFive", 10)
local borderPart = theFive and theFive:WaitForChild("BorderPart", 10)

if not theFive or not borderPart then
	warn("[GunBorderHandler] Could not find TheFive or BorderPart!")
	return
end

local TOOL_NAME = "TheFiveGun"

-- ============================================
-- STATE UPDATE LOGIC
-- ============================================

local function updateBorderCollision()
	if not theFive or not borderPart then
		return
	end

	-- 1. Check if protection is active (default to false if nil)
	local protectionActive = theFive:GetAttribute("ProtectionActive") == true

	-- 2. Check if player has the gun
	local hasGun = false
	local character = player.Character
	if character then
		if character:FindFirstChild(TOOL_NAME) then
			hasGun = true
		end
	end

	-- Also check backpack (though usually collision matters when equipped/holding)
	local backpack = player:FindFirstChild("Backpack")
	if backpack and backpack:FindFirstChild(TOOL_NAME) then
		hasGun = true
	end

	-- 3. Determine desired collision state
	local shouldCollide = false

	if protectionActive then
		if hasGun then
			-- key requirement: Gun holder can pass through
			shouldCollide = false
			-- print("[GunBorderHandler] Protection Active + Has Gun -> Collision DISABLED")
		else
			-- Everyone else is blocked
			shouldCollide = true
		end
	else
		-- Protection inactive -> everyone can pass
		shouldCollide = false
	end

	-- 4. Apply to BorderPart (handle both Part and Model)
	if borderPart:IsA("BasePart") then
		borderPart.CanCollide = shouldCollide
		borderPart.CanQuery = shouldCollide -- Also disable query so mouse ignores it
	elseif borderPart:IsA("Model") then
		for _, part in pairs(borderPart:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = shouldCollide
				part.CanQuery = shouldCollide
			end
		end
	end
end

-- ============================================
-- EVENT CONNECTIONS
-- ============================================

-- Monitor ProtectionActive attribute
theFive:GetAttributeChangedSignal("ProtectionActive"):Connect(updateBorderCollision)

-- Monitor Character changes (respawn)
player.CharacterAdded:Connect(function(newCharacter)
	-- Wait for child added/removed in character (tool equip/unequip)
	newCharacter.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			updateBorderCollision()
		end
	end)

	newCharacter.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			updateBorderCollision()
		end
	end)

	updateBorderCollision()
end)

-- Monitor Backpack changes (picking up gun)
local function monitorBackpack(bp)
	bp.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			updateBorderCollision()
		end
	end)

	bp.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			updateBorderCollision()
		end
	end)
end

if player:FindFirstChild("Backpack") then
	monitorBackpack(player.Backpack)
end

player.ChildAdded:Connect(function(child)
	if child.Name == "Backpack" then
		monitorBackpack(child)
	end
end)

-- Initial check
if player.Character then
	player.Character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			updateBorderCollision()
		end
	end)
	player.Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			updateBorderCollision()
		end
	end)
end

updateBorderCollision()
print("[GunBorderHandler] Initialized")
