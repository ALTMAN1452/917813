local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

local UI = {}

--==================== 全局状态 ====================
local soulMode = false
local watchTarget = nil
local watchModel = nil
local aimLockTarget = nil
local aimLockModel = nil
local stickTarget = nil
local stickModel = nil
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

local camState = 0
local camDistance = 12
local camYaw = 0
local camPitch = 20
local isCameraLocked = false

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
local lastListKey = ""
local lastModelListKey = ""
local refreshList = function() end
local refreshModelList = function() end

local speeds = 1
local currentFov = 70
local currentTab = 1
local isMinimized = false

local antiServerEnabled = false
local npcCache = setmetatable({}, {__mode = "k"})
local modelComHistory = setmetatable({}, {__mode = "k"})
local candidateModels = setmetatable({}, {__mode = "k"})
local candidateDeadline = setmetatable({}, {__mode = "k"})

local itemEspEnabled = false
local itemEspCache = {}
local rayEnabled = false
local modelEspEnabled = false
local noShadowEnabled = false
local crosshairEnabled = false
local espLines = {}
local espEnabled = false
local playerHighlights = {}
local npcHighlights = {}
local noclipEnvCollides = {}
local noclipScanAccum = 0
local originalLighting = {}
local darkRemoveOn = false
local hiddenEffects = setmetatable({}, {__mode = "k"})
local hiddenDarkParts = setmetatable({}, {__mode = "k"})
local forceConn = nil
local originalPlayerSizes = setmetatable({}, {__mode = "k"})
local originalNPCSizes = setmetatable({}, {__mode = "k"})
local hitboxMultipliers = {1, 3, 6, 10, 20, 50, 100, 200, 500, 800}
local hitboxNames = {"1x", "3x", "6x", "10x", "20x", "50x", "100x", "200x", "500x", "800x"}
local playerHitboxIndex = 1
local npcHitboxIndex = 1
local modelHitboxIndices = setmetatable({}, {__mode = "k"})
local playerHitboxIndices = setmetatable({}, {__mode = "k"})
local hitboxAimTarget = nil
local recoveredCache = setmetatable({}, {__mode = "k"})

local antiTPEnabled = false 
local antiTP_bypass = false
local lastTPCheckCF = CFrame.new()

local isTouchingLoop = false
local isInteractingLoop = false
local isClickingLoop = false

local nativePopupBlockEnabled = false
local zeroPromptEnabled = false
local zeroPromptConn = nil

-- 点击倍数 专用状态表（独立锁 + 长按计时）
local x100State = {
    enabled = false,
    multiplier = 100,
    executing = setmetatable({}, {__mode = "k"}),
    conns = setmetatable({}, {__mode = "k"}),
    holdStart = nil,
    holdTriggered = false
}

local blockKeywords = {"购买", "buy", "robux", "充值", "价格", "purchase"}
local monsterKeywords = {"shark","monster","creature","beast","boss","enemy","dragon","zombie","animal","whale","fish","killer","megalodon","greatwhite","ghost","demon","spirit","undead","skeleton","witch","vampire"}
local excludeKeywords = {"door", "map", "baseplate", "building", "tree", "wall", "floor", "gate", "glass", "window", "terrain", "house", "room", "hall", "corridor", "island", "carpet", "chair", "table", "couch", "sofa", "bed", "lamp", "painting", "shelf", "cabinet", "prop", "decor", "picture", "art", "frame", "canvas", "poster", "light", "mirror", "clock"}

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

local playerCharConns = setmetatable({}, {__mode = "k"})
local originalShadows = setmetatable({}, {__mode = "k"})

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

--==================== 前置声明关键函数 ====================
local applyHitbox, restoreHitbox, restoreAllHitboxes
local registerNPC, unregisterNPC
local updatePlayerESP, updateNpcHighlights
local forceStopFly, forceStopAirwalk, forceStopStick, forceStopSoul
local resetCamera, updateHeadVisibility
local startPhysics, stopPhysics

--==================== 零延迟交互逻辑 ====================
local function applyZeroPrompt(prompt)
    if prompt and prompt:IsA("ProximityPrompt") and prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
end

local function toggleZeroPrompt(state)
    zeroPromptEnabled = state
    if zeroPromptConn then zeroPromptConn:Disconnect(); zeroPromptConn = nil end
    if zeroPromptEnabled then
        for _, obj in pairs(workspace:GetDescendants()) do
            applyZeroPrompt(obj)
        end
        zeroPromptConn = workspace.DescendantAdded:Connect(applyZeroPrompt)
    end
end

--==================== 点击倍数 核心逻辑 (独立防抖) ====================
local function hookSingleCD(cd)
    if x100State.conns[cd] then return end
    x100State.conns[cd] = cd.MouseClick:Connect(function(plr)
        if not x100State.enabled or x100State.executing[cd] then return end
        if plr == LocalPlayer and fireclickdetector then
            x100State.executing[cd] = true
            task.spawn(function()
                for i = 1, x100State.multiplier do
                    if not x100State.enabled or not cd.Parent then break end
                    pcall(function() fireclickdetector(cd) end)
                    task.wait(0.05)
                end
                x100State.executing[cd] = nil
            end)
        end
    end)
end

local function hookClickX100()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ClickDetector") then
            hookSingleCD(obj)
        end
    end
end

local function unhookClickX100()
    for _, conn in pairs(x100State.conns) do
        pcall(function() conn:Disconnect() end)
    end
    x100State.conns = setmetatable({}, {__mode = "k"})
end

track(workspace.DescendantAdded:Connect(function(obj)
    if x100State.enabled and obj:IsA("ClickDetector") then
        hookSingleCD(obj)
    end
end))

--==================== 原生购买弹窗狙击 ====================
local function killNativePurchasePrompt()
    if not nativePopupBlockEnabled then return end
    local foundation = CoreGui:FindFirstChild("FoundationOverlay")
    if not foundation then return end
    local productNode = foundation:FindFirstChild("ProductDetailsContainer", true)
    if not productNode then return end
    local safeArea = foundation:FindFirstChild("SafeAreaFrame")
    if not safeArea then return end
    local overlay = safeArea:FindFirstChild("OverlayPortal")
    if not overlay then return end
    
    for _, desc in ipairs(overlay:GetDescendants()) do
        if desc:IsA("GuiObject") and desc.Visible then desc.Visible = false end
    end
    for _, desc in ipairs(overlay:GetDescendants()) do
        if desc:IsA("TextButton") and (desc.Name == "CancelButton" or desc.Text == "取消" or desc.Text == "Cancel") then
            pcall(function() desc:Activate() end)
            break
        end
    end
    local function hideDarkOverlays(container)
        if not container then return end
        for _, gui in ipairs(container:GetChildren()) do
            if gui:IsA("GuiObject") and gui.Name ~= "FlyGui_V4" then
                if gui.Visible and gui.Size.X.Scale > 0.9 and gui.Size.Y.Scale > 0.9 then
                    if gui.BackgroundTransparency < 0.9 and (gui.BackgroundColor3.R < 0.1 and gui.BackgroundColor3.G < 0.1 and gui.BackgroundColor3.B < 0.1) then
                        gui.Visible = false
                    end
                end
                if not gui:IsA("ScreenGui") and not gui:IsA("SurfaceGui") then
                    hideDarkOverlays(gui)
                end
            end
        end
    end
    hideDarkOverlays(CoreGui)
    hideDarkOverlays(PlayerGui)
end

track(RunService.Heartbeat:Connect(function()
    if loopAlive() then killNativePurchasePrompt() end
end))

--==================== 角色获取 ====================
local function getCharForPlayer(p)
    local c = p.Character
    if c and c.Parent then
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hum then return c end
    end
    local r = recoveredCache[p]
    if r and r.Parent and r:FindFirstChildOfClass("Humanoid") then return r end
    return nil
end

local function getModelHRP(model)
    if not model or not model.Parent then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

local function getTargetPart(player)
    if not player then return nil end
    local char = getCharForPlayer(player)
    if not char then return nil end
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

local function refreshRecoveredCache()
    local needed = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local c = p.Character
            if not c or not c.Parent or not c:FindFirstChildOfClass("Humanoid") then
                needed[p.Name] = p
            else
                recoveredCache[p] = nil
            end
        end
    end
    if next(needed) == nil then return end
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("Model") and needed[obj.Name] then
            local p = needed[obj.Name]
            if not recoveredCache[p] or not recoveredCache[p].Parent then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum then
                    recoveredCache[p] = obj
                    needed[p.Name] = nil
                end
            end
        end
    end
end

local function getClosestTarget()
    if not Camera then return nil, nil end
    local closestP, closestM = nil, nil
    local minDist = 9999
    local sc = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    
    for _, pl in pairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            local tp = getTargetPart(pl)
            if tp then
                local char = getCharForPlayer(pl)
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local sp, onScreen = Camera:WorldToViewportPoint(tp.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - sc).Magnitude
                        if d < minDist and d < 500 then minDist = d; closestP = tp; closestM = nil end
                    end
                end
            end
        end
    end
    if not closestP then
        for model in pairs(npcCache) do
            if model and model.Parent then
                local tp = getModelHRP(model)
                if tp then
                    local sp, onScreen = Camera:WorldToViewportPoint(tp.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - sc).Magnitude
                        if d < minDist and d < 500 then minDist = d; closestM = model; closestP = nil end
                    end
                end
            end
        end
    end
    return closestP, closestM
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

--==================== 精准模型透视（扫描逻辑） ====================
local COM_SPEED_THRESHOLD = 0.4
local COM_MIN_DT = 0.05
local COM_MAX_DT = 10.0
local CANDIDATE_TTL = 99999

local function computeModelCOM(model)
    local seenAssemblies = {}
    local totalMass = 0
    local wx, wy, wz = 0, 0, 0
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and not p.Anchored then
            local root = p.AssemblyRootPart or p
            if not seenAssemblies[root] then
                seenAssemblies[root] = true
                local c = root.AssemblyCenterOfMass
                if typeof(c) ~= "Vector3" then c = root.Position end
                local m = root.AssemblyMass
                if not m or m <= 0 then m = root.Size.X * root.Size.Y * root.Size.Z end
                if m <= 0 then m = 1 end
                wx = wx + c.X * m; wy = wy + c.Y * m; wz = wz + c.Z * m
                totalMass = totalMass + m
            end
        end
    end
    if totalMass <= 0 then return nil end
    return Vector3.new(wx / totalMass, wy / totalMass, wz / totalMass)
end

local function isMovingModelDynamic(model)
    local com = computeModelCOM(model)
    if not com then return false end
    local now = os.clock()
    local rec = modelComHistory[model]
    local moving = false
    if rec then
        local dt = now - rec.t
        if dt >= COM_MIN_DT and dt <= COM_MAX_DT then
            local speed = (com - rec.c).Magnitude / dt
            if speed > COM_SPEED_THRESHOLD then moving = true end
        end
    end
    modelComHistory[model] = {c = com, t = now}
    return moving
end

registerNPC = function(model)
    if not model or not model:IsA("Model") then return end
    if npcCache[model] then
        candidateModels[model] = nil; candidateDeadline[model] = nil; return
    end
    if model == LocalPlayer.Character then return end
    if Players:GetPlayerFromCharacter(model) then return end
    if isExcluded(model.Name) then return end

    local isMonster = hasMonsterKeyword(model.Name)

    if model:FindFirstChildOfClass("Humanoid") or isMonster then
        npcCache[model] = os.clock(); candidateModels[model] = nil; candidateDeadline[model] = nil; return
    end
    if model:FindFirstChildWhichIsA("VehicleSeat", true) or model:FindFirstChildWhichIsA("Seat", true) then
        npcCache[model] = os.clock(); candidateModels[model] = nil; candidateDeadline[model] = nil; return
    end
    if model:FindFirstChildWhichIsA("ProximityPrompt", true) or model:FindFirstChildWhichIsA("ClickDetector", true) then
        npcCache[model] = os.clock(); candidateModels[model] = nil; candidateDeadline[model] = nil; return
    end

    local magnitude = 0
    local ok, size = pcall(function() return model:GetExtentsSize() end)
    if ok and typeof(size) == "Vector3" then magnitude = size.Magnitude end

    if magnitude > 5 and magnitude < 150 then
        if isMovingModelDynamic(model) then
            npcCache[model] = os.clock(); candidateModels[model] = nil; candidateDeadline[model] = nil
        else
            if not candidateModels[model] then candidateDeadline[model] = os.clock() + CANDIDATE_TTL end
            candidateModels[model] = true
        end
    end
end

unregisterNPC = function(model)
    if not model then return end
    npcCache[model] = nil; modelComHistory[model] = nil
    candidateModels[model] = nil; candidateDeadline[model] = nil
end

task.spawn(function()
    task.wait(0.5)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then registerNPC(obj) end
    end
end)

track(workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Model") then unregisterNPC(obj) end
end))

--==================== 碰撞箱 ====================
local HB_BASE = Vector3.new(21, 21, 21)

applyHitbox = function(char, index, isNPC)
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
            backup[part] = {Size = part.Size, Transparency = part.Transparency, CanCollide = part.CanCollide, Massless = part.Massless, CastShadow = part.CastShadow}
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
    if not char:FindFirstChild("HumanoidRootPart") then
        for _, p in pairs(char:GetChildren()) do
            if p:IsA("BasePart") then modify(p) end
        end
    end
end

restoreHitbox = function(char, isNPC)
    if not char or not char.Parent then return end
    local dict = isNPC and originalNPCSizes or originalPlayerSizes
    local backup = dict[char]
    if backup then
        for part, o in pairs(backup) do
            if part and part.Parent then
                part.Size = o.Size; part.Transparency = o.Transparency; part.CanCollide = o.CanCollide
                part.Massless = o.Massless; part.CastShadow = o.CastShadow
            end
        end
        dict[char] = nil
    end
end

restoreAllHitboxes = function()
    for char in pairs(originalPlayerSizes) do restoreHitbox(char, false) end
    for char in pairs(originalNPCSizes) do restoreHitbox(char, true) end
end

local function updatePlayers()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local c = getCharForPlayer(plr)
            if c then
                local idx = playerHitboxIndices[plr] or 1
                if idx > 1 then applyHitbox(c, idx, false)
                else restoreHitbox(c, false) end
            end
        end
    end
end

--==================== 按需驱动的扫描主循环（防叠加） ====================
local function needScanPlayers()
    if espEnabled then return true end
    if UI.ListFrame.Visible then return true end
    if playerHitboxIndex > 1 then return true end
    if aimMode > 0 then return true end
    return false
end

local function needScanModels()
    if modelEspEnabled then return true end
    if UI.ModelListFrame.Visible then return true end
    if npcHitboxIndex > 1 then return true end
    return false
end

task.spawn(function()
    while loopAlive() and task.wait(1) do
        if needScanPlayers() then
            refreshRecoveredCache()
            if UI.ListFrame.Visible then refreshList() end
            if playerHitboxIndex > 1 then
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer then
                        local c = getCharForPlayer(plr)
                        if c then applyHitbox(c, playerHitboxIndices[plr] or playerHitboxIndex, false) end
                    end
                end
            end
            updatePlayerESP()
        end
        if needScanModels() then
            if UI.ModelListFrame.Visible then refreshModelList() end
            if npcHitboxIndex > 1 then
                local myChar = LocalPlayer.Character
                local myHRP = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChildWhichIsA("BasePart"))
                if myHRP then
                    local myPos = myHRP.Position
                    for model in pairs(npcCache) do
                        if not model or not model.Parent then
                            npcCache[model] = nil
                        else
                            local nhrp = getModelHRP(model)
                            if nhrp and (nhrp.Position - myPos).Magnitude < 400 then applyHitbox(model, npcHitboxIndex, true) end
                        end
                    end
                end
            end
            updateNpcHighlights()
        end
    end
