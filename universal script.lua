-- ==========================================================
-- Fly GUI V6.7-Opt2 + 接管相机 (真·纯逻辑修复版)
-- ==========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

local soulMode = false
local watchTarget = nil
local aimLockTarget = nil
local stickTarget = nil
local targetYaw, targetPitch = 0, 0
local soulYaw, soulPitch = 0, 0
local followOffsetForward = -1.5
local followOffsetRight = 0
local followOffsetUp = 1
local currentWalkSpeed = 16
local currentJumpPower = 50
-- 防撞状态：按需锁位置，不常驻
local antiKnockback = false
local antiKB_BodyPosition = nil
local antiKB_TargetPos = Vector3.zero
local antiKB_ActiveUntil = 0

local myLoop = {Run = true}
local myConns = {}
if _G.FlyGuiV4_Loop then _G.FlyGuiV4_Loop.Run = false end
if _G.FlyGuiV4_Conns then
    for _, c in pairs(_G.FlyGuiV4_Conns) do pcall(function() c:Disconnect() end) end
end
_G.FlyGuiV4_Conns = myConns
_G.FlyGuiV4_Loop = myLoop
pcall(function() RunService:UnbindFromRenderStep("Aimbot") end)
pcall(function() RunService:UnbindFromRenderStep("TakeoverCameraLoop") end)

local function loopAlive() return myLoop.Run end
local function track(conn)
    if not myLoop.Run then
        pcall(function() conn:Disconnect() end)
        return conn
    end
    table.insert(myConns, conn)
    return conn
end

pcall(function()
    for _, name in ipairs({"FlyGui_V4", "TakeoverCamera"}) do
        local old = PlayerGui:FindFirstChild(name)
        if old then old:Destroy() end
        local oldCore = CoreGui:FindFirstChild(name)
        if oldCore then oldCore:Destroy() end
    end
    for _, obj in pairs(CoreGui:GetChildren()) do
        if obj.Name == "ESP_Highlight" then obj:Destroy() end
    end
end)

track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if workspace.CurrentCamera then Camera = workspace.CurrentCamera end
end))

-- ===== 工具函数 =====
local function getTargetPart(player)
    if not player or not player.Character then return nil end
    local char = player.Character
    if not char.Parent then return nil end
    for _, name in ipairs({"Head", "UpperTorso", "Torso", "HumanoidRootPart"}) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    for _, v in pairs(char:GetChildren()) do
        if v:IsA("BasePart") then return v end
    end
    return nil
end

local function getHRP(char)
    if not char or not char.Parent then return nil end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChildWhichIsA("BasePart")
end

local function getClosestTarget()
    if not Camera then return nil end
    local closest, minDist = nil, 9999
    local sc = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, pl in pairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            local tp = getTargetPart(pl)
            if tp then
                local hum = pl.Character and pl.Character:FindFirstChild("Humanoid")
                if hum and hum.Health > 0 then
                    local sp, onScreen = Camera:WorldToViewportPoint(tp.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - sc).Magnitude
                        if d < minDist and d < 500 then minDist = d; closest = tp end
                    end
                end
            end
        end
    end
    return closest
end

local translateDict = {
    ["door"] = "门", ["exit"] = "出口", ["knob"] = "门把手", ["keypad"] = "密码锁",
    ["drawer"] = "抽屉", ["cabinet"] = "柜子", ["chest"] = "宝箱", ["locker"] = "储物柜",
    ["seat"] = "座位", ["chair"] = "椅子", ["button"] = "按钮", ["switch"] = "开关",
    ["lever"] = "拉杆", ["valve"] = "阀门", ["key"] = "钥匙", ["coin"] = "金币",
    ["item"] = "物品", ["pickup"] = "可拾取", ["bed"] = "床", ["book"] = "书",
    ["fuse"] = "保险丝", ["battery"] = "电池", ["candle"] = "蜡烛", ["painting"] = "画",
    ["pull"] = "拉绳", ["push"] = "推门", ["open"] = "打开"
}

local function translateName(engName)
    local lowerName = string.lower(engName)
    if translateDict[lowerName] then return translateDict[lowerName] end
    for eng, chn in pairs(translateDict) do
        if string.find(lowerName, eng) then
            return chn
        end
    end
    return engName
end

local npcCache = setmetatable({}, {__mode = "k"})

local function registerNPC(model)
    if not model or not model:IsA("Model") then return end
    if model == LocalPlayer.Character then return end
    if Players:GetPlayerFromCharacter(model) then return end
    if model:FindFirstChildOfClass("Humanoid") then
        npcCache[model] = true
    end
end

local function unregisterNPC(model)
    if model then npcCache[model] = nil end
end

for _, obj in pairs(workspace:GetDescendants()) do
    if obj:IsA("Model") then registerNPC(obj) end
end

track(workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") then
        registerNPC(obj)
    elseif obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
        registerNPC(obj.Parent)
    end
end))

track(workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Model") then
        unregisterNPC(obj)
    end
end))

-- ==========================================
-- 主界面 UI
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FlyGui_V4"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 190, 0, 164)
MainFrame.Position = UDim2.new(0.15, 0, 0.1, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
MainFrame.BackgroundTransparency = 0.1
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.ZIndex = 101
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local mainStroke = Instance.new("UIStroke", MainFrame)
mainStroke.Color = Color3.fromRGB(0, 200, 255)
mainStroke.Thickness = 1
mainStroke.Transparency = 0.2

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 30)
TopBar.BackgroundTransparency = 1
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(0, 8, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 22, 0, 22)
ToggleBtn.Position = UDim2.new(0, 34, 0, 4)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 200)
ToggleBtn.Text = "T"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 12
ToggleBtn.Parent = TopBar
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 5)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -65, 1, 0)
Title.Position = UDim2.new(0, 65, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Fly GUI Opt2"
Title.TextColor3 = Color3.fromRGB(0, 220, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local dragging, dragStart, startPos = false, nil, nil
Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
track(UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local d = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end))

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -16, 0, 24)
TabBar.Position = UDim2.new(0, 8, 0, 30)
TabBar.BackgroundTransparency = 1
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame

local BasicTab = Instance.new("TextButton")
BasicTab.Size = UDim2.new(0.5, -2, 1, 0)
BasicTab.BackgroundColor3 = Color3.fromRGB(0, 120, 180)
BasicTab.Text = "基础"
BasicTab.TextColor3 = Color3.fromRGB(255, 255, 255)
BasicTab.Font = Enum.Font.GothamBold
BasicTab.TextSize = 12
BasicTab.Parent = TabBar
Instance.new("UICorner", BasicTab).CornerRadius = UDim.new(0, 6)

local AdvTab = Instance.new("TextButton")
AdvTab.Size = UDim2.new(0.5, -2, 1, 0)
AdvTab.Position = UDim2.new(0.5, 2, 0, 0)
AdvTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40)
AdvTab.Text = "高级"
AdvTab.TextColor3 = Color3.fromRGB(150, 160, 170)
AdvTab.Font = Enum.Font.GothamBold
AdvTab.TextSize = 12
AdvTab.Parent = TabBar
Instance.new("UICorner", AdvTab).CornerRadius = UDim.new(0, 6)

local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, -16, 1, -64)
ContentFrame.Position = UDim2.new(0, 8, 0, 60)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

local PageBasic = Instance.new("Frame")
PageBasic.Size = UDim2.new(1, 0, 1, 0)
PageBasic.BackgroundTransparency = 1
PageBasic.Parent = ContentFrame

local PageAdv = Instance.new("Frame")
PageAdv.Size = UDim2.new(1, 0, 1, 0)
PageAdv.BackgroundTransparency = 1
PageAdv.Visible = false
PageAdv.Parent = ContentFrame

