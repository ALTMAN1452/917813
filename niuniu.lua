local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- 【整改】PlayerModule 改为延迟加载，避免高防游戏 WaitForChild 无超时卡死 UI 线程
local PlayerModule = nil
local playerModuleLoadAttempted = false

local function loadPlayerModuleAsync()
    if playerModuleLoadAttempted then return end
    playerModuleLoadAttempted = true
    task.wait(0.2)
    local okPs, ps = pcall(function() return LocalPlayer:WaitForChild("PlayerScripts", 3) end)
    if not okPs or not ps then warn("[喜瓜] PlayerScripts 不可用，移动逻辑降级到 MoveDirection"); return end
    local okPm, pm = pcall(function() return ps:WaitForChild("PlayerModule", 3) end)
    if not okPm or not pm then warn("[喜瓜] PlayerModule 不可用，移动逻辑降级到 MoveDirection"); return end
    local okReq, result = pcall(function() return require(pm) end)
    if okReq and result then
        PlayerModule = result
        print("[喜瓜] PlayerModule 延迟加载成功")
    else
        warn("[喜瓜] PlayerModule require 失败，移动逻辑降级到 MoveDirection")
    end
end

local function getMoveWorldDir()
    if PlayerModule then
        local ok, controls = pcall(function() return PlayerModule:GetControls() end)
        if ok and controls then
            local ok2, mv = pcall(function() return controls:GetMoveVector() end)
            if ok2 and mv and mv.Magnitude > 0.01 then
                local camLook = Camera.CFrame.LookVector
                local camRight = Camera.CFrame.RightVector
                local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
                if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit else flatLook = Vector3.new(0, 0, -1) end
                local flatRight = Vector3.new(camRight.X, 0, camRight.Z)
                if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit else flatRight = Vector3.new(1, 0, 0) end
                local wdir = flatLook * (-mv.Z) + flatRight * mv.X
                if wdir.Magnitude > 0.01 then return wdir.Unit end
            end
        end
    end
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.MoveDirection.Magnitude > 0.1 then return hum.MoveDirection.Unit end
    end
    return Vector3.zero
end

local function getMoveVector()
    if PlayerModule then
        local ok, controls = pcall(function() return PlayerModule:GetControls() end)
        if ok and controls then
            local ok2, mv = pcall(function() return controls:GetMoveVector() end)
            if ok2 and mv then return mv end
        end
    end
    return Vector3.zero
end

local UI = {}

--==================== 全局状态 ====================
local soulMode = false
local soulSpeed = 10 
local touchFlyUp = false
local touchFlyDown = false
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
local flyLockDir = nil
local flyLastPos = nil
local flyMode = "normal"
local flyHoldStart = nil
local flyHoldTriggered = false

-- 玩法模式状态
local ragdollEnabled = false
local spinEnabled = false
local ragdollSpeed = 20
local spinSpeed = 10
local handstandEnabled = false
local handstandSpeed = 18
local orbitEnabled = false
local orbitSpeed = 5
local orbitRadius = 15
local orbitCenter = nil

-- 幽灵模式增强
local ghostHazardBackup = setmetatable({}, {__mode = "k"})
local ghostHookInstalled = false
local hazardKeywords = {"laser", "kill", "death", "damage", "hazard", "trap", "spike", "lava", "acid", "poison", "fire", "burn"}

local interactBackup = {}
local playerListCache = {}
local modelListCache = {}

local ghostModeEnabled = false
local ghostConn = nil
local lockSpeedEnabled = false

local npcFreezeEnabled = false
local npcFreezeBackup = setmetatable({}, {__mode = "k"})
local npcLiftEnabled = false
local npcLiftBackup = setmetatable({}, {__mode = "k"})

local camState = 0
local camDistance = 15 
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

local forceShowSelfEnabled = false
local unlockDistanceEnabled = false

local npcCache = setmetatable({}, {__mode = "k"})
local modelComHistory = setmetatable({}, {__mode = "k"})

local itemEspEnabled = false
local itemEspCache = {}
local rayEnabled = false
local modelEspEnabled = false
local noShadowEnabled = false
local crosshairEnabled = false
local espLines = {}
local espEnabled = false

local singlePlayerEsp = {}
local singleModelEsp = {}
local singlePlayerRay = {}
local singleModelRay = {}

local globalPlayerHitboxMult = 1
local globalNpcHitboxMult = 1
local singlePlayerHitboxMult = {} 
local singleModelHitboxMult = {} 
local singleModelFrozen = {}
local activeHitboxSliderTarget = nil 
local activeHitboxSliderType = nil 
local currentHitboxValue = 1
local hitboxApplyDebounce = nil

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
local recoveredCache = setmetatable({}, {__mode = "k"})

local antiTPEnabled = false 
local lastTPCheckCF = CFrame.new()

local isTouchingLoop = false
local isInteractingLoop = false
local isClickingLoop = false

local nativePopupBlockEnabled = false
local zeroPromptEnabled = false
local zeroPromptConn = nil
local purchaseKillConn = nil

local lastRecoverScanTime = 0
local lastPlayerListRefreshTime = 0
local lastModelListRefreshTime = 0

local x100State = {
    enabled = false,
    multiplier = 100,
    executing = setmetatable({}, {__mode = "k"}),
    conns = setmetatable({}, {__mode = "k"}),
    holdStart = nil,
    holdTriggered = false
}

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

function loopAlive() return myLoop.Run end
function track(conn)
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

--==================== 幽灵模式 hook 拦截 ====================
local function setupGhostHook()
    if ghostHookInstalled then return end
    ghostHookInstalled = true
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if ghostModeEnabled then
                if method == "TakeDamage" or method == "BreakJoints" or method == "Die" then
                    local char = LocalPlayer.Character
                    if char and typeof(self) == "Instance" and self:IsDescendantOf(char) then
                        return
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
    end)
end

local function scanAndDisableHazards()
    if not ghostModeEnabled then return end
    local char = LocalPlayer.Character
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            if not (char and obj:IsDescendantOf(char)) then
                local lower = string.lower(obj.Name)
                local hit = false
                for _, kw in ipairs(hazardKeywords) do
                    if string.find(lower, kw) then hit = true; break end
                end
                if hit then
                    if ghostHazardBackup[obj] == nil then
                        ghostHazardBackup[obj] = {CanTouch = obj.CanTouch, CanCollide = obj.CanCollide}
                    end
                    obj.CanTouch = false
                    obj.CanCollide = false
                end
            end
        end
    end
end

local function restoreHazards()
    for obj, bak in pairs(ghostHazardBackup) do
        if obj and obj.Parent then
            pcall(function() obj.CanTouch = bak.CanTouch; obj.CanCollide = bak.CanCollide end)
        end
    end
    ghostHazardBackup = setmetatable({}, {__mode = "k"})
end

--==================== NPC 控制函数 ====================
function applyNpcFreeze(model)
    if not model or not model.Parent then return end
    if not npcFreezeBackup[model] then npcFreezeBackup[model] = {} end
    local backup = npcFreezeBackup[model]
    
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        if not backup._humanoid then backup._humanoid = {WalkSpeed = hum.WalkSpeed, JumpPower = hum.JumpPower} end
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.UseJumpPower = true
    end
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            if not backup[p] then backup[p] = {Anchored = p.Anchored} end
            p.Anchored = true
        end
    end
end

function releaseNpcFreeze(model)
    if not model then return end
    local backup = npcFreezeBackup[model]
    if not backup then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and backup._humanoid then
        hum.WalkSpeed = backup._humanoid.WalkSpeed
        hum.JumpPower = backup._humanoid.JumpPower
    end
    for k, b in pairs(backup) do
        if typeof(k) == "Instance" and k:IsA("BasePart") and b.Anchored ~= nil then
            if k.Parent then k.Anchored = b.Anchored end
        end
    end
    npcFreezeBackup[model] = nil
end

function applyNpcLift(model)
    if not model or not model.Parent then return end
    local existing = npcLiftBackup[model]
    if existing and existing.bv and existing.bv.Parent then return end
    
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not root then
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then root = p; break end
        end
    end
    if not root then return end
    
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then 
            p.Anchored = false
            p.Massless = false
            pcall(function() p:SetNetworkOwner(LocalPlayer) end)
        end
    end
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(0, math.huge, 0)
    bv.Velocity = Vector3.new(0, 80, 0)
    bv.Parent = root
    npcLiftBackup[model] = {bv = bv, root = root}
end

function releaseNpcLift(model)
    if not model then return end
    local data = npcLiftBackup[model]
    if not data then return end
    if data.bv then pcall(function() data.bv:Destroy() end) end
    npcLiftBackup[model] = nil
end

--==================== 核心逻辑 ====================
function applyHitbox(char, mult, isNPC)
    if not mult or mult <= 1 then restoreHitbox(char, isNPC); return end
    if not char or not char.Parent then return end
    local targetSize = Vector3.new(21, 21, 21) * mult
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

function restoreHitbox(char, isNPC)
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

function restoreAllHitboxes()
    for char in pairs(originalPlayerSizes) do restoreHitbox(char, false) end
    for char in pairs(originalNPCSizes) do restoreHitbox(char, true) end
end

function registerNPC(model)
    if not model or not model:IsA("Model") then return end
    if npcCache[model] then return end
    if model == LocalPlayer.Character then return end
    if Players:GetPlayerFromCharacter(model) then return end
    if isExcluded(model.Name) then return end

    local isMonster = hasMonsterKeyword(model.Name)
    local hasHum = model:FindFirstChildOfClass("Humanoid") ~= nil
    local hasUnanchored = false
    
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and not p.Anchored then hasUnanchored = true; break end
    end

    if hasHum or isMonster or hasUnanchored then
        local magnitude = 0
        local ok, size = pcall(function() return model:GetExtentsSize() end)
        if ok and typeof(size) == "Vector3" then magnitude = size.Magnitude end
        if magnitude >= 1 and magnitude <= 500 then
            npcCache[model] = os.clock()
        end
    end
end

function unregisterNPC(model)
    if not model then return end
    npcCache[model] = nil; modelComHistory[model] = nil
    if npcHighlights[model] then pcall(function() npcHighlights[model]:Destroy() end); npcHighlights[model] = nil end
    if espLines[model] then
        pcall(function() if espLines[model].line then espLines[model].line:Remove() end end)
        pcall(function() if espLines[model].label then espLines[model].label:Destroy() end end)
        espLines[model] = nil
    end
    singleModelEsp[model] = nil; singleModelRay[model] = nil; singleModelHitboxMult[model] = nil
    singleModelFrozen[model] = nil; npcFreezeBackup[model] = nil
    if npcLiftBackup[model] then pcall(function() releaseNpcLift(model) end) end
    if aimLockModel == model then aimMode = 0; aimLockModel = nil end
    if stickModel == model then pcall(function() forceStopStick() end) end
    if watchModel == model then pcall(function() stopWatching() end) end
end

function updatePlayerESP()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local target = nil
            if espEnabled or singlePlayerEsp[p] then target = getCharForPlayer(p) end
            if target then
                if not playerHighlights[p] then
                    pcall(function()
                        local hl = Instance.new("Highlight")
                        hl.Name = "ESP_Highlight"; hl.Adornee = target
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.OutlineColor = Color3.new(1, 1, 1); hl.FillTransparency = 0.5
                        hl.Parent = CoreGui; playerHighlights[p] = hl
                    end)
                elseif playerHighlights[p] then playerHighlights[p].Adornee = target end
                local color = Color3.fromRGB(255, 255, 0)
                if singlePlayerEsp[p] then color = Color3.fromRGB(0, 255, 0) end
                playerHighlights[p].FillColor = color
            elseif playerHighlights[p] then
                pcall(function() playerHighlights[p]:Destroy() end); playerHighlights[p] = nil
            end
        end
    end
end

function updateNpcHighlights()
    if not loopAlive() then return end
    for model, hl in pairs(npcHighlights) do
        if not model or not model.Parent then pcall(function() hl:Destroy() end); npcHighlights[model] = nil end
    end
    if not modelEspEnabled and next(singleModelEsp) == nil then return end
    for model in pairs(npcCache) do
        if not loopAlive() then break end
        if model and model.Parent and (modelEspEnabled or singleModelEsp[model]) then
            local isMonster = hasMonsterKeyword(model.Name)
            if not npcHighlights[model] then
                pcall(function()
                    local hl = Instance.new("Highlight")
                    hl.Name = "ESP_Highlight"; hl.Adornee = model
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.OutlineColor = Color3.new(1, 1, 1); hl.FillTransparency = 0.5
                    hl.Parent = CoreGui; npcHighlights[model] = hl
                end)
            end
            if npcHighlights[model] then
                local color = isMonster and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 100, 100)
                if singleModelEsp[model] then color = Color3.fromRGB(0, 150, 255) end
                npcHighlights[model].FillColor = color
            end
        end
    end
end

function forceStopFly()
    flyLockDir = nil; flyLastPos = nil
    flyMode = "normal"; flyHoldStart = nil; flyHoldTriggered = false
    if not flying then return end
    flying = false; flyDiagnosticPending = false; flyWasVehicle = false
    UI.SpeedSliderContainer.Visible = false
    UI.SoulUpBtn.Visible = false; UI.SoulDownBtn.Visible = false
    touchFlyUp = false; touchFlyDown = false
    stopPhysics(); updateSliderLayout()
end

function forceStopAirwalk()
    if not airwalkEnabled then return end
    airwalkEnabled = false; if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
end

function forceStopStick()
    if not stickMode then return end
    stickMode = false; stickTarget = nil; stickModel = nil
    if UI.FollowCtrlFrame then UI.FollowCtrlFrame.Visible = false end
    if ghostModeEnabled then setNoclipState(false) end
    
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local ap = hrp:FindFirstChild("StickAlignPos")
            if ap then ap:Destroy() end
            local aatt = hrp:FindFirstChild("StickAlignAtt")
            if aatt then aatt:Destroy() end
            local bg = hrp:FindFirstChild("StickBodyGyro")
            if bg then bg:Destroy() end
        end
    end
end

function forceStopSoul()
    if not soulMode then return end
    toggleSoul(false)
end

function resetCamera()
    if Camera and Camera.CameraType == Enum.CameraType.Scriptable then
        Camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then Camera.CameraSubject = char.Humanoid end
    end
end

function updateHeadVisibility()
    local char = LocalPlayer.Character
    if not char or soulMode then return end
    local head = char:FindFirstChild("Head")
    local hide = (camState == 2) and not forceShowSelfEnabled
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

function startPhysics()
    flyWasVehicle = false
    local char = LocalPlayer.Character; if not char or not char.Parent then return false, "no_char" end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return false, "no_hum" end
    local attach; local isInVehicle = false
    if hum.SeatPart then
        isInVehicle = true; attach = hum.SeatPart.AssemblyRootPart or hum.SeatPart
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
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.UseJumpPower = true
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
    flyLastPos = attach.Position
    return true
end

function stopPhysics()
    flying = false; flyDiagnosticPending = false; flyWasVehicle = false; flyLockDir = nil; flyLastPos = nil
    if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
    if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
    flyAttach = nil; unmuteCharacterSounds()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        local hum = char.Humanoid
        hum.PlatformStand = false
        if not soulMode then
            hum.WalkSpeed = currentWalkSpeed
            hum.JumpPower = currentJumpPower
            hum.UseJumpPower = true
        end
        for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
            if state ~= Enum.HumanoidStateType.Dead then pcall(function() hum:SetStateEnabled(state, true) end) end
        end
        if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end

--==================== 基础功能 ====================
function applyZeroPrompt(prompt)
    if prompt and prompt:IsA("ProximityPrompt") and prompt.HoldDuration > 0 then prompt.HoldDuration = 0 end
end

function toggleZeroPrompt(state)
    zeroPromptEnabled = state
    if zeroPromptConn then zeroPromptConn:Disconnect(); zeroPromptConn = nil end
    if zeroPromptEnabled then
        for _, obj in pairs(workspace:GetDescendants()) do applyZeroPrompt(obj) end
        zeroPromptConn = workspace.DescendantAdded:Connect(applyZeroPrompt)
    end
end

function hookSingleCD(cd)
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

function hookClickX100()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ClickDetector") then hookSingleCD(obj) end
    end
end

function unhookClickX100()
    for _, conn in pairs(x100State.conns) do pcall(function() conn:Disconnect() end) end
    x100State.conns = setmetatable({}, {__mode = "k"})
end

track(workspace.DescendantAdded:Connect(function(obj)
    if x100State.enabled and obj:IsA("ClickDetector") then hookSingleCD(obj) end
end))

function killNativePurchasePrompt()
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
                if not gui:IsA("ScreenGui") and not gui:IsA("SurfaceGui") then hideDarkOverlays(gui) end
            end
        end
    end
    hideDarkOverlays(CoreGui)
    hideDarkOverlays(PlayerGui)
end

local function ensurePurchaseKillConn()
    if purchaseKillConn then return end
    if not nativePopupBlockEnabled then return end
    purchaseKillConn = RunService.Heartbeat:Connect(function()
        if not loopAlive() then
            if purchaseKillConn then purchaseKillConn:Disconnect(); purchaseKillConn = nil end
            return
        end
        killNativePurchasePrompt()
    end)
end
local function stopPurchaseKillConn()
    if purchaseKillConn then purchaseKillConn:Disconnect(); purchaseKillConn = nil end
end

function getCharForPlayer(p)
    local c = p.Character
    if c and c.Parent then
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hum then return c end
    end
    local r = recoveredCache[p]
    if r and r.Parent and r:FindFirstChildOfClass("Humanoid") then return r end
    return nil
end

function getModelHRP(model)
    if not model or not model.Parent then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

function getTargetPart(player)
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

function getHRP(char)
    if not char or not char.Parent then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso") or char:FindFirstChildWhichIsA("BasePart")
end

function refreshRecoveredCache()
    local now = os.clock()
    if now - lastRecoverScanTime < 2 then return end
    lastRecoverScanTime = now
    local needed = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local c = p.Character
            if not c or not c.Parent or not c:FindFirstChildOfClass("Humanoid") then needed[p.Name] = p
            else recoveredCache[p] = nil end
        end
    end
    if next(needed) == nil then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and needed[obj.Name] then
            local p = needed[obj.Name]
            if not recoveredCache[p] or not recoveredCache[p].Parent then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum then recoveredCache[p] = obj; needed[p.Name] = nil end
            end
        end
    end
end

function getClosestTarget()
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
                    local sp, onScreen = Camera:WorldToViewportPoint(Camera, tp.Position)
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
function translateName(engName)
    local lowerName = string.lower(engName)
    if translateDict[lowerName] then return translateDict[lowerName] end
    for eng, chn in pairs(translateDict) do
        if string.find(lowerName, eng) then return chn end
    end
    return engName
end

function hasMonsterKeyword(name)
    local lower = string.lower(name)
    for _, kw in ipairs(monsterKeywords) do
        if string.find(lower, kw) then return true end
    end
    return false
end

function isExcluded(name)
    local lower = string.lower(name)
    for _, kw in ipairs(excludeKeywords) do
        if string.find(lower, kw) then return true end
    end
    return false
end

function computeModelCOM(model)
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

function isMovingModelDynamic(model)
    local com = computeModelCOM(model)
    if not com then return false end
    local now = os.clock()
    local rec = modelComHistory[model]
    local moving = false
    if rec then
        local dt = now - rec.t
        if dt >= 0.05 and dt <= 10.0 then
            local speed = (com - rec.c).Magnitude / dt
            if speed > 0.4 then moving = true end
        end
    end
    modelComHistory[model] = {c = com, t = now}
    return moving
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