end)

--==================== 自瞄 ====================
RunService:BindToRenderStep("Aimbot", Enum.RenderPriority.Camera.Value + 1, function()
    if not loopAlive() or soulMode or not Camera then return end
    if camState ~= 0 then
        if isCameraLocked then
            isCameraLocked = false
            local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if h then local g = h:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
        end
        return
    end
    if aimMode > 0 then
        local targetPart = nil
        if aimMode == 2 then
            if aimLockTarget then
                targetPart = getTargetPart(aimLockTarget)
                local hum = targetPart and targetPart.Parent:FindFirstChildOfClass("Humanoid")
                if not targetPart or not hum or hum.Health <= 0 then aimLockTarget = nil; aimMode = 0 end
            elseif aimLockModel then
                targetPart = getModelHRP(aimLockModel)
                if not targetPart or not aimLockModel.Parent then aimLockModel = nil; aimMode = 0 end
            else aimMode = 0 end
            if aimMode == 0 then UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150) end
        else
            local cp, cm = getClosestTarget()
            if cp then targetPart = cp; aimLockTarget = Players:GetPlayerFromCharacter(cp.Parent)
            elseif cm then targetPart = getModelHRP(cm); aimLockModel = cm end
        end
        if not targetPart then return end
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

--==================== 穿墙 ====================
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
        Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1),
        Vector3.new(1,0,1).Unit, Vector3.new(-1,0,1).Unit, Vector3.new(1,0,-1).Unit, Vector3.new(-1,0,-1).Unit,
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
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then
            local vehicleModel = hum.SeatPart:FindFirstAncestorOfClass("Model")
            if vehicleModel then
                for _, v in pairs(vehicleModel:GetDescendants()) do
                    if v:IsA("BasePart") then
                        if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end
                        if v.CanCollide then v.CanCollide = false end
                    end
                end
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
                            root.AssemblyLinearVelocity = Vector3.new(push.Unit.X * 150, vel.Y, push.Unit.Z * 150)
                        end
                    end
                end
            end
        end
    end
end

track(RunService.Heartbeat:Connect(function(dt) noclipTick(dt) end))

--==================== 防瞬移/防切服 ====================
track(RunService.Heartbeat:Connect(function()
    if not antiTPEnabled then return end
    if antiTP_bypass or flying or soulMode or airwalkEnabled then lastTPCheckCF = CFrame.new(); return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        if lastTPCheckCF == CFrame.new() then
            lastTPCheckCF = hrp.CFrame
        else
            local dist = (hrp.Position - lastTPCheckCF.Position).Magnitude
            if dist > 35 then
                hrp.CFrame = lastTPCheckCF
                hrp.AssemblyLinearVelocity = Vector3.zero
            elseif dist < 15 then
                lastTPCheckCF = lastTPCheckCF:Lerp(hrp.CFrame, 0.5)
            end
        end
    else lastTPCheckCF = CFrame.new() end
end))

--==================== 提示 / 物透 ====================
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
    if noShadowEnabled and obj:IsA("BasePart") then
        if originalShadows[obj] == nil then originalShadows[obj] = obj.CastShadow end
        obj.CastShadow = false
    end
    if itemEspEnabled and (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")) then tryAddItemEsp(obj) end
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
            if dist < ITEM_ESP_MAX_DIST then data.text.Text = data.name .. " [" .. math.floor(dist) .. "m]" end
        end
    end
end))

--==================== 去黑 / 去阴影 ====================
local function captureLighting()
    originalLighting = {
        FogEnd=Lighting.FogEnd, FogStart=Lighting.FogStart, GlobalShadows=Lighting.GlobalShadows,
        Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient,
        ExposureCompensation=Lighting.ExposureCompensation, ShadowSoftness=Lighting.ShadowSoftness,
        Brightness=Lighting.Brightness, ClockTime=Lighting.ClockTime
    }
end

local function checkDarkPart(obj)
    if not darkRemoveOn or not obj:IsA("BasePart") then return end
    local myChar = LocalPlayer.Character
    if myChar and obj:IsDescendantOf(myChar) then return end
    if obj.Parent and obj.Parent:FindFirstChildOfClass("Humanoid") then return end
    local c = obj.Color
    if c.R < 0.08 and c.G < 0.08 and c.B < 0.08 and (obj.Size.X > 80 or obj.Size.Y > 80 or obj.Size.Z > 80) and obj.Transparency >= 0.3 and obj.Transparency <= 0.99 then
        if hiddenDarkParts[obj] == nil then hiddenDarkParts[obj] = obj.Transparency end
        obj.Transparency = 1
    end
end

track(workspace.DescendantAdded:Connect(function(obj)
    if darkRemoveOn and obj:IsA("BasePart") then checkDarkPart(obj) end
end))

local function scanAndHideDarkParts()
    local myChar = LocalPlayer.Character
    for _, obj in pairs(workspace:GetDescendants()) do
        if not loopAlive() then break end
        if obj:IsA("BasePart") and not (myChar and obj:IsDescendantOf(myChar)) and not (obj.Parent and obj.Parent:FindFirstChildOfClass("Humanoid")) then
            local c = obj.Color
            if c.R < 0.08 and c.G < 0.08 and c.B < 0.08 and (obj.Size.X > 80 or obj.Size.Y > 80 or obj.Size.Z > 80) and obj.Transparency >= 0.3 and obj.Transparency <= 0.99 then
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
    Lighting.GlobalShadows = false; Lighting.FogStart = 0; Lighting.FogEnd = 1e9
    Lighting.Brightness = 1.5; Lighting.ClockTime = 13
    Lighting.Ambient = Color3.fromRGB(100, 100, 100); Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 100)
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
        applyDarkOnce()
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

--==================== 透视 ====================
updatePlayerESP = function()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local target = nil
            if espEnabled then target = getCharForPlayer(p) end
            if target then
                if not playerHighlights[p] then
                    pcall(function()
                        local hl = Instance.new("Highlight")
                        hl.Name = "ESP_Highlight"; hl.Adornee = target
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.FillColor = Color3.fromRGB(255, 255, 0); hl.OutlineColor = Color3.new(1, 1, 1); hl.FillTransparency = 0.5
                        hl.Parent = CoreGui; playerHighlights[p] = hl
                    end)
                elseif playerHighlights[p] then playerHighlights[p].Adornee = target end
            elseif playerHighlights[p] then
                pcall(function() playerHighlights[p]:Destroy() end); playerHighlights[p] = nil
            end
        end
    end
end

local function hookPlayerCharacter(p)
    if p == LocalPlayer then return end
    if playerCharConns[p] then playerCharConns[p]:Disconnect() end
    playerCharConns[p] = p.CharacterAdded:Connect(function()
        task.wait(1)
        if not loopAlive() then return end
        updatePlayerESP()
    end)
end

updateNpcHighlights = function()
    if not loopAlive() then return end
    for model, hl in pairs(npcHighlights) do
        if not model or not model.Parent then pcall(function() hl:Destroy() end); npcHighlights[model] = nil end
    end
    if not modelEspEnabled then return end
    for model in pairs(npcCache) do
        if not loopAlive() then break end
        if model and model.Parent and not npcHighlights[model] then
            local isMonster = hasMonsterKeyword(model.Name)
            pcall(function()
                local hl = Instance.new("Highlight")
                hl.Name = "ESP_Highlight"; hl.Adornee = model
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillColor = isMonster and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 100, 100)
                hl.OutlineColor = Color3.new(1, 1, 1); hl.FillTransparency = 0.5
                hl.Parent = CoreGui; npcHighlights[model] = hl
            end)
        end
    end
end

track(workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") then
        registerNPC(obj)
        if modelEspEnabled and npcCache[obj] and not npcHighlights[obj] then updateNpcHighlights() end
    elseif obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
        registerNPC(obj.Parent)
        if modelEspEnabled and npcCache[obj.Parent] and not npcHighlights[obj.Parent] then updateNpcHighlights() end
    elseif obj:IsA("BasePart") then
        local model = obj:FindFirstAncestorOfClass("Model")
        if model and model ~= workspace then
            registerNPC(model)
            if modelEspEnabled and npcCache[model] and not npcHighlights[model] then updateNpcHighlights() end
        end
    end
end))

track(Players.PlayerAdded:Connect(function(p)
    task.wait(1)
    if not loopAlive() or p.Parent ~= Players then return end
    hookPlayerCharacter(p); updatePlayerESP()
end))

track(Players.PlayerRemoving:Connect(function(p)
    if playerCharConns[p] then playerCharConns[p]:Disconnect(); playerCharConns[p] = nil end
    recoveredCache[p] = nil
    if playerHighlights[p] then pcall(function() playerHighlights[p]:Destroy() end); playerHighlights[p] = nil end
    if aimLockTarget == p then
        aimMode = 0; aimLockTarget = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150); lastListKey = ""
    end
    if stickTarget == p then forceStopStick() end
    if watchTarget == p then stopWatching() end
end))

--==================== 射线 ====================
local function createRayForModel(model)
    if not hasDrawing then return nil end
    local line = nil
    pcall(function()
        line = Drawing.new("Line")
        line.Thickness = 2; line.Transparency = 0.8; line.Visible = false
    end)
    if not line then return nil end
    local label = Instance.new("BillboardGui")
    label.Name = "RayLabel_BB"; label.Size = UDim2.new(0, 150, 0, 20); label.StudsOffset = Vector3.new(0, 2, 0); label.AlwaysOnTop = true; label.MaxDistance = 2000
    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, 0, 1, 0); txt.BackgroundTransparency = 1; txt.Font = Enum.Font.GothamBold; txt.TextSize = 12; txt.TextStrokeTransparency = 0.5; txt.Text = ""
    txt.Parent = label; label.Adornee = model; label.Parent = model
    return {line = line, label = label, text = txt, adornee = model}
end

local function clearRays(filter)
    for key, data in pairs(espLines) do
        local shouldClear = (filter == nil) or (filter == "player" and key:IsA("Player")) or (filter == "npc" and key:IsA("Model"))
        if shouldClear then
            pcall(function() if data.line then data.line:Remove() end end)
            pcall(function() if data.label then data.label:Destroy() end end)
            espLines[key] = nil
        end
    end
end

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() then return end
    if not rayEnabled then
        if next(espLines) then clearRays() end
        return
    end
    if not hasDrawing then return end
    local vp = Camera.ViewportSize; local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local myChar = LocalPlayer.Character; local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    local myPos = myHRP.Position

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local targetChar = getCharForPlayer(p)
            if espLines[p] then
                if not espEnabled or not targetChar then
                    if espLines[p].line then espLines[p].line.Visible = false end
                else
                    local hrp = getHRP(targetChar)
                    if hrp then
                        local data = espLines[p]; local sp, _ = Camera:WorldToViewportPoint(hrp.Position)
                        if sp.Z > 0 then
                            data.line.From = center; data.line.To = Vector2.new(sp.X, sp.Y); data.line.Color = Color3.fromRGB(255, 255, 0); data.line.Visible = true
                            data.text.Text = p.Name .. " [" .. math.floor((hrp.Position - myPos).Magnitude) .. "m]"; data.text.TextColor3 = Color3.fromRGB(255, 255, 0)
                        else data.line.Visible = false end
                    else
                        if espLines[p].line then espLines[p].line.Visible = false end
                    end
                end
            elseif espEnabled and targetChar then espLines[p] = createRayForModel(targetChar) end
        end
    end

    local myVehicleModel = nil
    local myHum = myChar:FindFirstChildOfClass("Humanoid")
    if myHum and myHum.SeatPart then myVehicleModel = myHum.SeatPart:FindFirstAncestorOfClass("Model") end

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
                        data.line.From = center; data.line.To = Vector2.new(sp.X, sp.Y); data.line.Color = Color3.fromRGB(255, 50, 50); data.line.Visible = true; data.text.Text = ""
                    else data.line.Visible = false; data.text.Text = "" end
                else if data.line then data.line.Visible = false end; data.text.Text = "" end
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

--==================== UI ====================
UI.ScreenGui = Instance.new("ScreenGui")
UI.ScreenGui.Name = "FlyGui_V4"
UI.ScreenGui.ResetOnSpawn = false
UI.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
UI.ScreenGui.DisplayOrder = 2147483647
UI.ScreenGui.IgnoreGuiInset = true
UI.ScreenGui.Parent = PlayerGui

UI.Crosshair = Instance.new("Frame")
UI.Crosshair.Size = UDim2.new(0, 24, 0, 24)
UI.Crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
UI.Crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
UI.Crosshair.BackgroundTransparency = 1
UI.Crosshair.Visible = false
UI.Crosshair.ZIndex = 2147483646
UI.Crosshair.Parent = UI.ScreenGui

local crossH = Instance.new("Frame")
crossH.Size = UDim2.new(1, 0, 0, 2)
crossH.Position = UDim2.new(0, 0, 0.5, -1)
crossH.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
crossH.BorderSizePixel = 0
crossH.Parent = UI.Crosshair

local crossV = Instance.new("Frame")
crossV.Size = UDim2.new(0, 2, 1, 0)
crossV.Position = UDim2.new(0.5, -1, 0, 0)
crossV.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
crossV.BorderSizePixel = 0
crossV.Parent = UI.Crosshair

UI.MainFrame = Instance.new("Frame")
UI.MainFrame.Size = UDim2.new(0, 190, 0, 200)
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
    s.Color = color; s.Thickness = 1; s.Transparency = 0.2
end
addStroke(UI.MainFrame, Color3.fromRGB(0, 200, 255))

UI.TopBar = Instance.new("Frame")
UI.TopBar.Size = UDim2.new(1, 0, 0, 30)
UI.TopBar.Position = UDim2.new(0, 0, 0, 0)
UI.TopBar.BackgroundTransparency = 1
UI.TopBar.ZIndex = 102
UI.TopBar.Parent = UI.MainFrame

UI.CloseBtn = Instance.new("TextButton")
UI.CloseBtn.Size = UDim2.new(0, 22, 0, 22)
UI.CloseBtn.Position = UDim2.new(0, 8, 0, 4)
UI.CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
UI.CloseBtn.Text = "X"
UI.CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.CloseBtn.Font = Enum.Font.GothamBold
UI.CloseBtn.TextSize = 12
UI.CloseBtn.ZIndex = 103
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
UI.ToggleBtn.ZIndex = 103
UI.ToggleBtn.Parent = UI.TopBar
Instance.new("UICorner", UI.ToggleBtn).CornerRadius = UDim.new(0, 5)

UI.Title = Instance.new("TextLabel")
UI.Title.Size = UDim2.new(1, -65, 1, 0)
UI.Title.Position = UDim2.new(0, 65, 0, 0)
UI.Title.BackgroundTransparency = 1
UI.Title.Text = "喜瓜专用 V6.9"
UI.Title.TextColor3 = Color3.fromRGB(0, 220, 255)
UI.Title.Font = Enum.Font.GothamBold
UI.Title.TextSize = 13
UI.Title.TextXAlignment = Enum.TextXAlignment.Left
UI.Title.ZIndex = 103
UI.Title.Parent = UI.TopBar

local dragging, dragStart, startPos = false, nil, nil
UI.Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = UI.MainFrame.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
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
UI.TabBar.ZIndex = 102
UI.TabBar.Parent = UI.MainFrame

