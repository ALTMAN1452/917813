local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

local UI = {}

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
local flyWasVehicle = false
local flyDiagnosticPending = false
local flyStartTime = 0
local flyStartPos = nil

local monsterKeywords = {"shark","monster","creature","beast","boss","enemy","dragon","zombie","animal","whale","fish","killer","megalodon","greatwhite"}
local excludeKeywords = {"door", "map", "baseplate", "building", "tree", "wall", "floor", "gate", "glass", "window", "terrain"}

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
    if not myLoop.Run then pcall(function() conn:Disconnect() end); return conn end
    table.insert(myConns, conn)
    return conn
end

local hasDrawing = false
pcall(function()
    if Drawing and Drawing.new then
        local t = Drawing.new("Line")
        if t then t:Remove(); hasDrawing = true end
    end
end)

pcall(function()
    for _, name in ipairs({"FlyGui_V4","TakeoverCamera"}) do
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

local function getTargetPart(player)
    if not player or not player.Character then return nil end
    local char = player.Character
    if not char.Parent then return nil end
    for _, name in ipairs({"Head","UpperTorso","Torso","HumanoidRootPart"}) do
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
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso") or char:FindFirstChildWhichIsA("BasePart")
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

local translateDict = {["door"]="门",["exit"]="出口",["knob"]="门把手",["keypad"]="密码锁",["drawer"]="抽屉",["cabinet"]="柜子",["chest"]="宝箱",["locker"]="储物柜",["seat"]="座位",["chair"]="椅子",["button"]="按钮",["switch"]="开关",["lever"]="拉杆",["valve"]="阀门",["key"]="钥匙",["coin"]="金币",["item"]="物品",["pickup"]="可拾取",["bed"]="床",["book"]="书",["fuse"]="保险丝",["battery"]="电池",["candle"]="蜡烛",["painting"]="画",["pull"]="拉绳",["push"]="推门",["open"]="打开"}
local function translateName(engName)
    local lowerName = string.lower(engName)
    if translateDict[lowerName] then return translateDict[lowerName] end
    for eng, chn in pairs(translateDict) do
        if string.find(lowerName, eng) then return chn end
    end
    return engName
end

local function hasMonsterKeyword(name)
    local lower = string.lower(name)
    for _, kw in ipairs(monsterKeywords) do
        if string.find(lower, kw) then return true end
    end
    return false
end

local function isExcluded(name)
    local lower = string.lower(name)
    for _, kw in ipairs(excludeKeywords) do
        if string.find(lower, kw) then return true end
    end
    return false
end

local npcCache = setmetatable({}, {__mode = "k"})

local function isMovableModel(model)
    if model.PrimaryPart and not model.PrimaryPart.Anchored then return true end
    for _, p in ipairs(model:GetChildren()) do
        if p:IsA("BasePart") and not p.Anchored then return true end
    end
    return false
end

local function registerNPC(model)
    if not model or not model:IsA("Model") then return end
    if model == LocalPlayer.Character then return end
    if Players:GetPlayerFromCharacter(model) then return end -- 绝对排除玩家
    
    if isExcluded(model.Name) then return end
    
    local isMonster = hasMonsterKeyword(model.Name)
    local magnitude = 0
    local ok, size = pcall(function() return model:GetExtentsSize() end)
    if ok and typeof(size) == "Vector3" then magnitude = size.Magnitude end
    
    -- 递归查找座位（FindFirstChildWhichIsA 第二个参数传 true）
    if model:FindFirstChildOfClass("Humanoid") or 
       isMonster or 
       model:FindFirstChildWhichIsA("VehicleSeat", true) or 
       model:FindFirstChildWhichIsA("Seat", true) then
        npcCache[model] = true
    elseif magnitude > 3 and isMovableModel(model) then
        npcCache[model] = true
    end
end

local function unregisterNPC(model)
    if model then npcCache[model] = nil end
end

task.spawn(function()
    task.wait(0.5)
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then registerNPC(obj) end
    end
end)

track(workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Model") then unregisterNPC(obj) end
end))

UI.ScreenGui = Instance.new("ScreenGui")
UI.ScreenGui.Name = "FlyGui_V4"
UI.ScreenGui.ResetOnSpawn = false
UI.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
UI.ScreenGui.DisplayOrder = 2147483647
UI.ScreenGui.IgnoreGuiInset = true
UI.ScreenGui.Parent = PlayerGui

UI.MainFrame = Instance.new("Frame")
UI.MainFrame.Size = UDim2.new(0, 190, 0, 164)
UI.MainFrame.Position = UDim2.new(0.15, 0, 0.1, 0)
UI.MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.MainFrame.BackgroundTransparency = 0.1
UI.MainFrame.BorderSizePixel = 0
UI.MainFrame.Active = true
UI.MainFrame.ZIndex = 101
UI.MainFrame.Parent = UI.ScreenGui
Instance.new("UICorner", UI.MainFrame).CornerRadius = UDim.new(0, 10)

local function addStroke(parent, color)
    local s = Instance.new("UIStroke", parent)
    s.Color = color
    s.Thickness = 1
    s.Transparency = 0.2
end
addStroke(UI.MainFrame, Color3.fromRGB(0, 200, 255))

UI.TopBar = Instance.new("Frame")
UI.TopBar.Size = UDim2.new(1, 0, 0, 30)
UI.TopBar.BackgroundTransparency = 1
UI.TopBar.Parent = UI.MainFrame

UI.CloseBtn = Instance.new("TextButton")
UI.CloseBtn.Size = UDim2.new(0, 22, 0, 22)
UI.CloseBtn.Position = UDim2.new(0, 8, 0, 4)
UI.CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
UI.CloseBtn.Text = "X"
UI.CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.CloseBtn.Font = Enum.Font.GothamBold
UI.CloseBtn.TextSize = 12
UI.CloseBtn.Parent = UI.TopBar
Instance.new("UICorner", UI.CloseBtn).CornerRadius = UDim.new(0, 5)

UI.ToggleBtn = Instance.new("TextButton")
UI.ToggleBtn.Size = UDim2.new(0, 22, 0, 22)
UI.ToggleBtn.Position = UDim2.new(0, 34, 0, 4)
UI.ToggleBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 200)
UI.ToggleBtn.Text = "T"
UI.ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.ToggleBtn.Font = Enum.Font.GothamBold
UI.ToggleBtn.TextSize = 12
UI.ToggleBtn.Parent = UI.TopBar
Instance.new("UICorner", UI.ToggleBtn).CornerRadius = UDim.new(0, 5)

UI.Title = Instance.new("TextLabel")
UI.Title.Size = UDim2.new(1, -65, 1, 0)
UI.Title.Position = UDim2.new(0, 65, 0, 0)
UI.Title.BackgroundTransparency = 1
UI.Title.Text = "喜瓜专用"
UI.Title.TextColor3 = Color3.fromRGB(0, 220, 255)
UI.Title.Font = Enum.Font.GothamBold
UI.Title.TextSize = 13
UI.Title.TextXAlignment = Enum.TextXAlignment.Left
UI.Title.Parent = UI.TopBar

local dragging, dragStart, startPos = false, nil, nil
UI.Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = UI.MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
track(UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local d = input.Position - dragStart
        UI.MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end))

UI.TabBar = Instance.new("Frame")
UI.TabBar.Size = UDim2.new(1, -16, 0, 24)
UI.TabBar.Position = UDim2.new(0, 8, 0, 30)
UI.TabBar.BackgroundTransparency = 1
UI.TabBar.Parent = UI.MainFrame

UI.BasicTab = Instance.new("TextButton")
UI.BasicTab.Size = UDim2.new(0.33, -2, 1, 0)
UI.BasicTab.Position = UDim2.new(0, 0, 0, 0)
UI.BasicTab.BackgroundColor3 = Color3.fromRGB(0, 120, 180)
UI.BasicTab.Text = "基础"
UI.BasicTab.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.BasicTab.Font = Enum.Font.GothamBold
UI.BasicTab.TextSize = 12
UI.BasicTab.Parent = UI.TabBar
Instance.new("UICorner", UI.BasicTab).CornerRadius = UDim.new(0, 6)

UI.DrawTab = Instance.new("TextButton")
UI.DrawTab.Size = UDim2.new(0.34, -2, 1, 0)
UI.DrawTab.Position = UDim2.new(0.33, 2, 0, 0)
UI.DrawTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40)
UI.DrawTab.Text = "绘制"
UI.DrawTab.TextColor3 = Color3.fromRGB(150, 160, 170)
UI.DrawTab.Font = Enum.Font.GothamBold
UI.DrawTab.TextSize = 12
UI.DrawTab.Parent = UI.TabBar
Instance.new("UICorner", UI.DrawTab).CornerRadius = UDim.new(0, 6)

UI.AdvTab = Instance.new("TextButton")
UI.AdvTab.Size = UDim2.new(0.33, -2, 1, 0)
UI.AdvTab.Position = UDim2.new(0.67, 2, 0, 0)
UI.AdvTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40)
UI.AdvTab.Text = "高级"
UI.AdvTab.TextColor3 = Color3.fromRGB(150, 160, 170)
UI.AdvTab.Font = Enum.Font.GothamBold
UI.AdvTab.TextSize = 12
UI.AdvTab.Parent = UI.TabBar
Instance.new("UICorner", UI.AdvTab).CornerRadius = UDim.new(0, 6)

