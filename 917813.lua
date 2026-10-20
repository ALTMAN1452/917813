-- ==========================================================
-- Fly GUI V7.8.3 (带载具飞行 + GhostLock免伤+平滑恢复 + 全种族透视 + 智能翻译)
-- ==========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- ===== 全局清理 =====
local myLoop = {Run = true}
local myConns = {}
if _G.FlyGuiV4_Loop then _G.FlyGuiV4_Loop.Run = false end
if _G.FlyGuiV4_Conns then
    for _, c in pairs(_G.FlyGuiV4_Conns) do pcall(function() c:Disconnect() end) end
end
_G.FlyGuiV4_Conns = myConns
_G.FlyGuiV4_Loop = myLoop
pcall(function() RunService:UnbindFromRenderStep("Aimbot") end)

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
    for _, name in ipairs({"FlyGui_V4", "FlyGui_V3", "ItemESP"}) do
        local old = PlayerGui:FindFirstChild(name)
        if old then old:Destroy() end
    end
    for _, obj in pairs(CoreGui:GetChildren()) do
        if obj.Name == "ESP_Highlight" or obj.Name == "NPC_Text_ESP" then obj:Destroy() end
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

-- ===== 翻译字典 =====
local translateDict = {
    ["door"] = "门", ["gate"] = "大门", ["exit"] = "出口", ["entrance"] = "入口",
    ["keypad"] = "密码锁", ["knob"] = "门把手", ["handle"] = "把手", ["button"] = "按钮",
    ["switch"] = "开关", ["lever"] = "拉杆", ["valve"] = "阀门", ["elevator"] = "电梯",
    ["stairs"] = "楼梯", ["window"] = "窗户", ["hatch"] = "舱门",
    ["drawer"] = "抽屉", ["cabinet"] = "柜子", ["wardrobe"] = "衣柜", ["closet"] = "壁橱",
    ["chest"] = "宝箱", ["box"] = "箱子", ["crate"] = "木箱", ["locker"] = "储物柜",
    ["safe"] = "保险箱", ["fridge"] = "冰箱", ["shelf"] = "架子", ["bed"] = "床",
    ["seat"] = "座位", ["chair"] = "椅子", ["table"] = "桌子", ["desk"] = "书桌",
    ["key"] = "钥匙", ["keycard"] = "门禁卡", ["coin"] = "金币", ["item"] = "物品",
    ["pickup"] = "可拾取", ["book"] = "书", ["fuse"] = "保险丝", ["battery"] = "电池",
    ["candle"] = "蜡烛", ["painting"] = "画", ["flashlight"] = "手电筒", ["clock"] = "时钟",
    ["paper"] = "纸", ["note"] = "纸条", ["plate"] = "盘子", ["generator"] = "发电机",
    ["wires"] = "电线", ["statue"] = "雕像", ["code"] = "密码", ["gear"] = "齿轮",
    ["pull"] = "拉绳", ["push"] = "推门", ["open"] = "打开", ["use"] = "使用",
    ["interact"] = "交互", ["click"] = "点击", ["press"] = "按下", ["hide"] = "躲藏",
    ["hiding"] = "躲藏点", ["grab"] = "抓取", ["take"] = "拿取", ["read"] = "阅读"
}

local function translateName(engName)
    local cleanName = string.lower(engName)
    cleanName = string.gsub(cleanName, "[^a-z]", " ")
    for eng, chn in pairs(translateDict) do
        if string.find(cleanName, eng) then
            return chn
        end
    end
    return engName
end