UI.BasicTab = Instance.new("TextButton")
UI.BasicTab.Size = UDim2.new(0.25, -2, 1, 0); UI.BasicTab.Position = UDim2.new(0, 0, 0, 0)
UI.BasicTab.BackgroundColor3 = Color3.fromRGB(0, 120, 180); UI.BasicTab.Text = "基础"
UI.BasicTab.TextColor3 = Color3.fromRGB(255, 255, 255); UI.BasicTab.Font = Enum.Font.GothamBold; UI.BasicTab.TextSize = 12
UI.BasicTab.ZIndex = 103; UI.BasicTab.Parent = UI.TabBar
Instance.new("UICorner", UI.BasicTab).CornerRadius = UDim.new(0, 6)

UI.DrawTab = Instance.new("TextButton")
UI.DrawTab.Size = UDim2.new(0.25, -2, 1, 0); UI.DrawTab.Position = UDim2.new(0.25, 2, 0, 0)
UI.DrawTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40); UI.DrawTab.Text = "绘制"
UI.DrawTab.TextColor3 = Color3.fromRGB(150, 160, 170); UI.DrawTab.Font = Enum.Font.GothamBold; UI.DrawTab.TextSize = 12
UI.DrawTab.ZIndex = 103; UI.DrawTab.Parent = UI.TabBar
Instance.new("UICorner", UI.DrawTab).CornerRadius = UDim.new(0, 6)

UI.AdvTab = Instance.new("TextButton")
UI.AdvTab.Size = UDim2.new(0.25, -2, 1, 0); UI.AdvTab.Position = UDim2.new(0.50, 2, 0, 0)
UI.AdvTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40); UI.AdvTab.Text = "高级"
UI.AdvTab.TextColor3 = Color3.fromRGB(150, 160, 170); UI.AdvTab.Font = Enum.Font.GothamBold; UI.AdvTab.TextSize = 12
UI.AdvTab.ZIndex = 103; UI.AdvTab.Parent = UI.TabBar
Instance.new("UICorner", UI.AdvTab).CornerRadius = UDim.new(0, 6)

UI.EntTab = Instance.new("TextButton")
UI.EntTab.Size = UDim2.new(0.25, -2, 1, 0); UI.EntTab.Position = UDim2.new(0.75, 2, 0, 0)
UI.EntTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40); UI.EntTab.Text = "娱乐"
UI.EntTab.TextColor3 = Color3.fromRGB(150, 160, 170); UI.EntTab.Font = Enum.Font.GothamBold; UI.EntTab.TextSize = 12
UI.EntTab.ZIndex = 103; UI.EntTab.Parent = UI.TabBar
Instance.new("UICorner", UI.EntTab).CornerRadius = UDim.new(0, 6)

UI.ContentFrame = Instance.new("Frame")
UI.ContentFrame.Size = UDim2.new(1, -16, 1, -64)
UI.ContentFrame.Position = UDim2.new(0, 8, 0, 60)
UI.ContentFrame.BackgroundTransparency = 1
UI.ContentFrame.ZIndex = 102
UI.ContentFrame.Parent = UI.MainFrame

UI.PageBasic = Instance.new("Frame")
UI.PageBasic.Size = UDim2.new(1, 0, 1, 0); UI.PageBasic.BackgroundTransparency = 1; UI.PageBasic.ZIndex = 103; UI.PageBasic.Parent = UI.ContentFrame

UI.PageDraw = Instance.new("Frame")
UI.PageDraw.Size = UDim2.new(1, 0, 1, 0); UI.PageDraw.BackgroundTransparency = 1; UI.PageDraw.Visible = false; UI.PageDraw.ZIndex = 103; UI.PageDraw.Parent = UI.ContentFrame

UI.PageAdv = Instance.new("Frame")
UI.PageAdv.Size = UDim2.new(1, 0, 1, 0); UI.PageAdv.BackgroundTransparency = 1; UI.PageAdv.Visible = false; UI.PageAdv.ZIndex = 103; UI.PageAdv.Parent = UI.ContentFrame

UI.PageEnt = Instance.new("Frame")
UI.PageEnt.Size = UDim2.new(1, 0, 1, 0); UI.PageEnt.BackgroundTransparency = 1; UI.PageEnt.Visible = false; UI.PageEnt.ZIndex = 103; UI.PageEnt.Parent = UI.ContentFrame

local function createButton(name, text, pos, color, parent, size)
    local btn = Instance.new("TextButton")
    btn.Name = name; btn.Size = size or UDim2.new(0.5, -2, 0, 28); btn.Position = pos
    btn.BackgroundColor3 = color; btn.BackgroundTransparency = 0.1; btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
    btn.ZIndex = 104; btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

UI.AimBtn = createButton("Aim", "随机自瞄: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(60, 90, 150), UI.PageBasic)
UI.SoulBtn = createButton("Soul", "出窍: 关", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(140, 80, 60), UI.PageBasic)
UI.NoclipBtn = createButton("Noclip", "穿墙模式", UDim2.new(0, 0, 0, 32), Color3.fromRGB(80, 80, 90), UI.PageBasic)
UI.AirWalkBtn = createButton("AirWalk", "空中走", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(40, 130, 150), UI.PageBasic)
UI.WalkSpeedBtn = createButton("WalkSpeed", "速度: 16", UDim2.new(0, 0, 0, 64), Color3.fromRGB(60, 100, 150), UI.PageBasic)
UI.JumpBtn = createButton("Jump", "跳高: 50", UDim2.new(0.5, 2, 0, 64), Color3.fromRGB(150, 100, 60), UI.PageBasic)
UI.FlyBtn = createButton("Fly", "开启飞行", UDim2.new(0, 0, 0, 96), Color3.fromRGB(180, 160, 40), UI.PageBasic, UDim2.new(1, 0, 0, 28))

UI.EspBtn = createButton("Esp", "人透: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(140, 50, 120), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.ItemEspBtn = createButton("ItemEsp", "物透: 关", UDim2.new(0.33, 2, 0, 0), Color3.fromRGB(40, 140, 140), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.CrosshairBtn = createButton("CrosshairBtn", "准星: 关", UDim2.new(0.66, 2, 0, 0), Color3.fromRGB(150, 150, 50), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))

UI.ModelEspBtn = createButton("ModelEsp", "模型透视: 关", UDim2.new(0, 0, 0, 32), Color3.fromRGB(200, 80, 100), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.RayBtn = createButton("Ray", "射线: 关", UDim2.new(0.33, 2, 0, 32), Color3.fromRGB(80, 140, 200), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.DarkBtn = createButton("DarkRemove", "去黑: 关", UDim2.new(0.66, 2, 0, 32), Color3.fromRGB(140, 120, 50), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))

UI.NoShadowBtn = createButton("NoShadow", "去阴影: 关", UDim2.new(0, 0, 0, 64), Color3.fromRGB(100, 100, 120), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.FovBtn = createButton("FovBtn", "视野(FOV): 70", UDim2.new(0.33, 2, 0, 64), Color3.fromRGB(60, 90, 150), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.CamBtn = createButton("CamBtn", "相机: 关闭", UDim2.new(0.66, 2, 0, 64), Color3.fromRGB(100, 50, 150), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))

UI.OpenListBtn = createButton("OpenList", "玩家列表", UDim2.new(0, 0, 0, 0), Color3.fromRGB(180, 60, 140), UI.PageAdv)
UI.OpenModelListBtn = createButton("OpenModelList", "模型列表", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(50, 180, 120), UI.PageAdv)

UI.PlayerHitboxBtn = createButton("PlayerHitbox", "玩家: 1x", UDim2.new(0, 0, 0, 32), Color3.fromRGB(140, 140, 40), UI.PageAdv)
UI.NPCHitboxBtn = createButton("NPCHitbox", "模型: 1x", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(160, 50, 50), UI.PageAdv)

UI.HitboxAimBtn = createButton("HitboxAim", "准星放大", UDim2.new(0, 0, 0, 64), Color3.fromRGB(200, 50, 200), UI.PageAdv, UDim2.new(1, 0, 0, 28))

UI.CollectTouchBtn = createButton("CollectTouch", "全触碰", UDim2.new(0, 0, 0, 0), Color3.fromRGB(180, 120, 40), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.CollectInteractBtn = createButton("CollectInteract", "全交互", UDim2.new(0.33, 2, 0, 0), Color3.fromRGB(180, 90, 40), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.CollectClickBtn = createButton("CollectClick", "全点击", UDim2.new(0.66, 2, 0, 0), Color3.fromRGB(140, 100, 200), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))

UI.Click100Btn = createButton("Click100", "点击倍数: " .. x100State.multiplier, UDim2.new(0, 0, 0, 32), Color3.fromRGB(100, 50, 150), UI.PageEnt)
UI.MagnetBtn = createButton("Magnet", "全吸物", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(200, 100, 100), UI.PageEnt)

UI.AntiTPBtn = createButton("AntiTP", "防瞬移: 关", UDim2.new(0, 0, 0, 64), Color3.fromRGB(80, 150, 120), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.AntiServerBtn = createButton("AntiServer", "防切服: 关", UDim2.new(0.33, 2, 0, 64), Color3.fromRGB(100, 50, 150), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.ZeroPromptBtn = createButton("ZeroPrompt", "零延迟: 关", UDim2.new(0.66, 2, 0, 64), Color3.fromRGB(100, 50, 150), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))

UI.NativePopupBtn = createButton("NativePopup", "防购买弹窗: 关", UDim2.new(0, 0, 0, 96), Color3.fromRGB(100, 50, 150), UI.PageEnt, UDim2.new(1, 0, 0, 28))

--==================== 点击倍数弹窗 UI ====================
UI.ClickMultiplierDialog = Instance.new("Frame", UI.ScreenGui)
UI.ClickMultiplierDialog.Size = UDim2.new(0, 180, 0, 110)
UI.ClickMultiplierDialog.Position = UDim2.new(0.5, -90, 0.5, -55)
UI.ClickMultiplierDialog.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.ClickMultiplierDialog.BorderSizePixel = 0
UI.ClickMultiplierDialog.Visible = false
UI.ClickMultiplierDialog.ZIndex = 1000
Instance.new("UICorner", UI.ClickMultiplierDialog).CornerRadius = UDim.new(0, 8)
addStroke(UI.ClickMultiplierDialog, Color3.fromRGB(0, 200, 255))

UI.DialogTitle = Instance.new("TextLabel", UI.ClickMultiplierDialog)
UI.DialogTitle.Size = UDim2.new(1, 0, 0, 24)
UI.DialogTitle.BackgroundTransparency = 1
UI.DialogTitle.Text = "设置点击倍数"
UI.DialogTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
UI.DialogTitle.Font = Enum.Font.GothamBold
UI.DialogTitle.TextSize = 14
UI.DialogTitle.ZIndex = 1001

UI.ClickMultiplierBox = Instance.new("TextBox", UI.ClickMultiplierDialog)
UI.ClickMultiplierBox.Size = UDim2.new(1, -20, 0, 32)
UI.ClickMultiplierBox.Position = UDim2.new(0, 10, 0, 28)
UI.ClickMultiplierBox.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
UI.ClickMultiplierBox.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.ClickMultiplierBox.TextSize = 16
UI.ClickMultiplierBox.Font = Enum.Font.GothamBold
UI.ClickMultiplierBox.Text = tostring(x100State.multiplier)
UI.ClickMultiplierBox.ZIndex = 1001
Instance.new("UICorner", UI.ClickMultiplierBox).CornerRadius = UDim.new(0, 4)

UI.DialogConfirm = Instance.new("TextButton", UI.ClickMultiplierDialog)
UI.DialogConfirm.Size = UDim2.new(0.5, -15, 0, 28)
UI.DialogConfirm.Position = UDim2.new(0, 10, 0, 70)
UI.DialogConfirm.BackgroundColor3 = Color3.fromRGB(40, 150, 90)
UI.DialogConfirm.Text = "确定"
UI.DialogConfirm.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.DialogConfirm.Font = Enum.Font.GothamBold
UI.DialogConfirm.TextSize = 13
UI.DialogConfirm.ZIndex = 1001
Instance.new("UICorner", UI.DialogConfirm).CornerRadius = UDim.new(0, 4)

UI.DialogCancel = Instance.new("TextButton", UI.ClickMultiplierDialog)
UI.DialogCancel.Size = UDim2.new(0.5, -15, 0, 28)
UI.DialogCancel.Position = UDim2.new(0.5, 5, 0, 70)
UI.DialogCancel.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
UI.DialogCancel.Text = "取消"
UI.DialogCancel.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.DialogCancel.Font = Enum.Font.GothamBold
UI.DialogCancel.TextSize = 13
UI.DialogCancel.ZIndex = 1001
Instance.new("UICorner", UI.DialogCancel).CornerRadius = UDim.new(0, 4)

UI.DialogConfirm.MouseButton1Click:Connect(function()
    local num = tonumber(UI.ClickMultiplierBox.Text)
    if num and num > 0 and num <= 1000 then
        x100State.multiplier = math.floor(num)
        x100State.enabled = true
        UI.Click100Btn.Text = "点击倍数: " .. x100State.multiplier
        UI.Click100Btn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
        hookClickX100()
    else
        UI.ClickMultiplierBox.Text = tostring(x100State.multiplier)
    end
    UI.ClickMultiplierDialog.Visible = false
end)
UI.DialogCancel.MouseButton1Click:Connect(function() UI.ClickMultiplierDialog.Visible = false end)

--==================== 滑条 ====================
UI.SpeedSliderContainer = Instance.new("Frame")
UI.SpeedSliderContainer.Name = "SpeedSliderContainer"
UI.SpeedSliderContainer.Size = UDim2.new(0, 36, 0, 150); UI.SpeedSliderContainer.Position = UDim2.new(1, 5, 0, 7)
UI.SpeedSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28); UI.SpeedSliderContainer.BackgroundTransparency = 0.05
UI.SpeedSliderContainer.Visible = false; UI.SpeedSliderContainer.ZIndex = 105; UI.SpeedSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SpeedSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.SpeedSliderContainer, Color3.fromRGB(0, 200, 255))

UI.SpeedBg = Instance.new("Frame")
UI.SpeedBg.Size = UDim2.new(0, 6, 1, -20); UI.SpeedBg.Position = UDim2.new(0.5, -3, 0, 10)
UI.SpeedBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65); UI.SpeedBg.BorderSizePixel = 0
UI.SpeedBg.Active = true; UI.SpeedBg.ZIndex = 106; UI.SpeedBg.Parent = UI.SpeedSliderContainer
Instance.new("UICorner", UI.SpeedBg).CornerRadius = UDim.new(1, 0)

UI.SpeedThumb = Instance.new("TextButton")
UI.SpeedThumb.Size = UDim2.new(0, 20, 0, 20); UI.SpeedThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.SpeedThumb.BackgroundColor3 = Color3.fromRGB(0, 200, 255); UI.SpeedThumb.Text = ""
UI.SpeedThumb.ZIndex = 107; UI.SpeedThumb.Parent = UI.SpeedSliderContainer
Instance.new("UICorner", UI.SpeedThumb).CornerRadius = UDim.new(1, 0)

UI.JumpSliderContainer = Instance.new("Frame")
UI.JumpSliderContainer.Name = "JumpSliderContainer"
UI.JumpSliderContainer.Size = UDim2.new(0, 36, 0, 72); UI.JumpSliderContainer.Position = UDim2.new(1, 45, 0, 10)
UI.JumpSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28); UI.JumpSliderContainer.BackgroundTransparency = 0.05
UI.JumpSliderContainer.Visible = false; UI.JumpSliderContainer.ZIndex = 140; UI.JumpSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.JumpSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.JumpSliderContainer, Color3.fromRGB(255, 180, 100))

UI.JumpBg = Instance.new("Frame")
UI.JumpBg.Size = UDim2.new(0, 6, 1, -10); UI.JumpBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.JumpBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65); UI.JumpBg.BorderSizePixel = 0
UI.JumpBg.Active = true; UI.JumpBg.ZIndex = 141; UI.JumpBg.Parent = UI.JumpSliderContainer
Instance.new("UICorner", UI.JumpBg).CornerRadius = UDim.new(1, 0)