UI.ContentFrame = Instance.new("Frame")
UI.ContentFrame.Size = UDim2.new(1, -16, 1, -64)
UI.ContentFrame.Position = UDim2.new(0, 8, 0, 60)
UI.ContentFrame.BackgroundTransparency = 1
UI.ContentFrame.Parent = UI.MainFrame

UI.PageBasic = Instance.new("Frame")
UI.PageBasic.Size = UDim2.new(1, 0, 1, 0)
UI.PageBasic.BackgroundTransparency = 1
UI.PageBasic.Parent = UI.ContentFrame

UI.PageDraw = Instance.new("Frame")
UI.PageDraw.Size = UDim2.new(1, 0, 1, 0)
UI.PageDraw.BackgroundTransparency = 1
UI.PageDraw.Visible = false
UI.PageDraw.Parent = UI.ContentFrame

UI.PageAdv = Instance.new("Frame")
UI.PageAdv.Size = UDim2.new(1, 0, 1, 0)
UI.PageAdv.BackgroundTransparency = 1
UI.PageAdv.Visible = false
UI.PageAdv.Parent = UI.ContentFrame

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

UI.AimBtn = createButton("Aim", "随机自瞄: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(60, 90, 150), UI.PageBasic, UDim2.new(0.5, -2, 0, 28))
UI.OpenListBtn = createButton("OpenList", "玩家列表", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(180, 60, 140), UI.PageBasic, UDim2.new(0.5, -2, 0, 28))
UI.FlyBtn = createButton("Fly", "开启飞行", UDim2.new(0, 0, 0, 32), Color3.fromRGB(180, 160, 40), UI.PageBasic, UDim2.new(0.5, -2, 0, 28))
UI.NoclipBtn = createButton("Noclip", "穿墙模式", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(80, 80, 90), UI.PageBasic, UDim2.new(0.5, -2, 0, 28))
UI.WalkSpeedBtn = createButton("WalkSpeed", "速度: 16", UDim2.new(0, 0, 0, 64), Color3.fromRGB(60, 100, 150), UI.PageBasic, UDim2.new(0.5, -2, 0, 28))
UI.JumpBtn = createButton("Jump", "跳高: 50", UDim2.new(0.5, 2, 0, 64), Color3.fromRGB(150, 100, 60), UI.PageBasic, UDim2.new(0.5, -2, 0, 28))

UI.EspBtn = createButton("Esp", "人透: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(140, 50, 120), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))
UI.ItemEspBtn = createButton("ItemEsp", "物透: 关", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(40, 140, 140), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))
UI.ModelEspBtn = createButton("ModelEsp", "模型透视: 关", UDim2.new(0, 0, 0, 32), Color3.fromRGB(200, 80, 100), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))
UI.RayBtn = createButton("Ray", "射线: 关", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(80, 140, 200), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))
UI.DarkBtn = createButton("DarkRemove", "去黑: 关", UDim2.new(0, 0, 0, 64), Color3.fromRGB(140, 120, 50), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))
UI.NoShadowBtn = createButton("NoShadow", "去阴影: 关", UDim2.new(0.5, 2, 0, 64), Color3.fromRGB(100, 100, 120), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))
UI.FovBtn = createButton("FovBtn", "视野(FOV): 70", UDim2.new(0, 0, 0, 96), Color3.fromRGB(60, 90, 150), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))
UI.CamBtn = createButton("CamBtn", "相机: 关闭", UDim2.new(0.5, 2, 0, 96), Color3.fromRGB(100, 50, 150), UI.PageDraw, UDim2.new(0.5, -2, 0, 28))

UI.CollectBtn = createButton("Collect", "全图开箱", UDim2.new(0, 0, 0, 0), Color3.fromRGB(180, 120, 40), UI.PageAdv, UDim2.new(0.5, -2, 0, 28))
UI.AirWalkBtn = createButton("AirWalk", "空中行走", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(40, 130, 150), UI.PageAdv, UDim2.new(0.5, -2, 0, 28))
UI.SoulBtn = createButton("Soul", "出窍: 关", UDim2.new(0, 0, 0, 32), Color3.fromRGB(140, 80, 60), UI.PageAdv, UDim2.new(0.5, -2, 0, 28))
UI.PlayerHitboxBtn = createButton("PlayerHitbox", "玩家: 1x", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(140, 140, 40), UI.PageAdv, UDim2.new(0.5, -2, 0, 28))
UI.NPCHitboxBtn = createButton("NPCHitbox", "NPC: 1x", UDim2.new(0, 0, 0, 64), Color3.fromRGB(160, 50, 50), UI.PageAdv, UDim2.new(0.5, -2, 0, 28))

local camState = 0
local camDistance = 12

-- 滑条UI：紧贴悬浮窗右侧
UI.SpeedSliderContainer = Instance.new("Frame")
UI.SpeedSliderContainer.Name = "SpeedSliderContainer"
UI.SpeedSliderContainer.Size = UDim2.new(0, 36, 0, 150)
UI.SpeedSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.SpeedSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.SpeedSliderContainer.BackgroundTransparency = 0.05
UI.SpeedSliderContainer.Visible = false
UI.SpeedSliderContainer.ZIndex = 105
UI.SpeedSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SpeedSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.SpeedSliderContainer, Color3.fromRGB(0, 200, 255))

UI.SpeedBg = Instance.new("Frame")
UI.SpeedBg.Size = UDim2.new(0, 6, 1, -20)
UI.SpeedBg.Position = UDim2.new(0.5, -3, 0, 10)
UI.SpeedBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
UI.SpeedBg.BorderSizePixel = 0
UI.SpeedBg.Active = true
UI.SpeedBg.ZIndex = 106
UI.SpeedBg.Parent = UI.SpeedSliderContainer
Instance.new("UICorner", UI.SpeedBg).CornerRadius = UDim.new(1, 0)

UI.SpeedThumb = Instance.new("TextButton")
UI.SpeedThumb.Size = UDim2.new(0, 20, 0, 20)
UI.SpeedThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.SpeedThumb.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
UI.SpeedThumb.Text = ""
UI.SpeedThumb.ZIndex = 107
UI.SpeedThumb.Parent = UI.SpeedSliderContainer
Instance.new("UICorner", UI.SpeedThumb).CornerRadius = UDim.new(1, 0)

-- 速度（下），跳高（上），紧贴悬浮窗
UI.WalkSpeedSliderContainer = Instance.new("Frame")
UI.WalkSpeedSliderContainer.Name = "WalkSpeedSliderContainer"
UI.WalkSpeedSliderContainer.Size = UDim2.new(0, 36, 0, 72)
UI.WalkSpeedSliderContainer.Position = UDim2.new(1, 45, 0, 88)
UI.WalkSpeedSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.WalkSpeedSliderContainer.BackgroundTransparency = 0.05
UI.WalkSpeedSliderContainer.Visible = false
UI.WalkSpeedSliderContainer.ZIndex = 130
UI.WalkSpeedSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.WalkSpeedSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.WalkSpeedSliderContainer, Color3.fromRGB(100, 180, 255))

UI.WalkSpeedBg = Instance.new("Frame")
UI.WalkSpeedBg.Size = UDim2.new(0, 6, 1, -10)
UI.WalkSpeedBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.WalkSpeedBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
UI.WalkSpeedBg.BorderSizePixel = 0
UI.WalkSpeedBg.Active = true
UI.WalkSpeedBg.ZIndex = 131
UI.WalkSpeedBg.Parent = UI.WalkSpeedSliderContainer
Instance.new("UICorner", UI.WalkSpeedBg).CornerRadius = UDim.new(1, 0)

UI.WalkSpeedThumb = Instance.new("TextButton")
UI.WalkSpeedThumb.Size = UDim2.new(0, 20, 0, 20)
UI.WalkSpeedThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.WalkSpeedThumb.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
UI.WalkSpeedThumb.Text = ""
UI.WalkSpeedThumb.ZIndex = 132
UI.WalkSpeedThumb.Parent = UI.WalkSpeedSliderContainer
Instance.new("UICorner", UI.WalkSpeedThumb).CornerRadius = UDim.new(1, 0)

UI.JumpSliderContainer = Instance.new("Frame")
UI.JumpSliderContainer.Name = "JumpSliderContainer"
UI.JumpSliderContainer.Size = UDim2.new(0, 36, 0, 72)
UI.JumpSliderContainer.Position = UDim2.new(1, 45, 0, 10)
UI.JumpSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.JumpSliderContainer.BackgroundTransparency = 0.05
UI.JumpSliderContainer.Visible = false
UI.JumpSliderContainer.ZIndex = 140
UI.JumpSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.JumpSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.JumpSliderContainer, Color3.fromRGB(255, 180, 100))

