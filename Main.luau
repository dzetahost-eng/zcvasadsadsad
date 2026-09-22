--[[ 
	zcva hub — самопис под Загадка убийства 2 (MM2-like)
	UI: собственный форк Obsidian (dzetahost-eng/zcvasadsadsad)
	Всё написано с нуля, никаких сторонних баз.
]]

local repo = "https://raw.githubusercontent.com/dzetahost-eng/zcvasadsadsad/main/"

local Library
if readfile and isfile and isfile("Library.lua") then
	Library = loadstring(readfile("Library.lua"))()
else
	Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
end

local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

--// Сервисы //--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Состояние //--
local Connections = {}
local Drawings = {}
local Highlights = {}
local Unloaded = false

local function Listen(signal, fn)
	local conn = signal:Connect(fn)
	table.insert(Connections, conn)
	return conn
end

--// Окно //--
local Window = Library:CreateWindow({
	Title = "zcva",
	Footer = "self-written",
	Icon = 95816097006870,
	NotifySide = "Right",
	CornerRadius = 12,
	BackgroundTransparency = 0.1,
	ShowCustomCursor = true,
	ToggleKeybind = Enum.KeyCode.RightControl,
	Animations = { ToggleWindow = true, TabSwitch = true },
})

Window:AddDialog("welcome", {
	Title = "zcva",
	Description = "Добро пожаловать, " .. LP.DisplayName .. "!",
	AutoDismiss = true,
	OutsideClickDismiss = true,
	FooterButtons = {
		Confirm = { Title = "Погнали", Variant = "Primary", Callback = function() end },
	},
})

local Tabs = {
	Main = Window:AddTab("Главная", "house"),
	Visuals = Window:AddTab("Визуалы", "eye"),
	Player = Window:AddTab("Игрок", "user"),
	Misc = Window:AddTab("Разное", "ellipsis"),
	Settings = Window:AddTab("Настройки", "settings"),
}

--========================================================
-- РОЛИ (самопис)
--========================================================
local Roles = {}
local RoleColors = {
	Murderer = Color3.fromRGB(255, 65, 65),
	Sheriff = Color3.fromRGB(70, 140, 255),
	Hero = Color3.fromRGB(70, 140, 255),
	Innocent = Color3.fromRGB(90, 220, 130),
}
local RoleRu = { Murderer = "Маньяк", Sheriff = "Шериф", Hero = "Герой", Innocent = "Мирный" }

local function GetRoleModule()
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("CurrentRoundClient", 5))
	end)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

local function DetectRole(plr)
	-- 1) Модуль раунда
	local mod = GetRoleModule()
	if mod and type(mod.PlayerData) == "table" then
		local d = mod.PlayerData[plr.Name]
		if type(d) == "table" and d.Role then
			if (d.Role == "Sheriff" or d.Role == "Hero") and d.Dead then
				return "Innocent"
			end
			return d.Role == "Hero" and "Sheriff" or d.Role
		end
	end

	-- 2) По предметам
	local char = plr.Character
	local backpack = plr:FindFirstChildOfClass("Backpack")
	if (char and (char:FindFirstChild("Gun") or char:FindFirstChild("Revolver")))
		or (backpack and (backpack:FindFirstChild("Gun") or backpack:FindFirstChild("Revolver"))) then
		return "Sheriff"
	end
	if (char and char:FindFirstChild("Knife")) or (backpack and backpack:FindFirstChild("Knife")) then
		return "Murderer"
	end

	return "Innocent"
end

local RoleLabel
local NotifyRoles = false
local LastRoles = {}