UI.JumpThumb = Instance.new("TextButton")
UI.JumpThumb.Size = UDim2.new(0, 20, 0, 20); UI.JumpThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.JumpThumb.BackgroundColor3 = Color3.fromRGB(255, 180, 100); UI.JumpThumb.Text = ""
UI.JumpThumb.ZIndex = 142; UI.JumpThumb.Parent = UI.JumpSliderContainer
Instance.new("UICorner", UI.JumpThumb).CornerRadius = UDim.new(1, 0)

UI.WalkSpeedSliderContainer = Instance.new("Frame")
UI.WalkSpeedSliderContainer.Name = "WalkSpeedSliderContainer"
UI.WalkSpeedSliderContainer.Size = UDim2.new(0, 36, 0, 72); UI.WalkSpeedSliderContainer.Position = UDim2.new(1, 45, 0, 84)
UI.WalkSpeedSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28); UI.WalkSpeedSliderContainer.BackgroundTransparency = 0.05
UI.WalkSpeedSliderContainer.Visible = false; UI.WalkSpeedSliderContainer.ZIndex = 130; UI.WalkSpeedSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.WalkSpeedSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.WalkSpeedSliderContainer, Color3.fromRGB(100, 180, 255))

UI.WalkSpeedBg = Instance.new("Frame")
UI.WalkSpeedBg.Size = UDim2.new(0, 6, 1, -10); UI.WalkSpeedBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.WalkSpeedBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65); UI.WalkSpeedBg.BorderSizePixel = 0
UI.WalkSpeedBg.Active = true; UI.WalkSpeedBg.ZIndex = 131; UI.WalkSpeedBg.Parent = UI.WalkSpeedSliderContainer
Instance.new("UICorner", UI.WalkSpeedBg).CornerRadius = UDim.new(1, 0)

UI.WalkSpeedThumb = Instance.new("TextButton")
UI.WalkSpeedThumb.Size = UDim2.new(0, 20, 0, 20); UI.WalkSpeedThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.WalkSpeedThumb.BackgroundColor3 = Color3.fromRGB(100, 180, 255); UI.WalkSpeedThumb.Text = ""
UI.WalkSpeedThumb.ZIndex = 132; UI.WalkSpeedThumb.Parent = UI.WalkSpeedSliderContainer
Instance.new("UICorner", UI.WalkSpeedThumb).CornerRadius = UDim.new(1, 0)

UI.CamDistSliderContainer = Instance.new("Frame")
UI.CamDistSliderContainer.Name = "CamDistSliderContainer"
UI.CamDistSliderContainer.Size = UDim2.new(0, 36, 0, 72); UI.CamDistSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.CamDistSliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28); UI.CamDistSliderContainer.BackgroundTransparency = 0.05
UI.CamDistSliderContainer.Visible = false; UI.CamDistSliderContainer.ZIndex = 120; UI.CamDistSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.CamDistSliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.CamDistSliderContainer, Color3.fromRGB(200, 100, 255))

UI.CamDistBg = Instance.new("Frame")
UI.CamDistBg.Size = UDim2.new(0, 6, 1, -10); UI.CamDistBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.CamDistBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65); UI.CamDistBg.BorderSizePixel = 0
UI.CamDistBg.Active = true; UI.CamDistBg.ZIndex = 121; UI.CamDistBg.Parent = UI.CamDistSliderContainer
Instance.new("UICorner", UI.CamDistBg).CornerRadius = UDim.new(1, 0)

UI.CamDistThumb = Instance.new("TextButton")
UI.CamDistThumb.Size = UDim2.new(0, 20, 0, 20); UI.CamDistThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.CamDistThumb.BackgroundColor3 = Color3.fromRGB(200, 100, 255); UI.CamDistThumb.Text = ""
UI.CamDistThumb.ZIndex = 122; UI.CamDistThumb.Parent = UI.CamDistSliderContainer
Instance.new("UICorner", UI.CamDistThumb).CornerRadius = UDim.new(1, 0)

UI.SliderContainer = Instance.new("Frame")
UI.SliderContainer.Name = "SliderContainer"
UI.SliderContainer.Size = UDim2.new(0, 36, 0, 72); UI.SliderContainer.Position = UDim2.new(1, 5, 0, 88)
UI.SliderContainer.BackgroundColor3 = Color3.fromRGB(20, 22, 28); UI.SliderContainer.BackgroundTransparency = 0.05
UI.SliderContainer.Visible = false; UI.SliderContainer.ZIndex = 110; UI.SliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SliderContainer).CornerRadius = UDim.new(0, 8)
addStroke(UI.SliderContainer, Color3.fromRGB(0, 220, 255))

UI.SliderBg = Instance.new("Frame")
UI.SliderBg.Size = UDim2.new(0, 6, 1, -10); UI.SliderBg.Position = UDim2.new(0.5, -3, 0, 5)
UI.SliderBg.BackgroundColor3 = Color3.fromRGB(50, 55, 65); UI.SliderBg.BorderSizePixel = 0
UI.SliderBg.Active = true; UI.SliderBg.ZIndex = 111; UI.SliderBg.Parent = UI.SliderContainer
Instance.new("UICorner", UI.SliderBg).CornerRadius = UDim.new(1, 0)

UI.SliderThumb = Instance.new("TextButton")
UI.SliderThumb.Size = UDim2.new(0, 20, 0, 20); UI.SliderThumb.Position = UDim2.new(0, 10, 0.5, -10)
UI.SliderThumb.BackgroundColor3 = Color3.fromRGB(0, 220, 255); UI.SliderThumb.Text = ""
UI.SliderThumb.ZIndex = 112; UI.SliderThumb.Parent = UI.SliderContainer
Instance.new("UICorner", UI.SliderThumb).CornerRadius = UDim.new(1, 0)

local function updateSliderLayout()
    if currentTab == 1 then
        local speedOn = UI.SpeedSliderContainer.Visible
        if speedOn then UI.SpeedSliderContainer.Position = UDim2.new(1, 5, 0, 7) end
        local nextX = speedOn and 45 or 5
        if UI.WalkSpeedSliderContainer.Visible then UI.WalkSpeedSliderContainer.Position = UDim2.new(1, nextX, 0, 84) end
        if UI.JumpSliderContainer.Visible then UI.JumpSliderContainer.Position = UDim2.new(1, nextX, 0, 10) end
    elseif currentTab == 2 then
        if UI.CamDistSliderContainer.Visible then UI.CamDistSliderContainer.Position = UDim2.new(1, 5, 0, 10) end
        if UI.SliderContainer.Visible then UI.SliderContainer.Position = UDim2.new(1, 5, 0, 88) end
    end
end

local function updateSpeedFromY(absoluteY)
    local bgAbsY = UI.SpeedBg.AbsolutePosition.Y; local bgHeight = UI.SpeedBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    speeds = math.floor(10 - (relativeY * 9) + 0.5)
    UI.SpeedThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateWalkSpeedFromY(absoluteY)
    local bgAbsY = UI.WalkSpeedBg.AbsolutePosition.Y; local bgHeight = UI.WalkSpeedBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    currentWalkSpeed = math.floor(200 - (relativeY * 184))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then char.Humanoid.WalkSpeed = currentWalkSpeed end
    UI.WalkSpeedBtn.Text = "速度: " .. currentWalkSpeed
    UI.WalkSpeedThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateJumpFromY(absoluteY)
    local bgAbsY = UI.JumpBg.AbsolutePosition.Y; local bgHeight = UI.JumpBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    currentJumpPower = math.floor(200 - (relativeY * 150))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then char.Humanoid.JumpPower = currentJumpPower; char.Humanoid.UseJumpPower = true end
    UI.JumpBtn.Text = "跳高: " .. currentJumpPower
    UI.JumpThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateFovFromY(absoluteY)
    local bgAbsY = UI.SliderBg.AbsolutePosition.Y; local bgHeight = UI.SliderBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    currentFov = math.floor(120 - (relativeY * 70))
    if Camera then Camera.FieldOfView = currentFov end
    UI.FovBtn.Text = "视野(FOV): " .. currentFov
    UI.SliderThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local function updateCamDistFromY(absoluteY)
    local bgAbsY = UI.CamDistBg.AbsolutePosition.Y; local bgHeight = UI.CamDistBg.AbsoluteSize.Y
    if bgHeight <= 0 then return end
    local relativeY = math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
    camDistance = math.floor(4 + ((1 - relativeY) * 36) + 0.5)
    UI.CamDistThumb.Position = UDim2.new(0.5, -10, relativeY, -10)
end

local mainDragInput = nil; local mainDragType = nil

track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local pos = input.Position
        if UI.SpeedSliderContainer.Visible then
            local a, s = UI.SpeedSliderContainer.AbsolutePosition, UI.SpeedSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "speed"; updateSpeedFromY(pos.Y); return end
        end
        if UI.WalkSpeedSliderContainer.Visible then
            local a, s = UI.WalkSpeedSliderContainer.AbsolutePosition, UI.WalkSpeedSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "walkspeed"; updateWalkSpeedFromY(pos.Y); return end
        end
        if UI.JumpSliderContainer.Visible then
            local a, s = UI.JumpSliderContainer.AbsolutePosition, UI.JumpSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "jump"; updateJumpFromY(pos.Y); return end
        end
        if UI.SliderContainer.Visible then
            local a, s = UI.SliderContainer.AbsolutePosition, UI.SliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "fov"; updateFovFromY(pos.Y); return end
        end
        if UI.CamDistSliderContainer.Visible then
            local a, s = UI.CamDistSliderContainer.AbsolutePosition, UI.CamDistSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "camdist"; updateCamDistFromY(pos.Y); return end
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

track(UserInputService.InputEnded:Connect(function(input) if input == mainDragInput then mainDragInput = nil; mainDragType = nil end end))

local function getFocusPart()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
end

resetCamera = function()
    if Camera and Camera.CameraType == Enum.CameraType.Scriptable then
        Camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then Camera.CameraSubject = char.Humanoid end
    end
end

updateHeadVisibility = function()
    local char = LocalPlayer.Character
    if not char or soulMode then return end
    local head = char:FindFirstChild("Head"); local hide = (camState == 2)
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            local isHeadPart = false
            if v == head then isHeadPart = true
            elseif v.Parent and v.Parent:IsA("Accessory") then
                local aType = v.Parent.AccessoryType
                if aType == Enum.AccessoryType.Hat or aType == Enum.AccessoryType.Hair or aType == Enum.AccessoryType.Neck then isHeadPart = true end
            end
            if isHeadPart then v.LocalTransparencyModifier = hide and 1 or 0
            elseif camState ~= 0 then v.LocalTransparencyModifier = 0 end
        elseif v:IsA("Decal") and v.Parent == head then v.Transparency = hide and 1 or 0 end
    end
end

track(RunService:BindToRenderStep("TakeoverCameraLoop", Enum.RenderPriority.Last.Value - 1, function(dt)
    if camState == 0 or not loopAlive() then return end
    local focus = getFocusPart(); if not Camera or not focus then return end
    if Camera.CameraType ~= Enum.CameraType.Scriptable then pcall(function() Camera.CameraType = Enum.CameraType.Scriptable end) end
    if camState == 2 then updateHeadVisibility() end
    local focusPos = focus.Position; local rot = CFrame.fromEulerAnglesYXZ(math.rad(camPitch), math.rad(camYaw), 0)
    if camState == 1 then
        local offset = rot.LookVector * -camDistance; local targetPos = focusPos + offset
        local rp = RaycastParams.new(); local char = LocalPlayer.Character
        if char then rp.FilterDescendantsInstances = {char}; rp.FilterType = Enum.RaycastFilterType.Exclude end
        local ray = workspace:Raycast(focusPos, offset, rp)
        if ray then targetPos = ray.Position + ray.Normal * 0.5 end
        Camera.CFrame = CFrame.lookAt(targetPos, focusPos)
    else Camera.CFrame = CFrame.new(focusPos + Vector3.new(0, 1.2, 0) + rot.LookVector * 1.5) * rot end
end))

local camDragInput = nil
track(UserInputService.InputBegan:Connect(function(input)
    if camState == 0 and not soulMode then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local vp = Camera and Camera.ViewportSize or Vector2.new(800, 600); local pos = input.Position
        for _, cont in pairs({UI.SliderContainer, UI.CamDistSliderContainer, UI.WalkSpeedSliderContainer, UI.JumpSliderContainer, UI.SpeedSliderContainer}) do
            if cont.Visible then
                local p, s = cont.AbsolutePosition, cont.AbsoluteSize
                if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
            end
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
        if soulMode then targetYaw = targetYaw - delta.X; targetPitch = math.clamp(targetPitch - delta.Y, -60, 60)
        else camYaw = camYaw - delta.X; camPitch = math.clamp(camPitch - delta.Y, -60, 60) end
    end
end))

track(UserInputService.InputEnded:Connect(function(input) if input == camDragInput then camDragInput = nil end end))

local function showPage(idx)
    currentTab = idx
    UI.PageBasic.Visible = idx == 1; UI.PageDraw.Visible = idx == 2; UI.PageAdv.Visible = idx == 3; UI.PageEnt.Visible = idx == 4
    UI.BasicTab.BackgroundColor3 = idx == 1 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    UI.BasicTab.TextColor3 = idx == 1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    UI.DrawTab.BackgroundColor3 = idx == 2 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    UI.DrawTab.TextColor3 = idx == 2 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    UI.AdvTab.BackgroundColor3 = idx == 3 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    UI.AdvTab.TextColor3 = idx == 3 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)
    UI.EntTab.BackgroundColor3 = idx == 4 and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(30, 33, 40)
    UI.EntTab.TextColor3 = idx == 4 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 170)

    if idx ~= 1 then
        UI.WalkSpeedSliderContainer.Visible = false; UI.JumpSliderContainer.Visible = false; UI.SpeedSliderContainer.Visible = false
    end
    if idx ~= 2 then UI.SliderContainer.Visible = false; UI.CamDistSliderContainer.Visible = false end
    
    if idx == 1 then UI.MainFrame.Size = UDim2.new(0, 190, 0, 190) 
    elseif idx == 2 then UI.MainFrame.Size = UDim2.new(0, 190, 0, 164) 
    elseif idx == 3 then UI.MainFrame.Size = UDim2.new(0, 190, 0, 160) 
    elseif idx == 4 then UI.MainFrame.Size = UDim2.new(0, 190, 0, 190) end
    updateSliderLayout()
end
UI.BasicTab.MouseButton1Click:Connect(function() showPage(1) end)
UI.DrawTab.MouseButton1Click:Connect(function() showPage(2) end)
UI.AdvTab.MouseButton1Click:Connect(function() showPage(3) end)
UI.EntTab.MouseButton1Click:Connect(function() showPage(4) end)

