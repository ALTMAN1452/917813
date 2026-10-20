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
            local h = c:FindFirstChild("HumanoidRootPart")
            if not h then break end

            local dir = (toPos - current).Unit
            current = current + dir * step
            pcall(function() h.CFrame = CFrame.new(current) * targetRot end)

            if camOffset and Camera then
                Camera.CFrame = h.CFrame * camOffset
            end

            RunService.Heartbeat:Wait()
        end

        -- 最后精确到位
        local c = LocalPlayer.Character
        if c and c.Parent then
            local h = c:FindFirstChild("HumanoidRootPart")
            if h then
                pcall(function() h.CFrame = CFrame.new(toPos) * targetRot end)
            end
        end

        ghostRestoring = false

        -- 相机恢复 Custom 跟随
        if Camera then
            Camera.CameraType = Enum.CameraType.Custom
            local c2 = LocalPlayer.Character
            if c2 and c2:FindFirstChild("Humanoid") then
                Camera.CameraSubject = c2.Humanoid
            end
        end
    end)
end

local function forceStopGhost()
    if not ghostLock then
        if GhostLockBtn then
            GhostLockBtn.Text = "Ghost: 关"
            GhostLockBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 255)
        end
        return
    end
    ghostLock = false
    if ghostJumpConn then ghostJumpConn:Disconnect(); ghostJumpConn = nil end
    if ghostHealthConn then ghostHealthConn:Disconnect(); ghostHealthConn = nil end

    local char = LocalPlayer.Character
    local savedPos = ghostVirtualPos
    local savedRot = nil
    local fromPos = nil

    if char and char.Parent then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            savedRot = hrp.CFrame - hrp.CFrame.Position
            fromPos = hrp.Position

            -- 先解锚，服务端会立刻把 HRP 位置覆盖到 P0
            hrp.Anchored = false

            if savedPos then
                smoothRestoreGhost(hrp, fromPos, savedPos, savedRot)
            end
        end
    end

    restoreGhostInvuln()

    ghostAnchorPos = nil
    ghostVirtualPos = nil
    ghostVelocity = Vector3.zero

    if GhostLockBtn then
        GhostLockBtn.Text = "Ghost: 关"
        GhostLockBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 255)
    end
end

local function startGhostLock()
    if ghostLock then return false end
    local char = LocalPlayer.Character
    if not char or not char.Parent then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end

    if hum.SeatPart then
        pcall(function() hum.Sit = false end)
        task.wait(0.15)
        char = LocalPlayer.Character
        if not char then return false end
        hrp = char:FindFirstChild("HumanoidRootPart")
        hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then return false end
    end

    forceStopFly()
    forceStopAirwalk()
    forceStopStick()
    forceStopSoul()
    if aimMode == 1 then
        aimMode = 0
        AimBtn.Text = "自瞄: 关"
        AimBtn.BackgroundColor3 = Color3.fromRGB(200, 200, 255)
        local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
        resetCamera()
    end

    ghostAnchorPos = hrp.Position
    ghostVirtualPos = hrp.Position
    ghostVelocity = Vector3.zero
    ghostLastHealth = hum.Health

    if ghostInvuln then
        applyGhostInvuln()
    end

    hrp.Anchored = true
    ghostLock = true

    ghostJumpConn = UserInputService.JumpRequest:Connect(function()
        if not ghostLock then return end
        if ghostVelocity.Y <= 0.5 then
            local jp = hum.JumpPower
            if jp < 10 then
                local jh = hum.JumpHeight
                if jh and jh > 0 then
                    jp = math.sqrt(2 * workspace.Gravity * jh)
                else
                    jp = 50
                end
            end
            ghostVelocity = Vector3.new(0, jp, 0)
        end
    end)

    ghostHealthConn = hum.HealthChanged:Connect(function(newHealth)
        if not ghostLock then return end
        if not ghostInvuln then
            ghostLastHealth = newHealth
            return
        end
        if newHealth <= 0 then
            if ghostLastHealth > 0 then
                pcall(function() hum.Health = ghostLastHealth end)
            end
        elseif newHealth < ghostLastHealth then
            pcall(function() hum.Health = ghostLastHealth end)
        else
            ghostLastHealth = newHealth
        end
    end)

    return true