function needScanPlayers()
    if espEnabled or next(singlePlayerEsp) ~= nil then return true end
    if UI.ListFrame.Visible then return true end
    if globalPlayerHitboxMult > 1 or next(singlePlayerHitboxMult) ~= nil then return true end
    if aimMode > 0 then return true end
    return false
end

function needScanModels()
    if modelEspEnabled or next(singleModelEsp) ~= nil then return true end
    if UI.ModelListFrame.Visible then return true end
    if globalNpcHitboxMult > 1 or next(singleModelHitboxMult) ~= nil then return true end
    return false
end

task.spawn(function()
    while loopAlive() and task.wait(1) do
        if npcFreezeEnabled or npcLiftEnabled then
            local myChar = LocalPlayer.Character
            local myHRP = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChildWhichIsA("BasePart"))
            if myHRP then
                for model in pairs(npcCache) do
                    if model and model.Parent then
                        local nhrp = getModelHRP(model)
                        if nhrp and (nhrp.Position - myHRP.Position).Magnitude < 100 then
                            if npcFreezeEnabled then applyNpcFreeze(model) end
                            if npcLiftEnabled then applyNpcLift(model) end
                        end
                    end
                end
            end
        end
        if needScanPlayers() then
            refreshRecoveredCache()
            if UI.ListFrame.Visible then refreshList() end
            if globalPlayerHitboxMult > 1 or next(singlePlayerHitboxMult) ~= nil then
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer then
                        local c = getCharForPlayer(plr)
                        if c then 
                            local m = singlePlayerHitboxMult[plr] or globalPlayerHitboxMult
                            if m > 1 then applyHitbox(c, m, false) else restoreHitbox(c, false) end 
                        end
                    end
                end
            end
            updatePlayerESP()
        end
        if needScanModels() then
            if UI.ModelListFrame.Visible then refreshModelList() end
            if globalNpcHitboxMult > 1 or next(singleModelHitboxMult) ~= nil then
                local myChar = LocalPlayer.Character
                local myHRP = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChildWhichIsA("BasePart"))
                if myHRP then
                    local myPos = myHRP.Position
                    for model in pairs(npcCache) do
                        if not model or not model.Parent then npcCache[model] = nil
                        else
                            local nhrp = getModelHRP(model)
                            if nhrp and (nhrp.Position - myPos).Magnitude < 100 then 
                                local m = singleModelHitboxMult[model] or globalNpcHitboxMult
                                if m > 1 then applyHitbox(model, m, true) else restoreHitbox(model, true) end 
                            end
                        end
                    end
                end
            end
            updateNpcHighlights()
        end
    end
end)

RunService:BindToRenderStep("Aimbot", Enum.RenderPriority.Camera.Value + 1, function(dt)
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
        if aimMode == 3 then
            if aimLockTarget then
                targetPart = getTargetPart(aimLockTarget)
                local hum = targetPart and targetPart.Parent:FindFirstChildOfClass("Humanoid")
                if not targetPart or not hum or hum.Health <= 0 then aimLockTarget = nil; aimMode = 0 end
            elseif aimLockModel then
                targetPart = getModelHRP(aimLockModel)
                if not targetPart or not aimLockModel.Parent then aimLockModel = nil; aimMode = 0 end
            else aimMode = 0 end
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
            local targetGyroCF = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
            if aimMode == 1 then bg.CFrame = bg.CFrame:Lerp(targetGyroCF, math.clamp(dt * 8, 0, 1))
            else bg.CFrame = targetGyroCF end
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
        local targetCF = CFrame.lookAt(camPos, tp)
        if aimMode == 1 then Camera.CFrame = Camera.CFrame:Lerp(targetCF, math.clamp(dt * 8, 0, 1))
        else Camera.CFrame = targetCF end
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

function restoreEnvCollides()
    for part, c in pairs(noclipEnvCollides) do
        if part and part.Parent then pcall(function() part.CanCollide = c end) end
    end
    noclipEnvCollides = {}
    noclipScanAccum = 0
end

function scanEnvCollide()
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

function noclipTick(dt)
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
    if noclipScanAccum >= 0.15 then noclipScanAccum = 0; scanEnvCollide() end
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

track(RunService.Heartbeat:Connect(function()
    if not antiTPEnabled then return end
    if flying or soulMode or airwalkEnabled then lastTPCheckCF = CFrame.new(); return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        if lastTPCheckCF == CFrame.new() then lastTPCheckCF = hrp.CFrame
        else
            local dist = (hrp.Position - lastTPCheckCF.Position).Magnitude
            if dist > 15 then hrp.CFrame = lastTPCheckCF; hrp.AssemblyLinearVelocity = Vector3.zero
            elseif dist < 8 then lastTPCheckCF = lastTPCheckCF:Lerp(hrp.CFrame, 0.5) end
        end
    else lastTPCheckCF = CFrame.new() end
end))

function tryAddItemEsp(obj)
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
    elseif string.find(lowerName, "drawer") or string.find(lowerName, "cabinet") or string.find(lowerName, "chest") or string.find(lowerName, "locker") or string.find(lowerName, "knob") then color = Color3.fromRGB(255, 150, 50) end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ItemESP_Billboard"; billboard.Size = UDim2.new(0, 120, 0, 24); billboard.StudsOffset = Vector3.new(0, 1.5, 0)
    billboard.AlwaysOnTop = true; billboard.MaxDistance = 1000; billboard.Adornee = part; billboard.Parent = part
    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 1, 0); text.BackgroundTransparency = 1; text.TextColor3 = color
    text.Font = Enum.Font.GothamBold; text.TextSize = 14; text.TextStrokeTransparency = 0.5; text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); text.Text = chineseName; text.Parent = billboard
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
            if data.billboard then data.billboard:Destroy() end; itemEspCache[obj] = nil
        else
            local dist = (data.part.Position - myPos).Magnitude
            if dist < 1000 then data.text.Text = data.name .. " [" .. math.floor(dist) .. "m]" end
        end
    end
end))

function captureLighting()
    originalLighting = {
        FogEnd=Lighting.FogEnd, FogStart=Lighting.FogStart, GlobalShadows=Lighting.GlobalShadows,
        Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient,
        ExposureCompensation=Lighting.ExposureCompensation, ShadowSoftness=Lighting.ShadowSoftness,
        Brightness=Lighting.Brightness, ClockTime=Lighting.ClockTime
    }
end

function checkDarkPart(obj)
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

function scanAndHideDarkParts()
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

function restoreDarkParts()
    for part, t in pairs(hiddenDarkParts) do
        if part and part.Parent then pcall(function() part.Transparency = t end) end
    end
    hiddenDarkParts = setmetatable({}, {__mode = "k"})
end

function applyDarkOnce()
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

function startForceOverride()
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

function stopForceOverride()
    if forceConn then forceConn:Disconnect(); forceConn = nil end
end

function restoreLighting()
    stopForceOverride()
    for k, v in pairs(originalLighting) do pcall(function() Lighting[k] = v end) end
    for obj, data in pairs(hiddenEffects) do
        if obj and obj.Parent then
            for k, v in pairs(data) do pcall(function() obj[k] = v end) end
        end
    end
    hiddenEffects = setmetatable({}, {__mode = "k"})
end

function hookPlayerCharacter(p)
    if p == LocalPlayer then return end
    if playerCharConns[p] then playerCharConns[p]:Disconnect() end
    playerCharConns[p] = p.CharacterAdded:Connect(function()
        task.wait(1)
        if not loopAlive() then return end
        updatePlayerESP()
    end)
end

track(workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") then
        registerNPC(obj)
        if (modelEspEnabled or next(singleModelEsp) ~= nil) and npcCache[obj] and not npcHighlights[obj] then updateNpcHighlights() end
    elseif obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
        registerNPC(obj.Parent)
        if (modelEspEnabled or next(singleModelEsp) ~= nil) and npcCache[obj.Parent] and not npcHighlights[obj.Parent] then updateNpcHighlights() end
    elseif obj:IsA("BasePart") then
        local model = obj:FindFirstAncestorOfClass("Model")
        if model and model ~= workspace then
            registerNPC(model)
            if (modelEspEnabled or next(singleModelEsp) ~= nil) and npcCache[model] and not npcHighlights[model] then updateNpcHighlights() end
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
    singlePlayerEsp[p] = nil; singlePlayerRay[p] = nil; singlePlayerHitboxMult[p] = nil
    if playerHighlights[p] then pcall(function() playerHighlights[p]:Destroy() end); playerHighlights[p] = nil end
    if espLines[p] then
        pcall(function() if espLines[p].line then espLines[p].line:Remove() end end)
        pcall(function() if espLines[p].label then espLines[p].label:Destroy() end end)
        espLines[p] = nil
    end
    if playerListCache[p] then
        local frame = playerListCache[p].frame
        if frame and frame.Parent then frame:Destroy() end
        playerListCache[p] = nil
    end
    if aimLockTarget == p then aimMode = 0; aimLockTarget = nil; lastListKey = "" end
    if stickTarget == p then forceStopStick() end
    if watchTarget == p then stopWatching() end
end))

function createRayForModel(model)
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

function clearRays(filter, respectSingle)
    for key, data in pairs(espLines) do
        local isPlayer = typeof(key) == "Instance" and key:IsA("Player")
        local isModel = typeof(key) == "Instance" and key:IsA("Model")
        local shouldClear = (filter == nil) or (filter == "player" and isPlayer) or (filter == "npc" and isModel)
        if shouldClear then
            local keep = false
            if respectSingle then
                if isPlayer and singlePlayerRay[key] then keep = true
                elseif isModel and singleModelRay[key] then keep = true end
            end
            if not keep then
                pcall(function() if data.line then data.line:Remove() end end)
                pcall(function() if data.label then data.label:Destroy() end end)
                espLines[key] = nil
            end
        end
    end
end

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() then return end
    if not rayEnabled and next(singlePlayerRay) == nil and next(singleModelRay) == nil then
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
            local isGlobalRayValid = rayEnabled and (espEnabled or singlePlayerEsp[p])
            local isSingleRayValid = singlePlayerRay[p]
            if espLines[p] then
                if not targetChar or (not isGlobalRayValid and not isSingleRayValid) then
                    if espLines[p].line then espLines[p].line.Visible = false end
                    if espLines[p].text then espLines[p].text.Text = "" end
                else
                    local hrp = getHRP(targetChar)
                    if hrp then
                        local data = espLines[p]; local sp, _ = Camera:WorldToViewportPoint(hrp.Position)
                        if sp.Z > 0 then
                            local color = isSingleRayValid and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 255, 0)
                            data.line.From = center; data.line.To = Vector2.new(sp.X, sp.Y); data.line.Color = color; data.line.Visible = true
                            data.text.Text = p.Name .. " [" .. math.floor((hrp.Position - myPos).Magnitude) .. "m]"; data.text.TextColor3 = color
                        else data.line.Visible = false; data.text.Text = "" end
                    else if espLines[p].line then espLines[p].line.Visible = false end; if espLines[p].text then espLines[p].text.Text = "" end end
                end
            elseif targetChar and (isGlobalRayValid or isSingleRayValid) then 
                espLines[p] = createRayForModel(targetChar) 
            end
        end
    end

    local myVehicleModel = nil
    local myHum = myChar:FindFirstChildOfClass("Humanoid")
    if myHum and myHum.SeatPart then myVehicleModel = myHum.SeatPart:FindFirstAncestorOfClass("Model") end

    local invalid = {}
    for model, data in pairs(espLines) do
        if typeof(model) == "Instance" and model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
            local isGlobalRayValid = modelEspEnabled and rayEnabled
            local isSingleRayValid = singleModelRay[model]
            if not model.Parent or model == myVehicleModel or model == LocalPlayer.Character then table.insert(invalid, model)
            elseif not isGlobalRayValid and not isSingleRayValid then
                if data.line then data.line.Visible = false end
                if data.text then data.text.Text = "" end
            else
                local hrp = getHRP(model)
                if hrp and data.line then
                    local sp, _ = Camera:WorldToViewportPoint(hrp.Position)
                    if sp.Z > 0 then
                        local color = isSingleRayValid and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(255, 50, 50)
                        data.line.From = center; data.line.To = Vector2.new(sp.X, sp.Y); data.line.Color = color; data.line.Visible = true; data.text.Text = ""
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

    if modelEspEnabled or next(singleModelRay) ~= nil then
        for model in pairs(npcCache) do
            if model and model.Parent and not espLines[model] and model ~= LocalPlayer.Character and not Players:GetPlayerFromCharacter(model) and model ~= myVehicleModel then
                if (modelEspEnabled and rayEnabled) or singleModelRay[model] then espLines[model] = createRayForModel(model) end
            end
        end
    end
end))

-- 第三人称相机接管 每帧强制显形
track(RunService.RenderStepped:Connect(function()
    if not loopAlive() or not (forceShowSelfEnabled or camState == 1) then return end
    local char = LocalPlayer.Character
    if char then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                v.LocalTransparencyModifier = 0
                if v.Transparency > 0 and v.Name ~= "HumanoidRootPart" then v.Transparency = 0 end
            elseif v:IsA("Decal") then v.Transparency = 0 end
        end
    end
end))

-- 玩法模式每帧逻辑
track(RunService.RenderStepped:Connect(function(dt)
    if not loopAlive() then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    -- 强制第三人称逻辑
    if camState == 1 and not soulMode and not flying and not ragdollEnabled and not handstandEnabled then
        hum.AutoRotate = false
        local camLook = Camera.CFrame.LookVector
        local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
        if flatLook.Magnitude > 0.01 then
            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit)
        end
    end

    -- 玩偶模式
    if ragdollEnabled and not stickMode then
        hum.PlatformStand = true
        if char:FindFirstChild("Animate") then char.Animate.Disabled = true end
        if hum:GetState() ~= Enum.HumanoidStateType.Physics then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
        end
        local mv = getMoveVector()
        if mv.Magnitude > 0.01 then
            local camLook = Camera.CFrame.LookVector
            local camRight = Camera.CFrame.RightVector
            local flatLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
            local flatRight = Vector3.new(camRight.X, 0, camRight.Z).Unit
            local dir = flatLook * (-mv.Z) + flatRight * mv.X
            if dir.Magnitude > 0.01 then
                local targetVel = dir.Unit * ragdollSpeed
                hrp.AssemblyLinearVelocity = Vector3.new(targetVel.X, hrp.AssemblyLinearVelocity.Y, targetVel.Z)
            end
        end
    end

    -- 倒立模式
    if handstandEnabled and not stickMode then
        local camLook = Camera.CFrame.LookVector
        local flatLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
        if not hrp:FindFirstChild("HandstandVel") then
            local oldV = hrp:FindFirstChild("HandstandVel")
            if oldV then oldV:Destroy() end
            local vel = Instance.new("BodyVelocity")
            vel.Name = "HandstandVel"
            vel.MaxForce = Vector3.new(math.huge, 0, math.huge)
            vel.Parent = hrp
        end
        local vel = hrp:FindFirstChild("HandstandVel")
        local md = hum.MoveDirection
        local camRight = Camera.CFrame.RightVector
        local flatRight = Vector3.new(camRight.X, 0, camRight.Z).Unit
        local moveDir = flatLook * md:Dot(flatLook) + flatRight * md:Dot(flatRight)
        if moveDir.Magnitude > 0.01 then
            vel.Velocity = moveDir.Unit * handstandSpeed
        else
            vel.Velocity = Vector3.zero
        end
        if not hrp:FindFirstChild("HandstandOri") then
            local oldO = hrp:FindFirstChild("HandstandOri")
            if oldO then oldO:Destroy() end
            local att = Instance.new("Attachment", hrp)
            local ori = Instance.new("AlignOrientation")
            ori.Name = "HandstandOri"
            ori.Attachment0 = att
            ori.MaxTorque = math.huge
            ori.Mode = Enum.OrientationAlignmentMode.OneAttachment
            ori.Responsiveness = 30
            ori.Parent = hrp
        end
        local ori = hrp:FindFirstChild("HandstandOri")
        local lookAtCF = CFrame.lookAt(hrp.Position, hrp.Position + flatLook)
        ori.CFrame = lookAtCF * CFrame.Angles(math.rad(180), 0, 0)
    end

    -- 旋转模式 (直接暴力强改 CFrame，转速拉满)
    if spinEnabled and hrp then
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(spinSpeed) * dt * 100, 0)
    end
end))

--==================== 幽灵模式 ====================
function toggleGhostMode(state)
    ghostModeEnabled = state
    if state then
        setupGhostHook()
    end
    
    if ghostConn then ghostConn:Disconnect(); ghostConn = nil end
    if state then
        scanAndDisableHazards()
        local scanAccum = 0
        ghostConn = RunService.Heartbeat:Connect(function(dt)
            if not loopAlive() or not ghostModeEnabled then return end
            local char = LocalPlayer.Character
            if char and char:FindFirstChildOfClass("Humanoid") then
                local hum = char.Humanoid
                if hum.Health > 0 and hum.Health < hum.MaxHealth then
                    pcall(function() hum.Health = hum.MaxHealth end)
                end
                if hum.Health > 0 then
                    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
                end
            end
            scanAccum = scanAccum + (dt or 0)
            if scanAccum >= 0.5 then
                scanAccum = 0
                scanAndDisableHazards()
            end
        end)
    else
        restoreHazards()
        local char = LocalPlayer.Character
        if char and char:FindFirstChildOfClass("Humanoid") then
            pcall(function() char.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
        end
    end
end

function setNoclipState(state)
    toggleGhostMode(state)
    noclip = state
    local char = LocalPlayer.Character
    if char then
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
    end
end

--==================== UI 构建 ====================
UI.ScreenGui = Instance.new("ScreenGui")
UI.ScreenGui.Name = "FlyGui_V4"
UI.ScreenGui.ResetOnSpawn = false
UI.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
UI.ScreenGui.DisplayOrder = 2147483647
UI.ScreenGui.IgnoreGuiInset = true
UI.ScreenGui.Parent = PlayerGui

local uiScale = Instance.new("UIScale")
uiScale.Scale = 0.85
uiScale.Parent = UI.ScreenGui

UI.Crosshair = Instance.new("Frame")
UI.Crosshair.Size = UDim2.new(0, 24, 0, 24)
UI.Crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
UI.Crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
UI.Crosshair.BackgroundTransparency = 1
UI.Crosshair.Visible = false
UI.Crosshair.ZIndex = 2147483646
UI.Crosshair.Parent = UI.ScreenGui

do
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
end

UI.MainFrame = Instance.new("Frame")
UI.MainFrame.Size = UDim2.new(0, 195, 0, 195)
UI.MainFrame.Position = UDim2.new(0.15, 0, 0.1, 0)
UI.MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
UI.MainFrame.BackgroundTransparency = 0.05
UI.MainFrame.BorderSizePixel = 0
UI.MainFrame.Active = true
UI.MainFrame.ZIndex = 101
UI.MainFrame.Parent = UI.ScreenGui
Instance.new("UICorner", UI.MainFrame).CornerRadius = UDim.new(0, 12)

local mainStroke = Instance.new("UIStroke", UI.MainFrame)
mainStroke.Color = Color3.fromRGB(0, 200, 255)
mainStroke.Thickness = 1.5
mainStroke.Transparency = 0.2

function addStroke(parent, color)
    local s = Instance.new("UIStroke", parent)
    s.Color = color; s.Thickness = 1; s.Transparency = 0.2
end

function bindPressEffect(btn)
    if not btn or not btn:IsA("GuiObject") then return end
    local origSize = btn.Size
    local function scaleDown()
        TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(origSize.X.Scale * 0.93, origSize.X.Offset * 0.93, origSize.Y.Scale * 0.93, origSize.Y.Offset * 0.93)
        }):Play()
    end
    local function scaleUp()
        TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = origSize}):Play()
    end
    btn.MouseButton1Down:Connect(scaleDown)
    btn.MouseButton1Up:Connect(scaleUp)
    btn.MouseLeave:Connect(scaleUp)