UI.JumpBg = Instance.new("Frame")
UI.JumpBg.Size = UDim2.new(0, 6, 1, -10)
UI.JumpBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.JumpBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
UI.JumpBg.BorderSizePixel = 0
UI.JumpBg.Active = true
UI.JumpBg.ZIndex = 141
UI.JumpBg.Parent = UI.JumpSliderContainer
Instance.new("UICorner", UI.JumpBg).CornerRadius = UDim.new(1, 0)

UI.JumpThumb = Instance.new("TextButton")
UI.JumpThumb.Size = UDim2.new(0, 20, 0, 20)
UI.JumpThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.JumpThumb.BackgroundColor3 = Color3.fromRGB(255, 180, 100)
UI.JumpThumb.Text = ""
UI.JumpThumb.ZIndex = 142
UI.JumpThumb.Parent = UI.JumpSliderContainer
Instance.new("UICorner", UI.JumpThumb).CornerRadius = UDim.new(1, 0)

-- 视野（下），相机（上），紧贴悬浮窗
UI.SliderContainer = Instance.new("Frame")
UI.SliderContainer.Name = "SliderContainer"
UI.SliderContainer.Size = UDim2.new(0, 36, 0, 72)
UI.SliderContainer.Position = UDim2.new(1, 5, 0, 88)
UI.SliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.SliderContainer.BackgroundTransparency = 0.05
UI.SliderContainer.Visible = false
UI.SliderContainer.ZIndex = 110
UI.SliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.SliderContainer, Color3.fromRGB(0, 220, 255))

UI.SliderBg = Instance.new("Frame")
UI.SliderBg.Size = UDim2.new(0, 6, 1, -10)
UI.SliderBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.SliderBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
UI.SliderBg.BorderSizePixel = 0
UI.SliderBg.Active = true
UI.SliderBg.ZIndex = 111
UI.SliderBg.Parent = UI.SliderContainer
Instance.new("UICorner", UI.SliderBg).CornerRadius = UDim.new(1, 0)

UI.SliderThumb = Instance.new("TextButton")
UI.SliderThumb.Size = UDim2.new(0, 20, 0, 20)
UI.SliderThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.SliderThumb.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
UI.SliderThumb.Text = ""
UI.SliderThumb.ZIndex = 112
UI.SliderThumb.Parent = UI.SliderContainer
Instance.new("UICorner", UI.SliderThumb).CornerRadius = UDim.new(1, 0)

UI.CamDistSliderContainer = Instance.new("Frame")
UI.CamDistSliderContainer.Name = "CamDistSliderContainer"
UI.CamDistSliderContainer.Size = UDim2.new(0, 36, 0, 72)
UI.CamDistSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.CamDistSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.CamDistSliderContainer.BackgroundTransparency = 0.05
UI.CamDistSliderContainer.Visible = false
UI.CamDistSliderContainer.ZIndex = 120
UI.CamDistSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.CamDistSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.CamDistSliderContainer, Color3.fromRGB(200, 100, 255))

UI.CamDistBg = Instance.new("Frame")
UI.CamDistBg.Size = UDim2.new(0, 6, 1, -10)
UI.CamDistBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.CamDistBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
UI.CamDistBg.BorderSizePixel = 0
UI.CamDistBg.Active = true
UI.CamDistBg.ZIndex = 121
UI.CamDistBg.Parent = UI.CamDistSliderContainer
Instance.new("UICorner", UI.CamDistBg).CornerRadius = UDim.new(1, 0)

UI.CamDistThumb = Instance.new("TextButton")
UI.CamDistThumb.Size = UDim2.new(0, 20, 0, 20)
UI.CamDistThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.CamDistThumb.BackgroundColor3 = Color3.fromRGB(200, 100, 255)
UI.CamDistThumb.Text = ""
UI.CamDistThumb.ZIndex = 122
UI.CamDistThumb.Parent = UI.CamDistSliderContainer
Instance.new("UICorner", UI.CamDistThumb).CornerRadius = UDim.new(1, 0)

local speeds = 1
local currentFov = 70
local currentTab = 1
local isMinimized = false

local function updateSpeedFromY(absoluteY)
    local bgAbsY = UI.SpeedBg.AbsolutePosition.Y
    local bgHeight = UI.SpeedBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    speeds = math.floor(10 - (relativeY * 9) + 0.5)
    UI.SpeedThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateWalkSpeedFromY(absoluteY)
    local bgAbsY = UI.WalkSpeedBg.AbsolutePosition.Y
    local bgHeight = UI.WalkSpeedBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    currentWalkSpeed = math.floor(200 - (relativeY * 184))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char.Humanoid.WalkSpeed = currentWalkSpeed
    end
    UI.WalkSpeedBtn.Text = "速度: " .. currentWalkSpeed
    UI.WalkSpeedThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateJumpFromY(absoluteY)
    local bgAbsY = UI.JumpBg.AbsolutePosition.Y
    local bgHeight = UI.JumpBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    currentJumpPower = math.floor(200 - (relativeY * 150))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char.Humanoid.JumpPower = currentJumpPower
        char.Humanoid.UseJumpPower = true
    end
    UI.JumpBtn.Text = "跳高: " .. currentJumpPower
    UI.JumpThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateFovFromY(absoluteY)
    local bgAbsY = UI.SliderBg.AbsolutePosition.Y
    local bgHeight = UI.SliderBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    currentFov = math.floor(120 - (relativeY * 70))
    if Camera then Camera.FieldOfView = currentFov end
    UI.FovBtn.Text = "视野(FOV): " .. currentFov
    UI.SliderThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateCamDistFromY(absoluteY)
    local bgAbsY = UI.CamDistBg.AbsolutePosition.Y
    local bgHeight = UI.CamDistBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    camDistance = math.floor(4 + ((1 - relativeY) * 36) + 0.5)
    UI.CamDistThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local mainDragInput = nil
local mainDragType = nil

track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local pos = input.Position
        if UI.SpeedSliderContainer.Visible then
            local a, s = UI.SpeedSliderContainer.AbsolutePosition, UI.SpeedSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then
                mainDragInput = input; mainDragType = "speed"; updateSpeedFromY(pos.Y); return
            end
        end
        if UI.WalkSpeedSliderContainer.Visible then
            local a, s = UI.WalkSpeedSliderContainer.AbsolutePosition, UI.WalkSpeedSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then
                mainDragInput = input; mainDragType = "walkspeed"; updateWalkSpeedFromY(pos.Y); return
            end
        end
        if UI.JumpSliderContainer.Visible then
            local a, s = UI.JumpSliderContainer.AbsolutePosition, UI.JumpSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then
                mainDragInput = input; mainDragType = "jump"; updateJumpFromY(pos.Y); return
            end
        end
        if UI.SliderContainer.Visible then
            local a, s = UI.SliderContainer.AbsolutePosition, UI.SliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then
                mainDragInput = input; mainDragType = "fov"; updateFovFromY(pos.Y); return
            end
        end
        if UI.CamDistSliderContainer.Visible then
            local a, s = UI.CamDistSliderContainer.AbsolutePosition, UI.CamDistSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then
                mainDragInput = input; mainDragType = "camdist"; updateCamDistFromY(pos.Y); return
            end
        end
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if input == mainDragInput then
        if mainDragType == "speed" then updateSpeedFromY(input.Position.Y)
        elseif mainDragType == "walkspeed" then updateWalkSpeedFromY(input.Position.Y)
        elseif mainDragType == "jump" then updateJumpFromY(input.Position.Y)
        elseif mainDragType == "fov" then updateFovFromY(input.Position.Y)
        elseif mainDragType == "camdist" then updateCamDistFromY(input.Position.Y) end
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input == mainDragInput then mainDragInput = nil; mainDragType = nil end
end))

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
            if v == head then isHeadPart = true
            elseif v.Parent and v.Parent:IsA("Accessory") then
                local aType = v.Parent.AccessoryType
                if aType == Enum.AccessoryType.Hat or aType == Enum.AccessoryType.Hair or aType == Enum.AccessoryType.Neck then
                    isHeadPart = true
                end
            end
            if isHeadPart then
                v.LocalTransparencyModifier = hide and 1 or 0
            elseif camState ~= 0 then
                v.LocalTransparencyModifier = 0
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
    if camState == 2 then updateHeadVisibility() end
    local focusPos = focus.Position
    local rot = CFrame.fromEulerAnglesYXZ(math.rad(camPitch), math.rad(camYaw), 0)
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
        Camera.CFrame = CFrame.new(focusPos + Vector3.new(0, 1.2, 0) + rot.LookVector * 1.5) * rot
    end
end))