local function createButton(name, text, pos, color, parent, size)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = size or UDim2.new(0.33, -2, 0, 28)
    btn.Position = pos
    btn.BackgroundColor3 = color
    btn.BackgroundTransparency = 0.1
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local AimBtn = createButton("Aim", "随机自瞄: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(60, 90, 150), PageBasic, UDim2.new(0.5, -2, 0, 28))
local OpenListBtn = createButton("OpenList", "玩家列表", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(180, 60, 140), PageBasic, UDim2.new(0.5, -2, 0, 28))
local FlyBtn = createButton("Fly", "开启飞行", UDim2.new(0, 0, 0, 32), Color3.fromRGB(180, 160, 40), PageBasic, UDim2.new(0.5, -2, 0, 28))
local NoclipBtn = createButton("Noclip", "穿墙模式", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(80, 80, 90), PageBasic, UDim2.new(0.5, -2, 0, 28))
local WalkSpeedBtn = createButton("WalkSpeed", "速度: 16", UDim2.new(0, 0, 0, 64), Color3.fromRGB(60, 100, 150), PageBasic, UDim2.new(0.5, -2, 0, 28))
local JumpBtn = createButton("Jump", "跳高: 50", UDim2.new(0.5, 2, 0, 64), Color3.fromRGB(150, 100, 60), PageBasic, UDim2.new(0.5, -2, 0, 28))

local AntiCollideBtn = createButton("AntiCollide", "防撞: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(100, 100, 120), PageAdv, UDim2.new(1, 0, 0, 28))
local CollectBtn = createButton("Collect", "全图开箱", UDim2.new(0, 0, 0, 32), Color3.fromRGB(180, 120, 40), PageAdv, UDim2.new(0.5, -2, 0, 28))
local AirWalkBtn = createButton("AirWalk", "空中行走", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(40, 130, 150), PageAdv, UDim2.new(0.5, -2, 0, 28))
local SoulBtn = createButton("Soul", "出窍: 关", UDim2.new(0, 0, 0, 64), Color3.fromRGB(140, 80, 60), PageAdv, UDim2.new(0.5, -2, 0, 28))
local DarkBtn = createButton("DarkRemove", "去黑: 关", UDim2.new(0.5, 2, 0, 64), Color3.fromRGB(140, 120, 50), PageAdv, UDim2.new(0.5, -2, 0, 28))
local EspBtn = createButton("Esp", "人透: 关", UDim2.new(0, 0, 0, 96), Color3.fromRGB(140, 50, 120), PageAdv, UDim2.new(0.5, -2, 0, 28))
local ItemEspBtn = createButton("ItemEsp", "物透: 关", UDim2.new(0.5, 2, 0, 96), Color3.fromRGB(40, 140, 140), PageAdv, UDim2.new(0.5, -2, 0, 28))
local PlayerHitboxBtn = createButton("PlayerHitbox", "玩家: 正常", UDim2.new(0, 0, 0, 128), Color3.fromRGB(140, 140, 40), PageAdv, UDim2.new(0.5, -2, 0, 28))
local NPCHitboxBtn = createButton("NPCHitbox", "NPC: 正常", UDim2.new(0.5, 2, 0, 128), Color3.fromRGB(160, 50, 50), PageAdv, UDim2.new(0.5, -2, 0, 28))
local FovBtn = createButton("FovBtn", "视野(FOV): 70", UDim2.new(0, 0, 0, 160), Color3.fromRGB(60, 90, 150), PageAdv, UDim2.new(1, 0, 0, 28))
local CamBtn = createButton("CamBtn", "相机: 关闭", UDim2.new(0, 0, 0, 192), Color3.fromRGB(100, 50, 150), PageAdv, UDim2.new(1, 0, 0, 28))
local camState = 0
local camDistance = 12
local camSensitivity = 1.0

local SpeedSliderContainer = Instance.new("Frame")
SpeedSliderContainer.Name = "SpeedSliderContainer"
SpeedSliderContainer.Size = UDim2.new(1, 0, 0, 26)
SpeedSliderContainer.Position = UDim2.new(0, 0, 0, 100)
SpeedSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
SpeedSliderContainer.BackgroundTransparency = 0.1
SpeedSliderContainer.Visible = false
SpeedSliderContainer.ZIndex = 105
SpeedSliderContainer.Parent = PageBasic
Instance.new("UICorner", SpeedSliderContainer).CornerRadius = UDim.new(0, 8)

local SpeedBg = Instance.new("Frame")
SpeedBg.Size = UDim2.new(1, -20, 0, 6)
SpeedBg.Position = UDim2.new(0, 10, 0.5, -3)
SpeedBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
SpeedBg.BorderSizePixel = 0
SpeedBg.Active = true
SpeedBg.ZIndex = 106
SpeedBg.Parent = SpeedSliderContainer
Instance.new("UICorner", SpeedBg).CornerRadius = UDim.new(1, 0)

local SpeedThumb = Instance.new("TextButton")
SpeedThumb.Size = UDim2.new(0, 16, 0, 16)
SpeedThumb.Position = UDim2.new(0, -8, 0.5, -8)
SpeedThumb.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
SpeedThumb.Text = ""
SpeedThumb.ZIndex = 107
SpeedThumb.Parent = SpeedSliderContainer
Instance.new("UICorner", SpeedThumb).CornerRadius = UDim.new(1, 0)

local SliderContainer = Instance.new("Frame")
SliderContainer.Name = "SliderContainer"
SliderContainer.Size = UDim2.new(0, 40, 0, 150)
SliderContainer.Position = UDim2.new(1, 5, 0, 100)
SliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
SliderContainer.BackgroundTransparency = 0.1
SliderContainer.Visible = false
SliderContainer.ZIndex = 110
SliderContainer.Parent = MainFrame
Instance.new("UICorner", SliderContainer).CornerRadius = UDim.new(0, 8)

local SliderBg = Instance.new("Frame")
SliderBg.Size = UDim2.new(0, 6, 1, -20)
SliderBg.Position = UDim2.new(0.5, -3, 0, 10)
SliderBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
SliderBg.BorderSizePixel = 0
SliderBg.Active = true
SliderBg.ZIndex = 111
SliderBg.Parent = SliderContainer
Instance.new("UICorner", SliderBg).CornerRadius = UDim.new(1, 0)

local SliderThumb = Instance.new("TextButton")
SliderThumb.Size = UDim2.new(0, 20, 0, 20)
SliderThumb.Position = UDim2.new(0, 10, 0.5, -10)
SliderThumb.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
SliderThumb.Text = ""
SliderThumb.ZIndex = 112
SliderThumb.Parent = SliderContainer
Instance.new("UICorner", SliderThumb).CornerRadius = UDim.new(1, 0)

local CamDistSliderContainer = Instance.new("Frame")
CamDistSliderContainer.Name = "CamDistSliderContainer"
CamDistSliderContainer.Size = UDim2.new(0, 40, 0, 150)
CamDistSliderContainer.Position = UDim2.new(1, 50, 0, 100)
CamDistSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
CamDistSliderContainer.BackgroundTransparency = 0.1
CamDistSliderContainer.Visible = false
CamDistSliderContainer.ZIndex = 120
CamDistSliderContainer.Parent = MainFrame
Instance.new("UICorner", CamDistSliderContainer).CornerRadius = UDim.new(0, 8)

local CamDistBg = Instance.new("Frame")
CamDistBg.Size = UDim2.new(0, 6, 1, -20)
CamDistBg.Position = UDim2.new(0.5, -3, 0, 10)
CamDistBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
CamDistBg.BorderSizePixel = 0
CamDistBg.Active = true
CamDistBg.ZIndex = 121
CamDistBg.Parent = CamDistSliderContainer
Instance.new("UICorner", CamDistBg).CornerRadius = UDim.new(1, 0)

local CamDistThumb = Instance.new("TextButton")
CamDistThumb.Size = UDim2.new(0, 20, 0, 20)
CamDistThumb.Position = UDim2.new(0, 10, 0.5, -10)
CamDistThumb.BackgroundColor3 = Color3.fromRGB(200, 100, 255)
CamDistThumb.Text = ""
CamDistThumb.ZIndex = 122
CamDistThumb.Parent = CamDistSliderContainer
Instance.new("UICorner", CamDistThumb).CornerRadius = UDim.new(1, 0)

local WalkSpeedSliderContainer = Instance.new("Frame")
WalkSpeedSliderContainer.Name = "WalkSpeedSliderContainer"
WalkSpeedSliderContainer.Size = UDim2.new(0, 40, 0, 150)
WalkSpeedSliderContainer.Position = UDim2.new(1, 5, 0, 100)
WalkSpeedSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
WalkSpeedSliderContainer.BackgroundTransparency = 0.1
WalkSpeedSliderContainer.Visible = false
WalkSpeedSliderContainer.ZIndex = 130
WalkSpeedSliderContainer.Parent = MainFrame
Instance.new("UICorner", WalkSpeedSliderContainer).CornerRadius = UDim.new(0, 8)

local WalkSpeedBg = Instance.new("Frame")
WalkSpeedBg.Size = UDim2.new(0, 6, 1, -20)
WalkSpeedBg.Position = UDim2.new(0.5, -3, 0, 10)
WalkSpeedBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
WalkSpeedBg.BorderSizePixel = 0
WalkSpeedBg.Active = true
WalkSpeedBg.ZIndex = 131
WalkSpeedBg.Parent = WalkSpeedSliderContainer
Instance.new("UICorner", WalkSpeedBg).CornerRadius = UDim.new(1, 0)

local WalkSpeedThumb = Instance.new("TextButton")
WalkSpeedThumb.Size = UDim2.new(0, 20, 0, 20)
WalkSpeedThumb.Position = UDim2.new(0, 10, 0.5, -10)
WalkSpeedThumb.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
WalkSpeedThumb.Text = ""
WalkSpeedThumb.ZIndex = 132
WalkSpeedThumb.Parent = WalkSpeedSliderContainer
Instance.new("UICorner", WalkSpeedThumb).CornerRadius = UDim.new(1, 0)

local JumpSliderContainer = Instance.new("Frame")
JumpSliderContainer.Name = "JumpSliderContainer"
JumpSliderContainer.Size = UDim2.new(0, 40, 0, 150)
JumpSliderContainer.Position = UDim2.new(1, 50, 0, 100)
JumpSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
JumpSliderContainer.BackgroundTransparency = 0.1
JumpSliderContainer.Visible = false
JumpSliderContainer.ZIndex = 140
JumpSliderContainer.Parent = MainFrame
Instance.new("UICorner", JumpSliderContainer).CornerRadius = UDim.new(0, 8)

local JumpBg = Instance.new("Frame")
JumpBg.Size = UDim2.new(0, 6, 1, -20)
JumpBg.Position = UDim2.new(0.5, -3, 0, 10)
JumpBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
JumpBg.BorderSizePixel = 0
JumpBg.Active = true
JumpBg.ZIndex = 141
JumpBg.Parent = JumpSliderContainer
Instance.new("UICorner", JumpBg).CornerRadius = UDim.new(1, 0)

local JumpThumb = Instance.new("TextButton")
JumpThumb.Size = UDim2.new(0, 20, 0, 20)
JumpThumb.Position = UDim2.new(0, 10, 0.5, -10)
JumpThumb.BackgroundColor3 = Color3.fromRGB(255, 180, 100)
JumpThumb.Text = ""
JumpThumb.ZIndex = 142
JumpThumb.Parent = JumpSliderContainer
Instance.new("UICorner", JumpThumb).CornerRadius = UDim.new(1, 0)


local speeds = 1
local currentFov = 70
local currentTab = 1
local isMinimized = false

local function updateSpeedFromX(absoluteX)
    local bgAbsX = SpeedBg.AbsolutePosition.X
    local bgWidth = SpeedBg.AbsoluteSize.X
    if bgWidth <= 0 then return end
    local relativeX = (absoluteX - bgAbsX) / bgWidth
    relativeX = math.clamp(relativeX, 0, 1)
    speeds = math.floor(1 + (relativeX * 9) + 0.5)
    SpeedThumb.Position = UDim2.new(relativeX, -8, 0.5, -8)
end

local function updateFovFromY(absoluteY)
    local bgAbsY = SliderBg.AbsolutePosition.Y
    local bgHeight = SliderBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = (absoluteY - bgAbsY) / bgHeight
    relativeY = math.clamp(relativeY, 0, 1)
    currentFov = math.floor(120 - (relativeY * 70))
    if Camera then Camera.FieldOfView = currentFov end
    FovBtn.Text = "视野(FOV): " .. currentFov
    SliderThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateCamDistFromY(absoluteY)
    local bgAbsY = CamDistBg.AbsolutePosition.Y
    local bgHeight = CamDistBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = (absoluteY - bgAbsY) / bgHeight
    relativeY = math.clamp(relativeY, 0, 1)
    camDistance = math.floor(4 + ((1 - relativeY) * 36) + 0.5)
    CamDistThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateWalkSpeedFromY(absoluteY)
    local bgAbsY = WalkSpeedBg.AbsolutePosition.Y
    local bgHeight = WalkSpeedBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = (absoluteY - bgAbsY) / bgHeight
    relativeY = math.clamp(relativeY, 0, 1)
    currentWalkSpeed = math.floor(200 - (relativeY * 184))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char.Humanoid.WalkSpeed = currentWalkSpeed
    end
    WalkSpeedBtn.Text = "速度: " .. currentWalkSpeed
    WalkSpeedThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateJumpFromY(absoluteY)
    local bgAbsY = JumpBg.AbsolutePosition.Y
    local bgHeight = JumpBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = (absoluteY - bgAbsY) / bgHeight
    relativeY = math.clamp(relativeY, 0, 1)
    currentJumpPower = math.floor(200 - (relativeY * 150))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char.Humanoid.JumpPower = currentJumpPower
        char.Humanoid.UseJumpPower = true
    end
    JumpBtn.Text = "跳高: " .. currentJumpPower
    JumpThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local mainDragInput = nil
local mainDragType = nil

track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local pos = input.Position
        
        if SpeedSliderContainer.Visible then
            local absPos = SpeedSliderContainer.AbsolutePosition
            local absSize = SpeedSliderContainer.AbsoluteSize
            if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
                mainDragInput = input; mainDragType = "speed"; updateSpeedFromX(pos.X); return
            end
        end
        if SliderContainer.Visible then
            local absPos = SliderContainer.AbsolutePosition
            local absSize = SliderContainer.AbsoluteSize
            if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
                mainDragInput = input; mainDragType = "fov"; updateFovFromY(pos.Y); return
            end
        end
        if CamDistSliderContainer.Visible then
            local absPos = CamDistSliderContainer.AbsolutePosition
            local absSize = CamDistSliderContainer.AbsoluteSize
            if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
                mainDragInput = input; mainDragType = "camdist"; updateCamDistFromY(pos.Y); return
            end
        end
        if WalkSpeedSliderContainer.Visible then
            local absPos = WalkSpeedSliderContainer.AbsolutePosition
            local absSize = WalkSpeedSliderContainer.AbsoluteSize
            if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
                mainDragInput = input; mainDragType = "walkspeed"; updateWalkSpeedFromY(pos.Y); return
            end
        end
        if JumpSliderContainer.Visible then
            local absPos = JumpSliderContainer.AbsolutePosition
            local absSize = JumpSliderContainer.AbsoluteSize
            if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
                mainDragInput = input; mainDragType = "jump"; updateJumpFromY(pos.Y); return
            end
        end
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if input == mainDragInput then
        if mainDragType == "speed" then updateSpeedFromX(input.Position.X)
        elseif mainDragType == "fov" then updateFovFromY(input.Position.Y)
        elseif mainDragType == "camdist" then updateCamDistFromY(input.Position.Y)
        elseif mainDragType == "walkspeed" then updateWalkSpeedFromY(input.Position.Y)
        elseif mainDragType == "jump" then updateJumpFromY(input.Position.Y) end
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input == mainDragInput then
        mainDragInput = nil; mainDragType = nil
    end
end))