end

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
bindPressEffect(UI.CloseBtn)

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
bindPressEffect(UI.ToggleBtn)

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

do
    local dragging, dragStart, startPos = false, nil, nil
    UI.Title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = UI.MainFrame.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStart
            UI.MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))
end

UI.TabBar = Instance.new("Frame")
UI.TabBar.Size = UDim2.new(1, -16, 0, 24)
UI.TabBar.Position = UDim2.new(0, 8, 0, 32)
UI.TabBar.BackgroundTransparency = 1
UI.TabBar.ZIndex = 102
UI.TabBar.Parent = UI.MainFrame

UI.BasicTab = Instance.new("TextButton")
UI.BasicTab.Size = UDim2.new(0.25, -2, 1, 0); UI.BasicTab.Position = UDim2.new(0, 0, 0, 0)
UI.BasicTab.BackgroundColor3 = Color3.fromRGB(0, 120, 180); UI.BasicTab.Text = "基础"
UI.BasicTab.TextColor3 = Color3.fromRGB(255, 255, 255); UI.BasicTab.Font = Enum.Font.GothamBold; UI.BasicTab.TextSize = 12
UI.BasicTab.ZIndex = 103; UI.BasicTab.Parent = UI.TabBar
Instance.new("UICorner", UI.BasicTab).CornerRadius = UDim.new(0, 6)
bindPressEffect(UI.BasicTab)

UI.DrawTab = Instance.new("TextButton")
UI.DrawTab.Size = UDim2.new(0.25, -2, 1, 0); UI.DrawTab.Position = UDim2.new(0.25, 2, 0, 0)
UI.DrawTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40); UI.DrawTab.Text = "绘制"
UI.DrawTab.TextColor3 = Color3.fromRGB(150, 160, 170); UI.DrawTab.Font = Enum.Font.GothamBold; UI.DrawTab.TextSize = 12
UI.DrawTab.ZIndex = 103; UI.DrawTab.Parent = UI.TabBar
Instance.new("UICorner", UI.DrawTab).CornerRadius = UDim.new(0, 6)
bindPressEffect(UI.DrawTab)

UI.AdvTab = Instance.new("TextButton")
UI.AdvTab.Size = UDim2.new(0.25, -2, 1, 0); UI.AdvTab.Position = UDim2.new(0.50, 2, 0, 0)
UI.AdvTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40); UI.AdvTab.Text = "高级"
UI.AdvTab.TextColor3 = Color3.fromRGB(150, 160, 170); UI.AdvTab.Font = Enum.Font.GothamBold; UI.AdvTab.TextSize = 12
UI.AdvTab.ZIndex = 103; UI.AdvTab.Parent = UI.TabBar
Instance.new("UICorner", UI.AdvTab).CornerRadius = UDim.new(0, 6)
bindPressEffect(UI.AdvTab)

UI.EntTab = Instance.new("TextButton")
UI.EntTab.Size = UDim2.new(0.25, -2, 1, 0); UI.EntTab.Position = UDim2.new(0.75, 2, 0, 0)
UI.EntTab.BackgroundColor3 = Color3.fromRGB(30, 33, 40); UI.EntTab.Text = "娱乐"
UI.EntTab.TextColor3 = Color3.fromRGB(150, 160, 170); UI.EntTab.Font = Enum.Font.GothamBold; UI.EntTab.TextSize = 12
UI.EntTab.ZIndex = 103; UI.EntTab.Parent = UI.TabBar
Instance.new("UICorner", UI.EntTab).CornerRadius = UDim.new(0, 6)
bindPressEffect(UI.EntTab)

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

function createButton(name, text, pos, color, parent, size)
    local btn = Instance.new("TextButton")
    btn.Name = name; btn.Size = size or UDim2.new(0.5, -2, 0, 28); btn.Position = pos
    btn.BackgroundColor3 = color; btn.BackgroundTransparency = 0.0; btn.Text = text
    btn.TextColor3 = Color3.fromRGB(0, 0, 0); btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
    btn.ZIndex = 104; btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    bindPressEffect(btn)
    return btn
end

UI.AimBtn = createButton("Aim", "自瞄: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageBasic)
UI.SoulBtn = createButton("Soul", "出窍: 16", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(140, 80, 60), UI.PageBasic)
UI.NoclipBtn = createButton("Noclip", "幽灵模式", UDim2.new(0, 0, 0, 32), Color3.fromRGB(255, 255, 255), UI.PageBasic)
UI.AirWalkBtn = createButton("AirWalk", "空中走", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(255, 255, 255), UI.PageBasic)
UI.WalkSpeedBtn = createButton("WalkSpeed", "速度: 16", UDim2.new(0, 0, 0, 64), Color3.fromRGB(60, 100, 150), UI.PageBasic)
UI.JumpBtn = createButton("Jump", "跳高: 50", UDim2.new(0.5, 2, 0, 64), Color3.fromRGB(150, 100, 60), UI.PageBasic)
UI.FlyBtn = createButton("Fly", "飞行: 35", UDim2.new(0, 0, 0, 96), Color3.fromRGB(180, 160, 40), UI.PageBasic, UDim2.new(1, 0, 0, 28))

UI.EspBtn = createButton("Esp", "人透: 关", UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.ItemEspBtn = createButton("ItemEsp", "物透: 关", UDim2.new(0.33, 2, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.CrosshairBtn = createButton("CrosshairBtn", "准星: 关", UDim2.new(0.66, 2, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))

UI.ModelEspBtn = createButton("ModelEsp", "模型透视: 关", UDim2.new(0, 0, 0, 32), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.RayBtn = createButton("Ray", "射线: 关", UDim2.new(0.33, 2, 0, 32), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.DarkBtn = createButton("DarkRemove", "去黑: 关", UDim2.new(0.66, 2, 0, 32), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))

UI.NoShadowBtn = createButton("NoShadow", "去阴影: 关", UDim2.new(0, 0, 0, 64), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.FovBtn = createButton("FovBtn", "视野: 70", UDim2.new(0.33, 2, 0, 64), Color3.fromRGB(60, 90, 150), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))
UI.CamBtn = createButton("CamBtn", "视角: 关", UDim2.new(0.66, 2, 0, 64), Color3.fromRGB(100, 50, 150), UI.PageDraw, UDim2.new(0.33, -2, 0, 28))

UI.UnlockCamBtn = createButton("UnlockCam", "解锁距离: 关", UDim2.new(0, 0, 0, 96), Color3.fromRGB(255, 255, 255), UI.PageDraw, UDim2.new(1, 0, 0, 28))

UI.OpenListBtn = createButton("OpenList", "玩家列表", UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageAdv)
UI.OpenModelListBtn = createButton("OpenModelList", "模型列表", UDim2.new(0.5, 2, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageAdv)

UI.PlayerHitboxBtn = createButton("PlayerHitbox", "玩家: 1x", UDim2.new(0, 0, 0, 32), Color3.fromRGB(140, 140, 40), UI.PageAdv)
UI.NPCHitboxBtn = createButton("NPCHitbox", "模型: 1x", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(160, 50, 50), UI.PageAdv)

UI.CollectTouchBtn = createButton("CollectTouch", "全触碰", UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.CollectInteractBtn = createButton("CollectInteract", "全交互", UDim2.new(0.33, 2, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.CollectClickBtn = createButton("CollectClick", "全点击", UDim2.new(0.66, 2, 0, 0), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))

UI.Click100Btn = createButton("Click100", "点击: 100", UDim2.new(0, 0, 0, 32), Color3.fromRGB(100, 50, 150), UI.PageEnt)
UI.MagnetBtn = createButton("Magnet", "全吸物", UDim2.new(0.5, 2, 0, 32), Color3.fromRGB(255, 255, 255), UI.PageEnt)

UI.AntiTPBtn = createButton("AntiTP", "防瞬移: 关", UDim2.new(0, 0, 0, 64), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.ZeroPromptBtn = createButton("ZeroPrompt", "零延迟: 关", UDim2.new(0.33, 2, 0, 64), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.LockSpeedBtn = createButton("LockSpeed", "锁速: 关", UDim2.new(0.66, 2, 0, 64), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))

UI.NativePopupBtn = createButton("NativePopup", "防弹窗: 关", UDim2.new(0, 0, 0, 96), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.RagdollBtn = createButton("RagdollBtn", "玩偶: 20", UDim2.new(0.33, 2, 0, 96), Color3.fromRGB(150, 50, 150), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.SpinBtn = createButton("SpinBtn", "旋转: 10", UDim2.new(0.66, 2, 0, 96), Color3.fromRGB(200, 100, 50), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))

UI.NpcFreezeBtn = createButton("NpcFreeze", "全图定住: 关", UDim2.new(0, 0, 0, 128), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.5, -2, 0, 28))
UI.NpcLiftBtn = createButton("NpcLift", "全图升空: 关", UDim2.new(0.5, 2, 0, 128), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.5, -2, 0, 28))

UI.HandstandBtn = createButton("HandstandBtn", "倒立: 18", UDim2.new(0, 0, 0, 160), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))
UI.OrbitBtn = createButton("OrbitBtn", "绕: 关", UDim2.new(0.33, 2, 0, 160), Color3.fromRGB(255, 255, 255), UI.PageEnt, UDim2.new(0.33, -2, 0, 28))

--==================== 滑条 UI ====================
local function styleSlider(container, bg, thumb, color1, color2)
    container.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
    container.BackgroundTransparency = 0.05
    
    bg.Size = UDim2.new(0, 8, 1, -20); bg.Position = UDim2.new(0.5, -4, 0, 10)
    bg.BackgroundColor3 = Color3.fromRGB(255, 255, 255); bg.BorderSizePixel = 0
    local bgGrad = Instance.new("UIGradient", bg)
    bgGrad.Rotation = 90
    bgGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, color1), ColorSequenceKeypoint.new(1, color2)})
    bgGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.2)})

    thumb.Size = UDim2.new(0, 14, 0, 14); thumb.Position = UDim2.new(0.5, -7, 0.5, -7)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255); thumb.Text = ""
    local tc = Instance.new("UICorner", thumb); tc.CornerRadius = UDim.new(1, 0)
    local ts = Instance.new("UIStroke", thumb); ts.Color = color1; ts.Thickness = 2
end

UI.SpeedSliderContainer = Instance.new("Frame")
UI.SpeedSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.SpeedSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.SpeedSliderContainer.Visible = false; UI.SpeedSliderContainer.ZIndex = 105; UI.SpeedSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SpeedSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.SpeedSliderContainer, Color3.fromRGB(0, 200, 255))
UI.SpeedBg = Instance.new("Frame"); UI.SpeedBg.Active = true; UI.SpeedBg.ZIndex = 106; UI.SpeedBg.Parent = UI.SpeedSliderContainer; Instance.new("UICorner", UI.SpeedBg).CornerRadius = UDim.new(1, 0)
UI.SpeedThumb = Instance.new("TextButton"); UI.SpeedThumb.ZIndex = 107; UI.SpeedThumb.Parent = UI.SpeedSliderContainer
styleSlider(UI.SpeedSliderContainer, UI.SpeedBg, UI.SpeedThumb, Color3.fromRGB(0, 255, 255), Color3.fromRGB(0, 120, 200))

UI.JumpSliderContainer = Instance.new("Frame")
UI.JumpSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.JumpSliderContainer.Position = UDim2.new(1, 45, 0, 10)
UI.JumpSliderContainer.Visible = false; UI.JumpSliderContainer.ZIndex = 140; UI.JumpSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.JumpSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.JumpSliderContainer, Color3.fromRGB(255, 180, 100))
UI.JumpBg = Instance.new("Frame"); UI.JumpBg.Active = true; UI.JumpBg.ZIndex = 141; UI.JumpBg.Parent = UI.JumpSliderContainer; Instance.new("UICorner", UI.JumpBg).CornerRadius = UDim.new(1, 0)
UI.JumpThumb = Instance.new("TextButton"); UI.JumpThumb.ZIndex = 142; UI.JumpThumb.Parent = UI.JumpSliderContainer
styleSlider(UI.JumpSliderContainer, UI.JumpBg, UI.JumpThumb, Color3.fromRGB(255, 200, 100), Color3.fromRGB(200, 100, 0))

UI.WalkSpeedSliderContainer = Instance.new("Frame")
UI.WalkSpeedSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.WalkSpeedSliderContainer.Position = UDim2.new(1, 45, 0, 10)
UI.WalkSpeedSliderContainer.Visible = false; UI.WalkSpeedSliderContainer.ZIndex = 130; UI.WalkSpeedSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.WalkSpeedSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.WalkSpeedSliderContainer, Color3.fromRGB(100, 180, 255))
UI.WalkSpeedBg = Instance.new("Frame"); UI.WalkSpeedBg.Active = true; UI.WalkSpeedBg.ZIndex = 131; UI.WalkSpeedBg.Parent = UI.WalkSpeedSliderContainer; Instance.new("UICorner", UI.WalkSpeedBg).CornerRadius = UDim.new(1, 0)
UI.WalkSpeedThumb = Instance.new("TextButton"); UI.WalkSpeedThumb.ZIndex = 132; UI.WalkSpeedThumb.Parent = UI.WalkSpeedSliderContainer
styleSlider(UI.WalkSpeedSliderContainer, UI.WalkSpeedBg, UI.WalkSpeedThumb, Color3.fromRGB(100, 180, 255), Color3.fromRGB(50, 100, 200))

UI.CamDistSliderContainer = Instance.new("Frame")
UI.CamDistSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.CamDistSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.CamDistSliderContainer.Visible = false; UI.CamDistSliderContainer.ZIndex = 120; UI.CamDistSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.CamDistSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.CamDistSliderContainer, Color3.fromRGB(200, 100, 255))
UI.CamDistBg = Instance.new("Frame"); UI.CamDistBg.Active = true; UI.CamDistBg.ZIndex = 121; UI.CamDistBg.Parent = UI.CamDistSliderContainer; Instance.new("UICorner", UI.CamDistBg).CornerRadius = UDim.new(1, 0)
UI.CamDistThumb = Instance.new("TextButton"); UI.CamDistThumb.ZIndex = 122; UI.CamDistThumb.Parent = UI.CamDistSliderContainer
styleSlider(UI.CamDistSliderContainer, UI.CamDistBg, UI.CamDistThumb, Color3.fromRGB(200, 100, 255), Color3.fromRGB(100, 0, 200))

UI.SliderContainer = Instance.new("Frame")
UI.SliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.SliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.SliderContainer.Visible = false; UI.SliderContainer.ZIndex = 110; UI.SliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.SliderContainer, Color3.fromRGB(0, 220, 255))
UI.SliderBg = Instance.new("Frame"); UI.SliderBg.Active = true; UI.SliderBg.ZIndex = 111; UI.SliderBg.Parent = UI.SliderContainer; Instance.new("UICorner", UI.SliderBg).CornerRadius = UDim.new(1, 0)
UI.SliderThumb = Instance.new("TextButton"); UI.SliderThumb.ZIndex = 112; UI.SliderThumb.Parent = UI.SliderContainer
styleSlider(UI.SliderContainer, UI.SliderBg, UI.SliderThumb, Color3.fromRGB(0, 220, 255), Color3.fromRGB(0, 150, 200))

UI.ClickMultiplierSliderContainer = Instance.new("Frame")
UI.ClickMultiplierSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.ClickMultiplierSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.ClickMultiplierSliderContainer.Visible = false; UI.ClickMultiplierSliderContainer.ZIndex = 150; UI.ClickMultiplierSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.ClickMultiplierSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.ClickMultiplierSliderContainer, Color3.fromRGB(200, 100, 255))
UI.ClickMultiplierBg = Instance.new("Frame"); UI.ClickMultiplierBg.Active = true; UI.ClickMultiplierBg.ZIndex = 151; UI.ClickMultiplierBg.Parent = UI.ClickMultiplierSliderContainer; Instance.new("UICorner", UI.ClickMultiplierBg).CornerRadius = UDim.new(1, 0)
UI.ClickMultiplierThumb = Instance.new("TextButton"); UI.ClickMultiplierThumb.ZIndex = 152; UI.ClickMultiplierThumb.Parent = UI.ClickMultiplierSliderContainer
styleSlider(UI.ClickMultiplierSliderContainer, UI.ClickMultiplierBg, UI.ClickMultiplierThumb, Color3.fromRGB(200, 100, 255), Color3.fromRGB(150, 50, 200))

UI.HitboxSliderContainer = Instance.new("Frame")
UI.HitboxSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.HitboxSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.HitboxSliderContainer.Visible = false; UI.HitboxSliderContainer.ZIndex = 160; UI.HitboxSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.HitboxSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.HitboxSliderContainer, Color3.fromRGB(255, 100, 100))
UI.HitboxBg = Instance.new("Frame"); UI.HitboxBg.Active = true; UI.HitboxBg.ZIndex = 161; UI.HitboxBg.Parent = UI.HitboxSliderContainer; Instance.new("UICorner", UI.HitboxBg).CornerRadius = UDim.new(1, 0)
UI.HitboxThumb = Instance.new("TextButton"); UI.HitboxThumb.ZIndex = 162; UI.HitboxThumb.Parent = UI.HitboxSliderContainer
styleSlider(UI.HitboxSliderContainer, UI.HitboxBg, UI.HitboxThumb, Color3.fromRGB(255, 100, 100), Color3.fromRGB(200, 0, 0))

UI.SoulSpeedSliderContainer = Instance.new("Frame")
UI.SoulSpeedSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.SoulSpeedSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.SoulSpeedSliderContainer.Visible = false; UI.SoulSpeedSliderContainer.ZIndex = 155; UI.SoulSpeedSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SoulSpeedSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.SoulSpeedSliderContainer, Color3.fromRGB(150, 100, 255))
UI.SoulSpeedBg = Instance.new("Frame"); UI.SoulSpeedBg.Active = true; UI.SoulSpeedBg.ZIndex = 156; UI.SoulSpeedBg.Parent = UI.SoulSpeedSliderContainer; Instance.new("UICorner", UI.SoulSpeedBg).CornerRadius = UDim.new(1, 0)
UI.SoulSpeedThumb = Instance.new("TextButton"); UI.SoulSpeedThumb.ZIndex = 157; UI.SoulSpeedThumb.Parent = UI.SoulSpeedSliderContainer
styleSlider(UI.SoulSpeedSliderContainer, UI.SoulSpeedBg, UI.SoulSpeedThumb, Color3.fromRGB(150, 100, 255), Color3.fromRGB(80, 40, 200))