UI.FovBtn.MouseButton1Click:Connect(function() UI.SliderContainer.Visible = not UI.SliderContainer.Visible; updateSliderLayout() end)
UI.WalkSpeedBtn.MouseButton1Click:Connect(function() UI.WalkSpeedSliderContainer.Visible = not UI.WalkSpeedSliderContainer.Visible; updateSliderLayout() end)
UI.JumpBtn.MouseButton1Click:Connect(function() UI.JumpSliderContainer.Visible = not UI.JumpSliderContainer.Visible; updateSliderLayout() end)

UI.CamBtn.MouseButton1Click:Connect(function()
    if aimMode > 0 then
        aimMode = 0; aimLockTarget = nil; aimLockModel = nil
        UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
        lastListKey = ""
    end
    if watchTarget or watchModel then
        watchTarget = nil; watchModel = nil
        if Camera then
            Camera.CameraType = Enum.CameraType.Custom
            local wc = LocalPlayer.Character
            if wc and wc:FindFirstChild("Humanoid") then Camera.CameraSubject = wc.Humanoid end
        end
    end
    camState = camState + 1; if camState > 2 then camState = 0 end
    if camState == 1 then
        local focus = getFocusPart()
        if focus and Camera then
            local look = Camera.CFrame.LookVector
            camYaw = math.deg(math.atan2(-look.X, -look.Z)); camPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        end
        UI.CamBtn.Text = "相机: 第三人称"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100); UI.CamDistSliderContainer.Visible = true
    elseif camState == 2 then
        UI.CamBtn.Text = "相机: 第一人称"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 0); UI.CamDistSliderContainer.Visible = false
    else
        UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false
        updateHeadVisibility(); resetCamera()
    end
    updateSliderLayout()
end)

--==================== 列表 ====================
local STATE_LABEL = {ok = "正常", invis = "隐身", dead = "死亡", gone = "消失", recovered = "已恢复"}
local STATE_COLOR = {
    ok = Color3.fromRGB(255, 255, 255),
    invis = Color3.fromRGB(255, 200, 80),
    dead = Color3.fromRGB(180, 180, 180),
    gone = Color3.fromRGB(255, 80, 80),
    recovered = Color3.fromRGB(100, 220, 255),
}

local function createListFrame(parent, titleText, closeCallback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 195, 0, 280); frame.Position = UDim2.new(1, 0, 0, 0)
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28); frame.BackgroundTransparency = 0.1
    frame.Visible = false; frame.ZIndex = 150; frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10); addStroke(frame, Color3.fromRGB(0, 220, 140))

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -30, 0, 30); title.BackgroundTransparency = 1
    title.Text = titleText; title.TextColor3 = Color3.fromRGB(0, 230, 150)
    title.Font = Enum.Font.GothamBold; title.TextSize = 13; title.ZIndex = 152; title.Parent = frame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22); closeBtn.Position = UDim2.new(1, -26, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50); closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 12
    closeBtn.ZIndex = 153; closeBtn.Parent = frame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)
    closeBtn.MouseButton1Click:Connect(closeCallback)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -10, 1, -40); scroll.Position = UDim2.new(0, 5, 0, 35)
    scroll.BackgroundTransparency = 1; scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.ZIndex = 152; scroll.Parent = frame
    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 4); layout.SortOrder = Enum.SortOrder.LayoutOrder
    return frame, scroll
end

UI.ListFrame, UI.ScrollingFrame = createListFrame(UI.MainFrame, "玩家列表", function() UI.ListFrame.Visible = false; UI.FollowCtrlFrame.Visible = false end)
UI.ModelListFrame, UI.ModelScrollingFrame = createListFrame(UI.MainFrame, "模型列表", function() UI.ModelListFrame.Visible = false end)

UI.FollowCtrlFrame = Instance.new("Frame")
UI.FollowCtrlFrame.Name = "FollowCtrlFrame"
UI.FollowCtrlFrame.Size = UDim2.new(0, 34, 0, 216); UI.FollowCtrlFrame.Position = UDim2.new(1, 200, 0, 35)
UI.FollowCtrlFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28); UI.FollowCtrlFrame.BackgroundTransparency = 0.1
UI.FollowCtrlFrame.Visible = false; UI.FollowCtrlFrame.ZIndex = 160; UI.FollowCtrlFrame.Parent = UI.MainFrame
Instance.new("UICorner", UI.FollowCtrlFrame).CornerRadius = UDim.new(0, 6); addStroke(UI.FollowCtrlFrame, Color3.fromRGB(79, 255, 152))
local followPad = Instance.new("UIPadding", UI.FollowCtrlFrame)
followPad.PaddingTop = UDim.new(0, 4); followPad.PaddingBottom = UDim.new(0, 4); followPad.PaddingLeft = UDim.new(0, 4); followPad.PaddingRight = UDim.new(0, 4)
local followLayout = Instance.new("UIListLayout", UI.FollowCtrlFrame)
followLayout.Padding = UDim.new(0, 2); followLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function createFollowBtn(text, color, layoutOrder, axis, delta)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 28); btn.BackgroundColor3 = color; btn.BackgroundTransparency = 0.1
    btn.Text = text; btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
    btn.LayoutOrder = layoutOrder; btn.ZIndex = 161; btn.Parent = UI.FollowCtrlFrame
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
resetFollowBtn.MouseButton1Click:Connect(function() followOffsetForward = -1.5; followOffsetRight = 0; followOffsetUp = 1 end)

--==================== 物理/飞行 ====================
local function muteCharacterSounds()
    local char = LocalPlayer.Character; if not char then return end
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

stopPhysics = function()
    flying = false; flyDiagnosticPending = false; flyWasVehicle = false
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    flyAttach = nil; unmuteCharacterSounds()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        local hum = char.Humanoid
        hum.PlatformStand = false
        for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
            if state ~= Enum.HumanoidStateType.Dead then pcall(function() hum:SetStateEnabled(state, true) end) end
        end
        if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end

startPhysics = function()
    flyWasVehicle = false
    local char = LocalPlayer.Character; if not char or not char.Parent then return false, "no_char" end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return false, "no_hum" end
    local attach; local isInVehicle = false
    if hum.SeatPart then
        isInVehicle = true; attach = hum.SeatPart.AssemblyRootPart or hum.SeatPart
        if not attach then attach = hum.SeatPart end
        if not attach then return false, "no_attach" end
        pcall(function() local owner = attach:GetNetworkOwner(); if owner ~= LocalPlayer then attach:SetNetworkOwner(LocalPlayer) end end)
    else
        if hum.RigType == Enum.HumanoidRigType.R6 then attach = char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
        else attach = char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart") end
    end
    if not attach then return false, "no_attach" end
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    if not isInVehicle then
        hum.PlatformStand = true
        if char:FindFirstChild("Animate") then char.Animate.Disabled = true end
        pcall(function() for _, t in pairs(hum:GetPlayingAnimationTracks()) do t:AdjustSpeed(0) end end)
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
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9); bodyVelocity.Velocity = Vector3.new(0, 0.1, 0)
    bodyGyro = Instance.new("BodyGyro", attach)
    bodyGyro.P = 9e4; bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9); bodyGyro.CFrame = attach.CFrame
    flyAttach = attach; flyWasVehicle = isInVehicle
    return true
end

forceStopFly = function()
    if not flying then return end
    flying = false; flyDiagnosticPending = false; flyWasVehicle = false
    UI.FlyBtn.Text = "开启飞行"; UI.FlyBtn.BackgroundColor3 = Color3.fromRGB(180, 160, 40)
    UI.SpeedSliderContainer.Visible = false; stopPhysics(); updateSliderLayout()
end

forceStopAirwalk = function()
    if not airwalkEnabled then return end
    airwalkEnabled = false; if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    UI.AirWalkBtn.Text = "空中走"; UI.AirWalkBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 150)
end

forceStopStick = function()
    if not stickMode then return end
    stickMode = false; stickTarget = nil; stickModel = nil
    if UI.FollowCtrlFrame then UI.FollowCtrlFrame.Visible = false end
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then char.Humanoid.PlatformStand = false end
end

local function toggleSoul(state)
    if state then
        if not Camera then return end
        local char = LocalPlayer.Character; if not char or not char.Parent then return end
        local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        soulMode = true; forceStopFly(); forceStopAirwalk(); forceStopStick()
        if camState ~= 0 then camState = 0; UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false end
        if aimMode > 0 then
            aimMode = 0; aimLockTarget = nil; aimLockModel = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
            local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
        end
        local bp = Instance.new("BodyPosition"); bp.Name = "SoulAnchor"; bp.Position = hrp.Position; bp.MaxForce = Vector3.new(9e9, 9e9, 9e9); bp.Parent = hrp
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then v.LocalTransparencyModifier = 1 end
            if v:IsA("Decal") then v.Transparency = 1 end
        end
        soulCFrame = Camera.CFrame; local look = Camera.CFrame.LookVector
        targetYaw = math.deg(math.atan2(-look.X, -look.Z)); targetPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        soulYaw, soulPitch = targetYaw, targetPitch
        Camera.CameraType = Enum.CameraType.Scriptable
    else
        soulMode = false
        local char = LocalPlayer.Character; local finalCF = Camera and Camera.CFrame
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

forceStopSoul = function()
    if not soulMode then return end
    toggleSoul(false); UI.SoulBtn.Text = "出窍: 关"; UI.SoulBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 60)
end

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() or not soulMode or not Camera then return end
    soulYaw = soulYaw + (targetYaw - soulYaw) * 0.5; soulPitch = soulPitch + (targetPitch - soulPitch) * 0.5
    local rot = CFrame.fromEulerAnglesYXZ(math.rad(soulPitch), math.rad(soulYaw), 0)
    local char = LocalPlayer.Character; local flyDir = Vector3.zero
    if char and char:FindFirstChild("Humanoid") then
        local moveDir = char.Humanoid.MoveDirection
        if moveDir.Magnitude > 0.1 then
            local camLook = Camera.CFrame.LookVector; local camRight = Camera.CFrame.RightVector
            local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
            if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit else flatLook = Vector3.new(0,0,-1) end
            local flatRight = Vector3.new(camRight.X, 0, camRight.Z)
            if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit else flatRight = Vector3.new(1,0,0) end
            local fwd = moveDir:Dot(flatLook); local rgt = moveDir:Dot(flatRight)
            flyDir = camLook * fwd + camRight * rgt
        end
    end
    local up = 0
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then up = up + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then up = up - 1 end
    flyDir = flyDir + Vector3.new(0, up, 0)
    if flyDir.Magnitude > 0.1 then soulCFrame = soulCFrame + flyDir.Unit * (speeds * 30) * 0.1 end
    Camera.CFrame = soulCFrame * rot
end))

--==================== 状态与列表刷新 ====================
local function getCharState(p)
    local char = p.Character
    if char and char.Parent and char:FindFirstChildOfClass("Humanoid") then
        local hum = char:FindFirstChildOfClass("Humanoid"); if hum.Health <= 0 then return "dead", char end
        local maxV = 0
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local tr = math.max(part.Transparency, part.LocalTransparencyModifier or 0); local v = 1 - tr
                if v > maxV then maxV = v end
            end
        end
        if maxV < 0.05 then return "invis", char end
        return "ok", char
    end
    local r = recoveredCache[p]
    if r and r.Parent then local hum = r:FindFirstChildOfClass("Humanoid"); if hum and hum.Health > 0 then return "recovered", r end end
    return "gone", nil
end

local function getListKey()
    local names = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(names, p.Name .. ":" .. getCharState(p)) end
    end
    table.sort(names)
    return tostring(aimLockTarget) .. "_" .. tostring(aimMode) .. "_" .. tostring(stickTarget) .. "_" .. tostring(stickMode) .. "_" .. tostring(watchTarget) .. "_" .. table.concat(names, ",")
end

local function getModelListKey()
    local names = {}
    for model, t in pairs(npcCache) do if model and model.Parent then table.insert(names, model.Name .. "_" .. tostring(t)) end end
    table.sort(names)
    return tostring(aimLockModel) .. "_" .. tostring(aimMode) .. "_" .. tostring(stickModel) .. "_" .. tostring(watchModel) .. "_" .. table.concat(names, ",")
end

local function stopWatching()
    if not watchTarget and not watchModel then return end
    watchTarget = nil; watchModel = nil
    if Camera then
        Camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then Camera.CameraSubject = char.Humanoid end
    end
end

local function startWatching(target)
    if not target then return end
    local isPlayer = typeof(target) == "Instance" and target:IsA("Player")
    local isModel = typeof(target) == "Instance" and target:IsA("Model")
    local char = nil; local focusPart = nil; local hum = nil
    
    if isPlayer then
        char = getCharForPlayer(target); if not char then return end
        hum = char:FindFirstChildOfClass("Humanoid"); focusPart = getModelHRP(char)
    elseif isModel then char = target; hum = target:FindFirstChildOfClass("Humanoid"); focusPart = getModelHRP(target) end
    
    if not focusPart then return end
    if isPlayer and (not hum or hum.Health <= 0) then return end
    if not Camera then return end
    if camState ~= 0 then camState = 0; UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
    if soulMode then toggleSoul(false); UI.SoulBtn.Text = "出窍: 关"; UI.SoulBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 60) end
    if aimMode > 0 then
        aimMode = 0; aimLockTarget = nil; aimLockModel = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
    end
    forceStopFly(); isCameraLocked = false
    if isPlayer then watchTarget = target; watchModel = nil else watchModel = target; watchTarget = nil end
    Camera.CameraType = Enum.CameraType.Custom; Camera.CameraSubject = hum or focusPart
end