-- ==========================================
-- 接管相机
-- ==========================================
local camYaw = 0
local camPitch = 20
local isCameraLocked = false

local function getFocusPart()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
end

local function resetCamera()
    if Camera and Camera.CameraType == Enum.CameraType.Scriptable then
        Camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            Camera.CameraSubject = char.Humanoid
        end
    end
end

local function updateHeadVisibility()
    local char = LocalPlayer.Character
    if not char or soulMode then return end
    local head = char:FindFirstChild("Head")
    local hide = (camState == 2)
    
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            local isHeadPart = false
            if v == head then
                isHeadPart = true
            elseif v.Parent and v.Parent:IsA("Accessory") then
                local aType = v.Parent.AccessoryType
                if aType == Enum.AccessoryType.Hat or aType == Enum.AccessoryType.Hair or aType == Enum.AccessoryType.Neck then
                    isHeadPart = true
                end
            end
            
            if isHeadPart then
                v.LocalTransparencyModifier = hide and 1 or 0
            else
                if camState ~= 0 then
                    v.LocalTransparencyModifier = 0
                end
            end
        elseif v:IsA("Decal") and v.Parent == head then
            v.Transparency = hide and 1 or 0
        end
    end
end

track(RunService:BindToRenderStep("TakeoverCameraLoop", Enum.RenderPriority.Last.Value - 1, function(dt)
    if camState == 0 or not loopAlive() then return end
    local focus = getFocusPart()
    if not Camera or not focus then return end

    if Camera.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function() Camera.CameraType = Enum.CameraType.Scriptable end)
    end

    if camState == 2 then
        updateHeadVisibility()
    end

    local focusPos = focus.Position
    local yawRad = math.rad(camYaw)
    local pitchRad = math.rad(camPitch)
    local rot = CFrame.fromEulerAnglesYXZ(pitchRad, yawRad, 0)

    if camState == 1 then
        local offset = rot.LookVector * -camDistance
        local targetPos = focusPos + offset
        local rp = RaycastParams.new()
        local char = LocalPlayer.Character
        if char then
            rp.FilterDescendantsInstances = {char}
            rp.FilterType = Enum.RaycastFilterType.Exclude
        end
        local ray = workspace:Raycast(focusPos, offset, rp)
        if ray then targetPos = ray.Position + ray.Normal * 0.5 end
        Camera.CFrame = CFrame.lookAt(targetPos, focusPos)
    else
        local offset = Vector3.new(0, 1.2, 0)
        Camera.CFrame = CFrame.new(focusPos + offset + rot.LookVector * 1.5) * rot
    end
end))

local camDragInput = nil
track(UserInputService.InputBegan:Connect(function(input)
    if camState == 0 and not soulMode then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local vp = Camera and Camera.ViewportSize or Vector2.new(800, 600)
        local pos = input.Position
        
        if SliderContainer.Visible then
            local p = SliderContainer.AbsolutePosition
            local s = SliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        if CamDistSliderContainer.Visible then
            local p = CamDistSliderContainer.AbsolutePosition
            local s = CamDistSliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        if WalkSpeedSliderContainer.Visible then
            local p = WalkSpeedSliderContainer.AbsolutePosition
            local s = WalkSpeedSliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        if JumpSliderContainer.Visible then
            local p = JumpSliderContainer.AbsolutePosition
            local s = JumpSliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        local p = MainFrame.AbsolutePosition
        local s = MainFrame.AbsoluteSize
        if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end

        if pos.X > vp.X * 0.35 then
            camDragInput = input
        end
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if (camState == 0 and not soulMode) or not camDragInput or input ~= camDragInput then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Delta
        if soulMode then
            targetYaw = targetYaw - delta.X * camSensitivity
            targetPitch = math.clamp(targetPitch - delta.Y * camSensitivity, -60, 60)
        else
            camYaw = camYaw - delta.X * camSensitivity
            camPitch = math.clamp(camPitch - delta.Y * camSensitivity, -60, 60)
        end
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input == camDragInput then camDragInput = nil end
end))

track(LocalPlayer.CharacterAdded:Connect(function()
    if camState ~= 0 then
        task.wait(0.3)
        if Camera then pcall(function() Camera.CameraType = Enum.CameraType.Scriptable end) end
    end
end))

local function showPage(idx)
    currentTab = idx
    PageBasic.Visible = idx == 1
    PageAdv.Visible = idx == 2
    BasicTab.BackgroundColor3 = idx == 1 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    BasicTab.TextColor3 = idx == 1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    AdvTab.BackgroundColor3 = idx == 2 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    AdvTab.TextColor3 = idx == 2 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    if idx == 1 then
        SliderContainer.Visible = false
        CamDistSliderContainer.Visible = false
    else
        WalkSpeedSliderContainer.Visible = false
        JumpSliderContainer.Visible = false
    end
    if idx == 1 then
        MainFrame.Size = UDim2.new(0, 190, 0, 164)
    else
        MainFrame.Size = UDim2.new(0, 190, 0, 290)
    end
end
BasicTab.MouseButton1Click:Connect(function() showPage(1) end)
AdvTab.MouseButton1Click:Connect(function() showPage(2) end)

FovBtn.MouseButton1Click:Connect(function()
    SliderContainer.Visible = not SliderContainer.Visible
    if SliderContainer.Visible then CamDistSliderContainer.Visible = false end
end)

WalkSpeedBtn.MouseButton1Click:Connect(function()
    WalkSpeedSliderContainer.Visible = not WalkSpeedSliderContainer.Visible
    if WalkSpeedSliderContainer.Visible then JumpSliderContainer.Visible = false end
end)

JumpBtn.MouseButton1Click:Connect(function()
    JumpSliderContainer.Visible = not JumpSliderContainer.Visible
    if JumpSliderContainer.Visible then WalkSpeedSliderContainer.Visible = false end
end)

CamBtn.MouseButton1Click:Connect(function()
    if watchTarget then
        watchTarget = nil
        if Camera then
            Camera.CameraType = Enum.CameraType.Custom
            local wc = LocalPlayer.Character
            if wc and wc:FindFirstChild("Humanoid") then
                Camera.CameraSubject = wc.Humanoid
            end
        end
    end

    camState = camState + 1
    if camState > 2 then camState = 0 end
    
    if camState == 1 then
        local focus = getFocusPart()
        if focus and Camera then
            local look = Camera.CFrame.LookVector
            camYaw = math.deg(math.atan2(-look.X, -look.Z))
            camPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        end
        CamBtn.Text = "相机: 第三人称"
        CamBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
        CamDistSliderContainer.Visible = true
    elseif camState == 2 then
        CamBtn.Text = "相机: 第一人称"
        CamBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 0)
        CamDistSliderContainer.Visible = false
    else
        CamBtn.Text = "相机: 关闭"
        CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
        CamDistSliderContainer.Visible = false
        
        updateHeadVisibility()
        resetCamera()
    end
end)

-- ===== 玩家列表 =====
local ListFrame = Instance.new("Frame")
ListFrame.Size = UDim2.new(0, 180, 0, 280)
ListFrame.Position = UDim2.new(1, 0, 0, 0)
ListFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
ListFrame.BackgroundTransparency = 0.1
ListFrame.Visible = false
ListFrame.ZIndex = 150
ListFrame.Parent = MainFrame
Instance.new("UICorner", ListFrame).CornerRadius = UDim.new(0, 10)
local listStroke = Instance.new("UIStroke", ListFrame)
listStroke.Color = Color3.fromRGB(0, 220, 140)
listStroke.Thickness = 1
listStroke.Transparency = 0.2

local ListTitleBg = Instance.new("Frame")
ListTitleBg.Size = UDim2.new(1, 0, 0, 30)
ListTitleBg.BackgroundTransparency = 1
ListTitleBg.ZIndex = 151
ListTitleBg.Parent = ListFrame

local ListTitle = Instance.new("TextLabel")
ListTitle.Size = UDim2.new(1, -30, 0, 30)
ListTitle.BackgroundTransparency = 1
ListTitle.Text = "玩家列表"
ListTitle.TextColor3 = Color3.fromRGB(0, 230, 150)
ListTitle.Font = Enum.Font.GothamBold
ListTitle.TextSize = 13
ListTitle.TextXAlignment = Enum.TextXAlignment.Center
ListTitle.TextYAlignment = Enum.TextYAlignment.Center
ListTitle.ZIndex = 152
ListTitle.Parent = ListFrame

local CloseListBtn = Instance.new("TextButton")
CloseListBtn.Size = UDim2.new(0, 22, 0, 22)
CloseListBtn.Position = UDim2.new(1, -26, 0, 4)
CloseListBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseListBtn.Text = "X"
CloseListBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseListBtn.Font = Enum.Font.GothamBold
CloseListBtn.TextSize = 12
CloseListBtn.ZIndex = 153
CloseListBtn.Parent = ListFrame
Instance.new("UICorner", CloseListBtn).CornerRadius = UDim.new(0, 5)