UI.SpinSliderContainer = Instance.new("Frame")
UI.SpinSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.SpinSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.SpinSliderContainer.Visible = false; UI.SpinSliderContainer.ZIndex = 170; UI.SpinSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.SpinSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.SpinSliderContainer, Color3.fromRGB(255, 150, 50))
UI.SpinBg = Instance.new("Frame"); UI.SpinBg.Active = true; UI.SpinBg.ZIndex = 171; UI.SpinBg.Parent = UI.SpinSliderContainer; Instance.new("UICorner", UI.SpinBg).CornerRadius = UDim.new(1, 0)
UI.SpinThumb = Instance.new("TextButton"); UI.SpinThumb.ZIndex = 172; UI.SpinThumb.Parent = UI.SpinSliderContainer
styleSlider(UI.SpinSliderContainer, UI.SpinBg, UI.SpinThumb, Color3.fromRGB(255, 150, 50), Color3.fromRGB(200, 100, 0))

UI.RagdollSliderContainer = Instance.new("Frame")
UI.RagdollSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.RagdollSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.RagdollSliderContainer.Visible = false; UI.RagdollSliderContainer.ZIndex = 175; UI.RagdollSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.RagdollSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.RagdollSliderContainer, Color3.fromRGB(150, 50, 150))
UI.RagdollBg = Instance.new("Frame"); UI.RagdollBg.Active = true; UI.RagdollBg.ZIndex = 176; UI.RagdollBg.Parent = UI.RagdollSliderContainer; Instance.new("UICorner", UI.RagdollBg).CornerRadius = UDim.new(1, 0)
UI.RagdollThumb = Instance.new("TextButton"); UI.RagdollThumb.ZIndex = 177; UI.RagdollThumb.Parent = UI.RagdollSliderContainer
styleSlider(UI.RagdollSliderContainer, UI.RagdollBg, UI.RagdollThumb, Color3.fromRGB(150, 50, 150), Color3.fromRGB(80, 0, 80))

UI.HandstandSliderContainer = Instance.new("Frame")
UI.HandstandSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.HandstandSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.HandstandSliderContainer.Visible = false; UI.HandstandSliderContainer.ZIndex = 178; UI.HandstandSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.HandstandSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.HandstandSliderContainer, Color3.fromRGB(255, 255, 255))
UI.HandstandBg = Instance.new("Frame"); UI.HandstandBg.Active = true; UI.HandstandBg.ZIndex = 179; UI.HandstandBg.Parent = UI.HandstandSliderContainer; Instance.new("UICorner", UI.HandstandBg).CornerRadius = UDim.new(1, 0)
UI.HandstandThumb = Instance.new("TextButton"); UI.HandstandThumb.ZIndex = 180; UI.HandstandThumb.Parent = UI.HandstandSliderContainer
styleSlider(UI.HandstandSliderContainer, UI.HandstandBg, UI.HandstandThumb, Color3.fromRGB(200, 200, 200), Color3.fromRGB(100, 100, 100))

UI.OrbitSliderContainer = Instance.new("Frame")
UI.OrbitSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.OrbitSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.OrbitSliderContainer.Visible = false; UI.OrbitSliderContainer.ZIndex = 181; UI.OrbitSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.OrbitSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.OrbitSliderContainer, Color3.fromRGB(100, 200, 100))
UI.OrbitBg = Instance.new("Frame"); UI.OrbitBg.Active = true; UI.OrbitBg.ZIndex = 182; UI.OrbitBg.Parent = UI.OrbitSliderContainer; Instance.new("UICorner", UI.OrbitBg).CornerRadius = UDim.new(1, 0)
UI.OrbitThumb = Instance.new("TextButton"); UI.OrbitThumb.ZIndex = 183; UI.OrbitThumb.Parent = UI.OrbitSliderContainer
styleSlider(UI.OrbitSliderContainer, UI.OrbitBg, UI.OrbitThumb, Color3.fromRGB(100, 200, 100), Color3.fromRGB(50, 150, 50))

UI.OrbitRadiusSliderContainer = Instance.new("Frame")
UI.OrbitRadiusSliderContainer.Size = UDim2.new(0, 36, 0, 175); UI.OrbitRadiusSliderContainer.Position = UDim2.new(1, 5, 0, 10)
UI.OrbitRadiusSliderContainer.Visible = false; UI.OrbitRadiusSliderContainer.ZIndex = 184; UI.OrbitRadiusSliderContainer.Parent = UI.MainFrame
Instance.new("UICorner", UI.OrbitRadiusSliderContainer).CornerRadius = UDim.new(0, 8); addStroke(UI.OrbitRadiusSliderContainer, Color3.fromRGB(100, 200, 100))
UI.OrbitRadiusBg = Instance.new("Frame"); UI.OrbitRadiusBg.Active = true; UI.OrbitRadiusBg.ZIndex = 185; UI.OrbitRadiusBg.Parent = UI.OrbitRadiusSliderContainer; Instance.new("UICorner", UI.OrbitRadiusBg).CornerRadius = UDim.new(1, 0)
UI.OrbitRadiusThumb = Instance.new("TextButton"); UI.OrbitRadiusThumb.ZIndex = 186; UI.OrbitRadiusThumb.Parent = UI.OrbitRadiusSliderContainer
styleSlider(UI.OrbitRadiusSliderContainer, UI.OrbitRadiusBg, UI.OrbitRadiusThumb, Color3.fromRGB(100, 200, 100), Color3.fromRGB(50, 150, 50))

UI.SoulUpBtn = Instance.new("TextButton")
UI.SoulUpBtn.Size = UDim2.new(0, 40, 0, 40) 
UI.SoulUpBtn.Position = UDim2.new(1, -80, 0, 120) 
UI.SoulUpBtn.AnchorPoint = Vector2.new(0.5, 0.5)
UI.SoulUpBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
UI.SoulUpBtn.BackgroundTransparency = 0.3
UI.SoulUpBtn.Text = "▲"
UI.SoulUpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.SoulUpBtn.Font = Enum.Font.GothamBold
UI.SoulUpBtn.TextSize = 20
UI.SoulUpBtn.Visible = false
UI.SoulUpBtn.ZIndex = 200
UI.SoulUpBtn.Parent = UI.ScreenGui
Instance.new("UICorner", UI.SoulUpBtn).CornerRadius = UDim.new(1, 0)
addStroke(UI.SoulUpBtn, Color3.fromRGB(200, 150, 255))

UI.SoulDownBtn = Instance.new("TextButton")
UI.SoulDownBtn.Size = UDim2.new(0, 40, 0, 40)
UI.SoulDownBtn.Position = UDim2.new(1, -80, 0, 170) 
UI.SoulDownBtn.AnchorPoint = Vector2.new(0.5, 0.5)
UI.SoulDownBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
UI.SoulDownBtn.BackgroundTransparency = 0.3
UI.SoulDownBtn.Text = "▼"
UI.SoulDownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UI.SoulDownBtn.Font = Enum.Font.GothamBold
UI.SoulDownBtn.TextSize = 20
UI.SoulDownBtn.Visible = false
UI.SoulDownBtn.ZIndex = 200
UI.SoulDownBtn.Parent = UI.ScreenGui
Instance.new("UICorner", UI.SoulDownBtn).CornerRadius = UDim.new(1, 0)
addStroke(UI.SoulDownBtn, Color3.fromRGB(200, 150, 255))

UI.SoulUpBtn.MouseButton1Down:Connect(function()
    touchFlyUp = true
    UI.SoulUpBtn.BackgroundTransparency = 0.05
    UI.SoulUpBtn.BackgroundColor3 = Color3.fromRGB(180, 130, 255)
end)
UI.SoulUpBtn.MouseButton1Up:Connect(function()
    touchFlyUp = false
    UI.SoulUpBtn.BackgroundTransparency = 0.3
    UI.SoulUpBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
end)
UI.SoulUpBtn.MouseLeave:Connect(function()
    touchFlyUp = false
    UI.SoulUpBtn.BackgroundTransparency = 0.3
    UI.SoulUpBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
end)
UI.SoulDownBtn.MouseButton1Down:Connect(function()
    touchFlyDown = true
    UI.SoulDownBtn.BackgroundTransparency = 0.05
    UI.SoulDownBtn.BackgroundColor3 = Color3.fromRGB(180, 130, 255)
end)
UI.SoulDownBtn.MouseButton1Up:Connect(function()
    touchFlyDown = false
    UI.SoulDownBtn.BackgroundTransparency = 0.3
    UI.SoulDownBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
end)
UI.SoulDownBtn.MouseLeave:Connect(function()
    touchFlyDown = false
    UI.SoulDownBtn.BackgroundTransparency = 0.3
    UI.SoulDownBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
end)
track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if touchFlyUp then touchFlyUp = false; UI.SoulUpBtn.BackgroundTransparency = 0.3; UI.SoulUpBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255) end
        if touchFlyDown then touchFlyDown = false; UI.SoulDownBtn.BackgroundTransparency = 0.3; UI.SoulDownBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 255) end
    end
end))

function applyHitboxColor(isPlayer)
    local c1, c2
    if isPlayer then
        c1 = Color3.fromRGB(255, 100, 100); c2 = Color3.fromRGB(200, 0, 0)
    else
        c1 = Color3.fromRGB(100, 150, 255); c2 = Color3.fromRGB(50, 80, 200)
    end
    local contStroke = UI.HitboxSliderContainer:FindFirstChildOfClass("UIStroke")
    if contStroke then contStroke.Color = c1 end
    local bgGrad = UI.HitboxBg:FindFirstChildOfClass("UIGradient")
    if bgGrad then bgGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2)}) end
    local thumbStroke = UI.HitboxThumb:FindFirstChildOfClass("UIStroke")
    if thumbStroke then thumbStroke.Color = c1 end
end

function updateSliderLayout()
    local activeSliders = {}
    if currentTab == 1 then
        if UI.SpeedSliderContainer.Visible then table.insert(activeSliders, UI.SpeedSliderContainer) end
        if UI.WalkSpeedSliderContainer.Visible then table.insert(activeSliders, UI.WalkSpeedSliderContainer) end
        if UI.JumpSliderContainer.Visible then table.insert(activeSliders, UI.JumpSliderContainer) end
        if UI.SoulSpeedSliderContainer.Visible then table.insert(activeSliders, UI.SoulSpeedSliderContainer) end
    elseif currentTab == 2 then
        if UI.SliderContainer.Visible then table.insert(activeSliders, UI.SliderContainer) end
        if UI.CamDistSliderContainer.Visible then table.insert(activeSliders, UI.CamDistSliderContainer) end
    elseif currentTab == 3 then
        if UI.HitboxSliderContainer.Visible then table.insert(activeSliders, UI.HitboxSliderContainer) end
    elseif currentTab == 4 then
        if UI.ClickMultiplierSliderContainer.Visible then table.insert(activeSliders, UI.ClickMultiplierSliderContainer) end
        if UI.SpinSliderContainer.Visible then table.insert(activeSliders, UI.SpinSliderContainer) end
        if UI.RagdollSliderContainer.Visible then table.insert(activeSliders, UI.RagdollSliderContainer) end
        if UI.HandstandSliderContainer.Visible then table.insert(activeSliders, UI.HandstandSliderContainer) end
        if UI.OrbitSliderContainer.Visible then table.insert(activeSliders, UI.OrbitSliderContainer) end
        if UI.OrbitRadiusSliderContainer.Visible then table.insert(activeSliders, UI.OrbitRadiusSliderContainer) end
    end

    for i, slider in ipairs(activeSliders) do
        slider.Position = UDim2.new(1, 5 + (i-1)*40, 0, 10)
    end
end

function getSliderRelativeY(absoluteY, bg)
    local bgAbsY = bg.AbsolutePosition.Y; local bgHeight = bg.AbsoluteSize.Y
    if bgHeight <= 0 then return 0 end
    return math.clamp((absoluteY - bgAbsY) / bgHeight, 0, 1)
end

function updateThumbPos(thumb, relativeY, _legacyBgHeight)
    if not thumb or not thumb.Parent then return end
    local bg = thumb.Parent:FindFirstChildWhichIsA("Frame")
    if not bg then return end
    local scale = uiScale and uiScale.Scale or 1
    if scale <= 0 then scale = 1 end
    local bgAbsH = bg.AbsoluteSize.Y
    local bgAbsY = bg.AbsolutePosition.Y
    local parentAbsY = thumb.Parent.AbsolutePosition.Y
    if bgAbsH <= 0 then return end
    local thumbAbsH = thumb.AbsoluteSize.Y
    if thumbAbsH <= 0 then thumbAbsH = 14 * scale end
    local travel = bgAbsH - thumbAbsH
    if travel < 0 then travel = 0 end
    relativeY = math.clamp(relativeY, 0, 1)
    local targetAbsY = bgAbsY + relativeY * travel
    local yOffset = (targetAbsY - parentAbsY) / scale
    thumb.Position = UDim2.new(0.5, -7, 0, yOffset)
end

function refreshAllSliderThumbs()
    updateThumbPos(UI.SpeedThumb, 1 - ((speeds - 1) / 9), UI.SpeedBg.AbsoluteSize.Y)
    updateThumbPos(UI.WalkSpeedThumb, (200 - currentWalkSpeed) / 184, UI.WalkSpeedBg.AbsoluteSize.Y)
    updateThumbPos(UI.JumpThumb, (200 - currentJumpPower) / 150, UI.JumpBg.AbsoluteSize.Y)
    updateThumbPos(UI.SliderThumb, (120 - currentFov) / 70, UI.SliderBg.AbsoluteSize.Y)
    updateThumbPos(UI.CamDistThumb, (40 - camDistance) / 36, UI.CamDistBg.AbsoluteSize.Y)
    updateThumbPos(UI.ClickMultiplierThumb, 1 - ((x100State.multiplier - 1) / 999), UI.ClickMultiplierBg.AbsoluteSize.Y)
    updateThumbPos(UI.HitboxThumb, 1 - ((currentHitboxValue - 1) / 199), UI.HitboxBg.AbsoluteSize.Y)
    updateThumbPos(UI.SoulSpeedThumb, 1 - ((soulSpeed - 1) / 29), UI.SoulSpeedBg.AbsoluteSize.Y)
    updateThumbPos(UI.SpinThumb, 1 - ((spinSpeed - 1) / 199), UI.SpinBg.AbsoluteSize.Y) 
    updateThumbPos(UI.RagdollThumb, 1 - ((ragdollSpeed - 10) / 90), UI.RagdollBg.AbsoluteSize.Y) 
    updateThumbPos(UI.HandstandThumb, 1 - ((handstandSpeed - 5) / 45), UI.HandstandBg.AbsoluteSize.Y)
    updateThumbPos(UI.OrbitThumb, 1 - ((orbitSpeed - 1) / 19), UI.OrbitBg.AbsoluteSize.Y)
    updateThumbPos(UI.OrbitRadiusThumb, 1 - ((orbitRadius - 5) / 45), UI.OrbitRadiusBg.AbsoluteSize.Y)
end

local clickMultDebounce = nil
function applyClickMultiplier(val)
    if val < 1 then val = 1 end
    if val > 1000 then val = 1000 end
    x100State.multiplier = val
    x100State.enabled = true
    hookClickX100()
end

function updateClickMultFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.ClickMultiplierBg)
    local val = math.floor(1 + ((1 - relativeY) * 999) + 0.5)
    updateThumbPos(UI.ClickMultiplierThumb, relativeY, UI.ClickMultiplierBg.AbsoluteSize.Y)
    if clickMultDebounce then task.cancel(clickMultDebounce) end
    clickMultDebounce = task.delay(0.5, function() applyClickMultiplier(val) end)
end

function applyHitboxSliderValue(val)
    if val < 1 then val = 1 end
    if val > 200 then val = 200 end
    currentHitboxValue = val
    if activeHitboxSliderType == "global_player" then
        globalPlayerHitboxMult = val
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local c = getCharForPlayer(plr)
                if c then
                    local m = singlePlayerHitboxMult[plr] or globalPlayerHitboxMult
                    if m > 1 then applyHitbox(c, m, false) else restoreHitbox(c, false) end
                end
            end
        end
    elseif activeHitboxSliderType == "single_player" and activeHitboxSliderTarget then
        singlePlayerHitboxMult[activeHitboxSliderTarget] = val
        local c = getCharForPlayer(activeHitboxSliderTarget)
        if c then applyHitbox(c, val, false) end
    elseif activeHitboxSliderType == "global_npc" then
        globalNpcHitboxMult = val
        local myChar = LocalPlayer.Character
        local myHRP = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChildWhichIsA("BasePart"))
        local myPos = myHRP and myHRP.Position
        for model in pairs(npcCache) do
            if model and model.Parent then
                local skip = false
                if myPos then
                    local nhrp = getModelHRP(model)
                    if nhrp and (nhrp.Position - myPos).Magnitude > 100 then skip = true end
                end
                if not skip then
                    local m = singleModelHitboxMult[model] or globalNpcHitboxMult
                    if m > 1 then applyHitbox(model, m, true) else restoreHitbox(model, true) end
                end
            end
        end
    elseif activeHitboxSliderType == "single_npc" and activeHitboxSliderTarget then
        singleModelHitboxMult[activeHitboxSliderTarget] = val
        if activeHitboxSliderTarget.Parent then applyHitbox(activeHitboxSliderTarget, val, true) end
    end
end

function updateHitboxFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.HitboxBg)
    local val = math.floor(1 + ((1 - relativeY) * 199) + 0.5)
    updateThumbPos(UI.HitboxThumb, relativeY, UI.HitboxBg.AbsoluteSize.Y)
    if hitboxApplyDebounce then task.cancel(hitboxApplyDebounce) end
    hitboxApplyDebounce = task.delay(0.5, function() applyHitboxSliderValue(val) end)
end

function updateSoulSpeedFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.SoulSpeedBg)
    soulSpeed = math.floor(30 - (relativeY * 29) + 0.5)
    updateThumbPos(UI.SoulSpeedThumb, relativeY, UI.SoulSpeedBg.AbsoluteSize.Y)
end

function updateSpinSpeedFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.SpinBg)
    spinSpeed = math.floor(1 + ((1 - relativeY) * 199) + 0.5)
    updateThumbPos(UI.SpinThumb, relativeY, UI.SpinBg.AbsoluteSize.Y)
end

function updateRagdollSpeedFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.RagdollBg)
    ragdollSpeed = math.floor(100 - (relativeY * 90) + 0.5)
    updateThumbPos(UI.RagdollThumb, relativeY, UI.RagdollBg.AbsoluteSize.Y)
end

function updateHandstandSpeedFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.HandstandBg)
    handstandSpeed = math.floor(50 - (relativeY * 45) + 0.5)
    updateThumbPos(UI.HandstandThumb, relativeY, UI.HandstandBg.AbsoluteSize.Y)
end

function updateOrbitSpeedFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.OrbitBg)
    orbitSpeed = math.floor(20 - (relativeY * 19) + 0.5)
    updateThumbPos(UI.OrbitThumb, relativeY, UI.OrbitBg.AbsoluteSize.Y)
end

function updateOrbitRadiusFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.OrbitRadiusBg)
    orbitRadius = math.floor(5 + ((1 - relativeY) * 45) + 0.5)
    updateThumbPos(UI.OrbitRadiusThumb, relativeY, UI.OrbitRadiusBg.AbsoluteSize.Y)
end

local mainDragInput = nil; local mainDragType = nil