local camDragInput = nil
track(UserInputService.InputBegan:Connect(function(input)
    if camState == 0 and not soulMode then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local vp = Camera and Camera.ViewportSize or Vector2.new(800, 600)
        local pos = input.Position
        if UI.SliderContainer.Visible then
            local p, s = UI.SliderContainer.AbsolutePosition, UI.SliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        if UI.CamDistSliderContainer.Visible then
            local p, s = UI.CamDistSliderContainer.AbsolutePosition, UI.CamDistSliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        if UI.WalkSpeedSliderContainer.Visible then
            local p, s = UI.WalkSpeedSliderContainer.AbsolutePosition, UI.WalkSpeedSliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        if UI.JumpSliderContainer.Visible then
            local p, s = UI.JumpSliderContainer.AbsolutePosition, UI.JumpSliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        if UI.SpeedSliderContainer.Visible then
            local p, s = UI.SpeedSliderContainer.AbsolutePosition, UI.SpeedSliderContainer.AbsoluteSize
            if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        end
        local p, s = UI.MainFrame.AbsolutePosition, UI.MainFrame.AbsoluteSize
        if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
        if pos.X > vp.X * 0.35 then camDragInput = input end
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if (camState == 0 and not soulMode) or not camDragInput or input ~= camDragInput then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Delta
        if soulMode then
            targetYaw = targetYaw - delta.X
            targetPitch = math.clamp(targetPitch - delta.Y, -60, 60)
        else
            camYaw = camYaw - delta.X
            camPitch = math.clamp(camPitch - delta.Y, -60, 60)
        end
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input == camDragInput then camDragInput = nil end
end))

local function showPage(idx)
    currentTab = idx
    UI.PageBasic.Visible = idx == 1
    UI.PageDraw.Visible = idx == 2
    UI.PageAdv.Visible = idx == 3
    UI.BasicTab.BackgroundColor3 = idx == 1 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    UI.BasicTab.TextColor3 = idx == 1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    UI.DrawTab.BackgroundColor3 = idx == 2 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    UI.DrawTab.TextColor3 = idx == 2 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    UI.AdvTab.BackgroundColor3 = idx == 3 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    UI.AdvTab.TextColor3 = idx == 3 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    
    if idx ~= 1 then
        UI.WalkSpeedSliderContainer.Visible = false
        UI.JumpSliderContainer.Visible = false
        UI.SpeedSliderContainer.Visible = false
    end
    if idx ~= 2 then
        UI.SliderContainer.Visible = false
        UI.CamDistSliderContainer.Visible = false
    end
    
    if idx == 2 then
        UI.MainFrame.Size = UDim2.new(0, 190, 0, 200)
    else
        UI.MainFrame.Size = UDim2.new(0, 190, 0, 164)
    end
end
UI.BasicTab.MouseButton1Click:Connect(function() showPage(1) end)
UI.DrawTab.MouseButton1Click:Connect(function() showPage(2) end)
UI.AdvTab.MouseButton1Click:Connect(function() showPage(3) end)

UI.FovBtn.MouseButton1Click:Connect(function()
    UI.SliderContainer.Visible = not UI.SliderContainer.Visible
end)

UI.WalkSpeedBtn.MouseButton1Click:Connect(function()
    UI.WalkSpeedSliderContainer.Visible = not UI.WalkSpeedSliderContainer.Visible
end)

UI.JumpBtn.MouseButton1Click:Connect(function()
    UI.JumpSliderContainer.Visible = not UI.JumpSliderContainer.Visible
end)

UI.CamBtn.MouseButton1Click:Connect(function()
    if watchTarget then
        watchTarget = nil
        if Camera then
            Camera.CameraType = Enum.CameraType.Custom
            local wc = LocalPlayer.Character
            if wc and wc:FindFirstChild("Humanoid") then Camera.CameraSubject = wc.Humanoid end
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
        UI.CamBtn.Text = "相机: 第三人称"
        UI.CamBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
        UI.CamDistSliderContainer.Visible = true
    elseif camState == 2 then
        UI.CamBtn.Text = "相机: 第一人称"
        UI.CamBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 0)
        UI.CamDistSliderContainer.Visible = false
    else
        UI.CamBtn.Text = "相机: 关闭"
        UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
        UI.CamDistSliderContainer.Visible = false
        updateHeadVisibility()
        resetCamera()
    end
end)

UI.ListFrame = Instance.new("Frame")
UI.ListFrame.Size = UDim2.new(0, 180, 0, 280)
UI.ListFrame.Position = UDim2.new(1, 0, 0, 0)
UI.ListFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.ListFrame.BackgroundTransparency = 0.1
UI.ListFrame.Visible = false
UI.ListFrame.ZIndex = 150
UI.ListFrame.Parent = UI.MainFrame
Instance.new("UICorner", UI.ListFrame).CornerRadius = UDim.new(0, 10)
addStroke(UI.ListFrame, Color3.fromRGB(0, 220, 140))

UI.ListTitle = Instance.new("TextLabel")
UI.ListTitle.Size = UDim2.new(1, -30, 0, 30)
UI.ListTitle.BackgroundTransparency = 1
UI.ListTitle.Text = "玩家列表"
UI.ListTitle.TextColor3 = Color3.fromRGB(0, 230, 150)
UI.ListTitle.Font = Enum.Font.GothamBold
UI.ListTitle.TextSize = 13
UI.ListTitle.TextXAlignment = Enum.TextXAlignment.Center
UI.ListTitle.TextYAlignment = Enum.TextYAlignment.Center
UI.ListTitle.ZIndex = 152
UI.ListTitle.Parent = UI.ListFrame

UI.CloseListBtn = Instance.new("TextButton")
UI.CloseListBtn.Size = UDim2.new(0, 22, 0, 22)
UI.CloseListBtn.Position = UDim2.new(1, -26, 0, 4)
UI.CloseListBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
UI.CloseListBtn.Text = "X"
UI.CloseListBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.CloseListBtn.Font = Enum.Font.GothamBold
UI.CloseListBtn.TextSize = 12
UI.CloseListBtn.ZIndex = 153
UI.CloseListBtn.Parent = UI.ListFrame
Instance.new("UICorner", UI.CloseListBtn).CornerRadius = UDim.new(0, 5)

UI.ScrollingFrame = Instance.new("ScrollingFrame")
UI.ScrollingFrame.Size = UDim2.new(1, -10, 1, -40)
UI.ScrollingFrame.Position = UDim2.new(0, 5, 0, 35)
UI.ScrollingFrame.BackgroundTransparency = 1
UI.ScrollingFrame.ScrollBarThickness = 4
UI.ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
UI.ScrollingFrame.ZIndex = 152
UI.ScrollingFrame.Parent = UI.ListFrame
Instance.new("UIListLayout", UI.ScrollingFrame).Padding = UDim.new(0, 4)

