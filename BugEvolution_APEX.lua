--[==[ Bug Evolution // Main Hub + Modern ESP ]==]--
local ApexLibrary = loadstring(game:HttpGet("https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua"))()

local Window = ApexLibrary.new({
    Title = "Bug Evolution // Main Hub",
    BrandText = "APEX_SYS",
    StatusText = "READY"
})

local AutoFarmTab = Window:CreateTab("AutoFarm", "FARMING & COLLECTION")
local StatsTab = Window:CreateTab("Stats", "MOVEMENT & PLAYER STATS")
local ESPTab = Window:CreateTab("ESP", "PLAYER VISUALS & STATS")
local EventTab = Window:CreateTab("EVENT", "EVENT & AUTOMATION")

_G.VoidOrbTeleport = false
_G.XpOrbTeleport = false
_G.AutoBugAttack = false
_G.SpinAllVoid = false

local currentBugTarget = nil
local currentBugTargetSince = nil
local teleportedBugs = setmetatable({}, { __mode = "k" })

local function isBugAlive(bug, bugsFolder)
    if not bug or not bugsFolder or bug.Parent ~= bugsFolder then
        return false
    end

    if bug:GetAttribute("Dead") == true or bug:GetAttribute("IsDead") == true then
        return false
    end

    local health = bug:GetAttribute("Health")
    if type(health) == "number" and health <= 0 then
        return false
    end

    local deadFlag = bug:FindFirstChild("Dead")
    if deadFlag and deadFlag:IsA("BoolValue") and deadFlag.Value then
        return false
    end

    local healthValue = bug:FindFirstChild("Health")
    if healthValue and (healthValue:IsA("NumberValue") or healthValue:IsA("IntValue")) and healthValue.Value <= 0 then
        return false
    end

    local humanoid = bug:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return false
    end

    return true
end

local function shouldCollectVoidOrbs()
    if not _G.VoidOrbTeleport then
        return false
    end

    if not _G.AutoBugAttack then
        return true
    end

    local bugsFolder = workspace:FindFirstChild("Bugs")
    return not isBugAlive(currentBugTarget, bugsFolder)
end

local function shouldWaitForVoidsBeforeNextBug()
    local voidFolder = workspace:FindFirstChild("VoidOrbs")
    return _G.VoidOrbTeleport and voidFolder and #voidFolder:GetChildren() > 0
end

-- 1. Shared XP and Void Orb collector
local lastOrbKind = "void"

local function getOrbPosition(orb)
    if not orb or not orb.Parent then
        return nil
    end

    if orb:IsA("BasePart") then
        return orb.Position
    elseif orb:IsA("Model") then
        local part = orb.PrimaryPart or orb:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position
    end

    return nil
end

local function findNextOrb(folderName, highestXPFirst)
    local folder = workspace:FindFirstChild(folderName)
    if not folder then
        return nil, nil
    end

    local orbs = folder:GetChildren()
    if highestXPFirst then
        table.sort(orbs, function(a, b)
            local xpA = a:GetAttribute("XP") or a:GetAttribute("Value") or 0
            local xpB = b:GetAttribute("XP") or b:GetAttribute("Value") or 0
            return xpA > xpB
        end)
    end

    for _, orb in ipairs(orbs) do
        local position = getOrbPosition(orb)
        if position then
            return orb, position
        end
    end

    return nil, nil
end

task.spawn(function()
    while true do
        task.wait(0.05)

        local canCollectVoid = shouldCollectVoidOrbs()
        local canCollectXP = _G.XpOrbTeleport
            and not _G.AutoBugAttack
            and (not _G.VoidOrbTeleport or canCollectVoid)

        if canCollectVoid or canCollectXP then
            local kind
            if canCollectVoid and canCollectXP then
                kind = lastOrbKind
                lastOrbKind = (lastOrbKind == "void") and "xp" or "void"
            elseif canCollectVoid then
                kind = "void"
            else
                kind = "xp"
            end

            local folderName = (kind == "void") and "VoidOrbs" or "Orbs"
            local orb, targetPos = findNextOrb(folderName, kind == "xp")

            if not orb and canCollectVoid and canCollectXP then
                kind = (kind == "void") and "xp" or "void"
                folderName = (kind == "void") and "VoidOrbs" or "Orbs"
                orb, targetPos = findNextOrb(folderName, kind == "xp")
            end

            if orb and targetPos then
                local player = game.Players.LocalPlayer
                local character = player.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")

                if hrp then
                    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
                end
            end
        end
    end
end)

-- 2. Auto Bug Attack Loop
task.spawn(function()
    while true do
        task.wait(0.5)
        if _G.AutoBugAttack then
            local player = game.Players.LocalPlayer
            local character = player.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            local bugsFolder = workspace:FindFirstChild("Bugs")
            
            if hrp and bugsFolder then
                local isTargetValid = false
                local targetTimedOut = false

                if isBugAlive(currentBugTarget, bugsFolder) then
                    if currentBugTargetSince and os.clock() - currentBugTargetSince >= 20 then
                        targetTimedOut = true
                    else
                        isTargetValid = true
                    end
                end
                
                if not isTargetValid and (targetTimedOut or not shouldWaitForVoidsBeforeNextBug()) then
                    currentBugTarget = nil
                    currentBugTargetSince = nil
                    
                    local bugs = bugsFolder:GetChildren()
                    if #bugs > 0 then
                        local zoneRank = {
                            meadow = 1,
                            pond = 8,
                            grove = 10,
                            woods = 15,
                            desert = 25,
                            ridge = 30,
                            caves = 40
                        }

                        table.sort(bugs, function(a, b)
                            local bossA = a:GetAttribute("Boss") == true
                            local bossB = b:GetAttribute("Boss") == true

                            if bossA ~= bossB then
                                return bossA
                            end

                            local zoneA = string.lower(tostring(a:GetAttribute("Zone") or ""))
                            local zoneB = string.lower(tostring(b:GetAttribute("Zone") or ""))
                            local rankA = zoneRank[zoneA] or 0
                            local rankB = zoneRank[zoneB] or 0

                            if rankA ~= rankB then
                                return rankA > rankB
                            end

                            local sizeA = a:GetAttribute("SizeMult") or 0
                            local sizeB = b:GetAttribute("SizeMult") or 0
                            return sizeA > sizeB
                        end)
                        
                        for _, bug in ipairs(bugs) do
                            if not teleportedBugs[bug] then
                                local targetPos = nil
                                if bug:IsA("BasePart") then
                                    targetPos = bug.Position
                                elseif bug:IsA("Model") then
                                    local part = bug.PrimaryPart
                                        or bug:FindFirstChildWhichIsA("BasePart", true)
                                    targetPos = part and part.Position
                                end
                                
                                if targetPos then
                                    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
                                    teleportedBugs[bug] = true
                                    currentBugTarget = bug
                                    currentBugTargetSince = os.clock()
                                    task.wait(1.5)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        else
            currentBugTarget = nil
        end
    end
end)

AutoFarmTab:CreateToggle(
    "Auto Bug Attack",
    "Prioritizes Boss, Zone, then SizeMult. Waits for each target to die or 20 seconds, then collects enabled Void Orbs before the next target. Turns off Auto XP.",
    false,
    function(state)
        _G.AutoBugAttack = state
        if state then
            _G.XpOrbTeleport = false
        else
            currentBugTarget = nil
        end
    end
)

AutoFarmTab:CreateToggle(
    "Auto Collect XP Orbs", 
    "Collects highest-value XP Orbs alongside enabled Void Orbs. Turns off Auto Bugs.", 
    false, 
    function(state)
        _G.XpOrbTeleport = state
        if state then
            _G.AutoBugAttack = false
        end
    end
)

AutoFarmTab:CreateToggle(
    "Auto Teleport Void Orbs", 
    "Collects Void Orbs alongside XP Orbs without one loop blocking the other. With Auto Bug active, waits for its target to die before collecting.", 
    false, 
    function(state)
        _G.VoidOrbTeleport = state
    end
)

local infiniteStaminaEnabled = false
game:GetService("RunService").Heartbeat:Connect(function()
    if infiniteStaminaEnabled then
        pcall(function()
            local Event = game:GetService("ReplicatedStorage").Remotes.SetSprint
            Event:FireServer(false)
        end)
    end
end)

StatsTab:CreateToggle(
    "Infinite Stamina",
    "Sends sprint state update on Heartbeat to prevent stamina drain.",
    false,
    function(state)
        infiniteStaminaEnabled = state
    end
)

-- EVENT Tab Toggle implementation (fires on frame via Heartbeat)
game:GetService("RunService").Heartbeat:Connect(function()
    if _G.SpinAllVoid then
        pcall(function()
            local Event = game:GetService("ReplicatedStorage").Remotes.VoidAction
            Event:InvokeServer(
                "Spin",
                nil
            )
        end)
    end
end)

EventTab:CreateToggle(
    "Spin All Void",
    "Invokes the VoidAction Spin remote on every frame.",
    false,
    function(state)
        _G.SpinAllVoid = state
    end
)

AutoFarmTab:CreateToggle(
    "Anti-AFK", 
    "Prevents you from getting kicked by Roblox for being idle.", 
    false, 
    function(state)
        _G.AntiAFKEnabled = state
        
        if _G.AntiAFKEnabled and not _G.AntiAFKConnection then
            local vu = game:GetService("VirtualUser")
            _G.AntiAFKConnection = game:GetService("Players").LocalPlayer.Idled:Connect(function()
                if _G.AntiAFKEnabled then
                    vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                    task.wait(1)
                    vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                end
            end)
        end
    end
)

local localPlayer = game.Players.LocalPlayer
local runService = game:GetService("RunService")

local originalWalkspeed = localPlayer:GetAttribute("WalkSpeed") or 16
local speedEnabled = false
local targetSpeed = 16

localPlayer:GetAttributeChangedSignal("WalkSpeed"):Connect(function()
    if not speedEnabled then
        local currentVal = localPlayer:GetAttribute("WalkSpeed")
        if currentVal then
            originalWalkspeed = currentVal
        end
    end
end)

runService.Heartbeat:Connect(function()
    if speedEnabled then
        local currentVal = localPlayer:GetAttribute("WalkSpeed")
        local desired = math.min(targetSpeed, 200)
        if currentVal ~= desired then
            localPlayer:SetAttribute("WalkSpeed", desired)
        end
    end
end)

StatsTab:CreateToggleWithInput(
    "Speed Changer",
    "Modifies LocalPlayer WalkSpeed attribute (Max 200) and restores original game speed when disabled.",
    false,
    16,
    function(state)
        speedEnabled = state
        if speedEnabled then
            local currentVal = localPlayer:GetAttribute("WalkSpeed")
            if currentVal then originalWalkspeed = currentVal end
            localPlayer:SetAttribute("WalkSpeed", math.min(targetSpeed, 200))
        else
            localPlayer:SetAttribute("WalkSpeed", originalWalkspeed)
        end
    end,
    function(value)
        targetSpeed = math.clamp(tonumber(value) or 16, 0, 200)
        if speedEnabled then
            localPlayer:SetAttribute("WalkSpeed", targetSpeed)
        end
    end
)

local originalJumpPower = localPlayer:GetAttribute("JumpPower") or 50
local jumpPowerEnabled = false
local targetJumpPower = 50

localPlayer:GetAttributeChangedSignal("JumpPower"):Connect(function()
    if not jumpPowerEnabled then
        local currentVal = localPlayer:GetAttribute("JumpPower")
        if currentVal then
            originalJumpPower = currentVal
        end
    end
end)

runService.Heartbeat:Connect(function()
    if jumpPowerEnabled then
        local currentVal = localPlayer:GetAttribute("JumpPower")
        local desired = math.min(targetJumpPower, 200)
        if currentVal ~= desired then
            localPlayer:SetAttribute("JumpPower", desired)
        end
    end
end)

StatsTab:CreateToggleWithInput(
    "JumpPower Changer",
    "Modifies LocalPlayer JumpPower attribute (Max 200) and restores original game jump power when disabled.",
    false,
    50,
    function(state)
        jumpPowerEnabled = state
        if jumpPowerEnabled then
            local currentVal = localPlayer:GetAttribute("JumpPower")
            if currentVal then originalJumpPower = currentVal end
            localPlayer:SetAttribute("JumpPower", math.min(targetJumpPower, 200))
        else
            localPlayer:SetAttribute("JumpPower", originalJumpPower)
        end
    end,
    function(value)
        targetJumpPower = math.clamp(tonumber(value) or 50, 0, 200)
        if jumpPowerEnabled then
            localPlayer:SetAttribute("JumpPower", targetJumpPower)
        end
    end
)

local infiniteJumpEnabled = false
game:GetService("UserInputService").JumpRequest:Connect(function()
    if infiniteJumpEnabled then
        local character = localPlayer.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.Jump = true
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end
end)

runService.Heartbeat:Connect(function()
    if infiniteJumpEnabled then
        local character = localPlayer.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.Space) then
                humanoid.Jump = true
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end
end)

StatsTab:CreateToggle(
    "Infinite Jump",
    "Allows you to jump infinitely in mid-air.",
    false,
    function(state)
        infiniteJumpEnabled = state
    end
)

-- ==========================================
-- 3. MODERN ESP & PLAYER STATS SYSTEM
-- ==========================================
_G.ESPEnabled = false
_G.ESPTracers = false

local espCache = {}

local function removeESP(player)
    if espCache[player] then
        for _, drawingObj in pairs(espCache[player]) do
            pcall(function() drawingObj:Remove() end)
        end
        espCache[player] = nil
    end
end

game.Players.PlayerRemoving:Connect(function(player)
    removeESP(player)
end)

runService.RenderStepped:Connect(function()
    if not _G.ESPEnabled then
        for player, _ in pairs(espCache) do
            removeESP(player)
        end
        return
    end

    local camera = workspace.CurrentCamera
    local viewportSize = camera.ViewportSize

    for _, player in ipairs(game.Players:GetPlayers()) do
        -- Skip LocalPlayer
        if player == localPlayer then
            removeESP(player)
        else
            local character = player.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")

            if character and hrp and humanoid and humanoid.Health > 0 then
                if not espCache[player] then
                    espCache[player] = {
                        Tracer = Drawing.new("Line"),
                        InfoText = Drawing.new("Text")
                    }
                    
                    local esp = espCache[player]
                    esp.InfoText.Size = 13
                    esp.InfoText.Center = true
                    esp.InfoText.Outline = true
                    esp.InfoText.Font = Drawing.Fonts.UI
                end

                local esp = espCache[player]
                local vector, onScreen = camera:WorldToViewportPoint(hrp.Position)

                -- Fixed Neon Cyan Color
                local espColor = Color3.fromRGB(0, 255, 255)

                if onScreen then
                    -- Tracers
                    if _G.ESPTracers then
                        esp.Tracer.Visible = true
                        esp.Tracer.From = Vector2.new(viewportSize.X / 2, viewportSize.Y)
                        esp.Tracer.To = Vector2.new(vector.X, vector.Y)
                        esp.Tracer.Color = espColor
                        esp.Tracer.Thickness = 1.2
                    else
                        esp.Tracer.Visible = false
                    end

                    -- Display Name & Username format: {display}({username}) + Level
                    local displayName = player.DisplayName
                    local userName = player.Name
                    local level = character:GetAttribute("Level") or "N/A"

                    esp.InfoText.Visible = true
                    esp.InfoText.Position = Vector2.new(vector.X, vector.Y - 40)
                    esp.InfoText.Color = espColor
                    esp.InfoText.Text = string.format("%s (%s)\nLevel: %s", displayName, userName, tostring(level))
                else
                    esp.Tracer.Visible = false
                    esp.InfoText.Visible = false
                end
            else
                removeESP(player)
            end
        end
    end
end)

-- ESP UI Elements in Dedicated Tab
ESPTab:CreateToggle(
    "Enable ESP",
    "Toggles sleek modern player ESP and character stat tracking.",
    false,
    function(state)
        _G.ESPEnabled = state
        if not state then
            for player, _ in pairs(espCache) do
                removeESP(player)
            end
        end
    end
)

ESPTab:CreateToggle(
    "Tracers",
    "Draws snapline tracers from the bottom center of the screen to players.",
    false,
    function(state)
        _G.ESPTracers = state
    end
)

local ConfigTab = Window:CreateTab("Config", "KEYBINDS & SCRIPT CONTROL")

ConfigTab:CreateKeybindCard()
ConfigTab:CreateKillButton("UNLOAD SCRIPT & CLEANUP", function()
    _G.AutoBugAttack = false
    _G.XpOrbTeleport = false
    _G.VoidOrbTeleport = false
    _G.AntiAFKEnabled = false
    _G.ESPEnabled = false
    _G.ESPTracers = false
    _G.SpinAllVoid = false

    -- Clear all ESP drawings on unload
    for player, _ in pairs(espCache) do
        removeESP(player)
    end

    if speedEnabled then
        localPlayer:SetAttribute("WalkSpeed", originalWalkspeed)
    end
    if jumpPowerEnabled then
        localPlayer:SetAttribute("JumpPower", originalJumpPower)
    end

    infiniteStaminaEnabled = false
    speedEnabled = false
    jumpPowerEnabled = false
    infiniteJumpEnabled = false
    if _G.AntiAFKConnection then
        _G.AntiAFKConnection:Disconnect()
        _G.AntiAFKConnection = nil
    end
    Window:Unload()
end)