track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local pos = input.Position
        if UI.ClickMultiplierSliderContainer.Visible then
            local a, s = UI.ClickMultiplierSliderContainer.AbsolutePosition, UI.ClickMultiplierSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "clickmult"; updateClickMultFromY(pos.Y); return end
        end
        if UI.HitboxSliderContainer.Visible then
            local a, s = UI.HitboxSliderContainer.AbsolutePosition, UI.HitboxSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "hitbox"; updateHitboxFromY(pos.Y); return end
        end
        if UI.SoulSpeedSliderContainer.Visible then
            local a, s = UI.SoulSpeedSliderContainer.AbsolutePosition, UI.SoulSpeedSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "soulspeed"; updateSoulSpeedFromY(pos.Y); return end
        end
        if UI.SpinSliderContainer.Visible then
            local a, s = UI.SpinSliderContainer.AbsolutePosition, UI.SpinSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "spinspeed"; updateSpinSpeedFromY(pos.Y); return end
        end
        if UI.RagdollSliderContainer.Visible then
            local a, s = UI.RagdollSliderContainer.AbsolutePosition, UI.RagdollSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "ragdoll"; updateRagdollSpeedFromY(pos.Y); return end
        end
        if UI.HandstandSliderContainer.Visible then
            local a, s = UI.HandstandSliderContainer.AbsolutePosition, UI.HandstandSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "handstand"; updateHandstandSpeedFromY(pos.Y); return end
        end
        if UI.OrbitSliderContainer.Visible then
            local a, s = UI.OrbitSliderContainer.AbsolutePosition, UI.OrbitSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "orbit"; updateOrbitSpeedFromY(pos.Y); return end
        end
        if UI.OrbitRadiusSliderContainer.Visible then
            local a, s = UI.OrbitRadiusSliderContainer.AbsolutePosition, UI.OrbitRadiusSliderContainer.AbsoluteSize
            if pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y then mainDragInput = input; mainDragType = "orbitradius"; updateOrbitRadiusFromY(pos.Y); return end
        end
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
        elseif mainDragType == "camdist" then updateCamDistFromY(input.Position.Y)
        elseif mainDragType == "clickmult" then updateClickMultFromY(input.Position.Y)
        elseif mainDragType == "hitbox" then updateHitboxFromY(input.Position.Y)
        elseif mainDragType == "soulspeed" then updateSoulSpeedFromY(input.Position.Y) 
        elseif mainDragType == "spinspeed" then updateSpinSpeedFromY(input.Position.Y)
        elseif mainDragType == "ragdoll" then updateRagdollSpeedFromY(input.Position.Y)
        elseif mainDragType == "handstand" then updateHandstandSpeedFromY(input.Position.Y)
        elseif mainDragType == "orbit" then updateOrbitSpeedFromY(input.Position.Y)
        elseif mainDragType == "orbitradius" then updateOrbitRadiusFromY(input.Position.Y) end
    end
end))

track(UserInputService.InputEnded:Connect(function(input) if input == mainDragInput then mainDragInput = nil; mainDragType = nil end end))

function updateSpeedFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.SpeedBg)
    speeds = math.floor(10 - (relativeY * 9) + 0.5)
    updateThumbPos(UI.SpeedThumb, relativeY, UI.SpeedBg.AbsoluteSize.Y)
end

function updateWalkSpeedFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.WalkSpeedBg)
    currentWalkSpeed = math.floor(200 - (relativeY * 184))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") and not soulMode and not flying then 
        char.Humanoid.WalkSpeed = currentWalkSpeed 
    end
    updateThumbPos(UI.WalkSpeedThumb, relativeY, UI.WalkSpeedBg.AbsoluteSize.Y)
end

function updateJumpFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.JumpBg)
    currentJumpPower = math.floor(200 - (relativeY * 150))
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") and not soulMode and not flying then 
        char.Humanoid.JumpPower = currentJumpPower; char.Humanoid.UseJumpPower = true 
    end
    updateThumbPos(UI.JumpThumb, relativeY, UI.JumpBg.AbsoluteSize.Y)
end

function updateFovFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.SliderBg)
    currentFov = math.floor(120 - (relativeY * 70))
    if Camera then Camera.FieldOfView = currentFov end
    updateThumbPos(UI.SliderThumb, relativeY, UI.SliderBg.AbsoluteSize.Y)
end

function updateCamDistFromY(absoluteY)
    local relativeY = getSliderRelativeY(absoluteY, UI.CamDistBg)
    camDistance = math.floor(4 + ((1 - relativeY) * 36) + 0.5)
    updateThumbPos(UI.CamDistThumb, relativeY, UI.CamDistBg.AbsoluteSize.Y)
end

function getFocusPart()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
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
        local rightOffset = rot.RightVector * 1
        Camera.CFrame = CFrame.lookAt(targetPos + rightOffset, focusPos + rightOffset)
    else Camera.CFrame = CFrame.new(focusPos + Vector3.new(0, 1.2, 0) + rot.LookVector * 1.5) * rot end
end))

local camDragInput = nil
track(UserInputService.InputBegan:Connect(function(input)
    if camState == 0 and not soulMode then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local vp = Camera and Camera.ViewportSize or Vector2.new(800, 600); local pos = input.Position
        for _, cont in pairs({UI.SliderContainer, UI.CamDistSliderContainer, UI.WalkSpeedSliderContainer, UI.JumpSliderContainer, UI.SpeedSliderContainer, UI.ClickMultiplierSliderContainer, UI.HitboxSliderContainer, UI.SoulSpeedSliderContainer, UI.SpinSliderContainer, UI.RagdollSliderContainer, UI.HandstandSliderContainer, UI.OrbitSliderContainer, UI.OrbitRadiusSliderContainer, UI.ListFrame, UI.ModelListFrame, UI.FollowCtrlFrame}) do
            if cont.Visible then
                local p, s = cont.AbsolutePosition, cont.AbsoluteSize
                if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
            end
        end
        if soulMode then
            if UI.SoulUpBtn.Visible then
                local p, s = UI.SoulUpBtn.AbsolutePosition, UI.SoulUpBtn.AbsoluteSize
                if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then return end
            end
            if UI.SoulDownBtn.Visible then
                local p, s = UI.SoulDownBtn.AbsolutePosition, UI.SoulDownBtn.AbsoluteSize
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
        if soulMode then targetYaw = targetYaw - delta.X; targetPitch = math.clamp(targetPitch - delta.Y, -85, 85)
        else camYaw = camYaw - delta.X; camPitch = math.clamp(camPitch - delta.Y, -60, 60) end
    end
end))

track(UserInputService.InputEnded:Connect(function(input) if input == camDragInput then camDragInput = nil end end))

function showPage(idx)
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
        if UI.SoulSpeedSliderContainer then UI.SoulSpeedSliderContainer.Visible = false end
    end
    if idx == 1 then
        if soulMode and UI.SoulSpeedSliderContainer then UI.SoulSpeedSliderContainer.Visible = true end
        if flying and UI.SpeedSliderContainer then UI.SpeedSliderContainer.Visible = true end
    end
    if idx ~= 2 then UI.SliderContainer.Visible = false; UI.CamDistSliderContainer.Visible = false end
    if idx ~= 3 then UI.HitboxSliderContainer.Visible = false end
    if idx ~= 4 then UI.ClickMultiplierSliderContainer.Visible = false; UI.SpinSliderContainer.Visible = false; UI.RagdollSliderContainer.Visible = false; UI.HandstandSliderContainer.Visible = false; UI.OrbitSliderContainer.Visible = false; UI.OrbitRadiusSliderContainer.Visible = false end

    if idx == 1 then UI.MainFrame.Size = UDim2.new(0, 195, 0, 227) 
    elseif idx == 2 then UI.MainFrame.Size = UDim2.new(0, 195, 0, 195) 
    elseif idx == 3 then UI.MainFrame.Size = UDim2.new(0, 195, 0, 195) 
    elseif idx == 4 then UI.MainFrame.Size = UDim2.new(0, 195, 0, 260) end
    
    updateSliderLayout()
    task.delay(0.05, refreshAllSliderThumbs)
end
UI.BasicTab.MouseButton1Click:Connect(function() showPage(1) end)
UI.DrawTab.MouseButton1Click:Connect(function() showPage(2) end)
UI.AdvTab.MouseButton1Click:Connect(function() showPage(3) end)
UI.EntTab.MouseButton1Click:Connect(function() showPage(4) end)

UI.FovBtn.MouseButton1Click:Connect(function() 
    UI.SliderContainer.Visible = not UI.SliderContainer.Visible 
    updateSliderLayout(); task.delay(0.05, refreshAllSliderThumbs)
end)
UI.WalkSpeedBtn.MouseButton1Click:Connect(function() 
    UI.WalkSpeedSliderContainer.Visible = not UI.WalkSpeedSliderContainer.Visible 
    updateSliderLayout(); task.delay(0.05, refreshAllSliderThumbs)
end)
UI.JumpBtn.MouseButton1Click:Connect(function() 
    UI.JumpSliderContainer.Visible = not UI.JumpSliderContainer.Visible 
    updateSliderLayout(); task.delay(0.05, refreshAllSliderThumbs)
end)

UI.SpinBtn.MouseButton1Click:Connect(function()
    spinEnabled = not spinEnabled
    if spinEnabled then
        UI.SpinSliderContainer.Visible = true
    else
        UI.SpinSliderContainer.Visible = false
    end
    updateSliderLayout()
    task.delay(0.05, refreshAllSliderThumbs)
end)

UI.RagdollBtn.MouseButton1Click:Connect(function()
    ragdollEnabled = not ragdollEnabled
    if ragdollEnabled then
        if flying then forceStopFly() end
        if soulMode then forceStopSoul() end
        if handstandEnabled then 
            handstandEnabled = false
            UI.HandstandSliderContainer.Visible = false
            local char = LocalPlayer.Character
            if char then
                local oldV = char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart:FindFirstChild("HandstandVel")
                if oldV then oldV:Destroy() end
                local oldO = char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart:FindFirstChild("HandstandOri")
                if oldO then oldO:Destroy() end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then 
                    hum.PlatformStand = false 
                    pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
                end
                if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
            end
        end
        UI.RagdollSliderContainer.Visible = true
    else
        UI.RagdollSliderContainer.Visible = false
        local char = LocalPlayer.Character
        if char and char:FindFirstChildOfClass("Humanoid") then
            char.Humanoid.PlatformStand = false
            local ang = char.HumanoidRootPart:FindFirstChild("RagdollAng")
            if ang then ang:Destroy() end
            if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
            char.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
    updateSliderLayout()
    task.delay(0.05, refreshAllSliderThumbs)
end)

UI.CamBtn.MouseButton1Click:Connect(function()
    if aimMode > 0 then
        aimMode = 0; aimLockTarget = nil; aimLockModel = nil
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
        UI.CamDistSliderContainer.Visible = true
    elseif camState == 2 then
        UI.CamDistSliderContainer.Visible = false
    else
        UI.CamDistSliderContainer.Visible = false
        updateHeadVisibility(); resetCamera()
    end
    updateSliderLayout()
end)

UI.UnlockCamBtn.MouseButton1Click:Connect(function()
    unlockDistanceEnabled = not unlockDistanceEnabled
    if unlockDistanceEnabled then
        LocalPlayer.CameraMaxZoomDistance = math.huge
    else
        LocalPlayer.CameraMaxZoomDistance = 128
    end
end)

UI.PlayerHitboxBtn.MouseButton1Click:Connect(function()
    if UI.HitboxSliderContainer.Visible and activeHitboxSliderType == "global_player" then
        UI.HitboxSliderContainer.Visible = false
    else
        activeHitboxSliderType = "global_player"; activeHitboxSliderTarget = nil; currentHitboxValue = globalPlayerHitboxMult
        UI.HitboxSliderContainer.Visible = true
        applyHitboxColor(true)
        updateThumbPos(UI.HitboxThumb, 1 - ((currentHitboxValue - 1) / 199), UI.HitboxBg.AbsoluteSize.Y)
    end
    updateSliderLayout()
end)

UI.NPCHitboxBtn.MouseButton1Click:Connect(function()
    if UI.HitboxSliderContainer.Visible and activeHitboxSliderType == "global_npc" then
        UI.HitboxSliderContainer.Visible = false
    else
        activeHitboxSliderType = "global_npc"; activeHitboxSliderTarget = nil; currentHitboxValue = globalNpcHitboxMult
        UI.HitboxSliderContainer.Visible = true
        applyHitboxColor(false)
        updateThumbPos(UI.HitboxThumb, 1 - ((currentHitboxValue - 1) / 199), UI.HitboxBg.AbsoluteSize.Y)
    end
    updateSliderLayout()
end)

UI.NpcFreezeBtn.MouseButton1Click:Connect(function()
    npcFreezeEnabled = not npcFreezeEnabled
    if npcFreezeEnabled then
        for model in pairs(npcCache) do applyNpcFreeze(model) end
    else
        for model in pairs(npcFreezeBackup) do releaseNpcFreeze(model) end
    end
end)

UI.NpcLiftBtn.MouseButton1Click:Connect(function()
    npcLiftEnabled = not npcLiftEnabled
    if npcLiftEnabled then
        for model in pairs(npcCache) do applyNpcLift(model) end
    else
        for model in pairs(npcLiftBackup) do releaseNpcLift(model) end
    end
end)

UI.HandstandBtn.MouseButton1Click:Connect(function()
    handstandEnabled = not handstandEnabled
    if handstandEnabled then
        if flying then forceStopFly() end
        if soulMode then forceStopSoul() end
        if ragdollEnabled then 
            ragdollEnabled = false
            UI.RagdollSliderContainer.Visible = false
        end
        
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = true
                if char:FindFirstChild("Animate") then char.Animate.Disabled = true end
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
            end
        end
        UI.HandstandSliderContainer.Visible = true
    else
        UI.HandstandSliderContainer.Visible = false
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp then
                for _, v in ipairs(hrp:GetChildren()) do
                    if v.Name == "HandstandOri" or v.Name == "HandstandVel" or v.Name == "HandstandAtt" then
                        v:Destroy()
                    end
                end
            end
            if hum then
                hum.PlatformStand = false
                if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end
    end
    updateSliderLayout()
    task.delay(0.05, refreshAllSliderThumbs)
end)

UI.OrbitBtn.MouseButton1Click:Connect(function()
    orbitEnabled = not orbitEnabled
    if orbitEnabled then
        UI.OrbitSliderContainer.Visible = true
        UI.OrbitRadiusSliderContainer.Visible = true
        orbitCenter = nil
    else
        UI.OrbitSliderContainer.Visible = false
        UI.OrbitRadiusSliderContainer.Visible = false
        orbitCenter = nil
        -- 清除绕圈吸力
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local op = hrp:FindFirstChild("OrbitPos")
                if op then op:Destroy() end
            end
        end
    end
    updateSliderLayout()
    task.delay(0.05, refreshAllSliderThumbs)
end)

UI.MagnetBtn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart
    local targetCF = hrp.CFrame * CFrame.new(0, 0, -6)
    local count = 0
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and model ~= char then
            local isChar = Players:GetPlayerFromCharacter(model)
            local hasHum = model:FindFirstChildOfClass("Humanoid")
            local isMonster = hasMonsterKeyword(model.Name)
            if not isChar and (hasHum or isMonster or model:FindFirstChildWhichIsA("BasePart")) then
                if not isExcluded(model.Name) then
                    pcall(function()
                        for _, p in ipairs(model:GetDescendants()) do
                            if p:IsA("BasePart") then
                                pcall(function() p:SetNetworkOwner(LocalPlayer) end)
                                p.Anchored = false
                            end
                        end
                        model:PivotTo(targetCF)
                        count = count + 1
                    end)
                end
            end
        end
    end
end)

UI.LockSpeedBtn.MouseButton1Click:Connect(function()
    lockSpeedEnabled = not lockSpeedEnabled
    if lockSpeedEnabled then
        local char = LocalPlayer.Character
        if char and char:FindFirstChildOfClass("Humanoid") then
            char.Humanoid.WalkSpeed = currentWalkSpeed
            char.Humanoid.JumpPower = currentJumpPower
        end
    end
end)

local STATE_LABEL = {ok = "正常", invis = "隐身", dead = "死亡", gone = "消失", recovered = "已恢复"}
local STATE_COLOR = {
    ok = Color3.fromRGB(255, 255, 255), invis = Color3.fromRGB(255, 200, 80), dead = Color3.fromRGB(180, 180, 180), gone = Color3.fromRGB(255, 80, 80), recovered = Color3.fromRGB(100, 220, 255),
}

function createListFrame(parent, titleText, closeCallback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 195, 0, 280); frame.Position = UDim2.new(1, 0, 0, 0)
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28); frame.BackgroundTransparency = 0.1
    frame.Visible = false; frame.ZIndex = 150; frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10); addStroke(frame, Color3.fromRGB(0, 220, 140))

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -30, 0, 30); title.BackgroundTransparency = 1; title.Text = titleText; title.TextColor3 = Color3.fromRGB(0, 230, 150)
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
    return frame, scroll
end

UI.ListFrame, UI.ScrollingFrame = createListFrame(UI.MainFrame, "玩家列表", function() UI.ListFrame.Visible = false; UI.FollowCtrlFrame.Visible = false end)
UI.ModelListFrame, UI.ModelScrollingFrame = createListFrame(UI.MainFrame, "模型列表", function() UI.ModelListFrame.Visible = false end)

UI.FollowCtrlFrame = Instance.new("Frame")
UI.FollowCtrlFrame.Name = "FollowCtrlFrame"
UI.FollowCtrlFrame.Size = UDim2.new(0, 100, 0, 88) 
UI.FollowCtrlFrame.Position = UDim2.new(1, -140, 0, 60)
UI.FollowCtrlFrame.AnchorPoint = Vector2.new(0, 0)
UI.FollowCtrlFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28); UI.FollowCtrlFrame.BackgroundTransparency = 0.2
UI.FollowCtrlFrame.Visible = false; UI.FollowCtrlFrame.ZIndex = 160; UI.FollowCtrlFrame.Parent = UI.ScreenGui
Instance.new("UICorner", UI.FollowCtrlFrame).CornerRadius = UDim.new(0, 6); addStroke(UI.FollowCtrlFrame, Color3.fromRGB(79, 255, 152))

local function createGridBtn(text, color, x, y, axis, delta)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 30, 0, 26)
    btn.Position = UDim2.new(0, x, 0, y)
    btn.BackgroundColor3 = color; btn.BackgroundTransparency = 0.1
    btn.Text = text; btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
    btn.ZIndex = 161; btn.Parent = UI.FollowCtrlFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    bindPressEffect(btn)
    btn.MouseButton1Click:Connect(function()
        if axis == "forward" then followOffsetForward = followOffsetForward + delta
        elseif axis == "right" then followOffsetRight = followOffsetRight + delta
        elseif axis == "up" then followOffsetUp = followOffsetUp + delta end
        followOffsetForward = math.clamp(followOffsetForward, -15, 15); followOffsetRight = math.clamp(followOffsetRight, -15, 15); followOffsetUp = math.clamp(followOffsetUp, -15, 15)
    end)
    return btn
end

createGridBtn("前", Color3.fromRGB(60, 90, 150), 5, 5, "forward", 0.5)
createGridBtn("上", Color3.fromRGB(60, 140, 80), 35, 5, "up", 0.5)
createGridBtn("后", Color3.fromRGB(60, 90, 150), 65, 5, "forward", -0.5)
createGridBtn("左", Color3.fromRGB(60, 90, 150), 5, 33, "right", -0.5)

local resetFollowBtn = createGridBtn("重", Color3.fromRGB(120, 60, 200), 35, 33, "none", 0) 
resetFollowBtn.MouseButton1Click:Connect(function() 
    followOffsetForward = -1.5; followOffsetRight = 0; followOffsetUp = 1 
end)