local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Size = UDim2.new(1, -10, 1, -40)
ScrollingFrame.Position = UDim2.new(0, 5, 0, 35)
ScrollingFrame.BackgroundTransparency = 1
ScrollingFrame.ScrollBarThickness = 4
ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollingFrame.ZIndex = 152
ScrollingFrame.Parent = ListFrame
Instance.new("UIListLayout", ScrollingFrame).Padding = UDim.new(0, 4)

local FollowCtrlFrame = Instance.new("Frame")
FollowCtrlFrame.Name = "FollowCtrlFrame"
FollowCtrlFrame.Size = UDim2.new(0, 34, 0, 216)
FollowCtrlFrame.Position = UDim2.new(1, 185, 0, 35)
FollowCtrlFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
FollowCtrlFrame.BackgroundTransparency = 0.1
FollowCtrlFrame.Visible = false
FollowCtrlFrame.ZIndex = 160
FollowCtrlFrame.Parent = MainFrame
Instance.new("UICorner", FollowCtrlFrame).CornerRadius = UDim.new(0, 6)
local followStroke = Instance.new("UIStroke", FollowCtrlFrame)
followStroke.Color = Color3.fromRGB(79, 255, 152)
followStroke.Thickness = 1
followStroke.Transparency = 0.2
local followPad = Instance.new("UIPadding", FollowCtrlFrame)
followPad.PaddingTop = UDim.new(0, 4)
followPad.PaddingBottom = UDim.new(0, 4)
followPad.PaddingLeft = UDim.new(0, 4)
followPad.PaddingRight = UDim.new(0, 4)
local followLayout = Instance.new("UIListLayout", FollowCtrlFrame)
followLayout.Padding = UDim.new(0, 2)
followLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function createFollowBtn(text, color, layoutOrder, axis, delta)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.BackgroundColor3 = color
    btn.BackgroundTransparency = 0.1
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.LayoutOrder = layoutOrder
    btn.ZIndex = 161
    btn.Parent = FollowCtrlFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(function()
        if axis == "forward" then followOffsetForward = followOffsetForward + delta
        elseif axis == "right" then followOffsetRight = followOffsetRight + delta
        elseif axis == "up" then followOffsetUp = followOffsetUp + delta
        end
        followOffsetForward = math.clamp(followOffsetForward, -15, 15)
        followOffsetRight = math.clamp(followOffsetRight, -15, 15)
        followOffsetUp = math.clamp(followOffsetUp, -15, 15)
    end)
    return btn
end

createFollowBtn("前", Color3.fromRGB(60, 90, 150), 1, "forward", 0.5)
createFollowBtn("后", Color3.fromRGB(60, 90, 150), 2, "forward", -0.5)
createFollowBtn("左", Color3.fromRGB(60, 90, 150), 3, "right", -0.5)
createFollowBtn("右", Color3.fromRGB(60, 90, 150), 4, "right", 0.5)
createFollowBtn("上", Color3.fromRGB(60, 140, 80), 5, "up", 0.5)
createFollowBtn("下", Color3.fromRGB(140, 80, 60), 6, "up", -0.5)

local resetFollowBtn = createFollowBtn("重", Color3.fromRGB(120, 60, 200), 7, "none", 0)
resetFollowBtn.MouseButton1Click:Connect(function()
    followOffsetForward = -1.5
    followOffsetRight = 0
    followOffsetUp = 1
end)

local flying = false
local noclip = false
local airwalkEnabled = false
local airwalkPlate = nil
local bodyVelocity = nil
local bodyGyro = nil
local flyAttach = nil
local aimMode = 0
local stickMode = false
local originalCollides = setmetatable({}, {__mode = "k"})

local noclipSeat = nil
local vehicleCollides = setmetatable({}, {__mode = "k"})
local vehicleScanCounter = 0

local flySoundBackup = {}
local flySoundConn = nil
local soundCheckCounter = 0

local soulCFrame = CFrame.new()
local originalPlayerSizes = setmetatable({}, {__mode = "k"})
local originalNPCSizes = setmetatable({}, {__mode = "k"})
local hitboxSizes = {1, 6, 12, 20, 30, 200, 500, 800}
local hitboxNames = {"正常", "中", "大", "巨", "极", "全", "终", "究"}
local playerHitboxIndex = 1
local npcHitboxIndex = 1

local lastListKey = ""
local refreshList = function() end

local itemEspEnabled = false
local itemEspCache = {}

local function restoreVehicleCollides()
    for part, c in pairs(vehicleCollides) do
        if part and part.Parent then
            pcall(function() part.CanCollide = c end)
        end
    end
    vehicleCollides = setmetatable({}, {__mode = "k"})
    noclipSeat = nil
    vehicleScanCounter = 0
end

local function applyNoclipToVehicle(seat, char)
    if noclipSeat ~= seat then
        restoreVehicleCollides()
        noclipSeat = seat
        vehicleScanCounter = 0
    end
    vehicleScanCounter = vehicleScanCounter + 1
    if vehicleScanCounter >= 10 or #vehicleCollides == 0 and vehicleScanCounter == 1 then
        vehicleScanCounter = 0
        local ok, parts = pcall(function() return seat:GetConnectedParts(true) end)
        if ok and parts then
            for _, part in ipairs(parts) do
                if part:IsA("BasePart") and not (char and part:IsDescendantOf(char)) then
                    if vehicleCollides[part] == nil then
                        vehicleCollides[part] = part.CanCollide
                    end
                end
            end
        end
    end
    for part in pairs(vehicleCollides) do
        if part and part.Parent and part.CanCollide then
            part.CanCollide = false
        end
    end
end

local function muteCharacterSounds()
    local char = LocalPlayer.Character
    if not char then return end
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("Sound") then
            if flySoundBackup[v] == nil then
                flySoundBackup[v] = v.Volume
            end
            if v.Volume ~= 0 then v.Volume = 0 end
        end
    end
end

local function unmuteCharacterSounds()
    if flySoundConn then
        flySoundConn:Disconnect()
        flySoundConn = nil
    end
    for sound, vol in pairs(flySoundBackup) do
        if sound and sound.Parent then
            pcall(function() sound.Volume = vol end)
        end
    end
    flySoundBackup = {}
end

local function stopPhysics()
    flying = false
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    flyAttach = nil
    unmuteCharacterSounds()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        local hum = char.Humanoid
        hum.PlatformStand = false
        for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
            if state ~= Enum.HumanoidStateType.Dead then
                pcall(function() hum:SetStateEnabled(state, true) end)
            end
        end
        if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end

local function startPhysics()
    local char = LocalPlayer.Character
    if not char or not char.Parent then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local attach
    local isInVehicle = false
    if hum.SeatPart then
        isInVehicle = true
        attach = hum.SeatPart.AssemblyRootPart or hum.SeatPart
        -- 尝试抢载具网络所有权；抢不到说明是副驾，不飞也不跳车
        local ok = pcall(function() attach:SetNetworkOwner(LocalPlayer) end)
        if not ok then
            return false
        end
    else
        if hum.RigType == Enum.HumanoidRigType.R6 then
            attach = char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
        else
            attach = char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
        end
    end
    if not attach then return false end
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    if not isInVehicle then
        for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
            if state ~= Enum.HumanoidStateType.Dead then
                pcall(function() hum:SetStateEnabled(state, false) end)
            end
        end
        hum.PlatformStand = true
        if char:FindFirstChild("Animate") then char.Animate.Disabled = true end
        pcall(function()
            for _, t in pairs(hum:GetPlayingAnimationTracks()) do t:AdjustSpeed(0) end
        end)
    end
    muteCharacterSounds()
    if flySoundConn then flySoundConn:Disconnect() end
    flySoundConn = char.DescendantAdded:Connect(function(inst)
        if inst:IsA("Sound") then
            if flySoundBackup[inst] == nil then flySoundBackup[inst] = inst.Volume end
            inst.Volume = 0
        end
    end)
    bodyVelocity = Instance.new("BodyVelocity", attach)
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVelocity.Velocity = Vector3.new(0, 0.1, 0)
    bodyGyro = Instance.new("BodyGyro", attach)
    bodyGyro.P = 9e4
    bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bodyGyro.CFrame = attach.CFrame
    flyAttach = attach
    return true
end

local function forceStopFly()
    if not flying then return end
    flying = false
    FlyBtn.Text = "开启飞行"
    FlyBtn.BackgroundColor3 = Color3.fromRGB(180, 160, 40)
    SpeedSliderContainer.Visible = false
    stopPhysics()
end

local function forceStopAirwalk()
    if not airwalkEnabled then return end
    airwalkEnabled = false
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    AirWalkBtn.Text = "空中行走"
    AirWalkBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 150)
end

local function forceStopStick()
    if not stickMode then return end
    stickMode = false
    if FollowCtrlFrame then FollowCtrlFrame.Visible = false end
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then char.Humanoid.PlatformStand = false end
end

local function toggleSoul(state)
    if state then
        if not Camera then return end
        local char = LocalPlayer.Character
        if not char or not char.Parent then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        soulMode = true
        forceStopFly(); forceStopAirwalk(); forceStopStick()
        if camState ~= 0 then
            camState = 0
            CamBtn.Text = "相机: 关闭"
            CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
            CamDistSliderContainer.Visible = false
        end
        if aimMode > 0 then
            aimMode = 0
            aimLockTarget = nil
            AimBtn.Text = "随机自瞄: 关"
            AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
            local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
        end
        local bp = Instance.new("BodyPosition")
        bp.Name = "SoulAnchor"
        bp.Position = hrp.Position
        bp.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bp.Parent = hrp
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then v.LocalTransparencyModifier = 1 end
            if v:IsA("Decal") then v.Transparency = 1 end
        end
        soulCFrame = Camera.CFrame
        local look = Camera.CFrame.LookVector
        targetYaw = math.deg(math.atan2(-look.X, -look.Z))
        targetPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        soulYaw, soulPitch = targetYaw, targetPitch
        Camera.CameraType = Enum.CameraType.Scriptable
    else
        soulMode = false
        local char = LocalPlayer.Character
        local finalCF = Camera and Camera.CFrame
        if char and char.Parent then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bp = hrp:FindFirstChild("SoulAnchor"); if bp then bp:Destroy() end
                if finalCF then hrp.CFrame = finalCF end
                for _, v in pairs(char:GetDescendants()) do
                    if v:IsA("BasePart") then v.LocalTransparencyModifier = 0 end
                    if v:IsA("Decal") then v.Transparency = 0 end
                end
            end
        end
        resetCamera()
    end
end

local function forceStopSoul()
    if not soulMode then return end
    toggleSoul(false)
    SoulBtn.Text = "出窍: 关"
    SoulBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 60)