UI.FollowCtrlFrame = Instance.new("Frame")
UI.FollowCtrlFrame.Name = "FollowCtrlFrame"
UI.FollowCtrlFrame.Size = UDim2.new(0, 34, 0, 216)
UI.FollowCtrlFrame.Position = UDim2.new(1, 185, 0, 35)
UI.FollowCtrlFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.FollowCtrlFrame.BackgroundTransparency = 0.1
UI.FollowCtrlFrame.Visible = false
UI.FollowCtrlFrame.ZIndex = 160
UI.FollowCtrlFrame.Parent = UI.MainFrame
Instance.new("UICorner", UI.FollowCtrlFrame).CornerRadius = UDim.new(0, 6)
addStroke(UI.FollowCtrlFrame, Color3.fromRGB(79, 255, 152))
local followPad = Instance.new("UIPadding", UI.FollowCtrlFrame)
followPad.PaddingTop = UDim.new(0, 4)
followPad.PaddingBottom = UDim.new(0, 4)
followPad.PaddingLeft = UDim.new(0, 4)
followPad.PaddingRight = UDim.new(0, 4)
local followLayout = Instance.new("UIListLayout", UI.FollowCtrlFrame)
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
    btn.Parent = UI.FollowCtrlFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(function()
        if axis == "forward" then followOffsetForward = followOffsetForward + delta
        elseif axis == "right" then followOffsetRight = followOffsetRight + delta
        elseif axis == "up" then followOffsetUp = followOffsetUp + delta end
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
local originalCollides = {}

local flySoundBackup = {}
local flySoundConn = nil
local soundCheckCounter = 0

local soulCFrame = CFrame.new()
local originalPlayerSizes = setmetatable({}, {__mode = "k"})
local originalNPCSizes = setmetatable({}, {__mode = "k"})
local hitboxMultipliers = {1, 3, 6, 10, 20, 50, 100, 200, 500, 800}
local hitboxNames = {"1x", "3x", "6x", "10x", "20x", "50x", "100x", "200x", "500x", "800x"}
local playerHitboxIndex = 1
local npcHitboxIndex = 1

local lastListKey = ""
local refreshList = function() end

local itemEspEnabled = false
local itemEspCache = {}

local rayEnabled = false
local modelEspEnabled = false
local noShadowEnabled = false
local espLines = {}

local function createRayForModel(model)
    if not hasDrawing then return nil end
    local line = nil
    pcall(function()
        line = Drawing.new("Line")
        line.Thickness = 2
        line.Transparency = 0.8
        line.Visible = false
    end)
    if not line then return nil end
    local label = Instance.new("BillboardGui")
    label.Name = "RayLabel_BB"
    label.Size = UDim2.new(0, 150, 0, 20)
    label.StudsOffset = Vector3.new(0, 2, 0)
    label.AlwaysOnTop = true
    label.MaxDistance = 2000
    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundTransparency = 1
    txt.Font = Enum.Font.GothamBold
    txt.TextSize = 12
    txt.TextStrokeTransparency = 0.5
    txt.Text = ""
    txt.Parent = label
    label.Adornee = model
    label.Parent = model
    return {line = line, label = label, text = txt, adornee = model}
end

local function clearRays(filter)
    for key, data in pairs(espLines) do
        local shouldClear = (filter == nil)
            or (filter == "player" and key:IsA("Player"))
            or (filter == "npc" and key:IsA("Model"))
        if shouldClear then
            pcall(function() if data.line then data.line:Remove() end end)
            pcall(function() if data.label then data.label:Destroy() end end)
            espLines[key] = nil
        end
    end
end

local noclipEnvCollides = {}
local noclipScanAccum = 0

local function restoreEnvCollides()
    for part, c in pairs(noclipEnvCollides) do
        if part and part.Parent then pcall(function() part.CanCollide = c end) end
    end
    noclipEnvCollides = {}
    noclipScanAccum = 0
end

local function scanEnvCollide()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if not hrp then return end
    local center = hrp.Position
    local scanRadius = 25
    local filters = {char}
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart then
        local seat = hum.SeatPart
        local root = seat.AssemblyRootPart or seat
        if root then center = root.Position end
        local vehicleModel = seat:FindFirstAncestorOfClass("Model")
        if vehicleModel and vehicleModel ~= workspace then table.insert(filters, vehicleModel) end
        scanRadius = 55
    end
    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = filters
    rp.FilterType = Enum.RaycastFilterType.Exclude
    pcall(function() rp.RespectCanCollide = false end)
    local dirs = {
        Vector3.new(1,0,0), Vector3.new(-1,0,0),
        Vector3.new(0,0,1), Vector3.new(0,0,-1),
        Vector3.new(1,0,1).Unit, Vector3.new(-1,0,1).Unit,
        Vector3.new(1,0,-1).Unit, Vector3.new(-1,0,-1).Unit,
    }
    for _, dir in ipairs(dirs) do
        local ray = workspace:Raycast(center, dir * scanRadius, rp)
        if ray and ray.Instance and ray.Instance:IsA("BasePart") then
            local p = ray.Instance
            if noclipEnvCollides[p] == nil then noclipEnvCollides[p] = p.CanCollide end
            if p.CanCollide then p.CanCollide = false end
        end
    end
end

local function noclipTick(dt)
    if not loopAlive() then return end
    if not noclip then
        if next(noclipEnvCollides) then restoreEnvCollides() end
        return
    end
    local char = LocalPlayer.Character
    if char then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end
                if v.CanCollide then v.CanCollide = false end
            end
        end
    end
    for part in pairs(noclipEnvCollides) do
        if part and part.Parent and part.CanCollide then part.CanCollide = false end
    end
    noclipScanAccum = noclipScanAccum + (dt or 0)
    if noclipScanAccum >= 0.15 then
        noclipScanAccum = 0
        scanEnvCollide()
    end
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then
            local seat = hum.SeatPart
            local root = seat.AssemblyRootPart or seat
            if root and not root.Anchored then
                local md = hum.MoveDirection
                if md.Magnitude > 0.1 then
                    local push = Vector3.new(md.X, 0, md.Z)
                    if push.Magnitude > 0.01 then
                        local vel = root.AssemblyLinearVelocity
                        local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
                        if horizontalSpeed < 15 then
                            root.AssemblyLinearVelocity = Vector3.new(
                                push.Unit.X * 150,
                                vel.Y,
                                push.Unit.Z * 150
                            )
                        end
                    end
                end
            end
        end
    end
end

local function muteCharacterSounds()
    local char = LocalPlayer.Character
    if not char then return end
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("Sound") then
            if flySoundBackup[v] == nil then flySoundBackup[v] = v.Volume end
            if v.Volume ~= 0 then v.Volume = 0 end
        end
    end
end

local function unmuteCharacterSounds()
    if flySoundConn then flySoundConn:Disconnect(); flySoundConn = nil end
    for sound, vol in pairs(flySoundBackup) do
        if sound and sound.Parent then pcall(function() sound.Volume = vol end) end
    end
    flySoundBackup = {}
end

local function stopPhysics()
    flying = false
    flyDiagnosticPending = false
    flyWasVehicle = false
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
    flyWasVehicle = false
    local char = LocalPlayer.Character
    if not char or not char.Parent then return false, "no_char" end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false, "no_hum" end
    local attach
    local isInVehicle = false
    if hum.SeatPart then
        isInVehicle = true
        attach = hum.SeatPart.AssemblyRootPart or hum.SeatPart
        if not attach then return false, "no_attach" end
        if attach.Anchored then return false, "anchored" end
        local owner = nil
        local okQuery = pcall(function() owner = attach:GetNetworkOwner() end)
        if not okQuery then return false, "query_fail" end
        if owner ~= LocalPlayer then
            pcall(function() attach:SetNetworkOwner(LocalPlayer) end)
        end
    else
        if hum.RigType == Enum.HumanoidRigType.R6 then
            attach = char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
        else
            attach = char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
        end
    end
    if not attach then return false, "no_attach" end
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    if not isInVehicle then
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
    flyWasVehicle = isInVehicle
    return true
end

local function forceStopFly()
    if not flying then return end
    flying = false
    flyDiagnosticPending = false
    flyWasVehicle = false
    UI.FlyBtn.Text = "开启飞行"
    UI.FlyBtn.BackgroundColor3 = Color3.fromRGB(180, 160, 40)
    UI.SpeedSliderContainer.Visible = false
    stopPhysics()
end

local function forceStopAirwalk()
    if not airwalkEnabled then return end
    airwalkEnabled = false
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    UI.AirWalkBtn.Text = "空中行走"
    UI.AirWalkBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 150)
end

local function forceStopStick()
    if not stickMode then return end
    stickMode = false
    if UI.FollowCtrlFrame then UI.FollowCtrlFrame.Visible = false end
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
            UI.CamBtn.Text = "相机: 关闭"
            UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
            UI.CamDistSliderContainer.Visible = false
        end
        if aimMode > 0 then
            aimMode = 0
            aimLockTarget = nil
            UI.AimBtn.Text = "随机自瞄: 关"
            UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
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
    UI.SoulBtn.Text = "出窍: 关"
    UI.SoulBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 60)
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

local HB_BASE = Vector3.new(21, 21, 21)

local function applyHitbox(char, index, isNPC)
    if index == 1 then return end
    if not char or not char.Parent then return end
    local mult = hitboxMultipliers[index]
    local targetSize = HB_BASE * mult
    local dict = isNPC and originalNPCSizes or originalPlayerSizes
    if not dict[char] then dict[char] = {} end
    local backup = dict[char]
    local function modify(part)
        if not part or not part:IsA("BasePart") then return end
        if not backup[part] then
            backup[part] = {
                Size = part.Size,
                Transparency = part.Transparency,
                CanCollide = part.CanCollide,
                Massless = part.Massless,
                CastShadow = part.CastShadow,
            }
        end
        part.CanCollide = false
        part.Transparency = 0.6
        part.Size = targetSize
        part.Massless = true
        part.CastShadow = false
    end
    modify(char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
    modify(char:FindFirstChild("Head"))
    modify(char:FindFirstChild("HumanoidRootPart"))
end

local function restoreHitbox(char, isNPC)
    if not char or not char.Parent then return end
    local dict = isNPC and originalNPCSizes or originalPlayerSizes
    local backup = dict[char]
    if backup then
        for part, o in pairs(backup) do
            if part and part.Parent then
                part.Size = o.Size
                part.Transparency = o.Transparency
                part.CanCollide = o.CanCollide
                part.Massless = o.Massless
                part.CastShadow = o.CastShadow
            end
        end
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
            if not model or not model.Parent then npcCache[model] = nil
            else
                local nhrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if nhrp and (nhrp.Position - myPos).Magnitude < 400 then
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
                    UI.AimBtn.Text = "随机自瞄: 关"
                    UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                    lastListKey = ""
                end
            else
                aimMode = 0
                UI.AimBtn.Text = "随机自瞄: 关"
                UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
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
        UI.CamBtn.Text = "相机: 关闭"
        UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
        UI.CamDistSliderContainer.Visible = false
    end
    if soulMode then
        toggleSoul(false)
        UI.SoulBtn.Text = "出窍: 关"
        UI.SoulBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 60)
    end
    if aimMode > 0 then
        aimMode = 0
        aimLockTarget = nil
        UI.AimBtn.Text = "随机自瞄: 关"
        UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
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
        if not wh or wh.Health <= 0 then stopWatching() end
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
            UI.AimBtn.Text = "随机自瞄: 关"
            UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        end
    end
    local key = getListKey()
    if not force and key == lastListKey then return end
    lastListKey = key
    for _, c in pairs(UI.ScrollingFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local count = 0
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
            count = count + 1
            local f = Instance.new("Frame", UI.ScrollingFrame)
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
                isAimLocked and "解" or "锁", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", lk).CornerRadius = UDim.new(0, 4)
            lk.MouseButton1Click:Connect(function()
                if aimMode == 2 and aimLockTarget == p then
                    aimMode = 0
                    aimLockTarget = nil
                    UI.AimBtn.Text = "随机自瞄: 关"
                    UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
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
                    UI.AimBtn.Text = "随机自瞄: 关"
                    UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                end
                refreshList(true)
            end)

            local w = Instance.new("TextButton", f)
            w.Size, w.Position, w.BackgroundColor3, w.Text, w.TextColor3, w.Font, w.TextSize, w.ZIndex =
                UDim2.new(0, 28, 0, 22), UDim2.new(1, -87, 0, 4),
                (watchTarget == p) and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(50, 120, 160),
                (watchTarget == p) and "停" or "视", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", w).CornerRadius = UDim.new(0, 4)
            w.MouseButton1Click:Connect(function()
                if watchTarget == p then stopWatching() else startWatching(p) end
                refreshList(true)
            end)

            local s = Instance.new("TextButton", f)
            local isFollowing = (stickMode and stickTarget == p)
            s.Size, s.Position, s.BackgroundColor3, s.Text, s.TextColor3, s.Font, s.TextSize, s.ZIndex =
                UDim2.new(0, 28, 0, 22), UDim2.new(1, -58, 0, 4),
                isFollowing and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(180, 120, 40),
                isFollowing and "停" or "跟", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
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
                UI.FollowCtrlFrame.Visible = UI.ListFrame.Visible
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
                    if t.Parent then
                        t.Text = "OK"
                        task.wait(1)
                        if t.Parent then t.Text = "传" end
                    end
                end
            end)
        end
    end
    UI.ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