local function RefreshRoles()
	if Unloaded then
		return
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		local role = DetectRole(plr)
		if Roles[plr] ~= role then
			local old = Roles[plr]
			Roles[plr] = role

			if NotifyRoles and role ~= "Innocent" and old ~= role and plr ~= LP then
				Library:Notify({
					Title = "Роль обнаружена",
					Description = plr.Name .. " — " .. (RoleRu[role] or role),
					Time = 4,
				})
			end
		end
	end

	-- Чистим вышедших
	for plr in pairs(Roles) do
		if not plr.Parent then
			Roles[plr] = nil
		end
	end

	if RoleLabel then
		RoleLabel:SetText("Твоя роль: " .. (RoleRu[Roles[LP]] or "неизвестно"))
	end
end

Listen(Players.PlayerRemoving, function(plr)
	Roles[plr] = nil
	LastRoles[plr] = nil
end)

--========================================================
-- ESP (Drawing API, самопис)
--========================================================
local ESP = {
	Enabled = false,
	Boxes = false,
	Names = false,
	Tracers = false,
	Distance = false,
	MaxDist = 2000,
}

local DrawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

local function NewDrawing(class, props)
	if not DrawingAvailable then
		return setmetatable({}, {
			__index = function()
				return false
			end,
			__newindex = function() end,
		})
	end

	local obj = Drawing.new(class)
	for k, v in pairs(props) do
		obj[k] = v
	end
	table.insert(Drawings, obj)
	return obj
end

local ESPPool = {}

local function GetESPObjects(plr)
	if not ESPPool[plr] then
		ESPPool[plr] = {
			Box = NewDrawing("Square", { Thickness = 1, Filled = false }),
			Name = NewDrawing("Text", { Size = 14, Center = true, Outline = true }),
			Dist = NewDrawing("Text", { Size = 12, Center = true, Outline = true }),
			Tracer = NewDrawing("Line", { Thickness = 1 }),
		}
	end
	return ESPPool[plr]
end

local function ESPSetVisible(visible)
	for _, objs in pairs(ESPPool) do
		objs.Box.Visible = visible
		objs.Name.Visible = visible
		objs.Dist.Visible = visible
		objs.Tracer.Visible = visible
	end
end

local function ESPUpdate()
	if not ESP.Enabled then
		return
	end

	local vp = Camera.ViewportSize
	local myChar = LP.Character
	local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then
			continue
		end

		local objs = GetESPObjects(plr)
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")

		if not (char and hrp and hum and hum.Health > 0) then
			objs.Box.Visible = false
			objs.Name.Visible = false
			objs.Dist.Visible = false
			objs.Tracer.Visible = false
			continue
		end

		local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
		if not onScreen or pos.Z > ESP.MaxDist then
			objs.Box.Visible = false
			objs.Name.Visible = false
			objs.Dist.Visible = false
			objs.Tracer.Visible = false
			continue
		end

		local role = Roles[plr] or "Innocent"
		local color = RoleColors[role] or Color3.new(1, 1, 1)

		local top = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(0, 3, 0)).Position)
		local bottom = Camera:WorldToViewportPoint((hrp.CFrame * CFrame.new(0, -3, 0)).Position)
		local height = math.abs(top.Y - bottom.Y)
		local width = height * 0.65

		if ESP.Boxes then
			objs.Box.Size = Vector2.new(width, height)
			objs.Box.Position = Vector2.new(pos.X - width / 2, top.Y)
			objs.Box.Color = color
			objs.Box.Visible = true
		else
			objs.Box.Visible = false
		end

		if ESP.Names then
			objs.Name.Text = plr.Name .. " [" .. (RoleRu[role] or "?") .. "]"
			objs.Name.Color = color
			objs.Name.Position = Vector2.new(pos.X, top.Y - 16)
			objs.Name.Visible = true
		else
			objs.Name.Visible = false
		end

		if ESP.Distance and myHRP then
			objs.Dist.Text = math.floor((hrp.Position - myHRP.Position).Magnitude) .. "м"
			objs.Dist.Position = Vector2.new(pos.X, bottom.Y + 2)
			objs.Dist.Color = color
			objs.Dist.Visible = true
		else
			objs.Dist.Visible = false
		end

		if ESP.Tracers then
			objs.Tracer.From = Vector2.new(vp.X / 2, vp.Y)
			objs.Tracer.To = Vector2.new(pos.X, bottom.Y)
			objs.Tracer.Color = color
			objs.Tracer.Visible = true
		else
			objs.Tracer.Visible = false
		end
	end