end

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() or not soulMode or not Camera then return end
    soulYaw = soulYaw + (targetYaw - soulYaw) * 0.5
    soulPitch = soulPitch + (targetPitch - soulPitch) * 0.5
    local rot = CFrame.fromEulerAnglesYXZ(math.rad(soulPitch), math.rad(soulYaw), 0)
    local char = LocalPlayer.Character
    local flyDir = Vector3.zero
    if char and char:FindFirstChild("Humanoid") then
        local moveDir = char.Humanoid.MoveDirection
        if moveDir.Magnitude > 0.1 then
            local flatLook = Vector3.new(rot.LookVector.X, 0, rot.LookVector.Z)
            if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit else flatLook = Vector3.new(0,0,-1) end
            local f = moveDir:Dot(flatLook)
            local r = moveDir:Dot(rot.RightVector)
            flyDir = rot.LookVector * f + rot.RightVector * r
        end
    end
    local up = 0
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then up = up + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then up = up - 1 end
    flyDir = flyDir + Vector3.new(0, up, 0)
    if flyDir.Magnitude > 0.1 then
        soulCFrame = soulCFrame + flyDir.Unit * (speeds * 30) * 0.1
    end
    Camera.CFrame = soulCFrame * rot
end))

local function applyHitbox(char, index, isNPC)
    if index == 1 then return end
    if not char or not char.Parent then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if not hrp then return end
    local dict = isNPC and originalNPCSizes or originalPlayerSizes
    if not dict[char] then
        dict[char] = {Size = hrp.Size, Transparency = hrp.Transparency,
                      Color = hrp.Color, Material = hrp.Material, CanCollide = hrp.CanCollide}
    end
    local o = dict[char]
    hrp.Size = o.Size * hitboxSizes[index]
    hrp.Transparency = index >= 6 and 0.8 or 0.7
    hrp.Color = isNPC and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 0)
    hrp.Material = Enum.Material.Neon
    hrp.CanCollide = false
end

local function restoreHitbox(char, isNPC)
    if not char or not char.Parent then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    local dict = isNPC and originalNPCSizes or originalPlayerSizes
    local o = dict[char]
    if hrp and o then
        hrp.Size = o.Size; hrp.Transparency = o.Transparency
        hrp.Color = o.Color; hrp.Material = o.Material; hrp.CanCollide = o.CanCollide
        dict[char] = nil
    end
end

local function updatePlayers()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            if playerHitboxIndex > 1 then applyHitbox(plr.Character, playerHitboxIndex, false)
            else restoreHitbox(plr.Character, false) end
        end
    end
end

local function restoreAllHitboxes()
    for char in pairs(originalPlayerSizes) do restoreHitbox(char, false) end
    for char in pairs(originalNPCSizes) do restoreHitbox(char, true) end
end

task.spawn(function()
    while task.wait(2) do
        if not loopAlive() then break end
        if npcHitboxIndex <= 1 then continue end
        local myChar = LocalPlayer.Character
        local myHRP = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChildWhichIsA("BasePart"))
        if not myHRP then continue end
        local myPos = myHRP.Position
        for model in pairs(npcCache) do
            if not model or not model.Parent then
                npcCache[model] = nil
            else
                local hum = model:FindFirstChildOfClass("Humanoid")
                local nhrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if hum and hum.Health > 0 and nhrp and (nhrp.Position - myPos).Magnitude < 400 then
                    applyHitbox(model, npcHitboxIndex, true)
                end
            end
        end
    end
end)

RunService:BindToRenderStep("Aimbot", Enum.RenderPriority.Camera.Value + 1, function()
    if not loopAlive() or soulMode then return end
    if not Camera then return end

    if aimMode > 0 then
        local targetPart
        if aimMode == 2 then
            if aimLockTarget then
                targetPart = getTargetPart(aimLockTarget)
                local hum = aimLockTarget.Character and aimLockTarget.Character:FindFirstChild("Humanoid")
                if not targetPart or not hum or hum.Health <= 0 then
                    aimLockTarget = nil
                    aimMode = 0
                    AimBtn.Text = "随机自瞄: 关"
                    AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                    lastListKey = ""
                end
            else
                aimMode = 0
                AimBtn.Text = "随机自瞄: 关"
                AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
            end
        else
            targetPart = getClosestTarget()
        end

        if not targetPart then
            if isCameraLocked then
                isCameraLocked = false
                local c = LocalPlayer.Character
                local h = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart"))
                if h then
                    local g = h:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
                end
                resetCamera()
            end
            return
        end

        local char = LocalPlayer.Character
        local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
        if not hrp then return end
        isCameraLocked = true

        local tp = targetPart.Position
        local flat = Vector3.new((tp - hrp.Position).X, 0, (tp - hrp.Position).Z)
        if flat.Magnitude > 0.1 then
            local bg = hrp:FindFirstChild("AimbotGyro") or Instance.new("BodyGyro", hrp)
            bg.Name, bg.MaxTorque, bg.P = "AimbotGyro", Vector3.new(0, math.huge, 0), 1e5
            bg.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
        end

        Camera.CameraType = Enum.CameraType.Scriptable
        local d = (hrp.Position - tp).Magnitude
        local sd = d < 10 and (25 - d) or 12
        local sh = d < 10 and (15 - d / 2) or 5
        local camPos = hrp.Position - (tp - hrp.Position).Unit * sd + Vector3.new(0, sh, 0)
        local rp = RaycastParams.new()
        rp.FilterDescendantsInstances = {char, targetPart.Parent}
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local ray = workspace:Raycast(hrp.Position, camPos - hrp.Position, rp)
        if ray and d > 10 then camPos = ray.Position + ray.Normal * 0.5 end
        Camera.CFrame = CFrame.lookAt(camPos, tp)
        return
    end

    if isCameraLocked then
        isCameraLocked = false
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local g = char.HumanoidRootPart:FindFirstChild("AimbotGyro")
            if g then g:Destroy() end
        end
        resetCamera()
    end
end)

local function getListKey()
    local names = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
            table.insert(names, p.Name)
        end
    end
    table.sort(names)
    return tostring(aimLockTarget) .. "_" .. tostring(aimMode) .. "_" .. tostring(stickTarget) .. "_" .. tostring(stickMode) .. "_" .. tostring(watchTarget) .. "_" .. table.concat(names, ",")
end

local function stopWatching()
    if not watchTarget then return end
    watchTarget = nil
    if Camera then
        Camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            Camera.CameraSubject = char.Humanoid
        end
    end
end

local function startWatching(player)
    if not player or player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    if not Camera then return end

    if camState ~= 0 then
        camState = 0
        CamBtn.Text = "相机: 关闭"
        CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
        CamDistSliderContainer.Visible = false
    end
    if soulMode then
        toggleSoul(false)
        SoulBtn.Text = "出窍: 关"
        SoulBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 60)
    end
    if aimMode > 0 then
        aimMode = 0
        aimLockTarget = nil
        AimBtn.Text = "随机自瞄: 关"
        AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
        end
    end
    isCameraLocked = false

    watchTarget = player
    Camera.CameraType = Enum.CameraType.Custom
    Camera.CameraSubject = hum
end

refreshList = function(force)
    if watchTarget then
        local wc = watchTarget.Character
        local wh = wc and wc:FindFirstChildOfClass("Humanoid")
        if not wh or wh.Health <= 0 then
            stopWatching()
        end
    end
    if stickMode and stickTarget then
        local sc = stickTarget.Character
        local sh = sc and sc:FindFirstChildOfClass("Humanoid")
        if not sh or sh.Health <= 0 then
            forceStopStick()
            stickTarget = nil
        end
    end
    if aimMode == 2 and aimLockTarget then
        local ac = aimLockTarget.Character
        local ah = ac and ac:FindFirstChildOfClass("Humanoid")
        if not ah or ah.Health <= 0 then
            aimMode = 0
            aimLockTarget = nil
            AimBtn.Text = "随机自瞄: 关"
            AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        end
    end

    local key = getListKey()
    if not force and key == lastListKey then return end
    lastListKey = key
    for _, c in pairs(ScrollingFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local count = 0
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
            count = count + 1
            local f = Instance.new("Frame", ScrollingFrame)
            f.Size, f.BackgroundColor3, f.LayoutOrder, f.ZIndex =
                UDim2.new(1, -4, 0, 30), Color3.fromRGB(30, 33, 40), count, 152
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)

            local n = Instance.new("TextLabel", f)
            n.Size, n.BackgroundTransparency, n.Text, n.TextColor3, n.Font, n.TextSize, n.Position, n.ZIndex =
                UDim2.new(1, -122, 1, 0), 1, p.Name,
                (aimMode == 2 and aimLockTarget == p) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255),
                Enum.Font.SourceSansBold, 13, UDim2.new(0, 4, 0, 0), 153
            n.TextXAlignment = Enum.TextXAlignment.Left
            n.TextTruncate = Enum.TextTruncate.AtEnd

            local lk = Instance.new("TextButton", f)
            local isAimLocked = (aimMode == 2 and aimLockTarget == p)
            lk.Size, lk.Position, lk.BackgroundColor3, lk.Text, lk.TextColor3, lk.Font, lk.TextSize, lk.ZIndex =
                UDim2.new(0, 28, 0, 22), UDim2.new(1, -116, 0, 4),
                isAimLocked and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(60, 90, 150),
                isAimLocked and "解" or "锁",
                Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", lk).CornerRadius = UDim.new(0, 4)
            lk.MouseButton1Click:Connect(function()
                if aimMode == 2 and aimLockTarget == p then
                    aimMode = 0
                    aimLockTarget = nil
                    AimBtn.Text = "随机自瞄: 关"
                    AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
                    end
                    if not flying and not soulMode and camState == 0 and not watchTarget then resetCamera() end
                else
                    local char = LocalPlayer.Character
                    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
                    if soulMode then forceStopSoul() end
                    if watchTarget then stopWatching() end
                    aimMode = 2
                    aimLockTarget = p
                    AimBtn.Text = "随机自瞄: 关"
                    AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                end
                refreshList(true)
            end)

            local w = Instance.new("TextButton", f)
            w.Size, w.Position, w.BackgroundColor3, w.Text, w.TextColor3, w.Font, w.TextSize, w.ZIndex =
                UDim2.new(0, 28, 0, 22), UDim2.new(1, -87, 0, 4),
                (watchTarget == p) and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(50, 120, 160),
                (watchTarget == p) and "停" or "视",
                Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", w).CornerRadius = UDim.new(0, 4)
            w.MouseButton1Click:Connect(function()
                if watchTarget == p then
                    stopWatching()
                else
                    startWatching(p)
                end
                refreshList(true)
            end)

            local s = Instance.new("TextButton", f)
            local isFollowing = (stickMode and stickTarget == p)
            s.Size, s.Position, s.BackgroundColor3, s.Text, s.TextColor3, s.Font, s.TextSize, s.ZIndex =
                UDim2.new(0, 28, 0, 22), UDim2.new(1, -58, 0, 4),
                isFollowing and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(180, 120, 40),
                isFollowing and "停" or "跟",
                Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", s).CornerRadius = UDim.new(0, 4)
            s.MouseButton1Click:Connect(function()
                if stickMode and stickTarget == p then
                    forceStopStick()
                    refreshList(true)
                    return
                end
                local char = LocalPlayer.Character
                if not char or not char:FindFirstChild("HumanoidRootPart") then return end
                forceStopFly(); forceStopAirwalk()
                if soulMode then forceStopSoul() end
                stickTarget = p
                stickMode = true
                FollowCtrlFrame.Visible = true
                refreshList(true)
            end)

            local t = Instance.new("TextButton", f)
            t.Size, t.Position, t.BackgroundColor3, t.Text, t.TextColor3, t.Font, t.TextSize, t.ZIndex =
                UDim2.new(0, 28, 0, 22), UDim2.new(1, -29, 0, 4),
                Color3.fromRGB(180, 120, 40), "传", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", t).CornerRadius = UDim.new(0, 4)
            t.MouseButton1Click:Connect(function()
                local myChar = LocalPlayer.Character
                if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
                if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    forceStopFly()
                    myChar.HumanoidRootPart.CFrame = p.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 4)
                    -- 传送后清掉防撞锁，避免把玩家拉回去
                    if antiKB_BodyPosition then
                        antiKB_BodyPosition:Destroy()
                        antiKB_BodyPosition = nil
                        antiKB_ActiveUntil = 0
                    end
                    if t.Parent then
                        t.Text = "OK"
                        task.wait(1)
                        if t.Parent then t.Text = "传" end
                    end
                end
            end)
        end
    end
    ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