end

-- ===== 出窍 RenderStepped =====
track(RunService.RenderStepped:Connect(function()
    if not loopAlive() or not soulMode or not Camera then return end
    camYaw = camYaw + (targetYaw - camYaw) * 0.5
    camPitch = camPitch + (targetPitch - camPitch) * 0.5
    local rot = CFrame.fromEulerAnglesYXZ(math.rad(camPitch), math.rad(camYaw), 0)
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

-- ===== GhostLock RenderStepped =====
track(RunService.RenderStepped:Connect(function(dt)
    if not loopAlive() or not ghostLock or ghostRestoring then return end
    local char = LocalPlayer.Character
    if not char or not char.Parent then forceStopGhost(); return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then forceStopGhost(); return end
    if hum.Health <= 0 then forceStopGhost(); return end
    if hum.SeatPart then forceStopGhost(); return end

    if ghostInvuln then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") and ghostPartData[v] == nil then
                ghostPartData[v] = {CanTouch = v.CanTouch, CanQuery = v.CanQuery}
                v.CanTouch = false
                v.CanQuery = false
            end
        end
    end

    local mv = UserInputService:GetMoveVector()
    local camLook = Camera and Camera.CFrame.LookVector or Vector3.new(0, 0, -1)
    local camRight = Camera and Camera.CFrame.RightVector or Vector3.new(1, 0, 0)
    local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
    if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
    flatLook = flatLook.Unit
    local flatRight = Vector3.new(camRight.X, 0, camRight.Z)
    if flatRight.Magnitude < 0.01 then flatRight = Vector3.new(1, 0, 0) end
    flatRight = flatRight.Unit

    local worldMove = flatLook * (-mv.Z) + flatRight * mv.X
    if worldMove.Magnitude > 1 then worldMove = worldMove.Unit end

    local speed = hum.WalkSpeed
    local horizVel = worldMove * speed

    local grav = workspace.Gravity
    ghostVelocity = Vector3.new(horizVel.X, ghostVelocity.Y - grav * dt, horizVel.Z)

    local nextPos = ghostVirtualPos + ghostVelocity * dt

    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = {char}
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local rayLen = hrp.Size.Y / 2 + 3.5
    local rayResult = workspace:Raycast(nextPos, Vector3.new(0, -rayLen, 0), rp)

    if rayResult and ghostVelocity.Y <= 0 then
        local groundY = rayResult.Position.Y + (hrp.Size.Y / 2) + 0.05
        if nextPos.Y <= groundY then
            nextPos = Vector3.new(nextPos.X, groundY, nextPos.Z)
            ghostVelocity = Vector3.new(ghostVelocity.X, 0, ghostVelocity.Z)
        end
    end

    ghostVirtualPos = nextPos

    local lookCF = CFrame.lookAt(Vector3.zero, flatLook)
    local rotOnly = lookCF - lookCF.Position
    hrp.CFrame = CFrame.new(ghostVirtualPos) * rotOnly
end))

-- ===== 命中框 =====
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
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj ~= myChar and not Players:GetPlayerFromCharacter(obj) then
                local nhrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                if nhrp and (nhrp.Position - myPos).Magnitude < 400 then
                    applyHitbox(obj, npcHitboxIndex, true)
                end
            end
        end
    end
end)

-- 【怪物绝对禁锢】
track(RunService.Stepped:Connect(function()
    if not loopAlive() or not npcFrozen then return end
    local myChar = LocalPlayer.Character
    local myHRP = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChildWhichIsA("BasePart"))
    if not myHRP then return end
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= myChar and not Players:GetPlayerFromCharacter(obj) then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if hrp then
                if (hrp.Position - myHRP.Position).Magnitude < 500 then
                    if not frozenNPCData[hrp] then
                        frozenNPCData[hrp] = {
                            cframe = hrp.CFrame,
                            anchored = hrp.Anchored,
                            walkSpeed = hum and hum.WalkSpeed or 16,
                            jumpPower = hum and hum.JumpPower or 50,
                            hum = hum
                        }
                    end
                    hrp.Anchored = true
                    hrp.CFrame = frozenNPCData[hrp].cframe
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    if hum then
                        hum.WalkSpeed = 0
                        hum.JumpPower = 0
                    end
                end
            end
        end
    end
end))