createGridBtn("右", Color3.fromRGB(60, 90, 150), 65, 33, "right", 0.5)
createGridBtn("下", Color3.fromRGB(140, 80, 60), 35, 61, "up", -0.5)

function muteCharacterSounds()
    local char = LocalPlayer.Character; if not char then return end
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("Sound") then
            if flySoundBackup[v] == nil then flySoundBackup[v] = v.Volume end
            if v.Volume ~= 0 then v.Volume = 0 end
        end
    end
end

function unmuteCharacterSounds()
    if flySoundConn then flySoundConn:Disconnect(); flySoundConn = nil end
    for sound, vol in pairs(flySoundBackup) do if sound and sound.Parent then pcall(function() sound.Volume = vol end) end end
    flySoundBackup = {}
end

function toggleSoul(state)
    if state then
        if not Camera then return end
        local char = LocalPlayer.Character; if not char or not char.Parent then return end
        local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        soulMode = true
        forceStopFly(); forceStopAirwalk(); forceStopStick()
        if hum then
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum.UseJumpPower = true
        end
        if camState ~= 0 then camState = 0; UI.CamDistSliderContainer.Visible = false end
        if aimMode > 0 then
            aimMode = 0; aimLockTarget = nil; aimLockModel = nil
            local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end
        end
        soulCFrame = CFrame.new(Camera.CFrame.Position); local look = Camera.CFrame.LookVector
        targetYaw = math.deg(math.atan2(-look.X, -look.Z)); targetPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        soulYaw, soulPitch = targetYaw, targetPitch
        Camera.CameraType = Enum.CameraType.Scriptable
        UI.SoulSpeedSliderContainer.Visible = (currentTab == 1)
        UI.SoulUpBtn.Visible = true; UI.SoulDownBtn.Visible = true
        updateSliderLayout(); refreshAllSliderThumbs()
    else
        soulMode = false
        local char = LocalPlayer.Character
        if char and char.Parent then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = currentWalkSpeed
                hum.JumpPower = currentJumpPower
                hum.UseJumpPower = true
            end
        end
        UI.SoulSpeedSliderContainer.Visible = false
        UI.SoulUpBtn.Visible = false; UI.SoulDownBtn.Visible = false
        touchFlyUp = false; touchFlyDown = false
        updateSliderLayout()
        resetCamera()
    end
end

track(RunService.RenderStepped:Connect(function()
    if not loopAlive() or not soulMode or not Camera then return end
    soulYaw = soulYaw + (targetYaw - soulYaw) * 0.5; soulPitch = soulPitch + (targetPitch - soulPitch) * 0.5
    local rot = CFrame.fromEulerAnglesYXZ(math.rad(soulPitch), math.rad(soulYaw), 0)
    local char = LocalPlayer.Character; local flyDir = getMoveWorldDir()
    local up = 0
    if touchFlyUp then up = up + 1 end
    if touchFlyDown then up = up - 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then up = up + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then up = up - 1 end
    if flyDir.Magnitude > 0.1 or math.abs(up) > 0.1 then 
        local actualSpeed = 1 + ((soulSpeed - 1) / 29) * 49
        local hDir = Vector3.new(flyDir.X, 0, flyDir.Z)
        local vSpeed = up * actualSpeed * 0.4
        if hDir.Magnitude > 0.01 then soulCFrame = soulCFrame + hDir.Unit * actualSpeed * 0.1 end
        if math.abs(vSpeed) > 0.01 then soulCFrame = soulCFrame + Vector3.new(0, vSpeed * 0.1, 0) end
    end
    Camera.CFrame = soulCFrame * rot
end))

function getCharState(p)
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

function getListKey()
    local names = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then 
            table.insert(names, p.Name .. ":" .. getCharState(p) .. "_" .. tostring(singlePlayerEsp[p]) .. "_" .. tostring(singlePlayerRay[p]) .. "_" .. tostring(singlePlayerHitboxMult[p]))
        end
    end
    table.sort(names)
    return tostring(aimLockTarget) .. "_" .. tostring(aimMode) .. "_" .. tostring(stickTarget) .. "_" .. tostring(stickMode) .. "_" .. tostring(watchTarget) .. "_" .. table.concat(names, ",")
end

function getModelListKey()
    local names = {}
    for model, t in pairs(npcCache) do 
        if model and model.Parent then 
            table.insert(names, model.Name .. "_" .. tostring(t) .. "_" .. tostring(singleModelEsp[model]) .. "_" .. tostring(singleModelRay[model]) .. "_" .. tostring(singleModelHitboxMult[model]) .. "_" .. tostring(singleModelFrozen[model])) 
        end 
    end
    table.sort(names)
    return tostring(aimLockModel) .. "_" .. tostring(aimMode) .. "_" .. tostring(stickModel) .. "_" .. tostring(watchModel) .. "_" .. table.concat(names, ",")
end

function stopWatching()
    flyLockDir = nil
    if not watchTarget and not watchModel then return end
    watchTarget = nil; watchModel = nil
    if Camera then
        Camera.CameraType = Enum.CameraType.Custom
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then Camera.CameraSubject = char.Humanoid end
    end
end

function startWatching(target)
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
    if camState ~= 0 then camState = 0; UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
    if soulMode then toggleSoul(false) end
    if aimMode > 0 then
        aimMode = 0; aimLockTarget = nil; aimLockModel = nil
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
    end
    if flying and Camera then flyLockDir = Camera.CFrame.LookVector end
    isCameraLocked = false
    if isPlayer then watchTarget = target; watchModel = nil else watchModel = target; watchTarget = nil end
    Camera.CameraType = Enum.CameraType.Custom; Camera.CameraSubject = hum or focusPart
end

local function createPlayerListFrame(p)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -4, 0, 30)
    f.BackgroundColor3 = Color3.fromRGB(30, 33, 40)
    f.ZIndex = 152
    f.Position = UDim2.new(0, 0, 0, 0)
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
    
    local n = Instance.new("TextLabel", f)
    n.Name = "NameLabel"
    n.Size = UDim2.new(1, -146, 1, 0); n.BackgroundTransparency = 1
    n.Font = Enum.Font.SourceSansBold; n.TextSize = 11
    n.Position = UDim2.new(0, 4, 0, 0); n.ZIndex = 153
    n.TextXAlignment = Enum.TextXAlignment.Left; n.TextTruncate = Enum.TextTruncate.AtEnd
    
    local function createBtn(name, xPos)
        local btn = Instance.new("TextButton")
        btn.Name = name; btn.Size = UDim2.new(0, 22, 0, 22); btn.Position = UDim2.new(1, xPos, 0, 4)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Font = Enum.Font.GothamBold; btn.TextSize = 10
        btn.ZIndex = 153
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        btn.Parent = f
        return btn
    end
    
    local fanBtn = createBtn("FanBtn", -142)
    fanBtn.Text = "倍"
    fanBtn.MouseButton1Click:Connect(function()
        local state = getCharState(p); local canAct = (state == "ok" or state == "invis" or state == "recovered")
        if not canAct then return end
        activeHitboxSliderType = "single_player"; activeHitboxSliderTarget = p; currentHitboxValue = singlePlayerHitboxMult[p] or 1
        UI.HitboxSliderContainer.Visible = true
        applyHitboxColor(true)
        updateThumbPos(UI.HitboxThumb, 1 - ((currentHitboxValue - 1) / 199), UI.HitboxBg.AbsoluteSize.Y)
        updateSliderLayout()
    end)
    
    local lk = createBtn("LkBtn", -118)
    lk.Text = "锁"
    lk.MouseButton1Click:Connect(function()
        local state = getCharState(p); local canAct = (state == "ok" or state == "invis" or state == "recovered")
        local isAimLocked = (aimMode == 3 and aimLockTarget == p)
        if not canAct and not isAimLocked then return end
        if aimMode == 3 and aimLockTarget == p then
            aimMode = 0; aimLockTarget = nil
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
            if not flying and not soulMode and camState == 0 and not watchTarget then resetCamera() end
        else
            local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
            if soulMode then forceStopSoul() end
            if watchTarget then stopWatching() end
            if camState ~= 0 then camState = 0; UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
            aimMode = 3; aimLockTarget = p; aimLockModel = nil
        end
        refreshList(true)
    end)
    
    local rBtn = createBtn("RayBtn", -94)
    rBtn.Text = "线"
    rBtn.MouseButton1Click:Connect(function()
        local state = getCharState(p); local canAct = (state == "ok" or state == "invis" or state == "recovered")
        if not canAct then return end
        singlePlayerRay[p] = not singlePlayerRay[p]
        refreshList(true)
    end)
    
    local eBtn = createBtn("EspBtn", -70)
    eBtn.Text = "透"
    eBtn.MouseButton1Click:Connect(function()
        local state = getCharState(p); local canAct = (state == "ok" or state == "invis" or state == "recovered")
        if not canAct then return end
        singlePlayerEsp[p] = not singlePlayerEsp[p]
        refreshList(true)
        updatePlayerESP()
    end)
    
    local wBtn = createBtn("WatchBtn", -46)
    wBtn.Text = "视"
    wBtn.MouseButton1Click:Connect(function()
        local state = getCharState(p); local canAct = (state == "ok" or state == "invis" or state == "recovered")
        if not canAct and watchTarget ~= p then return end
        if watchTarget == p then stopWatching() else startWatching(p) end
        refreshList(true)
    end)
    
    local sBtn = createBtn("StickBtn", -22)
    sBtn.Text = "跟"
    sBtn.MouseButton1Click:Connect(function()
        local state = getCharState(p); local canAct = (state == "ok" or state == "invis" or state == "recovered")
        if stickMode and stickTarget == p then forceStopStick(); refreshList(true); return end
        if not canAct then return end
        local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        forceStopFly(); forceStopAirwalk()
        if soulMode then forceStopSoul() end
        stickTarget = p; stickModel = nil; stickMode = true; UI.FollowCtrlFrame.Visible = true; refreshList(true)
        if not ghostModeEnabled then setNoclipState(true) end
    end)
    
    return f
end

local function updatePlayerListFrame(frame, p, state, canAct)
    local n = frame:FindFirstChild("NameLabel")
    if n then
        n.Text = p.Name .. " [" .. (STATE_LABEL[state] or "?") .. "]"
        n.TextColor3 = (aimMode == 3 and aimLockTarget == p) and Color3.fromRGB(255, 100, 100) or (STATE_COLOR[state] or Color3.fromRGB(255, 255, 255))
    end
    local hbMult = singlePlayerHitboxMult[p] or 1
    local fanBtn = frame:FindFirstChild("FanBtn")
    if fanBtn then
        fanBtn.Text = hbMult > 1 and (hbMult.."x") or "倍"
        fanBtn.BackgroundColor3 = hbMult > 1 and Color3.fromRGB(200, 100, 200) or Color3.fromRGB(80, 80, 90)
    end
    local isAimLocked = (aimMode == 3 and aimLockTarget == p)
    local lk = frame:FindFirstChild("LkBtn")
    if lk then
        lk.Text = isAimLocked and "解" or "锁"
        lk.BackgroundColor3 = isAimLocked and Color3.fromRGB(255, 100, 100) or (canAct and Color3.fromRGB(60, 90, 150) or Color3.fromRGB(50, 50, 50))
    end
    local isRay = singlePlayerRay[p]
    local rBtn = frame:FindFirstChild("RayBtn")
    if rBtn then
        rBtn.BackgroundColor3 = isRay and Color3.fromRGB(0, 255, 0) or (canAct and Color3.fromRGB(60, 140, 60) or Color3.fromRGB(50, 50, 50))
    end
    local isEsp = singlePlayerEsp[p]
    local eBtn = frame:FindFirstChild("EspBtn")
    if eBtn then
        eBtn.BackgroundColor3 = isEsp and Color3.fromRGB(0, 255, 0) or (canAct and Color3.fromRGB(60, 140, 60) or Color3.fromRGB(50, 50, 50))
    end
    local isWatching = (watchTarget == p)
    local wBtn = frame:FindFirstChild("WatchBtn")
    if wBtn then
        wBtn.Text = isWatching and "停" or "视"
        wBtn.BackgroundColor3 = isWatching and Color3.fromRGB(0, 200, 255) or (canAct and Color3.fromRGB(50, 120, 160) or Color3.fromRGB(50, 50, 50))
    end
    local isFollowing = (stickMode and stickTarget == p)
    local sBtn = frame:FindFirstChild("StickBtn")
    if sBtn then
        sBtn.Text = isFollowing and "停" or "跟"
        sBtn.BackgroundColor3 = isFollowing and Color3.fromRGB(79, 255, 152) or (canAct and Color3.fromRGB(180, 120, 40) or Color3.fromRGB(50, 50, 50))
    end
end

refreshList = function(force)
    if not force and os.clock() - lastPlayerListRefreshTime < 0.3 then return end
    lastPlayerListRefreshTime = os.clock()
    refreshRecoveredCache()
    if watchTarget then local wc = getCharForPlayer(watchTarget); local wh = wc and wc:FindFirstChildOfClass("Humanoid"); if not wh or wh.Health <= 0 then stopWatching() end end
    if stickMode and stickTarget then local sc = getCharForPlayer(stickTarget); local sh = sc and sc:FindFirstChildOfClass("Humanoid"); if not sh or sh.Health <= 0 then forceStopStick() end end
    if aimMode == 3 and aimLockTarget then local ac = getCharForPlayer(aimLockTarget); local ah = ac and ac:FindFirstChildOfClass("Humanoid"); if not ah or ah.Health <= 0 then aimMode = 0; aimLockTarget = nil end end
    local key = getListKey()
    if not force and key == lastListKey then return end
    lastListKey = key
    
    local sortedPlayers = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local isPinned = (aimLockTarget == p) or (stickTarget == p) or (watchTarget == p) or singlePlayerEsp[p] or singlePlayerRay[p] or (singlePlayerHitboxMult[p] and singlePlayerHitboxMult[p] > 1)
            table.insert(sortedPlayers, {player = p, pinned = isPinned})
        end
    end
    table.sort(sortedPlayers, function(a, b)
        if a.pinned and not b.pinned then return true end
        if not a.pinned and b.pinned then return false end
        return a.player.Name < b.player.Name
    end)

    local seen = {}
    local count = 0
    for i, data in ipairs(sortedPlayers) do
        local p = data.player
        seen[p] = true
        local state = getCharState(p)
        local canAct = (state == "ok" or state == "invis" or state == "recovered")
        
        local entry = playerListCache[p]
        local frame = entry and entry.frame
        local targetY = (i-1) * 34
        
        if not frame or not frame.Parent then
            frame = createPlayerListFrame(p)
            frame.Parent = UI.ScrollingFrame
            frame.Position = UDim2.new(0, 0, 0, targetY)
            playerListCache[p] = {frame = frame, tween = nil}
        else
            if entry.tween then entry.tween:Cancel() end
            entry.tween = TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 0, 0, targetY)
            })
            entry.tween:Play()
        end
        
        updatePlayerListFrame(frame, p, state, canAct)
        count = count + 1
    end
    
    for p, entry in pairs(playerListCache) do
        if not seen[p] then
            local frame = entry.frame
            if frame and frame.Parent then
                if entry.tween then entry.tween:Cancel() end
                local fade = TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundTransparency = 1})
                fade:Play()
                fade.Completed:Connect(function() if frame then frame:Destroy() end end)
            end
            playerListCache[p] = nil
        end
    end
    
    UI.ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

local function createModelListFrame(model)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -4, 0, 30)
    f.BackgroundColor3 = Color3.fromRGB(30, 33, 40)
    f.ZIndex = 152
    f.Position = UDim2.new(0, 0, 0, 0)
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
    
    local n = Instance.new("TextLabel", f)
    n.Name = "NameLabel"
    n.Size = UDim2.new(1, -170, 1, 0); n.BackgroundTransparency = 1
    n.Font = Enum.Font.SourceSansBold; n.TextSize = 11
    n.Position = UDim2.new(0, 4, 0, 0); n.ZIndex = 153
    n.TextXAlignment = Enum.TextXAlignment.Left; n.TextTruncate = Enum.TextTruncate.AtEnd
    
    local function createBtn(name, xPos)
        local btn = Instance.new("TextButton")
        btn.Name = name; btn.Size = UDim2.new(0, 22, 0, 22); btn.Position = UDim2.new(1, xPos, 0, 4)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Font = Enum.Font.GothamBold; btn.TextSize = 10
        btn.ZIndex = 153
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        btn.Parent = f
        return btn
    end
    
    local frzBtn = createBtn("FrzBtn", -166)
    frzBtn.Text = "定"
    frzBtn.MouseButton1Click:Connect(function()
        if singleModelFrozen[model] then
            releaseNpcFreeze(model)
            singleModelFrozen[model] = nil
        else
            applyNpcFreeze(model)
            singleModelFrozen[model] = true
        end
        refreshModelList(true)
    end)
    
    local fanBtn = createBtn("FanBtn", -142)
    fanBtn.Text = "倍"
    fanBtn.MouseButton1Click:Connect(function()
        activeHitboxSliderType = "single_npc"; activeHitboxSliderTarget = model; currentHitboxValue = singleModelHitboxMult[model] or 1
        UI.HitboxSliderContainer.Visible = true
        applyHitboxColor(false)
        updateThumbPos(UI.HitboxThumb, 1 - ((currentHitboxValue - 1) / 199), UI.HitboxBg.AbsoluteSize.Y)
        updateSliderLayout()
    end)
    
    local lk = createBtn("LkBtn", -118)
    lk.Text = "锁"
    lk.MouseButton1Click:Connect(function()
        local isAimLocked = (aimMode == 3 and aimLockModel == model)
        if aimMode == 3 and aimLockModel == model then
            aimMode = 0; aimLockModel = nil
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
            if not flying and not soulMode and camState == 0 and not watchTarget then resetCamera() end
        else
            local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
            if soulMode then forceStopSoul() end
            if watchTarget or watchModel then stopWatching() end
            if camState ~= 0 then camState = 0; UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
            aimMode = 3; aimLockModel = model; aimLockTarget = nil
        end
        refreshModelList(true)
    end)
    
    local rBtn = createBtn("RayBtn", -94)
    rBtn.Text = "线"
    rBtn.MouseButton1Click:Connect(function()
        singleModelRay[model] = not singleModelRay[model]
        refreshModelList(true)
    end)
    
    local eBtn = createBtn("EspBtn", -70)
    eBtn.Text = "透"
    eBtn.MouseButton1Click:Connect(function()
        singleModelEsp[model] = not singleModelEsp[model]
        refreshModelList(true)
        updateNpcHighlights()
    end)
    
    local wBtn = createBtn("WatchBtn", -46)
    wBtn.Text = "视"
    wBtn.MouseButton1Click:Connect(function() if watchModel == model then stopWatching() else startWatching(model) end; refreshModelList(true) end)
    
    local sBtn = createBtn("StickBtn", -22)
    sBtn.Text = "跟"
    sBtn.MouseButton1Click:Connect(function()
        if stickMode and stickModel == model then forceStopStick(); refreshModelList(true); return end
        local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        forceStopFly(); forceStopAirwalk()
        if soulMode then forceStopSoul() end
        stickModel = model; stickTarget = nil; stickMode = true; UI.FollowCtrlFrame.Visible = true; refreshModelList(true)
        if not ghostModeEnabled then setNoclipState(true) end
    end)
    
    return f
end