task.spawn(function()
    while task.wait(1.5) do
        if not loopAlive() then break end
        if ListFrame.Visible then refreshList() end
    end
end)

task.spawn(function()
    while task.wait(1) do
        if not loopAlive() then break end
        if watchTarget then
            local ch = watchTarget.Character
            local h = ch and ch:FindFirstChildOfClass("Humanoid")
            if not h or h.Health <= 0 then
                stopWatching()
                if ListFrame.Visible then refreshList(true) end
            end
        end
        if stickMode and stickTarget then
            local sc = stickTarget.Character
            local sh = sc and sc:FindFirstChildOfClass("Humanoid")
            if not sh or sh.Health <= 0 then
                forceStopStick()
                stickTarget = nil
                if ListFrame.Visible then refreshList(true) end
            end
        end
        if aimMode == 2 and aimLockTarget then
            local ac = aimLockTarget.Character
            local ah = ac and ac:FindFirstChildOfClass("Humanoid")
            if not ah or ah.Health <= 0 then
                aimMode = 0
                aimLockTarget = nil
                AimBtn.Text = "随机自瞄: 关"
                AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                if ListFrame.Visible then refreshList(true) end
            end
        end
    end
end)

-- 防撞：检测被撞 → BodyPosition 短暂锁位置
track(RunService.Heartbeat:Connect(function(dt)
    if not loopAlive() or not antiKnockback then
        if antiKB_BodyPosition then
            antiKB_BodyPosition:Destroy()
            antiKB_BodyPosition = nil
            antiKB_ActiveUntil = 0
        end
        return
    end
    -- 特殊状态跳过（飞行/出窍/跟随/坐载具时不需要防撞）
    if flying or soulMode or stickMode then
        if antiKB_BodyPosition then
            antiKB_BodyPosition:Destroy()
            antiKB_BodyPosition = nil
            antiKB_ActiveUntil = 0
        end
        return
    end
    local char = LocalPlayer.Character
    if not char then
        if antiKB_BodyPosition then antiKB_BodyPosition:Destroy(); antiKB_BodyPosition = nil; antiKB_ActiveUntil = 0 end
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 or hum.SeatPart then
        if antiKB_BodyPosition then antiKB_BodyPosition:Destroy(); antiKB_BodyPosition = nil; antiKB_ActiveUntil = 0 end
        return
    end

    local now = os.clock()
    local v = hrp.AssemblyLinearVelocity
    local hv = Vector3.new(v.X, 0, v.Z)
    local moveDir = hum.MoveDirection
    local triggered = false

    if moveDir.Magnitude < 0.1 then
        if hv.Magnitude > 2 then triggered = true end
    else
        local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
        if flat.Magnitude > 0.01 then
            flat = flat.Unit
            local spd = hv.Magnitude
            if spd > hum.WalkSpeed + 3 then
                triggered = true
            elseif spd > 0.5 then
                -- 速度方向和输入方向偏差大（被侧推）
                local dot = hv.Unit:Dot(flat)
                if dot < 0.3 then triggered = true end
            end
        end
    end

    if triggered then
        antiKB_ActiveUntil = now + 0.3
        antiKB_TargetPos = Vector3.new(hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
        if not antiKB_BodyPosition or antiKB_BodyPosition.Parent ~= hrp then
            if antiKB_BodyPosition then antiKB_BodyPosition:Destroy() end
            antiKB_BodyPosition = Instance.new("BodyPosition")
            antiKB_BodyPosition.MaxForce = Vector3.new(9e9, 0, 9e9)
            antiKB_BodyPosition.P = 5e4
            antiKB_BodyPosition.D = 5e3
            antiKB_BodyPosition.Position = antiKB_TargetPos
            antiKB_BodyPosition.Parent = hrp
        end
    end

    if antiKB_BodyPosition then
        if now > antiKB_ActiveUntil then
            antiKB_BodyPosition:Destroy()
            antiKB_BodyPosition = nil
        else
            if moveDir.Magnitude > 0.1 then
                local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
                if flat.Magnitude > 0.01 then
                    antiKB_TargetPos = antiKB_TargetPos + flat.Unit * hum.WalkSpeed * dt
                end
            end
            antiKB_TargetPos = Vector3.new(antiKB_TargetPos.X, hrp.Position.Y, antiKB_TargetPos.Z)
            antiKB_BodyPosition.Position = antiKB_TargetPos
        end
    end
end))

-- 穿墙 Stepped：角色 + 载具
track(RunService.Stepped:Connect(function()
    if not loopAlive() then return end
    if not noclip then
        if noclipSeat then restoreVehicleCollides() end
        return
    end
    local char = LocalPlayer.Character
    if not char then
        if noclipSeat then restoreVehicleCollides() end
        return
    end
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end
            if v.CanCollide then v.CanCollide = false end
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if seat then
        applyNoclipToVehicle(seat, char)
    elseif noclipSeat then
        restoreVehicleCollides()
    end
end))

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if not hrp then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if not Camera then return end

    if stickMode and stickTarget and stickTarget.Character then
        local thrp = getHRP(stickTarget.Character)
        if thrp then
            hrp.CFrame = thrp.CFrame * CFrame.new(followOffsetRight, followOffsetUp, -followOffsetForward)
            hrp.Velocity = Vector3.zero
            hum.PlatformStand = true
            return
        end
    end

    if not flying then return end

    soundCheckCounter = soundCheckCounter + 1
    if soundCheckCounter >= 30 then
        soundCheckCounter = 0
        muteCharacterSounds()
    end

    if not bodyVelocity or not bodyVelocity.Parent or not bodyGyro or not bodyGyro.Parent then
        startPhysics(); return
    end
    if hum.SeatPart == nil and flyAttach ~= char:FindFirstChild("UpperTorso") and flyAttach ~= char:FindFirstChild("Torso") and flyAttach ~= hrp then
        startPhysics()
        return
    end
    if hum.SeatPart and flyAttach ~= hum.SeatPart.AssemblyRootPart and flyAttach ~= hum.SeatPart then
        startPhysics()
        return
    end

    if aimMode > 0 and not hum.SeatPart then
        bodyGyro.MaxTorque = Vector3.zero
    else
        bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    end

    local moveDir = hum.MoveDirection
    local up = 0
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then up = up + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then up = up - 1 end

    local fullLook = Camera.CFrame.LookVector
    local fullRight = Camera.CFrame.RightVector
    local flatLook = Vector3.new(fullLook.X, 0, fullLook.Z)
    if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
    flatLook = flatLook.Unit
    local flatRight = Vector3.new(fullRight.X, 0, fullRight.Z)
    if flatRight.Magnitude < 0.01 then flatRight = Vector3.new(1, 0, 0) end
    flatRight = flatRight.Unit

    local flyDir = Vector3.zero
    if moveDir.Magnitude > 0.1 then
        local fwd = moveDir:Dot(flatLook)
        local rgt = moveDir:Dot(flatRight)
        flyDir = fullLook * fwd + fullRight * rgt
    end
    flyDir = flyDir + Vector3.new(0, up, 0)
    bodyVelocity.Velocity = flyDir.Magnitude > 0.1 and (flyDir.Unit * (speeds * 50)) or Vector3.new(0, 0.1, 0)

    if hum.SeatPart then
        local currentPos = flyAttach.Position
        bodyGyro.CFrame = CFrame.new(currentPos, currentPos + flatLook)
    else
        local flat = Vector3.new(fullLook.X, 0, fullLook.Z)
        if flat.Magnitude > 0.01 and flyAttach and flyAttach.Parent then
            bodyGyro.CFrame = CFrame.new(flyAttach.Position, flyAttach.Position + flat.Unit)
        end
    end
end))

local function zeroPrompt(prompt)
    if prompt and prompt:IsA("ProximityPrompt") and prompt.HoldDuration > 0 then
        prompt.HoldDuration = 0
    end
end

for _, obj in pairs(workspace:GetDescendants()) do
    if obj:IsA("ProximityPrompt") then zeroPrompt(obj) end
end

track(workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("ProximityPrompt") then zeroPrompt(obj) end
end))

local ITEM_ESP_MAX_DIST = 1000

local function tryAddItemEsp(obj)
    if not itemEspEnabled then return end
    if not (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")) then return end
    local part = obj.Parent
    if part and part:IsA("Attachment") then part = part.Parent end
    if not part or not part:IsA("BasePart") then return end
    if itemEspCache[obj] then return end

    local objName = obj.Name
    if obj:IsA("ProximityPrompt") and obj.ObjectText ~= "" then
        objName = obj.ObjectText
    elseif obj:IsA("ProximityPrompt") and obj.ActionText ~= "" then
        objName = obj.ActionText
    end

    local chineseName = translateName(objName)
    local lowerName = string.lower(objName)
    local color = Color3.fromRGB(0, 200, 255)
    if string.find(lowerName, "door") or string.find(lowerName, "exit") then
        color = Color3.fromRGB(50, 255, 50)
    elseif string.find(lowerName, "drawer") or string.find(lowerName, "cabinet") or string.find(lowerName, "chest") or string.find(lowerName, "locker") or string.find(lowerName, "knob") then
        color = Color3.fromRGB(255, 150, 50)
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ItemESP_Billboard"
    billboard.Size = UDim2.new(0, 120, 0, 24)
    billboard.StudsOffset = Vector3.new(0, 1.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = ITEM_ESP_MAX_DIST
    billboard.Adornee = part
    billboard.Parent = part

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 1, 0)
    text.BackgroundTransparency = 1
    text.TextColor3 = color
    text.Font = Enum.Font.GothamBold
    text.TextSize = 14
    text.TextStrokeTransparency = 0.5
    text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    text.Text = chineseName
    text.Parent = billboard

    itemEspCache[obj] = {billboard = billboard, part = part, text = text, name = chineseName}
end

track(workspace.DescendantAdded:Connect(function(obj)
    if itemEspEnabled and (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")) then
        tryAddItemEsp(obj)
    end
end))

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() or not itemEspEnabled then return end
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    local myPos = myHRP.Position
    for obj, data in pairs(itemEspCache) do
        if not obj.Parent or not data.part.Parent then
            if data.billboard then data.billboard:Destroy() end
            itemEspCache[obj] = nil
        else
            local dist = (data.part.Position - myPos).Magnitude
            if dist < ITEM_ESP_MAX_DIST then
                data.text.Text = data.name .. " [" .. math.floor(dist) .. "m]"
            end
        end
    end
end))