end

Listen(RunService.RenderStepped, function()
	ESPUpdate()
end)

--========================================================
-- CHAMS (Highlight, самопис)
--========================================================
local Chams = { Enabled = false }

local function ChamsClear()
	for plr, hl in pairs(Highlights) do
		pcall(function()
			hl:Destroy()
		end)
		Highlights[plr] = nil
	end
end

local function ChamsUpdate()
	if not Chams.Enabled then
		return
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then
			continue
		end

		local char = plr.Character
		local role = Roles[plr] or "Innocent"

		if char and not Highlights[plr] then
			local hl = Instance.new("Highlight")
			hl.FillTransparency = 0.65
			hl.OutlineTransparency = 0
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = char
			Highlights[plr] = hl
		end

		local hl = Highlights[plr]
		if hl then
			if char and hl.Parent ~= char then
				hl.Parent = char
			end
			if not char then
				hl.Parent = nil
			end
			local color = RoleColors[role] or Color3.new(1, 1, 1)
			hl.FillColor = color
			hl.OutlineColor = color
		end
	end
end

Listen(RunService.Heartbeat, function()
	ChamsUpdate()
end)

Listen(Players.PlayerRemoving, function(plr)
	local hl = Highlights[plr]
	if hl then
		pcall(function()
			hl:Destroy()
		end)
		Highlights[plr] = nil
	end
end)

--========================================================
-- ПЕРСОНАЖ
--========================================================
local PlayerCfg = {
	Speed = 16,
	Jump = 50,
	Noclip = false,
	InfJump = false,
	Fly = false,
	FlySpeed = 50,
	AntiVoid = false,
}

Listen(Players.LocalPlayer.CharacterAdded, function(char)
	if Unloaded then
		return
	end
	task.wait(0.3)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = PlayerCfg.Speed
		hum.JumpPower = PlayerCfg.Jump
		hum.UseJumpPower = true
	end
end)

Listen(UserInputService.JumpRequest, function()
	if PlayerCfg.InfJump and not Unloaded then
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)

Listen(RunService.Stepped, function()
	if Unloaded then
		return
	end
	if PlayerCfg.Noclip then
		local char = LP.Character
		if char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end
	end
end)

-- Полёт
local FlyObjects = nil

local function StartFly()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
	bv.Velocity = Vector3.zero
	bv.Parent = hrp

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
	bg.P = 9e4
	bg.CFrame = hrp.CFrame
	bg.Parent = hrp

	FlyObjects = { bv = bv, bg = bg }

	local conn = RunService.RenderStepped:Connect(function()
		if not FlyObjects or Unloaded then
			return
		end
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			move += Camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			move -= Camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			move += Camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			move -= Camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			move += Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			move -= Vector3.new(0, 1, 0)
		end
		bv.Velocity = move * PlayerCfg.FlySpeed
		bg.CFrame = Camera.CFrame
	end)
	table.insert(Connections, conn)
end

local function StopFly()
	if FlyObjects then
		pcall(function()
			FlyObjects.bv:Destroy()
			FlyObjects.bg:Destroy()
		end)
		FlyObjects = nil
	end
end

-- AntiVoid
local LastSafePos = nil

Listen(RunService.Heartbeat, function()
	if Unloaded then
		return
	end
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	if hrp.Position.Y > (Workspace.FallenPartsDestroyHeight or -500) + 5 then
		LastSafePos = hrp.CFrame
	end

	if PlayerCfg.AntiVoid and hrp.Position.Y < (Workspace.FallenPartsDestroyHeight or -500) + 10 and LastSafePos then
		hrp.CFrame = LastSafePos + Vector3.new(0, 5, 0)
	end
end)