refreshList = function(force)
    refreshRecoveredCache()
    if watchTarget then local wc = getCharForPlayer(watchTarget); local wh = wc and wc:FindFirstChildOfClass("Humanoid"); if not wh or wh.Health <= 0 then stopWatching() end end
    if stickMode and stickTarget then local sc = getCharForPlayer(stickTarget); local sh = sc and sc:FindFirstChildOfClass("Humanoid"); if not sh or sh.Health <= 0 then forceStopStick() end end
    if aimMode == 2 and aimLockTarget then local ac = getCharForPlayer(aimLockTarget); local ah = ac and ac:FindFirstChildOfClass("Humanoid"); if not ah or ah.Health <= 0 then aimMode = 0; aimLockTarget = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150) end end
    local key = getListKey()
    if not force and key == lastListKey then return end
    lastListKey = key
    for _, c in pairs(UI.ScrollingFrame:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local count = 0
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            count = count + 1
            local state = getCharState(p); local canAct = (state == "ok" or state == "invis" or state == "recovered")
            local f = Instance.new("Frame", UI.ScrollingFrame)
            f.Size, f.BackgroundColor3, f.LayoutOrder, f.ZIndex = UDim2.new(1, -4, 0, 30), Color3.fromRGB(30, 33, 40), count, 152
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
            
            local n = Instance.new("TextLabel", f)
            n.Size, n.BackgroundTransparency, n.TextColor3, n.Font, n.TextSize, n.Position, n.ZIndex = UDim2.new(1, -145, 1, 0), 1, (aimMode == 2 and aimLockTarget == p) and Color3.fromRGB(255, 100, 100) or (STATE_COLOR[state] or Color3.fromRGB(255,255,255)), Enum.Font.SourceSansBold, 12, UDim2.new(0, 4, 0, 0), 153
            n.Text = p.Name .. " [" .. (STATE_LABEL[state] or "?") .. "]"; n.TextXAlignment = Enum.TextXAlignment.Left; n.TextTruncate = Enum.TextTruncate.AtEnd

            local hbIdx = playerHitboxIndices[p] or 1
            local fanBtn = Instance.new("TextButton", f)
            fanBtn.Size, fanBtn.Position, fanBtn.BackgroundColor3, fanBtn.Text, fanBtn.TextColor3, fanBtn.Font, fanBtn.TextSize, fanBtn.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -141, 0, 4), hbIdx > 1 and Color3.fromRGB(200, 100, 200) or Color3.fromRGB(80, 80, 90), hbIdx > 1 and hitboxNames[hbIdx] or "范", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", fanBtn).CornerRadius = UDim.new(0, 4)
            fanBtn.MouseButton1Click:Connect(function()
                if not canAct then return end
                local currentIdx = playerHitboxIndices[p] or 1; local nextIdx = (currentIdx % #hitboxMultipliers) + 1; playerHitboxIndices[p] = nextIdx
                local c = getCharForPlayer(p); if c then if nextIdx == 1 then restoreHitbox(c, false) else applyHitbox(c, nextIdx, false) end end
                refreshList(true)
            end)

            local lk = Instance.new("TextButton", f)
            local isAimLocked = (aimMode == 2 and aimLockTarget == p)
            lk.Size, lk.Position, lk.BackgroundColor3, lk.Text, lk.TextColor3, lk.Font, lk.TextSize, lk.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -115, 0, 4), isAimLocked and Color3.fromRGB(255, 100, 100) or (canAct and Color3.fromRGB(60, 90, 150) or Color3.fromRGB(50, 50, 50)), isAimLocked and "解" or "锁", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", lk).CornerRadius = UDim.new(0, 4)
            lk.MouseButton1Click:Connect(function()
                if not canAct and not isAimLocked then return end
                if aimMode == 2 and aimLockTarget == p then
                    aimMode = 0; aimLockTarget = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
                    if not flying and not soulMode and camState == 0 and not watchTarget then resetCamera() end
                else
                    local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
                    if soulMode then forceStopSoul() end
                    if watchTarget then stopWatching() end
                    if camState ~= 0 then camState = 0; UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
                    aimMode = 2; aimLockTarget = p; aimLockModel = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                end
                refreshList(true)
            end)

            local w = Instance.new("TextButton", f)
            w.Size, w.Position, w.BackgroundColor3, w.Text, w.TextColor3, w.Font, w.TextSize, w.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -89, 0, 4), (watchTarget == p) and Color3.fromRGB(0, 200, 255) or (canAct and Color3.fromRGB(50, 120, 160) or Color3.fromRGB(50, 50, 50)), (watchTarget == p) and "停" or "视", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", w).CornerRadius = UDim.new(0, 4)
            w.MouseButton1Click:Connect(function()
                if not canAct and watchTarget ~= p then return end
                if watchTarget == p then stopWatching() else startWatching(p) end
                refreshList(true)
            end)

            local s = Instance.new("TextButton", f)
            local isFollowing = (stickMode and stickTarget == p)
            s.Size, s.Position, s.BackgroundColor3, s.Text, s.TextColor3, s.Font, s.TextSize, s.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -63, 0, 4), isFollowing and Color3.fromRGB(79, 255, 152) or (canAct and Color3.fromRGB(180, 120, 40) or Color3.fromRGB(50, 50, 50)), isFollowing and "停" or "跟", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", s).CornerRadius = UDim.new(0, 4)
            s.MouseButton1Click:Connect(function()
                if stickMode and stickTarget == p then forceStopStick(); refreshList(true); return end
                if not canAct then return end
                local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
                forceStopFly(); forceStopAirwalk()
                if soulMode then forceStopSoul() end
                stickTarget = p; stickModel = nil; stickMode = true; UI.FollowCtrlFrame.Visible = UI.ListFrame.Visible; refreshList(true)
            end)

            local t = Instance.new("TextButton", f)
            t.Size, t.Position, t.BackgroundColor3, t.Text, t.TextColor3, t.Font, t.TextSize, t.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -37, 0, 4), canAct and Color3.fromRGB(180, 120, 40) or Color3.fromRGB(50, 50, 50), "传", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
            Instance.new("UICorner", t).CornerRadius = UDim.new(0, 4)
            t.MouseButton1Click:Connect(function()
                if not canAct then return end
                local myChar = LocalPlayer.Character; if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
                local targetChar = getCharForPlayer(p); local thrp = targetChar and (targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChildWhichIsA("BasePart"))
                if thrp then
                    forceStopFly(); myChar.HumanoidRootPart.CFrame = thrp.CFrame * CFrame.new(0, 0, 4)
                    if t.Parent then t.Text = "OK"; task.wait(1); if t.Parent then t.Text = "传" end end
                end
            end)
        end
    end
    UI.ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

refreshModelList = function(force)
    if watchModel then if not watchModel.Parent then stopWatching() end end
    if stickMode and stickModel then if not stickModel.Parent then forceStopStick() end end
    if aimMode == 2 and aimLockModel then if not aimLockModel.Parent then aimMode = 0; aimLockModel = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150) end end
    local key = getModelListKey()
    if not force and key == lastModelListKey then return end
    lastModelListKey = key
    
    for _, c in pairs(UI.ModelScrollingFrame:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local sortedModels = {}
    for model, time in pairs(npcCache) do if model and model.Parent then table.insert(sortedModels, {model = model, time = time}) end end
    table.sort(sortedModels, function(a, b) return a.time < b.time end)

    local count = 0
    for _, data in ipairs(sortedModels) do
        local model = data.model; count = count + 1
        local f = Instance.new("Frame", UI.ModelScrollingFrame)
        f.Size, f.BackgroundColor3, f.LayoutOrder, f.ZIndex = UDim2.new(1, -4, 0, 30), Color3.fromRGB(30, 33, 40), count, 152
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
        
        local n = Instance.new("TextLabel", f)
        n.Size, n.BackgroundTransparency, n.TextColor3, n.Font, n.TextSize, n.Position, n.ZIndex = UDim2.new(1, -145, 1, 0), 1, (aimMode == 2 and aimLockModel == model) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255), Enum.Font.SourceSansBold, 12, UDim2.new(0, 4, 0, 0), 153
        n.Text = model.Name; n.TextXAlignment = Enum.TextXAlignment.Left; n.TextTruncate = Enum.TextTruncate.AtEnd

        local hbIdx = modelHitboxIndices[model] or 1
        local fanBtn = Instance.new("TextButton", f)
        fanBtn.Size, fanBtn.Position, fanBtn.BackgroundColor3, fanBtn.Text, fanBtn.TextColor3, fanBtn.Font, fanBtn.TextSize, fanBtn.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -141, 0, 4), hbIdx > 1 and Color3.fromRGB(200, 100, 200) or Color3.fromRGB(80, 80, 90), hbIdx > 1 and hitboxNames[hbIdx] or "范", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
        Instance.new("UICorner", fanBtn).CornerRadius = UDim.new(0, 4)
        fanBtn.MouseButton1Click:Connect(function()
            local currentIdx = modelHitboxIndices[model] or 1; local nextIdx = (currentIdx % #hitboxMultipliers) + 1; modelHitboxIndices[model] = nextIdx
            if nextIdx == 1 then restoreHitbox(model, true) else applyHitbox(model, nextIdx, true) end
            refreshModelList(true)
        end)

        local lk = Instance.new("TextButton", f)
        local isAimLocked = (aimMode == 2 and aimLockModel == model)
        lk.Size, lk.Position, lk.BackgroundColor3, lk.Text, lk.TextColor3, lk.Font, lk.TextSize, lk.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -115, 0, 4), isAimLocked and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(60, 90, 150), isAimLocked and "解" or "锁", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
        Instance.new("UICorner", lk).CornerRadius = UDim.new(0, 4)
        lk.MouseButton1Click:Connect(function()
            if aimMode == 2 and aimLockModel == model then
                aimMode = 0; aimLockModel = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
                if not flying and not soulMode and camState == 0 and not watchTarget then resetCamera() end
            else
                local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
                if soulMode then forceStopSoul() end
                if watchTarget or watchModel then stopWatching() end
                if camState ~= 0 then camState = 0; UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
                aimMode = 2; aimLockModel = model; aimLockTarget = nil; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
            end
            refreshModelList(true)
        end)

        local w = Instance.new("TextButton", f)
        w.Size, w.Position, w.BackgroundColor3, w.Text, w.TextColor3, w.Font, w.TextSize, w.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -89, 0, 4), (watchModel == model) and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(50, 120, 160), (watchModel == model) and "停" or "视", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
        Instance.new("UICorner", w).CornerRadius = UDim.new(0, 4)
        w.MouseButton1Click:Connect(function() if watchModel == model then stopWatching() else startWatching(model) end; refreshModelList(true) end)

        local s = Instance.new("TextButton", f)
        local isFollowing = (stickMode and stickModel == model)
        s.Size, s.Position, s.BackgroundColor3, s.Text, s.TextColor3, s.Font, s.TextSize, s.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -63, 0, 4), isFollowing and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(180, 120, 40), isFollowing and "停" or "跟", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
        Instance.new("UICorner", s).CornerRadius = UDim.new(0, 4)
        s.MouseButton1Click:Connect(function()
            if stickMode and stickModel == model then forceStopStick(); refreshModelList(true); return end
            local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
            forceStopFly(); forceStopAirwalk()
            if soulMode then forceStopSoul() end
            stickModel = model; stickTarget = nil; stickMode = true; UI.FollowCtrlFrame.Visible = UI.ModelListFrame.Visible; refreshModelList(true)
        end)

        local t = Instance.new("TextButton", f)
        t.Size, t.Position, t.BackgroundColor3, t.Text, t.TextColor3, t.Font, t.TextSize, t.ZIndex = UDim2.new(0, 24, 0, 22), UDim2.new(1, -37, 0, 4), Color3.fromRGB(180, 120, 40), "传", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 11, 153
        Instance.new("UICorner", t).CornerRadius = UDim.new(0, 4)
        t.MouseButton1Click:Connect(function()
            local myChar = LocalPlayer.Character; if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
            local thrp = getModelHRP(model)
            if thrp then forceStopFly(); myChar.HumanoidRootPart.CFrame = thrp.CFrame * CFrame.new(0, 0, 4); if t.Parent then t.Text = "OK"; task.wait(1); if t.Parent then t.Text = "传" end end end
        end)
    end
    UI.ModelScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

--==================== 飞行渲染 ====================
track(RunService.RenderStepped:Connect(function()
    if not loopAlive() then return end
    local char = LocalPlayer.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"); if not hrp then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum or not Camera then return end

    if flyDiagnosticPending then
        local elapsed = os.clock() - flyStartTime
        if elapsed > 0.6 then
            flyDiagnosticPending = false
            local currentAttach = flyAttach
            if currentAttach and currentAttach.Parent and flyStartPos then
                if (currentAttach.Position - flyStartPos).Magnitude < 0.3 then
                    forceStopFly(); UI.FlyBtn.Text = "载具飞行被服务端拒绝"
                    task.spawn(function() task.wait(1.6); if UI.FlyBtn.Parent and UI.FlyBtn.Text == "载具飞行被服务端拒绝" then UI.FlyBtn.Text = "开启飞行" end end)
                end
            end
        end
    end

    if stickMode and (stickTarget or stickModel) then
        local thrp = nil
        if stickTarget then local tchar = getCharForPlayer(stickTarget); thrp = tchar and getHRP(tchar)
        elseif stickModel then thrp = getModelHRP(stickModel) end
        if thrp then
            local baseCF = thrp.CFrame * CFrame.new(followOffsetRight, followOffsetUp, -followOffsetForward)
            local targetCF = baseCF + thrp.AssemblyLinearVelocity * 0.1
            char:PivotTo(targetCF); hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero; hum.PlatformStand = true
            return
        end
    end

    if not flying then return end
    soundCheckCounter = soundCheckCounter + 1
    if soundCheckCounter >= 60 then soundCheckCounter = 0; muteCharacterSounds() end
    if not bodyVelocity or not bodyVelocity.Parent or not bodyGyro or not bodyGyro.Parent then local ok = startPhysics(); if not ok then forceStopFly() end; return end
    if hum.SeatPart == nil and flyAttach ~= char:FindFirstChild("UpperTorso") and flyAttach ~= char:FindFirstChild("Torso") and flyAttach ~= hrp then local ok = startPhysics(); if not ok then forceStopFly() end; return end
    if hum.SeatPart and flyAttach ~= hum.SeatPart.AssemblyRootPart and flyAttach ~= hum.SeatPart then local ok = startPhysics(); if not ok then forceStopFly() end; return end
    if aimMode > 0 and not hum.SeatPart then bodyGyro.MaxTorque = Vector3.zero else bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9) end
    local moveDir = hum.MoveDirection
    local up = 0
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then up = up + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then up = up - 1 end
    local fullLook = Camera.CFrame.LookVector; local fullRight = Camera.CFrame.RightVector
    local flatLook = Vector3.new(fullLook.X, 0, fullLook.Z); if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end; flatLook = flatLook.Unit
    local flatRight = Vector3.new(fullRight.X, 0, fullRight.Z); if flatRight.Magnitude < 0.01 then flatRight = Vector3.new(1, 0, 0) end; flatRight = flatRight.Unit
    local flyDir = Vector3.zero
    if moveDir.Magnitude > 0.1 then local fwd = moveDir:Dot(flatLook); local rgt = moveDir:Dot(flatRight); flyDir = fullLook * fwd + fullRight * rgt end
    flyDir = flyDir + Vector3.new(0, up, 0)
    local targetVel = flyDir.Magnitude > 0.1 and (flyDir.Unit * (speeds * 50)) or Vector3.new(0, 0.1, 0)
    bodyVelocity.Velocity = targetVel
    if flyAttach and flyDir.Magnitude > 0.1 and flyAttach.Parent then
        local actualVel = flyAttach.AssemblyLinearVelocity.Magnitude; local expected = speeds * 50
        if actualVel < expected * 0.3 then
            local forceStep = flyDir.Unit * math.min(expected * 0.016, 3)
            pcall(function()
                if hum.SeatPart then
                    local vehicleModel = hum.SeatPart:FindFirstAncestorOfClass("Model")
                    if vehicleModel then vehicleModel:PivotTo(vehicleModel:GetPivot() + forceStep) else flyAttach.CFrame = flyAttach.CFrame + forceStep end
                else flyAttach.CFrame = flyAttach.CFrame + forceStep end
            end)
        end
    end
    if hum.SeatPart then local currentPos = flyAttach.Position; bodyGyro.CFrame = CFrame.new(currentPos, currentPos + flatLook)
    else
        local flat = Vector3.new(fullLook.X, 0, fullLook.Z)
        if flat.Magnitude > 0.01 and flyAttach and flyAttach.Parent then bodyGyro.CFrame = CFrame.new(flyAttach.Position, flyAttach.Position + flat.Unit) end
    end
end))

--==================== 按钮 ====================
UI.FlyBtn.MouseButton1Click:Connect(function()
    if not flying then
        local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local ok, reason = startPhysics()
        if ok then
            flying = true; UI.FlyBtn.Text = "飞行中"; UI.FlyBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            if currentTab == 1 then UI.SpeedSliderContainer.Visible = true end
            if flyWasVehicle and flyAttach then flyStartTime = os.clock(); flyStartPos = flyAttach.Position; flyDiagnosticPending = true end
        else
            local msg = "无法飞行"
            if reason == "anchored" then msg = "载具锚定不可飞" elseif reason == "server_owned" then msg = "服务端拒绝载具" elseif reason == "no_attach" then msg = "无载具部件" end
            UI.FlyBtn.Text = msg
            task.spawn(function() task.wait(1.4); if UI.FlyBtn.Parent and UI.FlyBtn.Text == msg then UI.FlyBtn.Text = "开启飞行" end end)
        end
    else
        forceStopFly()
        if camState == 0 and not soulMode and not watchTarget and not watchModel and aimMode == 0 then resetCamera() end
    end
    updateSliderLayout()
end)