local originalLighting = {}
local darkRemoveOn = false
local hiddenEffects = setmetatable({}, {__mode = "k"})
local hiddenDarkParts = setmetatable({}, {__mode = "k"})
local forceConn = nil
local lightingCaptured = false

local function captureLighting()
    if lightingCaptured then return end
    lightingCaptured = true
    originalLighting = {
        FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ExposureCompensation = Lighting.ExposureCompensation,
        ShadowSoftness = Lighting.ShadowSoftness,
    }
end

local function scanAndHideDarkParts()
    local myChar = LocalPlayer.Character
    for _, obj in pairs(workspace:GetDescendants()) do
        if not loopAlive() then break end
        if obj:IsA("BasePart") then
            if myChar and obj:IsDescendantOf(myChar) then continue end
            if obj.Parent and obj.Parent:FindFirstChildOfClass("Humanoid") then continue end
            local c = obj.Color
            if c.R < 0.08 and c.G < 0.08 and c.B < 0.08
                and (obj.Size.X > 80 or obj.Size.Y > 80 or obj.Size.Z > 80)
                and obj.Transparency >= 0.3 and obj.Transparency <= 0.99 then
                if hiddenDarkParts[obj] == nil then hiddenDarkParts[obj] = obj.Transparency end
                obj.Transparency = 1
            end
        end
    end
end

local function restoreDarkParts()
    for part, t in pairs(hiddenDarkParts) do
        if part and part.Parent then pcall(function() part.Transparency = t end) end
    end
    hiddenDarkParts = setmetatable({}, {__mode = "k"})
end

local function applyDarkOnce()
    Lighting.GlobalShadows = false
    Lighting.FogStart = 0
    Lighting.FogEnd = 1e9
    pcall(function() Lighting.ShadowSoftness = 0 end)
    for _, obj in pairs(Lighting:GetChildren()) do
        if obj:IsA("Atmosphere") then
            if not hiddenEffects[obj] then
                hiddenEffects[obj] = {Density = obj.Density, Haze = obj.Haze, Glare = obj.Glare, Offset = obj.Offset}
            end
            obj.Density, obj.Haze, obj.Glare, obj.Offset = 0, 0, 0, 0
        elseif obj:IsA("PostEffect") then
            if not hiddenEffects[obj] then hiddenEffects[obj] = {Enabled = obj.Enabled} end
            obj.Enabled = false
        end
    end
end

local function startForceOverride()
    if forceConn then forceConn:Disconnect(); forceConn = nil end
    forceConn = RunService.Heartbeat:Connect(function()
        if not loopAlive() then
            if forceConn then forceConn:Disconnect(); forceConn = nil end
            return
        end
        Lighting.GlobalShadows = false
        Lighting.FogStart = 0
        Lighting.FogEnd = 1e9
        for _, obj in pairs(Lighting:GetChildren()) do
            if obj:IsA("Atmosphere") then
                if not hiddenEffects[obj] then
                    hiddenEffects[obj] = {Density = obj.Density, Haze = obj.Haze, Glare = obj.Glare, Offset = obj.Offset}
                end
                obj.Density, obj.Haze, obj.Glare, obj.Offset = 0, 0, 0, 0
            elseif obj:IsA("PostEffect") then
                if not hiddenEffects[obj] then hiddenEffects[obj] = {Enabled = obj.Enabled} end
                obj.Enabled = false
            end
        end
    end)
end

local function stopForceOverride()
    if forceConn then forceConn:Disconnect(); forceConn = nil end
end

local function restoreLighting()
    stopForceOverride()
    for k, v in pairs(originalLighting) do pcall(function() Lighting[k] = v end) end
    for obj, data in pairs(hiddenEffects) do
        if obj and obj.Parent then
            for k, v in pairs(data) do pcall(function() obj[k] = v end) end
        end
    end
    hiddenEffects = setmetatable({}, {__mode = "k"})
end

local espEnabled = false
local playerHighlights = {}
local npcHighlights = {}
local espFailed = setmetatable({}, {__mode = "k"})

local function updatePlayerESP()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if espEnabled and p.Character and p.Character.Parent then
                if not playerHighlights[p] and not espFailed[p] then
                    local ok = pcall(function()
                        local hl = Instance.new("Highlight")
                        hl.Name = "ESP_Highlight"
                        hl.Adornee = p.Character
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.FillColor = Color3.fromRGB(255, 255, 0)
                        hl.OutlineColor = Color3.new(1, 1, 1)
                        hl.FillTransparency = 0.5
                        hl.Parent = CoreGui
                        playerHighlights[p] = hl
                    end)
                    if not ok then espFailed[p] = true end
                elseif playerHighlights[p] then
                    playerHighlights[p].Adornee = p.Character
                end
            elseif playerHighlights[p] then
                pcall(function() playerHighlights[p]:Destroy() end)
                playerHighlights[p] = nil
            end
        end
    end
end

task.spawn(function()
    while task.wait(3) do
        if not loopAlive() then break end
        if not espEnabled then continue end
        for model, hl in pairs(npcHighlights) do
            if not model or not model.Parent or not model:FindFirstChild("Humanoid") or model.Humanoid.Health <= 0 then
                pcall(function() hl:Destroy() end)
                npcHighlights[model] = nil
            end
        end
        for model in pairs(npcCache) do
            if not loopAlive() then break end
            if not model or not model.Parent then
                npcCache[model] = nil
            elseif model ~= LocalPlayer.Character and not npcHighlights[model] and not espFailed[model] then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local ok = pcall(function()
                        local hl = Instance.new("Highlight")
                        hl.Name = "ESP_Highlight"
                        hl.Adornee = model
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.FillColor = Color3.fromRGB(255, 50, 50)
                        hl.OutlineColor = Color3.new(1, 1, 1)
                        hl.FillTransparency = 0.5
                        hl.Parent = CoreGui
                        npcHighlights[model] = hl
                    end)
                    if not ok then espFailed[model] = true end
                end
            end
        end
    end
end)

track(Players.PlayerAdded:Connect(function(p)
    task.wait(1)
    if not loopAlive() then return end
    updatePlayerESP()
    track(p.CharacterAdded:Connect(function()
        task.wait(1)
        if not loopAlive() then return end
        updatePlayerESP()
    end))
end))

track(Players.PlayerRemoving:Connect(function(p)
    if playerHighlights[p] then
        pcall(function() playerHighlights[p]:Destroy() end)
        playerHighlights[p] = nil
    end
    espFailed[p] = nil
    if aimLockTarget == p then
        aimMode = 0
        aimLockTarget = nil
        AimBtn.Text = "随机自瞄: 关"
        AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        lastListKey = ""
    end
    if stickTarget == p then
        forceStopStick()
        stickTarget = nil
    end
    if watchTarget == p then
        stopWatching()
    end
end))

FlyBtn.MouseButton1Click:Connect(function()
    if not flying then
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        if startPhysics() then
            flying = true
            FlyBtn.Text = "飞行中"
            FlyBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            if currentTab == 1 then SpeedSliderContainer.Visible = true end
        else
            -- 副驾提示
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.SeatPart then
                FlyBtn.Text = "副驾不可飞"
                task.wait(1.2)
                if FlyBtn.Parent and FlyBtn.Text == "副驾不可飞" then
                    FlyBtn.Text = "开启飞行"
                end
            end
        end
    else
        forceStopFly()
        resetCamera()
    end
end)

NoclipBtn.MouseButton1Click:Connect(function()
    noclip = not noclip
    NoclipBtn.Text = noclip and "穿墙中" or "穿墙模式"
    NoclipBtn.BackgroundColor3 = noclip and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(80, 80, 90)
    local char = LocalPlayer.Character
    if not char then return end
    if noclip then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end
                v.CanCollide = false
            end
        end
    else
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then v.CanCollide = originalCollides[v] ~= false end
        end
        originalCollides = setmetatable({}, {__mode = "k"})
        restoreVehicleCollides()
    end
end)