--========================================================
-- FAKE POSITION (самопис, спуф __index)
--========================================================
local FakePos = {
	Enabled = false,
	X = 0,
	Y = 0,
	Z = 0,
	Supported = false,
}

-- Кэш ссылки на HRP обновляется ВНЕ хука — внутри хука ни одного
-- обращения к инстантам, иначе рекурсия __index (C stack overflow)
local CachedHRP = nil

task.spawn(function()
	while not Unloaded do
		local char = LP.Character
		CachedHRP = char and char:FindFirstChild("HumanoidRootPart")
		task.wait(0.5)
	end
end)

if hookmetamethod and newcclosure then
	local oldIndex
	oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, k)
		if FakePos.Enabled and self == CachedHRP and (k == "CFrame" or k == "Position") then
			local real = oldIndex(self, k)
			if k == "CFrame" then
				return real * CFrame.new(FakePos.X, FakePos.Y, FakePos.Z)
			end
			return real.Position + Vector3.new(FakePos.X, FakePos.Y, FakePos.Z)
		end
		return oldIndex(self, k)
	end))
	FakePos.Supported = true
end

-- Fake lag (чоук репликации)
local FakeLag = { Enabled = false, Duration = 0.15, Rate = 0.5 }

task.spawn(function()
	while not Unloaded do
		if FakeLag.Enabled then
			local char = LP.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.Anchored = true
				task.wait(FakeLag.Duration)
				hrp.Anchored = false
			end
			task.wait(FakeLag.Rate)
		else
			task.wait(0.2)
		end
	end
end)

--========================================================
-- МИР
--========================================================
local World = { Fullbright = false, NoFog = false }

local SavedLighting = {
	Ambient = Lighting.Ambient,
	Brightness = Lighting.Brightness,
	GlobalShadows = Lighting.GlobalShadows,
	FogEnd = Lighting.FogEnd,
	FogStart = Lighting.FogStart,
	ClockTime = Lighting.ClockTime,
}

local function ApplyWorld()
	if World.Fullbright then
		Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.Brightness = 3
		Lighting.GlobalShadows = false
		Lighting.ClockTime = 14
	else
		Lighting.Ambient = SavedLighting.Ambient
		Lighting.Brightness = SavedLighting.Brightness
		Lighting.GlobalShadows = SavedLighting.GlobalShadows
		Lighting.ClockTime = SavedLighting.ClockTime
	end

	if World.NoFog then
		Lighting.FogEnd = 1e6
		Lighting.FogStart = 0
	else
		Lighting.FogEnd = SavedLighting.FogEnd
		Lighting.FogStart = SavedLighting.FogStart
	end
end

--========================================================
-- ГРУППЫ / ЭЛЕМЕНТЫ
--========================================================

--// Главная //--
local InfoGroup = Tabs.Main:AddGroupbox({ Name = "Информация", Side = "Left" })
InfoGroup:AddLabel("User", { Text = "Юзер: " .. LP.Name .. " (@" .. LP.DisplayName .. ")" })
RoleLabel = InfoGroup:AddLabel("Role", { Text = "Твоя роль: неизвестно" })
InfoGroup:AddLabel("Round", { Text = "Место: " .. game.PlaceId })

local RoleGroup = Tabs.Main:AddGroupbox({ Name = "Роли", Side = "Left" })
RoleGroup:AddToggle("RoleNotify", {
	Text = "Уведомлять о ролях",
	Default = false,
	Callback = function(v)
		NotifyRoles = v
	end,
})
RoleGroup:AddButton({
	Text = "Обновить роли",
	Func = function()
		RefreshRoles()
		Library:Notify({ Title = "Роли обновлены", Time = 2 })
	end,
})