-- ===== 主界面 UI =====
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FlyGui_V4"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 180, 0, 154)
MainFrame.Position = UDim2.new(0.15, 0, 0.1, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ZIndex = 101
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 30)
TopBar.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 8)
local TopBarFix = Instance.new("Frame")
TopBarFix.Size = UDim2.new(1, 0, 0.5, 0)
TopBarFix.Position = UDim2.new(0, 0, 0.5, 0)
TopBarFix.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
TopBarFix.BorderSizePixel = 0
TopBarFix.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(0, 4, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 22, 0, 22)
ToggleBtn.Position = UDim2.new(0, 30, 0, 4)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(192, 150, 230)
ToggleBtn.Text = "T"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 13
ToggleBtn.Parent = TopBar
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 5)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -55, 1, 0)
Title.Position = UDim2.new(0, 55, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Fly GUI V7.8.3"
Title.TextColor3 = Color3.fromRGB(242, 60, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, 0, 0, 24)
TabBar.Position = UDim2.new(0, 0, 0, 30)
TabBar.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame

local BasicTab = Instance.new("TextButton")
BasicTab.Size = UDim2.new(0.5, 0, 1, 0)
BasicTab.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
BasicTab.Text = "基础"
BasicTab.TextColor3 = Color3.fromRGB(255, 255, 255)
BasicTab.Font = Enum.Font.GothamBold
BasicTab.TextSize = 12
BasicTab.Parent = TabBar
Instance.new("UICorner", BasicTab).CornerRadius = UDim.new(0, 5)

local AdvTab = Instance.new("TextButton")
AdvTab.Size = UDim2.new(0.5, 0, 1, 0)
AdvTab.Position = UDim2.new(0.5, 0, 0, 0)
AdvTab.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
AdvTab.Text = "高级"
AdvTab.TextColor3 = Color3.fromRGB(150, 150, 160)
AdvTab.Font = Enum.Font.GothamBold
AdvTab.TextSize = 12
AdvTab.Parent = TabBar
Instance.new("UICorner", AdvTab).CornerRadius = UDim.new(0, 5)

local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, -12, 1, -54)
ContentFrame.Position = UDim2.new(0, 6, 0, 54)
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
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(0, 0, 0)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    return btn
end

