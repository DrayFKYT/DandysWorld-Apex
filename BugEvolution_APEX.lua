--[================================================================[
    BUG EVOLUTION [MOBILE / PC] // APEX UI EDITION
    ---------------------------------------------------------------
    Game: Bug Evolution
    PlaceId: 70650894743738
    UI framework: APEX_SYS (ApexLibraryPlus.lua)

    Features
      * Auto bug attack with boss / zone / size priority
      * Auto breakables, XP orbs, void orbs, rainbow orbs
      * Void spinner, playtime rewards, ability casting
      * Client speed / jump / flight / infinite stamina
      * Infinite jump, local ghost mode, auto stealth casting
      * Player / bug / orb / breakable ESP with colour pickers
      * Void guard: recovers from off-map falls, returns to the
        current bug target without resetting its timer
      * Persistent feature settings in BugEvolution_Config.json
      * Mandatory library CONFIG tab (anti-AFK + shared UI profile)

    Run order
        Run this script. It downloads ApexLibraryPlus.lua from GitHub
        and loads it automatically. Local copies are only a fallback.

    Library URL
        https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua?v=17
]================================================================]--

-- // Apex Library Loader
local LIBRARY_URL = "https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua?v=17"
local MIN_LAYOUT_REVISION = 17

local function IsPlusLibrary(library)
    return type(library) == "table"
        and library.Version ~= nil
        and type(library.new) == "function"
        and type(library.RegisterUnloadCallback) == "function"
        and (tonumber(library.LayoutRevision) or 0) >= MIN_LAYOUT_REVISION
end

local function CompileLibrary(source, sourceName)
    local compile = loadstring or load
    if type(compile) ~= "function" then
        return nil, "loadstring/load is not available"
    end
    local ok, chunk, err = pcall(compile, source, "@" .. tostring(sourceName or "ApexLibraryPlus.lua"))
    if not ok then
        return nil, tostring(chunk)
    end
    if type(chunk) ~= "function" then
        return nil, tostring(err or "compile failed")
    end
    return chunk
end

local function ExecuteLibrary(source, sourceName)
    local chunk, compileErr = CompileLibrary(source, sourceName)
    if not chunk then
        return nil, compileErr
    end
    local ok, library = pcall(chunk)
    if not ok then
        return nil, tostring(library)
    end
    if not IsPlusLibrary(library) then
        return nil, "file did not return a valid ApexLibrary table"
    end
    return library
end

local function LoadLibraryFromGitHub()
    local ok, source = pcall(function()
        if type(game) == "table" or typeof(game) == "Instance" then
            if type(game.HttpGet) == "function" then
                return game:HttpGet(LIBRARY_URL)
            end
            if type(game.HttpGetAsync) == "function" then
                return game:HttpGetAsync(LIBRARY_URL)
            end
        end
        if type(HttpGet) == "function" then
            return HttpGet(LIBRARY_URL)
        end
        error("HttpGet is not available in this executor")
    end)
    if not ok then
        return nil, tostring(source)
    end
    if type(source) ~= "string" or #source == 0 then
        return nil, "empty response"
    end
    return ExecuteLibrary(source, LIBRARY_URL)
end

local function LoadLibraryFromLocalFiles()
    if type(readfile) ~= "function" then
        return nil, "readfile is not available"
    end
    local candidates = {
        "ApexLibraryPlus.lua",
        "apex_dandys/ApexLibraryPlus.lua",
        "scripts/ApexLibraryPlus.lua"
    }
    local errors = {}
    for _, candidate in ipairs(candidates) do
        local ok, source = pcall(function()
            return readfile(candidate)
        end)
        if ok and type(source) == "string" and #source > 0 then
            local library, err = ExecuteLibrary(source, candidate)
            if library then
                return library
            end
            errors[#errors + 1] = candidate .. ": " .. tostring(err)
        elseif not ok then
            errors[#errors + 1] = candidate .. ": " .. tostring(source)
        end
    end
    return nil, table.concat(errors, "; ")
end

local function GetReusableLibrary()
    local ok, library = pcall(function()
        if getgenv then
            return getgenv().ApexLibrary
        end
        return nil
    end)
    if ok and IsPlusLibrary(library) then
        return library
    end
    return nil
end

local ApexLibrary = nil
local loadErrors = {}

local githubLibrary, githubErr = LoadLibraryFromGitHub()
if githubLibrary then
    ApexLibrary = githubLibrary
else
    loadErrors[#loadErrors + 1] = "GitHub: " .. tostring(githubErr)
end

if not ApexLibrary then
    ApexLibrary = GetReusableLibrary()
end

if not ApexLibrary then
    local localLibrary, localErr = LoadLibraryFromLocalFiles()
    if localLibrary then
        ApexLibrary = localLibrary
    else
        loadErrors[#loadErrors + 1] = "Local: " .. tostring(localErr)
    end
end

if not ApexLibrary then
    error("[Bug Evolution] Could not load ApexLibraryPlus.lua.\n"
        .. "  URL: " .. LIBRARY_URL .. "\n"
        .. "  " .. table.concat(loadErrors, "\n  ") .. "\n"
        .. "Make sure the repository and file are public on the main branch.")
end

if getgenv then
    pcall(function()
        getgenv().ApexLibrary = ApexLibrary
    end)
end

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local SCRIPT_VERSION = "BUG EVOLUTION // LUNARIS HUB 1.0"
local AUTHOR = "Drk_Duck"
local ConfigFile = "BugEvolution_Config.json"
local CONFIG_VERSION = 1
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)

-- // Session guard. Re-running replaces the old loops instead of stacking them.
local SESSION = {}
local ScriptRunning = true
if getgenv then
    pcall(function()
        local previousUnload = getgenv().BugEvolutionUnload
        if type(previousUnload) == "function" then
            pcall(previousUnload)
        end
        local previousCleanup = getgenv().BugEvolutionNamecallCleanup
        if type(previousCleanup) == "function" then
            pcall(previousCleanup)
        end
        getgenv().BugEvolutionSession = SESSION
    end)
end

local function SessionActive()
    if not ScriptRunning then
        return false
    end
    if getgenv then
        local ok, active = pcall(function()
            return getgenv().BugEvolutionSession == SESSION
        end)
        if ok then
            return active
        end
    end
    return true
end

-- // Helpers
local function Clamp(value, minimum, maximum)
    local number = tonumber(value)
    if not number then
        return minimum
    end
    if number < minimum then
        return minimum
    end
    if number > maximum then
        return maximum
    end
    return number
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function GetCharacter()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root and humanoid.Health > 0 then
        return character, humanoid, root
    end
    return nil
end

local function GetBugRoot(bug)
    if not bug then
        return nil
    end
    return bug:FindFirstChild("HumanoidRootPart") or bug:FindFirstChildWhichIsA("BasePart", true)
end

local function GetOrbPosition(orb)
    if not orb or not orb.Parent then
        return nil
    end
    if orb:IsA("BasePart") then
        return orb.Position
    end
    if orb:IsA("Model") then
        local part = orb:FindFirstChild("Hit")
            or orb.PrimaryPart
            or orb:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end
    return nil
end

local function IsBugAlive(bug, folder)
    if not bug or not folder or bug.Parent ~= folder then
        return false
    end
    local humanoid = bug:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        return true
    end
    return false
end

local function IsBreakableAlive(breakable, folder)
    if not breakable or not folder or breakable.Parent ~= folder then
        return false
    end
    local hp = tonumber(breakable:GetAttribute("HP"))
    if hp == nil then
        return true
    end
    return hp > 0
end

-- // Colour persistence helpers
local function ColorToTable(color)
    return {
        R = math.floor(color.R * 255 + 0.5),
        G = math.floor(color.G * 255 + 0.5),
        B = math.floor(color.B * 255 + 0.5)
    }
end

local function ColorFromTable(value, fallback)
    if type(value) ~= "table" then
        return fallback
    end
    return Color3.fromRGB(
        Clamp(value.R or 255, 0, 255),
        Clamp(value.G or 255, 0, 255),
        Clamp(value.B or 255, 0, 255)
    )
end

-- // Feature state
local State = {
    AutoBug = false,
    AutoBreak = false,
    AutoXPOrb = false,
    AutoVoidOrb = false,
    AutoRainbowOrb = false,
    AutoSpin = false,
    AutoPlaytime = false,
    AutoAbility1 = false,
    AutoAbility2 = false,
    AutoStealth = false,
    Speed = false,
    Jump = false,
    Fly = false,
    InfiniteJump = false,
    InfiniteStamina = false,
    Ghost = false,
    VoidGuard = true,
    ESPPlayers = false,
    ESPPlayerTracers = false,
    ESPBugs = false,
    ESPBugTracers = false,
    ESPOrbs = false,
    ESPVoidOrbs = false,
    ESPBreakables = false,
}

local Values = {
    Speed = 100,
    JumpPower = 100,
    FlySpeed = 80,
    AttackRange = 8,
    TargetTimeout = 20,
    ESPDistance = 1200,
}

local Colors = {
    PlayerESP = Color3.fromRGB(0, 255, 255),
    PlayerTracer = Color3.fromRGB(0, 200, 255),
    BugESP = Color3.fromRGB(255, 90, 90),
    BugTracer = Color3.fromRGB(255, 50, 50),
    OrbESP = Color3.fromRGB(255, 220, 80),
    VoidOrbESP = Color3.fromRGB(190, 90, 255),
    BreakableESP = Color3.fromRGB(70, 255, 150),
}

-- // Persisted script settings
local function LoadScriptConfig()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        return nil
    end
    local ok, decoded = pcall(function()
        if isfile(ConfigFile) then
            return HttpService:JSONDecode(readfile(ConfigFile))
        end
    end)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

local savedConfig = LoadScriptConfig()
if type(savedConfig) == "table" then
    if type(savedConfig.Features) == "table" then
        for key, value in pairs(savedConfig.Features) do
            if State[key] ~= nil then
                State[key] = value == true
            end
        end
    end
    if type(savedConfig.Values) == "table" then
        if savedConfig.Values.Speed ~= nil then
            Values.Speed = Clamp(savedConfig.Values.Speed, 0, 200)
        end
        if savedConfig.Values.JumpPower ~= nil then
            Values.JumpPower = Clamp(savedConfig.Values.JumpPower, 0, 1000)
        end
        if savedConfig.Values.FlySpeed ~= nil then
            Values.FlySpeed = Clamp(savedConfig.Values.FlySpeed, 0, 200)
        end
        if savedConfig.Values.AttackRange ~= nil then
            Values.AttackRange = Clamp(savedConfig.Values.AttackRange, 2, 200)
        end
        if savedConfig.Values.TargetTimeout ~= nil then
            Values.TargetTimeout = Clamp(savedConfig.Values.TargetTimeout, 5, 120)
        end
        if savedConfig.Values.ESPDistance ~= nil then
            Values.ESPDistance = Clamp(savedConfig.Values.ESPDistance, 100, 10000)
        end
    end
    if type(savedConfig.Colors) == "table" then
        Colors.PlayerESP = ColorFromTable(savedConfig.Colors.PlayerESP, Colors.PlayerESP)
        Colors.PlayerTracer = ColorFromTable(savedConfig.Colors.PlayerTracer, Colors.PlayerTracer)
        Colors.BugESP = ColorFromTable(savedConfig.Colors.BugESP, Colors.BugESP)
        Colors.BugTracer = ColorFromTable(savedConfig.Colors.BugTracer, Colors.BugTracer)
        Colors.OrbESP = ColorFromTable(savedConfig.Colors.OrbESP, Colors.OrbESP)
        Colors.VoidOrbESP = ColorFromTable(savedConfig.Colors.VoidOrbESP, Colors.VoidOrbESP)
        Colors.BreakableESP = ColorFromTable(savedConfig.Colors.BreakableESP, Colors.BreakableESP)
    end
end

local function SaveScriptConfig()
    if type(writefile) ~= "function" then
        return
    end
    local features = {}
    for key, value in pairs(State) do
        features[key] = value == true
    end
    local values = {
        Speed = Values.Speed,
        JumpPower = Values.JumpPower,
        FlySpeed = Values.FlySpeed,
        AttackRange = Values.AttackRange,
        TargetTimeout = Values.TargetTimeout,
        ESPDistance = Values.ESPDistance
    }
    local colors = {
        PlayerESP = ColorToTable(Colors.PlayerESP),
        PlayerTracer = ColorToTable(Colors.PlayerTracer),
        BugESP = ColorToTable(Colors.BugESP),
        BugTracer = ColorToTable(Colors.BugTracer),
        OrbESP = ColorToTable(Colors.OrbESP),
        VoidOrbESP = ColorToTable(Colors.VoidOrbESP),
        BreakableESP = ColorToTable(Colors.BreakableESP)
    }
    pcall(function()
        writefile(ConfigFile, HttpService:JSONEncode({
            ConfigVersion = CONFIG_VERSION,
            Features = features,
            Values = values,
            Colors = colors
        }))
    end)
end

-- // Shared state used by the combat loops and the void guard
local BugTarget = { Model = nil, Since = 0, LastPos = nil }
local BreakTarget = { Model = nil, Since = 0, AttackAt = 0 }
-- Set while the orb collector is mid-touch. Combat loops yield instead of
-- teleporting the character back before the server sees the orb touch.
local OrbBusy = false
-- Symmetric guard: set while a combat loop is repositioning and firing. The
-- orb collector yields so the server sees the new position before validating
-- the attack remote, otherwise every attack fired right after an orb teleport
-- is rejected for being out of range.
local CombatBusy = false
local SessionKills = 0
local SessionBreaks = 0
local DebugCounters = {
    AbilityTicks = 0,
    AbilityChecks = 0,
    AbilityCasts = 0,
    LastAbility = nil,
}
local LastSafeCFrame = nil
local LastVoidRecovery = 0
local VoidRecoveries = 0
local ESPAccumulator = 0
local ESPEntryCount = 0

-- // Status notifications
local ApexWindow = nil
local function Notify(text, duration)
    if ApexWindow then
        pcall(function()
            ApexWindow:SetStatus(tostring(text))
        end)
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "BUG EVOLUTION",
            Text = tostring(text),
            Duration = duration or 3
        })
    end)