local function updateModelListFrame(frame, model)
    local n = frame:FindFirstChild("NameLabel")
    if n then
        n.Text = model.Name
        n.TextColor3 = (aimMode == 3 and aimLockModel == model) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
    end
    local isFrozen = singleModelFrozen[model]
    local frzBtn = frame:FindFirstChild("FrzBtn")
    if frzBtn then
        frzBtn.BackgroundColor3 = isFrozen and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(80, 80, 90)
    end
    local hbMult = singleModelHitboxMult[model] or 1
    local fanBtn = frame:FindFirstChild("FanBtn")
    if fanBtn then
        fanBtn.Text = hbMult > 1 and (hbMult.."x") or "倍"
        fanBtn.BackgroundColor3 = hbMult > 1 and Color3.fromRGB(200, 100, 200) or Color3.fromRGB(80, 80, 90)
    end
    local isAimLocked = (aimMode == 3 and aimLockModel == model)
    local lk = frame:FindFirstChild("LkBtn")
    if lk then
        lk.Text = isAimLocked and "解" or "锁"
        lk.BackgroundColor3 = isAimLocked and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(60, 90, 150)
    end
    local isRay = singleModelRay[model]
    local rBtn = frame:FindFirstChild("RayBtn")
    if rBtn then
        rBtn.BackgroundColor3 = isRay and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(60, 140, 60)
    end
    local isEsp = singleModelEsp[model]
    local eBtn = frame:FindFirstChild("EspBtn")
    if eBtn then
        eBtn.BackgroundColor3 = isEsp and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(60, 140, 60)
    end
    local isWatching = (watchModel == model)
    local wBtn = frame:FindFirstChild("WatchBtn")
    if wBtn then
        wBtn.Text = isWatching and "停" or "视"
        wBtn.BackgroundColor3 = isWatching and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(50, 120, 160)
    end
    local isFollowing = (stickMode and stickModel == model)
    local sBtn = frame:FindFirstChild("StickBtn")
    if sBtn then
        sBtn.Text = isFollowing and "停" or "跟"
        sBtn.BackgroundColor3 = isFollowing and Color3.fromRGB(79, 255, 152) or Color3.fromRGB(180, 120, 40)
    end
end

refreshModelList = function(force)
    if not force and os.clock() - lastModelListRefreshTime < 0.3 then return end
    lastModelListRefreshTime = os.clock()
    if watchModel then if not watchModel.Parent then stopWatching() end end
    if stickMode and stickModel then if not stickModel.Parent then forceStopStick() end end
    if aimMode == 3 and aimLockModel then if not aimLockModel.Parent then aimMode = 0; aimLockModel = nil end end
    local key = getModelListKey()
    if not force and key == lastModelListKey then return end
    lastModelListKey = key
    
    local sortedModels = {}
    for model, time in pairs(npcCache) do 
        if model and model.Parent then 
            local isPinned = (aimLockModel == model) or (stickModel == model) or (watchModel == model) or singleModelEsp[model] or singleModelRay[model] or (singleModelHitboxMult[model] and singleModelHitboxMult[model] > 1) or singleModelFrozen[model]
            table.insert(sortedModels, {model = model, time = time, pinned = isPinned}) 
        end 
    end
    table.sort(sortedModels, function(a, b) 
        if a.pinned and not b.pinned then return true end
        if not a.pinned and b.pinned then return false end
        return a.time < b.time 
    end)

    local seen = {}
    local count = 0
    for i, data in ipairs(sortedModels) do
        local model = data.model
        seen[model] = true
        local targetY = (i-1) * 34
        
        local entry = modelListCache[model]
        local frame = entry and entry.frame
        
        if not frame or not frame.Parent then
            frame = createModelListFrame(model)
            frame.Parent = UI.ModelScrollingFrame
            frame.Position = UDim2.new(0, 0, 0, targetY)
            modelListCache[model] = {frame = frame, tween = nil}
        else
            if entry.tween then entry.tween:Cancel() end
            entry.tween = TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 0, 0, targetY)
            })
            entry.tween:Play()
        end
        
        updateModelListFrame(frame, model)
        count = count + 1
    end
    
    for model, entry in pairs(modelListCache) do
        if not seen[model] then
            local frame = entry.frame
            if frame and frame.Parent then
                if entry.tween then entry.tween:Cancel() end
                local fade = TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundTransparency = 1})
                fade:Play()
                fade.Completed:Connect(function() if frame then frame:Destroy() end end)
            end
            modelListCache[model] = nil
        end
    end
    
    UI.ModelScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

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
                    task.spawn(function() task.wait(1.6); if UI.FlyBtn.Parent and UI.FlyBtn.Text == "载具飞行被服务端拒绝" then UI.FlyBtn.Text = "飞行: 35" end end)
                end
            end
        end
    end

    if stickMode and (stickTarget or stickModel) then
        local thrp = nil
        if stickTarget then local tchar = getCharForPlayer(stickTarget); thrp = tchar and getHRP(tchar)
        elseif stickModel then thrp = getModelHRP(stickModel) end
        if thrp then
            local targetCF = thrp.CFrame * CFrame.new(followOffsetRight, followOffsetUp, -followOffsetForward) + thrp.AssemblyLinearVelocity * 0.1
            
            if orbitEnabled then
                local angle = os.clock() * orbitSpeed
                targetCF = CFrame.lookAt(thrp.Position + Vector3.new(math.cos(angle) * orbitRadius, followOffsetUp, math.sin(angle) * orbitRadius), thrp.Position)
            end
            
            if not hrp:FindFirstChild("StickAlignPos") then
                local alignPos = Instance.new("AlignPosition", hrp)
                alignPos.Name = "StickAlignPos"
                alignPos.MaxForce = math.huge
                alignPos.Responsiveness = 1000
                local att = Instance.new("Attachment", hrp)
                att.Name = "StickAlignAtt"
                alignPos.Attachment0 = att
                alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                
                local bg = Instance.new("BodyGyro", hrp)
                bg.Name = "StickBodyGyro"
                bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bg.P = 10000
                bg.D = 500
            end
            
            local ap = hrp:FindFirstChild("StickAlignPos")
            local bg = hrp:FindFirstChild("StickBodyGyro")
            if ap and bg then
                ap.Position = targetCF.Position
                if handstandEnabled then
                    local camLook = Camera.CFrame.LookVector
                    local flatLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
                    bg.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook) * CFrame.Angles(math.rad(180), 0, 0)
                elseif spinEnabled then
                    bg.MaxTorque = Vector3.zero
                else
                    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                    bg.CFrame = targetCF
                end
            end
            
            hum.PlatformStand = true
            return
        end
    end
    
    -- 独立绕圈逻辑（未跟随时）
    if orbitEnabled and not stickMode then
        if not orbitCenter then orbitCenter = hrp.Position end
        local angle = os.clock() * orbitSpeed
        local targetPos = orbitCenter + Vector3.new(math.cos(angle) * orbitRadius, 0, math.sin(angle) * orbitRadius)
        
        if not hrp:FindFirstChild("OrbitPos") then
            local op = Instance.new("AlignPosition", hrp)
            op.Name = "OrbitPos"
            op.MaxForce = math.huge
            op.Responsiveness = 1000
            local att = Instance.new("Attachment", hrp)
            att.Name = "OrbitAtt"
            op.Attachment0 = att
            op.Mode = Enum.PositionAlignmentMode.OneAttachment
        end
        local op = hrp:FindFirstChild("OrbitPos")
        if op then op.Position = targetPos end
        
        -- 面向中心点或者朝向切线
        local lookAtCF = CFrame.lookAt(hrp.Position, targetPos + (targetPos - orbitCenter).Unit * 5)
        hrp.CFrame = hrp.CFrame:Lerp(CFrame.lookAt(hrp.Position, hrp.Position + (targetPos - orbitCenter).Unit), 0.2)
        
        hum.PlatformStand = true
        return
    end

    if not flying then return end
    soundCheckCounter = soundCheckCounter + 1
    if soundCheckCounter >= 60 then soundCheckCounter = 0; muteCharacterSounds() end
    if not bodyVelocity or not bodyVelocity.Parent or not bodyGyro or not bodyGyro.Parent then local ok = startPhysics(); if not ok then forceStopFly() end; return end
    if hum.SeatPart == nil and flyAttach ~= char:FindFirstChild("UpperTorso") and flyAttach ~= char:FindFirstChild("Torso") and flyAttach ~= hrp then local ok = startPhysics(); if not ok then forceStopFly() end; return end
    if hum.SeatPart and flyAttach ~= hum.SeatPart.AssemblyRootPart and flyAttach ~= hum.SeatPart then local ok = startPhysics(); if not ok then forceStopFly() end; return end
    if aimMode > 0 and not hum.SeatPart then bodyGyro.MaxTorque = Vector3.zero else bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9) end
    
    if flyLastPos and flyAttach then
        local dist = (flyAttach.Position - flyLastPos).Magnitude
        if dist > 60 then
            flyAttach.CFrame = CFrame.new(flyLastPos)
        end
        flyLastPos = flyAttach.Position
    end
    
    local mv = getMoveVector()
    local up = 0
    if touchFlyUp then up = up + 1 end
    if touchFlyDown then up = up - 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then up = up + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then up = up - 1 end
    local fullLook = flyLockDir or Camera.CFrame.LookVector
    local fullRight = Camera.CFrame.RightVector
    local flatLook = Vector3.new(fullLook.X, 0, fullLook.Z); if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end; flatLook = flatLook.Unit
    local flatRight = Vector3.new(fullRight.X, 0, fullRight.Z); if flatRight.Magnitude < 0.01 then flatRight = Vector3.new(1, 0, 0) end; flatRight = flatRight.Unit
    local worldMove = Vector3.zero
    if mv.Magnitude > 0.01 then
        worldMove = fullLook * (-mv.Z) + fullRight * mv.X
        if worldMove.Magnitude > 0.01 then worldMove = worldMove.Unit * math.min(mv.Magnitude, 1) end
    else
        local md = hum.MoveDirection
        if md.Magnitude > 0.1 then
            local fwd = md:Dot(flatLook)
            local rgt = md:Dot(flatRight)
            worldMove = fullLook * fwd + fullRight * rgt
            if worldMove.Magnitude > 0.01 then worldMove = worldMove.Unit * math.min(md.Magnitude, 1) end
        end
    end
    local flyDir = worldMove + Vector3.new(0, up, 0)
    local flySpeed = 35 + (speeds - 1) * (1000 - 35) / 9
    if flyMode == "ground" then
        local hDir = Vector3.new(flyDir.X, 0, flyDir.Z)
        if hDir.Magnitude > 0.1 then
            local hTarget = hDir.Unit * flySpeed
            bodyVelocity.MaxForce = Vector3.new(9e9, 0, 9e9)
            bodyVelocity.Velocity = Vector3.new(hTarget.X, 0, hTarget.Z)
        else
            bodyVelocity.MaxForce = Vector3.new(9e9, 0, 9e9)
            bodyVelocity.Velocity = Vector3.new(0, 0, 0)
        end
    else
        bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        local targetVel = flyDir.Magnitude > 0.1 and (flyDir.Unit * flySpeed) or Vector3.new(0, 0.1, 0)
        bodyVelocity.Velocity = targetVel
    end
    if flyAttach and flyDir.Magnitude > 0.1 and flyAttach.Parent and flyMode == "normal" then
        local actualVel = flyAttach.AssemblyLinearVelocity.Magnitude; local expected = flySpeed
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

track(RunService.Heartbeat:Connect(function()
    if not lockSpeedEnabled then return end
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") and not soulMode and not flying then
        local hum = char.Humanoid
        if hum.WalkSpeed ~= currentWalkSpeed and hum.WalkSpeed >= 0 then hum.WalkSpeed = currentWalkSpeed end
        if hum.JumpPower ~= currentJumpPower and hum.JumpPower >= 0 then hum.JumpPower = currentJumpPower end
    end
end))

UI.FlyBtn.MouseButton1Down:Connect(function()
    flyHoldStart = tick(); flyHoldTriggered = false
    local holdRef = flyHoldStart
    task.delay(1, function()
        if not loopAlive() then return end
        if flyHoldStart ~= holdRef or flyHoldTriggered then return end
        if tick() - flyHoldStart < 0.95 then return end
        flyHoldTriggered = true
        if not flying then
            if soulMode then forceStopSoul() end
            if ragdollEnabled then UI.RagdollBtn.MouseButton1Click:Connect(function() end); ragdollEnabled = false; end
            if handstandEnabled then 
                handstandEnabled = false
                local char = LocalPlayer.Character
                if char then
                    local oldV = char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart:FindFirstChild("HandstandVel")
                    if oldV then oldV:Destroy() end
                    local oldO = char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart:FindFirstChild("HandstandOri")
                    if oldO then oldO:Destroy() end
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then hum.PlatformStand = false end
                end
            end
            local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
            local ok = startPhysics()
            if ok then
                flying = true; flyMode = "ground"
                if currentTab == 1 then UI.SpeedSliderContainer.Visible = true end
                UI.SoulUpBtn.Visible = false; UI.SoulDownBtn.Visible = false
                task.defer(function()
                    task.wait(0.1)
                    if UI.SpeedSliderContainer.Visible then refreshAllSliderThumbs() end
                end)
            end
        elseif flyMode == "normal" then
            flyMode = "ground"
            UI.SoulUpBtn.Visible = false; UI.SoulDownBtn.Visible = false
        elseif flyMode == "ground" then
            flyMode = "normal"
            UI.SoulUpBtn.Visible = true; UI.SoulDownBtn.Visible = true
        end
        updateSliderLayout()
    end)
end)

UI.FlyBtn.MouseButton1Up:Connect(function()
    local wasHold = flyHoldTriggered
    local startTime = flyHoldStart
    flyHoldStart = nil; flyHoldTriggered = false
    if wasHold or not startTime then return end
    local holdTime = tick() - startTime
    if holdTime >= 0.95 then return end
    if not flying then
        if soulMode then forceStopSoul() end
        if ragdollEnabled then UI.RagdollBtn.MouseButton1Click:Connect(function() end); ragdollEnabled = false; end
        if handstandEnabled then 
            handstandEnabled = false
            local char = LocalPlayer.Character
            if char then
                local oldV = char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart:FindFirstChild("HandstandVel")
                if oldV then oldV:Destroy() end
                local oldO = char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart:FindFirstChild("HandstandOri")
                if oldO then oldO:Destroy() end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
            end
        end
        local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local ok, reason = startPhysics()
        if ok then
            flying = true; flyMode = "normal"
            if currentTab == 1 then UI.SpeedSliderContainer.Visible = true end
            UI.SoulUpBtn.Visible = true; UI.SoulDownBtn.Visible = true
            if flyWasVehicle and flyAttach then flyStartTime = os.clock(); flyStartPos = flyAttach.Position; flyDiagnosticPending = true end
            task.defer(function()
                task.wait(0.1)
                if UI.SpeedSliderContainer.Visible then refreshAllSliderThumbs() end
            end)
        else
            local msg = "无法飞行"
            if reason == "anchored" then msg = "载具锚定不可飞" elseif reason == "server_owned" then msg = "服务端拒绝载具" elseif reason == "no_attach" then msg = "无载具部件" end
            UI.FlyBtn.Text = msg
            task.spawn(function() task.wait(1.4); if UI.FlyBtn.Parent and UI.FlyBtn.Text == msg then UI.FlyBtn.Text = "飞行: 35" end end)
        end
    else
        forceStopFly()
        if camState == 0 and not soulMode and not watchTarget and not watchModel and aimMode == 0 then resetCamera() end
    end
    updateSliderLayout()
end)

UI.NoclipBtn.MouseButton1Click:Connect(function()
    setNoclipState(not ghostModeEnabled)
end)

UI.AimBtn.MouseButton1Click:Connect(function()
    if aimMode == 1 then
        aimMode = 2
    elseif aimMode == 2 then
        aimMode = 0
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); if hrp then local g = hrp:FindFirstChild("AimbotGyro"); if g then g:Destroy() end end
        if not flying and not soulMode and camState == 0 and not watchTarget and not watchModel then resetCamera() end
    else
        if aimMode == 3 then aimLockTarget = nil; aimLockModel = nil end
        local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        if soulMode then forceStopSoul() end
        if watchTarget or watchModel then stopWatching() end
        if camState ~= 0 then camState = 0; UI.CamDistSliderContainer.Visible = false; updateHeadVisibility() end
        aimMode = 1; aimLockTarget = nil; aimLockModel = nil
    end
end)

UI.OpenListBtn.MouseButton1Click:Connect(function()
    UI.ListFrame.Visible = not UI.ListFrame.Visible
    if UI.ListFrame.Visible then
        UI.ModelListFrame.Visible = false
        refreshList(true); if stickMode and stickTarget then UI.FollowCtrlFrame.Visible = true end
    else UI.FollowCtrlFrame.Visible = false end
end)

UI.OpenModelListBtn.MouseButton1Click:Connect(function()
    UI.ModelListFrame.Visible = not UI.ModelListFrame.Visible
    if UI.ModelListFrame.Visible then
        UI.ListFrame.Visible = false
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
end)

UI.AntiTPBtn.MouseButton1Click:Connect(function()
    antiTPEnabled = not antiTPEnabled
    if antiTPEnabled then lastTPCheckCF = CFrame.new() end
end)

UI.NativePopupBtn.MouseButton1Click:Connect(function()
    nativePopupBlockEnabled = not nativePopupBlockEnabled
    if nativePopupBlockEnabled then ensurePurchaseKillConn() else stopPurchaseKillConn() end
end)

UI.ZeroPromptBtn.MouseButton1Click:Connect(function()
    toggleZeroPrompt(not zeroPromptEnabled)
end)

UI.Click100Btn.MouseButton1Down:Connect(function()
    x100State.holdStart = tick(); x100State.holdTriggered = false
    task.spawn(function()
        task.wait(1)
        if x100State.holdStart and tick() - x100State.holdStart >= 0.95 then
            x100State.holdTriggered = true; x100State.enabled = false; unhookClickX100()
            UI.ClickMultiplierSliderContainer.Visible = false
        end
    end)
end)

UI.Click100Btn.MouseButton1Up:Connect(function()
    if x100State.holdStart then
        local holdTime = tick() - x100State.holdStart; x100State.holdStart = nil
        if not x100State.holdTriggered and holdTime < 1 then
            UI.ClickMultiplierSliderContainer.Visible = not UI.ClickMultiplierSliderContainer.Visible
            if UI.ClickMultiplierSliderContainer.Visible then
                local currentVal = x100State.multiplier or 100
                local relY = 1 - ((currentVal - 1) / 999)
                updateThumbPos(UI.ClickMultiplierThumb, relY, UI.ClickMultiplierBg.AbsoluteSize.Y)
            end
            updateSliderLayout()
        end
    end
end)

-- 全触碰 (重构版：过滤不可触碰、去重、每50个批量等待0.02s)
function doTouchOnce()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return 0 end
    local hrp = char.HumanoidRootPart
    local seen = setmetatable({}, {__mode = "k"})
    local batch = {}
    
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") and v.CanTouch and not v:IsDescendantOf(char) and not seen[v] then
            seen[v] = true
            table.insert(batch, v)
        end
    end
    
    local count = 0
    for i, part in ipairs(batch) do
        if not loopAlive() then break end
        pcall(function() 
            firetouchinterest(hrp, part, 0)
            firetouchinterest(hrp, part, 1)
        end)
        count = count + 1
        if i % 50 == 0 then task.wait(0.02) end
    end
    return count