task.spawn(function()
    while task.wait(1.5) do
        if not loopAlive() then break end
        if UI.ListFrame.Visible then refreshList() end
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
                if UI.ListFrame.Visible then refreshList(true) end
            end
        end
        if stickMode and stickTarget then
            local sc = stickTarget.Character
            local sh = sc and sc:FindFirstChildOfClass("Humanoid")
            if not sh or sh.Health <= 0 then
                forceStopStick()
                stickTarget = nil
                if UI.ListFrame.Visible then refreshList(true) end
            end
        end
        if aimMode == 2 and aimLockTarget then
            local ac = aimLockTarget.Character
            local ah = ac and ac:FindFirstChildOfClass("Humanoid")
            if not ah or ah.Health <= 0 then
                aimMode = 0
                aimLockTarget = nil
                UI.AimBtn.Text = "随机自瞄: 关"
                UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                if UI.ListFrame.Visible then refreshList(true) end
            end
        end
    end
end)

track(RunService.Heartbeat:Connect(function(dt) noclipTick(dt) end))

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if not hrp then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if not Camera then return end

    if flyDiagnosticPending then
        local elapsed = os.clock() - flyStartTime
        if elapsed > 0.6 then
            flyDiagnosticPending = false
            local currentAttach = flyAttach
            if currentAttach and currentAttach.Parent and flyStartPos then
                if (currentAttach.Position - flyStartPos).Magnitude < 0.3 then
                    forceStopFly()
                    UI.FlyBtn.Text = "载具飞行被服务端拒绝"
                    task.spawn(function()
                        task.wait(1.6)
                        if UI.FlyBtn.Parent and UI.FlyBtn.Text == "载具飞行被服务端拒绝" then UI.FlyBtn.Text = "开启飞行" end
                    end)
                end
            end
        end
    end

    if stickMode and stickTarget and stickTarget.Character then
        local thrp = getHRP(stickTarget.Character)
        if thrp then
            local baseCF = thrp.CFrame * CFrame.new(followOffsetRight, followOffsetUp, -followOffsetForward)
            local targetCF = baseCF + thrp.AssemblyLinearVelocity * 0.1
            char:PivotTo(targetCF)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
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
        local ok = startPhysics(); if not ok then forceStopFly() end
        return
    end
    if hum.SeatPart == nil and flyAttach ~= char:FindFirstChild("UpperTorso") and flyAttach ~= char:FindFirstChild("Torso") and flyAttach ~= hrp then
        local ok = startPhysics(); if not ok then forceStopFly() end
        return
    end
    if hum.SeatPart and flyAttach ~= hum.SeatPart.AssemblyRootPart and flyAttach ~= hum.SeatPart then
        local ok = startPhysics(); if not ok then forceStopFly() end
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
    local targetVel = flyDir.Magnitude > 0.1 and (flyDir.Unit * (speeds * 50)) or Vector3.new(0, 0.1, 0)
    bodyVelocity.Velocity = targetVel
    if flyAttach and flyDir.Magnitude > 0.1 and flyAttach.Parent then
        local actualVel = flyAttach.AssemblyLinearVelocity.Magnitude
        local expected = speeds * 50
        if actualVel < expected * 0.3 then
            local forceStep = flyDir.Unit * math.min(expected * 0.016, 3)
            pcall(function()
                if hum.SeatPart then
                    local vehicleModel = hum.SeatPart:FindFirstAncestorOfClass("Model")
                    if vehicleModel then
                        vehicleModel:PivotTo(vehicleModel:GetPivot() + forceStep)
                    else
                        flyAttach.CFrame = flyAttach.CFrame + forceStep
                    end
                else
                    flyAttach.CFrame = flyAttach.CFrame + forceStep
                end
            end)
        end
    end
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
    if prompt and prompt:IsA("ProximityPrompt") and prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
end
for _, obj in pairs(workspace:GetDescendants()) do
    if obj:IsA("ProximityPrompt") then zeroPrompt(obj) end
end
track(workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("ProximityPrompt") then zeroPrompt(obj) end
    if noShadowEnabled and obj:IsA("BasePart") then
        obj.CastShadow = false
    end
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
    if obj:IsA("ProximityPrompt") and obj.ObjectText ~= "" then objName = obj.ObjectText
    elseif obj:IsA("ProximityPrompt") and obj.ActionText ~= "" then objName = obj.ActionText end
    local chineseName = translateName(objName)
    local lowerName = string.lower(objName)
    local color = Color3.fromRGB(0, 200, 255)
    if string.find(lowerName, "door") or string.find(lowerName, "exit") then color = Color3.fromRGB(50, 255, 50)
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
        FogEnd=Lighting.FogEnd, FogStart=Lighting.FogStart,
        GlobalShadows=Lighting.GlobalShadows, Ambient=Lighting.Ambient,
        OutdoorAmbient=Lighting.OutdoorAmbient,
        ExposureCompensation=Lighting.ExposureCompensation,
        ShadowSoftness=Lighting.ShadowSoftness,
        Brightness=Lighting.Brightness,
        ClockTime=Lighting.ClockTime
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
    Lighting.Brightness = 1.5
    Lighting.ClockTime = 13
    Lighting.Ambient = Color3.fromRGB(100, 100, 100)
    Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 100)
    Lighting.ExposureCompensation = 0
    pcall(function() Lighting.ShadowSoftness = 0 end)
    for _, obj in pairs(Lighting:GetChildren()) do
        if obj:IsA("Atmosphere") then
            if not hiddenEffects[obj] then hiddenEffects[obj] = {Density=obj.Density, Haze=obj.Haze, Glare=obj.Glare, Offset=obj.Offset} end
            obj.Density, obj.Haze, obj.Glare, obj.Offset = 0, 0, 0, 0
        elseif obj:IsA("PostEffect") then
            if not hiddenEffects[obj] then hiddenEffects[obj] = {Enabled=obj.Enabled} end
            obj.Enabled = false
        end
    end
end

local function startForceOverride()
    if forceConn then forceConn:Disconnect(); forceConn = nil end
    local accum = 0
    forceConn = RunService.Heartbeat:Connect(function(dt)
        if not loopAlive() then
            if forceConn then forceConn:Disconnect(); forceConn = nil end
            return
        end
        accum = accum + (dt or 0)
        if accum < 0.1 then return end
        accum = 0
        Lighting.GlobalShadows = false
        Lighting.FogStart = 0
        Lighting.FogEnd = 1e9
        Lighting.Brightness = 1.5
        Lighting.ClockTime = 13
        Lighting.Ambient = Color3.fromRGB(100, 100, 100)
        Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 100)
        Lighting.ExposureCompensation = 0
        for _, obj in pairs(Lighting:GetChildren()) do
            if obj:IsA("Atmosphere") then
                if not hiddenEffects[obj] then hiddenEffects[obj] = {Density=obj.Density, Haze=obj.Haze, Glare=obj.Glare, Offset=obj.Offset} end
                obj.Density, obj.Haze, obj.Glare, obj.Offset = 0, 0, 0, 0
            elseif obj:IsA("PostEffect") then
                if not hiddenEffects[obj] then hiddenEffects[obj] = {Enabled=obj.Enabled} end
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

local function updatePlayerESP()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if espEnabled and p.Character and p.Character.Parent then
                if not playerHighlights[p] then
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