end

-- // Executor compatibility helpers
local function MakeClosure(callback)
    if type(newcclosure) == "function" then
        local ok, closure = pcall(newcclosure, callback)
        if ok and type(closure) == "function" then
            return closure
        end
    end
    return callback
end

-- // Attribute spoofing. The game reads player attributes for movement,
-- // stamina and flight; returning the desired values here is what makes the
-- // client-side versions of those cheats work.
local Spoof = {
    WalkSpeed = false,
    JumpPower = false,
    Stamina = false,
    CanFly = false,
}

local NamecallCleanup = nil

local function RestoreMovement()
    local _, humanoid = GetCharacter()
    if not humanoid then
        return
    end
    local actualWalk = LocalPlayer:GetAttribute("WalkSpeed")
    local actualJump = LocalPlayer:GetAttribute("JumpPower")
    if IsFiniteNumber(actualWalk) then
        humanoid.WalkSpeed = actualWalk
    end
    if IsFiniteNumber(actualJump) then
        humanoid.UseJumpPower = true
        humanoid.JumpPower = actualJump
    end
end

local function InstallNamecallHook()
    if NamecallCleanup then
        return true
    end
    if type(getrawmetatable) ~= "function"
        or type(setreadonly) ~= "function"
        or type(getnamecallmethod) ~= "function" then
        return false
    end

    local metatable = getrawmetatable(game)
    if not metatable or type(metatable.__namecall) ~= "function" then
        return false
    end

    local original = metatable.__namecall
    local wrapper = MakeClosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "GetAttribute" and self == LocalPlayer then
            local attribute = select(1, ...)
            if attribute == "WalkSpeed" and Spoof.WalkSpeed then
                return Values.Speed
            end
            if attribute == "JumpPower" and Spoof.JumpPower then
                return Values.JumpPower
            end
            if attribute == "BaseJumpPower" and Spoof.JumpPower then
                return Values.JumpPower
            end
            if attribute == "Stamina" and Spoof.Stamina then
                return original(self, "MaxStamina")
            end
            if attribute == "Exhausted" and Spoof.Stamina then
                return false
            end
            if attribute == "FreeSprint" and Spoof.Stamina then
                return true
            end
            if attribute == "AlwaysSprint" and Spoof.Stamina then
                return true
            end
            if attribute == "CanFly" and Spoof.CanFly then
                return true
            end
        end
        return original(self, ...)
    end)

    local installed = pcall(function()
        pcall(setreadonly, metatable, false)
        metatable.__namecall = wrapper
        pcall(setreadonly, metatable, true)
    end)

    if not installed or metatable.__namecall ~= wrapper then
        pcall(function()
            pcall(setreadonly, metatable, false)
            if metatable.__namecall == wrapper then
                metatable.__namecall = original
            end
            pcall(setreadonly, metatable, true)
        end)
        return false
    end

    NamecallCleanup = function()
        pcall(function()
            pcall(setreadonly, metatable, false)
            if metatable.__namecall == wrapper then
                metatable.__namecall = original
            end
            pcall(setreadonly, metatable, true)
        end)
    end
    if getgenv then
        pcall(function()
            getgenv().BugEvolutionNamecallCleanup = NamecallCleanup
        end)
    end
    return true
end

local function RestoreNamecallHook()
    if NamecallCleanup then
        pcall(NamecallCleanup)
        NamecallCleanup = nil
    end
end

if not InstallNamecallHook() then
    Notify("Attribute guard unavailable on this executor", 5)
end

-- // Feature application callbacks
local FeatureApply = {}
local ToggleAPIs = {}

local function SetFeature(key, enabled, skipSave)
    if State[key] == nil then
        return
    end
    local active = enabled == true
    State[key] = active
    local apply = FeatureApply[key]
    if apply then
        pcall(apply, active)
    end
    -- Keep the visible switch in sync when a feature is changed from outside
    -- the UI (debug console, script API, or config reload).
    local api = ToggleAPIs[key]
    if api and type(api.GetEnabled) == "function" and type(api.SetEnabled) == "function" then
        if api:GetEnabled() ~= active then
            pcall(api.SetEnabled, api, active)
        end
    end
    if not skipSave then
        SaveScriptConfig()
    end
end

-- // Combat helpers
local ZoneRank = {
    meadow = 1,
    pond = 8,
    grove = 10,
    woods = 15,
    desert = 25,
    ridge = 30,
    caves = 40,
}