RunService:BindToRenderStep("Aimbot", Enum.RenderPriority.Camera.Value + 1, function()
    if not loopAlive() or soulMode or ghostLock or ghostRestoring then return end
    if not Camera then return end
    if aimMode == 1 then
        local targetPart
        if selectedTarget then
            targetPart = getTargetPart(selectedTarget)
            local hum = selectedTarget.Character and selectedTarget.Character:FindFirstChild("Humanoid")
            if not targetPart or not hum or hum.Health <= 0 then
                selectedTarget = nil
                lastListKey = ""
            end
        end
        if not targetPart then targetPart = getClosestTarget() end
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
    return tostring(selectedTarget) .. "_" .. table.concat(names, ",")
end

refreshList = function(force)
    if selectedTarget and (not selectedTarget.Character
        or not selectedTarget.Character:FindFirstChild("Humanoid")
        or selectedTarget.Character.Humanoid.Health <= 0) then
        selectedTarget = nil
        forceStopStick()
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
                UDim2.new(1, -4, 0, 30), Color3.fromRGB(50, 50, 60), count, 152
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
            local n = Instance.new("TextLabel", f)
            n.Size, n.BackgroundTransparency, n.Text, n.TextColor3, n.Font, n.TextSize, n.Position, n.ZIndex =
                UDim2.new(1, -75, 1, 0), 1, p.Name,
                p == selectedTarget and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(255, 255, 255),
                Enum.Font.SourceSansBold, 13, UDim2.new(0, 4, 0, 0), 153
            n.TextXAlignment = Enum.TextXAlignment.Left
            n.TextTruncate = Enum.TextTruncate.AtEnd
            local l = Instance.new("TextButton", f)
            l.Size, l.Position, l.BackgroundColor3, l.Text, l.TextColor3, l.Font, l.TextSize, l.ZIndex =
                UDim2.new(0, 32, 0, 22), UDim2.new(1, -68, 0, 4),
                p == selectedTarget and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(200, 200, 255),
                "锁", Color3.fromRGB(0, 0, 0), Enum.Font.GothamBold, 12, 153
            Instance.new("UICorner", l).CornerRadius = UDim.new(0, 4)
            l.MouseButton1Click:Connect(function()
                if selectedTarget == p then
                    selectedTarget = nil
                    forceStopStick()
                else
                    selectedTarget = p
                end
                refreshList(true)
            end)
            local t = Instance.new("TextButton", f)
            t.Size, t.Position, t.BackgroundColor3, t.Text, t.TextColor3, t.Font, t.TextSize, t.ZIndex =
                UDim2.new(0, 32, 0, 22), UDim2.new(1, -34, 0, 4),
                Color3.fromRGB(255, 215, 0), "传", Color3.fromRGB(0, 0, 0), Enum.Font.GothamBold, 12, 153
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
    ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

task.spawn(function()
    while task.wait(1.5) do
        if not loopAlive() then break end
        if ListFrame.Visible then refreshList() end
    end
end)

track(RunService.Stepped:Connect(function()
    if not loopAlive() or not noclip then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end
            if v.CanCollide then v.CanCollide = false end
        end
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
    if stickMode and selectedTarget and selectedTarget.Character then
        local thrp = getHRP(selectedTarget.Character)
        if thrp then
            local pos = thrp.Position - thrp.CFrame.LookVector * stickDistances[stickDistIndex] + Vector3.new(0, 1, 0)
            hrp.CFrame = CFrame.new(pos, thrp.Position)
            hrp.Velocity = Vector3.zero
            hum.PlatformStand = true
            return
        end
    end
    if not flying then return end
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
    if aimMode == 1 and not hum.SeatPart then
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

task.spawn(function()
    while task.wait(1) do
        if not loopAlive() then break end
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.HoldDuration > 0 then
                obj.HoldDuration = 0
            end
        end
    end
end)

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() or not itemEspEnabled then return end
    local myChar = LocalPlayer.Character
    local myHRP = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChildWhichIsA("BasePart"))
    if not myHRP then return end
    local myPos = myHRP.Position
    for _, obj in pairs(workspace:GetDescendants()) do
        if (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")) then
            local part = obj.Parent
            if part:IsA("Attachment") then part = part.Parent end
            if part:IsA("BasePart") then
                local dist = (part.Position - myPos).Magnitude
                if dist < 200 then
                    if not itemEspCache[obj] then
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
                        billboard.MaxDistance = 200
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
                end
            end
        end
    end
    for obj, data in pairs(itemEspCache) do
        if not obj.Parent or not data.part.Parent then
            if data.billboard then data.billboard:Destroy() end
            itemEspCache[obj] = nil
        else
            local dist = math.floor((data.part.Position - myPos).Magnitude)
            if dist < 200 then
                data.billboard.Enabled = true
                data.text.Text = data.name .. " [" .. dist .. "m]"
            else
                data.billboard.Enabled = false
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
        for model, data in pairs(npcHighlights) do
            if not model or not model.Parent or (model:FindFirstChildOfClass("Humanoid") and model:FindFirstChildOfClass("Humanoid").Health <= 0) then
                pcall(function() if data.hl then data.hl:Destroy() end; if data.bill then data.bill:Destroy() end end)
                npcHighlights[model] = nil
            end
        end
        for _, obj in pairs(workspace:GetDescendants()) do
            if not loopAlive() then break end
            if obj:IsA("Model") and obj ~= LocalPlayer.Character and not Players:GetPlayerFromCharacter(obj) then
                local primary = obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")
                if primary and not npcHighlights[obj] and not espFailed[obj] then
                    local hl = Instance.new("Highlight")
                    hl.Name = "ESP_Highlight"
                    hl.Adornee = obj
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.FillColor = Color3.fromRGB(255, 0, 0)
                    hl.OutlineColor = Color3.new(1, 1, 1)
                    hl.FillTransparency = 0.5
                    hl.Parent = CoreGui
                    local bill = Instance.new("BillboardGui")
                    bill.Name = "NPC_Text_ESP"
                    bill.Size = UDim2.new(0, 100, 0, 20)
                    bill.StudsOffset = Vector3.new(0, primary.Size.Y/2 + 2, 0)
                    bill.AlwaysOnTop = true
                    bill.Adornee = primary
                    bill.Parent = CoreGui
                    local txt = Instance.new("TextLabel", bill)
                    txt.Size = UDim2.new(1, 0, 1, 0)
                    txt.BackgroundTransparency = 1
                    txt.Text = "⚠ 怪物"
                    txt.TextColor3 = Color3.fromRGB(255, 50, 50)
                    txt.Font = Enum.Font.GothamBold
                    txt.TextSize = 16
                    txt.TextStrokeTransparency = 0.5
                    txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                    npcHighlights[obj] = {hl = hl, bill = bill, part = primary}
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
    if selectedTarget == p then
        selectedTarget = nil
        forceStopStick()
        lastListKey = ""
    end
end))

FlyBtn.MouseButton1Click:Connect(function()
    if not flying then
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        forceStopGhost()
        if startPhysics() then
            flying = true
            FlyBtn.Text = "飞行中"
            FlyBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            if currentTab == 1 then
                SpeedSliderContainer.Visible = true
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
    NoclipBtn.BackgroundColor3 = noclip and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(180, 180, 180)
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
    end
end)

AimBtn.MouseButton1Click:Connect(function()
    if aimMode == 0 then
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        forceStopSoul()
        forceStopGhost()
        aimMode = 1
        AimBtn.Text = "自瞄: 硬"
        AimBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    else
        aimMode = 0
        AimBtn.Text = "自瞄: 关"
        AimBtn.BackgroundColor3 = Color3.fromRGB(200, 200, 255)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
        end
        if not flying and not soulMode then resetCamera() end
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
    if ListFrame.Visible then
        refreshList(true)
    end
end)

CloseListBtn.MouseButton1Click:Connect(function()
    ListFrame.Visible = false
end)

AirWalkBtn.MouseButton1Click:Connect(function()
    if airwalkEnabled then forceStopAirwalk(); return end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    forceStopGhost()
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
                    if fireproximityprompt then
                        fireproximityprompt(v)
                    else
                        v.HoldDuration = 0
                        v:InputHoldBegin()
                        task.wait(0.01)
                        v:InputHoldEnd()
                    end
                end)
                counts = counts + 1
                task.wait(0.01)
            elseif v:IsA("ClickDetector") then
                pcall(function()
                    if fireclickdetector then fireclickdetector(v) end
                end)
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

NPCFreezeBtn.MouseButton1Click:Connect(function()
    npcFrozen = not npcFrozen
    NPCFreezeBtn.Text = npcFrozen and "怪禁: 开" or "怪禁: 关"
    NPCFreezeBtn.BackgroundColor3 = npcFrozen and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(255, 255, 255)
    if not npcFrozen then
        stopNPCFreeze()
    else
        frozenNPCData = setmetatable({}, {__mode = "k"})
    end
end)

ItemEspBtn.MouseButton1Click:Connect(function()
    itemEspEnabled = not itemEspEnabled
    ItemEspBtn.Text = itemEspEnabled and "物透: 开" or "物透: 关"
    ItemEspBtn.BackgroundColor3 = itemEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(0, 255, 255)
    if not itemEspEnabled then
        for obj, data in pairs(itemEspCache) do
            if data.billboard then data.billboard:Destroy() end
        end
        itemEspCache = {}
    end
end)

ScaleBtn.MouseButton1Click:Connect(function()
    currentScaleIndex = (currentScaleIndex % #scaleModes) + 1
    ScaleBtn.Text = "体型: " .. scaleNames[currentScaleIndex]
    applyScale(scaleModes[currentScaleIndex])
end)

SoulBtn.MouseButton1Click:Connect(function()
    if not soulMode and not Camera then return end
    toggleSoul(not soulMode)
    SoulBtn.Text = soulMode and "出窍: 开" or "出窍: 关"
    SoulBtn.BackgroundColor3 = soulMode and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(255, 180, 100)
    if soulMode then forceStopStick() end
end)

EspBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    EspBtn.Text = espEnabled and "人透: 开" or "人透: 关"
    EspBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(255, 100, 255)
    updatePlayerESP()
    if not espEnabled then
        for _, data in pairs(npcHighlights) do
            pcall(function() if data.hl then data.hl:Destroy() end; if data.bill then data.bill:Destroy() end end)
        end
        npcHighlights = {}
    end
end)

StickBtn.MouseButton1Click:Connect(function()
    if stickMode then forceStopStick(); return end
    if not selectedTarget then
        StickBtn.Text = "需先锁人"
        task.wait(1)
        StickBtn.Text = "贴背: 关"
        return
    end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    forceStopFly(); forceStopAirwalk(); forceStopGhost()
    if soulMode then forceStopSoul() end
    stickMode = true
    StickBtn.Text = "贴背: 开"
    StickBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
end)

DistBtn.MouseButton1Click:Connect(function()
    stickDistIndex = (stickDistIndex % #stickDistances) + 1
    DistBtn.Text = "距离: " .. stickDistances[stickDistIndex]
end)

DarkBtn.MouseButton1Click:Connect(function()
    darkRemoveOn = not darkRemoveOn
    DarkBtn.Text = darkRemoveOn and "去黑: 开" or "去黑: 关"
    DarkBtn.BackgroundColor3 = darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(255, 255, 150)
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

GhostLockBtn.MouseButton1Click:Connect(function()
    if not ghostLock then
        if startGhostLock() then
            GhostLockBtn.Text = "Ghost: 开"
            GhostLockBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
        end
    else
        forceStopGhost()
    end
end)

ToggleBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        ListFrame.Visible = false
        SliderContainer.Visible = false
        SpeedSliderContainer.Visible = false
        MainFrame.Size = UDim2.new(0, 180, 0, 30)
        ListFrame.Size = UDim2.new(0, 180, 0, 30)
    else
        showPage(currentTab)
        ListFrame.Size = UDim2.new(0, 180, 0, 280)
        if currentTab == 1 and flying then
            SpeedSliderContainer.Visible = true
        end
    end
    TabBar.Visible = not isMinimized
    ContentFrame.Visible = not isMinimized
end)

track(LocalPlayer.CharacterAdded:Connect(function()
    stopPhysics()
    forceStopGhost()
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false
    restoreAllHitboxes()
    originalPlayerSizes = setmetatable({}, {__mode = "k"})
    originalNPCSizes = setmetatable({}, {__mode = "k"})
    noclip = false; aimMode = 0; selectedTarget = nil
    playerHitboxIndex = 1; npcHitboxIndex = 1
    currentScaleIndex = 1
    soulMode = false; stickMode = false; stickDistIndex = 3
    lastListKey = ""
    for obj, data in pairs(itemEspCache) do
        if data.billboard then data.billboard:Destroy() end
    end
    itemEspCache = {}
    if itemEspEnabled then
        ItemEspBtn.Text = "物透: 关"
        ItemEspBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
        itemEspEnabled = false
    end
    currentFov = 70
    if Camera then Camera.FieldOfView = currentFov end
    FovBtn.Text = "视野: " .. currentFov
    SliderThumb.Position = UDim2.new(0.5, -10, 0.5, -10)
    flying = false
    SpeedSliderContainer.Visible = false
    showPage(1)
    ListFrame.Size = UDim2.new(0, 180, 0, 280)
    task.wait(1)
    if not loopAlive() then return end
    FlyBtn.Text = "开启飞行"
    FlyBtn.BackgroundColor3 = Color3.fromRGB(255, 249, 74)
    NoclipBtn.Text, NoclipBtn.BackgroundColor3 = "穿墙模式", Color3.fromRGB(180, 180, 180)
    AimBtn.Text, AimBtn.BackgroundColor3 = "自瞄: 关", Color3.fromRGB(200, 200, 255)
    PlayerHitboxBtn.Text, NPCHitboxBtn.Text = "玩家: 正常", "NPC: 正常"
    AirWalkBtn.Text, AirWalkBtn.BackgroundColor3 = "空中行走", Color3.fromRGB(150, 255, 255)
    ScaleBtn.Text, ScaleBtn.BackgroundColor3 = "体型: 正常", Color3.fromRGB(180, 255, 180)
    SoulBtn.Text, SoulBtn.BackgroundColor3 = "出窍: 关", Color3.fromRGB(255, 180, 100)
    StickBtn.Text, StickBtn.BackgroundColor3 = "贴背: 关", Color3.fromRGB(255, 150, 0)
    DistBtn.Text, DistBtn.BackgroundColor3 = "距离: 1.5", Color3.fromRGB(200, 200, 200)
    CollectBtn.Text = "全图开箱"
    EspBtn.Text = espEnabled and "人透: 开" or "人透: 关"
    EspBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(255, 100, 255)
    DarkBtn.Text = darkRemoveOn and "去黑: 开" or "去黑: 关"
    DarkBtn.BackgroundColor3 = darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(255, 255, 150)
    NPCFreezeBtn.Text = "怪禁: 关"
    NPCFreezeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    GhostLockBtn.Text = "Ghost: 关"
    GhostLockBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 255)
    stopNPCFreeze()
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
    if ghostLock then forceStopGhost() end
    if soulMode then toggleSoul(false) end
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false
    stopNPCFreeze()
    stopForceOverride()
    stopPhysics()
    resetCamera()
    pcall(function() RunService:UnbindFromRenderStep("Aimbot") end)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local g = char.HumanoidRootPart:FindFirstChild("AimbotGyro")
        if g then g:Destroy() end
    end
    for _, v in pairs(playerHighlights) do pcall(function() v:Destroy() end) end
    playerHighlights = {}
    for _, data in pairs(npcHighlights) do
        pcall(function() if data.hl then data.hl:Destroy() end; if data.bill then data.bill:Destroy() end end)
    end
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
        end
        if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
        pcall(function() char:ScaleTo(1) end)
    end
    restoreAllHitboxes()
    noclip = false; flying = false; stickMode = false; soulMode = false; espEnabled = false
    LocalPlayer.CameraMaxZoomDistance = 128
    if Camera then Camera.FieldOfView = 70 end
    if ScreenGui then ScreenGui:Destroy() end
end

CloseBtn.MouseButton1Click:Connect(function() pcall(closeAll) end)
