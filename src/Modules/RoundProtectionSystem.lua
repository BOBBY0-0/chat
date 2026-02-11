--[[
    RoundProtectionSystem (ModuleScript)
    =====================================
    LOCATION: ReplicatedStorage/Modules
    
    Handles round protection to prevent outsiders from interfering with active games:
    - Border wall activation (collision toggle on BorderPart)
    - Chair locking (disable unoccupied seats at round start)
]]

local RoundProtectionSystem = {}

-- Services
local workspace = game:GetService("Workspace")

-- Cache references
local theFive = nil
local borderPart = nil
local chairsFolder = nil

-- State tracking
local lockedSeats = {} -- Seats that were locked at round start
local isProtectionActive = false

-- ============================================
-- INITIALIZATION
-- ============================================
local function ensureReferences()
	if not theFive then
		theFive = workspace:FindFirstChild("TheFive")
		if not theFive then
			warn("[RoundProtectionSystem] TheFive model not found in workspace!")
			return false
		end
	end

	if not borderPart then
		borderPart = theFive:FindFirstChild("BorderPart")
		if not borderPart then
			warn("[RoundProtectionSystem] BorderPart not found in TheFive!")
		end
	end

	if not chairsFolder then
		chairsFolder = theFive:FindFirstChild("Chairs")
		if not chairsFolder then
			warn("[RoundProtectionSystem] Chairs folder not found in TheFive!")
		end
	end

	return true
end

-- ============================================
-- BORDER WALL FUNCTIONS
-- ============================================

-- Enable collision on BorderPart (blocks outsiders from entering)
function RoundProtectionSystem:ActivateBorderWall()
	if not ensureReferences() then
		return
	end

	if theFive then
		theFive:SetAttribute("ProtectionActive", true)
	end

	if borderPart then
		-- Handle both single part and model with multiple parts
		if borderPart:IsA("BasePart") then
			borderPart.CanCollide = true
			print("[RoundProtectionSystem] BorderPart collision enabled")
		elseif borderPart:IsA("Model") then
			for _, part in pairs(borderPart:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = true
				end
			end
			print("[RoundProtectionSystem] BorderPart model collision enabled")
		end
	end
end

-- Disable collision on BorderPart (allows free movement)
function RoundProtectionSystem:DeactivateBorderWall()
	if not ensureReferences() then
		return
	end

	if theFive then
		theFive:SetAttribute("ProtectionActive", false)
	end

	if borderPart then
		-- Handle both single part and model with multiple parts
		if borderPart:IsA("BasePart") then
			borderPart.CanCollide = false
			print("[RoundProtectionSystem] BorderPart collision disabled")
		elseif borderPart:IsA("Model") then
			for _, part in pairs(borderPart:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
			print("[RoundProtectionSystem] BorderPart model collision disabled")
		end
	end
end

-- ============================================
-- CHAIR LOCKING FUNCTIONS
-- ============================================

-- Lock all unoccupied chairs (prevent new players from sitting)
function RoundProtectionSystem:LockUnoccupiedChairs()
	if not ensureReferences() then
		return
	end
	if not chairsFolder then
		return
	end

	lockedSeats = {} -- Reset tracking

	for _, chair in pairs(chairsFolder:GetChildren()) do
		local seat = chair:FindFirstChild("Seat")
		if seat and seat:IsA("Seat") then
			-- Only lock if seat is NOT occupied
			if not seat.Occupant then
				seat.Disabled = true
				table.insert(lockedSeats, seat)
				print("[RoundProtectionSystem] Locked empty seat: " .. chair.Name)
			end
		end
	end

	print("[RoundProtectionSystem] Locked " .. #lockedSeats .. " empty chairs")
end

-- Unlock all chairs (restore normal functionality)
function RoundProtectionSystem:UnlockAllChairs()
	-- Unlock specifically tracked seats
	for _, seat in pairs(lockedSeats) do
		if seat and seat.Parent then
			seat.Disabled = false
		end
	end

	print("[RoundProtectionSystem] Unlocked " .. #lockedSeats .. " chairs")
	lockedSeats = {}

	-- Also ensure ALL seats are unlocked (safety fallback)
	if chairsFolder then
		for _, chair in pairs(chairsFolder:GetChildren()) do
			local seat = chair:FindFirstChild("Seat")
			if seat and seat:IsA("Seat") then
				seat.Disabled = false
			end
		end
	end
end

-- ============================================
-- COMBINED PROTECTION FUNCTIONS
-- ============================================

-- Start all round protections
function RoundProtectionSystem:StartRoundProtection()
	if isProtectionActive then
		print("[RoundProtectionSystem] Protection already active, skipping")
		return
	end

	print("[RoundProtectionSystem] ========== STARTING ROUND PROTECTION ==========")

	-- Activate border wall first (block entry)
	self:ActivateBorderWall()

	-- Then lock unoccupied chairs
	self:LockUnoccupiedChairs()

	isProtectionActive = true
	print("[RoundProtectionSystem] Round protection ACTIVE")
end

-- End all round protections
function RoundProtectionSystem:EndRoundProtection()
	if not isProtectionActive then
		print("[RoundProtectionSystem] Protection not active, skipping")
		return
	end

	print("[RoundProtectionSystem] ========== ENDING ROUND PROTECTION ==========")

	-- Deactivate border wall
	self:DeactivateBorderWall()

	-- Unlock all chairs
	self:UnlockAllChairs()

	isProtectionActive = false
	print("[RoundProtectionSystem] Round protection DEACTIVATED")
end

-- Check if protection is currently active
function RoundProtectionSystem:IsActive()
	return isProtectionActive
end

return RoundProtectionSystem