local function updateNpcHighlights()
    if not loopAlive() then return end
    for model, hl in pairs(npcHighlights) do
        if not model or not model.Parent then
            pcall(function() hl:Destroy() end)
            npcHighlights[model] = nil
        end
    end
    if not modelEspEnabled then return end
    
    -- 扫描全图所有后代（包括文件夹里的）
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= LocalPlayer.Character then
            registerNPC(obj)
        end
    end
    
    for model in pairs(npcCache) do
        if not loopAlive() then break end
        if model and model.Parent and not npcHighlights[model] then
            local isMonster = hasMonsterKeyword(model.Name)
            pcall(function()
                local hl = Instance.new("Highlight")
                hl.Name = "ESP_Highlight"
                hl.Adornee = model
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillColor = isMonster and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 100, 100)
                hl.OutlineColor = Color3.new(1, 1, 1)
                hl.FillTransparency = 0.5
                hl.Parent = CoreGui
                npcHighlights[model] = hl
            end)
        end
    end
end

track(workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") then
        registerNPC(obj)
        if modelEspEnabled and npcCache[obj] and not npcHighlights[obj] then
            updateNpcHighlights()
        end
    elseif obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
        registerNPC(obj.Parent)
        if modelEspEnabled and npcCache[obj.Parent] and not npcHighlights[obj.Parent] then
            updateNpcHighlights()
        end
    end
end))

task.spawn(function()
    while task.wait(2) do
        if not loopAlive() then break end
        updateNpcHighlights()
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
    if aimLockTarget == p then
        aimMode = 0
        aimLockTarget = nil
        UI.AimBtn.Text = "随机自瞄: 关"
        UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        lastListKey = ""
    end
    if stickTarget == p then forceStopStick(); stickTarget = nil end
    if watchTarget == p then stopWatching() end
end))

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() then return end
    if not rayEnabled then
        if next(espLines) then clearRays() end
        return
    end
    if not hasDrawing then return end
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    local myPos = myHRP.Position

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if espLines[p] then
                if not espEnabled or not p.Character then
                    if espLines[p].line then espLines[p].line.Visible = false end
                else
                    local hrp = getHRP(p.Character)
                    if hrp then
                        local data = espLines[p]
                        local sp, _ = Camera:WorldToViewportPoint(hrp.Position)
                        if sp.Z > 0 then
                            data.line.From = center
                            data.line.To = Vector2.new(sp.X, sp.Y)
                            data.line.Color = Color3.fromRGB(255, 255, 0)
                            data.line.Visible = true
                            local dist = (hrp.Position - myPos).Magnitude
                            data.text.Text = p.Name .. " [" .. math.floor(dist) .. "m]"
                            data.text.TextColor3 = Color3.fromRGB(255, 255, 0)
                        else
                            data.line.Visible = false
                        end
                    else
                        if espLines[p].line then espLines[p].line.Visible = false end
                    end
                end
            elseif espEnabled and p.Character then
                espLines[p] = createRayForModel(p.Character)
            end
        end
    end

    local myVehicleModel = nil
    local myHum = myChar:FindFirstChildOfClass("Humanoid")
    if myHum and myHum.SeatPart then
        myVehicleModel = myHum.SeatPart:FindFirstAncestorOfClass("Model")
    end

    local invalid = {}
    for model, data in pairs(espLines) do
        if typeof(model) == "Instance" and model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
            if not model.Parent or model == myVehicleModel or model == LocalPlayer.Character then
                table.insert(invalid, model)
            elseif not modelEspEnabled then
                if data.line then data.line.Visible = false end
                if data.text then data.text.Text = "" end
            else
                local hrp = getHRP(model)
                if hrp and data.line then
                    local sp, _ = Camera:WorldToViewportPoint(hrp.Position)
                    if sp.Z > 0 then
                        data.line.From = center
                        data.line.To = Vector2.new(sp.X, sp.Y)
                        data.line.Color = Color3.fromRGB(255, 50, 50)
                        data.line.Visible = true
                        data.text.Text = "" -- 去掉模型名字
                    else
                        data.line.Visible = false
                        data.text.Text = ""
                    end
                else
                    if data.line then data.line.Visible = false end
                    data.text.Text = ""
                end
            end
        end
    end
    for _, m in ipairs(invalid) do
        local data = espLines[m]
        if data then
            pcall(function() if data.line then data.line:Remove() end end)
            pcall(function() if data.label then data.label:Destroy() end end)
            espLines[m] = nil
        end
    end

    if modelEspEnabled then
        for model in pairs(npcCache) do
            if model and model.Parent and not espLines[model] and model ~= LocalPlayer.Character and not Players:GetPlayerFromCharacter(model) and model ~= myVehicleModel then
                espLines[model] = createRayForModel(model)
            end
        end
    end
end))

UI.FlyBtn.MouseButton1Click:Connect(function()
    if not flying then
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local ok, reason = startPhysics()
        if ok then
            flying = true
            UI.FlyBtn.Text = "飞行中"
            UI.FlyBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            if currentTab == 1 then UI.SpeedSliderContainer.Visible = true end
            if flyWasVehicle and flyAttach then
                flyStartTime = os.clock()
                flyStartPos = flyAttach.Position
                flyDiagnosticPending = true
            end
        else
            local msg = "无法飞行"
            if reason == "anchored" then msg = "载具锚定不可飞"
            elseif reason == "server_owned" then msg = "服务端拒绝载具"
            elseif reason == "no_attach" then msg = "无载具部件" end
            UI.FlyBtn.Text = msg
            task.spawn(function()
                task.wait(1.4)
                if UI.FlyBtn.Parent and UI.FlyBtn.Text == msg then UI.FlyBtn.Text = "开启飞行" end
            end)
        end
    else
        forceStopFly()
        if camState == 0 and not soulMode and not watchTarget and aimMode == 0 then
            resetCamera()
        end
    end
end)

UI.NoclipBtn.MouseButton1Click:Connect(function()
    noclip = not noclip
    UI.NoclipBtn.Text = noclip and "穿墙中" or "穿墙模式"
    UI.NoclipBtn.BackgroundColor3 = noclip and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(80, 80, 90)
    local char = LocalPlayer.Character
    if not char then return end
    if noclip then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end
                v.CanCollide = false
            end
        end
        noclipScanAccum = 999
    else
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                if originalCollides[v] ~= nil then
                    v.CanCollide = originalCollides[v]
                else
                    local n = v.Name
                    if n == "HumanoidRootPart" or n == "Torso" or n == "UpperTorso" or n == "LowerTorso" or n == "Head" then
                        v.CanCollide = true
                    end
                end
            end
        end
        originalCollides = {}
        restoreEnvCollides()
    end
end)

UI.AimBtn.MouseButton1Click:Connect(function()
    if aimMode == 1 then
        aimMode = 0
        UI.AimBtn.Text = "随机自瞄: 关"
        UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
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
        UI.AimBtn.Text = "随机自瞄: 硬"
        UI.AimBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

UI.PlayerHitboxBtn.MouseButton1Click:Connect(function()
    playerHitboxIndex = (playerHitboxIndex % #hitboxMultipliers) + 1
    UI.PlayerHitboxBtn.Text = "玩家: " .. hitboxNames[playerHitboxIndex]
    updatePlayers()
end)

UI.NPCHitboxBtn.MouseButton1Click:Connect(function()
    npcHitboxIndex = (npcHitboxIndex % #hitboxMultipliers) + 1
    UI.NPCHitboxBtn.Text = "NPC: " .. hitboxNames[npcHitboxIndex]
    if npcHitboxIndex == 1 then
        for char in pairs(originalNPCSizes) do restoreHitbox(char, true) end
    end
end)

UI.OpenListBtn.MouseButton1Click:Connect(function()
    UI.ListFrame.Visible = not UI.ListFrame.Visible
    if UI.ListFrame.Visible then
        refreshList(true)
        if stickMode then UI.FollowCtrlFrame.Visible = true end
    else
        UI.FollowCtrlFrame.Visible = false
    end
end)

UI.CloseListBtn.MouseButton1Click:Connect(function()
    UI.ListFrame.Visible = false
    UI.FollowCtrlFrame.Visible = false
end)

UI.AirWalkBtn.MouseButton1Click:Connect(function()
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
    UI.AirWalkBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
    UI.AirWalkBtn.Text = "行走开启"
end)

UI.CollectBtn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart
    UI.CollectBtn.Text = "远程爆破中..."
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
        UI.CollectBtn.Text = "远程开门中..."
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
        if not loopAlive() or not UI.CollectBtn.Parent then return end
        UI.CollectBtn.Text = "触发: " .. counts .. "个"
        task.wait(1.5)
        if UI.CollectBtn.Parent then UI.CollectBtn.Text = "全图开箱" end
    end)
end)

UI.ItemEspBtn.MouseButton1Click:Connect(function()
    itemEspEnabled = not itemEspEnabled
    UI.ItemEspBtn.Text = itemEspEnabled and "物透: 开" or "物透: 关"
    UI.ItemEspBtn.BackgroundColor3 = itemEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(40, 140, 140)
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

UI.RayBtn.MouseButton1Click:Connect(function()
    rayEnabled = not rayEnabled
    UI.RayBtn.Text = rayEnabled and "射线: 开" or "射线: 关"
    UI.RayBtn.BackgroundColor3 = rayEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(80, 140, 200)
    if not rayEnabled then clearRays() end
end)

UI.ModelEspBtn.MouseButton1Click:Connect(function()
    modelEspEnabled = not modelEspEnabled
    UI.ModelEspBtn.Text = modelEspEnabled and "模型透视: 开" or "模型透视: 关"
    UI.ModelEspBtn.BackgroundColor3 = modelEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(200, 80, 100)
    if modelEspEnabled then
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Model") then registerNPC(obj) end
        end
        updateNpcHighlights()
    else
        for _, hl in pairs(npcHighlights) do pcall(function() hl:Destroy() end) end
        npcHighlights = {}
        clearRays("npc")
    end
end)

UI.NoShadowBtn.MouseButton1Click:Connect(function()
    noShadowEnabled = not noShadowEnabled
    UI.NoShadowBtn.Text = noShadowEnabled and "去阴影: 开" or "去阴影: 关"
    UI.NoShadowBtn.BackgroundColor3 = noShadowEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 100, 120)
    
    if noShadowEnabled then
        Lighting.GlobalShadows = false
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") then v.CastShadow = false end
        end
    else
        Lighting.GlobalShadows = true
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") then v.CastShadow = true end
        end
    end
end)

UI.SoulBtn.MouseButton1Click:Connect(function()
    if not soulMode and not Camera then return end
    if not soulMode and watchTarget then stopWatching() end
    toggleSoul(not soulMode)
    UI.SoulBtn.Text = soulMode and "出窍: 开" or "出窍: 关"
    UI.SoulBtn.BackgroundColor3 = soulMode and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 80, 60)
    if soulMode then forceStopStick() end
end)