UI.NoclipBtn.MouseButton1Click:Connect(function()
    noclip = not noclip
    UI.NoclipBtn.Text = noclip and "穿墙中" or "穿墙模式"
    UI.NoclipBtn.BackgroundColor3 = noclip and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(80, 80, 90)
    local char = LocalPlayer.Character; if not char then return end
    if noclip then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end; v.CanCollide = false end
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then
            local vehicleModel = hum.SeatPart:FindFirstAncestorOfClass("Model")
            if vehicleModel then
                for _, v in pairs(vehicleModel:GetDescendants()) do
                    if v:IsA("BasePart") then if originalCollides[v] == nil then originalCollides[v] = v.CanCollide end; v.CanCollide = false end
                end
            end
        end
        noclipScanAccum = 999
    else
        for part, orig in pairs(originalCollides) do if part and part.Parent then pcall(function() part.CanCollide = orig end) end end
        originalCollides = {}; restoreEnvCollides()
    end
end)

UI.AimBtn.MouseButton1Click:Connect(function()
    if aimMode == 1 then
        aimMode = 0; UI.AimBtn.Text = "随机自瞄: 关"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
        if not flying and not soulMode and camState == 0 and not watchTarget and not watchModel then resetCamera() end
    else
        local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        if soulMode then forceStopSoul() end
        if watchTarget or watchModel then stopWatching() end
        if camState ~= 0 then camState = 0; UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
        aimMode = 1; aimLockTarget = nil; aimLockModel = nil; UI.AimBtn.Text = "随机自瞄: 硬"; UI.AimBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

UI.PlayerHitboxBtn.MouseButton1Click:Connect(function()
    playerHitboxIndex = (playerHitboxIndex % #hitboxMultipliers) + 1
    UI.PlayerHitboxBtn.Text = "玩家: " .. hitboxNames[playerHitboxIndex]
    for _, plr in pairs(Players:GetPlayers()) do if plr ~= LocalPlayer then playerHitboxIndices[plr] = playerHitboxIndex end end
    updatePlayers()
end)

UI.NPCHitboxBtn.MouseButton1Click:Connect(function()
    npcHitboxIndex = (npcHitboxIndex % #hitboxMultipliers) + 1
    UI.NPCHitboxBtn.Text = "模型: " .. hitboxNames[npcHitboxIndex]
    if npcHitboxIndex == 1 then
        for char in pairs(originalNPCSizes) do restoreHitbox(char, true) end
    else
        -- 核心修复：点击放大时先强制全图重扫，填满缓存
        for _, obj in ipairs(workspace:GetDescendants()) do if obj:IsA("Model") then registerNPC(obj) end end
        for model in pairs(npcCache) do if model and model.Parent then applyHitbox(model, npcHitboxIndex, true) end end
    end
end)

UI.HitboxAimBtn.MouseButton1Click:Connect(function()
    if aimMode > 0 and (aimLockTarget or aimLockModel) then
        local targetModel = nil
        if aimLockTarget then targetModel = getCharForPlayer(aimLockTarget) elseif aimLockModel then targetModel = aimLockModel end
        if targetModel then
            if hitboxAimTarget == targetModel then
                restoreHitbox(targetModel, true); hitboxAimTarget = nil; UI.HitboxAimBtn.Text = "准星放大"; UI.HitboxAimBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 200)
            else
                if hitboxAimTarget then restoreHitbox(hitboxAimTarget, true) end
                hitboxAimTarget = targetModel; applyHitbox(targetModel, 4, true); UI.HitboxAimBtn.Text = "恢复碰"; UI.HitboxAimBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            end
            return
        end
    end
    if hitboxAimTarget then
        restoreHitbox(hitboxAimTarget, true); hitboxAimTarget = nil; UI.HitboxAimBtn.Text = "准星放大"; UI.HitboxAimBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 200); return
    end
    if not Camera then return end
    local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = {LocalPlayer.Character}
    local ray = workspace:Raycast(Camera.CFrame.Position, Camera.CFrame.LookVector * 2000, rp)
    if ray and ray.Instance then
        local model = ray.Instance:FindFirstAncestorOfClass("Model")
        if model then
            if Players:GetPlayerFromCharacter(model) or model:FindFirstChildOfClass("Humanoid") or npcCache[model] then
                hitboxAimTarget = model; applyHitbox(model, 4, true); UI.HitboxAimBtn.Text = "恢复碰"; UI.HitboxAimBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152); return
            end
        end
    end
    UI.HitboxAimBtn.Text = "未瞄准"; task.wait(1); if UI.HitboxAimBtn.Parent then UI.HitboxAimBtn.Text = "准星放大" end
end)

UI.OpenListBtn.MouseButton1Click:Connect(function()
    UI.ListFrame.Visible = not UI.ListFrame.Visible
    if UI.ListFrame.Visible then
        UI.ModelListFrame.Visible = false -- 互斥
        refreshList(true); if stickMode and stickTarget then UI.FollowCtrlFrame.Visible = true end
    else UI.FollowCtrlFrame.Visible = false end
end)

UI.OpenModelListBtn.MouseButton1Click:Connect(function()
    UI.ModelListFrame.Visible = not UI.ModelListFrame.Visible
    if UI.ModelListFrame.Visible then
        UI.ListFrame.Visible = false -- 互斥
        for _, obj in ipairs(workspace:GetDescendants()) do if obj:IsA("Model") then registerNPC(obj) end end
        refreshModelList(true); if stickMode and stickModel then UI.FollowCtrlFrame.Visible = true end
    else UI.FollowCtrlFrame.Visible = false end
end)

UI.AirWalkBtn.MouseButton1Click:Connect(function()
    if airwalkEnabled then forceStopAirwalk(); return end
    local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    airwalkEnabled = true; forceStopFly(); forceStopStick(); resetCamera()
    local hrp = char.HumanoidRootPart
    airwalkPlate = Instance.new("Part"); airwalkPlate.Name = "AirWalkPlate_V4"; airwalkPlate.Size = Vector3.new(1000, 2, 1000)
    airwalkPlate.Position = Vector3.new(hrp.Position.X, hrp.Position.Y - 3.2, hrp.Position.Z)
    airwalkPlate.Anchored = true; airwalkPlate.CanCollide = true; airwalkPlate.Transparency = 1; airwalkPlate.Material = Enum.Material.SmoothPlastic; airwalkPlate.Parent = workspace
    UI.AirWalkBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152); UI.AirWalkBtn.Text = "行走开启"
end)

UI.AntiTPBtn.MouseButton1Click:Connect(function()
    antiTPEnabled = not antiTPEnabled; UI.AntiTPBtn.Text = antiTPEnabled and "防瞬移: 开" or "防瞬移: 关"
    UI.AntiTPBtn.BackgroundColor3 = antiTPEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(80, 150, 120)
    if antiTPEnabled then lastTPCheckCF = CFrame.new() end
end)

UI.AntiServerBtn.MouseButton1Click:Connect(function()
    antiServerEnabled = not antiServerEnabled; UI.AntiServerBtn.Text = antiServerEnabled and "防切服: 开" or "防切服: 关"
    UI.AntiServerBtn.BackgroundColor3 = antiServerEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 50, 150)
end)

UI.NativePopupBtn.MouseButton1Click:Connect(function()
    nativePopupBlockEnabled = not nativePopupBlockEnabled; UI.NativePopupBtn.Text = nativePopupBlockEnabled and "防购买弹窗: 开" or "防购买弹窗: 关"
    UI.NativePopupBtn.BackgroundColor3 = nativePopupBlockEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 50, 150)
end)

UI.ZeroPromptBtn.MouseButton1Click:Connect(function()
    toggleZeroPrompt(not zeroPromptEnabled); UI.ZeroPromptBtn.Text = zeroPromptEnabled and "零延迟: 开" or "零延迟: 关"
    UI.ZeroPromptBtn.BackgroundColor3 = zeroPromptEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 50, 150)
end)

--==================== 点击倍数按钮 (原生事件接管版) ====================
UI.Click100Btn.MouseButton1Down:Connect(function()
    x100State.holdStart = tick()
    x100State.holdTriggered = false
    task.spawn(function()
        task.wait(1)
        if x100State.holdStart and tick() - x100State.holdStart >= 0.95 then
            x100State.holdTriggered = true
            x100State.enabled = false
            unhookClickX100()
            UI.Click100Btn.Text = "点击倍数: 关"
            UI.Click100Btn.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
        end
    end)
end)

UI.Click100Btn.MouseButton1Up:Connect(function()
    if x100State.holdStart then
        local holdTime = tick() - x100State.holdStart
        x100State.holdStart = nil
        if not x100State.holdTriggered and holdTime < 1 then
            UI.ClickMultiplierDialog.Visible = not UI.ClickMultiplierDialog.Visible
            UI.ClickMultiplierBox.Text = tostring(x100State.multiplier)
        end
    end
end)

--==================== 全图触碰/交互/点击 ====================
local function doTouchOnce()
    local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return 0 end
    local hrp = char.HumanoidRootPart; local originalCF = hrp.CFrame
    local targets = {}
    for _, v in pairs(game:GetDescendants()) do if v:IsA("TouchTransmitter") and v.Parent and v.Parent:IsA("BasePart") then table.insert(targets, v.Parent) end end
    local counts = 0
    for i, part in ipairs(targets) do
        if not loopAlive() or not hrp.Parent then break end
        pcall(function() firetouchinterest(hrp, part, 0); firetouchinterest(hrp, part, 1); firetouchinterest(hrp, part, 0); firetouchinterest(hrp, part, 1) end)
        counts = counts + 1
    end
    task.wait(0.05)
    if antiTPEnabled and hrp.Parent then
        if (hrp.Position - originalCF.Position).Magnitude > 35 then hrp.CFrame = originalCF; hrp.AssemblyLinearVelocity = Vector3.zero end
    elseif loopAlive() and hrp.Parent and (hrp.Position - originalCF.Position).Magnitude > 10 then hrp.CFrame = originalCF; hrp.AssemblyLinearVelocity = Vector3.zero end
    return counts
end

local touchIsHeld = false
UI.CollectTouchBtn.MouseButton1Down:Connect(function()
    if isTouchingLoop then isTouchingLoop = false; UI.CollectTouchBtn.Text = "全触碰"; UI.CollectTouchBtn.BackgroundColor3 = Color3.fromRGB(180, 120, 40); return end
    touchIsHeld = true
    task.spawn(function()
        task.wait(2)
        if touchIsHeld then
            isTouchingLoop = true; UI.CollectTouchBtn.Text = "循环触碰中..."; UI.CollectTouchBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            while isTouchingLoop and loopAlive() do doTouchOnce(); task.wait(0.3) end
            UI.CollectTouchBtn.Text = "全触碰"; UI.CollectTouchBtn.BackgroundColor3 = Color3.fromRGB(180, 120, 40); isTouchingLoop = false
        end
    end)
end)

local function doInteractOnce()
    local myChar = LocalPlayer.Character; local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart"); local origCF = myHRP and myHRP.CFrame
    local counts = 0
    for _, v in pairs(game:GetDescendants()) do
        if not loopAlive() then break end
        if v:IsA("ProximityPrompt") then
            pcall(function()
                local bak = {HoldDuration = v.HoldDuration, Enabled = v.Enabled, MaxActivationDistance = v.MaxActivationDistance, RequiresLineOfSight = v.RequiresLineOfSight}
                v.HoldDuration = 0; v.Enabled = true; v.MaxActivationDistance = math.huge; v.RequiresLineOfSight = false
                if fireproximityprompt then fireproximityprompt(v) else pcall(function() v:InputHoldBegin(); task.wait(); v:InputHoldEnd() end) end
                task.wait(0.01)
                v.HoldDuration = bak.HoldDuration; v.Enabled = bak.Enabled; v.MaxActivationDistance = bak.MaxActivationDistance; v.RequiresLineOfSight = bak.RequiresLineOfSight
            end)
            counts = counts + 1
        end
    end
    if antiTPEnabled and myHRP and origCF then
        task.wait(0.05)
        if (myHRP.Position - origCF.Position).Magnitude > 35 then myHRP.CFrame = origCF; myHRP.AssemblyLinearVelocity = Vector3.zero end
    end
    return counts
end

local interactIsHeld = false
UI.CollectInteractBtn.MouseButton1Down:Connect(function()
    if isInteractingLoop then isInteractingLoop = false; UI.CollectInteractBtn.Text = "全交互"; UI.CollectInteractBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 40); return end
    interactIsHeld = true
    task.spawn(function()
        task.wait(2)
        if interactIsHeld then
            isInteractingLoop = true; UI.CollectInteractBtn.Text = "循环交互中..."; UI.CollectInteractBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            while isInteractingLoop and loopAlive() do doInteractOnce(); task.wait(0.3) end
            UI.CollectInteractBtn.Text = "全交互"; UI.CollectInteractBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 40); isInteractingLoop = false
        end
    end)
end)

local function doClickOnce()
    local myChar = LocalPlayer.Character; local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart"); local origCF = myHRP and myHRP.CFrame
    local counts = 0
    for _, v in pairs(game:GetDescendants()) do
        if not loopAlive() then break end
        if v:IsA("ClickDetector") then pcall(function() if fireclickdetector then fireclickdetector(v) end end); counts = counts + 1 end
    end
    if antiTPEnabled and myHRP and origCF then
        task.wait(0.05)
        if (myHRP.Position - origCF.Position).Magnitude > 35 then myHRP.CFrame = origCF; myHRP.AssemblyLinearVelocity = Vector3.zero end
    end
    return counts
end

local clickIsHeld = false
UI.CollectClickBtn.MouseButton1Down:Connect(function()
    if isClickingLoop then isClickingLoop = false; UI.CollectClickBtn.Text = "全点击"; UI.CollectClickBtn.BackgroundColor3 = Color3.fromRGB(140, 100, 200); return end
    clickIsHeld = true
    task.spawn(function()
        task.wait(2)
        if clickIsHeld then
            isClickingLoop = true; UI.CollectClickBtn.Text = "循环点击中..."; UI.CollectClickBtn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
            while isClickingLoop and loopAlive() do doClickOnce(); task.wait(0.3) end
            UI.CollectClickBtn.Text = "全点击"; UI.CollectClickBtn.BackgroundColor3 = Color3.fromRGB(140, 100, 200); isClickingLoop = false
        end
    end)
end)

track(UserInputService.InputEnded:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
        if touchIsHeld then touchIsHeld = false; if not isTouchingLoop then task.spawn(function() local prevText = UI.CollectTouchBtn.Text; UI.CollectTouchBtn.Text = "触碰中..."; local c = doTouchOnce(); UI.CollectTouchBtn.Text = "碰: " .. c .. "个"; task.wait(1); UI.CollectTouchBtn.Text = prevText end) end end
        if interactIsHeld then interactIsHeld = false; if not isInteractingLoop then task.spawn(function() local prevText = UI.CollectInteractBtn.Text; UI.CollectInteractBtn.Text = "交互中..."; local c = doInteractOnce(); UI.CollectInteractBtn.Text = "交: " .. c .. "个"; task.wait(1); UI.CollectInteractBtn.Text = prevText end) end end
        if clickIsHeld then clickIsHeld = false; if not isClickingLoop then task.spawn(function() local prevText = UI.CollectClickBtn.Text; UI.CollectClickBtn.Text = "点击中..."; local c = doClickOnce(); UI.CollectClickBtn.Text = "点: " .. c .. "个"; task.wait(1); UI.CollectClickBtn.Text = prevText end) end end
    end
end))