local function BugScore(bug)
    if not bug then
        return -math.huge
    end
    local zone = string.lower(tostring(bug:GetAttribute("Zone") or ""))
    local rank = ZoneRank[zone] or 0
    local boss = bug:GetAttribute("Boss") == true and 1 or 0
    local size = tonumber(bug:GetAttribute("SizeMult")) or 0
    local humanoid = bug:FindFirstChildOfClass("Humanoid")
    local health = humanoid and humanoid.MaxHealth or 0
    return boss * 1e9 + rank * 1e6 + size * 1e3 + health
end

local function FindBestBug(folder)
    local best, bestScore = nil, -math.huge
    if not folder then
        return nil
    end
    for _, bug in ipairs(folder:GetChildren()) do
        if IsBugAlive(bug, folder) then
            local score = BugScore(bug)
            if score > bestScore then
                best, bestScore = bug, score
            end
        end
    end
    return best
end

local function FindBestBreakable(folder)
    local best, bestScore = nil, -math.huge
    if not folder then
        return nil
    end
    for _, breakable in ipairs(folder:GetChildren()) do
        if IsBreakableAlive(breakable, folder) then
            local coins = tonumber(breakable:GetAttribute("Coins")) or 0
            local xp = tonumber(breakable:GetAttribute("XP")) or 0
            local hp = tonumber(breakable:GetAttribute("HP")) or 0
            local score = coins * 1e6 + xp * 1e3 - hp
            if score > bestScore then
                best, bestScore = breakable, score
            end
        end
    end
    return best
end

local function FindOrb(folder, useValue)
    local best, bestScore = nil, -math.huge
    if not folder then
        return nil, nil
    end
    for _, orb in ipairs(folder:GetChildren()) do
        local position = GetOrbPosition(orb)
        if position then
            local score = 0
            if useValue then
                score = tonumber(orb:GetAttribute("XP"))
                    or tonumber(orb:GetAttribute("Credits"))
                    or tonumber(orb:GetAttribute("Value"))
                    or 0
            end
            if score > bestScore then
                best, bestScore = orb, position
            end
        end
    end
    return best, bestScore
end

local function FireAttack(targetName)
    if not Remotes then
        return false
    end
    local attack = Remotes:FindFirstChild("Attack")
    if not attack then
        return false
    end
    local ok = pcall(function()
        attack:FireServer(targetName)
    end)
    return ok
end

local function CastAbility(slot)
    if not Remotes then
        return false
    end
    local useAbility = Remotes:FindFirstChild("UseAbility")
    local name = LocalPlayer:GetAttribute("Ability" .. tostring(slot))
    if not useAbility or type(name) ~= "string" or name == "" then
        return false
    end
    DebugCounters.LastCastSlot = slot
    DebugCounters.LastCastName = name
    -- The server takes the ability SLOT (1 or 2), not the ability name.
    -- Passing a name always resolved to slot 1 and silently miscast stealth
    -- abilities that lived in slot 2.
    return pcall(function()
        useAbility:FireServer(slot)
    end)
end

local function AbilityReady(slot)
    local readyAt = tonumber(LocalPlayer:GetAttribute("Ability" .. tostring(slot) .. "Ready")) or 0
    local now = Workspace:GetServerTimeNow()
    return now >= readyAt
end

local StealthAbilities = {
    Camouflage = true,
    SandVeil = true,
    Phase = true,
    Burrow = true,
}

local function GetStealthSlot()
    for slot = 1, 2 do
        local name = LocalPlayer:GetAttribute("Ability" .. tostring(slot))
        if type(name) == "string" and StealthAbilities[name] then
            return slot, name
        end
    end
    return nil, nil
end

-- // Void guard: random surface recovery + target recovery without resetting
-- // the target timer.
local function RandomSurfaceCFrame()
    local character = GetCharacter()
    if not character then
        return nil
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    params.RespectCanCollide = true
    params.IgnoreWater = true

    for _ = 1, 40 do
        local x = math.random(-820, 820)
        local z = math.random(-820, 820)
        local hit = Workspace:Raycast(Vector3.new(x, 900, z), Vector3.new(0, -3200, 0), params)
        if hit and hit.Normal.Y > 0.55 then
            return CFrame.new(hit.Position + Vector3.new(0, 6, 0))
        end
    end
    return nil
end

local function RecoverFromVoid()
    if os.clock() - LastVoidRecovery < 2 then
        return
    end
    LastVoidRecovery = os.clock()
    VoidRecoveries = VoidRecoveries + 1

    local _, _, root = GetCharacter()
    if not root then
        return
    end

    local bugsFolder = Workspace:FindFirstChild("Bugs")
    if BugTarget.Model and IsBugAlive(BugTarget.Model, bugsFolder) then
        local bugRoot = GetBugRoot(BugTarget.Model)
        if bugRoot then
            -- Deliberately do not touch BugTarget.Since. The timer continues
            -- as if the fall never happened.
            root.CFrame = CFrame.new(bugRoot.Position + Vector3.new(0, 6, 0))
            Notify("VOID RECOVERY // returned to target", 2)
            return
        end
    end

    local surface = RandomSurfaceCFrame()
    if surface then
        root.CFrame = surface
        Notify("VOID RECOVERY // random surface", 2)
    elseif LastSafeCFrame then
        root.CFrame = LastSafeCFrame
        Notify("VOID RECOVERY // last safe spot", 2)
    else
        root.CFrame = CFrame.new(0, 120, 0)
        Notify("VOID RECOVERY // emergency spawn", 2)
    end
end

local function TeleportToBug(bug)
    local _, _, root = GetCharacter()
    local bugRoot = GetBugRoot(bug)
    if not root or not bugRoot then
        return false
    end
    local stand = bugRoot.Position + Vector3.new(0, 4, 0)
    root.CFrame = CFrame.lookAt(stand, bugRoot.Position)
    return true
end

local function TeleportToNearestBug()
    local bugsFolder = Workspace:FindFirstChild("Bugs")
    local _, _, root = GetCharacter()
    if not bugsFolder or not root then
        return
    end
    local best, bestDistance = nil, math.huge
    for _, bug in ipairs(bugsFolder:GetChildren()) do
        local bugRoot = GetBugRoot(bug)
        if bugRoot and bug:FindFirstChildOfClass("Humanoid") then
            local distance = (bugRoot.Position - root.Position).Magnitude
            if distance < bestDistance then
                best, bestDistance = bug, distance
            end
        end
    end
    if best then
        TeleportToBug(best)
        Notify("TELEPORT // " .. best.Name, 2)
    else
        Notify("No bugs found", 2)
    end
end

-- // Auto bug attack loop
task.spawn(function()
    local nextAttack = 0
    while SessionActive() do
        task.wait(0.1)
        local bugsFolder = Workspace:FindFirstChild("Bugs")
        if not State.AutoBug then
            BugTarget.Model = nil
            BugTarget.Since = 0
            continue
        end

        local _, humanoid, root = GetCharacter()
        if not humanoid or not root or not bugsFolder then
            continue
        end
        if OrbBusy then
            continue
        end

        if BugTarget.Model and not IsBugAlive(BugTarget.Model, bugsFolder) then
            SessionKills = SessionKills + 1
            BugTarget.Model = nil
            BugTarget.Since = 0
            nextAttack = 0
        end

        if not BugTarget.Model then
            local bug = FindBestBug(bugsFolder)
            if bug then
                BugTarget.Model = bug
                BugTarget.Since = os.clock()
                local bugRoot = GetBugRoot(bug)
                BugTarget.LastPos = bugRoot and bugRoot.Position or nil
            end
        end

        local bug = BugTarget.Model
        if not bug then
            continue
        end

        if os.clock() - BugTarget.Since > Values.TargetTimeout then
            BugTarget.Model = nil
            BugTarget.Since = 0
            continue
        end

        local bugRoot = GetBugRoot(bug)
        if not bugRoot then
            BugTarget.Model = nil
            continue
        end

        local distance = (root.Position - bugRoot.Position).Magnitude
        local desired = math.clamp(Values.AttackRange, 2, 34)
        local needsReposition = distance > desired + 2 or not BugTarget.LastPos
            or (bugRoot.Position - BugTarget.LastPos).Magnitude > 8
        local standCFrame = nil
        if needsReposition then
            local direction = root.Position - bugRoot.Position
            if direction.Magnitude < 0.1 then
                direction = Vector3.new(0, 0, 1)
            end
            local flat = Vector3.new(direction.X, 0, direction.Z)
            if flat.Magnitude < 0.1 then
                flat = Vector3.new(0, 0, 1)
            end
            flat = flat.Unit * desired
            local stand = bugRoot.Position + flat + Vector3.new(0, 4, 0)
            standCFrame = CFrame.lookAt(stand, bugRoot.Position)
        end

        if os.clock() >= nextAttack then
            CombatBusy = true
            if standCFrame then
                root.CFrame = standCFrame
                BugTarget.LastPos = bugRoot.Position
                -- The server validates the attack against the replicated
                -- position, so give it a moment to see the new CFrame.
                task.wait(0.16)
            end
            if BugTarget.Model == bug and IsBugAlive(bug, bugsFolder) then
                FireAttack(bug.Name)
            end
            nextAttack = os.clock() + 0.9
            CombatBusy = false
        elseif standCFrame then
            root.CFrame = standCFrame
            BugTarget.LastPos = bugRoot.Position
        end
    end
end)