local RolesList = RoleGroup:AddDropdown("RolesList", {
	Values = {},
	Multi = true,
	Text = "Кто есть кто",
	Searchable = true,
	Callback = function() end,
})

task.spawn(function()
	while not Unloaded do
		RefreshRoles()

		-- список игроков с ролями
		local list = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP then
				table.insert(list, plr.Name .. " — " .. (RoleRu[Roles[plr]] or "?"))
			end
		end
		pcall(function()
			Options.RolesList:SetValues(list)
		end)

		task.wait(1)
	end
end)

--// Визуалы //--
local ESPGroup = Tabs.Visuals:AddGroupbox({ Name = "ESP", Side = "Left" })
if not DrawingAvailable then
	ESPGroup:AddLabel("Drawing API недоступен в этом экзекьюторе")
end
ESPGroup:AddToggle("ESPEnabled", {
	Text = "Включить ESP",
	Default = false,
	Callback = function(v)
		ESP.Enabled = v
		if not v then
			ESPSetVisible(false)
		end
	end,
})
ESPGroup:AddToggle("ESPBoxes", {
	Text = "Боксы",
	Default = true,
	Callback = function(v)
		ESP.Boxes = v
	end,
})
ESPGroup:AddToggle("ESPNames", {
	Text = "Имена + роли",
	Default = true,
	Callback = function(v)
		ESP.Names = v
	end,
})
ESPGroup:AddToggle("ESPTracers", {
	Text = "Трейсеры",
	Default = false,
	Callback = function(v)
		ESP.Tracers = v
	end,
})
ESPGroup:AddToggle("ESPDistance", {
	Text = "Дистанция",
	Default = true,
	Callback = function(v)
		ESP.Distance = v
	end,
})
ESPGroup:AddSlider("ESPMaxDist", {
	Text = "Макс. дистанция",
	Default = 2000,
	Min = 100,
	Max = 5000,
	Rounding = 0,
	Suffix = "м",
	Callback = function(v)
		ESP.MaxDist = v
	end,
})

local ChamsGroup = Tabs.Visuals:AddGroupbox({ Name = "Chams", Side = "Left" })
ChamsGroup:AddToggle("ChamsEnabled", {
	Text = "Включить Chams",
	Default = false,
	Callback = function(v)
		Chams.Enabled = v
		if not v then
			ChamsClear()
		end
	end,
})

local ViewportGroup = Tabs.Visuals:AddGroupbox({ Name = "Превью", Description = "твой персонаж", Side = "Right" })

local WorldGroup = Tabs.Visuals:AddGroupbox({ Name = "Мир", Side = "Right" })
WorldGroup:AddToggle("Fullbright", {
	Text = "Fullbright",
	Default = false,
	Callback = function(v)
		World.Fullbright = v
		ApplyWorld()
	end,
})
WorldGroup:AddToggle("NoFog", {
	Text = "Убрать туман",
	Default = false,
	Callback = function(v)
		World.NoFog = v
		ApplyWorld()
	end,
})

--// Игрок //--
local CharGroup = Tabs.Player:AddGroupbox({ Name = "Персонаж", Side = "Left" })
CharGroup:AddSlider("WalkSpeed", {
	Text = "Скорость",
	Default = 16,
	Min = 16,
	Max = 200,
	Rounding = 0,
	Callback = function(v)
		PlayerCfg.Speed = v
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = v
		end
	end,
})
CharGroup:AddSlider("JumpPower", {
	Text = "Прыжок",
	Default = 50,
	Min = 50,
	Max = 300,
	Rounding = 0,
	Callback = function(v)
		PlayerCfg.Jump = v
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.UseJumpPower = true
			hum.JumpPower = v
		end
	end,
})
CharGroup:AddToggle("Noclip", {
	Text = "Noclip",
	Default = false,
	Callback = function(v)
		PlayerCfg.Noclip = v
	end,
})
CharGroup:AddToggle("InfJump", {
	Text = "Бесконечный прыжок",
	Default = false,
	Callback = function(v)
		PlayerCfg.InfJump = v
	end,
})