local AimBtn = createButton("Aim", "自瞄: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(200, 200, 255), PageBasic, UDim2.new(0.5, -2, 0, 28))
local OpenListBtn = createButton("OpenList", "玩家列表", UDim2.new(0.5, 0, 0, 0), Color3.fromRGB(255, 180, 255), PageBasic, UDim2.new(0.5, -2, 0, 28))
local FlyBtn = createButton("Fly", "开启飞行", UDim2.new(0, 0, 0, 32), Color3.fromRGB(255, 249, 74), PageBasic, UDim2.new(0.5, -2, 0, 28))
local NoclipBtn = createButton("Noclip", "穿墙模式", UDim2.new(0.5, 0, 0, 32), Color3.fromRGB(180, 180, 180), PageBasic, UDim2.new(0.5, -2, 0, 28))

local ScaleBtn = createButton("Scale", "体型: 正常", UDim2.new(0, 0, 0, 0), Color3.fromRGB(180, 255, 180), PageAdv, UDim2.new(0.5, -2, 0, 28))
local DarkBtn = createButton("DarkRemove", "去黑: 关", UDim2.new(0.5, 0, 0, 0), Color3.fromRGB(255, 255, 150), PageAdv, UDim2.new(0.5, -2, 0, 28))
local CollectBtn = createButton("Collect", "全图开箱", UDim2.new(0, 0, 0, 32), Color3.fromRGB(255, 215, 0), PageAdv, UDim2.new(0.5, -2, 0, 28))
local AirWalkBtn = createButton("AirWalk", "空中行走", UDim2.new(0.5, 0, 0, 32), Color3.fromRGB(150, 255, 255), PageAdv, UDim2.new(0.5, -2, 0, 28))
local SoulBtn = createButton("Soul", "出窍: 关", UDim2.new(0, 0, 0, 64), Color3.fromRGB(255, 180, 100), PageAdv, UDim2.new(0.5, -2, 0, 28))
local StickBtn = createButton("Stick", "贴背: 关", UDim2.new(0.5, 0, 0, 64), Color3.fromRGB(255, 150, 0), PageAdv, UDim2.new(0.5, -2, 0, 28))
local EspBtn = createButton("Esp", "人透: 关", UDim2.new(0, 0, 0, 96), Color3.fromRGB(255, 100, 255), PageAdv, UDim2.new(0.5, -2, 0, 28))
local DistBtn = createButton("Dist", "距离: 1.5", UDim2.new(0.5, 0, 0, 96), Color3.fromRGB(200, 200, 200), PageAdv, UDim2.new(0.5, -2, 0, 28))
local PlayerHitboxBtn = createButton("PlayerHitbox", "玩家: 正常", UDim2.new(0, 0, 0, 128), Color3.fromRGB(255, 255, 100), PageAdv, UDim2.new(0.5, -2, 0, 28))
local NPCHitboxBtn = createButton("NPCHitbox", "NPC: 正常", UDim2.new(0.5, 0, 0, 128), Color3.fromRGB(255, 100, 100), PageAdv, UDim2.new(0.5, -2, 0, 28))
local ItemEspBtn = createButton("ItemEsp", "物透: 关", UDim2.new(0, 0, 0, 160), Color3.fromRGB(0, 255, 255), PageAdv, UDim2.new(0.5, -2, 0, 28))
local NPCFreezeBtn = createButton("NPCFreeze", "怪禁: 关", UDim2.new(0.5, 0, 0, 160), Color3.fromRGB(255, 255, 255), PageAdv, UDim2.new(0.5, -2, 0, 28))
local FovBtn = createButton("FovBtn", "视野: 70", UDim2.new(0, 0, 0, 192), Color3.fromRGB(200, 200, 255), PageAdv, UDim2.new(0.5, -2, 0, 28))
local GhostLockBtn = createButton("GhostLock", "Ghost: 关", UDim2.new(0.5, 0, 0, 192), Color3.fromRGB(200, 150, 255), PageAdv, UDim2.new(0.5, -2, 0, 28))

-- ===== 速度横向滑条 =====
local SpeedSliderContainer = Instance.new("Frame")
SpeedSliderContainer.Name = "SpeedSliderContainer"
SpeedSliderContainer.Size = UDim2.new(1, 0, 0, 26)
SpeedSliderContainer.Position = UDim2.new(0, 0, 0, 68)
SpeedSliderContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
SpeedSliderContainer.Visible = false
SpeedSliderContainer.ZIndex = 105
SpeedSliderContainer.Parent = PageBasic
Instance.new("UICorner", SpeedSliderContainer).CornerRadius = UDim.new(0, 8)

local SpeedBg = Instance.new("Frame")
SpeedBg.Size = UDim2.new(1, -20, 0, 6)
SpeedBg.Position = UDim2.new(0, 10, 0.5, -3)
SpeedBg.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
SpeedBg.BorderSizePixel = 0
SpeedBg.ZIndex = 106
SpeedBg.Parent = SpeedSliderContainer
Instance.new("UICorner", SpeedBg).CornerRadius = UDim.new(1, 0)

local SpeedThumb = Instance.new("TextButton")
SpeedThumb.Size = UDim2.new(0, 16, 0, 16)
SpeedThumb.Position = UDim2.new(0, -8, 0.5, -8)
SpeedThumb.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
SpeedThumb.Text = ""
SpeedThumb.ZIndex = 107
SpeedThumb.Parent = SpeedSliderContainer
Instance.new("UICorner", SpeedThumb).CornerRadius = UDim.new(1, 0)

-- ===== FOV 竖直滑条 =====
local SliderContainer = Instance.new("Frame")
SliderContainer.Name = "SliderContainer"
SliderContainer.Size = UDim2.new(0, 40, 0, 150)
SliderContainer.Position = UDim2.new(1, 5, 0, 100)
SliderContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
SliderContainer.Visible = false
SliderContainer.ZIndex = 110
SliderContainer.Parent = MainFrame
Instance.new("UICorner", SliderContainer).CornerRadius = UDim.new(0, 8)

local SliderBg = Instance.new("Frame")
SliderBg.Size = UDim2.new(0, 6, 1, -20)
SliderBg.Position = UDim2.new(0.5, -3, 0, 10)
SliderBg.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
SliderBg.BorderSizePixel = 0
SliderBg.ZIndex = 111
SliderBg.Parent = SliderContainer
Instance.new("UICorner", SliderBg).CornerRadius = UDim.new(1, 0)

local SliderThumb = Instance.new("TextButton")
SliderThumb.Size = UDim2.new(0, 20, 0, 20)
SliderThumb.Position = UDim2.new(0, 10, 0.5, -10)
SliderThumb.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
SliderThumb.Text = ""
SliderThumb.ZIndex = 112
SliderThumb.Parent = SliderContainer
Instance.new("UICorner", SliderThumb).CornerRadius = UDim.new(1, 0)

-- ===== 滑动条逻辑 =====
local speeds = 1
local currentFov = 70
local isDraggingSpeed = false
local isDraggingFov = false
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

SpeedThumb.MouseButton1Down:Connect(function() isDraggingSpeed = true end)
SpeedBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingSpeed = true
        updateSpeedFromX(input.Position.X)
    end
end)