-- // Auto breakable loop
task.spawn(function()
    while SessionActive() do
        task.wait(0.1)
        local folder = Workspace:FindFirstChild("Breakables")
        if not State.AutoBreak or not folder then
            BreakTarget.Model = nil
            BreakTarget.Since = 0
            continue
        end

        local _, humanoid, root = GetCharacter()
        if not humanoid or not root then
            continue
        end
        if OrbBusy then
            continue
        end

        if BreakTarget.Model and not IsBreakableAlive(BreakTarget.Model, folder) then
            SessionBreaks = SessionBreaks + 1
            BreakTarget.Model = nil
            BreakTarget.Since = 0
        end

        if not BreakTarget.Model then
            BreakTarget.Model = FindBestBreakable(folder)
            BreakTarget.Since = os.clock()
            BreakTarget.AttackAt = 0
            if not BreakTarget.Model then
                continue
            end
        end

        if os.clock() - BreakTarget.Since > 10 then
            BreakTarget.Model = nil
            continue
        end

        local breakable = BreakTarget.Model
        local hitbox = breakable:FindFirstChild("Hitbox")
            or breakable:FindFirstChildWhichIsA("BasePart", true)
        if not hitbox then
            BreakTarget.Model = nil
            continue
        end

        local moveCFrame = nil
        if (root.Position - hitbox.Position).Magnitude > 8 then
            moveCFrame = CFrame.new(hitbox.Position + Vector3.new(0, 5, 0))
        end

        if os.clock() >= BreakTarget.AttackAt then
            CombatBusy = true
            if moveCFrame then
                root.CFrame = moveCFrame
                -- Reposition first; the server rejects attacks sent before
                -- the new position replicates.
                task.wait(0.16)
            end
            if BreakTarget.Model == breakable and IsBreakableAlive(breakable, folder) then
                FireAttack(breakable.Name)
            end
            BreakTarget.AttackAt = os.clock() + 0.9
            CombatBusy = false
        elseif moveCFrame then
            root.CFrame = moveCFrame
        end
    end
end)

-- // Orb collection loop. Runs independently of auto bug/auto break: the
-- combat loops yield while OrbBusy is set so they cannot teleport the
-- character away between the orb teleport and the touch interest. The old
-- version skipped forever whenever auto bug had a target, which is why none
-- of the orb toggles collected anything during normal farming.
local OrbDefinitions = {
    { Folder = "VoidOrbs", Toggle = "AutoVoidOrb", Bonus = 120 },
    { Folder = "RainbowOrbs", Toggle = "AutoRainbowOrb", Bonus = 60 },
    { Folder = "Orbs", Toggle = "AutoXPOrb", Bonus = 0 },
}

-- Orbs that failed a touch are skipped for a few seconds. Without this the
-- nearest-orb pick could sit on one unreachable orb forever, retrying every
-- 0.5 seconds and never collecting anything else.
local OrbRetryAfter = {}
local COMBAT_ORB_RADIUS = 150

local function FindOrbTarget(origin, anchor)
    local best, bestPosition, bestScore = nil, nil, math.huge
    local now = os.clock()
    for _, definition in ipairs(OrbDefinitions) do
        if State[definition.Toggle] then
            local folder = Workspace:FindFirstChild(definition.Folder)
            if folder then
                for _, orb in ipairs(folder:GetChildren()) do
                    local retryAt = OrbRetryAfter[orb]
                    if not retryAt or now >= retryAt then
                        local position = GetOrbPosition(orb)
                        if position then
                            -- While a combat loop owns a live target, only
                            -- take XP orbs near that fight. Crossing the map
                            -- on every pickup starves auto attack. Void and
                            -- rainbow orbs are rare and worth a detour.
                            local inRange = not anchor
                                or definition.Bonus > 0
                                or (position - anchor).Magnitude <= COMBAT_ORB_RADIUS
                            if inRange then
                                local distance = (position - origin).Magnitude
                                -- Void/rainbow orbs earn a detour; otherwise
                                -- the nearest enabled orb wins so XP collection
                                -- keeps moving instead of crossing the map.
                                local score = distance - definition.Bonus
                                if score < bestScore then
                                    best, bestPosition, bestScore = orb, position, score
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestPosition
end

task.spawn(function()
    local lastOrb = nil
    local lastOrbAt = 0
    while SessionActive() do
        task.wait(0.08)
        if not (State.AutoXPOrb or State.AutoVoidOrb or State.AutoRainbowOrb) then
            OrbBusy = false
            lastOrb = nil
            continue
        end
        -- CFrame flight owns the character position; orb teleports would
        -- fight the fly loop and snap right back.
        if State.Fly or CombatBusy then
            OrbBusy = false
            continue
        end

        local _, humanoid, root = GetCharacter()
        if not humanoid or not root or humanoid.Health <= 0 then
            OrbBusy = false
            continue
        end

        -- Drop retry entries for collected orbs and expired blacklists.
        if next(OrbRetryAfter) ~= nil then
            local now = os.clock()
            for orb, retryAt in pairs(OrbRetryAfter) do
                if not orb.Parent or now >= retryAt then
                    OrbRetryAfter[orb] = nil
                end
            end
        end

        -- Keep orb pickups local to the current fight so the combat loops can
        -- still land their attacks on schedule.
        local anchor = nil
        if State.AutoBug and BugTarget.Model then
            local bugsFolder = Workspace:FindFirstChild("Bugs")
            if bugsFolder and IsBugAlive(BugTarget.Model, bugsFolder) then
                local bugRoot = GetBugRoot(BugTarget.Model)
                anchor = bugRoot and bugRoot.Position or nil
            end
        end
        if not anchor and State.AutoBreak and BreakTarget.Model then
            local breakFolder = Workspace:FindFirstChild("Breakables")
            if breakFolder and IsBreakableAlive(BreakTarget.Model, breakFolder) then
                local hitbox = BreakTarget.Model:FindFirstChild("Hitbox")
                    or BreakTarget.Model:FindFirstChildWhichIsA("BasePart", true)
                anchor = hitbox and hitbox.Position or nil
            end
        end

        local orb, position = FindOrbTarget(root.Position, anchor)
        if not orb or not position then
            OrbBusy = false
            lastOrb = nil
            continue
        end

        -- If the pickup failed, retry the same orb after a short pause; if it
        -- succeeded the orb is gone and the next candidate is selected.
        if orb == lastOrb and os.clock() - lastOrbAt < 0.5 then
            OrbBusy = false
            continue
        end

        OrbBusy = true
        lastOrb = orb
        lastOrbAt = os.clock()
        -- Put the root centre on the orb. The old +2.5 offset left a 0.8-stud
        -- orb outside the root hitbox on some characters.
        root.CFrame = CFrame.new(position)
        task.wait(0.05)

        if orb.Parent then
            local touchPart = orb:IsA("BasePart") and orb
                or orb:FindFirstChild("Hit")
                or orb:FindFirstChildWhichIsA("BasePart", true)
            if touchPart and type(firetouchinterest) == "function" then
                pcall(function()
                    firetouchinterest(root, touchPart, 0)
                    task.wait(0.03)
                    firetouchinterest(root, touchPart, 1)
                end)
            end
        end
        task.wait(0.1)
        if orb.Parent then
            -- The touch did not collect it. Blacklist briefly and move on to
            -- a different orb instead of retrying this one forever.
            OrbRetryAfter[orb] = os.clock() + 3
        else
            OrbRetryAfter[orb] = nil
        end
        OrbBusy = false
    end
end)

-- // Auto void spinner
task.spawn(function()
    local nextSpin = 0
    while SessionActive() do
        task.wait(0.25)
        if not State.AutoSpin or os.clock() < nextSpin then
            continue
        end
        nextSpin = os.clock() + 1.2
        if Remotes then
            local voidAction = Remotes:FindFirstChild("VoidAction")
            if voidAction then
                pcall(function()
                    voidAction:InvokeServer("Spin", nil)
                end)
            end
        end
    end
end)

-- // Auto playtime reward claim
task.spawn(function()
    local nextCheck = 0
    while SessionActive() do
        task.wait(1)
        if not State.AutoPlaytime or os.clock() < nextCheck then
            continue
        end
        nextCheck = os.clock() + 8
        if Remotes then
            local rewards = Remotes:FindFirstChild("Rewards")
            if rewards then
                local ok, result = pcall(function()
                    return rewards:InvokeServer("Playtime")
                end)
                if ok and type(result) == "table"
                    and tonumber(result.Elapsed) and tonumber(result.At)
                    and result.Elapsed >= result.At then
                    local claimOk, claimed = pcall(function()
                        return rewards:InvokeServer("ClaimPlaytime")
                    end)
                    if claimOk and claimed == true then
                        Notify("PLAYTIME REWARD // claimed", 2)
                    end
                end
            end
        end
    end
end)