UI.EspBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    UI.EspBtn.Text = espEnabled and "人透: 开" or "人透: 关"
    UI.EspBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 50, 120)
    updatePlayerESP()
    if not espEnabled then clearRays("player") end
end)

UI.DarkBtn.MouseButton1Click:Connect(function()
    darkRemoveOn = not darkRemoveOn
    UI.DarkBtn.Text = darkRemoveOn and "去黑: 开" or "去黑: 关"
    UI.DarkBtn.BackgroundColor3 = darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 120, 50)
    if darkRemoveOn then
        captureLighting()
        applyDarkOnce()
        scanAndHideDarkParts()
        startForceOverride()
    else
        stopForceOverride()
        restoreLighting()
        restoreDarkParts()
        if noShadowEnabled then
            Lighting.GlobalShadows = false
        end
    end
end)

UI.ToggleBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        UI.ListFrame.Visible = false
        UI.FollowCtrlFrame.Visible = false
        UI.SliderContainer.Visible = false
        UI.CamDistSliderContainer.Visible = false
        UI.WalkSpeedSliderContainer.Visible = false
        UI.JumpSliderContainer.Visible = false
        UI.SpeedSliderContainer.Visible = false
        UI.MainFrame.Size = UDim2.new(0, 190, 0, 30)
        UI.ListFrame.Size = UDim2.new(0, 180, 0, 30)
    else
        showPage(currentTab)
        UI.ListFrame.Size = UDim2.new(0, 180, 0, 280)
        if currentTab == 1 and flying then UI.SpeedSliderContainer.Visible = true end
        if currentTab == 2 and camState == 1 then UI.CamDistSliderContainer.Visible = true end
        if stickMode and UI.ListFrame.Visible then UI.FollowCtrlFrame.Visible = true end
    end
    UI.TabBar.Visible = not isMinimized
    UI.ContentFrame.Visible = not isMinimized
end)

track(LocalPlayer.CharacterAdded:Connect(function()
    stopPhysics()
    stopWatching()
    restoreEnvCollides()
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false
    restoreAllHitboxes()
    originalPlayerSizes = setmetatable({}, {__mode = "k"})
    originalNPCSizes = setmetatable({}, {__mode = "k"})
    noclip = false; aimMode = 0; aimLockTarget = nil; stickTarget = nil
    playerHitboxIndex = 1; npcHitboxIndex = 1
    soulMode = false; stickMode = false
    lastListKey = ""
    originalCollides = {}

    for obj, data in pairs(itemEspCache) do
        if data.billboard then data.billboard:Destroy() end
    end
    itemEspCache = {}
    if itemEspEnabled then
        UI.ItemEspBtn.Text = "物透: 关"
        UI.ItemEspBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 140)
        itemEspEnabled = false
    end

    currentFov = 70
    if Camera then Camera.FieldOfView = currentFov end
    UI.FovBtn.Text = "视野(FOV): " .. currentFov
    UI.SliderThumb.Position = UDim2.new(0.5, -10, 0.5, -10)

    flying = false
    UI.SpeedSliderContainer.Visible = false
    UI.FollowCtrlFrame.Visible = false
    
    isMinimized = false
    UI.TabBar.Visible = true
    UI.ContentFrame.Visible = true
    showPage(1)
    UI.ListFrame.Size = UDim2.new(0, 180, 0, 280)

    task.wait(1)
    if not loopAlive() then return end

    UI.FlyBtn.Text = "开启飞行"
    UI.FlyBtn.BackgroundColor3 = Color3.fromRGB(180, 160, 40)
    UI.NoclipBtn.Text, UI.NoclipBtn.BackgroundColor3 = "穿墙模式", Color3.fromRGB(80, 80, 90)
    UI.AimBtn.Text, UI.AimBtn.BackgroundColor3 = "随机自瞄: 关", Color3.fromRGB(60, 90, 150)
    UI.PlayerHitboxBtn.Text, UI.NPCHitboxBtn.Text = "玩家: 1x", "NPC: 1x"
    UI.AirWalkBtn.Text, UI.AirWalkBtn.BackgroundColor3 = "空中行走", Color3.fromRGB(40, 130, 150)
    UI.SoulBtn.Text, UI.SoulBtn.BackgroundColor3 = "出窍: 关", Color3.fromRGB(140, 80, 60)
    UI.CollectBtn.Text = "全图开箱"
    UI.EspBtn.Text = espEnabled and "人透: 开" or "人透: 关"
    UI.EspBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 50, 120)
    UI.ModelEspBtn.Text = modelEspEnabled and "模型透视: 开" or "模型透视: 关"
    UI.ModelEspBtn.BackgroundColor3 = modelEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(200, 80, 100)
    UI.DarkBtn.Text = darkRemoveOn and "去黑: 开" or "去黑: 关"
    UI.DarkBtn.BackgroundColor3 = darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 120, 50)
    UI.NoShadowBtn.Text = noShadowEnabled and "去阴影: 开" or "去阴影: 关"
    UI.NoShadowBtn.BackgroundColor3 = noShadowEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 100, 120)

    local newChar = LocalPlayer.Character
    if newChar and newChar:FindFirstChildOfClass("Humanoid") then
        newChar.Humanoid.WalkSpeed = currentWalkSpeed
        newChar.Humanoid.JumpPower = currentJumpPower
        newChar.Humanoid.UseJumpPower = true
    end
    UI.WalkSpeedBtn.Text = "速度: " .. currentWalkSpeed
    UI.JumpBtn.Text = "跳高: " .. currentJumpPower

    camState = 0
    UI.CamBtn.Text = "相机: 关闭"
    UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
    UI.CamDistSliderContainer.Visible = false

    if darkRemoveOn then applyDarkOnce(); startForceOverride() end
    if noShadowEnabled then Lighting.GlobalShadows = false end
    resetCamera()
    UI.ListFrame.Visible = false
    LocalPlayer.CameraMaxZoomDistance = 128
    if espEnabled then updatePlayerESP() end
    if modelEspEnabled then updateNpcHighlights() end
end))

local function closeAll()
    myLoop.Run = false
    for _, c in pairs(myConns) do pcall(function() c:Disconnect() end) end
    if _G.FlyGuiV4_Conns == myConns then _G.FlyGuiV4_Conns = nil end
    if _G.FlyGuiV4_Loop == myLoop then _G.FlyGuiV4_Loop = nil end
    myConns = {}
    if soulMode then toggleSoul(false) end
    stopWatching()
    restoreEnvCollides()
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false
    camState = 0
    UI.CamBtn.Text = "相机: 关闭"
    UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
    UI.CamDistSliderContainer.Visible = false
    stopForceOverride()
    stopPhysics()
    resetCamera()
    clearRays()
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
    if darkRemoveOn then restoreLighting(); restoreDarkParts(); darkRemoveOn = false end
    for obj, data in pairs(itemEspCache) do
        if data.billboard then data.billboard:Destroy() end
    end
    itemEspCache = {}
    if char then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                local orig = originalCollides[v]
                if orig ~= nil then v.CanCollide = orig end
                v.LocalTransparencyModifier = 0
            end
            if v:IsA("Decal") then v.Transparency = 0 end
        end
        originalCollides = {}
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
    noclip = false; flying = false; stickMode = false; soulMode = false; espEnabled = false; modelEspEnabled = false; noShadowEnabled = false
    Lighting.GlobalShadows = true
    LocalPlayer.CameraMaxZoomDistance = 128
    if Camera then Camera.FieldOfView = 70 end
    if UI.ScreenGui then UI.ScreenGui:Destroy() end
end

UI.CloseBtn.MouseButton1Click:Connect(function() pcall(closeAll) end)