local function updateFovFromY(absoluteY)
    local bgAbsY = SliderBg.AbsolutePosition.Y
    local bgHeight = SliderBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = (absoluteY - bgAbsY) / bgHeight
    relativeY = math.clamp(relativeY, 0, 1)
    currentFov = math.floor(120 - (relativeY * 70))
    if Camera then Camera.FieldOfView = currentFov end
    FovBtn.Text = "视野: " .. currentFov
    SliderThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

SliderThumb.MouseButton1Down:Connect(function() isDraggingFov = true end)
SliderBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingFov = true
        updateFovFromY(input.Position.Y)
    end
end)

track(UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        if isDraggingSpeed then updateSpeedFromX(input.Position.X) end
        if isDraggingFov then updateFovFromY(input.Position.Y) end
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingSpeed = false
        isDraggingFov = false
    end
end))

local function showPage(idx)
    currentTab = idx
    PageBasic.Visible = idx == 1
    PageAdv.Visible = idx == 2
    BasicTab.BackgroundColor3 = idx == 1 and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(35, 35, 40)
    BasicTab.TextColor3 = idx == 1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 160)
    AdvTab.BackgroundColor3 = idx == 2 and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(35, 35, 40)
    AdvTab.TextColor3 = idx == 2 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 160)
    if idx ~= 2 then SliderContainer.Visible = false end
    if idx == 1 then
        MainFrame.Size = UDim2.new(0, 180, 0, 154)
    else
        MainFrame.Size = UDim2.new(0, 180, 0, 280)
    end
end
BasicTab.MouseButton1Click:Connect(function() showPage(1) end)
AdvTab.MouseButton1Click:Connect(function() showPage(2) end)

FovBtn.MouseButton1Click:Connect(function()
    SliderContainer.Visible = not SliderContainer.Visible
end)

-- ===== 玩家列表 =====
local ListFrame = Instance.new("Frame")
ListFrame.Size = UDim2.new(0, 180, 0, 280)
ListFrame.Position = UDim2.new(1, 0, 0, 0)
ListFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
ListFrame.Visible = false
ListFrame.ZIndex = 150
ListFrame.Parent = MainFrame
Instance.new("UICorner", ListFrame).CornerRadius = UDim.new(0, 8)

local ListTitleBg = Instance.new("Frame")
ListTitleBg.Size = UDim2.new(1, 0, 0, 30)
ListTitleBg.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
ListTitleBg.BorderSizePixel = 0
ListTitleBg.ZIndex = 151
ListTitleBg.Parent = ListFrame
Instance.new("UICorner", ListTitleBg).CornerRadius = UDim.new(0, 8)