-- // Auto ability / stealth casting
task.spawn(function()
    local nextCast = { [1] = 0, [2] = 0 }
    while SessionActive() do
        task.wait(0.35)
        DebugCounters.AbilityTicks = DebugCounters.AbilityTicks + 1
        for slot = 1, 2 do
            if os.clock() < nextCast[slot] then
                continue
            end
            local name = LocalPlayer:GetAttribute("Ability" .. tostring(slot))
            local shouldCast = State["AutoAbility" .. tostring(slot)] == true
            if not shouldCast and State.AutoStealth and type(name) == "string" and StealthAbilities[name] then
                shouldCast = true
            end
            if shouldCast then
                DebugCounters.AbilityChecks = DebugCounters.AbilityChecks + 1
            end
            if shouldCast and type(name) == "string" and name ~= "" and AbilityReady(slot) then
                if CastAbility(slot) then
                    DebugCounters.AbilityCasts = DebugCounters.AbilityCasts + 1
                    DebugCounters.LastAbility = name
                    -- Retry quickly if the server rejected the cast because of
                    -- its global ability lockout. The ready timestamp check
                    -- prevents spamming an ability that actually accepted.
                    nextCast[slot] = os.clock() + 0.75
                end
            end
        end
    end
end)

-- // Movement / stamina enforcement
RunService.Heartbeat:Connect(function(deltaTime)
    if not SessionActive() then
        return
    end
    local character, humanoid, root = GetCharacter()
    if humanoid then
        if State.Speed and humanoid.WalkSpeed < Values.Speed then
            humanoid.WalkSpeed = Values.Speed
        end
        if State.Jump then
            humanoid.UseJumpPower = true
            if humanoid.JumpPower < Values.JumpPower then
                humanoid.JumpPower = Values.JumpPower
            end
        end
    end
    if character and humanoid and root then
        if humanoid.FloorMaterial ~= Enum.Material.Air and root.Position.Y > -200 then
            LastSafeCFrame = root.CFrame
        end
        if State.VoidGuard and os.clock() - LastVoidRecovery >= 2 then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { character }
            params.RespectCanCollide = true
            params.IgnoreWater = true
            local hit = Workspace:Raycast(root.Position, Vector3.new(0, -6000, 0), params)
            local falling = root.Velocity.Y < -25
            if (not hit and falling) or root.Position.Y < -260 then
                RecoverFromVoid()
            end
        end
    end
end)

-- // Custom CFrame flight (independent of the game's flight permission).
-- Mirrors the proven Cos_Apex implementation: track raw WASD/Space/LeftShift,
-- move relative to the camera, and keep an accumulated fly position so the
-- character does not drift or get pulled back by the game's controllers.
local FlyInputs = {
    W = false,
    A = false,
    S = false,
    D = false,
    Space = false,
    LeftShift = false
}
local FlyPosition = nil
local FlyRoot = nil
local FLY_RESYNC_DISTANCE = 30

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or not SessionActive() then
        return
    end
    local key = input.KeyCode.Name
    if FlyInputs[key] ~= nil then
        FlyInputs[key] = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode.Name
    if FlyInputs[key] ~= nil then
        FlyInputs[key] = false
    end
end)

local function ClearFlyState()
    FlyPosition = nil
    FlyRoot = nil
    for key in pairs(FlyInputs) do
        FlyInputs[key] = false
    end
end

RunService.RenderStepped:Connect(function(deltaTime)
    if not SessionActive() or not State.Fly then
        FlyPosition = nil
        FlyRoot = nil
        return
    end
    local _, humanoid, root = GetCharacter()
    if not humanoid or not root then
        FlyPosition = nil
        FlyRoot = nil
        return
    end

    if FlyRoot ~= root or not FlyPosition then
        FlyRoot = root
        FlyPosition = root.Position
    elseif (root.Position - FlyPosition).Magnitude > FLY_RESYNC_DISTANCE then
        -- External teleport (orb collection, respawn, scripted move): adopt
        -- the new position instead of snapping back to the old flight path.
        FlyPosition = root.Position
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local move = Vector3.new(0, 0, 0)
    if FlyInputs.W then
        move = move + camera.CFrame.LookVector
    end
    if FlyInputs.S then
        move = move - camera.CFrame.LookVector
    end
    if FlyInputs.D then
        move = move + camera.CFrame.RightVector
    end
    if FlyInputs.A then
        move = move - camera.CFrame.RightVector
    end
    if FlyInputs.Space then
        move = move + Vector3.new(0, 1, 0)
    end
    if FlyInputs.LeftShift then
        move = move - Vector3.new(0, 1, 0)
    end
    if move.Magnitude > 0 then
        move = move.Unit
    end

    FlyPosition = FlyPosition + move * Values.FlySpeed * deltaTime
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    root.CFrame = CFrame.new(FlyPosition) * root.CFrame.Rotation
end)

-- // Local ghost mode
local GhostBillboards = {}
RunService.RenderStepped:Connect(function()
    if not SessionActive() or not State.Ghost then
        return
    end
    local character = LocalPlayer.Character
    if not character then
        return
    end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.LocalTransparencyModifier = 1
        elseif descendant:IsA("BillboardGui") then
            if GhostBillboards[descendant] == nil then
                GhostBillboards[descendant] = descendant.Enabled
            end
            descendant.Enabled = false
        end
    end
end)

local function RestoreGhost()
    local character = LocalPlayer.Character
    if character then
        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.LocalTransparencyModifier = 0
            elseif descendant:IsA("BillboardGui") then
                descendant.Enabled = GhostBillboards[descendant] ~= false
            end
        end
    end
    for billboard, enabled in pairs(GhostBillboards) do
        if billboard.Parent then
            billboard.Enabled = enabled
        end
    end
    GhostBillboards = {}
end

-- // Infinite jump. ChangeState alone can be swallowed while the humanoid is
-- falling or the game has the jumping state disabled, so re-enable it and
-- apply an upward impulse derived from the configured jump power.
UserInputService.JumpRequest:Connect(function()
    if not SessionActive() or not State.InfiniteJump or State.Fly then
        return
    end
    local _, humanoid, root = GetCharacter()
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end
    local lift
    if humanoid.UseJumpPower == false then
        lift = math.sqrt(2 * (Workspace.Gravity or 196.2) * (humanoid.JumpHeight or 7.2))
    else
        lift = Spoof.JumpPower and Values.JumpPower or humanoid.JumpPower
    end
    if type(lift) ~= "number" or lift ~= lift or lift <= 0 then
        lift = 50
    end
    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    end)
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    local velocity = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(
        velocity.X,
        math.max(velocity.Y, lift),
        velocity.Z
    )
end)

-- // ESP system
local ESPStores = {
    Players = {},
    Bugs = {},
    Orbs = {},
    VoidOrbs = {},
    Breakables = {},
}

local function CreateESPEntry()
    local text = Drawing.new("Text")
    text.Font = Drawing.Fonts.UI
    text.Size = 13
    text.Center = true
    text.Outline = true
    text.Visible = false

    local line = Drawing.new("Line")
    line.Thickness = 1.2
    line.Visible = false

    return { Text = text, Line = line, LastSeen = 0 }
end

local function RemoveESPEntry(store, key)
    local entry = store[key]
    if not entry then
        return
    end
    pcall(function()
        entry.Text:Remove()
    end)
    pcall(function()
        entry.Line:Remove()
    end)
    store[key] = nil
end

local function ClearESPStore(store)
    for key in pairs(store) do
        RemoveESPEntry(store, key)
    end
end

local function ClearAllESP()
    for _, store in pairs(ESPStores) do
        ClearESPStore(store)
    end
end

local function UpdateESPEntry(store, key, position, label, color, showText, showTracer, camera, viewport, now)
    ESPEntryCount = ESPEntryCount + 1
    local entry = store[key]
    if not entry then
        entry = CreateESPEntry()
        store[key] = entry
    end
    entry.LastSeen = now

    local screen, onScreen = camera:WorldToViewportPoint(position)
    if onScreen and screen.Z > 0 then
        if showText then
            entry.Text.Visible = true
            entry.Text.Position = Vector2.new(screen.X, screen.Y - 24)
            entry.Text.Text = label
            entry.Text.Color = color
        else
            entry.Text.Visible = false
        end
        if showTracer then
            entry.Line.Visible = true
            entry.Line.From = Vector2.new(viewport.X / 2, viewport.Y)
            entry.Line.To = Vector2.new(screen.X, screen.Y)
            entry.Line.Color = color
        else
            entry.Line.Visible = false
        end
    else
        entry.Text.Visible = false
        entry.Line.Visible = false
    end
end

local function CleanupESPStore(store, now)
    for key, entry in pairs(store) do
        if now - (entry.LastSeen or 0) > 1.5 then
            RemoveESPEntry(store, key)
        end
    end
end

