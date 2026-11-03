--[================================================================[
    CREATURES OF SONARIA // APEX UI MIGRATION
    ---------------------------------------------------------------
    Original gameplay logic: Drk_Duck
    UI framework: APEX_SYS (ApexLibraryPlus.lua)
    ---------------------------------------------------------------
    The original 300px ScreenGui is replaced by the APEX terminal
    interface. Every original feature is preserved:

      * [J] Instant Menu downward CFrame drop
      * Outline ESP for workspace.Characters
      * Minimap ESP (force every other player to Everyone)
      * Always Wall Climber
      * Infinite stamina / oxygen / moisture
      * Hide Scent
      * Always Aggro / Always Cower
      * Walk-Swim / Sprint / Fly speed attributes
      * CFrame Exploit Fly
      * Staff detector
      * Out-of-bounds damage remote removal
      * Live animation swapper with category filters and random/cycle preview
      * Client-side ragdoll / unragdoll with optional keybinds
      * Mandatory menu keybind with no clear option

    Run order:
        Run this script. It downloads ApexLibraryPlus.lua from GitHub
        and loads it automatically. Local copies are only a fallback.

    Library URL:
        https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/main/ApexLibraryPlus.lua?v=12
]================================================================]--

-- // Apex Library Loader
-- The version query bypasses executor HTTP caches that still hold an old
-- library. MIN_LAYOUT_REVISION rejects stale copies that slip through.
local LIBRARY_URL = "https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/main/ApexLibraryPlus.lua?v=12"
local MIN_LAYOUT_REVISION = 12

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
    error("[Cos Apex] Could not load ApexLibraryPlus.lua.\n"
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
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerName = LocalPlayer.Name

local SCRIPT_VERSION = "COS // APEX 1.2"
local AUTHOR = "Drk_Duck"
local ConfigFile = "Cos_Apex_Config.json"
local CONFIG_VERSION = 3

-- // Session guard. Re-running the script makes the old loops and callbacks
-- stop applying effects without touching the newly-created APEX window.
local SESSION = {}
local ScriptRunning = true
local sessionRegistered = false
if getgenv then
    sessionRegistered = pcall(function()
        getgenv().CosApexSession = SESSION
    end)
end

local function SessionActive()
    if not ScriptRunning then
        return false
    end
    if sessionRegistered and getgenv then
        local ok, active = pcall(function()
            return getgenv().CosApexSession == SESSION
        end)
        if ok then
            return active
        end
    end
    return true
end

-- // Feature state (defaults match the original script)
local Toggles = {
    InstantMenu = false,
    WalkSpeed = false,
    SprintSpeed = false,
    FlySpeed = false,
    ExploitFly = false,
    InfiniteStamina = false,
    InfiniteOxygen = false,
    InfiniteMoisture = false,
    AlwaysClimber = false,
    HideScent = false,
    AlwaysAggro = false,
    AlwaysCower = false,
    OutlineESP = false,
    ShowHealthBar = true,
    MinimapESP = false,
    AnimationSearchAll = false,
    AnimationLoop = true
}

local Speeds = {
    Walk = 16,
    Sprint = 16,
    Fly = 16,
    ExploitFly = 75,
    ScentPulse = 5,
    AilmentPulse = 8
}

local EXPLOIT_FLY_MAX = 100000

-- // The instant-menu drop is intentionally fixed. These values are no longer
-- exposed as controls or loaded from the config file.
local DROP_DURATION = 1
local DROP_SPEED = 1111111

-- // Action keybinds owned by this script. false means "no key assigned".
local Keybinds = {
    Ragdoll = "R",
    Unragdoll = "U"
}

local ESPSettings = {
    FillTransparency = 1,
    MaxDistance = 1500
}

local ESPColors = {
    Outline = Color3.fromRGB(255, 60, 60),
    Aggressive = Color3.fromRGB(255, 165, 0),
    Health = Color3.fromRGB(60, 220, 60),
    LowHealth = Color3.fromRGB(220, 60, 60)
}
local DEFAULT_TRAIT_COLOR = Color3.fromRGB(255, 220, 100)

local StatusCards = {}
local MyWindow = nil
local SafeSetStatus

-- // Config helpers
local function ClampNumber(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number then
        number = fallback
    end
    return math.clamp(number, minimum, maximum)
end

local function IsValidKeyName(value)
    if type(value) ~= "string" or value == "" then
        return false
    end
    local ok, key = pcall(function()
        return Enum.KeyCode[value]
    end)
    return ok and key ~= nil
end

local function KeybindToEnum(value)
    if not IsValidKeyName(value) then
        return nil
    end
    local ok, key = pcall(function()
        return Enum.KeyCode[value]
    end)
    return ok and key or nil
end

local function KeyToName(key)
    if key == nil then
        return false
    end
    local ok, name = pcall(function()
        return key.Name
    end)
    if ok and name then
        return name
    end
    return false
end

local function ColorToTable(color)
    return {
        R = math.floor(color.R * 255 + 0.5),
        G = math.floor(color.G * 255 + 0.5),
        B = math.floor(color.B * 255 + 0.5)
    }
end

local function TableToColor(data, fallback)
    if type(data) ~= "table" then
        return fallback
    end
    return Color3.fromRGB(
        math.clamp(tonumber(data.R) or math.floor(fallback.R * 255 + 0.5), 0, 255),
        math.clamp(tonumber(data.G) or math.floor(fallback.G * 255 + 0.5), 0, 255),
        math.clamp(tonumber(data.B) or math.floor(fallback.B * 255 + 0.5), 0, 255)
    )
end

local function DecodeConfigFile(path)
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

local function LoadScriptConfig()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        return
    end

    local ok, exists = pcall(isfile, ConfigFile)
    if not ok or not exists then
        return
    end

    local data = DecodeConfigFile(ConfigFile)
    if type(data) ~= "table" then
        return
    end

    if type(data.Toggles) == "table" then
        for key, value in pairs(data.Toggles) do
            if Toggles[key] ~= nil and type(value) == "boolean" then
                Toggles[key] = value
            end
        end
    end

    if type(data.Speeds) == "table" then
        local speeds = data.Speeds
        Speeds.Walk = ClampNumber(speeds.Walk, 1, 5000, Speeds.Walk)
        Speeds.Sprint = ClampNumber(speeds.Sprint, 1, 5000, Speeds.Sprint)
        Speeds.Fly = ClampNumber(speeds.Fly, 1, 5000, Speeds.Fly)
        Speeds.ExploitFly = ClampNumber(speeds.ExploitFly, 1, EXPLOIT_FLY_MAX, Speeds.ExploitFly)
        Speeds.ScentPulse = ClampNumber(speeds.ScentPulse, 1, 60, Speeds.ScentPulse)
        Speeds.AilmentPulse = ClampNumber(speeds.AilmentPulse, 1, 60, Speeds.AilmentPulse)
    end

    if type(data.ESP) == "table" then
        ESPSettings.FillTransparency = ClampNumber(data.ESP.FillTransparency, 0, 1, ESPSettings.FillTransparency)
        ESPSettings.MaxDistance = ClampNumber(data.ESP.MaxDistance, 50, 10000, ESPSettings.MaxDistance)
    end

    if type(data.Colors) == "table" then
        ESPColors.Outline = TableToColor(data.Colors.Outline, ESPColors.Outline)
        ESPColors.Aggressive = TableToColor(data.Colors.Aggressive, ESPColors.Aggressive)
        ESPColors.Health = TableToColor(data.Colors.Health, ESPColors.Health)
        ESPColors.LowHealth = TableToColor(data.Colors.LowHealth, ESPColors.LowHealth)
    end

    if type(data.Keybinds) == "table" then
        local ragdollKey = data.Keybinds.Ragdoll
        if ragdollKey == false then
            Keybinds.Ragdoll = false
        elseif IsValidKeyName(ragdollKey) then
            Keybinds.Ragdoll = ragdollKey
        end
        local unragdollKey = data.Keybinds.Unragdoll
        if unragdollKey == false then
            Keybinds.Unragdoll = false
        elseif IsValidKeyName(unragdollKey) then
            Keybinds.Unragdoll = unragdollKey
        end
    end
end

local function SaveScriptConfig()
    if type(writefile) ~= "function" then
        return
    end
    pcall(function()
        local data = {
            ConfigVersion = CONFIG_VERSION,
            ScriptVersion = SCRIPT_VERSION,
            Toggles = {},
            Speeds = {
                Walk = Speeds.Walk,
                Sprint = Speeds.Sprint,
                Fly = Speeds.Fly,
                ExploitFly = Speeds.ExploitFly,
                ScentPulse = Speeds.ScentPulse,
                AilmentPulse = Speeds.AilmentPulse
            },
            ESP = {
                FillTransparency = ESPSettings.FillTransparency,
                MaxDistance = ESPSettings.MaxDistance
            },
            Keybinds = {
                Ragdoll = Keybinds.Ragdoll,
                Unragdoll = Keybinds.Unragdoll
            },
            Colors = {}
        }
        for key, value in pairs(Toggles) do
            if type(value) == "boolean" then
                data.Toggles[key] = value
            end
        end
        for key, color in pairs(ESPColors) do
            data.Colors[key] = ColorToTable(color)
        end
        writefile(ConfigFile, HttpService:JSONEncode(data))
    end)
end

LoadScriptConfig()

-- // Connection bookkeeping
local Connections = {}
local CleanupSession -- forward declaration

local function TrackConnection(connection)
    if connection then
        Connections[#Connections + 1] = connection
    end
    return connection
end

local function DisconnectTrackedConnections()
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    Connections = {}
end

-- // Remote helpers
local function GetRemotesFolder()
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    if folder then
        return folder
    end
    return nil
end

local function GetRemote(remoteName)
    local folder = GetRemotesFolder()
    return folder and folder:FindFirstChild(remoteName) or nil
end

local function FireRemote(remoteName, ...)
    local remote = GetRemote(remoteName)
    if not remote then
        return false
    end
    pcall(remote.FireServer, remote, ...)
    return true
end

local function FireHideScent(value)
    return FireRemote("HideScent", value)
end

local function FireAilment(ailmentName)
    return FireRemote("StateAilment", ailmentName)
end

-- // Out-of-bounds damage remote. The original script destroyed this remote
-- unconditionally on load, so this build does the same and reports the state.
local OOBRemoved = false

local function TryRemoveOutOfBoundsDamage()
    if OOBRemoved then
        return true
    end
    local remotes = GetRemotesFolder()
    local remote = remotes and remotes:FindFirstChild("OutOfBoundsSelfDamage")
    if not remote then
        return false
    end
    pcall(function()
        remote:Destroy()
    end)
    OOBRemoved = remote.Parent == nil
    return OOBRemoved
end

-- // Staff detector. Always on in the original; it stays always on here.
local PERMISSION_PATHS = {
    { "Settings", "Permissions", "Admin" },
    { "Settings", "Permissions", "CommunityManager" },
    { "Settings", "Permissions", "Developer" },
    { "Settings", "Permissions", "Staff" },
    { "Settings", "Permissions", "Contributor" },
    { "Settings", "Permissions", "Translator" },
    { "Settings", "Permissions", "Tester" }
}
local StaffKickIssued = false

local function CheckPlayerForStaff(player)
    if StaffKickIssued or player == LocalPlayer then
        return false
    end

    for _, path in ipairs(PERMISSION_PATHS) do
        local current = player
        local found = true
        for _, partName in ipairs(path) do
            current = current:FindFirstChild(partName)
            if not current then
                found = false
                break
            end
        end

        if found and current:IsA("BoolValue") and current.Value == true then
            StaffKickIssued = true
            local message = "Staff/Admin presence detected: " .. player.Name
            warn("[Cos Apex] " .. message)
            pcall(function()
                LocalPlayer:Kick(message)
            end)
            return true
        end
    end
    return false
end

-- // Minimap ESP. The original forced "Everyone" and reset to "Default".
-- This build remembers each player's original value and restores it cleanly.
local MinimapOriginal = {}
local MinimapVisibilityCache = {}

local function GetMinimapVisibility(player)
    local cached = MinimapVisibilityCache[player]
    if cached and cached.Parent then
        return cached
    end
    local settings = player:FindFirstChild("Settings")
    local visibility = settings and settings:FindFirstChild("MinimapVisibility") or nil
    MinimapVisibilityCache[player] = visibility
    return visibility
end

local function ApplyMinimapToPlayer(player)
    if player == LocalPlayer then
        return
    end
    local visibility = GetMinimapVisibility(player)
    if not visibility then
        return
    end
    if MinimapOriginal[player] == nil then
        MinimapOriginal[player] = visibility.Value
    end
    if visibility.Value ~= "Everyone" then
        pcall(function()
            visibility.Value = "Everyone"
        end)
    end
end

local function ApplyMinimapNow()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            ApplyMinimapToPlayer(player)
        end
    end
end

local function RestoreMinimap()
    for player, original in pairs(MinimapOriginal) do
        local visibility = GetMinimapVisibility(player)
        if visibility then
            pcall(function()
                visibility.Value = original
            end)
        end
    end
    MinimapOriginal = {}
    MinimapVisibilityCache = {}
end

-- // Local character / attribute helpers
local function GetLocalCharacter()
    return LocalPlayer.Character
end

local function GetLocalCharacterData()
    local character = GetLocalCharacter()
    local data = character and character:FindFirstChild("Data")
    if data then
        return data
    end

    local charactersFolder = Workspace:FindFirstChild("Characters")
    local playerFolder = charactersFolder and charactersFolder:FindFirstChild(PlayerName)
    return playerFolder and playerFolder:FindFirstChild("Data") or nil
end

local function GetClimberData()
    local charactersFolder = Workspace:FindFirstChild("Characters")
    local playerFolder = charactersFolder and charactersFolder:FindFirstChild(PlayerName)
    return playerFolder and playerFolder:FindFirstChild("Data") or nil
end

-- One character/data lookup per heartbeat. Falls back to the same folder COS
-- uses for climber writes if the character model has no direct Data child.
local function GetLocalCharacterAndData()
    local character = GetLocalCharacter()
    local data = character and character:FindFirstChild("Data")
    if data then
        return character, data
    end
    return character, GetClimberData()
end

-- The game may give a creature wall climb on spawn. Baselines keep that
-- original value so turning the toggle off does not remove an innate ability.
local ClimberBaselines = setmetatable({}, { __mode = "k" })

local function ReadClimberAttribute(data)
    local ok, value = pcall(function()
        return data:GetAttribute("Climber")
    end)
    return ok and value == true or false
end

local function CaptureClimberBaseline(data)
    if not data then
        return false
    end
    local baseline = ClimberBaselines[data]
    if baseline == nil then
        baseline = ReadClimberAttribute(data)
        ClimberBaselines[data] = baseline
    end
    return baseline
end

-- While the toggle is off, follow the game's own value so later changes are
-- treated as the new baseline.
local function RefreshClimberBaseline(data)
    if data then
        ClimberBaselines[data] = ReadClimberAttribute(data)
    end
end

local function WriteClimberState(data, enabled)
    if not data then
        return
    end
    local ok, current = pcall(function()
        return data:GetAttribute("Climber")
    end)
    if not ok or current ~= enabled then
        data:SetAttribute("Climber", enabled)
    end
end

local function SetClimberState(enabled)
    local data = GetClimberData()
    if not data then
        return
    end
    local baseline = CaptureClimberBaseline(data)
    WriteClimberState(data, enabled == true or baseline)
end

local function SetAttributeOnChange(data, name, value)
    local ok, current = pcall(function()
        return data:GetAttribute(name)
    end)
    if not ok or current ~= value then
        data:SetAttribute(name, value)
    end
end

-- Writes the speed the current creature had before the toggle was enabled.
-- Baselines are captured per character Data instance so a new creature's own
-- values are used instead of a shared hardcoded default.
local SpeedBaselines = setmetatable({}, { __mode = "k" })

local function CaptureSpeedAttribute(data, attributeName)
    if not data then
        return
    end
    local baseline = SpeedBaselines[data]
    if not baseline then
        baseline = { Captured = {} }
        SpeedBaselines[data] = baseline
    end
    if baseline.Captured[attributeName] then
        return baseline[attributeName]
    end
    local ok, current = pcall(function()
        return data:GetAttribute(attributeName)
    end)
    baseline.Captured[attributeName] = true
    baseline[attributeName] = ok and current or nil
    return baseline[attributeName]
end

local function RestoreSpeedAttribute(attributeName)
    local data = GetLocalCharacterData()
    if not data then
        return
    end
    local baseline = SpeedBaselines[data]
    if not baseline or not baseline.Captured[attributeName] then
        return
    end
    local value = baseline[attributeName]
    if value ~= nil then
        SetAttributeOnChange(data, attributeName, value)
    end
end

local function EnforceAttributes(data)
    data = data or GetLocalCharacterData()
    if not data then
        return
    end

    if Toggles.InfiniteStamina then
        SetAttributeOnChange(data, "st", 99999999999999)
        SetAttributeOnChange(data, "sr", 99999999999999)
    end
    if Toggles.InfiniteOxygen then
        SetAttributeOnChange(data, "Oxygen", 999999999999)
    end
    if Toggles.InfiniteMoisture then
        SetAttributeOnChange(data, "Moisture", 999999999999)
    end
    if Toggles.WalkSpeed then
        CaptureSpeedAttribute(data, "s")
        SetAttributeOnChange(data, "s", Speeds.Walk)
    end
    if Toggles.SprintSpeed then
        CaptureSpeedAttribute(data, "ss")
        SetAttributeOnChange(data, "ss", Speeds.Sprint)
    end
    if Toggles.FlySpeed then
        CaptureSpeedAttribute(data, "fs")
        SetAttributeOnChange(data, "fs", Speeds.Fly)
    end
end

local function EnforceClimber(data)
    data = data or GetClimberData()
    if not data then
        return
    end
    if Toggles.AlwaysClimber then
        CaptureClimberBaseline(data)
        WriteClimberState(data, true)
    else
        -- Never force the attribute off here: creatures that spawn with wall
        -- climb must keep it. Just follow the game's own value as baseline.
        RefreshClimberBaseline(data)
    end
end

-- // ESP
local espData = {}

local function ReadValue(instance, name)
    local ok, attribute = pcall(function()
        return instance:GetAttribute(name)
    end)
    if ok and attribute ~= nil then
        return attribute
    end
    local child = instance:FindFirstChild(name)
    if child and child:IsA("ValueBase") then
        return child.Value
    end
    return nil
end

local function GetAilmentsInfo(ailmentsFolder)
    local traitLetters = {}
    local isAggressive = false

    if ailmentsFolder then
        local ok, attributes = pcall(function()
            return ailmentsFolder:GetAttributes()
        end)
        if ok and type(attributes) == "table" then
            for attributeName, attributeValue in pairs(attributes) do
                local lowerName = string.lower(attributeName)
                if string.find(lowerName, "trait") then
                    local base = attributeName:gsub("[Tt][Rr][Aa][Ii][Tt]$", "")
                    if base == "" then
                        base = attributeName
                    end
                    table.insert(traitLetters, string.upper(string.sub(base, 1, 1)))
                elseif string.find(lowerName, "aggro") or string.find(lowerName, "aggress") then
                    isAggressive = attributeValue ~= false
                end
            end
        end
    end

    return table.concat(traitLetters, "/"), isAggressive
end

local function CreateESPEntry(model)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Outline"
    highlight.FillTransparency = ESPSettings.FillTransparency
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = ESPColors.Outline
    highlight.OutlineColor = ESPColors.Outline
    highlight.Adornee = model
    highlight.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Info"
    billboard.Adornee = model
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(220, 90)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.Parent = model

    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = UDim2.fromScale(1, 1)
    container.Parent = billboard

    local playerLabel = Instance.new("TextLabel")
    playerLabel.Name = "PlayerLabel"
    playerLabel.BackgroundTransparency = 1
    playerLabel.Font = Enum.Font.GothamBold
    playerLabel.TextSize = 15
    playerLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
    playerLabel.TextStrokeTransparency = 0.3
    playerLabel.Size = UDim2.new(1, 0, 0.2, 0)
    playerLabel.Position = UDim2.new(0, 0, 0, 0)
    playerLabel.Text = ""
    playerLabel.Parent = container

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 16
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.Size = UDim2.new(1, 0, 0.222, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.2, 0)
    nameLabel.Text = ""
    nameLabel.Parent = container

    local traitsLabel = Instance.new("TextLabel")
    traitsLabel.Name = "TraitsLabel"
    traitsLabel.BackgroundTransparency = 1
    traitsLabel.Font = Enum.Font.Gotham
    traitsLabel.TextSize = 13
    traitsLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
    traitsLabel.TextStrokeTransparency = 0.3
    traitsLabel.Size = UDim2.new(1, 0, 0.178, 0)
    traitsLabel.Position = UDim2.new(0, 0, 0.444, 0)
    traitsLabel.Text = ""
    traitsLabel.Parent = container

    local healthBarBg = Instance.new("Frame")
    healthBarBg.Name = "HealthBarBg"
    healthBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    healthBarBg.BorderSizePixel = 0
    healthBarBg.Size = UDim2.new(1, 0, 0.089, 0)
    healthBarBg.Position = UDim2.new(0, 0, 0.689, 0)
    healthBarBg.Visible = Toggles.ShowHealthBar
    healthBarBg.Parent = container

    local healthBarFill = Instance.new("Frame")
    healthBarFill.Name = "HealthBarFill"
    healthBarFill.BackgroundColor3 = ESPColors.Health
    healthBarFill.BorderSizePixel = 0
    healthBarFill.Size = UDim2.new(1, 0, 1, 0)
    healthBarFill.Parent = healthBarBg

    local healthText = Instance.new("TextLabel")
    healthText.Name = "HealthText"
    healthText.BackgroundTransparency = 1
    healthText.Font = Enum.Font.GothamBold
    healthText.TextSize = 12
    healthText.TextColor3 = Color3.new(1, 1, 1)
    healthText.TextStrokeTransparency = 0.3
    healthText.TextXAlignment = Enum.TextXAlignment.Center
    healthText.Size = UDim2.new(1, 0, 0.156, 0)
    healthText.Position = UDim2.new(0, 0, 0.811, 0)
    healthText.Text = ""
    healthText.Visible = Toggles.ShowHealthBar
    healthText.Parent = container

    return {
        highlight = highlight,
        billboard = billboard,
        playerLabel = playerLabel,
        nameLabel = nameLabel,
        traitsLabel = traitsLabel,
        healthBarBg = healthBarBg,
        healthBarFill = healthBarFill,
        healthText = healthText,
        maxHealth = nil,
        lastSpecies = nil,
        cache = {},
        lastRawName = nil,
        displayName = nil
    }
end

local function DestroyESPEntry(model)
    local data = espData[model]
    if data then
        if data.highlight then
            pcall(function()
                data.highlight:Destroy()
            end)
        end
        if data.billboard then
            pcall(function()
                data.billboard:Destroy()
            end)
        end
        espData[model] = nil
    end
end

local function ClearESP()
    for model in pairs(espData) do
        DestroyESPEntry(model)
    end
    espData = {}
end

local function GetDisplayName(rawName)
    local player = Players:FindFirstChild(rawName)
    if player and player:IsA("Player") then
        return player.DisplayName
    end
    return rawName
end

local function SetEntryValue(data, key, instance, property, value)
    if data.cache[key] ~= value then
        data.cache[key] = value
        instance[property] = value
    end
end

local function UpdateESPEntry(model, data)
    if not model or not model.Parent then
        DestroyESPEntry(model)
        return
    end
    if not data.highlight or not data.highlight.Parent then
        DestroyESPEntry(model)
        return
    end

    local dataFolder = model:FindFirstChild("Data")
    local ailmentsFolder = model:FindFirstChild("Ailments")

    local health = tonumber(dataFolder and ReadValue(dataFolder, "h")) or 0
    local species = tostring((dataFolder and ReadValue(dataFolder, "Species")) or model.Name)
    local venStage = dataFolder and ReadValue(dataFolder, "vt")

    local maxHealthAttribute = dataFolder and ReadValue(dataFolder, "mh")
    local maxHealth
    if maxHealthAttribute ~= nil and tonumber(maxHealthAttribute) and tonumber(maxHealthAttribute) > 0 then
        maxHealth = tonumber(maxHealthAttribute)
        data.maxHealth = maxHealth
        data.lastSpecies = species
    else
        if data.lastSpecies ~= species then
            data.lastSpecies = species
            data.maxHealth = health
        end
        if health > (data.maxHealth or 0) then
            data.maxHealth = health
        end
        maxHealth = math.max(data.maxHealth or 1, 1)
    end

    local traitsText, isAggressive = GetAilmentsInfo(ailmentsFolder)

    local boxOk, boxCFrame, boxSize = pcall(function()
        return model:GetBoundingBox()
    end)
    if not boxOk or not boxCFrame then
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local camDistance = (camera.CFrame.Position - boxCFrame.Position).Magnitude
    local distance = camDistance
    local charactersFolder = Workspace:FindFirstChild("Characters")
    local myCreatureModel = charactersFolder and charactersFolder:FindFirstChild(PlayerName)
    if myCreatureModel and myCreatureModel ~= model and myCreatureModel:IsA("Model") then
        local pivotOk, myPivot = pcall(function()
            return myCreatureModel:GetPivot()
        end)
        if pivotOk and myPivot then
            local ownDistance = (myPivot.Position - boxCFrame.Position).Magnitude
            distance = math.min(camDistance, ownDistance)
        end
    end

    if distance > ESPSettings.MaxDistance then
        SetEntryValue(data, "billboardEnabled", data.billboard, "Enabled", false)
        SetEntryValue(data, "highlightEnabled", data.highlight, "Enabled", false)
        return
    end
    SetEntryValue(data, "billboardEnabled", data.billboard, "Enabled", true)
    SetEntryValue(data, "highlightEnabled", data.highlight, "Enabled", true)

    local color = isAggressive and ESPColors.Aggressive or ESPColors.Outline
    SetEntryValue(data, "outlineColor", data.highlight, "OutlineColor", color)
    SetEntryValue(data, "fillColor", data.highlight, "FillColor", color)
    SetEntryValue(data, "fillTransparency", data.highlight, "FillTransparency", ESPSettings.FillTransparency)

    local sizeY = boxSize and boxSize.Y or 4
    if data.cache.studsOffsetY ~= sizeY then
        data.cache.studsOffsetY = sizeY
        data.billboard.StudsOffsetWorldSpace = Vector3.new(0, sizeY * 0.5 + 1.5, 0)
    end

    local scale = 1
    if distance > 200 then
        scale = math.clamp((200 / distance), 0.30, 1)
    end
    scale = math.floor(scale * 20 + 0.5) / 20
    if data.cache.scale ~= scale then
        data.cache.scale = scale
        data.billboard.Size = UDim2.fromOffset(math.floor(220 * scale + 0.5), math.floor(90 * scale + 0.5))
    end

    SetEntryValue(data, "playerTextSize", data.playerLabel, "TextSize", math.max(10, math.floor(15 * scale)))
    SetEntryValue(data, "nameTextSize", data.nameLabel, "TextSize", math.max(10, math.floor(16 * scale)))
    SetEntryValue(data, "traitsTextSize", data.traitsLabel, "TextSize", math.max(9, math.floor(13 * scale)))
    SetEntryValue(data, "healthTextSize", data.healthText, "TextSize", math.max(9, math.floor(12 * scale)))

    local rawName = model.Name:gsub("^@", "")
    if data.lastRawName ~= rawName then
        data.lastRawName = rawName
        data.displayName = GetDisplayName(rawName)
    end
    SetEntryValue(data, "playerText", data.playerLabel, "Text", data.displayName or rawName)
    SetEntryValue(data, "nameText", data.nameLabel, "Text", species .. (isAggressive and "  ⚠" or ""))

    local venText = venStage ~= nil and ("Ven " .. tostring(venStage)) or ""
    local aggroText = isAggressive and "Aggressive" or ""
    local distanceText = string.format("%dm", math.floor(distance))
    local parts = {}
    if traitsText ~= "" then
        table.insert(parts, traitsText)
    end
    if aggroText ~= "" then
        table.insert(parts, aggroText)
    end
    if venText ~= "" then
        table.insert(parts, venText)
    end
    table.insert(parts, distanceText)
    SetEntryValue(data, "traitsText", data.traitsLabel, "Text", table.concat(parts, "  |  "))
    SetEntryValue(data, "traitsColor", data.traitsLabel, "TextColor3",
        isAggressive and ESPColors.Aggressive or DEFAULT_TRAIT_COLOR)

    local showHealth = Toggles.ShowHealthBar
    SetEntryValue(data, "healthBarVisible", data.healthBarBg, "Visible", showHealth)
    SetEntryValue(data, "healthTextVisible", data.healthText, "Visible", showHealth)
    if showHealth then
        local percent = math.clamp(health / math.max(maxHealth, 1), 0, 1)
        local percentKey = math.floor(percent * 100 + 0.5)
        if data.cache.healthPercent ~= percentKey then
            data.cache.healthPercent = percentKey
            data.healthBarFill.Size = UDim2.new(percentKey / 100, 0, 1, 0)
        end
        SetEntryValue(data, "healthFillColor", data.healthBarFill, "BackgroundColor3",
            percent <= 0.25 and ESPColors.LowHealth or ESPColors.Health)
        SetEntryValue(data, "healthText", data.healthText, "Text",
            string.format("%d/%d", math.floor(health), math.floor(maxHealth)))
    end
end

local NextESPUpdate = 0

local function UpdateESP(force)
    if not Toggles.OutlineESP then
        if next(espData) ~= nil then
            ClearESP()
        end
        return
    end

    local now = os.clock()
    if not force and now < NextESPUpdate then
        return
    end
    NextESPUpdate = now + 0.1

    local charactersFolder = Workspace:FindFirstChild("Characters")
    if not charactersFolder then
        ClearESP()
        return
    end

    local seen = {}
    for _, model in ipairs(charactersFolder:GetChildren()) do
        if model:IsA("Model") and model.Name:gsub("^@", "") ~= PlayerName then
            seen[model] = true
            if not espData[model] then
                espData[model] = CreateESPEntry(model)
            end
            UpdateESPEntry(model, espData[model])
        end
    end

    for model in pairs(espData) do
        if not seen[model] then
            DestroyESPEntry(model)
        end
    end
end

-- // Instant Menu (J) and Exploit Fly
local InstantConnection = nil
local DropInProgress = false
local currentFlyPosition = nil
local currentFlyRoot = nil
local flyInputs = {
    W = false,
    A = false,
    S = false,
    D = false,
    Space = false,
    LeftShift = false
}

local function GetLocalRoot()
    local character = GetLocalCharacter()
    return character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")) or nil
end

local function StartInstantDrop(ignoreToggle)
    local root = GetLocalRoot()
    if not root or DropInProgress then
        return
    end

    DropInProgress = true
    task.spawn(function()
        local startedAt = os.clock()
        local duration = DROP_DURATION
        while SessionActive() and (os.clock() - startedAt) < duration and (ignoreToggle or Toggles.InstantMenu) do
            local deltaTime = task.wait()
            local character = GetLocalCharacter()
            local currentRoot = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
            if not currentRoot then
                break
            end
            currentRoot.CFrame = currentRoot.CFrame * CFrame.new(0, -(DROP_SPEED * deltaTime), 0)
        end
        DropInProgress = false
    end)
end

local function SyncInstantMenu()
    if Toggles.InstantMenu then
        if not InstantConnection then
            InstantConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if gameProcessed or not SessionActive() then
                    return
                end
                if input.KeyCode == Enum.KeyCode.J then
                    StartInstantDrop(false)
                end
            end)
        end
    elseif InstantConnection then
        InstantConnection:Disconnect()
        InstantConnection = nil
    end
end

-- // Ailment / scent pulse loop
local NextScentPulse = 0
local NextAggroPulse = 0
local NextCowerPulse = 0

local function StartPulseLoop()
    task.spawn(function()
        while SessionActive() do
            local now = os.clock()

            if now >= NextScentPulse then
                if Toggles.HideScent then
                    FireHideScent(true)
                end
                NextScentPulse = now + Speeds.ScentPulse
            end

            if now >= NextAggroPulse then
                if Toggles.AlwaysAggro then
                    FireAilment("Aggression")
                end
                NextAggroPulse = now + Speeds.AilmentPulse
            end

            if now >= NextCowerPulse then
                if Toggles.AlwaysCower then
                    FireAilment("Cower")
                end
                NextCowerPulse = now + Speeds.AilmentPulse
            end

            task.wait(0.2)
        end
    end)
end

-- // Survival HUD bars ------------------------------------------------
-- The game calls the oxygen bar "BREATH" and names it Default. The
-- moisture bar is named Moisture. Both are hidden only while the matching
-- infinite stat is enabled, then restored to the state they had before.
local HUDHiddenBars = {}
local HUDBarsHidden = false

local function GetHUDGui()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    return playerGui and playerGui:FindFirstChild("HUDGui") or nil
end

local function GetBarsFrame(hudGui, frameName)
    local bottom = hudGui and hudGui:FindFirstChild("BottomFrame")
    local frame = bottom and bottom:FindFirstChild(frameName)
    return frame and frame:FindFirstChild("BarsFrame") or nil
end

local function GetBarByKind(barsFrame, kind)
    for _, bar in ipairs(barsFrame:GetChildren()) do
        if bar:IsA("GuiObject") then
            local nameLabel = bar:FindFirstChild("NameLabel")
            local label = nameLabel and nameLabel:IsA("TextLabel") and string.upper(nameLabel.Text) or ""
            if kind == "Oxygen" then
                if string.find(label, "BREATH", 1, true)
                    or string.find(label, "OXYGEN", 1, true)
                    or bar.Name == "Oxygen" then
                    return bar
                end
            elseif kind == "Moisture" then
                if string.find(label, "MOISTURE", 1, true) or bar.Name == "Moisture" then
                    return bar
                end
            end
        end
    end
    return nil
end

-- Resolved bar references are reused for two seconds instead of walking the
-- HUD tree on every heartbeat. Missing parents force an immediate refresh.
local HUDBarCache = {}
local HUDBarCacheAt = 0
local HUDBarCacheGui = nil
local HUD_BAR_CACHE_TTL = 2

local function RefreshHUDBarCache(hudGui)
    HUDBarCache = {}
    for _, frameName in ipairs({ "Other", "Mobile" }) do
        local barsFrame = GetBarsFrame(hudGui, frameName)
        if barsFrame then
            HUDBarCache[frameName] = {
                Oxygen = GetBarByKind(barsFrame, "Oxygen"),
                Moisture = GetBarByKind(barsFrame, "Moisture")
            }
        end
    end
    HUDBarCacheAt = os.clock()
    HUDBarCacheGui = hudGui
end

local function GetHUDBarCache(hudGui)
    local now = os.clock()
    if hudGui ~= HUDBarCacheGui
        or now - HUDBarCacheAt > HUD_BAR_CACHE_TTL
        or next(HUDBarCache) == nil then
        RefreshHUDBarCache(hudGui)
        return HUDBarCache
    end

    for _, entry in pairs(HUDBarCache) do
        if (entry.Oxygen and not entry.Oxygen.Parent)
            or (entry.Moisture and not entry.Moisture.Parent) then
            RefreshHUDBarCache(hudGui)
            break
        end
    end
    return HUDBarCache
end

-- Writes Visibility without letting our own change echo back into the
-- property listener that tracks what the game wants the bar to do.
local function WriteBarVisible(entry, bar, visible)
    entry.Suppress = true
    pcall(function()
        bar.Visible = visible
    end)
    entry.Suppress = false
end

local function SetHUDHidden(bar, hide)
    if not bar then
        return
    end

    local entry = HUDHiddenBars[bar]

    if hide then
        if not entry then
            entry = {
                Original = bar.Visible,
                Wanted = bar.Visible,
                Suppress = false,
                Connection = nil
            }
            HUDHiddenBars[bar] = entry
            -- The game may try to show the bar again while the stat is
            -- infinite. Hide it immediately instead of waiting a frame.
            entry.Connection = bar:GetPropertyChangedSignal("Visible"):Connect(function()
                local current = HUDHiddenBars[bar]
                if not current or current.Suppress then
                    return
                end
                current.Wanted = bar.Visible
                if bar.Visible then
                    WriteBarVisible(current, bar, false)
                end
            end)
        end
        if bar.Visible then
            entry.Wanted = true
            WriteBarVisible(entry, bar, false)
        end
        HUDBarsHidden = true
    elseif entry then
        HUDHiddenBars[bar] = nil
        if entry.Connection then
            pcall(function()
                entry.Connection:Disconnect()
            end)
        end
        if bar.Parent and bar.Visible ~= entry.Wanted then
            WriteBarVisible(entry, bar, entry.Wanted)
        end
    end
end

local function EnforceHUDVisibility()
    local hudGui = GetHUDGui()
    if not hudGui then
        return
    end
    -- Drop stale entries for bars that were destroyed or recreated by COS.
    for bar, entry in pairs(HUDHiddenBars) do
        if not bar.Parent then
            if entry.Connection then
                pcall(function()
                    entry.Connection:Disconnect()
                end)
            end
            HUDHiddenBars[bar] = nil
        end
    end
    local cache = GetHUDBarCache(hudGui)
    for _, frameName in ipairs({ "Other", "Mobile" }) do
        local cached = cache[frameName]
        if cached then
            SetHUDHidden(cached.Oxygen, Toggles.InfiniteOxygen)
            SetHUDHidden(cached.Moisture, Toggles.InfiniteMoisture)
        end
    end
end

local function RestoreHUDVisibility()
    for bar, entry in pairs(HUDHiddenBars) do
        if entry.Connection then
            pcall(function()
                entry.Connection:Disconnect()
            end)
        end
        if bar.Parent then
            WriteBarVisible(entry, bar, entry.Wanted)
        end
    end
    HUDHiddenBars = {}
    HUDBarsHidden = false
end

-- // Animation catalog and preview -------------------------------------
local ANIMATION_MAX_RESULTS = 40
local ANIMATION_CATALOG = {}
local ANIMATION_SPECIES_COUNTS = {}
local ANIMATION_PACKS = {}
local ANIMATION_PACK_SPECIES = {}
local ANIMATION_CURRENT_SPECIES = nil
local ANIMATION_CATALOG_READY = false
local ANIMATION_BASE_CATEGORIES = { "ALL", "MOVE", "SWIM", "POSE" }
local ANIMATION_CATEGORIES = { "ALL", "MOVE", "SWIM", "POSE" }
local ANIMATION_CATEGORY_KEYWORDS = {
    SWIM = { "swim", "dive" },
    MOVE = { "walk", "run", "jump", "fly", "glide", "flap", "fall", "grab" },
    POSE = { "idle", "sit", "lay", "pose", "mud", "beach", "rest", "sleep" }
}
local ANIMATION_CATEGORY_ORDER = { "SWIM", "MOVE", "POSE" }

-- Animations that do not match the broad groups are listed individually.
-- Variants collapse to their base type so Bite, Bite2, and BiteLeft all filter
-- as BITE, and EatUNUSED filters as EAT.
local function GetSpecificAnimationCategory(animationName)
    local name = string.lower(tostring(animationName or ""))
    name = string.gsub(name, "%s*%(leave%)", "")
    name = string.gsub(name, "unused$", "")
    name = string.gsub(name, "%d+$", "")
    name = string.gsub(name, "left$", "")
    name = string.gsub(name, "right$", "")
    return string.upper(name)
end

local function GetAnimationCategory(animationName)
    local lowerName = string.lower(tostring(animationName or ""))
    for _, category in ipairs(ANIMATION_CATEGORY_ORDER) do
        for _, keyword in ipairs(ANIMATION_CATEGORY_KEYWORDS[category]) do
            if string.find(lowerName, keyword, 1, true) then
                return category
            end
        end
    end
    return GetSpecificAnimationCategory(animationName)
end

local ANIMATION_PREVIEW = {
    Active = false,
    Name = nil,
    Species = nil,
    Foreign = false,
    Track = nil,
    Animation = nil
}
local AnimationCards = {}
local AnimationUI = {
    SearchBox = nil,
    Results = nil,
    CountLabel = nil,
    ScopeButton = nil,
    LoopButton = nil,
    Refresh = nil,
    Category = "ALL",
    Filtered = {},
    CategoryButtons = {},
    LastStatus = {}
}
local PlayerWrapperModule = nil
local UpdateAnimationStatus

local function GetAccentColor()
    if MyWindow and MyWindow.GetAccentColor then
        local ok, color = pcall(function()
            return MyWindow:GetAccentColor()
        end)
        if ok and typeof(color) == "Color3" then
            return color
        end
    end
    return (ApexLibrary.Theme and ApexLibrary.Theme.Accent) or Color3.fromRGB(255, 85, 0)
end

local function GetPlayerWrapper()
    if PlayerWrapperModule then
        return PlayerWrapperModule
    end
    local folder = ReplicatedStorage:FindFirstChild("_replicationFolder")
    local module = folder and folder:FindFirstChild("PlayerWrapper")
    if not module then
        return nil
    end
    local ok, result = pcall(require, module)
    if ok and type(result) == "table" then
        PlayerWrapperModule = result
        return result
    end
    return nil
end

local function GetCosCharacter()
    local wrapper = GetPlayerWrapper()
    if not wrapper then
        return nil
    end
    local ok, client = pcall(function()
        return wrapper.GetClient()
    end)
    if not ok or not client then
        return nil
    end
    local ok2, character = pcall(function()
        return client:GetCurrentCharacter()
    end)
    if ok2 then
        return character
    end
    return nil
end

local function GetCosAnimator(character)
    if not character then
        return nil
    end
    local controller = character.AnimationController
    if controller and controller.Parent then
        local animator = controller:FindFirstChildWhichIsA("Animator", true)
        if animator then
            return animator
        end
    end
    local root = character.Root
    local model = root and root.Parent
    if model then
        return model:FindFirstChildWhichIsA("Animator", true)
    end
    return nil
end

local function CountAnimationTracks(character)
    local count = 0
    if character and character.AnimationTracks then
        for _ in pairs(character.AnimationTracks) do
            count = count + 1
        end
    end
    return count
end

local function GetAnimationCatalogRoot()
    local storage = ReplicatedStorage:FindFirstChild("Storage")
    local creatures = storage and storage:FindFirstChild("Creatures")
    local root = creatures and creatures:FindFirstChild("Creatures")
    return root or creatures
end

local function BuildAnimationCatalog()
    local catalog = {}
    local counts = {}
    local packs = {}
    local extraCategories = {}
    local root = GetAnimationCatalogRoot()
    if root then
        for _, speciesFolder in ipairs(root:GetChildren()) do
            local speciesName = speciesFolder.Name
            local pack = {}
            for _, animation in ipairs(speciesFolder:GetDescendants()) do
                if animation:IsA("Animation") then
                    local animationId = animation.AnimationId
                    if type(animationId) == "string" and animationId ~= "" then
                        local category = GetAnimationCategory(animation.Name)
                        catalog[#catalog + 1] = {
                            Name = animation.Name,
                            Species = speciesName,
                            AnimationId = animationId,
                            Category = category
                        }
                        pack[#pack + 1] = {
                            Name = animation.Name,
                            AnimationId = animationId
                        }
                        counts[speciesName] = (counts[speciesName] or 0) + 1
                        if category ~= "SWIM" and category ~= "MOVE" and category ~= "POSE" then
                            extraCategories[category] = true
                        end
                    end
                end
            end
            if #pack > 0 then
                packs[speciesName] = pack
            end
        end
    end
    table.sort(catalog, function(a, b)
        if a.Name == b.Name then
            return a.Species < b.Species
        end
        return a.Name < b.Name
    end)
    local categories = {}
    for _, category in ipairs(ANIMATION_BASE_CATEGORIES) do
        categories[#categories + 1] = category
    end
    local sortedExtras = {}
    for category in pairs(extraCategories) do
        sortedExtras[#sortedExtras + 1] = category
    end
    table.sort(sortedExtras)
    for _, category in ipairs(sortedExtras) do
        categories[#categories + 1] = category
    end
    local packSpecies = {}
    for speciesName in pairs(packs) do
        packSpecies[#packSpecies + 1] = speciesName
    end
    table.sort(packSpecies)

    ANIMATION_CATEGORIES = categories
    ANIMATION_CATALOG = catalog
    ANIMATION_SPECIES_COUNTS = counts
    ANIMATION_PACKS = packs
    ANIMATION_PACK_SPECIES = packSpecies
    ANIMATION_CATALOG_READY = true
    local character = GetCosCharacter()
    ANIMATION_CURRENT_SPECIES = character and character.Species or nil
    return #catalog
end

local function StopForeignPreview()
    local preview = ANIMATION_PREVIEW
    if preview.Track then
        pcall(function()
            preview.Track:Stop(0.15)
        end)
        pcall(function()
            preview.Track:Destroy()
        end)
    end
    if preview.Animation then
        pcall(function()
            preview.Animation:Destroy()
        end)
    end
    preview.Track = nil
    preview.Animation = nil
end

local function ClearFakeAnimationState(character)
    if not character then
        return
    end
    local ok = pcall(function()
        character:ClearFakeState()
    end)
    if not ok and character.IgnoreStateTransitions then
        character.IgnoreStateTransitions = false
        pcall(function()
            character:SetState(character.State)
        end)
    end
end

-- // Creature animation pack replacement --------------------------------
-- Loads a complete animation pack from the game's animation library (for
-- example Kora's Idle/Walk/Run/Swim tracks) onto the current rig. The game
-- controller keeps driving its normal state machine, but every state now
-- resolves to the selected creature's animation. The mapping stays installed
-- until RESET, and the status line reports the live local tracks.
local ANIMATION_PACK_FALLBACKS = {
    Idle = { "Idle" },
    Walk = { "Walk", "Run" },
    Run = { "Run", "Walk" },
    Swim = { "Swim", "Walk" },
    SwimFast = { "SwimFast", "Swim", "Run" },
    SwimIdle = { "SwimIdle", "Swim", "Idle" },
    Jump = { "Jump", "Run", "Fall" },
    Fall = { "Fall", "Jump", "Idle" },
    FlyIdle = { "FlyIdle", "Glide", "Idle" },
    FlyForward = { "FlyForward", "Glide", "Run" },
    Glide = { "Glide", "FlyIdle", "FlyForward" },
    Flap = { "Flap", "Glide", "FlyIdle" },
    Dive = { "Dive", "Swim" },
    Ambush = { "Ambush", "Run" },
    Aggression = { "Aggression", "Cower", "Idle" },
    Cower = { "Cower", "Idle" },
    Lay = { "Lay", "Sit", "Idle" },
    Sit = { "Sit", "Lay", "Idle" },
    Mud = { "Mud", "Lay", "Idle" },
    Eat = { "Eat", "Drink", "Bite" },
    Drink = { "Drink", "Eat", "Bite" },
    Bite = { "Bite", "BiteLeft", "BiteRight", "Eat" }
}

local ANIMATION_SWAP = {
    Active = false,
    TargetSpecies = nil,
    TargetCount = 0,
    Character = nil,
    Root = nil,
    Tracks = {},
    Originals = {},
    AddedNames = {},
    UI = {},
    LastStatus = 0,
    LastStatusText = nil
}

local function BuildAnimationPackMap(species)
    local pack = species and ANIMATION_PACKS[species]
    if not pack then
        return nil
    end
    local map = {}
    for _, entry in ipairs(pack) do
        if not map[entry.Name] then
            map[entry.Name] = entry
        end
    end
    return map
end

local function ResolveAnimationPackTrack(stateName, map)
    local exact = map[stateName]
    if exact then
        return exact
    end
    local fallbacks = ANIMATION_PACK_FALLBACKS[stateName]
    if fallbacks then
        for _, name in ipairs(fallbacks) do
            if map[name] then
                return map[name]
            end
        end
    end
    return nil
end

function ANIMATION_SWAP.GetTargetCount()
    return ANIMATION_SWAP.TargetSpecies and #(ANIMATION_PACKS[ANIMATION_SWAP.TargetSpecies] or {}) or 0
end

function ANIMATION_SWAP.GetPlayingNames(character)
    local names = {}
    for name, track in pairs((character and character.AnimationTracks) or {}) do
        local playing = false
        pcall(function()
            playing = track and track.IsPlaying
        end)
        if playing then
            names[#names + 1] = tostring(name)
        end
    end
    table.sort(names)
    return names
end

function ANIMATION_SWAP.UpdateTargetUI()
    local selected = ANIMATION_SWAP.UI.SelectedLabel
    if selected then
        local species = ANIMATION_SWAP.TargetSpecies
        if species then
            selected.Text = "PACK: " .. tostring(species)
                .. " · " .. tostring(ANIMATION_SWAP.GetTargetCount()) .. " TRACKS"
        else
            selected.Text = "PACK: NONE SELECTED"
        end
    end
    if ANIMATION_SWAP.RefreshList then
        ANIMATION_SWAP.RefreshList()
    end
end

function ANIMATION_SWAP.SelectTarget(species)
    if not ANIMATION_PACKS[species] then
        return false
    end
    ANIMATION_SWAP.TargetSpecies = species
    ANIMATION_SWAP.UpdateTargetUI()
    ANIMATION_SWAP.UpdateStatus(true)
    SafeSetStatus("ANIMATION_PACK_TARGET")
    return true
end

function ANIMATION_SWAP.UpdateStatus(force)
    local now = os.clock()
    if not force and now - (ANIMATION_SWAP.LastStatus or 0) < 0.35 then
        return
    end
    ANIMATION_SWAP.LastStatus = now

    local label = ANIMATION_SWAP.UI.StatusLabel
    if not label then
        return
    end

    local character = ANIMATION_SWAP.Active and ANIMATION_SWAP.Character or GetCosCharacter()
    local playing = ANIMATION_SWAP.GetPlayingNames(character)
    local playingText = #playing > 0
        and table.concat(playing, " · ", 1, math.min(#playing, 5))
        or "—"

    local text
    if ANIMATION_SWAP.Active then
        text = "PACK (" .. tostring(ANIMATION_SWAP.TargetSpecies or "?") .. ")"
            .. " · " .. tostring(ANIMATION_SWAP.TargetCount) .. " TRACKS"
            .. "\nPLAYING: " .. playingText
    elseif ANIMATION_SWAP.TargetSpecies then
        text = "SELECTED: " .. tostring(ANIMATION_SWAP.TargetSpecies)
            .. " · " .. tostring(ANIMATION_SWAP.GetTargetCount()) .. " TRACKS"
            .. "\nPLAYING: " .. playingText
    else
        text = "PLAYING: " .. playingText
            .. "\nSELECT A CREATURE PACK ABOVE"
    end

    if text ~= ANIMATION_SWAP.LastStatusText then
        ANIMATION_SWAP.LastStatusText = text
        label.Text = text
    end
end

local ANIMATION_PACK_LOOPED = {
    Idle = true,
    Walk = true,
    Run = true,
    Swim = true,
    SwimFast = true,
    SwimIdle = true,
    FlyIdle = true,
    FlyForward = true,
    Glide = true,
    Jump = true,
    Fall = true,
    Ambush = true
}

local function IsLoopedPackState(stateName)
    return ANIMATION_PACK_LOOPED[stateName] == true
end

function ANIMATION_SWAP.Stop(silent)
    local character = ANIMATION_SWAP.Character
    local wasActive = ANIMATION_SWAP.Active

    for _, entry in ipairs(ANIMATION_SWAP.Tracks or {}) do
        pcall(function()
            entry.Track:Stop(0)
        end)
        pcall(function()
            entry.Track:Destroy()
        end)
        pcall(function()
            entry.Animation:Destroy()
        end)
    end

    if character and character.AnimationTracks then
        for name, original in pairs(ANIMATION_SWAP.Originals or {}) do
            if original then
                character.AnimationTracks[name] = original
            end
        end
        for _, name in ipairs(ANIMATION_SWAP.AddedNames or {}) do
            if not (ANIMATION_SWAP.Originals or {})[name] then
                character.AnimationTracks[name] = nil
            end
        end
    end

    if wasActive and character and character.Root and character.Root.Parent then
        pcall(function()
            character.IgnoreStateTransitions = false
            if character.SetState then
                character:SetState(character.State or "Idle")
            end
        end)
    end

    ANIMATION_SWAP.Active = false
    ANIMATION_SWAP.Character = nil
    ANIMATION_SWAP.Root = nil
    ANIMATION_SWAP.Tracks = {}
    ANIMATION_SWAP.Originals = {}
    ANIMATION_SWAP.AddedNames = {}
    ANIMATION_SWAP.TargetCount = 0
    ANIMATION_SWAP.LastStatusText = nil

    if not silent then
        UpdateAnimationStatus(true)
        ANIMATION_SWAP.UpdateStatus(true)
    end
end

function ANIMATION_SWAP.Start()
    if not ANIMATION_CATALOG_READY then
        BuildAnimationCatalog()
    end

    local species = ANIMATION_SWAP.TargetSpecies
    local pack = species and ANIMATION_PACKS[species]
    if not pack then
        SafeSetStatus("ANIMATION_PACK_NO_TARGET")
        ANIMATION_SWAP.UpdateStatus(true)
        return false
    end

    local character = GetCosCharacter()
    local root = character and character.Root
    if not character or not root or not root.Parent then
        SafeSetStatus("ANIMATION_PACK_NO_CREATURE")
        return false
    end

    StopForeignPreview()
    ANIMATION_PREVIEW.Active = false
    ANIMATION_PREVIEW.Name = nil
    ANIMATION_PREVIEW.Species = nil
    ANIMATION_PREVIEW.Foreign = false
    ANIMATION_SWAP.Stop(true)
    pcall(function()
        ClearFakeAnimationState(character)
    end)

    local animator = GetCosAnimator(character)
    local tracks = character.AnimationTracks
    if not animator or type(tracks) ~= "table" then
        SafeSetStatus("ANIMATION_PACK_FAILED")
        return false
    end

    local map = BuildAnimationPackMap(species)
    if not map then
        SafeSetStatus("ANIMATION_PACK_FAILED")
        return false
    end

    local originals = {}
    for name, track in pairs(tracks) do
        originals[name] = track
        pcall(function()
            if track and track.IsPlaying then
                track:Stop(0)
            end
        end)
    end

    local parent = character.AnimationController or root
    local entries = {}
    local addedNames = {}

    local function InstallTrack(stateName, source, original)
        local animation = Instance.new("Animation")
        animation.Name = "CosApexPack_" .. tostring(stateName)
        animation.AnimationId = source.AnimationId
        animation.Parent = parent

        local ok, track = pcall(function()
            return animator:LoadAnimation(animation)
        end)
        if not ok or not track then
            pcall(function()
                animation:Destroy()
            end)
            return false
        end

        local looped = IsLoopedPackState(stateName)
        if original then
            looped = original.Looped == true
        end
        pcall(function()
            track.Looped = looped
        end)
        if original and original.Priority then
            pcall(function()
                track.Priority = original.Priority
            end)
        end

        tracks[stateName] = track
        entries[#entries + 1] = {
            Name = stateName,
            Track = track,
            Animation = animation,
            Original = original
        }
        return true
    end

    for stateName, original in pairs(originals) do
        local source = ResolveAnimationPackTrack(stateName, map)
        if source then
            InstallTrack(stateName, source, original)
        end
    end

    -- Target-only states (for example fly or tail tracks the local species
    -- never loaded) are installed too, so the pack is complete.
    for stateName, source in pairs(map) do
        if not originals[stateName] then
            if InstallTrack(stateName, source, nil) then
                addedNames[#addedNames + 1] = stateName
            end
        end
    end

    if #entries == 0 then
        for name, original in pairs(originals) do
            if original then
                tracks[name] = original
            end
        end
        pcall(function()
            character:SetState(character.State or "Idle")
        end)
        SafeSetStatus("ANIMATION_PACK_FAILED")
        return false
    end

    ANIMATION_SWAP.Character = character
    ANIMATION_SWAP.Root = root
    ANIMATION_SWAP.Tracks = entries
    ANIMATION_SWAP.Originals = originals
    ANIMATION_SWAP.AddedNames = addedNames
    ANIMATION_SWAP.TargetCount = #pack
    ANIMATION_SWAP.Active = true

    pcall(function()
        character.IgnoreStateTransitions = false
        if character.SetState then
            character:SetState(character.State or "Idle")
        end
    end)

    UpdateAnimationStatus(true)
    ANIMATION_SWAP.UpdateTargetUI()
    ANIMATION_SWAP.UpdateStatus(true)
    SafeSetStatus("ANIMATION_PACK_ON")
    return true
end

function ANIMATION_SWAP.Enforce()
    if not ANIMATION_SWAP.Active then
        return
    end
    local character = ANIMATION_SWAP.Character
    local current = GetCosCharacter()
    if not character or character ~= current or not character.Root or not character.Root.Parent then
        ANIMATION_SWAP.Stop(true)
        return
    end
    local tracks = character.AnimationTracks
    if type(tracks) ~= "table" then
        return
    end
    for _, entry in ipairs(ANIMATION_SWAP.Tracks) do
        if entry.Track then
            tracks[entry.Name] = entry.Track
        end
    end
end

local function SetAnimationCard(card, key, value)
    if not card then
        return
    end
    if AnimationUI.LastStatus[key] ~= value then
        AnimationUI.LastStatus[key] = value
        pcall(function()
            card:SetValue(value)
        end)
    end
end

UpdateAnimationStatus = function(force)
    local now = os.clock()
    if not force and now - (AnimationUI.LastStatusTime or 0) < 0.5 then
        return
    end
    AnimationUI.LastStatusTime = now

    local character = GetCosCharacter()
    local species = character and character.Species or nil
    if species ~= ANIMATION_CURRENT_SPECIES then
        ANIMATION_CURRENT_SPECIES = species
        if ANIMATION_SWAP.Active then
            ANIMATION_SWAP.Stop(true)
        end
        if ANIMATION_PREVIEW.Active then
            StopForeignPreview()
            ClearFakeAnimationState(character)
            ANIMATION_PREVIEW.Active = false
            ANIMATION_PREVIEW.Name = nil
            ANIMATION_PREVIEW.Species = nil
            ANIMATION_PREVIEW.Foreign = false
        end
        if AnimationUI.Refresh then
            AnimationUI.Refresh()
        end
    end

    SetAnimationCard(AnimationCards.Species, "Species", tostring(species or "—"))
    SetAnimationCard(AnimationCards.State, "State", tostring((character and character.State) or "—"))
    SetAnimationCard(AnimationCards.Tracks, "Tracks", tostring(CountAnimationTracks(character)))

    local previewText = "ORIGINAL"
    if ANIMATION_SWAP.Active then
        previewText = "PACK · " .. tostring(ANIMATION_SWAP.TargetSpecies)
    elseif ANIMATION_PREVIEW.Active then
        previewText = tostring(ANIMATION_PREVIEW.Name) .. " · " .. tostring(ANIMATION_PREVIEW.Species)
        if ANIMATION_PREVIEW.Foreign then
            previewText = previewText .. " (FOREIGN)"
        end
    end
    SetAnimationCard(AnimationCards.Preview, "Preview", previewText)
end

local function RestoreOriginalAnimations()
    ANIMATION_SWAP.Stop(true)
    StopForeignPreview()
    local character = GetCosCharacter()
    if character then
        ClearFakeAnimationState(character)
    end
    ANIMATION_PREVIEW.Active = false
    ANIMATION_PREVIEW.Name = nil
    ANIMATION_PREVIEW.Species = nil
    ANIMATION_PREVIEW.Foreign = false
    UpdateAnimationStatus(true)
    ANIMATION_SWAP.UpdateStatus(true)
end

-- // Ragdoll -----------------------------------------------------------
-- The creature switches to its idle pose and holds that pose rigidly, but the
-- whole model becomes a real physics body. The game's movers are detached so
-- it cannot drive the character, collisions are enabled on the visible parts,
-- and the root is left unanchored so gravity and momentum can roll the body
-- around the map. Nothing rotates the model by hand. UNRAGDOLL restores the
-- movers, collisions, and animations, then stands the creature back up.
local RAGDOLL_COLLISION_TRANSPARENCY = 0.9
local RAGDOLL_TOPPLE_SPEED = 2.5
local RAGDOLL_MAX_MOMENTUM = 90

local RAGDOLL_MOVER_CLASSES = {
    BodyGyro = true,
    BodyVelocity = true,
    BodyForce = true,
    BodyPosition = true,
    BodyAngularVelocity = true,
    BodyThrust = true,
    LinearVelocity = true,
    AngularVelocity = true,
    VectorForce = true,
    Torque = true,
    AlignPosition = true,
    AlignOrientation = true
}

local RagdollState = {
    Active = false,
    Character = nil,
    Root = nil,
    Connection = nil,
    SavedMovers = nil,
    SavedParts = nil,
    SavedRootAnchored = false,
    SavedRootMassless = nil,
    SavedRootCanCollide = nil,
    SavedCFrame = nil,
    SavedState = nil,
    SavedStandOffset = 2,
    SavedTracks = {},
    DefaultGyroTorque = Vector3.new(9000000000, 9000000000, 9000000000),
    MoverProperties = {
        "MaxTorque",
        "MaxForce",
        "Force",
        "Enabled",
        "P",
        "D",
        "MaxVelocity"
    }
}

local function NeutralizeRagdollMovers(character)
    if character.BodyGyro then
        pcall(function()
            character.BodyGyro.MaxTorque = Vector3.new(0, 0, 0)
        end)
    end
    if character.BodyVelocity then
        pcall(function()
            character.BodyVelocity.MaxForce = Vector3.new(0, 0, 0)
        end)
    end
    if character.BodyForce then
        pcall(function()
            character.BodyForce.Force = Vector3.new(0, 0, 0)
        end)
    end
    if character.BodyPosition then
        pcall(function()
            character.BodyPosition.MaxForce = Vector3.new(0, 0, 0)
        end)
    end
    if character.LinearVelocity then
        pcall(function()
            character.LinearVelocity.Enabled = false
        end)
    end
end

local function GetRagdollMovers(character, model)
    local movers = {}
    local seen = {}
    local function add(mover)
        if mover and not seen[mover] then
            seen[mover] = true
            movers[#movers + 1] = mover
        end
    end

    if character then
        add(character.BodyGyro)
        add(character.BodyVelocity)
        add(character.BodyForce)
        add(character.BodyPosition)
        add(character.LinearVelocity)
        add(character.BodyAngularVelocity)
    end
    if model then
        for _, descendant in ipairs(model:GetDescendants()) do
            if RAGDOLL_MOVER_CLASSES[descendant.ClassName] then
                add(descendant)
            end
        end
    end
    return movers
end

-- Properties are not enough: the character controller rewrites MaxForce and
-- Enabled every frame. Detaching the movers makes the game's writes harmless
-- while ragdolled, and reattaching them restores normal movement afterward.
-- The setup-time properties (BodyGyro.MaxTorque in particular) are NOT
-- rewritten by the controller, so they must be captured and restored too.
function RagdollState.CaptureMoverProperties(mover)
    local props = {}
    for _, prop in ipairs(RagdollState.MoverProperties) do
        local ok, value = pcall(function()
            return mover[prop]
        end)
        if ok and value ~= nil then
            props[prop] = value
        end
    end
    return props
end

function RagdollState.ApplyMoverProperties(mover, props)
    for prop, value in pairs(props or {}) do
        pcall(function()
            mover[prop] = value
        end)
    end
end

local function DetachRagdollMovers(character, model)
    local saved = {}
    for _, mover in ipairs(GetRagdollMovers(character, model)) do
        saved[#saved + 1] = {
            Mover = mover,
            Parent = mover.Parent,
            Properties = RagdollState.CaptureMoverProperties(mover)
        }
        pcall(function()
            mover.Parent = nil
        end)
    end
    RagdollState.SavedMovers = saved
end

local function RestoreRagdollMovers()
    local saved = RagdollState.SavedMovers
    RagdollState.SavedMovers = nil
    for _, entry in ipairs(saved or {}) do
        local mover = entry.Mover
        if mover and entry.Parent then
            pcall(function()
                mover.Parent = entry.Parent
            end)
            RagdollState.ApplyMoverProperties(mover, entry.Properties)
            -- A zero torque gyro is the usual stale-ragdoll symptom: walking
            -- works through BodyVelocity but the body keeps tumbling because
            -- nothing uprights it. Fall back to the game's default torque.
            if mover.ClassName == "BodyGyro" then
                local ok, torque = pcall(function()
                    return mover.MaxTorque
                end)
                if ok and torque and torque.Magnitude < 1 then
                    pcall(function()
                        mover.MaxTorque = RagdollState.DefaultGyroTorque
                    end)
                end
            end
        end
    end
end

local function PrepareRagdollParts(character, root)
    local model = root and root.Parent
    local saved = {}
    local lowestY = root and root.Position.Y or 0
    local visibleParts = 0

    if model then
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < RAGDOLL_COLLISION_TRANSPARENCY then
                local bottom = part.Position.Y - part.Size.Y * 0.5
                if bottom < lowestY then
                    lowestY = bottom
                end
                saved[#saved + 1] = { Part = part, CanCollide = part.CanCollide }
                visibleParts = visibleParts + 1
                pcall(function()
                    part.CanCollide = true
                end)
            end
        end
    end

    RagdollState.SavedParts = saved
    RagdollState.SavedStandOffset = root and math.max(root.Position.Y - lowestY, 2) or 2

    if root then
        RagdollState.SavedRootMassless = root.Massless
        if root.Massless then
            pcall(function()
                root.Massless = false
            end)
        end
        if visibleParts == 0 then
            RagdollState.SavedRootCanCollide = root.CanCollide
            pcall(function()
                root.CanCollide = true
            end)
        end
    end
end

local function RestoreRagdollParts()
    local saved = RagdollState.SavedParts
    RagdollState.SavedParts = nil
    for _, entry in ipairs(saved or {}) do
        local part = entry.Part
        if part and part.Parent then
            pcall(function()
                part.CanCollide = entry.CanCollide
            end)
        end
    end

    local root = RagdollState.Root
    if root and root.Parent then
        if RagdollState.SavedRootMassless ~= nil then
            pcall(function()
                root.Massless = RagdollState.SavedRootMassless
            end)
        end
        if RagdollState.SavedRootCanCollide ~= nil then
            pcall(function()
                root.CanCollide = RagdollState.SavedRootCanCollide
            end)
        end
    end
    RagdollState.SavedRootMassless = nil
    RagdollState.SavedRootCanCollide = nil
end

local function EnterRagdollIdle(character)
    if not character then
        return
    end
    local ok = pcall(function()
        character:SetFakeState("Idle")
    end)
    if not ok then
        pcall(function()
            character:SetState("Idle")
        end)
    end
end

local function GetRagdollGroundY(root, model)
    local ok, filterType = pcall(function()
        return Enum.RaycastFilterType.Exclude
    end)
    if not ok then
        filterType = Enum.RaycastFilterType.Blacklist
    end
    local params = RaycastParams.new()
    params.FilterType = filterType
    params.FilterDescendantsInstances = { model }
    params.IgnoreWater = true
    local origin = root.Position + Vector3.new(0, root.Size.Y, 0)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -600, 0), params)
    return hit and hit.Position.Y or nil
end

local function FreezeRagdollAnimations(character)
    local animator = GetCosAnimator(character)
    if not animator then
        return
    end
    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if not ok or not tracks then
        return
    end
    for _, track in ipairs(tracks) do
        if track then
            if not RagdollState.SavedTracks[track] then
                local speed = 1
                pcall(function()
                    speed = track.Speed
                end)
                RagdollState.SavedTracks[track] = speed
            end
            pcall(function()
                track:AdjustSpeed(0)
            end)
        end
    end
end

local function RestoreRagdollAnimations()
    local tracks = RagdollState.SavedTracks
    RagdollState.SavedTracks = {}
    for track, speed in pairs(tracks) do
        pcall(function()
            track:AdjustSpeed(speed)
        end)
    end
end

function RagdollState.RecoverDetachedMovers()
    local character = GetCosCharacter()
    local root = character and character.Root
    if not character or not root or not root.Parent then
        return false
    end

    local recovered = false
    for _, name in ipairs({
        "BodyGyro",
        "BodyVelocity",
        "BodyForce",
        "BodyPosition",
        "LinearVelocity",
        "BodyAngularVelocity"
    }) do
        local ok, mover = pcall(function()
            return character[name]
        end)
        if ok and mover and mover.Parent == nil then
            local reparented = pcall(function()
                mover.Parent = root
            end)
            if reparented then
                recovered = true
            end
        end
    end

    if character.BodyGyro then
        local ok, torque = pcall(function()
            return character.BodyGyro.MaxTorque
        end)
        if ok and torque and torque.Magnitude < 1 then
            pcall(function()
                character.BodyGyro.MaxTorque = RagdollState.DefaultGyroTorque
            end)
            recovered = true
        end
    end

    if not recovered then
        return false
    end

    -- A lost ragdoll leaves collisions enabled and the body unanchored. Put
    -- the visible parts back to the game's normal non-colliding state, stand
    -- the creature upright, and resume its animation state machine.
    local model = root.Parent
    if model then
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") and part ~= root and part.Transparency < RAGDOLL_COLLISION_TRANSPARENCY then
                pcall(function()
                    part.CanCollide = false
                end)
            end
        end
    end

    pcall(function()
        local _, yaw = root.CFrame:ToOrientation()
        root.Anchored = false
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        if character.BodyGyro then
            character.BodyGyro.CFrame = root.CFrame
            character.BodyGyro.MaxTorque = RagdollState.DefaultGyroTorque
        end
        if character.BodyVelocity then
            character.BodyVelocity.Velocity = Vector3.new(0, 0, 0)
        end
        character.IgnoreStateTransitions = false
        if character.ClearFakeState then
            character:ClearFakeState()
        elseif character.SetState then
            character:SetState(character.State or "Idle")
        end
    end)

    return true
end

local function StopRagdoll(silent)
    if not RagdollState.Active then
        -- Recover from a stale ragdoll (script reload, lost state, or a
        -- previous unragdoll that only reattached the movers). Otherwise the
        -- creature keeps the ragdoll collisions and a zero-torque gyro, which
        -- lets it walk while still tumbling.
        local recovered = RagdollState.RecoverDetachedMovers()
        if recovered and not silent and SafeSetStatus then
            SafeSetStatus("RAGDOLL_OFF")
        end
        return
    end
    RagdollState.Active = false

    if RagdollState.Connection then
        pcall(function()
            RagdollState.Connection:Disconnect()
        end)
        RagdollState.Connection = nil
    end

    local character = RagdollState.Character
    local root = RagdollState.Root
    local savedAnchored = RagdollState.SavedRootAnchored

    -- Pin the model while it is repositioned so the game's movers cannot drag
    -- it away mid-restore.
    if root and root.Parent then
        pcall(function()
            root.Anchored = true
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end

    RestoreRagdollAnimations()

    -- Stand the creature up at the rolled XZ with its saved yaw, then snap it
    -- onto the floor beneath it.
    if root and root.Parent then
        local yaw = 0
        local savedFrame = RagdollState.SavedCFrame
        if savedFrame then
            pcall(function()
                local _, savedYaw = savedFrame:ToOrientation()
                yaw = savedYaw
            end)
        else
            pcall(function()
                local _, currentYaw = root.CFrame:ToOrientation()
                yaw = currentYaw
            end)
        end

        local position = root.Position
        local groundY = GetRagdollGroundY(root, root.Parent)
        if groundY then
            local offset = math.max(RagdollState.SavedStandOffset or 2, 2)
            position = Vector3.new(position.X, groundY + offset, position.Z)
        end

        local upright = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
        pcall(function()
            root.CFrame = upright
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
        if character and character.BodyGyro then
            pcall(function()
                character.BodyGyro.CFrame = upright
            end)
        end
        if character and character.BodyVelocity then
            pcall(function()
                character.BodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end)
        end
    end

    RestoreRagdollParts()
    RestoreRagdollMovers()

    if character then
        ClearFakeAnimationState(character)
        -- BodyGyro.MaxTorque is only configured when the character is built;
        -- the controller does not rewrite it. Restoring it is what stops the
        -- "I can walk but I still roll" limbo after UNRAGDOLL.
        pcall(function()
            if character.BodyGyro then
                local torque = character.BodyGyro.MaxTorque
                if torque.Magnitude < 1 then
                    character.BodyGyro.MaxTorque = RagdollState.DefaultGyroTorque
                end
            end
            character.IgnoreStateTransitions = false
            if character.SetState then
                character:SetState(RagdollState.SavedState or character.State or "Idle")
            end
        end)
    end

    if root and root.Parent then
        pcall(function()
            root.Anchored = savedAnchored
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            if character and character.BodyGyro then
                character.BodyGyro.CFrame = root.CFrame
            end
            if character and character.BodyVelocity then
                character.BodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end
        end)
    end

    RagdollState.Character = nil
    RagdollState.Root = nil
    RagdollState.SavedCFrame = nil
    RagdollState.SavedState = nil
    RagdollState.SavedRootAnchored = false
    RagdollState.SavedStandOffset = 2

    if not silent and SafeSetStatus then
        SafeSetStatus("RAGDOLL_OFF")
    end
end

local function StartRagdoll()
    if RagdollState.Active then
        if SafeSetStatus then
            SafeSetStatus("RAGDOLL_ON")
        end
        return true
    end

    local character = GetCosCharacter()
    local root = character and character.Root
    if not character or not root or not root.Parent then
        if SafeSetStatus then
            SafeSetStatus("RAGDOLL_NO_CREATURE")
        end
        return false
    end

    pcall(RestoreOriginalAnimations)

    RagdollState.Active = true
    RagdollState.Character = character
    RagdollState.Root = root
    RagdollState.SavedRootAnchored = root.Anchored
    RagdollState.SavedCFrame = root.CFrame
    RagdollState.SavedState = character.State
    RagdollState.SavedTracks = {}

    -- Capture the current momentum before the game's movers are detached.
    local momentum = Vector3.new(0, 0, 0)
    pcall(function()
        local velocity = root.AssemblyLinearVelocity
        momentum = Vector3.new(velocity.X, 0, velocity.Z)
        if momentum.Magnitude > RAGDOLL_MAX_MOMENTUM then
            momentum = momentum.Unit * RAGDOLL_MAX_MOMENTUM
        end
    end)

    -- Save the upright ground offset and enable collisions while the pose is
    -- still standing, so the restore has the correct numbers.
    PrepareRagdollParts(character, root)

    -- Hold the idle pose rigidly, then detach the movers so the controller
    -- cannot fight the physics body every frame.
    EnterRagdollIdle(character)
    FreezeRagdollAnimations(character)
    DetachRagdollMovers(character, root.Parent)

    pcall(function()
        root.Anchored = false
        root.AssemblyLinearVelocity = momentum
        local right = root.CFrame.RightVector
        local axis = Vector3.new(right.X, 0, right.Z)
        if axis.Magnitude > 0.001 then
            axis = axis.Unit
        else
            axis = Vector3.new(1, 0, 0)
        end
        root.AssemblyAngularVelocity = axis * RAGDOLL_TOPPLE_SPEED
    end)

    RagdollState.Connection = RunService.Heartbeat:Connect(function()
        if not SessionActive() then
            StopRagdoll(true)
            return
        end

        local rig = RagdollState.Character
        local rigRoot = RagdollState.Root
        if not rig or not rigRoot or not rigRoot.Parent then
            StopRagdoll(true)
            return
        end

        -- Physics owns the CFrame now. Only keep the controller neutral, the
        -- body unanchored, and the idle pose frozen.
        pcall(function()
            if rigRoot.Anchored then
                rigRoot.Anchored = false
            end
        end)
        NeutralizeRagdollMovers(rig)
        FreezeRagdollAnimations(rig)
    end)

    if SafeSetStatus then
        SafeSetStatus("RAGDOLL_ON")
    end
    return true
end

local function PreviewAnimation(entry)
    if type(entry) ~= "table" or not entry.Name or not entry.AnimationId then
        return false, "Invalid animation"
    end

    StopRagdoll(true)
    ANIMATION_SWAP.Stop(true)

    local character = GetCosCharacter()
    if not character then
        return false, "No active creature"
    end

    StopForeignPreview()
    ANIMATION_PREVIEW.Active = false
    ANIMATION_PREVIEW.Name = entry.Name
    ANIMATION_PREVIEW.Species = entry.Species
    ANIMATION_PREVIEW.Foreign = false

    local sameSpecies = ANIMATION_CURRENT_SPECIES
        and string.lower(tostring(entry.Species)) == string.lower(tostring(ANIMATION_CURRENT_SPECIES))
    local currentTrack = character.AnimationTracks and character.AnimationTracks[entry.Name]

    if sameSpecies and currentTrack then
        local ok = pcall(function()
            character:SetFakeState(entry.Name)
        end)
        if not ok then
            pcall(function()
                currentTrack:Play(0.2)
            end)
            pcall(function()
                character.IgnoreStateTransitions = true
            end)
        end
        ANIMATION_PREVIEW.Active = true
        ANIMATION_PREVIEW.Foreign = false
        UpdateAnimationStatus(true)
        return true
    end

    -- A foreign animation is loaded onto the current rig. State transitions
    -- are suppressed and normal tracks are stopped so the preview is visible.
    pcall(function()
        character.IgnoreStateTransitions = true
    end)
    for name, track in pairs(character.AnimationTracks or {}) do
        local metadata = character.Animations and character.Animations[name] or {}
        if track.IsPlaying and not metadata.Uncancellable then
            pcall(function()
                track:Stop(0.2)
            end)
        end
    end

    local animator = GetCosAnimator(character)
    if not animator then
        RestoreOriginalAnimations()
        return false, "Animator unavailable"
    end

    local animation = Instance.new("Animation")
    animation.Name = "CosApexPreview"
    animation.AnimationId = entry.AnimationId
    local animationParent = character.AnimationController or character.Root
    if animationParent then
        animation.Parent = animationParent
    end

    local ok, foreignTrack = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    if not ok or not foreignTrack then
        pcall(function()
            animation:Destroy()
        end)
        RestoreOriginalAnimations()
        return false, "Animation failed to load"
    end

    foreignTrack.Looped = Toggles.AnimationLoop ~= false
    pcall(function()
        foreignTrack.Priority = Enum.AnimationPriority.Action
    end)

    local played = pcall(function()
        foreignTrack:Play(0.2)
    end)
    if not played then
        pcall(function()
            foreignTrack:Destroy()
        end)
        pcall(function()
            animation:Destroy()
        end)
        RestoreOriginalAnimations()
        return false, "Animation failed to play"
    end

    ANIMATION_PREVIEW.Track = foreignTrack
    ANIMATION_PREVIEW.Animation = animation
    ANIMATION_PREVIEW.Active = true
    ANIMATION_PREVIEW.Foreign = true
    UpdateAnimationStatus(true)
    return true
end

local function GetAnimationQuery()
    local text = AnimationUI.SearchBox and AnimationUI.SearchBox.Text or ""
    text = string.lower(tostring(text))
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetFilteredAnimations(query)
    local results = {}
    local currentSpecies = ANIMATION_CURRENT_SPECIES
    local category = AnimationUI.Category or "ALL"
    for _, entry in ipairs(ANIMATION_CATALOG) do
        if Toggles.AnimationSearchAll or (currentSpecies and entry.Species == currentSpecies) then
            local nameLower = string.lower(entry.Name)
            local speciesLower = string.lower(entry.Species)
            local categoryMatches = category == "ALL" or entry.Category == category
            if categoryMatches and (query == ""
                or string.find(nameLower, query, 1, true)
                or string.find(speciesLower, query, 1, true)) then
                results[#results + 1] = entry
            end
        end
    end

    table.sort(results, function(a, b)
        local aCurrent = currentSpecies and a.Species == currentSpecies
        local bCurrent = currentSpecies and b.Species == currentSpecies
        if aCurrent ~= bCurrent then
            return aCurrent
        end
        if query ~= "" then
            local aExact = string.lower(a.Name) == query
            local bExact = string.lower(b.Name) == query
            if aExact ~= bExact then
                return aExact
            end
            local aPrefix = string.sub(string.lower(a.Name), 1, #query) == query
            local bPrefix = string.sub(string.lower(b.Name), 1, #query) == query
            if aPrefix ~= bPrefix then
                return aPrefix
            end
        end
        if a.Name ~= b.Name then
            return a.Name < b.Name
        end
        return a.Species < b.Species
    end)
    return results
end

local function SetAnimationStatus(text)
    if SafeSetStatus then
        SafeSetStatus(text)
    end
end

local function GetActionAnimationResults()
    return GetFilteredAnimations(GetAnimationQuery())
end

local function PreviewRandomAnimation()
    local filtered = GetActionAnimationResults()
    if #filtered == 0 then
        SetAnimationStatus("ANIM_NO_MATCHES")
        return
    end
    local entry = filtered[math.random(1, #filtered)]
    local ok = PreviewAnimation(entry)
    SetAnimationStatus(ok and "ANIM_RANDOM" or "ANIMATION_FAILED")
end

local function CycleAnimation(step)
    local filtered = GetActionAnimationResults()
    if #filtered == 0 then
        SetAnimationStatus("ANIM_NO_MATCHES")
        return
    end

    local index = 0
    if ANIMATION_PREVIEW.Name then
        for position, entry in ipairs(filtered) do
            if entry.Name == ANIMATION_PREVIEW.Name and entry.Species == ANIMATION_PREVIEW.Species then
                index = position
                break
            end
        end
    end

    index = index + (step or 1)
    if index < 1 then
        index = #filtered
    elseif index > #filtered then
        index = 1
    end

    local entry = filtered[index]
    local ok = PreviewAnimation(entry)
    SetAnimationStatus(ok and "ANIM_CYCLE" or "ANIMATION_FAILED")
end

local function UpdateAnimationScopeButton()
    if not AnimationUI.ScopeButton then
        return
    end
    if Toggles.AnimationSearchAll then
        AnimationUI.ScopeButton.Text = "SCOPE: ALL (" .. tostring(#ANIMATION_CATALOG) .. ")"
    else
        local count = ANIMATION_CURRENT_SPECIES
            and (ANIMATION_SPECIES_COUNTS[ANIMATION_CURRENT_SPECIES] or 0)
            or 0
        AnimationUI.ScopeButton.Text = "SCOPE: CURRENT (" .. tostring(count) .. ")"
    end
end

local function RenderAnimationResults()
    local results = AnimationUI.Results
    if not results then
        return
    end

    local query = GetAnimationQuery()
    local filtered = GetFilteredAnimations(query)
    AnimationUI.Filtered = filtered
    results:Clear()

    local shown = 0
    for _, entry in ipairs(filtered) do
        if shown >= ANIMATION_MAX_RESULTS then
            break
        end
        shown = shown + 1
        local isCurrent = ANIMATION_CURRENT_SPECIES and entry.Species == ANIMATION_CURRENT_SPECIES
        local label = (isCurrent and "[CURRENT] " or "") .. entry.Name .. "  ·  " .. entry.Species
        local button = results:AddButton(label, isCurrent and GetAccentColor() or nil, function()
            local ok, err = PreviewAnimation(entry)
            if not ok then
                SafeSetStatus("ANIMATION_FAILED")
                if AnimationUI.CountLabel then
                    AnimationUI.CountLabel.Text = "ERROR: " .. tostring(err)
                end
            end
        end)
        if button then
            button.TextXAlignment = Enum.TextXAlignment.Left
            button.TextTruncate = Enum.TextTruncate.AtEnd
        end
    end

    if #filtered == 0 then
        results:AddLabel("No matching animations.", nil, 24)
    elseif #filtered > shown then
        results:AddLabel("Showing first " .. tostring(shown) .. " of " .. tostring(#filtered) .. " matches. Refine your search.", nil, 30)
    end

    if AnimationUI.CountLabel then
        AnimationUI.CountLabel.Text = tostring(#filtered) .. " MATCHES"
    end
    UpdateAnimationScopeButton()
end

-- // Status cards
local LastStatusUpdate = 0

local function CountNearbyCreatures()
    local charactersFolder = Workspace:FindFirstChild("Characters")
    if not charactersFolder then
        return 0
    end
    local count = 0
    for _, model in ipairs(charactersFolder:GetChildren()) do
        if model:IsA("Model") and model.Name:gsub("^@", "") ~= PlayerName then
            count = count + 1
        end
    end
    return count
end

local function UpdateStatusCards(force)
    local now = os.clock()
    if not force and now - LastStatusUpdate < 1 then
        return
    end
    LastStatusUpdate = now

    if StatusCards.Nearby then
        StatusCards.Nearby:SetValue(tostring(CountNearbyCreatures()))
    end
    if StatusCards.OOB then
        StatusCards.OOB:SetValue(OOBRemoved and "REMOVED" or "PRESENT")
    end
    if StatusCards.Staff then
        StatusCards.Staff:SetValue(StaffKickIssued and "TRIGGERED" or "ARMED")
    end
end

-- // Cleanup (also used when a newer copy of the script takes over)
local CleanedOnce = false

CleanupSession = function()
    if CleanedOnce then
        return
    end
    CleanedOnce = true

    ScriptRunning = false
    DisconnectTrackedConnections()

    if InstantConnection then
        pcall(function()
            InstantConnection:Disconnect()
        end)
        InstantConnection = nil
    end

    pcall(RestoreMinimap)
    pcall(ClearESP)
    pcall(RestoreHUDVisibility)
    pcall(function()
        StopRagdoll(true)
    end)
    pcall(RestoreOriginalAnimations)
    pcall(function()
        SetClimberState(false)
    end)
    pcall(function()
        FireHideScent(false)
    end)

    DropInProgress = false
    currentFlyPosition = nil
    currentFlyRoot = nil
    flyInputs.W = false
    flyInputs.A = false
    flyInputs.S = false
    flyInputs.D = false
    flyInputs.Space = false
    flyInputs.LeftShift = false

    if sessionRegistered and getgenv then
        pcall(function()
            if getgenv().CosApexSession == SESSION then
                getgenv().CosApexSession = nil
            end
        end)
    end
end

-- // Shared inputs
TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not SessionActive() or gameProcessed then
        return
    end
    if flyInputs[input.KeyCode.Name] ~= nil then
        flyInputs[input.KeyCode.Name] = true
    end
end))

TrackConnection(UserInputService.InputEnded:Connect(function(input)
    if not SessionActive() then
        return
    end
    if flyInputs[input.KeyCode.Name] ~= nil then
        flyInputs[input.KeyCode.Name] = false
    end
end))

-- // Player events
if Players.PlayerAdded then
    TrackConnection(Players.PlayerAdded:Connect(function(player)
        if not SessionActive() then
            return
        end
        CheckPlayerForStaff(player)
        if Toggles.MinimapESP then
            ApplyMinimapToPlayer(player)
        end
    end))
end

if Players.PlayerRemoving then
    TrackConnection(Players.PlayerRemoving:Connect(function(player)
        MinimapOriginal[player] = nil
        MinimapVisibilityCache[player] = nil
    end))
end

if LocalPlayer.CharacterAdded then
    TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
        StopRagdoll(true)
        ANIMATION_CURRENT_SPECIES = nil
        pcall(RestoreOriginalAnimations)
        UpdateAnimationStatus(true)
    end))
end

if LocalPlayer.CharacterRemoving then
    TrackConnection(LocalPlayer.CharacterRemoving:Connect(function()
        StopRagdoll(true)
        ANIMATION_SWAP.Stop(true)
        pcall(StopForeignPreview)
        ANIMATION_PREVIEW.Active = false
        ANIMATION_PREVIEW.Name = nil
        ANIMATION_PREVIEW.Species = nil
        ANIMATION_PREVIEW.Foreign = false
        UpdateAnimationStatus(true)
        ANIMATION_SWAP.UpdateStatus(true)
    end))
end

-- // Main heartbeat: staff scan, minimap enforcement, attributes, status.
local NextMinimapUpdate = 0
local NextStaffScan = 0
TrackConnection(RunService.Heartbeat:Connect(function()
    if not SessionActive() then
        CleanupSession()
        return
    end

    local now = os.clock()
    if now >= NextStaffScan then
        NextStaffScan = now + 1
        for _, player in ipairs(Players:GetPlayers()) do
            if CheckPlayerForStaff(player) then
                break
            end
        end
    end

    if Toggles.MinimapESP then
        if now >= NextMinimapUpdate then
            ApplyMinimapNow()
            NextMinimapUpdate = now + 0.25
        end
    else
        NextMinimapUpdate = 0
    end

    local _, localData = GetLocalCharacterAndData()
    if localData then
        EnforceClimber(localData)
        EnforceAttributes(localData)
    end
    UpdateESP()
    if Toggles.InfiniteOxygen or Toggles.InfiniteMoisture then
        EnforceHUDVisibility()
    elseif HUDBarsHidden then
        RestoreHUDVisibility()
    end
    UpdateAnimationStatus(false)
    ANIMATION_SWAP.Enforce()
    ANIMATION_SWAP.UpdateStatus(false)
    UpdateStatusCards(false)
end))

-- // Exploit Fly render loop.
TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
    if not SessionActive() then
        CleanupSession()
        return
    end
    if not Toggles.ExploitFly then
        currentFlyPosition = nil
        currentFlyRoot = nil
        return
    end

    local root = GetLocalRoot()
    if not root then
        currentFlyPosition = nil
        currentFlyRoot = nil
        return
    end

    if currentFlyRoot ~= root or not currentFlyPosition then
        currentFlyRoot = root
        currentFlyPosition = root.Position
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local moveVector = Vector3.new(0, 0, 0)
    if flyInputs.W then
        moveVector = moveVector + camera.CFrame.LookVector
    end
    if flyInputs.S then
        moveVector = moveVector - camera.CFrame.LookVector
    end
    if flyInputs.D then
        moveVector = moveVector + camera.CFrame.RightVector
    end
    if flyInputs.A then
        moveVector = moveVector - camera.CFrame.RightVector
    end
    if flyInputs.Space then
        moveVector = moveVector + Vector3.new(0, 1, 0)
    end
    if flyInputs.LeftShift then
        moveVector = moveVector - Vector3.new(0, 1, 0)
    end

    if moveVector.Magnitude > 0 then
        moveVector = moveVector.Unit
    end

    currentFlyPosition = currentFlyPosition + (moveVector * Speeds.ExploitFly * deltaTime)
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    root.CFrame = CFrame.new(currentFlyPosition) * root.CFrame.Rotation
end))

-- // Apex UI
SafeSetStatus = function(text)
    if MyWindow then
        pcall(function()
            MyWindow:SetStatus(text)
        end)
    end
end

local function BindToggle(key, onChanged)
    return function(state)
        Toggles[key] = state == true
        SaveScriptConfig()
        if onChanged then
            pcall(onChanged, state)
        end
    end
end

local function BindColor(key)
    return function(color)
        ESPColors[key] = color
        SaveScriptConfig()
    end
end

local function BuildUI()
    local ApexVersion = tostring(ApexLibrary.Version or "APEX_SYS")
    ApexVersion = ApexVersion:gsub("^APEX_SYS%s*", "")

    MyWindow = ApexLibrary.new({
        Title = "Creatures of Sonaria // Menu",
        BrandText = AUTHOR .. " // " .. ApexVersion,
        StatusText = "BOOTING",
        AccentColor = Color3.fromRGB(255, 85, 0),
        HideKey = Enum.KeyCode.RightControl
    })

    local function BuildTab(name, subtitle, build)
        local tab = MyWindow:CreateTab(name, subtitle)
        local ok, err = pcall(build, tab)
        if not ok then
            warn("[Cos Apex] Failed to build tab " .. name .. ": " .. tostring(err))
        end
        return tab
    end

    -- MAIN -----------------------------------------------------------------
    BuildTab("MAIN", "DASHBOARD & SYSTEM INFO", function(tab)
        tab:CreateReadMeCard(
            "WELCOME // CREATURES OF SONARIA",
            "Apex migration of Drk_Duck's original Cos menu. Press [J] while INSTANT_MENU is enabled to drop below the map, or use the DROP NOW button. ESP colors, distances, and survival pulses are configurable.",
            104
        )
        tab:CreateSectionLabel("SESSION INFO")
        tab:CreateInfoCard("PLAYER", PlayerName)
        tab:CreateInfoCard("AUTHOR", AUTHOR)
        tab:CreateInfoCard("SCRIPT_VERSION", SCRIPT_VERSION)
        tab:CreateInfoCard("UI_ENGINE", ApexLibrary.Version or "APEX_SYS")

        tab:CreateSectionLabel("LIVE STATUS")
        StatusCards.Nearby = tab:CreateInfoCard("NEARBY_CREATURES", "0")
        StatusCards.OOB = tab:CreateInfoCard("OOB_DAMAGE_REMOTE", OOBRemoved and "REMOVED" or "PRESENT")
        StatusCards.Staff = tab:CreateInfoCard("STAFF_GUARD", "ARMED")

        tab:CreateReadMeCard(
            "QUICK NOTES",
            "OOB removal happens immediately on load. The staff guard is always on and kicks when a configured staff permission is detected. Use CONFIG to change the shared APEX accent and hide key.",
            88
        )
    end)

    -- MOVEMENT -------------------------------------------------------------
    BuildTab("MOVEMENT", "TELEPORT, SPEEDS & FLIGHT", function(tab)
        tab:CreateSectionLabel("INSTANT MENU")
        tab:CreateToggle(
            "INSTANT_MENU [J]",
            "While enabled, press J to drop straight down at high speed. Useful for reaching the menu area below the map.",
            Toggles.InstantMenu,
            function(state)
                Toggles.InstantMenu = state
                SyncInstantMenu()
                SaveScriptConfig()
            end
        )
        tab:CreateButton(
            "DROP_NOW [J]",
            "Run the downward CFrame drop once, even if the toggle is off.",
            function()
                StartInstantDrop(true)
            end
        )

        tab:CreateSectionLabel("ATTRIBUTE SPEEDS")
        local walkControl
        walkControl = tab:CreateToggleWithInput(
            "WALK_SWIM_SPEED",
            "Set the game's walk / swim speed attribute (s)",
            Toggles.WalkSpeed,
            Speeds.Walk,
            BindToggle("WalkSpeed", function(state)
                local data = GetLocalCharacterData()
                if state then
                    CaptureSpeedAttribute(data, "s")
                else
                    RestoreSpeedAttribute("s")
                end
            end),
            function(value)
                Speeds.Walk = ClampNumber(value, 1, 5000, Speeds.Walk)
                if walkControl then
                    walkControl:SetValue(Speeds.Walk)
                end
                SaveScriptConfig()
            end
        )

        local sprintControl
        sprintControl = tab:CreateToggleWithInput(
            "SPRINT_SPEED",
            "Set the game's sprint speed attribute (ss)",
            Toggles.SprintSpeed,
            Speeds.Sprint,
            BindToggle("SprintSpeed", function(state)
                local data = GetLocalCharacterData()
                if state then
                    CaptureSpeedAttribute(data, "ss")
                else
                    RestoreSpeedAttribute("ss")
                end
            end),
            function(value)
                Speeds.Sprint = ClampNumber(value, 1, 5000, Speeds.Sprint)
                if sprintControl then
                    sprintControl:SetValue(Speeds.Sprint)
                end
                SaveScriptConfig()
            end
        )

        local flyControl
        flyControl = tab:CreateToggleWithInput(
            "FLY_SPEED",
            "Set the game's flight speed attribute (fs)",
            Toggles.FlySpeed,
            Speeds.Fly,
            BindToggle("FlySpeed", function(state)
                local data = GetLocalCharacterData()
                if state then
                    CaptureSpeedAttribute(data, "fs")
                else
                    RestoreSpeedAttribute("fs")
                end
            end),
            function(value)
                Speeds.Fly = ClampNumber(value, 1, 5000, Speeds.Fly)
                if flyControl then
                    flyControl:SetValue(Speeds.Fly)
                end
                SaveScriptConfig()
            end
        )

        tab:CreateSectionLabel("EXPLOIT FLY")
        local exploitFlyControl
        exploitFlyControl = tab:CreateToggleWithInput(
            "EXPLOIT_FLY",
            "Camera-relative CFrame flight. Hold W/A/S/D, Space to rise, LeftShift to sink.",
            Toggles.ExploitFly,
            Speeds.ExploitFly,
            function(state)
                Toggles.ExploitFly = state
                currentFlyPosition = nil
                currentFlyRoot = nil
                SaveScriptConfig()
            end,
            function(value)
                Speeds.ExploitFly = ClampNumber(value, 1, EXPLOIT_FLY_MAX, Speeds.ExploitFly)
                if exploitFlyControl then
                    exploitFlyControl:SetValue(Speeds.ExploitFly)
                end
                SaveScriptConfig()
            end
        )
        tab:CreateReadMeCard(
            "FLIGHT NOTE",
            "Exploit Fly ignores normal flight limits by moving your root CFrame. Release the keys to hover and turn the toggle off to return control to the game.",
            78
        )
    end)

    -- SURVIVAL -------------------------------------------------------------
    BuildTab("SURVIVAL", "STATS, AILMENTS & CLIMBING", function(tab)
        tab:CreateSectionLabel("CORE STATS")
        tab:CreateToggle(
            "INFINITE_STAMINA",
            "Keep stamina and stamina regeneration at a very high value.",
            Toggles.InfiniteStamina,
            BindToggle("InfiniteStamina")
        )
        tab:CreateToggle(
            "INFINITE_OXYGEN",
            "Keep the Oxygen attribute at a very high value and hide the BREATH bar while enabled.",
            Toggles.InfiniteOxygen,
            BindToggle("InfiniteOxygen")
        )
        tab:CreateToggle(
            "INFINITE_MOISTURE",
            "Keep the Moisture attribute at a very high value and hide the MOISTURE bar while enabled.",
            Toggles.InfiniteMoisture,
            BindToggle("InfiniteMoisture")
        )

        tab:CreateSectionLabel("CLIMBING")
        tab:CreateToggle(
            "ALWAYS_WALL_CLIMBER",
            "Force the Climber attribute on your creature.",
            Toggles.AlwaysClimber,
            BindToggle("AlwaysClimber", function(state)
                SetClimberState(state)
            end)
        )

        tab:CreateSectionLabel("AILMENTS & SCENT")
        tab:CreateToggle(
            "HIDE_SCENT",
            "Pulse the HideScent remote so creature scent stays hidden.",
            Toggles.HideScent,
            function(state)
                Toggles.HideScent = state
                NextScentPulse = 0
                FireHideScent(state)
                SaveScriptConfig()
            end
        )
        tab:CreateToggle(
            "ALWAYS_AGGRO",
            "Pulse the Aggression ailment every few seconds.",
            Toggles.AlwaysAggro,
            function(state)
                Toggles.AlwaysAggro = state
                NextAggroPulse = 0
                SaveScriptConfig()
            end
        )
        tab:CreateToggle(
            "ALWAYS_COWER",
            "Pulse the Cower ailment every few seconds.",
            Toggles.AlwaysCower,
            function(state)
                Toggles.AlwaysCower = state
                NextCowerPulse = 0
                SaveScriptConfig()
            end
        )

        local scentPulseInput
        scentPulseInput = tab:CreateInputCard(
            "SCENT_PULSE",
            "Seconds between HideScent pulses (default 5)",
            Speeds.ScentPulse,
            function(value)
                Speeds.ScentPulse = ClampNumber(value, 1, 60, Speeds.ScentPulse)
                if scentPulseInput then
                    scentPulseInput:SetValue(Speeds.ScentPulse)
                end
                SaveScriptConfig()
            end
        )

        local ailmentPulseInput
        ailmentPulseInput = tab:CreateInputCard(
            "AILMENT_PULSE",
            "Seconds between Aggro and Cower pulses (default 8)",
            Speeds.AilmentPulse,
            function(value)
                Speeds.AilmentPulse = ClampNumber(value, 1, 60, Speeds.AilmentPulse)
                if ailmentPulseInput then
                    ailmentPulseInput:SetValue(Speeds.AilmentPulse)
                end
                SaveScriptConfig()
            end
        )

        tab:CreateSectionLabel("WORLD SAFETY")
        tab:CreateButton(
            "RETRY_OOB_REMOVAL",
            "Try again if the OutOfBoundsSelfDamage remote was not present at load.",
            function()
                TryRemoveOutOfBoundsDamage()
                UpdateStatusCards(true)
                SafeSetStatus(OOBRemoved and "OOB_REMOVED" or "OOB_PENDING")
            end
        )
        tab:CreateReadMeCard(
            "SURVIVAL NOTE",
            "Infinite stats are enforced every frame and persist while their toggles remain on. The game may reset attributes on respawn; the heartbeat reapplies them automatically.",
            82
        )
    end)

    -- ESP ------------------------------------------------------------------
    BuildTab("ESP", "OUTLINE ESP & MINIMAP", function(tab)
        tab:CreateSectionLabel("OUTLINE ESP")
        tab:CreateToggleWithColor(
            "OUTLINE_ESP",
            "Draw a true Highlight outline, floating info panel, and health bar around every other creature.",
            Toggles.OutlineESP,
            ESPColors.Outline,
            function(state)
                Toggles.OutlineESP = state
                if not state then
                    ClearESP()
                end
                SaveScriptConfig()
            end,
            BindColor("Outline")
        )

        tab:CreateSectionLabel("ESP COLORS")
        tab:CreateColorPicker(
            "AGGRESSIVE_COLOR",
            "Outline and text color for aggressive creatures",
            ESPColors.Aggressive,
            BindColor("Aggressive")
        )
        tab:CreateColorPicker(
            "HEALTH_COLOR",
            "Health bar color above 25 percent",
            ESPColors.Health,
            BindColor("Health")
        )
        tab:CreateColorPicker(
            "LOW_HEALTH_COLOR",
            "Health bar color at or below 25 percent",
            ESPColors.LowHealth,
            BindColor("LowHealth")
        )

        tab:CreateSectionLabel("ESP TUNING")
        tab:CreateToggle(
            "SHOW_HEALTH_BARS",
            "Show creature health values in the floating panel.",
            Toggles.ShowHealthBar,
            BindToggle("ShowHealthBar")
        )

        local fillInput
        fillInput = tab:CreateInputCard(
            "ESP_FILL_TRANSPARENCY",
            "0 = solid glow, 1 = outline only (default 1)",
            ESPSettings.FillTransparency,
            function(value)
                ESPSettings.FillTransparency = ClampNumber(value, 0, 1, ESPSettings.FillTransparency)
                if fillInput then
                    fillInput:SetValue(ESPSettings.FillTransparency)
                end
                SaveScriptConfig()
            end
        )

        local distanceInput
        distanceInput = tab:CreateInputCard(
            "ESP_MAX_DISTANCE",
            "Hide panels beyond this many studs (default 1500)",
            ESPSettings.MaxDistance,
            function(value)
                ESPSettings.MaxDistance = ClampNumber(value, 50, 10000, ESPSettings.MaxDistance)
                if distanceInput then
                    distanceInput:SetValue(ESPSettings.MaxDistance)
                end
                SaveScriptConfig()
            end
        )

        tab:CreateButton(
            "CLEAR_ESP",
            "Destroy every active ESP highlight and panel.",
            function()
                ClearESP()
                SafeSetStatus("ESP_CLEARED")
            end
        )

        tab:CreateSectionLabel("MINIMAP")
        tab:CreateToggle(
            "MINIMAP_ESP",
            "Force every other player's minimap visibility to Everyone while enabled, then restore their original value.",
            Toggles.MinimapESP,
            function(state)
                Toggles.MinimapESP = state
                if state then
                    ApplyMinimapNow()
                else
                    RestoreMinimap()
                end
                SaveScriptConfig()
            end
        )
        tab:CreateReadMeCard(
            "ESP NOTE",
            "Panels scale down with distance, show trait letters, Ven stage, aggression, and distance. Aggressive creatures use the aggressive color. Minimap changes are restored on toggle off or cleanup.",
            88
        )
    end)

    -- ANIMATION ------------------------------------------------------------
    BuildTab("ANIMATION", "ANIMATION SWAPPER & PREVIEW", function(tab)
        tab:CreateSectionLabel("LIVE ANIMATION STATE")
        AnimationCards.Species = tab:CreateInfoCard("CURRENT_SPECIES", "—")
        AnimationCards.State = tab:CreateInfoCard("CURRENT_STATE", "—")
        AnimationCards.Tracks = tab:CreateInfoCard("LOADED_TRACKS", "0")
        AnimationCards.Preview = tab:CreateInfoCard("PREVIEWING", "ORIGINAL")

        tab:CreateSectionLabel("ANIMATION SWAPPER")
        BuildAnimationCatalog()

        local theme = ApexLibrary.Theme

        -- Custom controls in this card follow the same hover and border
        -- treatment as the library's own action/list buttons.
        local function AddFeatureHover(button, baseColor, canHover)
            local function targetColor()
                if type(baseColor) == "function" then
                    return baseColor()
                end
                return baseColor or theme.Input
            end
            button.MouseEnter:Connect(function()
                if button.Parent and (not canHover or canHover()) then
                    TweenService:Create(button, TweenInfo.new(0.12), {
                        BackgroundColor3 = theme.TabBar
                    }):Play()
                end
            end)
            button.MouseLeave:Connect(function()
                if button.Parent then
                    TweenService:Create(button, TweenInfo.new(0.12), {
                        BackgroundColor3 = targetColor()
                    }):Play()
                end
            end)
        end

        local card = Instance.new("Frame")
        card.Name = "AnimationSwapperCard"
        card.Size = UDim2.new(1, 0, 0, 420)
        card.BackgroundColor3 = theme.Card
        card.BorderSizePixel = 0
        card.Parent = tab:GetContainer()

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -32, 0, 18)
        title.Position = UDim2.new(0, 16, 0, 8)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.RobotoMono
        title.Text = "ANIMATION SEARCH"
        title.TextColor3 = GetAccentColor()
        title.TextSize = 11
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = card
        if MyWindow and MyWindow.RegisterAccentListener then
            MyWindow:RegisterAccentListener(function(color)
                if title.Parent then
                    title.TextColor3 = color
                end
            end)
        end

        local desc = Instance.new("TextLabel")
        desc.Size = UDim2.new(1, -32, 0, 16)
        desc.Position = UDim2.new(0, 16, 0, 26)
        desc.BackgroundTransparency = 1
        desc.Font = Enum.Font.Roboto
        desc.Text = "Type to filter. Click a result to preview it on your current creature."
        desc.TextColor3 = theme.Muted
        desc.TextSize = 11
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.Parent = card

        local searchBox = Instance.new("TextBox")
        searchBox.Name = "AnimationSearchBox"
        searchBox.Size = UDim2.new(1, -32, 0, 30)
        searchBox.Position = UDim2.new(0, 16, 0, 48)
        searchBox.BackgroundColor3 = theme.Input
        searchBox.BorderSizePixel = 0
        searchBox.Font = Enum.Font.RobotoMono
        searchBox.Text = ""
        searchBox.PlaceholderText = "Search animation or creature..."
        searchBox.PlaceholderColor3 = theme.Muted
        searchBox.TextColor3 = theme.Text
        searchBox.TextSize = 12
        searchBox.ClearTextOnFocus = false
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        local searchStroke = Instance.new("UIStroke")
        searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        searchStroke.Color = theme.Border
        searchStroke.Thickness = 1
        searchStroke.Parent = searchBox
        local searchPadding = Instance.new("UIPadding")
        searchPadding.PaddingLeft = UDim.new(0, 10)
        searchPadding.PaddingRight = UDim.new(0, 10)
        searchPadding.Parent = searchBox
        searchBox.Parent = card

        local scopeButton = Instance.new("TextButton")
        scopeButton.Name = "AnimationScopeButton"
        scopeButton.Size = UDim2.new(0.5, -20, 0, 24)
        scopeButton.Position = UDim2.new(0, 16, 0, 86)
        scopeButton.BackgroundColor3 = theme.Input
        scopeButton.BorderSizePixel = 0
        scopeButton.Font = Enum.Font.RobotoMono
        scopeButton.Text = "SCOPE: CURRENT"
        scopeButton.TextColor3 = theme.Text
        scopeButton.TextSize = 11
        scopeButton.AutoButtonColor = false
        scopeButton.TextTruncate = Enum.TextTruncate.AtEnd
        scopeButton.Parent = card
        local scopeStroke = Instance.new("UIStroke")
        scopeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        scopeStroke.Color = theme.Border
        scopeStroke.Thickness = 1
        scopeStroke.Parent = scopeButton
        AddFeatureHover(scopeButton, theme.Input)

        local loopButton = Instance.new("TextButton")
        loopButton.Name = "AnimationLoopButton"
        loopButton.Size = UDim2.new(0.5, -20, 0, 24)
        loopButton.Position = UDim2.new(0.5, 4, 0, 86)
        loopButton.BackgroundColor3 = theme.Input
        loopButton.BorderSizePixel = 0
        loopButton.Font = Enum.Font.RobotoMono
        loopButton.Text = "LOOP PREVIEW: ON"
        loopButton.TextColor3 = theme.Text
        loopButton.TextSize = 11
        loopButton.AutoButtonColor = false
        loopButton.TextTruncate = Enum.TextTruncate.AtEnd
        loopButton.Parent = card
        local loopStroke = Instance.new("UIStroke")
        loopStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        loopStroke.Color = theme.Border
        loopStroke.Thickness = 1
        loopStroke.Parent = loopButton
        AddFeatureHover(loopButton, theme.Input)

        local categoryDropdown = Instance.new("TextButton")
        categoryDropdown.Name = "AnimationCategoryDropdown"
        categoryDropdown.Size = UDim2.new(1, -32, 0, 24)
        categoryDropdown.Position = UDim2.new(0, 16, 0, 116)
        categoryDropdown.BackgroundColor3 = theme.Input
        categoryDropdown.BorderSizePixel = 0
        categoryDropdown.Font = Enum.Font.RobotoMono
        categoryDropdown.Text = "TYPE: ALL"
        categoryDropdown.TextColor3 = theme.Text
        categoryDropdown.TextSize = 11
        categoryDropdown.AutoButtonColor = false
        categoryDropdown.TextTruncate = Enum.TextTruncate.AtEnd
        categoryDropdown.ZIndex = 22
        categoryDropdown.Parent = card
        local categoryDropdownStroke = Instance.new("UIStroke")
        categoryDropdownStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        categoryDropdownStroke.Color = theme.Border
        categoryDropdownStroke.Thickness = 1
        categoryDropdownStroke.Parent = categoryDropdown
        AddFeatureHover(categoryDropdown, theme.Input)

        local categoryMenu = Instance.new("ScrollingFrame")
        categoryMenu.Name = "AnimationCategoryMenu"
        categoryMenu.Size = UDim2.new(1, -32, 0, math.min(#ANIMATION_CATEGORIES * 26 + 10, 200))
        categoryMenu.Position = UDim2.new(0, 16, 0, 142)
        categoryMenu.BackgroundColor3 = theme.Card
        categoryMenu.BorderSizePixel = 0
        categoryMenu.Visible = false
        categoryMenu.ZIndex = 20
        categoryMenu.CanvasSize = UDim2.new(0, 0, 0, 0)
        categoryMenu.AutomaticCanvasSize = Enum.AutomaticSize.Y
        categoryMenu.ScrollBarThickness = 2
        categoryMenu.ScrollBarImageColor3 = theme.Border
        categoryMenu.Parent = card
        local categoryMenuStroke = Instance.new("UIStroke")
        categoryMenuStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        categoryMenuStroke.Color = theme.Border
        categoryMenuStroke.Thickness = 1
        categoryMenuStroke.Parent = categoryMenu
        local categoryMenuPadding = Instance.new("UIPadding")
        categoryMenuPadding.PaddingTop = UDim.new(0, 4)
        categoryMenuPadding.PaddingLeft = UDim.new(0, 4)
        categoryMenuPadding.PaddingRight = UDim.new(0, 4)
        categoryMenuPadding.PaddingBottom = UDim.new(0, 4)
        categoryMenuPadding.Parent = categoryMenu
        local categoryMenuLayout = Instance.new("UIListLayout")
        categoryMenuLayout.SortOrder = Enum.SortOrder.LayoutOrder
        categoryMenuLayout.Padding = UDim.new(0, 2)
        categoryMenuLayout.Parent = categoryMenu

        local UpdateCategoryDropdown
        local categoryButtons = {}
        for index, category in ipairs(ANIMATION_CATEGORIES) do
            local button = Instance.new("TextButton")
            button.Name = "AnimationCategory_" .. category
            button.Size = UDim2.new(1, -6, 0, 24)
            button.LayoutOrder = index
            button.BackgroundColor3 = theme.Input
            button.BorderSizePixel = 0
            button.Font = Enum.Font.RobotoMono
            button.Text = category
            button.TextColor3 = theme.Muted
            button.TextSize = 11
            button.AutoButtonColor = false
            button.TextTruncate = Enum.TextTruncate.AtEnd
            button.ZIndex = 21
            button.Parent = categoryMenu
            local stroke = Instance.new("UIStroke")
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Color = theme.Border
            stroke.Thickness = 1
            stroke.Parent = button
            AddFeatureHover(button, function()
                return (AnimationUI.Category == category) and theme.TabActive or theme.Input
            end, function()
                return AnimationUI.Category ~= category
            end)
            categoryButtons[category] = { Button = button, Stroke = stroke }
            button.Activated:Connect(function()
                AnimationUI.Category = category
                categoryMenu.Visible = false
                UpdateCategoryDropdown()
                RenderAnimationResults()
                SafeSetStatus("ANIM_FILTER_" .. category)
            end)
        end
        AnimationUI.CategoryButtons = categoryButtons

        categoryDropdown.Activated:Connect(function()
            categoryMenu.Visible = not categoryMenu.Visible
        end)

        UpdateCategoryDropdown = function()
            local accent = GetAccentColor()
            categoryDropdown.Text = "TYPE: " .. tostring(AnimationUI.Category)
            categoryDropdown.TextColor3 = theme.Text
            categoryDropdownStroke.Color = accent
            for category, entry in pairs(categoryButtons) do
                local active = AnimationUI.Category == category
                entry.Button.BackgroundColor3 = active and theme.TabActive or theme.Input
                entry.Button.TextColor3 = active and theme.Text or theme.Muted
                entry.Stroke.Color = active and accent or theme.Border
            end
        end
        UpdateCategoryDropdown()
        MyWindow:RegisterAccentListener(function()
            UpdateCategoryDropdown()
        end)

        local randomButton = Instance.new("TextButton")
        randomButton.Name = "AnimationRandomButton"
        randomButton.Size = UDim2.new(0.5, -20, 0, 24)
        randomButton.Position = UDim2.new(0, 16, 0, 144)
        randomButton.BackgroundColor3 = theme.Input
        randomButton.BorderSizePixel = 0
        randomButton.Font = Enum.Font.RobotoMono
        randomButton.Text = "RANDOM PREVIEW"
        randomButton.TextColor3 = theme.Text
        randomButton.TextSize = 11
        randomButton.AutoButtonColor = false
        randomButton.TextTruncate = Enum.TextTruncate.AtEnd
        randomButton.Parent = card
        local randomStroke = Instance.new("UIStroke")
        randomStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        randomStroke.Color = theme.Border
        randomStroke.Thickness = 1
        randomStroke.Parent = randomButton
        AddFeatureHover(randomButton, theme.Input)

        local nextButton = Instance.new("TextButton")
        nextButton.Name = "AnimationNextButton"
        nextButton.Size = UDim2.new(0.5, -20, 0, 24)
        nextButton.Position = UDim2.new(0.5, 4, 0, 144)
        nextButton.BackgroundColor3 = theme.Input
        nextButton.BorderSizePixel = 0
        nextButton.Font = Enum.Font.RobotoMono
        nextButton.Text = "NEXT PREVIEW"
        nextButton.TextColor3 = theme.Text
        nextButton.TextSize = 11
        nextButton.AutoButtonColor = false
        nextButton.TextTruncate = Enum.TextTruncate.AtEnd
        nextButton.Parent = card
        local nextStroke = Instance.new("UIStroke")
        nextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        nextStroke.Color = theme.Border
        nextStroke.Thickness = 1
        nextStroke.Parent = nextButton
        AddFeatureHover(nextButton, theme.Input)

        randomButton.Activated:Connect(PreviewRandomAnimation)
        nextButton.Activated:Connect(function()
            CycleAnimation(1)
        end)

        local countLabel = Instance.new("TextLabel")
        countLabel.Name = "AnimationMatchCount"
        countLabel.Size = UDim2.new(1, -42, 0, 14)
        countLabel.Position = UDim2.new(0, 26, 1, -18)
        countLabel.BackgroundTransparency = 1
        countLabel.Font = Enum.Font.RobotoMono
        countLabel.Text = "0 MATCHES"
        countLabel.TextColor3 = theme.Muted
        countLabel.TextSize = 10
        countLabel.TextXAlignment = Enum.TextXAlignment.Left
        countLabel.Parent = card

        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = "AnimationResults"
        scroll.Size = UDim2.new(1, -32, 0, 208)
        scroll.Position = UDim2.new(0, 16, 0, 176)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.ScrollBarThickness = 2
        scroll.ScrollBarImageColor3 = theme.Border
        scroll.Parent = card

        local listLayout = Instance.new("UIListLayout")
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Padding = UDim.new(0, 4)
        listLayout.Parent = scroll

        local listPadding = Instance.new("UIPadding")
        listPadding.PaddingBottom = UDim.new(0, 6)
        listPadding.Parent = scroll

        local order = 0
        local resultsAPI = {}
        function resultsAPI:Clear()
            for _, child in ipairs(scroll:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
            order = 0
        end
        function resultsAPI:AddLabel(text, color, labelHeight)
            order = order + 1
            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -8, 0, labelHeight or 24)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Roboto
            label.Text = tostring(text)
            label.TextColor3 = color or theme.Muted
            label.TextSize = 11
            label.TextWrapped = true
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Top
            label.LayoutOrder = order
            label.Parent = scroll
            local labelPadding = Instance.new("UIPadding")
            labelPadding.PaddingLeft = UDim.new(0, 10)
            labelPadding.PaddingRight = UDim.new(0, 8)
            labelPadding.Parent = label
            return label
        end
        function resultsAPI:AddButton(text, color, callback)
            order = order + 1
            local button = Instance.new("TextButton")
            button.Size = UDim2.new(1, -8, 0, 28)
            button.BackgroundColor3 = theme.Input
            button.AutoButtonColor = false
            button.Font = Enum.Font.RobotoMono
            button.Text = tostring(text)
            button.TextColor3 = color or theme.Text
            button.TextSize = 12
            button.TextXAlignment = Enum.TextXAlignment.Left
            button.TextTruncate = Enum.TextTruncate.AtEnd
            button.LayoutOrder = order
            button.Parent = scroll
            local buttonPadding = Instance.new("UIPadding")
            buttonPadding.PaddingLeft = UDim.new(0, 10)
            buttonPadding.PaddingRight = UDim.new(0, 8)
            buttonPadding.Parent = button
            local stroke = Instance.new("UIStroke")
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Color = color or theme.Border
            stroke.Transparency = 0.35
            stroke.Parent = button
            AddFeatureHover(button, theme.Input)
            button.Activated:Connect(function()
                if callback then
                    pcall(callback)
                end
            end)
            return button
        end

        AnimationUI.SearchBox = searchBox
        AnimationUI.Results = resultsAPI
        AnimationUI.CountLabel = countLabel
        AnimationUI.ScopeButton = scopeButton
        AnimationUI.LoopButton = loopButton
        AnimationUI.Refresh = RenderAnimationResults

        -- Result rows are rebuilt on every render, so they cannot hold their
        -- own accent listener. Re-render the list when the accent changes.
        if MyWindow and MyWindow.RegisterAccentListener then
            MyWindow:RegisterAccentListener(function()
                RenderAnimationResults()
            end)
        end

        local function UpdateLoopButton()
            loopButton.Text = "LOOP PREVIEW: " .. (Toggles.AnimationLoop and "ON" or "OFF")
        end

        scopeButton.Activated:Connect(function()
            Toggles.AnimationSearchAll = not Toggles.AnimationSearchAll
            SaveScriptConfig()
            RenderAnimationResults()
            SafeSetStatus(Toggles.AnimationSearchAll and "ANIM_SCOPE_ALL" or "ANIM_SCOPE_CURRENT")
        end)

        loopButton.Activated:Connect(function()
            Toggles.AnimationLoop = not Toggles.AnimationLoop
            SaveScriptConfig()
            UpdateLoopButton()
            SafeSetStatus(Toggles.AnimationLoop and "ANIM_LOOP_ON" or "ANIM_LOOP_OFF")
        end)

        UpdateLoopButton()

        local searchToken = 0
        TrackConnection(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            searchToken = searchToken + 1
            local token = searchToken
            task.delay(0.12, function()
                if token == searchToken and searchBox.Parent then
                    RenderAnimationResults()
                end
            end)
        end))

        TrackConnection(searchBox.FocusLost:Connect(function()
            RenderAnimationResults()
        end))

        RenderAnimationResults()
        UpdateAnimationStatus(true)

        tab:CreateButton(
            "RESTORE_ORIGINAL_ANIMATIONS",
            "Stop the preview or pack replacement and return the current creature to its own animation set.",
            function()
                RestoreOriginalAnimations()
                SafeSetStatus("ANIMATION_RESTORED")
            end
        )

        tab:CreateSectionLabel("CREATURE ANIMATION PACK")
        local packCard = Instance.new("Frame")
        packCard.Name = "AnimationPackCard"
        packCard.Size = UDim2.new(1, 0, 0, 346)
        packCard.BackgroundColor3 = theme.Card
        packCard.BorderSizePixel = 0
        packCard.Parent = tab:GetContainer()

        local packTitle = Instance.new("TextLabel")
        packTitle.Name = "AnimationPackTitle"
        packTitle.Size = UDim2.new(1, -32, 0, 18)
        packTitle.Position = UDim2.new(0, 16, 0, 8)
        packTitle.BackgroundTransparency = 1
        packTitle.Font = Enum.Font.RobotoMono
        packTitle.Text = "REPLACE FULL ANIMATION PACK"
        packTitle.TextColor3 = GetAccentColor()
        packTitle.TextSize = 11
        packTitle.TextTruncate = Enum.TextTruncate.AtEnd
        packTitle.TextXAlignment = Enum.TextXAlignment.Left
        packTitle.Parent = packCard

        local packDesc = Instance.new("TextLabel")
        packDesc.Size = UDim2.new(1, -32, 0, 40)
        packDesc.Position = UDim2.new(0, 16, 0, 28)
        packDesc.BackgroundTransparency = 1
        packDesc.Font = Enum.Font.Roboto
        packDesc.Text = "Choose a creature from the animation library. Its entire set replaces your Idle, Walk, Run, Swim, and action animations until RESET."
        packDesc.TextColor3 = theme.Muted
        packDesc.TextSize = 11
        packDesc.TextWrapped = true
        packDesc.TextXAlignment = Enum.TextXAlignment.Left
        packDesc.TextYAlignment = Enum.TextYAlignment.Top
        packDesc.Parent = packCard

        local packSelected = Instance.new("TextLabel")
        packSelected.Name = "AnimationPackSelected"
        packSelected.Size = UDim2.new(1, -32, 0, 16)
        packSelected.Position = UDim2.new(0, 16, 0, 70)
        packSelected.BackgroundTransparency = 1
        packSelected.Font = Enum.Font.RobotoMono
        packSelected.Text = "PACK: NONE SELECTED"
        packSelected.TextColor3 = theme.Text
        packSelected.TextSize = 11
        packSelected.TextTruncate = Enum.TextTruncate.AtEnd
        packSelected.TextXAlignment = Enum.TextXAlignment.Left
        packSelected.Parent = packCard

        local packSearch = Instance.new("TextBox")
        packSearch.Name = "AnimationPackSearch"
        packSearch.Size = UDim2.new(1, -32, 0, 28)
        packSearch.Position = UDim2.new(0, 16, 0, 90)
        packSearch.BackgroundColor3 = theme.Input
        packSearch.BorderSizePixel = 0
        packSearch.Font = Enum.Font.RobotoMono
        packSearch.Text = ""
        packSearch.PlaceholderText = "Search creature pack..."
        packSearch.PlaceholderColor3 = theme.Muted
        packSearch.TextColor3 = theme.Text
        packSearch.TextSize = 12
        packSearch.ClearTextOnFocus = false
        packSearch.TextXAlignment = Enum.TextXAlignment.Left
        local packSearchStroke = Instance.new("UIStroke")
        packSearchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        packSearchStroke.Color = theme.Border
        packSearchStroke.Thickness = 1
        packSearchStroke.Parent = packSearch
        local packSearchPadding = Instance.new("UIPadding")
        packSearchPadding.PaddingLeft = UDim.new(0, 8)
        packSearchPadding.PaddingRight = UDim.new(0, 8)
        packSearchPadding.Parent = packSearch
        packSearch.Parent = packCard

        local packCountLabel = Instance.new("TextLabel")
        packCountLabel.Name = "AnimationPackCount"
        packCountLabel.Size = UDim2.new(1, -32, 0, 12)
        packCountLabel.Position = UDim2.new(0, 16, 0, 122)
        packCountLabel.BackgroundTransparency = 1
        packCountLabel.Font = Enum.Font.RobotoMono
        packCountLabel.Text = "0 PACKS"
        packCountLabel.TextColor3 = theme.Muted
        packCountLabel.TextSize = 9
        packCountLabel.TextXAlignment = Enum.TextXAlignment.Left
        packCountLabel.Parent = packCard

        local packList = Instance.new("ScrollingFrame")
        packList.Name = "AnimationPackList"
        packList.Size = UDim2.new(1, -32, 0, 104)
        packList.Position = UDim2.new(0, 16, 0, 138)
        packList.BackgroundColor3 = theme.Input
        packList.BackgroundTransparency = 0.35
        packList.BorderSizePixel = 0
        packList.CanvasSize = UDim2.new(0, 0, 0, 0)
        packList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        packList.ScrollBarThickness = 2
        packList.ScrollBarImageColor3 = theme.Border
        packList.Parent = packCard
        local packListLayout = Instance.new("UIListLayout")
        packListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        packListLayout.Padding = UDim.new(0, 3)
        packListLayout.Parent = packList
        local packListPadding = Instance.new("UIPadding")
        packListPadding.PaddingTop = UDim.new(0, 3)
        packListPadding.PaddingLeft = UDim.new(0, 3)
        packListPadding.PaddingRight = UDim.new(0, 3)
        packListPadding.PaddingBottom = UDim.new(0, 3)
        packListPadding.Parent = packList

        local function CreatePackButton(name, text, position, size)
            local button = Instance.new("TextButton")
            button.Name = name
            button.Size = size
            button.Position = position
            button.BackgroundColor3 = theme.Input
            button.BorderSizePixel = 0
            button.Font = Enum.Font.RobotoMono
            button.Text = text
            button.TextColor3 = theme.Text
            button.TextSize = 12
            button.AutoButtonColor = false
            button.TextTruncate = Enum.TextTruncate.AtEnd
            button.TextXAlignment = Enum.TextXAlignment.Center
            button.Parent = packCard
            local stroke = Instance.new("UIStroke")
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Color = theme.Border
            stroke.Thickness = 1
            stroke.Parent = button
            AddFeatureHover(button, theme.Input)
            return button, stroke
        end

        local packApply, packApplyStroke = CreatePackButton(
            "AnimationPackApply",
            "APPLY PACK",
            UDim2.new(0, 16, 0, 250),
            UDim2.new(0.58, -18, 0, 26)
        )
        local packReset, packResetStroke = CreatePackButton(
            "AnimationPackReset",
            "RESET",
            UDim2.new(0.58, -2, 0, 250),
            UDim2.new(0.42, -14, 0, 26)
        )
        packApply.TextColor3 = GetAccentColor()
        packApplyStroke.Color = GetAccentColor()
        packReset.TextColor3 = GetAccentColor()
        packResetStroke.Color = GetAccentColor()

        local packStatus = Instance.new("TextLabel")
        packStatus.Name = "AnimationPackStatus"
        packStatus.Size = UDim2.new(1, -32, 0, 52)
        packStatus.Position = UDim2.new(0, 16, 0, 286)
        packStatus.BackgroundTransparency = 1
        packStatus.Font = Enum.Font.RobotoMono
        packStatus.Text = "PLAYING: —"
        packStatus.TextColor3 = theme.Muted
        packStatus.TextSize = 11
        packStatus.TextWrapped = true
        packStatus.TextXAlignment = Enum.TextXAlignment.Left
        packStatus.TextYAlignment = Enum.TextYAlignment.Top
        packStatus.Parent = packCard

        local packOrder = 0
        local function RefreshPackList()
            for _, child in ipairs(packList:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
            packOrder = 0

            local query = string.lower(tostring(packSearch.Text or ""))
            local matches = {}
            for _, species in ipairs(ANIMATION_PACK_SPECIES) do
                if query == "" or string.find(string.lower(species), query, 1, true) then
                    matches[#matches + 1] = species
                    if #matches >= 60 then
                        break
                    end
                end
            end

            local total = #ANIMATION_PACK_SPECIES
            if #matches >= 60 then
                packCountLabel.Text = "SHOWING 60 / " .. tostring(total) .. " PACKS — TYPE TO NARROW"
            elseif query == "" then
                packCountLabel.Text = "SHOWING " .. tostring(math.min(total, 60)) .. " / " .. tostring(total) .. " PACKS — SEARCH TO FIND ONE"
            else
                packCountLabel.Text = tostring(#matches) .. " MATCH" .. (#matches == 1 and "" or "ES")
            end

            if #matches == 0 then
                local empty = Instance.new("TextLabel")
                empty.Size = UDim2.new(1, -6, 0, 24)
                empty.BackgroundTransparency = 1
                empty.Font = Enum.Font.RobotoMono
                empty.Text = "NO CREATURE PACKS MATCH"
                empty.TextColor3 = theme.Muted
                empty.TextSize = 11
                empty.TextXAlignment = Enum.TextXAlignment.Left
                empty.Parent = packList
                local emptyPadding = Instance.new("UIPadding")
                emptyPadding.PaddingLeft = UDim.new(0, 6)
                emptyPadding.Parent = empty
                return
            end

            local accent = GetAccentColor()
            for _, species in ipairs(matches) do
                packOrder = packOrder + 1
                local selected = ANIMATION_SWAP.TargetSpecies == species
                local button = Instance.new("TextButton")
                button.Name = "AnimationPack_" .. species
                button.Size = UDim2.new(1, -6, 0, 24)
                button.LayoutOrder = packOrder
                button.BackgroundColor3 = selected and theme.TabActive or theme.Input
                button.BorderSizePixel = 0
                button.Font = Enum.Font.RobotoMono
                button.Text = species .. "  ·  " .. tostring(ANIMATION_SPECIES_COUNTS[species] or 0) .. " tracks"
                button.TextColor3 = selected and theme.Text or theme.Muted
                button.TextSize = 11
                button.AutoButtonColor = false
                button.TextTruncate = Enum.TextTruncate.AtEnd
                button.TextXAlignment = Enum.TextXAlignment.Left
                button.Parent = packList
                local padding = Instance.new("UIPadding")
                padding.PaddingLeft = UDim.new(0, 7)
                padding.PaddingRight = UDim.new(0, 6)
                padding.Parent = button
                local stroke = Instance.new("UIStroke")
                stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                stroke.Color = selected and accent or theme.Border
                stroke.Thickness = 1
                stroke.Parent = button
                if not selected then
                    AddFeatureHover(button, theme.Input)
                end
                button.Activated:Connect(function()
                    ANIMATION_SWAP.SelectTarget(species)
                end)
            end
        end
        ANIMATION_SWAP.RefreshList = RefreshPackList

        local packSearchToken = 0
        TrackConnection(packSearch:GetPropertyChangedSignal("Text"):Connect(function()
            packSearchToken = packSearchToken + 1
            local token = packSearchToken
            task.delay(0.1, function()
                if token == packSearchToken and packSearch.Parent then
                    RefreshPackList()
                end
            end)
        end))
        TrackConnection(packSearch.FocusLost:Connect(function()
            RefreshPackList()
        end))

        ANIMATION_SWAP.UI.SelectedLabel = packSelected
        ANIMATION_SWAP.UI.StatusLabel = packStatus
        ANIMATION_SWAP.UI.ApplyButton = packApply
        ANIMATION_SWAP.UI.ResetButton = packReset
        ANIMATION_SWAP.UI.SearchBox = packSearch
        ANIMATION_SWAP.UI.List = packList

        ANIMATION_SWAP.UpdateTargetUI()
        ANIMATION_SWAP.UpdateStatus(true)

        packApply.Activated:Connect(function()
            if not ANIMATION_SWAP.Start() then
                ANIMATION_SWAP.UpdateStatus(true)
            end
        end)
        packReset.Activated:Connect(function()
            ANIMATION_SWAP.Stop(false)
            SafeSetStatus("ANIMATION_RESTORED")
        end)

        if MyWindow and MyWindow.RegisterAccentListener then
            MyWindow:RegisterAccentListener(function(color)
                packTitle.TextColor3 = color
                packApply.TextColor3 = color
                packApplyStroke.Color = color
                packReset.TextColor3 = color
                packResetStroke.Color = color
                RefreshPackList()
            end)
        end

        tab:CreateSectionLabel("RAGDOLL CONTROLS")
        tab:CreateKeybindButton(
            "RAGDOLL",
            "Switch the creature to its idle pose and let gravity tumble the unanchored body with real physics. Movement control stays disabled until UNRAGDOLL. The keybind is optional; clear it with X or click the action button.",
            {
                Key = KeybindToEnum(Keybinds.Ragdoll),
                Required = false,
                ActionText = "RAGDOLL",
                OnActivated = function()
                    StartRagdoll()
                end,
                OnKeyChanged = function(key)
                    Keybinds.Ragdoll = KeyToName(key)
                    SaveScriptConfig()
                end
            }
        )
        tab:CreateKeybindButton(
            "UNRAGDOLL",
            "Stand the creature back up, restore its animations and collisions, and return control to COS.",
            {
                Key = KeybindToEnum(Keybinds.Unragdoll),
                Required = false,
                ActionText = "RESTORE",
                OnActivated = function()
                    StopRagdoll(false)
                end,
                OnKeyChanged = function(key)
                    Keybinds.Unragdoll = KeyToName(key)
                    SaveScriptConfig()
                end
            }
        )

        tab:CreateButton(
            "REFRESH_ANIMATION_CATALOG",
            "Rescan every creature's animation folder. Use this after a game update.",
            function()
                BuildAnimationCatalog()
                RenderAnimationResults()
                UpdateAnimationStatus(true)
                SafeSetStatus("ANIMATIONS_REFRESHED")
            end
        )

        tab:CreateReadMeCard(
            "ANIMATION NOTE",
            "Current-creature animations use COS's own fake-state preview. Foreign animations are loaded onto your current rig and may look distorted. Reset restores the original animation set; preview also clears on respawn or script unload.",
            100
        )
    end)

    -- CONFIG ---------------------------------------------------------------
    BuildTab("CONFIG", "INTERFACE & STORAGE", function(tab)
        if not UserInputService.TouchEnabled then
            tab:CreateKeybindButton(
                "OPEN / CLOSE MENU",
                "Mandatory window keybind. Click the key chip to rebind. This binding cannot be cleared.",
                {
                    Key = MyWindow.CurrentHideKey,
                    Required = true,
                    TriggerOnKey = false,
                    ShowAction = false,
                    OnKeyChanged = function(key)
                        if key then
                            MyWindow.CurrentHideKey = key
                            MyWindow:SaveSettings()
                        end
                    end
                }
            )
        end
        tab:CreateKillButton("KILL SCRIPT & CLEANUP", function()
            MyWindow:Unload()
        end)

        tab:CreateColorPicker(
            "ACCENT_COLOR",
            "Change the shared APEX system color",
            MyWindow.AccentColor,
            function(color)
                MyWindow:SetAccentColor(color)
            end
        )

        if UserInputService.TouchEnabled then
            tab:CreateToggle(
                "LOCK_BUTTON_POSITION",
                "Lock the mobile APEX claw button position",
                MyWindow.IsButtonLocked,
                function(state)
                    MyWindow.IsButtonLocked = state
                    MyWindow:SaveSettings()
                end
            )
        end

        tab:CreateInfoCard("LIBRARY_VERSION", ApexLibrary.Version or "APEX_SYS")
        tab:CreateInfoCard("SCRIPT_VERSION", SCRIPT_VERSION)
        tab:CreateInfoCard("AUTHOR", AUTHOR)
        tab:CreateReadMeCard(
            "CONFIG STORAGE",
            "APEX accent, hide key, mobile lock, and button position use the shared ApexLibrary_Config.json. Cos toggles, speeds, ESP colors, and tuning use Cos_Apex_Config.json.",
            88
        )
    end)

    local selected = pcall(function()
        MyWindow:SelectTab("MAIN", true)
    end)
    if not selected then
        pcall(function()
            MyWindow:SelectTab("MAIN")
        end)
    end

    MyWindow:RegisterUnloadCallback(function()
        CleanupSession()
    end)

    SafeSetStatus("READY")
end

-- // Bootstrap
BuildUI()
SyncInstantMenu()

if Toggles.MinimapESP then
    ApplyMinimapNow()
end

TryRemoveOutOfBoundsDamage()
if not OOBRemoved then
    task.spawn(function()
        for _ = 1, 20 do
            if not SessionActive() or OOBRemoved then
                break
            end
            task.wait(0.5)
            TryRemoveOutOfBoundsDamage()
            if OOBRemoved then
                UpdateStatusCards(true)
                break
            end
        end
    end)
end

StartPulseLoop()

for _, player in ipairs(Players:GetPlayers()) do
    if CheckPlayerForStaff(player) then
        break
    end
end

UpdateStatusCards(true)
print("[Cos Apex] " .. SCRIPT_VERSION .. " loaded for " .. PlayerName)