UI.MagnetBtn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart; UI.MagnetBtn.Text = "吸物中..."
    task.spawn(function()
        local count = 0
        for _, v in pairs(workspace:GetDescendants()) do
            if not loopAlive() or not hrp.Parent then break end
            if v:IsA("BasePart") and not v.Anchored and v.Mass > 0 then
                local model = v:FindFirstAncestorOfClass("Model"); local isChar = false; if model and (Players:GetPlayerFromCharacter(model) or model:FindFirstChildOfClass("Humanoid")) then isChar = true end
                if v ~= hrp and not v:IsDescendantOf(char) and not isChar and v.Size.Magnitude < 50 then pcall(function() v:SetNetworkOwner(LocalPlayer); local bv = v:FindFirstChild("MagnetForce"); if not bv then bv = Instance.new("BodyVelocity"); bv.Name = "MagnetForce"; bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge); bv.P = 5000; bv.Parent = v end; local targetPos = hrp.Position + hrp.CFrame.LookVector * 5; local dir = (targetPos - v.Position).Unit; bv.Velocity = dir * 100 + Vector3.new(0, 15, 0); task.delay(2, function() if bv and bv.Parent then bv:Destroy() end end) end); count = count + 1 end
            end
        end
        if UI.MagnetBtn.Parent then UI.MagnetBtn.Text = "吸: " .. count .. "个"; task.wait(2); if UI.MagnetBtn.Parent then UI.MagnetBtn.Text = "全吸物" end end
    end)
end)

UI.ItemEspBtn.MouseButton1Click:Connect(function()
    itemEspEnabled = not itemEspEnabled; UI.ItemEspBtn.Text = itemEspEnabled and "物透: 开" or "物透: 关"; UI.ItemEspBtn.BackgroundColor3 = itemEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(40, 140, 140)
    if itemEspEnabled then for _, obj in pairs(workspace:GetDescendants()) do if obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") then tryAddItemEsp(obj) end end
    else for obj, data in pairs(itemEspCache) do if data.billboard then data.billboard:Destroy() end end; itemEspCache = {} end
end)

UI.RayBtn.MouseButton1Click:Connect(function() rayEnabled = not rayEnabled; UI.RayBtn.Text = rayEnabled and "射线: 开" or "射线: 关"; UI.RayBtn.BackgroundColor3 = rayEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(80, 140, 200); if not rayEnabled then clearRays() end end)
UI.ModelEspBtn.MouseButton1Click:Connect(function() modelEspEnabled = not modelEspEnabled; UI.ModelEspBtn.Text = modelEspEnabled and "模型透视: 开" or "模型透视: 关"; UI.ModelEspBtn.BackgroundColor3 = modelEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(200, 80, 100); if modelEspEnabled then for _, obj in pairs(workspace:GetDescendants()) do if obj:IsA("Model") then registerNPC(obj) end end; updateNpcHighlights() else for _, hl in pairs(npcHighlights) do pcall(function() hl:Destroy() end) end; npcHighlights = {}; clearRays("npc") end end)
UI.CrosshairBtn.MouseButton1Click:Connect(function() crosshairEnabled = not crosshairEnabled; UI.CrosshairBtn.Text = crosshairEnabled and "准星: 开" or "准星: 关"; UI.CrosshairBtn.BackgroundColor3 = crosshairEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(150, 150, 50); UI.Crosshair.Visible = crosshairEnabled end)
UI.NoShadowBtn.MouseButton1Click:Connect(function() noShadowEnabled = not noShadowEnabled; UI.NoShadowBtn.Text = noShadowEnabled and "去阴影: 开" or "去阴影: 关"; UI.NoShadowBtn.BackgroundColor3 = noShadowEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 100, 120); if noShadowEnabled then Lighting.GlobalShadows = false; for _, v in pairs(workspace:GetDescendants()) do if v:IsA("BasePart") then if originalShadows[v] == nil then originalShadows[v] = v.CastShadow end; v.CastShadow = false end end else Lighting.GlobalShadows = true; for part, s in pairs(originalShadows) do if part and part.Parent then part.CastShadow = s end end; originalShadows = setmetatable({}, {__mode = "k"}) end end)
UI.SoulBtn.MouseButton1Click:Connect(function() if not soulMode and not Camera then return end; if not soulMode and (watchTarget or watchModel) then stopWatching() end; toggleSoul(not soulMode); UI.SoulBtn.Text = soulMode and "出窍: 开" or "出窍: 关"; UI.SoulBtn.BackgroundColor3 = soulMode and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 80, 60); if soulMode then forceStopStick() end end)
UI.EspBtn.MouseButton1Click:Connect(function() espEnabled = not espEnabled; UI.EspBtn.Text = espEnabled and "人透: 开" or "人透: 关"; UI.EspBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 50, 120); if espEnabled then for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then hookPlayerCharacter(p) end end end; updatePlayerESP(); if not espEnabled then clearRays("player"); for _, p in pairs(playerHighlights) do pcall(function() p:Destroy() end) end; playerHighlights = {} end end)
UI.DarkBtn.MouseButton1Click:Connect(function() darkRemoveOn = not darkRemoveOn; UI.DarkBtn.Text = darkRemoveOn and "去黑: 开" or "去黑: 关"; UI.DarkBtn.BackgroundColor3 = darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 120, 50); if darkRemoveOn then captureLighting(); applyDarkOnce(); scanAndHideDarkParts(); startForceOverride() else stopForceOverride(); restoreLighting(); restoreDarkParts(); if noShadowEnabled then Lighting.GlobalShadows = false end end end)

UI.ToggleBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then UI.ListFrame.Visible = false; UI.ModelListFrame.Visible = false; UI.FollowCtrlFrame.Visible = false; UI.SliderContainer.Visible = false; UI.CamDistSliderContainer.Visible = false; UI.WalkSpeedSliderContainer.Visible = false; UI.JumpSliderContainer.Visible = false; UI.SpeedSliderContainer.Visible = false; UI.MainFrame.Size = UDim2.new(0, 190, 0, 30)
    else showPage(currentTab); if stickMode and (stickTarget or stickModel) then UI.FollowCtrlFrame.Visible = true end end
    UI.TabBar.Visible = not isMinimized; UI.ContentFrame.Visible = not isMinimized; updateSliderLayout()
end)

--==================== 重生 ====================
track(LocalPlayer.CharacterAdded:Connect(function()
    stopPhysics(); stopWatching(); restoreEnvCollides()
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false; restoreAllHitboxes()
    originalPlayerSizes, originalNPCSizes, modelHitboxIndices, playerHitboxIndices = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    noclip, aimMode, aimLockTarget, aimLockModel, stickTarget, stickModel = false, 0, nil, nil, nil, nil
    playerHitboxIndex, npcHitboxIndex, soulMode, stickMode, lastListKey, lastModelListKey, originalCollides = 1, 1, false, false, "", "", {}
    if hitboxAimTarget then restoreHitbox(hitboxAimTarget, true); hitboxAimTarget = nil end
    isTouchingLoop, isInteractingLoop, isClickingLoop, touchIsHeld, interactIsHeld, clickIsHeld = false, false, false, false, false, false
    for obj, data in pairs(itemEspCache) do if data.billboard then data.billboard:Destroy() end end; itemEspCache = {}
    if itemEspEnabled then UI.ItemEspBtn.Text = "物透: 关"; UI.ItemEspBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 140); itemEspEnabled = false end
    currentFov = 70; if Camera then Camera.FieldOfView = currentFov end; UI.FovBtn.Text = "视野(FOV): " .. currentFov; UI.SliderThumb.Position = UDim2.new(0.5, -10, 0.5, -10)
    flying, UI.SpeedSliderContainer.Visible, UI.FollowCtrlFrame.Visible = false, false, false; isMinimized = false; UI.TabBar.Visible, UI.ContentFrame.Visible = true, true; showPage(1)
    task.wait(1); if not loopAlive() then return end

    UI.FlyBtn.Text, UI.FlyBtn.BackgroundColor3 = "开启飞行", Color3.fromRGB(180, 160, 40)
    UI.NoclipBtn.Text, UI.NoclipBtn.BackgroundColor3 = "穿墙模式", Color3.fromRGB(80, 80, 90)
    UI.AimBtn.Text, UI.AimBtn.BackgroundColor3 = "随机自瞄: 关", Color3.fromRGB(60, 90, 150)
    UI.PlayerHitboxBtn.Text, UI.NPCHitboxBtn.Text = "玩家: 1x", "模型: 1x"
    UI.AirWalkBtn.Text, UI.AirWalkBtn.BackgroundColor3 = "空中走", Color3.fromRGB(40, 130, 150)
    UI.SoulBtn.Text, UI.SoulBtn.BackgroundColor3 = "出窍: 关", Color3.fromRGB(140, 80, 60)
    UI.CollectTouchBtn.Text, UI.CollectTouchBtn.BackgroundColor3 = "全触碰", Color3.fromRGB(180, 120, 40)
    UI.CollectInteractBtn.Text, UI.CollectInteractBtn.BackgroundColor3 = "全交互", Color3.fromRGB(180, 90, 40)
    UI.CollectClickBtn.Text, UI.CollectClickBtn.BackgroundColor3 = "全点击", Color3.fromRGB(140, 100, 200)
    UI.HitboxAimBtn.Text, UI.HitboxAimBtn.BackgroundColor3 = "准星放大", Color3.fromRGB(200, 50, 200)
    UI.MagnetBtn.Text = "全吸物"
    UI.AntiTPBtn.Text, UI.AntiTPBtn.BackgroundColor3 = antiTPEnabled and "防瞬移: 开" or "防瞬移: 关", antiTPEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(80, 150, 120)
    UI.AntiServerBtn.Text, UI.AntiServerBtn.BackgroundColor3 = antiServerEnabled and "防切服: 开" or "防切服: 关", antiServerEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 50, 150)
    UI.CrosshairBtn.Text, UI.CrosshairBtn.BackgroundColor3 = crosshairEnabled and "准星: 开" or "准星: 关", crosshairEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(150, 150, 50)
    UI.Crosshair.Visible = crosshairEnabled
    UI.EspBtn.Text, UI.EspBtn.BackgroundColor3 = espEnabled and "人透: 开" or "人透: 关", espEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 50, 120)
    UI.ModelEspBtn.Text, UI.ModelEspBtn.BackgroundColor3 = modelEspEnabled and "模型透视: 开" or "模型透视: 关", modelEspEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(200, 80, 100)
    UI.DarkBtn.Text, UI.DarkBtn.BackgroundColor3 = darkRemoveOn and "去黑: 开" or "去黑: 关", darkRemoveOn and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(140, 120, 50)
    UI.NoShadowBtn.Text, UI.NoShadowBtn.BackgroundColor3 = noShadowEnabled and "去阴影: 开" or "去阴影: 关", noShadowEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 100, 120)
    UI.NativePopupBtn.Text, UI.NativePopupBtn.BackgroundColor3 = nativePopupBlockEnabled and "防购买弹窗: 开" or "防购买弹窗: 关", nativePopupBlockEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 50, 150)
    UI.ZeroPromptBtn.Text, UI.ZeroPromptBtn.BackgroundColor3 = zeroPromptEnabled and "零延迟: 开" or "零延迟: 关", zeroPromptEnabled and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(100, 50, 150)
    
    if x100State.enabled then UI.Click100Btn.Text = "点击倍数: " .. x100State.multiplier; UI.Click100Btn.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
    else UI.Click100Btn.Text = "点击倍数: 关"; UI.Click100Btn.BackgroundColor3 = Color3.fromRGB(100, 50, 150) end

    local newChar = LocalPlayer.Character
    if newChar and newChar:FindFirstChildOfClass("Humanoid") then newChar.Humanoid.WalkSpeed = currentWalkSpeed; newChar.Humanoid.JumpPower = currentJumpPower; newChar.Humanoid.UseJumpPower = true end
    UI.WalkSpeedBtn.Text = "速度: " .. currentWalkSpeed; UI.JumpBtn.Text = "跳高: " .. currentJumpPower
    camState = 0; UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false
    if darkRemoveOn then applyDarkOnce(); startForceOverride() end; if noShadowEnabled then Lighting.GlobalShadows = false end
    resetCamera(); UI.ListFrame.Visible, UI.ModelListFrame.Visible = false, false; LocalPlayer.CameraMaxZoomDistance = 128
    if espEnabled then for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then hookPlayerCharacter(p) end end; updatePlayerESP() end
    if modelEspEnabled then updateNpcHighlights() end; updateSliderLayout()
end))

--==================== 关闭 ====================
local function closeAll()
    myLoop.Run = false; for _, c in pairs(myConns) do pcall(function() c:Disconnect() end) end
    if _G.FlyGuiV4_Conns == myConns then _G.FlyGuiV4_Conns = nil end; if _G.FlyGuiV4_Loop == myLoop then _G.FlyGuiV4_Loop = nil end; myConns = {}
    if zeroPromptConn then zeroPromptConn:Disconnect(); zeroPromptConn = nil end; unhookClickX100()
    if soulMode then toggleSoul(false) end; stopWatching(); restoreEnvCollides()
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false; camState = 0; UI.CamBtn.Text = "相机: 关闭"; UI.CamBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 150); UI.CamDistSliderContainer.Visible = false
    stopForceOverride(); stopPhysics(); resetCamera(); clearRays()
    pcall(function() RunService:UnbindFromRenderStep("Aimbot") end); pcall(function() RunService:UnbindFromRenderStep("TakeoverCameraLoop") end)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then local g = char.HumanoidRootPart:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
    for _, v in pairs(playerHighlights) do pcall(function() v:Destroy() end) end; playerHighlights = {}
    for _, v in pairs(npcHighlights) do pcall(function() v:Destroy() end) end; npcHighlights = {}
    if darkRemoveOn then restoreLighting(); restoreDarkParts(); darkRemoveOn = false end
    for part, s in pairs(originalShadows) do if part and part.Parent then pcall(function() part.CastShadow = s end) end end; originalShadows = setmetatable({}, {__mode = "k"})
    for obj, data in pairs(itemEspCache) do if data.billboard then data.billboard:Destroy() end end; itemEspCache = {}
    if char then
        for part, orig in pairs(originalCollides) do if part and part.Parent then pcall(function() part.CanCollide = orig end) end end; originalCollides = {}
        for _, v in pairs(char:GetDescendants()) do if v:IsA("BasePart") then v.LocalTransparencyModifier = 0 end; if v:IsA("Decal") then v.Transparency = 0 end end
        local hum = char:FindFirstChild("Humanoid")
        if hum then hum.PlatformStand = false; for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do pcall(function() hum:SetStateEnabled(state, true) end) end; pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end) end
        if char:FindFirstChild("Animate") then char.Animate.Disabled = false end; pcall(function() char:ScaleTo(1) end)
    end
    if hitboxAimTarget then restoreHitbox(hitboxAimTarget, true); hitboxAimTarget = nil end; restoreAllHitboxes()
    noclip, flying, stickMode, soulMode, espEnabled, modelEspEnabled, noShadowEnabled, crosshairEnabled = false, false, false, false, false, false, false, false
    Lighting.GlobalShadows = true; LocalPlayer.CameraMaxZoomDistance = 128; if Camera then Camera.FieldOfView = 70 end; if UI.ScreenGui then UI.ScreenGui:Destroy() end
end
UI.CloseBtn.MouseButton1Click:Connect(function() pcall(closeAll) end)