local FlyGroup = Tabs.Player:AddGroupbox({ Name = "Полёт", Side = "Left" })
FlyGroup:AddToggle("Fly", {
	Text = "Fly (WASD + Space/Ctrl)",
	Default = false,
	Callback = function(v)
		PlayerCfg.Fly = v
		if v then
			StartFly()
		else
			StopFly()
		end
	end,
})
FlyGroup:AddSlider("FlySpeed", {
	Text = "Скорость полёта",
	Default = 50,
	Min = 10,
	Max = 300,
	Rounding = 0,
	Callback = function(v)
		PlayerCfg.FlySpeed = v
	end,
})

local FakeGroup = Tabs.Player:AddGroupbox({ Name = "Fake", Side = "Right" })
if FakePos.Supported then
	FakeGroup:AddToggle("FakePos", {
		Text = "Fake Position",
		Default = false,
		Callback = function(v)
			FakePos.Enabled = v
		end,
	})
	FakeGroup:AddSlider("FakePosX", {
		Text = "Смещение X",
		Default = 0,
		Min = -50,
		Max = 50,
		Rounding = 1,
		Callback = function(v)
			FakePos.X = v
		end,
	})
	FakeGroup:AddSlider("FakePosY", {
		Text = "Смещение Y",
		Default = 0,
		Min = -50,
		Max = 50,
		Rounding = 1,
		Callback = function(v)
			FakePos.Y = v
		end,
	})
	FakeGroup:AddSlider("FakePosZ", {
		Text = "Смещение Z",
		Default = 0,
		Min = -50,
		Max = 50,
		Rounding = 1,
		Callback = function(v)
			FakePos.Z = v
		end,
	})
else
	FakeGroup:AddLabel("Fake Position не поддерживается твоим экзекьютором")
end

local LagGroup = Tabs.Player:AddGroupbox({ Name = "Fake Lag", Side = "Right" })
LagGroup:AddToggle("FakeLag", {
	Text = "Включить",
	Default = false,
	Callback = function(v)
		FakeLag.Enabled = v
	end,
})
LagGroup:AddSlider("LagDuration", {
	Text = "Длительность фриза",
	Default = 0.15,
	Min = 0.05,
	Max = 1,
	Rounding = 2,
	Suffix = "с",
	Callback = function(v)
		FakeLag.Duration = v
	end,
})
LagGroup:AddSlider("LagRate", {
	Text = "Интервал",
	Default = 0.5,
	Min = 0.1,
	Max = 3,
	Rounding = 2,
	Suffix = "с",
	Callback = function(v)
		FakeLag.Rate = v
	end,
})

