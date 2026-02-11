--By Rufus14
local tweenservice = game:GetService("TweenService")
local runservice = game:GetService("RunService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")

-- Shared active players registry for validating targets
local ActivePlayersRegistry = require(replicatedstorage:WaitForChild("Modules"):WaitForChild("ActivePlayersRegistry"))

local TOOL_NAME = "TheFiveGun" -- set this to your Tool's name
local function isToolOwned(t)
	if not t then
		return false
	end
	for _, player in ipairs(players:GetPlayers()) do
		local character = player.Character
		if character and t:IsDescendantOf(character) then
			return true
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and t:IsDescendantOf(backpack) then
			return true
		end
	end
	return false
end
local function findTool()
	if script and script.Parent and script.Parent:IsA("Tool") and isToolOwned(script.Parent) then
		return script.Parent
	end
	for _, player in ipairs(players:GetPlayers()) do
		local character = player.Character
		if character then
			local t = character:FindFirstChild(TOOL_NAME)
			if t and t:IsA("Tool") then
				return t
			end
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			local t = backpack:FindFirstChild(TOOL_NAME)
			if t and t:IsA("Tool") then
				return t
			end
		end
	end
end
local function waitForTool()
	local t = findTool()
	while not t do
		task.wait(0.2)
		t = findTool()
	end
	return t
end
local tool
local owner
local character
local charroot
local charhum
local charhead
local remote = replicatedstorage:WaitForChild("Events"):WaitForChild("gunremote")

-- BindableEvent for server-to-server shot notification (notifies ChairWaitingSystem)
local shotUsedEvent = replicatedstorage:WaitForChild("Events"):FindFirstChild("ShotUsedEvent")
if not shotUsedEvent then
	shotUsedEvent = Instance.new("BindableEvent")
	shotUsedEvent.Name = "ShotUsedEvent"
	shotUsedEvent.Parent = replicatedstorage:WaitForChild("Events")
end

-- BindableEvent for empty gun click notification (for testing alternating empty gun rounds)
local emptyClickEvent = replicatedstorage:WaitForChild("Events"):FindFirstChild("EmptyClickEvent")
if not emptyClickEvent then
	emptyClickEvent = Instance.new("BindableEvent")
	emptyClickEvent.Name = "EmptyClickEvent"
	emptyClickEvent.Parent = replicatedstorage:WaitForChild("Events")
end

-- BindableFunction to query the currently highlighted player from AimHighlightHandler
-- Used for highlight-locked elimination (guaranteed kill when highlighted target exists)
local getHighlightedPlayerFunc = replicatedstorage:WaitForChild("Events"):FindFirstChild("GetHighlightedPlayer")
if not getHighlightedPlayerFunc then
	-- Wait briefly in case AimHighlightHandler hasn't created it yet
	task.delay(2, function()
		if not getHighlightedPlayerFunc then
			getHighlightedPlayerFunc = replicatedstorage:WaitForChild("Events"):FindFirstChild("GetHighlightedPlayer")
			if getHighlightedPlayerFunc then
				print("[GUN] GetHighlightedPlayer BindableFunction found (delayed)")
			else
				warn("[GUN] GetHighlightedPlayer BindableFunction not found - highlight-locked kills disabled")
			end
		end
	end)
end

local gunmodel
local handle
local cylinder
local barrelend
local currentwelds = {} --dont repeat names
local currentsounds = {} --dont repeat names
local ignoretable = {}
local leftarmneutralc0
local lookpartheight = 0.2
local armYawDivisor = 0.8 -- lower = more left/right aiming (was 1.5)
local ammochambered = 1 -- ONE BULLET ONLY
local maxchamber = 1 -- ONE BULLET SYSTEM
local lastsenthitmarker = tick()
local currentequiptick = tick()
local currentanimtick = tick()
local aiming = false

local toolstate = "idle"

-- Listen for SetGunAmmo event to allow external control of ammo (for alternating empty gun rounds)
local setGunAmmoEvent = replicatedstorage:WaitForChild("Events"):FindFirstChild("SetGunAmmo")
if not setGunAmmoEvent then
	setGunAmmoEvent = Instance.new("BindableEvent")
	setGunAmmoEvent.Name = "SetGunAmmo"
	setGunAmmoEvent.Parent = replicatedstorage:WaitForChild("Events")
end

setGunAmmoEvent.Event:Connect(function(targetPlayer, ammoCount)
	-- Only apply ammo change if this gun belongs to the targeted player
	if owner and owner == targetPlayer then
		ammochambered = ammoCount
		print("[GUN] Ammo set to " .. tostring(ammoCount) .. " for " .. owner.Name)
	end
end)

local limbdmgmultiplier = {
	["Head"] = 1 / 0,
	["Torso"] = 1,
	["Leg"] = 0.75,
	["Foot"] = 0.6,
	["Arm"] = 0.5,
	["Hand"] = 0.4,
}
local headattachments = {
	"FaceCenterAttachment",
	"FaceFrontAttachment",
	"HairAttachment",
	"HatAttachment",
	"NeckRigAttachment",
}
--if youre adding more ammo types then also add a function with the same bullet name to the "shootfunction" just ctrl f or something idk
local ammotype =
	{ --damage | shoot sound name | speed (studs per FPS multiplied by single delta) | penetration (in studs) | ws penalty | ws penalty duration | drop (cf per multiplied by delta) | speed drop (multiplied by delta) | color | hole size | base damage lost per penetration (multiplied by 1+wall width)
		[".357 Magnum"] = { 70, "shootnormal", 2e3, 2, 5, 0.5, 0.01, 1e3, Color3.fromRGB(255, 255, 255), 0.35, 10 },
		[".410 Shell"] = { 10, "shootshell", 1500, 0.7, 5, 0.5, 0.01, 1e3, Color3.fromRGB(255, 255, 255), 0.35, 1 },
	}