local ListTitle = Instance.new("TextLabel")
ListTitle.Size = UDim2.new(1, -30, 0, 30)
ListTitle.BackgroundTransparency = 1
ListTitle.Text = "玩家列表"
ListTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
ListTitle.Font = Enum.Font.GothamBold
ListTitle.TextSize = 13
ListTitle.TextXAlignment = Enum.TextXAlignment.Center
ListTitle.TextYAlignment = Enum.TextYAlignment.Center
ListTitle.ZIndex = 152
ListTitle.Parent = ListFrame

local CloseListBtn = Instance.new("TextButton")
CloseListBtn.Size = UDim2.new(0, 22, 0, 22)
CloseListBtn.Position = UDim2.new(1, -26, 0, 4)
CloseListBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
CloseListBtn.Text = "X"
CloseListBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseListBtn.Font = Enum.Font.GothamBold
CloseListBtn.TextSize = 13
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

-- ===== 状态变量 =====
local flying = false
local noclip = false
local airwalkEnabled = false
local airwalkPlate = nil
local bodyVelocity = nil
local bodyGyro = nil
local flyAttach = nil
local aimMode = 0
local selectedTarget = nil
local isCameraLocked = false
local stickMode = false
local originalCollides = setmetatable({}, {__mode = "k"})

local npcFrozen = false
local frozenNPCData = setmetatable({}, {__mode = "k"})

local stickDistances = {0.5, 1, 1.5, 2, 6, 8, 10, 15}
local stickDistIndex = 3
local scaleModes = {1, 0.5, 0.2, 0.1, 0.05, 0.01, 0.001, 2, 5, 10, 15, 20}
local scaleNames = {"正常","0.5x","0.2x","0.1x","0.05x","0.01x","0.00x","2倍","5倍","10倍","15倍","20倍"}
local currentScaleIndex = 1

local soulMode = false
local soulCFrame = CFrame.new()
local originalPlayerSizes = setmetatable({}, {__mode = "k"})
local originalNPCSizes = setmetatable({}, {__mode = "k"})
local hitboxSizes = {1, 6, 12, 20, 30, 200, 500, 800}
local hitboxNames = {"正常", "中", "大", "巨", "极", "全", "终", "究"}
local playerHitboxIndex = 1
local npcHitboxIndex = 1

local lastListKey = ""
local refreshList = function() end
local camYaw, camPitch, targetYaw, targetPitch = 0, 0, 0, 0

local itemEspEnabled = false
local itemEspCache = {}

-- ===== GhostLock 状态 =====
local ghostLock = false
local ghostAnchorPos = nil
local ghostVirtualPos = nil
local ghostVelocity = Vector3.zero
local ghostJumpConn = nil
local ghostHealthConn = nil
local ghostInvuln = true
local ghostLastHealth = 100
local ghostPartData = setmetatable({}, {__mode = "k"})
local ghostRestoring = false

local function resetCamera()
    isCameraLocked = false
    if Camera and Camera.CameraType == Enum.CameraType.Scriptable then
        Camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            Camera.CameraSubject = char.Humanoid
        end
    end
end

track(UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if gameProcessed or not isCameraLocked then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        targetYaw = targetYaw - input.Delta.X * 0.4
        targetPitch = math.clamp(targetPitch - input.Delta.Y * 0.4, -80, 80)
    end
end))

local function applyScale(scale)
    local char = LocalPlayer.Character
    if not char or not char.Parent then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if hrp and hum then
        local liftHeight = 20 * scale
        if scale <= 0.1 then liftHeight = 2
        elseif scale <= 1 then liftHeight = 10 end
        liftHeight = math.min(liftHeight, 50)
        hrp.CFrame = hrp.CFrame + Vector3.new(0, liftHeight, 0)
        pcall(function() char:ScaleTo(scale) end)
        for _, n in ipairs({"BodyHeightScale", "BodyWidthScale", "HeadScale"}) do
            local s = hum:FindFirstChild(n)
            if s then s.Value = scale end
        end
    end
    LocalPlayer.CameraMaxZoomDistance = scale > 1 and math.min(500, 100 * scale) or 128
end