--// Разное //--
local UtilGroup = Tabs.Misc:AddGroupbox({ Name = "Утилиты", Side = "Left" })
UtilGroup:AddToggle("AntiVoid", {
	Text = "AntiVoid",
	Default = false,
	Callback = function(v)
		PlayerCfg.AntiVoid = v
	end,
})
UtilGroup:AddLabel("ClickTP", { Text = "ClickTP" }):AddKeyPicker("ClickTP", {
	Default = "E",
	Text = "Телепорт в точку курсора",
	Mode = "Press",
	Callback = function()
		if Unloaded then
			return
		end
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local hit = LP:GetMouse().Hit
			hrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3, 0))
		end
	end,
})
UtilGroup:AddButton({
	Text = "Реконнект",
	Func = function()
		TeleportService:Teleport(game.PlaceId, LP)
	end,
})
UtilGroup:AddButton({
	Text = "Anti-AFK (включить)",
	Func = function()
		LP.Idled:Connect(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
		Library:Notify({ Title = "Anti-AFK включен", Time = 3 })
	end,
})

--// Превью (белый клон) //--
do
	local function PaintWhite(model)
		for _, obj in ipairs(model:GetDescendants()) do
			if obj:IsA("BasePart") then
				obj.Color = Color3.new(1, 1, 1)
				obj.Material = Enum.Material.SmoothPlastic
			elseif obj:IsA("Decal")
				or obj:IsA("Texture")
				or obj:IsA("SurfaceAppearance")
				or obj:IsA("Shirt")
				or obj:IsA("Pants")
				or obj:IsA("ShirtGraphic")
				or obj:IsA("Script")
				or obj:IsA("LocalScript") then
				obj:Destroy()
			end
		end
	end

	local char = LP.Character or LP.CharacterAdded:Wait()
	local was = char.Archivable
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = was
	clone:PivotTo(char:GetPivot())

	local vp = ViewportGroup:AddViewport("SelfPreview", {
		Object = clone,
		Clone = false,
		Camera = Instance.new("Camera"),
		Interactive = true,
		AutoFocus = true,
		Height = 200,
	})
	PaintWhite(vp.Object)

	Listen(RunService.Heartbeat, function()
		if Unloaded then
			return
		end
		local c = LP.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if hrp and vp.Object then
			pcall(function()
				vp.Object:PivotTo(hrp.CFrame)
			end)
		end
	end)

	Listen(LP.CharacterAdded, function(newChar)
		task.wait(0.5)
		pcall(function()
			local was2 = newChar.Archivable
			newChar.Archivable = true
			local newClone = newChar:Clone()
			newChar.Archivable = was2
			PaintWhite(newClone)
			vp:SetObject(newClone, false)
			vp:Focus()
		end)
	end)
end

--// Настройки //--
local MenuGroup = Tabs.Settings:AddGroupbox({ Name = "Меню", Side = "Left" })
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightControl",
	NoUI = true,
	Text = "Клавиша меню",
})
Options.MenuKeybind:OnChanged(function(v)
	if typeof(v) == "EnumItem" then
		Library.ToggleKeybind = v
	end
end)
Library.ToggleKeybind = Enum.KeyCode.RightControl

MenuGroup:AddSlider("CornerRadiusSlider", {
	Text = "Радиус углов",
	Default = 12,
	Min = 0,
	Max = 20,
	Rounding = 0,
	Callback = function(v)
		Window:SetCornerRadius(v)
	end,
})
MenuGroup:AddSlider("WindowTransparency", {
	Text = "Прозрачность окна",
	Default = 0.1,
	Min = 0,
	Max = 0.9,
	Rounding = 2,
	Callback = function(v)
		Window:SetBackgroundTransparency(v)
	end,
})
MenuGroup:AddDropdown("DPIDropdown", {
	Values = { "75%", "100%", "125%", "150%" },
	Default = "100%",
	Text = "Масштаб",
	Callback = function(v)
		Library:SetDPIScale(tonumber(v:gsub("%%", "")))
	end,
})
MenuGroup:AddButton({
	Text = "Выгрузить",
	Func = function()
		Library:Unload()
	end,
})

--// Менеджеры //--
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("zcva")
SaveManager:SetFolder("zcva/main")
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

--// Выгрузка //--
Library:OnUnload(function()
	Unloaded = true

	for _, conn in ipairs(Connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(Connections)

	for _, obj in ipairs(Drawings) do
		pcall(function()
			obj:Remove()
		end)
	end
	table.clear(Drawings)

	ChamsClear()
	StopFly()

	pcall(function()
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = false
		end
	end)

	Lighting.Ambient = SavedLighting.Ambient
	Lighting.Brightness = SavedLighting.Brightness
	Lighting.GlobalShadows = SavedLighting.GlobalShadows
	Lighting.FogEnd = SavedLighting.FogEnd
	Lighting.FogStart = SavedLighting.FogStart

	print("[zcva] выгружено")
end)

print("[zcva] загружен")