AimBtn.MouseButton1Click:Connect(function()
    if aimMode == 1 then
        aimMode = 0
        AimBtn.Text = "随机自瞄: 关"
        AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
        end
        if not flying and not soulMode and camState == 0 and not watchTarget then resetCamera() end
    else
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        if soulMode then forceStopSoul() end
        if watchTarget then stopWatching() end
        aimMode = 1
        aimLockTarget = nil
        AimBtn.Text = "随机自瞄: 硬"
        AimBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

PlayerHitboxBtn.MouseButton1Click:Connect(function()
    playerHitboxIndex = (playerHitboxIndex % #hitboxSizes) + 1
    PlayerHitboxBtn.Text = "玩家: " .. hitboxNames[playerHitboxIndex]
    updatePlayers()
end)

NPCHitboxBtn.MouseButton1Click:Connect(function()
    npcHitboxIndex = (npcHitboxIndex % #hitboxSizes) + 1
    NPCHitboxBtn.Text = "NPC: " .. hitboxNames[npcHitboxIndex]
    if npcHitboxIndex == 1 then
        for char in pairs(originalNPCSizes) do restoreHitbox(char, true) end
    end
end)

OpenListBtn.MouseButton1Click:Connect(function()
    ListFrame.Visible = not ListFrame.Visible
    if ListFrame.Visible then refreshList(true) end
end)

CloseListBtn.MouseButton1Click:Connect(function()
    ListFrame.Visible = false
end)

AirWalkBtn.MouseButton1Click:Connect(function()
    if airwalkEnabled then forceStopAirwalk(); return end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    airwalkEnabled = true
    forceStopFly(); forceStopStick(); resetCamera()
    local hrp = char.HumanoidRootPart
    airwalkPlate = Instance.new("Part")
    airwalkPlate.Name = "AirWalkPlate_V4"
    airwalkPlate.Size = Vector3.new(1000, 2, 1000)
    airwalkPlate.Position = Vector3.new(hrp.Position.X, hrp.Position.Y - 3.2, hrp.Position.Z)
    airwalkPlate.Anchored = true
    airwalkPlate.CanCollide = true
    airwalkPlate.Transparency = 1
    airwalkPlate.Material = Enum.Material.SmoothPlastic
    airwalkPlate.Parent = workspace
    AirWalkBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
    AirWalkBtn.Text = "行走开启"
end)

CollectBtn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart
    CollectBtn.Text = "远程爆破中..."
    task.spawn(function()
        local counts = 0
        for _, v in pairs(workspace:GetDescendants()) do
            if not loopAlive() or not hrp.Parent then break end
            if v:IsA("TouchTransmitter") then
                if v.Parent and v.Parent:IsA("BasePart") then
                    pcall(function()
                        firetouchinterest(hrp, v.Parent, 0)
                        task.wait(0.005)
                        firetouchinterest(hrp, v.Parent, 1)
                    end)
                    counts = counts + 1
                end
            end
        end
        CollectBtn.Text = "远程开门中..."
        for _, v in pairs(workspace:GetDescendants()) do
            if not loopAlive() then break end
            if v:IsA("ProximityPrompt") then
                pcall(function()
                    if fireproximityprompt then fireproximityprompt(v)
                    else v.HoldDuration = 0; v:InputHoldBegin(); task.wait(0.01); v:InputHoldEnd() end
                end)
                counts = counts + 1
                task.wait(0.01)
            elseif v:IsA("ClickDetector") then
                pcall(function() if fireclickdetector then fireclickdetector(v) end end)
                counts = counts + 1
                task.wait(0.01)
            end
        end
        if not loopAlive() or not CollectBtn.Parent then return end
        CollectBtn.Text = "触发: " .. counts .. "个"
        task.wait(1.5)
        if CollectBtn.Parent then CollectBtn.Text = "全图开箱" end
    end)
end)

ItemEspBtn.MouseButton1Click:Connect(function()
    itemEspEnabled = not itemEspEnabled
    ItemEspBtn.Text = itemEspEnabled and "物透: 开" or "物透: 关"
    ItemEspBtn.BackgroundColor3 = itemEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(40, 140, 140)
    if itemEspEnabled then
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") then tryAddItemEsp(obj) end
        end
    else
        for obj, data in pairs(itemEspCache) do
            if data.billboard then data.billboard:Destroy() end
        end
        itemEspCache = {}
    end
end)

SoulBtn.MouseButton1Click:Connect(function()
    if not soulMode and not Camera then return end
    if not soulMode and watchTarget then stopWatching() end
    toggleSoul(not soulMode)
    SoulBtn.Text = soulMode and "出窍: 开" or "出窍: 关"
    SoulBtn.BackgroundColor3 = soulMode and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 80, 60)
    if soulMode then forceStopStick() end
end)

EspBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    EspBtn.Text = espEnabled and "人透: 开" or "人透: 关"
    EspBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 50, 120)
    updatePlayerESP()
    if not espEnabled then
        for _, hl in pairs(npcHighlights) do pcall(function() hl:Destroy() end) end
        npcHighlights = {}
    end
end)

DarkBtn.MouseButton1Click:Connect(function()
    darkRemoveOn = not darkRemoveOn
    DarkBtn.Text = darkRemoveOn and "去黑: 开" or "去黑: 关"
    DarkBtn.BackgroundColor3 = darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 120, 50)
    if darkRemoveOn then
        captureLighting()
        applyDarkOnce()
        scanAndHideDarkParts()
        startForceOverride()
    else
        stopForceOverride()
        restoreLighting()
        restoreDarkParts()
    end
end)

AntiCollideBtn.MouseButton1Click:Connect(function()
    antiKnockback = not antiKnockback
    AntiCollideBtn.Text = antiKnockback and "防撞: 开" or "防撞: 关"
    AntiCollideBtn.BackgroundColor3 = antiKnockback and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 100, 120)
    if not antiKnockback and antiKB_BodyPosition then
        antiKB_BodyPosition:Destroy()
        antiKB_BodyPosition = nil
        antiKB_ActiveUntil = 0
    end
end)

ToggleBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        ListFrame.Visible = false
        FollowCtrlFrame.Visible = false
        SliderContainer.Visible = false
        CamDistSliderContainer.Visible = false
        WalkSpeedSliderContainer.Visible = false
        JumpSliderContainer.Visible = false
        MainFrame.Size = UDim2.new(0, 190, 0, 30)
        ListFrame.Size = UDim2.new(0, 180, 0, 30)
    else
        showPage(currentTab)
        ListFrame.Size = UDim2.new(0, 180, 0, 280)
        if currentTab == 1 and flying then SpeedSliderContainer.Visible = true end
        if currentTab == 2 and camState == 1 then CamDistSliderContainer.Visible = true end
        if stickMode then FollowCtrlFrame.Visible = true end
    end
    TabBar.Visible = not isMinimized
    ContentFrame.Visible = not isMinimized
end)

track(LocalPlayer.CharacterAdded:Connect(function()
    stopPhysics()
    stopWatching()
    restoreVehicleCollides()
    if antiKB_BodyPosition then antiKB_BodyPosition:Destroy(); antiKB_BodyPosition = nil end
    antiKB_ActiveUntil = 0
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false
    restoreAllHitboxes()
    originalPlayerSizes = setmetatable({}, {__mode = "k"})
    originalNPCSizes = setmetatable({}, {__mode = "k"})
    noclip = false; aimMode = 0; aimLockTarget = nil; stickTarget = nil
    playerHitboxIndex = 1; npcHitboxIndex = 1
    soulMode = false; stickMode = false
    lastListKey = ""

    for obj, data in pairs(itemEspCache) do
        if data.billboard then data.billboard:Destroy() end
    end
    itemEspCache = {}
    if itemEspEnabled then
        ItemEspBtn.Text = "物透: 关"
        ItemEspBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 140)
        itemEspEnabled = false
    end

    currentFov = 70
    if Camera then Camera.FieldOfView = currentFov end
    FovBtn.Text = "视野(FOV): " .. currentFov
    SliderThumb.Position = UDim2.new(0.5, -10, 0.5, -10)

    flying = false
    SpeedSliderContainer.Visible = false
    FollowCtrlFrame.Visible = false
    showPage(1)
    ListFrame.Size = UDim2.new(0, 180, 0, 280)

    task.wait(1)
    if not loopAlive() then return end

    FlyBtn.Text = "开启飞行"
    FlyBtn.BackgroundColor3 = Color3.fromRGB(180, 160, 40)
    NoclipBtn.Text, NoclipBtn.BackgroundColor3 = "穿墙模式", Color3.fromRGB(80, 80, 90)
    AimBtn.Text, AimBtn.BackgroundColor3 = "随机自瞄: 关", Color3.fromRGB(60, 90, 150)
    PlayerHitboxBtn.Text, NPCHitboxBtn.Text = "玩家: 正常", "NPC: 正常"
    AirWalkBtn.Text, AirWalkBtn.BackgroundColor3 = "空中行走", Color3.fromRGB(40, 130, 150)
    SoulBtn.Text, SoulBtn.BackgroundColor3 = "出窍: 关", Color3.fromRGB(140, 80, 60)
    CollectBtn.Text = "全图开箱"
    EspBtn.Text = espEnabled and "人透: 开" or "人透: 关"
    EspBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 50, 120)
    DarkBtn.Text = darkRemoveOn and "去黑: 开" or "去黑: 关"
    DarkBtn.BackgroundColor3 = darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 120, 50)
    AntiCollideBtn.Text = antiKnockback and "防撞: 开" or "防撞: 关"
    AntiCollideBtn.BackgroundColor3 = antiKnockback and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 100, 120)

    local newChar = LocalPlayer.Character
    if newChar and newChar:FindFirstChildOfClass("Humanoid") then
        newChar.Humanoid.WalkSpeed = currentWalkSpeed
        newChar.Humanoid.JumpPower = currentJumpPower
        newChar.Humanoid.UseJumpPower = true
    end
    WalkSpeedBtn.Text = "速度: " .. currentWalkSpeed
    JumpBtn.Text = "跳高: " .. currentJumpPower

    camState = 0
    CamBtn.Text = "相机: 关闭"
    CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
    CamDistSliderContainer.Visible = false

    if darkRemoveOn then applyDarkOnce(); startForceOverride() end
    resetCamera()
    ListFrame.Visible = false
    LocalPlayer.CameraMaxZoomDistance = 128
    if espEnabled then updatePlayerESP() end
end))

local function closeAll()
    myLoop.Run = false
    for _, c in pairs(myConns) do pcall(function() c:Disconnect() end) end
    if _G.FlyGuiV4_Conns == myConns then _G.FlyGuiV4_Conns = nil end
    if _G.FlyGuiV4_Loop == myLoop then _G.FlyGuiV4_Loop = nil end
    myConns = {}

    if soulMode then toggleSoul(false) end
    stopWatching()
    restoreVehicleCollides()
    if antiKB_BodyPosition then antiKB_BodyPosition:Destroy(); antiKB_BodyPosition = nil end
    antiKB_ActiveUntil = 0
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false

    camState = 0
    CamBtn.Text = "相机: 关闭"
    CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
    CamDistSliderContainer.Visible = false

    stopForceOverride()
    stopPhysics()
    resetCamera()
    pcall(function() RunService:UnbindFromRenderStep("Aimbot") end)
    pcall(function() RunService:UnbindFromRenderStep("TakeoverCameraLoop") end)

    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local g = char.HumanoidRootPart:FindFirstChild("AimbotGyro")
        if g then g:Destroy() end
    end

    for _, v in pairs(playerHighlights) do pcall(function() v:Destroy() end) end
    playerHighlights = {}
    for _, v in pairs(npcHighlights) do pcall(function() v:Destroy() end) end
    npcHighlights = {}
    espFailed = setmetatable({}, {__mode = "k"})

    if darkRemoveOn then restoreLighting(); restoreDarkParts(); darkRemoveOn = false end

    for obj, data in pairs(itemEspCache) do
        if data.billboard then data.billboard:Destroy() end
    end
    itemEspCache = {}

    if char then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = originalCollides[v] ~= false
                v.LocalTransparencyModifier = 0
            end
            if v:IsA("Decal") then v.Transparency = 0 end
        end
        originalCollides = setmetatable({}, {__mode = "k"})
        local hum = char:FindFirstChild("Humanoid")
        if hum then
            hum.PlatformStand = false
            for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
                pcall(function() hum:SetStateEnabled(state, true) end)
            end
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
        end
        if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
        pcall(function() char:ScaleTo(1) end)
    end

    restoreAllHitboxes()

    noclip = false; flying = false; stickMode = false; soulMode = false; espEnabled = false; antiKnockback = false
    LocalPlayer.CameraMaxZoomDistance = 128
    if Camera then Camera.FieldOfView = 70 end
    if ScreenGui then ScreenGui:Destroy() end
end

CloseBtn.MouseButton1Click:Connect(function() pcall(closeAll) end)