local function UpdateESP()
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local viewport = camera.ViewportSize
    local _, _, myRoot = GetCharacter()
    local origin = myRoot and myRoot.Position or Vector3.zero
    local maxDistance = Values.ESPDistance
    local now = os.clock()
    ESPEntryCount = 0

    -- Players
    if State.ESPPlayers or State.ESPPlayerTracers then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                if root and humanoid and humanoid.Health > 0
                    and (root.Position - origin).Magnitude <= maxDistance then
                    local level = player.Character:GetAttribute("Level")
                        or player:GetAttribute("Level")
                        or "?"
                    local label = string.format(
                        "%s (%s)\nLv %s | HP %d",
                        tostring(player.DisplayName),
                        tostring(player.Name),
                        tostring(level),
                        math.floor(humanoid.Health + 0.5)
                    )
                    UpdateESPEntry(
                        ESPStores.Players,
                        player,
                        root.Position + Vector3.new(0, 3, 0),
                        label,
                        Colors.PlayerESP,
                        State.ESPPlayers,
                        State.ESPPlayerTracers,
                        camera,
                        viewport,
                        now
                    )
                end
            end
        end
        CleanupESPStore(ESPStores.Players, now)
    elseif next(ESPStores.Players) ~= nil then
        ClearESPStore(ESPStores.Players)
    end

    -- Bugs
    local bugsFolder = Workspace:FindFirstChild("Bugs")
    if State.ESPBugs or State.ESPBugTracers then
        if bugsFolder then
            local candidates = {}
            for _, bug in ipairs(bugsFolder:GetChildren()) do
                local bugRoot = GetBugRoot(bug)
                local humanoid = bug:FindFirstChildOfClass("Humanoid")
                if bugRoot and humanoid and humanoid.Health > 0 then
                    local distance = (bugRoot.Position - origin).Magnitude
                    if distance <= maxDistance then
                        candidates[#candidates + 1] = {
                            Bug = bug,
                            Root = bugRoot,
                            Humanoid = humanoid,
                            Distance = distance,
                        }
                    end
                end
            end
            table.sort(candidates, function(a, b)
                return a.Distance < b.Distance
            end)
            local limit = math.min(#candidates, 140)
            for index = 1, limit do
                local candidate = candidates[index]
                local bug = candidate.Bug
                local humanoid = candidate.Humanoid
                local label = string.format(
                    "%s | %d/%d | %s",
                    tostring(bug.Name),
                    math.floor(humanoid.Health + 0.5),
                    math.floor(humanoid.MaxHealth + 0.5),
                    tostring(bug:GetAttribute("Zone") or "?")
                )
                if bug:GetAttribute("Boss") == true then
                    label = "[BOSS] " .. label
                end
                UpdateESPEntry(
                    ESPStores.Bugs,
                    bug,
                    candidate.Root.Position + Vector3.new(0, 4, 0),
                    label,
                    Colors.BugESP,
                    State.ESPBugs,
                    State.ESPBugTracers,
                    camera,
                    viewport,
                    now
                )
            end
        end
        CleanupESPStore(ESPStores.Bugs, now)
    elseif next(ESPStores.Bugs) ~= nil then
        ClearESPStore(ESPStores.Bugs)
    end

    -- Orbs (XP and rainbow share a pool)
    local orbFolder = Workspace:FindFirstChild("Orbs")
    local rainbowFolder = Workspace:FindFirstChild("RainbowOrbs")
    if State.ESPOrbs then
        local candidates = {}
        local function AddOrb(orb, isRainbow)
            local position = GetOrbPosition(orb)
            if position and (position - origin).Magnitude <= maxDistance then
                candidates[#candidates + 1] = {
                    Orb = orb,
                    Position = position,
                    Distance = (position - origin).Magnitude,
                    Rainbow = isRainbow
                }
            end
        end
        if orbFolder then
            for _, orb in ipairs(orbFolder:GetChildren()) do
                AddOrb(orb, false)
            end
        end
        if rainbowFolder then
            for _, orb in ipairs(rainbowFolder:GetChildren()) do
                AddOrb(orb, true)
            end
        end
        table.sort(candidates, function(a, b)
            return a.Distance < b.Distance
        end)
        local limit = math.min(#candidates, 100)
        for index = 1, limit do
            local candidate = candidates[index]
            local value = candidate.Orb:GetAttribute("XP")
                or candidate.Orb:GetAttribute("Value")
            local label
            if candidate.Rainbow then
                label = "RAINBOW ORB"
            else
                label = "ORB +" .. tostring(value or "?") .. " XP"
            end
            UpdateESPEntry(
                ESPStores.Orbs,
                candidate.Orb,
                candidate.Position + Vector3.new(0, 2, 0),
                label,
                Colors.OrbESP,
                true,
                false,
                camera,
                viewport,
                now
            )
        end
        CleanupESPStore(ESPStores.Orbs, now)
    elseif next(ESPStores.Orbs) ~= nil then
        ClearESPStore(ESPStores.Orbs)
    end

    -- Void orbs
    local voidFolder = Workspace:FindFirstChild("VoidOrbs")
    if State.ESPVoidOrbs then
        if voidFolder then
            for _, orb in ipairs(voidFolder:GetChildren()) do
                local position = GetOrbPosition(orb)
                if position and (position - origin).Magnitude <= maxDistance then
                    local credits = orb:GetAttribute("Credits") or 25
                    UpdateESPEntry(
                        ESPStores.VoidOrbs,
                        orb,
                        position + Vector3.new(0, 2, 0),
                        "VOID ORB +" .. tostring(credits) .. "c",
                        Colors.VoidOrbESP,
                        true,
                        false,
                        camera,
                        viewport,
                        now
                    )
                end
            end
        end
        CleanupESPStore(ESPStores.VoidOrbs, now)
    elseif next(ESPStores.VoidOrbs) ~= nil then
        ClearESPStore(ESPStores.VoidOrbs)
    end

    -- Breakables
    local breakFolder = Workspace:FindFirstChild("Breakables")
    if State.ESPBreakables then
        if breakFolder then
            local candidates = {}
            for _, breakable in ipairs(breakFolder:GetChildren()) do
                local hitbox = breakable:FindFirstChild("Hitbox")
                    or breakable:FindFirstChildWhichIsA("BasePart", true)
                if hitbox then
                    local distance = (hitbox.Position - origin).Magnitude
                    if distance <= maxDistance then
                        candidates[#candidates + 1] = {
                            Breakable = breakable,
                            Position = hitbox.Position,
                            Distance = distance
                        }
                    end
                end
            end
            table.sort(candidates, function(a, b)
                return a.Distance < b.Distance
            end)
            local limit = math.min(#candidates, 100)
            for index = 1, limit do
                local candidate = candidates[index]
                local breakable = candidate.Breakable
                local label = string.format(
                    "%s | %s/%s | %sc",
                    tostring(breakable.Name),
                    tostring(breakable:GetAttribute("HP") or "?"),
                    tostring(breakable:GetAttribute("MaxHP") or "?"),
                    tostring(breakable:GetAttribute("Coins") or "?")
                )
                UpdateESPEntry(
                    ESPStores.Breakables,
                    breakable,
                    candidate.Position + Vector3.new(0, 3, 0),
                    label,
                    Colors.BreakableESP,
                    true,
                    false,
                    camera,
                    viewport,
                    now
                )
            end
        end
        CleanupESPStore(ESPStores.Breakables, now)
    elseif next(ESPStores.Breakables) ~= nil then
        ClearESPStore(ESPStores.Breakables)
    end
end

RunService.RenderStepped:Connect(function(deltaTime)
    if not SessionActive() then
        return
    end
    ESPAccumulator = ESPAccumulator + deltaTime
    -- 40 Hz refresh instead of the old 12.5 Hz keeps text and tracers glued to
    -- moving targets. Dense scenes (all ESP categories on, hundreds of nearby
    -- targets) drop to 25 Hz so the drawing work cannot halve the frame rate.
    local interval = ESPEntryCount > 240 and 0.04 or 0.025
    if ESPAccumulator >= interval then
        ESPAccumulator = 0
        UpdateESP()
    end
end)

-- // UI
ApexWindow = ApexLibrary.new({
    Title = "BUG EVOLUTION // LUNARIS HUB",
    BrandText = "BUG_EVO // LUNARIS HUB",
    StatusText = "READY",
})

local function BindToggle(tab, key, name, description, onChange)
    if onChange then
        FeatureApply[key] = onChange
    end
    local api = tab:CreateToggle(name, description, State[key], function(enabled)
        SetFeature(key, enabled)
    end)
    ToggleAPIs[key] = api
    return api
end

local function BindToggleInput(tab, key, name, description, valueKey, minimum, maximum)
    local api = tab:CreateToggleWithInput(
        name,
        description,
        State[key],
        Values[valueKey],
        function(enabled)
            SetFeature(key, enabled)
        end,
        function(value)
            Values[valueKey] = Clamp(value, minimum, maximum)
            SaveScriptConfig()
        end,
        { Min = minimum, Max = maximum, Integer = true }
    )
    ToggleAPIs[key] = api
    return api
end

local function BindToggleColor(tab, key, name, description, colorKey)
    local api = tab:CreateToggleWithColor(
        name,
        description,
        State[key],
        Colors[colorKey],
        function(enabled)
            SetFeature(key, enabled)
        end,
        function(color)
            Colors[colorKey] = color
            SaveScriptConfig()
        end
    )
    ToggleAPIs[key] = api
    return api
end

local function BindValueInput(tab, name, description, valueKey, minimum, maximum)
    local api = tab:CreateInputCard(
        name,
        description,
        Values[valueKey],
        function(value)
            Values[valueKey] = Clamp(value, minimum, maximum)
            SaveScriptConfig()
        end,
        { Min = minimum, Max = maximum, Integer = true }
    )
    return api
end

-- // AUTOFARM
local farmTab = ApexWindow:CreateTab("FARM", "AUTOFARM // TARGETING")
farmTab:CreateSectionLabel("COMBAT")
BindToggle(
    farmTab,
    "AutoBug",
    "AUTO BUG ATTACK",
    "Prioritises bosses, then zone progression and SizeMult. Teleports into reach and bites on the server attack cooldown.",
    function()
        if not State.AutoBug then
            BugTarget.Model = nil
            BugTarget.Since = 0
        end
    end
)
BindToggle(
    farmTab,
    "AutoBreak",
    "AUTO BREAKABLES",
    "Finds the most valuable breakable (coins, then XP) and destroys it with server bites. Skips empty folders automatically.",
    function()
        if not State.AutoBreak then
            BreakTarget.Model = nil
            BreakTarget.Since = 0
        end
    end
)
BindValueInput(
    farmTab,
    "ATTACK STAND-OFF",
    "Distance kept from a bug target. Keep it under the current Reach stat (live Reach is shown in INFO). Hard cap 200.",
    "AttackRange",
    2,
    200
)
BindValueInput(
    farmTab,
    "TARGET TIMEOUT",
    "Abandons an unreachable or bugged target after this many seconds. Hard cap 120.",
    "TargetTimeout",
    5,
    120
)

farmTab:CreateSectionLabel("ORB COLLECTION")
BindToggle(
    farmTab,
    "AutoXPOrb",
    "AUTO XP ORBS",
    "Teleports to the highest-value XP orb and collects it. Pauses while a bug or breakable target is active.",
    nil
)
BindToggle(
    farmTab,
    "AutoVoidOrb",
    "AUTO VOID ORBS",
    "Collects Void Orbs whenever the void event drops them. Takes priority over normal XP orbs.",
    nil
)
BindToggle(
    farmTab,
    "AutoRainbowOrb",
    "AUTO RAINBOW ORBS",
    "Collects Rainbow Orbs. Runs before normal XP orbs when both are enabled.",
    nil
)
farmTab:CreateInfoCard("PRIORITY", "BUGS / BREAKS > VOID > RAINBOW > XP")

-- // EVENTS
local eventTab = ApexWindow:CreateTab("EVENTS", "EVENT // REWARDS")
eventTab:CreateSectionLabel("VOID EVENT")
BindToggle(
    eventTab,
    "AutoSpin",
    "AUTO VOID SPINNER",
    "Invokes the VoidAction spinner once per second while enabled. Works only where the void spinner is available.",
    nil
)
eventTab:CreateButton(
    "SPIN VOID ONCE",
    "Fire one manual VoidAction Spin call.",
    function()
        if Remotes then
            local voidAction = Remotes:FindFirstChild("VoidAction")
            if voidAction then
                local ok = pcall(function()
                    voidAction:InvokeServer("Spin", nil)
                end)
                Notify(ok and "VOID SPIN // sent" or "VOID SPIN // rejected", 2)
            end
        end
    end
)
eventTab:CreateSectionLabel("REWARDS")
BindToggle(
    eventTab,
    "AutoPlaytime",
    "AUTO CLAIM PLAYTIME",
    "Checks the playtime reward every few seconds and claims it when the timer is ready.",
    nil
)
eventTab:CreateButton(
    "CHECK REWARD STATUS",
    "Read the daily and playtime reward status without claiming anything.",
    function()
        if not Remotes then
            return
        end
        local rewards = Remotes:FindFirstChild("Rewards")
        if not rewards then
            return
        end
        local status = pcall(function()
            local result = rewards:InvokeServer("Status")
            if type(result) == "table" then
                Notify("DAILY // day " .. tostring(result.Day or "?")
                    .. " | claim " .. tostring(result.CanClaim == true), 4)
            end
            rewards:InvokeServer("Playtime")
        end)
        if not status then
            Notify("REWARD STATUS // unavailable", 2)
        end
    end
)
eventTab:CreateInfoCard("PLAYTIME", "CLAIMED AUTOMATICALLY WHEN READY")

-- // STATS
local statsTab = ApexWindow:CreateTab("STATS", "PLAYER // MOVEMENT")
statsTab:CreateSectionLabel("MOVEMENT")
BindToggleInput(
    statsTab,
    "Speed",
    "SPEED CHANGER",
    "Overrides the player WalkSpeed attribute read by the game. Values over 200 snap back to 200.",
    "Speed",
    0,
    200
)
BindToggleInput(
    statsTab,
    "Jump",
    "JUMP POWER",
    "Overrides the JumpPower attribute. The input allows up to 1000 and snaps larger values back to 1000.",
    "JumpPower",
    0,
    1000
)
BindToggleInput(
    statsTab,
    "Fly",
    "CFRAME FLIGHT",
    "Custom client flight. Hold Space to rise, LeftControl or C to sink, and WASD to move. Fly Speed is capped at 200.",
    "FlySpeed",
    0,
    200
)
-- Movement toggles also drive the attribute spoofs. Without these, the game
-- would keep reading its server values even though the local Humanoid changed.
FeatureApply.Speed = function(enabled)
    Spoof.WalkSpeed = enabled
    if not enabled then
        local _, humanoid = GetCharacter()
        local actual = LocalPlayer:GetAttribute("WalkSpeed")
        if humanoid and IsFiniteNumber(actual) then
            humanoid.WalkSpeed = actual
        end
    end
end
FeatureApply.Jump = function(enabled)
    Spoof.JumpPower = enabled
    if not enabled then
        local _, humanoid = GetCharacter()
        local actual = LocalPlayer:GetAttribute("JumpPower")
        if humanoid and IsFiniteNumber(actual) then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = actual
        end
    end
end
FeatureApply.Fly = function(enabled)
    Spoof.CanFly = enabled
    if not enabled then
        ClearFlyState()
        local _, _, root = GetCharacter()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end
end
BindToggle(
    statsTab,
    "InfiniteJump",
    "INFINITE JUMP",
    "Allows another jump in mid-air. Disabled automatically while CFrame Flight is on.",
    nil
)
BindToggle(
    statsTab,
    "InfiniteStamina",
    "INFINITE STAMINA",
    "Spoofs Stamina, Exhausted, FreeSprint and AlwaysSprint reads so the client never reports exhaustion.",
    function(enabled)
        Spoof.Stamina = enabled
    end
)

statsTab:CreateSectionLabel("PROTECTION")
BindToggle(
    statsTab,
    "VoidGuard",
    "VOID GUARD",
    "If there is no solid ground below you or you fall below the map, recover to the active bug target without resetting its timer, otherwise teleport to a random surface. On by default and saved.",
    function(enabled)
        Notify(enabled and "VOID GUARD // armed" or "VOID GUARD // off", 2)
    end
)

statsTab:CreateSectionLabel("ABILITIES")
BindToggle(
    statsTab,
    "AutoAbility1",
    "AUTO ABILITY 1",
    "Casts Ability1 as soon as its server cooldown is ready. Works for every species, including Dash and attacks.",
    nil
)
BindToggle(
    statsTab,
    "AutoAbility2",
    "AUTO ABILITY 2",
    "Casts Ability2 as soon as its server cooldown is ready. Independent of the stealth automation.",
    nil
)
statsTab:CreateButton(
    "CAST ABILITY 1",
    "Fires UseAbility for slot 1, whatever ability is equipped there.",
    function()
        local name = LocalPlayer:GetAttribute("Ability1")
        if CastAbility(1) then
            Notify("CAST // " .. tostring(name), 2)
        end
    end
)
statsTab:CreateButton(
    "CAST ABILITY 2",
    "Fires UseAbility for slot 2, whatever ability is equipped there.",
    function()
        local name = LocalPlayer:GetAttribute("Ability2")
        if CastAbility(2) then
            Notify("CAST // " .. tostring(name), 2)
        end
    end
)

statsTab:CreateSectionLabel("STEALTH // INVISIBILITY")
BindToggle(
    statsTab,
    "Ghost",
    "GHOST MODE [LOCAL]",
    "Hides your character and name tag on your own client. Other players still see you - pair it with a stealth ability for real cover.",
    function(enabled)
        if not enabled then
            RestoreGhost()
        end
    end
)
BindToggle(
    statsTab,
    "AutoStealth",
    "AUTO STEALTH ABILITY",
    "Casts your equipped stealth ability whenever it is ready. Works with Camouflage, Sand Veil, Phase and Burrow.",
    nil
)
statsTab:CreateButton(
    "CAST STEALTH NOW",
    "Casts whichever equipped slot holds a stealth ability.",
    function()
        local slot, name = GetStealthSlot()
        if slot then
            CastAbility(slot)
            Notify("STEALTH // " .. tostring(name), 2)
        else
            Notify("STEALTH // not equipped (Katydid, Luna Moth, Funnel-Web, Void Mosquito)", 5)
        end
    end
)
statsTab:CreateReadMeCard(
    "STEALTH SPECIES",
    "Camouflage: Katydid | Phase: Luna Moth, Void Mosquito | Burrow: Funnel-Web. Use the game's evolve panel to switch species, then enable AUTO STEALTH ABILITY.",
    100
)

-- // ESP
local espTab = ApexWindow:CreateTab("VISUALS", "ESP // TRACERS")
espTab:CreateSectionLabel("PLAYERS")
BindToggleColor(
    espTab,
    "ESPPlayers",
    "PLAYER ESP",
    "Draws player name, level and health. Use the palette button to change the ESP colour.",
    "PlayerESP"
)
BindToggleColor(
    espTab,
    "ESPPlayerTracers",
    "PLAYER TRACERS",
    "Draws snap lines from the bottom of the screen. Has its own colour picker.",
    "PlayerTracer"
)

espTab:CreateSectionLabel("WORLD")
BindToggleColor(
    espTab,
    "ESPBugs",
    "BUG ESP",
    "Draws bug name, health and zone, with a BOSS tag for bosses. Colour is adjustable.",
    "BugESP"
)
BindToggleColor(
    espTab,
    "ESPBugTracers",
    "BUG TRACERS",
    "Draws snap lines to bugs with an independent colour picker.",
    "BugTracer"
)
BindToggleColor(
    espTab,
    "ESPOrbs",
    "ORB ESP",
    "Draws XP and Rainbow Orbs within the ESP distance. Colour is adjustable.",
    "OrbESP"
)
BindToggleColor(
    espTab,
    "ESPVoidOrbs",
    "VOID ORB ESP",
    "Draws Void Orbs and their credit value with a separate colour.",
    "VoidOrbESP"
)
BindToggleColor(
    espTab,
    "ESPBreakables",
    "BREAKABLE ESP",
    "Draws breakables with HP and coin value. Colour is adjustable.",
    "BreakableESP"
)
BindValueInput(
    espTab,
    "ESP DISTANCE",
    "Maximum distance for all ESP elements. Hard cap 10000 studs.",
    "ESPDistance",
    100,
    10000
)

-- // INFO / TOOLS
local infoTab = ApexWindow:CreateTab("INFO", "SESSION // TOOLS")
infoTab:CreateSectionLabel("LIVE SESSION")
local InfoCards = {
    Player = infoTab:CreateInfoCard("PLAYER", LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")"),
    Stage = infoTab:CreateInfoCard("STAGE", "-"),
    Level = infoTab:CreateInfoCard("LEVEL", "-"),
    Health = infoTab:CreateInfoCard("HEALTH", "-"),
    Coins = infoTab:CreateInfoCard("COINS", "-"),
    Stamina = infoTab:CreateInfoCard("STAMINA", "-"),
    Reach = infoTab:CreateInfoCard("REACH", "-"),
    Ability1 = infoTab:CreateInfoCard("ABILITY 1", "-"),
    Ability2 = infoTab:CreateInfoCard("ABILITY 2", "-"),
    Target = infoTab:CreateInfoCard("TARGET", "OFF"),
    Guard = infoTab:CreateInfoCard("VOID GUARD", "ARMED"),
    Kills = infoTab:CreateInfoCard("KILLS / BREAKS", "0 / 0"),
    Recoveries = infoTab:CreateInfoCard("VOID RECOVERIES", "0"),
    Version = infoTab:CreateInfoCard("SCRIPT_VERSION", SCRIPT_VERSION),
    Engine = infoTab:CreateInfoCard("UI_ENGINE", (ApexLibrary.Version or "APEX_SYS") .. " | REV " .. tostring(ApexLibrary.LayoutRevision or "?")),
}

infoTab:CreateSectionLabel("TOOLS")
infoTab:CreateButton(
    "TELEPORT TO RANDOM SURFACE",
    "Immediately moves to a random solid surface inside the map. Useful as a manual void escape.",
    function()
        local surface = RandomSurfaceCFrame()
        if surface then
            local _, _, root = GetCharacter()
            if root then
                root.CFrame = surface
                Notify("SURFACE // teleported", 2)
            end
        else
            Notify("SURFACE // no ground found", 2)
        end
    end
)
infoTab:CreateButton(
    "TELEPORT TO NEAREST BUG",
    "Moves to the closest living bug without starting the auto-farm loop.",
    function()
        TeleportToNearestBug()
    end
)
infoTab:CreateButton(
    "RESTORE CHARACTER",
    "Clears ghost mode, speed/jump overrides and flight state.",
    function()
        SetFeature("Speed", false)
        SetFeature("Jump", false)
        SetFeature("Fly", false)
        SetFeature("Ghost", false)
        SetFeature("InfiniteStamina", false)
        RestoreMovement()
        RestoreGhost()
        Notify("CHARACTER // restored", 2)
    end
)
infoTab:CreateReadMeCard(
    "CONTROLS",
    "RightControl opens/closes this menu and always lands on CONFIG. The library CONFIG tab owns anti-AFK and the shared UI profile. Script features save to BugEvolution_Config.json. Void Guard is on by default and returns to the active bug target without resetting its timer.",
    104
)
infoTab:CreateKillButton("UNLOAD BUG EVOLUTION", nil, 150)

-- // Public control surface. Useful for debugging and for advanced users who
-- // want to drive the saved features from their own script.
if getgenv then
    pcall(function()
        getgenv().BugEvolution = {
            State = State,
            Values = Values,
            Colors = Colors,
            Spoof = Spoof,
            BugTarget = BugTarget,
            BreakTarget = BreakTarget,
            ESPStores = ESPStores,
            Debug = DebugCounters,
            SetFeature = SetFeature,
            SaveConfig = SaveScriptConfig,
            RecoverFromVoid = RecoverFromVoid,
            CastAbility = CastAbility,
            GetCharacter = GetCharacter,
            Notify = Notify,
        }
    end)
end

-- // Info card refresh
task.spawn(function()
    while SessionActive() do
        task.wait(0.5)
        local character, humanoid, root = GetCharacter()
        local stage = LocalPlayer:GetAttribute("StageName") or LocalPlayer:GetAttribute("StageId") or "-"
        local level = LocalPlayer:GetAttribute("Level") or "-"
        local coins = LocalPlayer:GetAttribute("Coins") or "-"
        local stamina = LocalPlayer:GetAttribute("Stamina")
        local maxStamina = LocalPlayer:GetAttribute("MaxStamina")
        local reach = LocalPlayer:GetAttribute("Reach") or "-"

        InfoCards.Stage:SetValue(tostring(stage))
        InfoCards.Level:SetValue(tostring(level))
        if humanoid then
            InfoCards.Health:SetValue(string.format("%d / %d", math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth + 0.5)))
        else
            InfoCards.Health:SetValue("DEAD / SPAWNING")
        end
        InfoCards.Coins:SetValue(tostring(coins))
        if stamina and maxStamina then
            InfoCards.Stamina:SetValue(string.format("%d / %d", math.floor(stamina + 0.5), math.floor(maxStamina + 0.5)))
        else
            InfoCards.Stamina:SetValue("-")
        end
        InfoCards.Reach:SetValue(tostring(reach))
        local now = Workspace:GetServerTimeNow()
        for slot = 1, 2 do
            local ability = LocalPlayer:GetAttribute("Ability" .. tostring(slot)) or "-"
            local readyAt = tonumber(LocalPlayer:GetAttribute("Ability" .. tostring(slot) .. "Ready")) or 0
            local remaining = math.max(0, readyAt - now)
            local status = remaining <= 0 and "READY" or string.format("%.1fs", remaining)
            InfoCards["Ability" .. tostring(slot)]:SetValue(tostring(ability) .. " | " .. status)
        end
        if BugTarget.Model and IsBugAlive(BugTarget.Model, Workspace:FindFirstChild("Bugs")) then
            InfoCards.Target:SetValue(string.format("%s | %.0fs", BugTarget.Model.Name, math.max(0, Values.TargetTimeout - (os.clock() - BugTarget.Since))))
        elseif BreakTarget.Model and IsBreakableAlive(BreakTarget.Model, Workspace:FindFirstChild("Breakables")) then
            InfoCards.Target:SetValue("BREAK // " .. BreakTarget.Model.Name)
        elseif State.AutoBug then
            InfoCards.Target:SetValue("SEARCHING")
        else
            InfoCards.Target:SetValue("OFF")
        end
        InfoCards.Guard:SetValue(State.VoidGuard and "ARMED" or "OFF")
        InfoCards.Kills:SetValue(tostring(SessionKills) .. " / " .. tostring(SessionBreaks))
        InfoCards.Recoveries:SetValue(tostring(VoidRecoveries))
    end
end)

-- // Initial feature application. Toggles created above already show the saved
-- // state; this starts the saved effects and loops.
for key, enabled in pairs(State) do
    local apply = FeatureApply[key]
    if apply and enabled then
        pcall(apply, true)
    end
end

-- // Cleanup / unload
local function Cleanup()
    if not ScriptRunning then
        return
    end
    ScriptRunning = false
    if getgenv then
        pcall(function()
            if getgenv().BugEvolutionSession == SESSION then
                getgenv().BugEvolutionSession = nil
            end
            getgenv().BugEvolution = nil
        end)
    end
    Spoof.WalkSpeed = false
    Spoof.JumpPower = false
    Spoof.Stamina = false
    Spoof.CanFly = false
    RestoreNamecallHook()
    ClearAllESP()
    RestoreMovement()
    RestoreGhost()
    if Remotes then
        local setFlying = Remotes:FindFirstChild("SetFlying")
        if setFlying then
            pcall(function()
                setFlying:FireServer(false)
            end)
        end
    end
end

local function UnloadScript()
    Cleanup()
    if ApexWindow then
        pcall(function()
            ApexWindow:Unload()
        end)
    end
end

ApexWindow:RegisterUnloadCallback(Cleanup)
if getgenv then
    pcall(function()
        getgenv().BugEvolutionUnload = UnloadScript
    end)
end

Notify("BUG EVOLUTION // loaded", 3)