local ammonames = {}
for i, v in pairs(ammotype) do
	ammonames[#ammonames + 1] = i
end
local currentselectedammo = 2
local currentchamberedammo = currentselectedammo

local cylinderweld
local hammerweld
local runfunc

local easingstyles = Enum.EasingStyle
local easingdirs = Enum.EasingDirection
local tfind = table.find

local sfxdata = { --dont repeat names (id, vol, rollmin, rollmax, playonremove)
	["impact1"] = { "341519743", 4, 0.2, 60, true },
	["impact2"] = { "1489924400", 4, 0.2, 60, true },
	["impact4"] = { "1476374050", 4, 0.2, 60, true },
	["impact3"] = { "3802437361", 4, 0.2, 60, true },
	["case1"] = { "2712534526", 2, 0.5, 60 },
	["case2"] = { "2712533735", 2, 0.5, 60 },
	["case3"] = { "2712535138", 2, 0.5, 60 },
	["gore1"] = { "4459570664", 1, 1, 60, true },
	["gore2"] = { "4459571224", 1, 1, 60, true },
	["gore3"] = { "4459571342", 1, 1, 60, true },
	["gore4"] = { "4459571443", 1, 1, 60, true },
	["snap"] = { "4086190876", 1, 1, 60, true },
	["bone"] = { "4086172420", 1, 1, 60, true },
	["pull"] = { "3292840510", 1, 1, 60 },
	["supersonic1"] = { "6113434720", 10, 0.025, 1, true },
	["supersonic2"] = { "3809084884", 10, 0.025, 1, true },
	["shootnormal"] = { "2323962833", 5, 1, 100 },
	["shootshell"] = { "7432112097", 1.5, 2, 100 },
	["shootaway"] = { "6320964561", 0.5, 2.5, 300 },
	["click"] = { "132464034", 4, 1, 60 },
	["equip"] = { "4549835866", 2.5, 1, 60 },
	["hl2reload"] = { "7227843922", 2, 1, 60 },
	["reload"] = { "8213803325", 2, 1, 60 },
}
local sfxbehavior = {
	["shootnormal"] = function(sound)
		local eq = Instance.new("EqualizerSoundEffect", sound)
		eq.HighGain = 2
		eq.LowGain = 10
		eq.MidGain = 0
	end,
	["shootshell"] = function(sound)
		local eq = Instance.new("EqualizerSoundEffect", sound)
		eq.HighGain = 2
		eq.LowGain = 10
		eq.MidGain = 0
	end,
}
local animrawdata = { --cf, easingstyle, easingdirection, normal speed
	["equip"] = {
		[1] = {
			["cylinderweld"] = {
				CFrame.new(-0.386173308, 0, 0.742014229, 0.866025388, 0, 0.5, 0, 1, 0, -0.5, 0, 0.866025388),
				easingstyles.Linear,
				easingdirs.Out,
				0,
			},
			["rarmweld"] = {
				CFrame.new(
					0.581273079,
					-0.699999809,
					-1.24858856,
					0.939692557,
					0.342020154,
					-6.51350496e-16,
					5.09649878e-09,
					-1.40025094e-08,
					-0.999999881,
					-0.342020094,
					0.939692438,
					-1.4901163e-08
				),
				easingstyles.Back,
				easingdirs.Out,
				0.4,
			},
			["larmweld"] = {
				CFrame.new(
					-0.516624451,
					-0.941628456,
					-1.47424138,
					-0.0593912154,
					-0.494882852,
					0.866927624,
					0.98480767,
					-0.171010062,
					-0.0301536433,
					0.163175881,
					0.851966143,
					0.497520924
				),
				easingstyles.Back,
				easingdirs.Out,
				0.4,
			},
			["headtorootweld"] = {
				CFrame.new(-1.23977661e-05, 0.300000191, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
				easingstyles.Back,
				easingdirs.Out,
				0.4,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.4 },
			["handleweld"] = {
				CFrame.new(
					-0.230419159,
					-1.36331868,
					-0.242621899,
					0.144542605,
					0.939691722,
					-0.309976667,
					-0.397127301,
					0.342020363,
					0.851652205,
					0.906309485,
					8.39294501e-08,
					0.422614098
				),
				easingstyles.Linear,
				easingdirs.Out,
				0.1,
			},
		},
		[2] = {
			["handleweld"] = {
				CFrame.new(
					-0.529827118,
					-0.833085537,
					-0.976356268,
					0.17101194,
					0.939691067,
					0.296197861,
					-0.469849497,
					0.342020631,
					-0.81379503,
					-0.866022766,
					2.46258338e-07,
					0.500003636
				),
				easingstyles.Linear,
				easingdirs.Out,
				0.1,
			},
		},
		[3] = {
			["handleweld"] = {
				CFrame.new(
					-0.3095541,
					-0.853526115,
					-0.14615345,
					-0.29619813,
					0.939692378,
					0.171010077,
					0.813797355,
					0.342020094,
					-0.4698461,
					-0.49999997,
					1.40485792e-08,
					-0.866025329
				),
				easingstyles.Back,
				easingdirs.Out,
				0.2,
			},
		},
	},
	["idle"] = {
		[1] = {
			["rarmweld"] = {
				CFrame.new(
					0.581273079,
					-0.699999809,
					-1.24858856,
					0.939692557,
					0.342020154,
					-6.51350496e-16,
					5.09649878e-09,
					-1.40025094e-08,
					-0.999999881,
					-0.342020094,
					0.939692438,
					-1.4901163e-08
				),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["larmweld"] = {
				CFrame.new(
					-0.516624451,
					-0.941628456,
					-1.47424138,
					-0.0593912154,
					-0.494882852,
					0.866927624,
					0.98480767,
					-0.171010062,
					-0.0301536433,
					0.163175881,
					0.851966143,
					0.497520924
				),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["headtorootweld"] = {
				CFrame.new(-1.23977661e-05, 0.300000191, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.3 },
			["handleweld"] = {
				CFrame.new(
					-0.3095541,
					-0.853526115,
					-0.14615345,
					-0.29619813,
					0.939692378,
					0.171010077,
					0.813797355,
					0.342020094,
					-0.4698461,
					-0.49999997,
					1.40485792e-08,
					-0.866025329
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.3,
			},
		},
	},
	["hammer"] = { --1 is pulled
		[1] = {
			["hammerweld"] = {
				CFrame.new(
					0.0966377258,
					9.53674316e-07,
					0.523095846,
					-0.707106471,
					-2.41757959e-07,
					0.707104743,
					-8.68540951e-07,
					0.999996901,
					-5.81955078e-07,
					-0.707104862,
					-1.11191844e-06,
					-0.707106411
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.1,
			},
		},
		[2] = {
			["hammerweld"] = {
				CFrame.new(
					0.0200212169,
					-3.27069245e-07,
					0.604648292,
					-0.173624277,
					0,
					0.984811902,
					0,
					1,
					0,
					-0.984811902,
					0,
					-0.173624277
				),
				easingstyles.Linear,
				easingdirs.InOut,
				0,
			},
		},
	},
	["pullhammer"] = {
		[1] = {
			["rarmweld"] = {
				CFrame.new(
					0.571992874,
					-0.810137272,
					-1.27408552,
					0.939692557,
					0.336824089,
					-0.0593911782,
					5.09649878e-09,
					-0.173648164,
					-0.984807611,
					-0.342020094,
					0.92541635,
					-0.163175896
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.25,
			},
			["larmweld"] = {
				CFrame.new(
					-0.47824192,
					-1.0829432,
					-1.5496875,
					-0.102297097,
					-0.487823397,
					0.866927624,
					0.966155708,
					-0.256190926,
					-0.0301536433,
					0.236808687,
					0.834502459,
					0.497520924
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.25,
			},
			["headtorootweld"] = {
				CFrame.new(-1.23977661e-05, 0.300000191, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
				easingstyles.Sine,
				easingdirs.InOut,
				0.25,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.25 },
			["handleweld"] = {
				CFrame.new(
					-0.162091255,
					-0.987659454,
					0.10125351,
					-0.316997468,
					0.948105216,
					0.0246382207,
					0.944333911,
					0.317935288,
					-0.0845160559,
					-0.0879636481,
					-0.00352505408,
					-0.99611336
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.25,
			},
		},
	},
	["shoot"] = {
		[1] = {
			["rarmweld"] = {
				CFrame.new(
					0.706853867,
					-0.85338378,
					-0.903558254,
					0.939692557,
					0.340718657,
					-0.0298090298,
					5.09649878e-09,
					-0.0871557593,
					-0.996194541,
					-0.342020094,
					0.936116576,
					-0.081899628
				),
				easingstyles.Back,
				easingdirs.Out,
				0.1,
			},
			["larmweld"] = {
				CFrame.new(
					-0.522049904,
					-1.17470145,
					-1.07692051,
					-0.059391208,
					-0.494882852,
					0.866927624,
					0.98480773,
					-0.171010017,
					-0.0301536433,
					0.163175881,
					0.851966202,
					0.497520924
				),
				easingstyles.Back,
				easingdirs.Out,
				0.1,
			},
			["headtorootweld"] = {
				CFrame.new(
					-1.23977661e-05,
					0.29809761,
					-0.0435776711,
					1,
					0,
					0,
					0,
					0.99619472,
					0.0871553794,
					0,
					-0.0871553794,
					0.99619472
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.1,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.25 },
			["handleweld"] = {
				CFrame.new(
					-0.208036423,
					-0.875477791,
					-0.0649077892,
					-0.315539211,
					0.947350204,
					0.0544299223,
					0.932750762,
					0.320195854,
					-0.165681332,
					-0.174386472,
					-0.00150941592,
					-0.984675944
				),
				easingstyles.Back,
				easingdirs.Out,
				0.1,
			},
		},
	},
	["aiming"] = {
		[1] = {
			["rarmweld"] = {
				CFrame.new(
					0.686244965,
					-0.694849491,
					-1.36498368,
					0.97231096,
					0.150802031,
					0.178522095,
					0.185443223,
					-0.033036992,
					-0.982099414,
					-0.142204762,
					0.988011777,
					-0.0600874498
				),
				easingstyles.Back,
				easingdirs.Out,
				0.35,
			},
			["larmweld"] = {
				CFrame.new(
					-0.231823921,
					-0.880647659,
					-1.60455871,
					0.207420453,
					-0.533368886,
					0.820057631,
					0.969359219,
					-0.000710717344,
					-0.245646164,
					0.131602854,
					0.845882535,
					0.516878664
				),
				easingstyles.Back,
				easingdirs.Out,
				0.35,
			},
			["headtorootweld"] = {
				CFrame.new(
					0.0864810944,
					0.291190147,
					-0.0353770256,
					0.981060147,
					0.172987461,
					-0.0871557593,
					-0.16550684,
					0.982379317,
					0.0868233591,
					0.100639306,
					-0.070754081,
					0.992403865
				),
				easingstyles.Back,
				easingdirs.Out,
				0.35,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.25 },
			["handleweld"] = {
				CFrame.new(
					-0.213535309,
					-0.782982588,
					-0.21203506,
					-0.145264804,
					0.988752723,
					0.0357116163,
					0.815811515,
					0.140120775,
					-0.56109345,
					-0.559780598,
					-0.0523659661,
					-0.826979578
				),
				easingstyles.Back,
				easingdirs.Out,
				0.35,
			},
		},
	},
	["reload"] = {
		[1] = {
			["rarmweld"] = {
				CFrame.new(
					1.45909214,
					-0.817311764,
					-1.27093649,
					0.945735216,
					-0.141705826,
					-0.292410791,
					-0.313528538,
					-0.161585465,
					-0.935729504,
					0.0853489339,
					0.976631522,
					-0.197245881
				),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["larmweld"] = {
				CFrame.new(
					-1.61120319,
					-1.04845333,
					-1.01484632,
					0.839249372,
					-0.0901277959,
					0.53622508,
					0.535112023,
					0.311947048,
					-0.785075843,
					-0.0965166986,
					0.945814908,
					0.310029775
				),
				easingstyles.Sine,
				easingdirs.In,
				0.15,
			},
			["headtorootweld"] = {
				CFrame.new(
					-1.23977661e-05,
					0.29809761,
					-0.0435776711,
					0.965925872,
					0,
					-0.258818835,
					0.0225574095,
					0.99619472,
					0.0841854736,
					0.257833958,
					-0.087155208,
					0.962250233
				),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.3 },
			["handleweld"] = {
				CFrame.Angles(0.4, -0.4, 0.4) * CFrame.new(
					-0.0345726013,
					-0.807703376,
					-0.135195255,
					-0.394007832,
					0.9182055,
					0.0406943038,
					0.836234808,
					0.376503527,
					-0.398692012,
					-0.381402761,
					-0.123057768,
					-0.916181147
				) * CFrame.Angles(0.5, 0, -0.5),
				easingstyles.Sine,
				easingdirs.Out,
				0.3,
			},
		},
		[2] = {
			["cylinderweld"] = {
				CFrame.new(
					-0.473670363,
					-0.249997139,
					0.59045887,
					0.866023183,
					-2.08616257e-06,
					0.499997288,
					1.60932541e-06,
					0.999998271,
					-1.47521496e-06,
					-0.499997675,
					2.13086605e-06,
					0.866024256
				),
				easingstyles.Bounce,
				easingdirs.Out,
				0.3,
			},
			["rarmweld"] = {
				CFrame.new(
					0.66204071,
					-1.00487018,
					-1.40310073,
					0.906771898,
					0.413311452,
					0.0832948983,
					0.250829071,
					-0.370025605,
					-0.894519687,
					-0.338894099,
					0.832018197,
					-0.439199388
				),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["larmweld"] = {
				CFrame.new(
					-1.24664688,
					-0.334390163,
					-1.54565525,
					0.937740624,
					-0.309682995,
					-0.157285899,
					-0.301955819,
					-0.503056169,
					-0.809788287,
					0.171653956,
					0.806864679,
					-0.56524682
				),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["headtorootweld"] = {
				CFrame.new(
					-1.23977661e-05,
					0.29809761,
					-0.0435776711,
					0.996194661,
					0,
					0.0871559232,
					-0.00759609602,
					0.99619472,
					0.0868235603,
					-0.086824283,
					-0.087155208,
					0.992403865
				),
				easingstyles.Back,
				easingdirs.Out,
				0.3,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.3 },
			["handleweld"] = {
				CFrame.new(
					-0.225281715,
					-0.775023937,
					-0.241071343,
					-0.433821082,
					0.810988128,
					-0.392552257,
					0.885406375,
					0.464435279,
					-0.0189884603,
					0.166915536,
					-0.355806917,
					-0.91953671
				),
				easingstyles.Back,
				easingdirs.Out,
				0.35,
			},
		},
		[3] = {
			["rarmweld"] = {
				CFrame.new(
					0.744299889,
					-1.19729733,
					-1.32542562,
					0.906771898,
					0.421496332,
					0.0102586821,
					0.250829071,
					-0.519735754,
					-0.816675603,
					-0.338894099,
					0.743111789,
					-0.577005386
				),
				easingstyles.Back,
				easingdirs.InOut,
				0.3,
			},
			["larmweld"] = {
				CFrame.new(
					-1.22107124,
					-0.371474028,
					-1.40748167,
					0.869718313,
					-0.48802039,
					-0.0736611113,
					-0.384723216,
					-0.576867878,
					-0.720563173,
					0.309156716,
					0.655026078,
					-0.689465463
				),
				easingstyles.Back,
				easingdirs.InOut,
				0.3,
			},
			["headtorootweld"] = {
				CFrame.new(
					-1.23977661e-05,
					0.29809761,
					-0.0435776711,
					0.996194661,
					0,
					0.0871559232,
					-0.00759609602,
					0.99619472,
					0.0868235603,
					-0.086824283,
					-0.087155208,
					0.992403865
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.3,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.3 },
			["handleweld"] = {
				CFrame.new(
					-0.225281715,
					-0.775023937,
					-0.241071343,
					-0.433821082,
					0.810988128,
					-0.392552257,
					0.885406375,
					0.464435279,
					-0.0189884603,
					0.166915536,
					-0.355806917,
					-0.91953671
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.3,
			},
		},
		[4] = {
			["rarmweld"] = {
				CFrame.new(
					1.04995537,
					-0.949098349,
					-1.50419724,
					0.906771898,
					0.359897166,
					0.219632521,
					0.250829071,
					-0.0417664014,
					-0.967129767,
					-0.338894099,
					0.932056427,
					-0.128145278
				),
				easingstyles.Sine,
				easingdirs.In,
				0.3,
			},
			["larmweld"] = {
				CFrame.new(
					-1.46550846,
					-1.31382942,
					0.0289647579,
					0.998860419,
					-0.00822135806,
					-0.0470123887,
					0.00118347246,
					0.989014983,
					-0.147810012,
					0.0477111042,
					0.147586092,
					0.987897635
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.2,
			},
			["headtorootweld"] = {
				CFrame.new(
					-0.0498123169,
					0.284331799,
					-0.113766909,
					0.819151878,
					-0.0996004045,
					0.564862669,
					-0.0499901921,
					0.968663037,
					0.243295938,
					-0.571393967,
					-0.227533907,
					0.78850311
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.3,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.3 },
			["handleweld"] = {
				CFrame.new(
					-0.225281715,
					-0.775023937,
					-0.241071343,
					-0.433821082,
					0.810988128,
					-0.392552257,
					0.885406375,
					0.464435279,
					-0.0189884603,
					0.166915536,
					-0.355806917,
					-0.91953671
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.3,
			},
		},
		[5] = {
			["moonclip"] = {
				CFrame.new(
					0.241176605,
					-1.00934005,
					-0.289575338,
					0.60723567,
					0.608014822,
					-0.511447072,
					0.793891251,
					-0.438767612,
					0.420970798,
					0.0315523595,
					-0.661662102,
					-0.749130547
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.3,
			},
			["rarmweld"] = {
				CFrame.new(
					0.919113159,
					-1.06223106,
					-1.38861322,
					0.939787447,
					0.153823823,
					0.305184275,
					0.297192037,
					0.0730896071,
					-0.952015996,
					-0.168748647,
					0.98539114,
					0.0229734778
				),
				easingstyles.Sine,
				easingdirs.Out,
				0.3,
			},
			["larmweld"] = {
				CFrame.new(
					-0.869959831,
					-1.11432672,
					-1.67204034,
					0.841543913,
					-0.54012394,
					-0.00835364312,
					0.100708514,
					0.172065318,
					-0.979924023,
					0.53071779,
					0.823807955,
					0.199195445
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.2,
			},
			["headtorootweld"] = {
				CFrame.new(
					-1.23977661e-05,
					0.29809761,
					-0.0435774326,
					0.996194601,
					8.94069672e-08,
					-0.0871557593,
					0.00759596005,
					0.99619472,
					0.0868233591,
					0.0868240595,
					-0.0871549994,
					0.992403865
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.3,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.3 },
			["handleweld"] = {
				CFrame.new(
					-0.456459045,
					-0.749354362,
					-0.306482673,
					-0.221677765,
					0.926017106,
					-0.305540442,
					0.80107373,
					-0.00572191179,
					-0.598540306,
					-0.556004405,
					-0.377440244,
					-0.740536034
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.3,
			},
		},
		[6] = {
			["cylinderweld"] = {
				CFrame.new(-0.386173308, 0, 0.742014229, 0.866025388, 0, 0.5, 0, 1, 0, -0.5, 0, 0.866025388),
				easingstyles.Sine,
				easingdirs.In,
				0.2,
			},
			["rarmweld"] = {
				CFrame.new(
					1.45909214,
					-0.817311764,
					-1.27093649,
					0.945735216,
					-0.141705826,
					-0.292410791,
					-0.313528538,
					-0.161585465,
					-0.935729504,
					0.0853489339,
					0.976631522,
					-0.197245881
				),
				easingstyles.Back,
				easingdirs.InOut,
				0.2,
			},
			["larmweld"] = {
				CFrame.new(
					-1.61120319,
					-1.04845333,
					-1.01484632,
					0.839249372,
					-0.0901277959,
					0.53622508,
					0.535112023,
					0.311947048,
					-0.785075843,
					-0.0965166986,
					0.945814908,
					0.310029775
				) * CFrame.new(0, -0.5, 0) * CFrame.Angles(0.5, -1.2, 1),
				easingstyles.Back,
				easingdirs.InOut,
				0.2,
			},
			["headtorootweld"] = {
				CFrame.new(
					-1.23977661e-05,
					0.29809761,
					-0.0435774326,
					0.996194601,
					8.94069672e-08,
					-0.0871557593,
					0.00759596005,
					0.99619472,
					0.0868233591,
					0.0868240595,
					-0.0871549994,
					0.992403865
				),
				easingstyles.Sine,
				easingdirs.InOut,
				0.3,
			},
			["rootweld"] = { CFrame.new(), easingstyles.Sine, easingdirs.InOut, 0.3 },
			["handleweld"] = {
				CFrame.new(
					-0.0345726013,
					-0.807703376,
					-0.135195255,
					-0.394007832,
					0.9182055,
					0.0406943038,
					0.836234808,
					0.376503527,
					-0.398692012,
					-0.381402761,
					-0.123057768,
					-0.916181147
				),
				easingstyles.Back,
				easingdirs.InOut,
				0.3,
			},
		},
	},
}
tween = function(speed, easingstyle, easingdirection, loopcount, WHAT, goal)
	local info = TweenInfo.new(speed, easingstyle, easingdirection, loopcount)
	local goals = goal
	local anim = tweenservice:Create(WHAT, info, goals)
	anim:Play()
end
pose = function(posename, index, speed, senttick)
	if senttick == currentanimtick then
		for i, v in pairs(animrawdata[posename][index]) do
			if currentwelds[i] then
				if i == "larmweld" and toolstate ~= "reloading" then
					--keep left arm relaxed outside of reload
					continue
				end
				tween(v[4] * speed, v[2], v[3], 0, currentwelds[i], { C0 = v[1] })
			end
		end
	end
end
reflect = function(hitpos, direction, raynormal, reflectmult)
	local theneeded = reflectmult * direction:Dot(raynormal)
	return direction - (theneeded * raynormal), theneeded
end
makepart = function(parent, size, cf, anchored, cancol, name) --spawnlocation because spawns have less limit on vsb
	local part = Instance.new("SpawnLocation")
	part.Enabled = false
	part.Anchored = anchored
	part.CanCollide = cancol
	part.Name = name or "Part"
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
	part:BreakJoints()
	return part
end
parentfindfirstchildofclass = function(cname, search)
	local par = search
	local foundinstance
	while par ~= workspace and not foundinstance do
		foundinstance = par:FindFirstChildOfClass(cname)
		par = par.Parent
	end
	return foundinstance
end
makebhole = function(pos, normal, size, color, parent, material, debristime)
	local hole = makepart(parent, Vector3.new(0.01, size, size), CFrame.new(pos), false, false, "buIlethole")
	hole.CanQuery = false
	hole.CanTouch = false
	hole.Material = material
	hole.BrickColor = color
	hole.Shape = Enum.PartType.Cylinder
	hole.CFrame = CFrame.lookAt(pos, pos + normal) * CFrame.Angles(math.pi / 2, 0, math.pi / 2)
	if parent.Anchored then
		hole.Anchored = true
	else
		local bw = Instance.new("Weld", hole)
		bw.C0 = parent.CFrame:ToObjectSpace(hole.CFrame)
		bw.Part0 = parent
		bw.Part1 = hole
	end
	if debristime then
		debris:AddItem(hole, debristime)
	end
	return hole
end
penetrate = function(direction, rayhitpos, penamount, wall)
	local penstate
	local outpos
	local outnormal
	local startingpoint = rayhitpos + (direction * penamount)
	local thatwall = RaycastParams.new()
	thatwall.FilterType = Enum.RaycastFilterType.Whitelist
	thatwall.FilterDescendantsInstances = { wall }
	local wscan = workspace:Raycast(startingpoint, direction * -penamount, thatwall) --starts from the other side of the wall and then casts back and checks if it hits and if not then its inside of a wall (inside of a wall means the wall is too thick and bullet wont go through)
	if not wscan then
		penstate = false
	else
		penstate = true
		outnormal = wscan.Normal
		outpos = wscan.Position
	end
	return penstate, outpos, outnormal
end
weld = function(part0, part1, c0, name)
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Name = name
	w.Parent = part0
	currentwelds[w.Name] = w
end
motor = function(part0, part1, c0, name)
	local m = Instance.new("Motor6D")
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.Name = name
	m.Parent = part0
	currentwelds[m.Name] = m
end
makeplayonremovesound = function(id, volume, rmax, rmin, speed, name)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Name = name
	s.Volume = volume or 1
	s.RollOffMaxDistance = rmax or 1e4
	s.RollOffMinDistance = rmin or 10
	s.PlaybackSpeed = speed or 1
	currentsounds[s.Name] = s
	s.Parent = nil
	s.PlayOnRemove = true
end
invishead = function(guy)
	local guyhead = guy:FindFirstChild("Head")
	if guyhead then
		guyhead.Transparency = 1
		for i, v in pairs(guyhead:GetDescendants()) do
			if v:IsA("Decal") or v:IsA("Texture") then
				v.Transparency = 1
			end
		end
		for i, v in pairs(guy:GetChildren()) do
			if v:IsA("Accessory") or v:IsA("Hat") then
				local vhandle = v:FindFirstChild("Handle", true)
				if vhandle and vhandle:IsA("BasePart") then
					local anattachment = vhandle:FindFirstChildOfClass("Attachment")
					if anattachment and headattachments[anattachment.Name] then
						vhandle.Transparency = 1
					end
				end
			end
		end
	end
end
makesound = function(id, parent, volume, rmax, rmin, speed, name)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Name = name
	s.Volume = volume or 1
	s.RollOffMaxDistance = rmax or 1e4
	s.RollOffMinDistance = rmin or 10
	s.PlaybackSpeed = speed or 1
	s.Parent = parent
	if sfxbehavior[name] then
		sfxbehavior[name](s)
	end
	currentsounds[s.Name] = s
end
playremovesound = function(name, parent, speed, timepos)
	local thesound = currentsounds[name]
	if not thesound then
		print(name, "sound not found")
		return
	end
	thesound.Parent = parent
	thesound.PlaybackSpeed = speed
	thesound.TimePosition = timepos or 0
	thesound.Parent = nil
end
playsound = function(name, speed, timepos)
	local thesound = currentsounds[name]
	if not thesound then
		print(name, "sound not found")
		return
	end
	thesound.PlaybackSpeed = speed or 1
	thesound.TimePosition = timepos or 0
	thesound:Play()
end
makebits = function(pos, divider, partt)
	for i = 1, 70 do
		local bit = Instance.new("SpawnLocation", workspace)
		bit.Enabled = false
		bit.Size = Vector3.new(0.18, 0.18, 0.18)
		bit.Material = Enum.Material.Pebble
		bit.BrickColor = BrickColor.new("Maroon")
		bit.CFrame = CFrame.new(pos)
			* CFrame.new(math.random(-10, 10) / divider, math.random(-10, 10) / divider, math.random(-10, 10) / divider)
		local vel = Instance.new("BodyVelocity", bit)
		vel.MaxForce = Vector3.new(1 / 0, 1 / 0, 1 / 0)
		vel.Velocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))
		local nocol = Instance.new("NoCollisionConstraint", bit)
		nocol.Part0 = partt
		nocol.Part1 = bit
		debris:AddItem(bit, 2)
		debris:AddItem(vel, 0.2)
		if i < 20 then
			bit.Color = Color3.fromRGB(200, 200, 200)
			bit.Material = "Slate"
		end
	end
end
damagehum = function(fh, alsopart, basedamage)
	-- IMPORTANT: Validate that target is an active player in the current round
	-- Non-active players (spectators, eliminated, lobby) take NO damage
	if fh.Parent then
		local targetPlayer = players:GetPlayerFromCharacter(fh.Parent)
		if targetPlayer and not ActivePlayersRegistry:IsPlayerActive(targetPlayer) then
			print("[GUN] Blocked damage - target " .. targetPlayer.Name .. " is not an active player")
			return -- Exit without dealing damage
		end
	end

	local applieddmg = basedamage
	for i, v in pairs(limbdmgmultiplier) do
		if alsopart.Name:find(i) then
			applieddmg = (basedamage * v)
		end
	end

	-- Check if this target is highlighted (guaranteed headshot/kill)
	local isHighlightedTarget = false
	if fh.Parent then
		isHighlightedTarget = fh.Parent:GetAttribute("IsHighlightedTarget") == true
	end

	-- Force headshot behavior for highlighted targets OR actual head hits
	if fh.Health > 0 and (alsopart.Name == "Head" or isHighlightedTarget) then
		invishead(fh.Parent)
		if tick() - lastsenthitmarker > 0.1 then
			lastsenthitmarker = tick()
			remote:FireClient(owner, "showcross", 0.5, Color3.new(1, 0, 0), 3.5)
		end
		-- Find head for gore effects (even if we hit another body part)
		local targetHead = fh.Parent:FindFirstChild("Head")
		if targetHead then
			playremovesound("gore" .. math.random(1, 4), targetHead, 1 + (math.random(-10, 10) / 50), 0)
			makebits(targetHead.Position, 10, targetHead)
		else
			playremovesound("gore" .. math.random(1, 4), alsopart, 1 + (math.random(-10, 10) / 50), 0)
			makebits(alsopart.Position, 10, alsopart)
		end
		-- Guaranteed kill for highlighted targets
		if isHighlightedTarget then
			applieddmg = fh.MaxHealth + 100 -- Overkill damage
		end
	else
		if tick() - lastsenthitmarker > 0.1 then
			lastsenthitmarker = tick()
			remote:FireClient(owner, "showcross", 0.5, Color3.new(1, 1, 1))
		end
	end
	fh.Health = fh.Health - applieddmg
end
removeweld = function(weldname)
	local foundweld = currentwelds[weldname]
	if foundweld then
		foundweld:Destroy()
		foundweld = nil
	else
		print(weldname, "not found")
	end
end
unweldasdescendantof = function(desc)
	for i, v in pairs(currentwelds) do
		if v:IsDescendantOf(desc) then
			removeweld(i)
		end
	end
end
shootbullet = function(direction, offsetrotation, ammoname)
	local theammo = ammotype[ammoname]
	if theammo then
		local spd = theammo[3]
		local drop = theammo[7]
		local speeddrop = theammo[8]
		local dmg = theammo[1]
		local pen = theammo[4]
		local tpassed = 0
		local bfunc
		local bullet = makepart(
			workspace,
			Vector3.new(theammo[1] / 150, theammo[1] / 150, theammo[3] / 40),
			charhead.CFrame * CFrame.new(0, -0.5, 0),
			true,
			false,
			"65%morebulletperbullet"
		)
		local startlength = bullet.Size.z
		local startwidth = bullet.Size.x
		local lastbpos = bullet.Position
		local penetrationdecreasemult = 1
		local wallpenpenalty = 0
		local decreasewalldmgmult = 0
		bullet.CanQuery = false
		bullet.CanTouch = false
		bullet.Material = Enum.Material.Neon
		bullet.Color = theammo[9]
		local mes = Instance.new("SpecialMesh", bullet)
		mes.MeshType = Enum.MeshType.Sphere
		bullet.CFrame = CFrame.lookAt(bullet.Position, direction.p)
			* offsetrotation
			* CFrame.new(0, 0, -(bullet.Size.z / 2))
		local rparams = RaycastParams.new()
		rparams.FilterDescendantsInstances = ignoretable
		rparams.FilterType = Enum.RaycastFilterType.Blacklist
		bfunc = runservice.Stepped:Connect(function(_, delta)
			if spd < 0 or dmg < 0 then
				bullet:Destroy()
				bfunc:Disconnect()
			end
			tpassed = tpassed + delta
			local penetrationpenaltymult = 1
			local raypenmult = 1
			local actualspeed = spd * delta
			local rotspeed = -drop * tpassed
			local startofbullet = bullet.Position - (bullet.CFrame.LookVector * bullet.Size.z / 2)
			local theray = workspace:Raycast(startofbullet, bullet.CFrame.LookVector * actualspeed, rparams)
			local bx, by, bz = bullet.CFrame:ToOrientation()
			if bx < -1.5 then
				rotspeed = 0
			end
			if not theray then
				bullet.CFrame = bullet.CFrame * CFrame.new(0, 0, -actualspeed) * CFrame.Angles(rotspeed, 0, 0)
				if spd > 1250 then --supersonic crack
					playremovesound("supersonic1", bullet, 1 + (math.random(-10, 10) / 50), 0)
				else --not a supersonic whoosh sound (ignore the sound name)
					playremovesound("supersonic2", bullet, 1 + (math.random(-10, 10) / 50), 0)
				end
			else
				local bholecolor = BrickColor.Black()
				local bholematerial = Enum.Material.Plastic
				local debristime = 20
				--finding humanoid
				local fh = parentfindfirstchildofclass("Humanoid", theray.Instance.Parent)
				if fh then
					if fh.Health ~= fh.Health or fh.Health > 2e3 then --the ~= happens when you put health to tonumber("nan")
						fh.MaxHealth = 1e3
						fh.Health = 1e3
					end
					bholecolor = BrickColor.new("Maroon")
					bholematerial = Enum.Material.Pebble
					debristime = 60
					penetrationpenaltymult = 0.5
					raypenmult = 1.5
					damagehum(fh, theray.Instance, dmg)
					playremovesound("bone", theray.Instance, 1 + (math.random(-10, 10) / 50), 0)
					playremovesound("snap", theray.Instance, 1 + (math.random(-10, 10) / 50), 0)
				end
				local pstate, outpos, outnormal =
					penetrate(bullet.CFrame.LookVector, theray.Position, pen * raypenmult, theray.Instance)
				local bounce, theneeded =
					reflect(theray.Position, bullet.CFrame.LookVector, theray.Normal, 1 + math.random(2, 20) / 20)
				if pstate and pen > 0 then
					local themag = (theray.Position - outpos).Magnitude
					bullet.CFrame = CFrame.lookAt(outpos, outpos + bullet.CFrame.LookVector)
						* CFrame.Angles(math.random(-20, 20) / 200, math.random(-20, 20) / 200, 0)
						* CFrame.new(0, 0, -bullet.Size.z / 2)
					makebhole(outpos, outnormal, theammo[10], bholecolor, theray.Instance, bholematerial, debristime)
					wallpenpenalty = wallpenpenalty + (themag * penetrationpenaltymult)
					decreasewalldmgmult = theammo[11] * (1 + themag)
				else
					bullet.CFrame = CFrame.new(theray.Position, theray.Position + bounce)
						* CFrame.new(0, 0, -bullet.Size.z / 2)
					if fh then
						bullet:Destroy()
						bfunc:Disconnect()
					end
				end
				local ghole = makebhole(
					theray.Position,
					theray.Normal,
					theammo[10],
					bholecolor,
					theray.Instance,
					bholematerial,
					debristime
				)
				if theneeded < -0.1 then
					playremovesound("impact" .. math.random(1, 4), ghole, 1 + math.random(-10, 10) / 100, 0)
				end
			end
			bullet.Size = Vector3.new(theammo[1] / 150, theammo[1] / 150, (theammo[3] / 40) * (spd / theammo[3]))
			spd = spd - (speeddrop * delta)
			dmg = (theammo[1] * (spd / theammo[3])) - decreasewalldmgmult
			pen = (theammo[4] * (spd / theammo[3])) - wallpenpenalty
			--print(pen)
			--print(dmg)
			--print("dec:",decreasewalldmgmult)
		end)
		remote:FireClient(owner, "showdata", ammochambered .. "/" .. maxchamber)
	end
end
changestate = function(nam)
	if not tool then
		toolstate = "unequipped"
		return
	end
	if tool.Parent == character then
		toolstate = nam
	else
		toolstate = "unequipped"
	end
end
local designdata = { --its only just color
	[".357 Magnum"] = { Color3.fromRGB(255, 255, 0) },
	[".410 Shell"] = { Color3.fromRGB(200, 0, 0) },
}
local animfuncs = {
	["equip"] = function(savedtick, speed)
		playsound("equip", 1.5 + math.random(-5, 5) / 70)
		for i = 1, 3 do
			if savedtick == currentanimtick then
				pose("equip", i, speed, savedtick)
				task.wait(0.1 * speed)
			end
		end
	end,
	["wholehammerpull"] = function(savedtick, speed)
		pose("pullhammer", 1, speed, savedtick)
		task.wait(0.25 * speed)
		playsound("pull", 1.5 + math.random(-5, 5) / 70, 0.1)
		pose("hammer", 1, speed, savedtick)
		pose("idle", 1, speed, savedtick)
		task.wait(0.05)
	end,
	["shoot"] = function(savedtick, speed)
		pose("shoot", 1, speed, savedtick)
		task.wait(0.1 * speed)
		pose("idle", 1, speed, savedtick)
		task.wait(0.2)
	end,
	["reload"] = function(savedtick, speed)
		local savedbullets = {}
		local addedfromclip = {}
		remote:FireClient(owner, "recoilsupaaction", CFrame.Angles(0, 0, 0.25))
		pose("reload", 1, speed, savedtick)
		task.wait(0.15 * speed)
		playsound("reload", 1, 0)
		pose("reload", 2, speed, savedtick)
		task.wait(0.17 * speed)
		pose("reload", 3, speed, savedtick)
		task.wait(0.1 * speed)
		for i, v in pairs(cylinder:GetChildren()) do
			if v.Name:sub(1, 1) == "b" then
				savedbullets[v] = v.Transparency
				local bclone = v:Clone()
				v.Transparency = 1
				bclone.Parent = workspace
				bclone.CanCollide = true
				bclone.Massless = true
				bclone:SetNetworkOwner(owner)
				bclone:BreakJoints()
				local smallvel = Instance.new("BodyVelocity", bclone)
				smallvel.MaxForce = Vector3.new(1 / 0, 1 / 0, 1 / 0)
				smallvel.Velocity = cylinder.holder.CFrame.RightVector * 10
				debris:AddItem(smallvel, 0.1)
				debris:AddItem(bclone, 1)
			end
		end
		task.wait(0.2)
		pose("reload", 4, speed, savedtick)
		task.wait(0.3 * speed)
		local moonclip
		if savedtick == currentanimtick then
			moonclip = makepart(
				gunmodel,
				cylinder.holder.Size - Vector3.new(0.4, 0, 0),
				character["Left Arm"].CFrame,
				false,
				false,
				"moonclip"
			)
			Instance.new("SpecialMesh", moonclip).MeshType = Enum.MeshType.Cylinder
			moonclip.BrickColor = BrickColor.Black()
			motor(character["Left Arm"], moonclip, CFrame.new(0, -1.5, 0), "moonclip")
			for i, v in pairs(savedbullets) do
				local clipclone = i:Clone()
				clipclone.Transparency = 0
				clipclone.Parent = gunmodel
				clipclone.Color = designdata[ammonames[currentselectedammo]][1]
				clipclone:BreakJoints()
				local weld = Instance.new("Weld", clipclone)
				weld.Part0 = moonclip
				weld.Part1 = clipclone
				weld.C0 = i.CFrame:ToObjectSpace(cylinder.holder.CFrame)
				table.insert(addedfromclip, clipclone)
			end
		end
		pose("reload", 5, speed, savedtick)
		task.wait(0.25 * speed)
		for i, v in pairs(savedbullets) do
			if currentanimtick == savedtick then
				i.Color = designdata[ammonames[currentselectedammo]][1]
			end
			i.Transparency = v
		end
		for i, v in pairs(addedfromclip) do
			v:Destroy()
			v = nil
		end
		task.wait(0.1)
		currentsounds["reload"].TimePosition = 1.6
		playsound("hl2reload", 1 + math.random(-5, 5) / 50, 1.9)
		remote:FireClient(owner, "recoilsupaaction", CFrame.Angles(0, 0, 0.2))
		pose("reload", 6, speed, savedtick)
		task.wait(0.1 * speed)
		if moonclip ~= nil then
			removeweld("moonclip")
			moonclip.CanCollide = true
			local smallvel = Instance.new("BodyVelocity", moonclip)
			smallvel.MaxForce = Vector3.new(1 / 0, 1 / 0, 1 / 0)
			smallvel.Velocity = cylinder.holder.CFrame.upVector * -15
			debris:AddItem(moonclip, 1)
			debris:AddItem(smallvel, 0.1)
		end
		task.wait(0.2 * speed)
		pose("idle", 1, speed, savedtick)
		task.wait(0.2)
		if currentanimtick == savedtick then
			currentchamberedammo = currentselectedammo
		end
	end,
}
local remotekeybehavior = {
	["e"] = function()
		if toolstate == "idle" then
			currentselectedammo = currentselectedammo + 1
			if currentselectedammo > #ammonames then
				currentselectedammo = 1
			end
		end
	end,
	["r"] = function()
		-- RELOAD DISABLED: One bullet system - no reloading allowed
		return
	end,
}
local shootfunction = {
	[".357 Magnum"] = function(name, pos)
		remote:FireClient(
			owner,
			"recoilsupaaction",
			CFrame.Angles(math.random(10, 15) / 25, math.random(-15, 15) / 30, math.random(-15, 15) / 20)
		)
		local shockwave = makepart(
			workspace,
			Vector3.new(),
			barrelend.CFrame * CFrame.new(-0.5, 0, 0) * CFrame.Angles(math.pi / 2, 0, math.pi / 2),
			true,
			false
		)
		local ring =
			makepart(workspace, Vector3.new(), barrelend.CFrame * CFrame.Angles(0, math.pi / 2, 0), true, false)
		local shockmesh = Instance.new("SpecialMesh", shockwave)
		shockmesh.VertexColor = Vector3.new(20, 20, 20)
		shockmesh.MeshId = "rbxassetid://20329976"
		local ringmesh = Instance.new("SpecialMesh", ring)
		ringmesh.VertexColor = Vector3.new(20, 20, 20)
		ringmesh.MeshId = "rbxassetid://3270017"
		shockwave.CanQuery = false
		shockwave.CanTouch = false
		ring.CanQuery = false
		ring.CanTouch = false
		tween(0.15, easingstyles.Sine, easingdirs.Out, 0, shockmesh, { Scale = Vector3.new(1, 0, 1) })
		tween(0.15, easingstyles.Sine, easingdirs.Out, 0, shockwave, { Transparency = 1 })
		tween(0.15, easingstyles.Sine, easingdirs.Out, 0, ringmesh, { Scale = Vector3.new(2.5, 2.5, 0) })
		tween(0.15, easingstyles.Sine, easingdirs.Out, 0, ring, { Transparency = 1 })
		local ligh = Instance.new("PointLight", handle)
		ligh.Brightness = 15
		ligh.Range = 15
		debris:AddItem(ring, 0.15)
		debris:AddItem(shockwave, 0.15)
		debris:AddItem(ligh, 0.025)
		shootbullet(pos, CFrame.Angles(math.random(-10, 10) / 1e3, math.random(-10, 10) / 1e3, 0), name)
	end,
	[".410 Shell"] = function(name, pos)
		remote:FireClient(
			owner,
			"recoilsupaaction",
			CFrame.Angles(math.random(10, 15) / 10, math.random(-15, 15) / 30, math.random(-15, 15) / 20)
		)
		local shockwave = makepart(
			workspace,
			Vector3.new(),
			barrelend.CFrame * CFrame.new(-0.25, 0, 0) * CFrame.Angles(math.pi / 2, 0, math.pi / 2),
			true,
			false
		)
		local ring =
			makepart(workspace, Vector3.new(), barrelend.CFrame * CFrame.Angles(0, math.pi / 2, 0), true, false)
		local shockmesh = Instance.new("SpecialMesh", shockwave)
		shockmesh.VertexColor = Vector3.new(20, 20, 20)
		shockmesh.Scale = Vector3.new(1.5, 0, 1.5)
		shockmesh.MeshId = "rbxassetid://20329976"
		local ringmesh = Instance.new("SpecialMesh", ring)
		ringmesh.VertexColor = Vector3.new(20, 20, 20)
		ringmesh.MeshId = "rbxassetid://3270017"
		shockwave.CanQuery = false
		shockwave.CanTouch = false
		ring.CanQuery = false
		ring.CanTouch = false
		tween(0.125, easingstyles.Sine, easingdirs.Out, 0, shockmesh, { Scale = Vector3.new(0.5, 3, 0.5) })
		tween(
			0.125,
			easingstyles.Sine,
			easingdirs.Out,
			0,
			shockwave,
			{ Transparency = 1, CFrame = shockwave.CFrame * CFrame.new(0, 1.5, 0) }
		)
		tween(0.125, easingstyles.Sine, easingdirs.Out, 0, ringmesh, { Scale = Vector3.new(4, 4, 0) })
		tween(0.125, easingstyles.Sine, easingdirs.Out, 0, ring, { Transparency = 1 })
		local ligh = Instance.new("PointLight", handle)
		ligh.Brightness = 15
		ligh.Range = 20
		debris:AddItem(ring, 0.125)
		debris:AddItem(shockwave, 0.125)
		debris:AddItem(ligh, 0.05)
		for i = 1, 15 do
			shootbullet(pos, CFrame.Angles(math.random(-20, 20) / 450, math.random(-20, 20) / 450, 0), name)
		end
	end,
}
-- ============================================
-- HIGHLIGHT-LOCKED ELIMINATION
-- If a highlighted target exists when the shot fires,
-- guarantee their elimination server-side, regardless of raycast result.
-- ============================================
local function tryHighlightLockedKill()
	if not getHighlightedPlayerFunc then
		return false
	end

	local ok, highlightedPlayer = pcall(function()
		return getHighlightedPlayerFunc:Invoke()
	end)

	if not ok or not highlightedPlayer then
		return false
	end

	-- Safety validation checks
	if highlightedPlayer == owner then
		print("[GUN] Highlight-locked kill blocked: target is the shooter")
		return false
	end

	if not ActivePlayersRegistry:IsPlayerActive(highlightedPlayer) then
		print("[GUN] Highlight-locked kill blocked: target " .. highlightedPlayer.Name .. " is not active")
		return false
	end

	if not highlightedPlayer.Character then
		print("[GUN] Highlight-locked kill blocked: target has no character")
		return false
	end

	local humanoid = highlightedPlayer.Character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		print("[GUN] Highlight-locked kill blocked: target has no humanoid or is already dead")
		return false
	end

	-- All checks passed — guaranteed kill
	print("[GUN] HIGHLIGHT-LOCKED KILL: Eliminating " .. highlightedPlayer.Name)

	-- Apply headshot visual effects
	invishead(highlightedPlayer.Character)
	local targetHead = highlightedPlayer.Character:FindFirstChild("Head")
	if targetHead then
		playremovesound("gore" .. math.random(1, 4), targetHead, 1 + (math.random(-10, 10) / 50), 0)
		makebits(targetHead.Position, 10, targetHead)
	end

	-- Red hitmarker for the shooter
	if owner then
		remote:FireClient(owner, "showcross", 0.5, Color3.new(1, 0, 0), 3.5)
	end

	-- Kill the target (server-authoritative)
	humanoid.Health = 0

	return true
end

local remotebehavior = {
	["lmb"] = function(pos)
		if toolstate == "idle" then
			toolstate = "shoot"
			local btick = currentanimtick
			pose("hammer", 2, 1, btick)
			playsound("click", 1 + math.random(-10, 10) / 50, 0)
			if ammochambered > 0 then
				ammochambered = ammochambered - 1
				shootfunction[ammonames[currentchamberedammo]](ammonames[currentchamberedammo], pos)
				-- Highlight-locked kill override: guaranteed elimination if highlighted target exists
				tryHighlightLockedKill()
				playsound(ammotype[ammonames[currentchamberedammo]][2], 1 + math.random(-10, 10) / 50, 0)
				playsound("shootaway", 1 + math.random(-10, 10) / 50, 0)
				remote:FireClient(owner, "bar", "shoot", 0.595)
				animfuncs["shoot"](currentanimtick, 0.8)

				-- ONE BULLET SYSTEM: Notify server that the shot was used
				-- This allows the minigame to detect miss vs kill
				if owner then
					shotUsedEvent:Fire(owner)
				end
			else
				-- EMPTY GUN: Notify server that an empty click occurred
				if owner then
					emptyClickEvent:Fire(owner)
				end
				task.wait(0.1)
			end
			task.wait(0.05)
			animfuncs["wholehammerpull"](currentanimtick, 0.75)
			task.spawn(function()
				task.wait(0.1)
				if aiming and currentanimtick == btick then
					pose("aiming", 1, 2, currentanimtick)
				end
			end)
			changestate("idle")
			if owner then
				remote:FireClient(owner, "isholding")
			end
		end
	end,
	["aimin"] = function()
		if not aiming then
			aiming = true
			charhum.WalkSpeed = charhum.WalkSpeed - 6
			if toolstate == "idle" then
				pose("aiming", 1, 2, currentanimtick)
			end
		end
	end,
	["notaimin"] = function()
		if aiming then
			aiming = false
			charhum.WalkSpeed = charhum.WalkSpeed + 6
			if toolstate == "idle" then
				pose("idle", 1, 1.5, currentanimtick)
			end
		end
	end,
	["keypress"] = function(thekey)
		if remotekeybehavior[thekey] then
			remotekeybehavior[thekey]()
		end
	end,
}
local function setupSounds()
	table.clear(currentsounds)
	for i, v in pairs(sfxdata) do
		if v[5] then
			makeplayonremovesound(v[1], v[2], v[4], v[3], 1, i)
		else
			makesound(v[1], handle, v[2], v[4], v[3], 1, i)
		end
	end
end
remote.OnServerEvent:Connect(function(WHO, WHAT, param)
	if not owner then
		return
	end
	if WHO ~= owner then
		if WHO.Character then
			WHO.Character:BreakJoints()
		end
		return
	end
	if remotebehavior[WHAT] then
		remotebehavior[WHAT](param)
	end
end)
local function onEquipped()
	currentanimtick = tick()
	currentequiptick = currentanimtick
	local equipbtick = currentanimtick
	local backuptick = currentanimtick
	owner = players:GetPlayerFromCharacter(tool.Parent)
	character = owner.Character
	charhead = character.Head
	charhum = character:FindFirstChildOfClass("Humanoid")
	charroot = character.HumanoidRootPart
	table.insert(ignoretable, character)

	-- Read InitialAmmo attribute set by ChairWaitingSystem for alternating bullet/empty rounds
	local initialAmmo = tool:GetAttribute("InitialAmmo")
	if initialAmmo ~= nil then
		ammochambered = initialAmmo
		print("[GUN] InitialAmmo attribute found: " .. tostring(initialAmmo) .. " for " .. owner.Name)
	end
	lookrootpart = Instance.new("Part")
	lookrootpart.Name = "animroot"
	lookrootpart.Size = Vector3.new(0.5, 0.5, 0.5)
	lookrootpart.CanCollide = false
	lookrootpart.CanTouch = false
	lookrootpart.Transparency = 1
	lookrootpart.Name = "lrp"
	lookrootpart.Parent = character.Head
	lookrootpart:BreakJoints()
	--[[print("------start")
	table.foreach(currentwelds, print)
	print("------end")--]]
	currentwelds[cylinderweld.Name] = cylinderweld
	currentwelds[hammerweld.Name] = hammerweld
	weld(
		character["Right Arm"],
		handle,
		CFrame.new(
			-0.488301277,
			-0.654794216,
			-0.0429682732,
			-0.330367118,
			0.939692199,
			-0.0885195136,
			0.907674193,
			0.342020571,
			0.243206337,
			0.258814603,
			4.96200414e-07,
			-0.965926945
		),
		"handleweld"
	)
	weld(lookrootpart, character.Head, CFrame.new(0, 1.5 - (1 + lookpartheight), 0), "headtorootweld")
	weld(lookrootpart, character["Right Arm"], CFrame.new(1.5, -(1 + lookpartheight), 0), "rarmweld")
	weld(lookrootpart, character["Left Arm"], CFrame.new(-1.5, -(1 + lookpartheight), 0), "larmweld")
	leftarmneutralc0 = character.Torso.CFrame:ToObjectSpace(character["Left Arm"].CFrame)
	weld(character.Torso, charroot, CFrame.new(), "rootweld")
	weld(character.Torso, lookrootpart, CFrame.new(0, 1 + lookpartheight, 0), "lookrootweld")
	aimpart = makepart(
		character,
		Vector3.new(0.5, 0.5, 0.5),
		charhead.CFrame * CFrame.new(0, -0.5, 1.5),
		false,
		false,
		"aimpartjudge"
	)
	aimpart.Transparency = 1
	aimpart.Shape = Enum.PartType.Ball
	aimpart.Material = Enum.Material.Neon
	aimpart.CanQuery = false
	aimpart.CanTouch = false
	aimpart:SetNetworkOwner(owner)
	runfunc = runservice.Stepped:Connect(function(_, delta)
		local probheadpos = charroot.Position + Vector3.new(0, 1 + lookpartheight, 0)
		local theunit = (charhead.Position - aimpart.Position).unit
		local unitrel = charroot.CFrame:vectorToObjectSpace(theunit)
		local velrel = charroot.CFrame:vectorToObjectSpace(charroot.Velocity)
		local theXtilt = unitrel.x
		if velrel.x < -5 or velrel.x > 5 then
			theXtilt = 0
		end
		currentwelds["lookrootweld"].C0 = currentwelds["lookrootweld"].C0:lerp(
			CFrame.new(0, 1 + lookpartheight, 0) * CFrame.Angles(-unitrel.y, theXtilt / armYawDivisor, 0),
			delta * 15
		)
		local larmweld = currentwelds["larmweld"]
		if larmweld then
			if toolstate == "reloading" then
				if larmweld.Part0 ~= lookrootpart then
					larmweld.Part0 = lookrootpart
					larmweld.C0 = lookrootpart.CFrame:ToObjectSpace(character["Left Arm"].CFrame)
				end
			else
				if larmweld.Part0 ~= character.Torso then
					larmweld.Part0 = character.Torso
					larmweld.C0 = character.Torso.CFrame:ToObjectSpace(character["Left Arm"].CFrame)
				end
				if leftarmneutralc0 then
					larmweld.C0 = larmweld.C0:Lerp(leftarmneutralc0, delta * 12)
				end
			end
		end
	end)
	remote:FireClient(owner, "showdata", ammochambered .. "/" .. maxchamber, ammonames[currentselectedammo])
	animfuncs["equip"](currentanimtick, 1)
	pose("hammer", 1, 1, backuptick)
	if toolstate == "unequipped" then
		toolstate = "idle"
	end
	task.spawn(function()
		task.wait(0.1)
		if aiming and currentanimtick == backuptick then
			pose("aiming", 1, 2, currentanimtick)
		end
	end)
	while currentequiptick == equipbtick and tool and tool.Parent == character do
		for i, v in pairs(ignoretable) do
			if not v:IsDescendantOf(game) then
				table.remove(ignoretable, tfind(ignoretable, v))
			end
		end
		task.wait(2)
	end
end
local function onUnequipped()
	--[[print("------start")
	table.foreach(currentwelds, print)
	print("------end")--]]
	if aiming then
		if charhum then
			remotebehavior["notaimin"]()
		else
			aiming = false
		end
	end
	if runfunc then
		runfunc:Disconnect()
		runfunc = nil
	end
	if character then
		unweldasdescendantof(character)
		local idx = tfind(ignoretable, character)
		if idx then
			table.remove(ignoretable, idx)
		end
	end
	table.clear(currentwelds)
	if aimpart then
		aimpart:Destroy()
		aimpart = nil
	end
	if lookrootpart then
		lookrootpart:Destroy()
		lookrootpart = nil
	end
	if toolstate == "idle" then
		toolstate = "unequipped"
	end
end

local toolEquippedConnection
local toolUnequippedConnection
local toolAncestryConnection
local toolBindInProgress = false
local ensureToolBound

local function cleanupEquippedState()
	onUnequipped()
	aiming = false
	toolstate = "unequipped"
	owner = nil
	character = nil
	charroot = nil
	charhum = nil
	charhead = nil
end

local function bindTool(newTool)
	if not newTool or newTool == tool then
		return
	end
	cleanupEquippedState()
	if toolEquippedConnection then
		toolEquippedConnection:Disconnect()
		toolEquippedConnection = nil
	end
	if toolUnequippedConnection then
		toolUnequippedConnection:Disconnect()
		toolUnequippedConnection = nil
	end
	if toolAncestryConnection then
		toolAncestryConnection:Disconnect()
		toolAncestryConnection = nil
	end
	tool = newTool
	gunmodel = tool:WaitForChild("model")
	handle = gunmodel:WaitForChild("Handle")
	cylinder = gunmodel:WaitForChild("cylinder")
	barrelend = gunmodel:WaitForChild("barrelend")
	cylinderweld = handle:WaitForChild("cylinderweld")
	hammerweld = handle:WaitForChild("hammerweld")
	setupSounds()
	ammochambered = maxchamber

	-- Read InitialAmmo attribute from ChairWaitingSystem (for alternating bullet/empty rounds)
	-- This must be done here because the tool may already be equipped when bindTool runs
	local initialAmmo = newTool:GetAttribute("InitialAmmo")
	if initialAmmo ~= nil then
		ammochambered = initialAmmo
		print("[GUN] bindTool: InitialAmmo = " .. tostring(initialAmmo))
	else
		print("[GUN] bindTool: No InitialAmmo attribute, using default = " .. tostring(ammochambered))
	end

	if currentselectedammo < 1 or currentselectedammo > #ammonames then
		currentselectedammo = 1
	end
	currentchamberedammo = currentselectedammo
	aiming = false
	toolstate = "idle"
	toolEquippedConnection = tool.Equipped:Connect(onEquipped)
	toolUnequippedConnection = tool.Unequipped:Connect(onUnequipped)
	toolAncestryConnection = tool.AncestryChanged:Connect(function()
		if tool == newTool and not isToolOwned(tool) then
			cleanupEquippedState()
			tool = nil
			ensureToolBound()
		end
	end)
end

ensureToolBound = function()
	if toolBindInProgress then
		return
	end
	toolBindInProgress = true
	task.spawn(function()
		local newTool = waitForTool()
		bindTool(newTool)
		toolBindInProgress = false
	end)
end

ensureToolBound()

workspace.DescendantAdded:Connect(function(WHAT)
	if WHAT.Name == "Handle" and WHAT:IsA("BasePart") then --wrote handle first so it doesnt have to go through 2 checks everytime a part gets made
		--print(WHAT.Name)
		table.insert(ignoretable, WHAT)
	end
end)

for i, v in pairs(workspace:GetDescendants()) do
	if v.Name == "Handle" and v:IsA("BasePart") then
		table.insert(ignoretable, v)
	end
end