local function stopPhysics()
    flying = false
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    flyAttach = nil
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
        pcall(function() attach:SetNetworkOwner(LocalPlayer) end)
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
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Swimming) end)
        hum.PlatformStand = true
        if char:FindFirstChild("Animate") then char.Animate.Disabled = true end
        pcall(function()
            for _, t in pairs(hum:GetPlayingAnimationTracks()) do t:AdjustSpeed(0) end
        end)
    end
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
    FlyBtn.BackgroundColor3 = Color3.fromRGB(255, 249, 74)
    SpeedSliderContainer.Visible = false
    stopPhysics()
end

local function forceStopAirwalk()
    if not airwalkEnabled then return end
    airwalkEnabled = false
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    AirWalkBtn.Text = "空中行走"
    AirWalkBtn.BackgroundColor3 = Color3.fromRGB(150, 255, 255)
end

local function forceStopStick()
    if not stickMode then return end
    stickMode = false
    StickBtn.Text = "贴背: 关"
    StickBtn.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then char.Humanoid.PlatformStand = false end
end

local function stopNPCFreeze()
    npcFrozen = false
    for hrp, data in pairs(frozenNPCData) do
        pcall(function()
            if hrp and hrp.Parent then
                hrp.Anchored = data.anchored
                hrp.CFrame = data.cframe
                if data.hum and data.hum.Parent then
                    data.hum.WalkSpeed = data.walkSpeed
                    data.hum.JumpPower = data.jumpPower
                end
            end
        end)
    end
    frozenNPCData = setmetatable({}, {__mode = "k"})
end

local function toggleSoul(state)
    if state then
        if not Camera then return end
        local char = LocalPlayer.Character
        if not char or not char.Parent then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        soulMode = true
        forceStopFly(); forceStopAirwalk(); forceStopStick(); forceStopGhost()
        if aimMode == 1 then
            aimMode = 0
            AimBtn.Text = "自瞄: 关"
            AimBtn.BackgroundColor3 = Color3.fromRGB(200, 200, 255)
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
        camYaw, camPitch = targetYaw, targetPitch
        Camera.CameraType = Enum.CameraType.Scriptable
        isCameraLocked = true
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
    SoulBtn.BackgroundColor3 = Color3.fromRGB(255, 180, 100)
end

-- ===== GhostLock 免伤 =====
local function applyGhostInvuln()
    local char = LocalPlayer.Character
    if not char then return end
    ghostPartData = setmetatable({}, {__mode = "k"})
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            ghostPartData[v] = {CanTouch = v.CanTouch, CanQuery = v.CanQuery}
            v.CanTouch = false
            v.CanQuery = false
        end
    end
end

local function restoreGhostInvuln()
    for part, data in pairs(ghostPartData) do
        if part and part.Parent then
            pcall(function()
                part.CanTouch = data.CanTouch
                part.CanQuery = data.CanQuery
            end)
        end
    end
    ghostPartData = setmetatable({}, {__mode = "k"})
end

-- ===== 平滑恢复：远距离不瞬移，分帧移动 =====
local function smoothRestoreGhost(hrp, fromPos, toPos, lookRot)
    local dist = (toPos - fromPos).Magnitude

    -- 近距离（< 50格）直接设，通常不触发瞬移检测
    if dist < 50 then
        pcall(function() hrp.CFrame = CFrame.new(toPos) * lookRot end)
        return
    end

    -- 远距离：相机切 Scriptable 补偿穿帮，HRP 每帧 50 格平滑移动
    ghostRestoring = true
    local camOffset = nil
    if Camera then
        camOffset = Camera.CFrame * hrp.CFrame:Inverse()
        Camera.CameraType = Enum.CameraType.Scriptable
    end

    task.spawn(function()
        local step = 50
        local current = hrp.Position
        local targetRot = lookRot

        while (current - toPos).Magnitude > step do
            if not loopAlive() then break end
            local c = LocalPlayer.Character
            if not c or not c.Parent then break end
            local h = c:FindFi