end

UI.CollectTouchBtn.MouseButton1Click:Connect(function()
    if isTouchingLoop then return end
    isTouchingLoop = true
    task.spawn(function()
        doTouchOnce()
        if not loopAlive() then return end
        isTouchingLoop = false
    end)
end)

-- 全点击 (重构版：去重、批量等待)
function doClickOnce()
    local count = 0
    local seen = setmetatable({}, {__mode = "k"})
    local batch = {}
    
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ClickDetector") and not seen[v] then
            seen[v] = true
            table.insert(batch, v)
        end
    end
    
    for i, v in ipairs(batch) do
        if not loopAlive() then break end
        pcall(function() if fireclickdetector then fireclickdetector(v) end end)
        count = count + 1
        if i % 40 == 0 then task.wait(0.02) end
    end
    return count
end

UI.CollectClickBtn.MouseButton1Click:Connect(function()
    if isClickingLoop then return end
    isClickingLoop = true
    task.spawn(function()
        doClickOnce()
        if not loopAlive() then return end
        isClickingLoop = false
    end)
end)

-- 全交互 (点击开启，锁死全图交互，再点关闭)
function enableCollectInteract()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") then
            if not interactBackup[v] then
                interactBackup[v] = { MaxActivationDistance = v.MaxActivationDistance, RequiresLineOfSight = v.RequiresLineOfSight }
            end
            v.MaxActivationDistance = math.huge
            v.RequiresLineOfSight = false
        end
    end
end
function disableCollectInteract()
    for v, bak in pairs(interactBackup) do
        if v and v.Parent then
            v.MaxActivationDistance = bak.MaxActivationDistance
            v.RequiresLineOfSight = bak.RequiresLineOfSight
        end
    end
    interactBackup = {}
end

function doInteractOnce()
    local count = 0
    local seen = setmetatable({}, {__mode = "k"})
    local batch = {}
    
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") and v.Enabled and not seen[v] then
            seen[v] = true
            table.insert(batch, v)
        end
    end
    
    for i, v in ipairs(batch) do
        if not loopAlive() then break end
        pcall(function() if fireproximityprompt then fireproximityprompt(v) end end)
        count = count + 1
        if i % 40 == 0 then task.wait(0.02) end
    end
    return count
end

UI.CollectInteractBtn.MouseButton1Click:Connect(function()
    if isInteractingLoop then return end
    isInteractingLoop = true
    enableCollectInteract()
    task.spawn(function()
        doInteractOnce()
        if not loopAlive() then return end
        disableCollectInteract()
        isInteractingLoop = false
    end)
end)

UI.ItemEspBtn.MouseButton1Click:Connect(function()
    itemEspEnabled = not itemEspEnabled
    if itemEspEnabled then for _, obj in pairs(workspace:GetDescendants()) do if obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") then tryAddItemEsp(obj) end end
    else for obj, data in pairs(itemEspCache) do if data.billboard then data.billboard:Destroy() end end; itemEspCache = {} end
end)

UI.RayBtn.MouseButton1Click:Connect(function() 
    rayEnabled = not rayEnabled
    if not rayEnabled then
        for key, data in pairs(espLines) do
            local isPlayer = typeof(key) == "Instance" and key:IsA("Player")
            local isModel = typeof(key) == "Instance" and key:IsA("Model")
            if (isPlayer and not singlePlayerRay[key]) or (isModel and not singleModelRay[key]) then
                pcall(function() if data.line then data.line:Remove() end end)
                pcall(function() if data.label then data.label:Destroy() end end)
                espLines[key] = nil
            end
        end
    end
end)
UI.ModelEspBtn.MouseButton1Click:Connect(function() modelEspEnabled = not modelEspEnabled; if modelEspEnabled then for _, obj in pairs(workspace:GetDescendants()) do if obj:IsA("Model") then registerNPC(obj) end end; updateNpcHighlights() else for _, hl in pairs(npcHighlights) do pcall(function() hl:Destroy() end) end; npcHighlights = {}; clearRays("npc", true) end end)
UI.CrosshairBtn.MouseButton1Click:Connect(function() crosshairEnabled = not crosshairEnabled; UI.Crosshair.Visible = crosshairEnabled end)
UI.NoShadowBtn.MouseButton1Click:Connect(function() noShadowEnabled = not noShadowEnabled; if noShadowEnabled then Lighting.GlobalShadows = false; for _, v in pairs(workspace:GetDescendants()) do if v:IsA("BasePart") then if originalShadows[v] == nil then originalShadows[v] = v.CastShadow end; v.CastShadow = false end end else Lighting.GlobalShadows = true; for part, s in pairs(originalShadows) do if part and part.Parent then part.CastShadow = s end end; originalShadows = setmetatable({}, {__mode = "k"}) end end)
UI.SoulBtn.MouseButton1Click:Connect(function() if not soulMode and not Camera then return end; if not soulMode and (watchTarget or watchModel) then stopWatching() end; toggleSoul(not soulMode) end)
UI.EspBtn.MouseButton1Click:Connect(function() espEnabled = not espEnabled; if espEnabled then for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then hookPlayerCharacter(p) end end end; updatePlayerESP(); if not espEnabled then clearRays("player", true); for _, p in pairs(playerHighlights) do pcall(function() p:Destroy() end) end; playerHighlights = {} end end)
UI.DarkBtn.MouseButton1Click:Connect(function() darkRemoveOn = not darkRemoveOn; if darkRemoveOn then captureLighting(); applyDarkOnce(); scanAndHideDarkParts(); startForceOverride() else stopForceOverride(); restoreLighting(); restoreDarkParts(); if noShadowEnabled then Lighting.GlobalShadows = false end end end)

-- 【核心颜色与文本同步中枢】0.1秒心跳刷新，彻底替代手写改色
local uiUpdateAccum = 0
track(RunService.Heartbeat:Connect(function(dt)
    if not loopAlive() then return end
    uiUpdateAccum = uiUpdateAccum + dt
    if uiUpdateAccum >= 0.1 then
        uiUpdateAccum = 0
        
        local function setStaticBtn(btn, isOn)
            if isOn then
                btn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                btn.TextColor3 = Color3.fromRGB(0, 0, 0)
            end
        end
        
        setStaticBtn(UI.NoclipBtn, ghostModeEnabled)
        setStaticBtn(UI.AirWalkBtn, airwalkEnabled)
        setStaticBtn(UI.EspBtn, espEnabled)
        setStaticBtn(UI.ItemEspBtn, itemEspEnabled)
        setStaticBtn(UI.CrosshairBtn, crosshairEnabled)
        setStaticBtn(UI.ModelEspBtn, modelEspEnabled)
        setStaticBtn(UI.RayBtn, rayEnabled)
        setStaticBtn(UI.DarkBtn, darkRemoveOn)
        setStaticBtn(UI.NoShadowBtn, noShadowEnabled)
        setStaticBtn(UI.UnlockCamBtn, unlockDistanceEnabled)
        setStaticBtn(UI.OpenListBtn, UI.ListFrame.Visible)
        setStaticBtn(UI.OpenModelListBtn, UI.ModelListFrame.Visible)
        setStaticBtn(UI.CollectTouchBtn, isTouchingLoop)
        setStaticBtn(UI.CollectInteractBtn, isInteractingLoop)
        setStaticBtn(UI.CollectClickBtn, isClickingLoop)
        setStaticBtn(UI.AntiTPBtn, antiTPEnabled)
        setStaticBtn(UI.ZeroPromptBtn, zeroPromptEnabled)
        setStaticBtn(UI.LockSpeedBtn, lockSpeedEnabled)
        setStaticBtn(UI.NativePopupBtn, nativePopupBlockEnabled)
        setStaticBtn(UI.NpcFreezeBtn, npcFreezeEnabled)
        setStaticBtn(UI.NpcLiftBtn, npcLiftEnabled)
        setStaticBtn(UI.HandstandBtn, handstandEnabled)
        setStaticBtn(UI.OrbitBtn, orbitEnabled)
        
        if aimMode == 0 then setStaticBtn(UI.AimBtn, false); UI.AimBtn.Text = "自瞄: 关" else setStaticBtn(UI.AimBtn, true); UI.AimBtn.Text = aimMode == 1 and "自瞄: 软" or (aimMode == 2 and "自瞄: 硬" or "自瞄: 指定") end
        
        local function setSliderBtn(btn, isOn, baseColor, text)
            btn.Text = text
            if isOn then
                btn.BackgroundColor3 = baseColor:Lerp(Color3.fromRGB(255,255,255), 0.3)
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                btn.BackgroundColor3 = baseColor
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end
        
        local flyColor = Color3.fromRGB(180, 160, 40)
        local currentFlySpeed = math.floor(35 + (speeds - 1) * (1000 - 35) / 9)
        setSliderBtn(UI.FlyBtn, flying, flyColor, flying and ("飞行已开启:" .. currentFlySpeed) or ("飞行: " .. currentFlySpeed))
        
        local soulColor = Color3.fromRGB(140, 80, 60)
        local currentSoulSpeed = math.floor(1 + ((soulSpeed - 1) / 29) * 49)
        setSliderBtn(UI.SoulBtn, soulMode, soulColor, soulMode and ("出窍已开启:" .. currentSoulSpeed) or ("出窍: " .. currentSoulSpeed))
        
        setSliderBtn(UI.WalkSpeedBtn, false, Color3.fromRGB(60, 100, 150), "速度: " .. currentWalkSpeed)
        setSliderBtn(UI.JumpBtn, false, Color3.fromRGB(150, 100, 60), "跳高: " .. currentJumpPower)
        setSliderBtn(UI.FovBtn, false, Color3.fromRGB(60, 90, 150), "视野: " .. currentFov)
        
        local camText = camState == 0 and "视角: 关" or (camState == 1 and "视角: 第三" or "视角: 第一")
        setSliderBtn(UI.CamBtn, camState > 0, Color3.fromRGB(100, 50, 150), camText)
        
        setSliderBtn(UI.PlayerHitboxBtn, false, Color3.fromRGB(140, 140, 40), "玩家: " .. globalPlayerHitboxMult .. "x")
        setSliderBtn(UI.NPCHitboxBtn, false, Color3.fromRGB(160, 50, 50), "模型: " .. globalNpcHitboxMult .. "x")
        
        setSliderBtn(UI.Click100Btn, x100State.enabled, Color3.fromRGB(100, 50, 150), x100State.enabled and ("点击已开启:" .. x100State.multiplier) or ("点击: " .. x100State.multiplier))
        
        setSliderBtn(UI.RagdollBtn, ragdollEnabled, Color3.fromRGB(150, 50, 150), ragdollEnabled and ("玩偶已开启:" .. ragdollSpeed) or ("玩偶: " .. ragdollSpeed))
        setSliderBtn(UI.SpinBtn, spinEnabled, Color3.fromRGB(200, 100, 50), spinEnabled and ("旋转已开启:" .. spinSpeed) or ("旋转: " .. spinSpeed))
        setSliderBtn(UI.HandstandBtn, handstandEnabled, Color3.fromRGB(200, 200, 200), handstandEnabled and ("倒立已开启:" .. handstandSpeed) or ("倒立: " .. handstandSpeed))
        setSliderBtn(UI.OrbitBtn, orbitEnabled, Color3.fromRGB(100, 200, 100), orbitEnabled and ("绕已开启:" .. orbitSpeed) or ("绕: " .. orbitSpeed))
    end
end))

UI.ToggleBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then 
        UI.ListFrame.Visible = false; UI.ModelListFrame.Visible = false; UI.SliderContainer.Visible = false; UI.CamDistSliderContainer.Visible = false; UI.WalkSpeedSliderContainer.Visible = false; UI.JumpSliderContainer.Visible = false; UI.SpeedSliderContainer.Visible = false; UI.ClickMultiplierSliderContainer.Visible = false; UI.HitboxSliderContainer.Visible = false; UI.SoulSpeedSliderContainer.Visible = false; UI.SpinSliderContainer.Visible = false; UI.RagdollSliderContainer.Visible = false; UI.HandstandSliderContainer.Visible = false; UI.OrbitSliderContainer.Visible = false; UI.OrbitRadiusSliderContainer.Visible = false; UI.MainFrame.Size = UDim2.new(0, 195, 0, 30)
        -- 注意这里：收缩时不隐藏 UI.FollowCtrlFrame，只要跟随着就显示
    else 
        showPage(currentTab); if stickMode and (stickTarget or stickModel) then UI.FollowCtrlFrame.Visible = true end 
    end
    UI.SoulUpBtn.Visible = soulMode
    UI.SoulDownBtn.Visible = soulMode
    UI.TabBar.Visible = not isMinimized; UI.ContentFrame.Visible = not isMinimized; updateSliderLayout()
end)

track(LocalPlayer.CharacterAdded:Connect(function()
    local savedCamState = camState
    stopPhysics(); stopWatching(); restoreEnvCollides()
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false; restoreAllHitboxes()
    originalPlayerSizes, originalNPCSizes = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    singlePlayerHitboxMult, singleModelHitboxMult = {}, {}
    singleModelFrozen = {}
    globalPlayerHitboxMult = 1; globalNpcHitboxMult = 1
    noclip, aimMode, aimLockTarget, aimLockModel, stickTarget, stickModel = false, 0, nil, nil, nil, nil
    soulMode, stickMode, lastListKey, lastModelListKey, originalCollides = false, false, "", "", {}
    isTouchingLoop, isInteractingLoop, isClickingLoop, touchIsHeld, interactIsHeld, clickIsHeld = false, false, false, false, false, false
    touchFlyUp, touchFlyDown = false, false
    flyMode = "normal"; flyHoldStart = nil; flyHoldTriggered = false
    if ghostModeEnabled then ghostModeEnabled = false; restoreHazards() end
    if ghostConn then ghostConn:Disconnect(); ghostConn = nil end
    
    ragdollEnabled = false; spinEnabled = false; handstandEnabled = false; orbitEnabled = false
    if UI.RagdollBtn then UI.RagdollBtn.Text = "玩偶: 20"; UI.RagdollBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 150) end
    if UI.SpinBtn then UI.SpinBtn.Text = "旋转: 10"; UI.SpinBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 50) end
    if UI.HandstandBtn then UI.HandstandBtn.Text = "倒立: 18" end
    if UI.OrbitBtn then UI.OrbitBtn.Text = "绕: 关" end

    for p, entry in pairs(playerListCache) do if entry.frame and entry.frame.Parent then entry.frame:Destroy() end end
    playerListCache = {}
    for m, entry in pairs(modelListCache) do if entry.frame and entry.frame.Parent then entry.frame:Destroy() end end
    modelListCache = {}
    for obj, data in pairs(itemEspCache) do if data.billboard then data.billboard:Destroy() end end; itemEspCache = {}
    if itemEspEnabled then itemEspEnabled = false end
    currentFov = 70; if Camera then Camera.FieldOfView = currentFov end
    flying, UI.SpeedSliderContainer.Visible, UI.FollowCtrlFrame.Visible = false, false, false; isMinimized = false; UI.TabBar.Visible, UI.ContentFrame.Visible = true, true; showPage(1)
    task.wait(1); if not loopAlive() then return end

    local newChar = LocalPlayer.Character
    if newChar and newChar:FindFirstChildOfClass("Humanoid") then 
        newChar.Humanoid.WalkSpeed = currentWalkSpeed; newChar.Humanoid.JumpPower = currentJumpPower; newChar.Humanoid.UseJumpPower = true 
    end
    camState = 0; UI.CamDistSliderContainer.Visible = false
    if darkRemoveOn then applyDarkOnce(); startForceOverride() end; if noShadowEnabled then Lighting.GlobalShadows = false end
    resetCamera(); UI.ListFrame.Visible, UI.ModelListFrame.Visible = false, false; LocalPlayer.CameraMaxZoomDistance = 128
    UI.SoulSpeedSliderContainer.Visible = false; soulSpeed = 10
    unlockDistanceEnabled = false

    if espEnabled then for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then hookPlayerCharacter(p) end end; updatePlayerESP() end
    if modelEspEnabled then updateNpcHighlights() end

    if savedCamState ~= 0 then
        camState = savedCamState
        if camState == 1 then
            UI.CamDistSliderContainer.Visible = true
            local focus = getFocusPart()
            if focus and Camera then
                local look = Camera.CFrame.LookVector
                camYaw = math.deg(math.atan2(-look.X, -look.Z)); camPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
            end
        elseif camState == 2 then
            UI.CamDistSliderContainer.Visible = false
        end
        updateHeadVisibility()
    end

    updateSliderLayout()
    task.delay(0.05, refreshAllSliderThumbs)
end))

function closeAll()
    myLoop.Run = false; for _, c in pairs(myConns) do pcall(function() c:Disconnect() end) end
    if _G.FlyGuiV4_Conns == myConns then _G.FlyGuiV4_Conns = nil end; if _G.FlyGuiV4_Loop == myLoop then _G.FlyGuiV4_Loop = nil end; myConns = {}
    if zeroPromptConn then zeroPromptConn:Disconnect(); zeroPromptConn = nil end; unhookClickX100()
    stopPurchaseKillConn()
    for model in pairs(singleModelFrozen) do pcall(function() releaseNpcFreeze(model) end) end
    singleModelFrozen = {}
    if npcFreezeEnabled then
        for model in pairs(npcFreezeBackup) do releaseNpcFreeze(model) end
        npcFreezeEnabled = false
    end
    if npcLiftEnabled then
        for model in pairs(npcLiftBackup) do releaseNpcLift(model) end
        npcLiftEnabled = false
    end
    if soulMode then toggleSoul(false) end; stopWatching(); restoreEnvCollides()
    if airwalkPlate then airwalkPlate:Destroy(); airwalkPlate = nil end
    airwalkEnabled = false; camState = 0; UI.CamDistSliderContainer.Visible = false
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
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then 
            hum.PlatformStand = false
            hum.WalkSpeed = currentWalkSpeed; hum.JumpPower = currentJumpPower
            for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do pcall(function() hum:SetStateEnabled(state, true) end) end
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end) 
        end
        if char:FindFirstChild("Animate") then char.Animate.Disabled = false end; pcall(function() char:ScaleTo(1) end)
    end
    restoreAllHitboxes()
    if ghostModeEnabled then ghostModeEnabled = false; restoreHazards() end
    if ghostConn then ghostConn:Disconnect(); ghostConn = nil end
    for p, entry in pairs(playerListCache) do if entry.frame and entry.frame.Parent then entry.frame:Destroy() end end
    playerListCache = {}
    for m, entry in pairs(modelListCache) do if entry.frame and entry.frame.Parent then entry.frame:Destroy() end end
    modelListCache = {}
    noclip, flying, stickMode, soulMode, espEnabled, modelEspEnabled, noShadowEnabled, crosshairEnabled = false, false, false, false, false, false, false, false
    handstandEnabled = false; orbitEnabled = false
    touchFlyUp, touchFlyDown = false, false
    Lighting.GlobalShadows = true; LocalPlayer.CameraMaxZoomDistance = 128; if Camera then Camera.FieldOfView = 70 end; if UI.ScreenGui then UI.ScreenGui:Destroy() end
end
UI.CloseBtn.MouseButton1Click:Connect(function() pcall(closeAll) end)

-- 【整改】UI 已创建完成，现在延迟加载 PlayerModule（带 3 秒超时，不阻塞主线程）
task.spawn(function()
    loadPlayerModuleAsync()
end)
