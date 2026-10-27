--[================================================================[
    DANDYS WORLD // APEX UI MIGRATION
    ---------------------------------------------------------------
    Original gameplay logic: Drk_Duck
    UI framework: APEX_SYS (ApexLibraryPlus.lua)
    ---------------------------------------------------------------
    The old ScreenGui, side list, spy panel, switches and checkboxes
    are gone. Every original function is preserved and wired into the
    new tabbed Apex interface.

    Run order:
        Run this script. It downloads ApexLibraryPlus.lua from GitHub
        and loads it automatically. Local copies are only a fallback.

    Library URL:
        https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua
]================================================================]--

-- // Apex Library Loader
local LIBRARY_URL = "https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua"

local function IsPlusLibrary(library)
    return type(library) == "table"
        and library.Version ~= nil
        and type(library.new) == "function"
        and type(library.RegisterUnloadCallback) == "function"
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

-- Prefer the latest published library.
local githubLibrary, githubErr = LoadLibraryFromGitHub()
if githubLibrary then
    ApexLibrary = githubLibrary
else
    loadErrors[#loadErrors + 1] = "GitHub: " .. tostring(githubErr)
end

-- Reuse an already-loaded copy if the network is unavailable.
if not ApexLibrary then
    ApexLibrary = GetReusableLibrary()
end

-- Last resort: local executor files.
if not ApexLibrary then
    local localLibrary, localErr = LoadLibraryFromLocalFiles()
    if localLibrary then
        ApexLibrary = localLibrary
    else
        loadErrors[#loadErrors + 1] = "Local: " .. tostring(localErr)
    end
end

if not ApexLibrary then
    error("[Dandys World] Could not load ApexLibraryPlus.lua.\n"
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
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local VIM = game:GetService("VirtualInputManager")
local VU = game:GetService("VirtualUser")

-- // Variables
local LocalPlayer = Players.LocalPlayer
local PlayerName = LocalPlayer.Name
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- // Session guard (prevents duplicate loops when the script is re-executed)
local SESSION = {}
local ScriptRunning = true
local sessionRegistered = false
if getgenv then
    sessionRegistered = pcall(function()
        getgenv().DandysApexSession = SESSION
    end)
end

local function SessionActive()
    if not ScriptRunning then
        return false
    end
    if sessionRegistered and getgenv then
        local ok, active = pcall(function()
            return getgenv().DandysApexSession == SESSION
        end)
        if ok then
            return active
        end
    end
    return true
end

-- // Remove old UI / ESP storage from the previous version
local function DestroyIfPresent(parent, name)
    if not parent then
        return
    end
    pcall(function()
        local object = parent:FindFirstChild(name)
        if object then
            object:Destroy()
        end
    end)
end

DestroyIfPresent(CoreGui, "DandysWorld_V27_Spy")
DestroyIfPresent(PlayerGui, "DandysWorld_V27_Spy")
DestroyIfPresent(CoreGui, "DandysWorld_ESP_Storage")
DestroyIfPresent(PlayerGui, "DandysWorld_ESP_Storage")

-- // ESP Folder (CoreGui preferred, PlayerGui fallback)
local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "DandysWorld_ESP_Storage"
local coreGuiOk = pcall(function()
    ESPFolder.Parent = CoreGui
end)
if not coreGuiOk or not ESPFolder.Parent then
    ESPFolder.Parent = PlayerGui
end

-- // Lighting Defaults (For Full Bright Reset)
local DefaultLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ColorShift_Bottom = Lighting.ColorShift_Bottom,
    ColorShift_Top = Lighting.ColorShift_Top
}

-- // Feature State
local Toggles = {
    PlayerESP = false,
    GenESP = false,
    MonsterESP = false,
    HazardESP = false,
    CapsuleESP = false,
    HealthESP = false,
    AllItemsESP = false,
    FullBright = false,
    InfStamina = false,
    AutoChat = false,
    ShowList = true,
    ShowSpy = true,
    TrackMonsters = false,
    TrackGens = false,
    TrackCapsules = false,
    TrackHealth = false,
    TrackAllItems = false,
    AutoSkill = false,
    Autofarm = false,
    AutoVote = false,
    AntiAFK = false
}

-- // Editable ESP Colors
local ESPColors = {
    PlayerESP = Color3.fromRGB(0, 120, 255),
    MonsterESP = Color3.fromRGB(255, 50, 50),
    HazardESP = Color3.fromRGB(255, 80, 0),
    GenESP = Color3.fromRGB(0, 255, 180),
    CapsuleESP = Color3.fromRGB(255, 200, 0),
    HealthESP = Color3.fromRGB(0, 255, 100),
    AllItemsESP = Color3.fromRGB(255, 255, 255)
}

local ESPSettings = {
    FillTransparency = 0.70
}

-- // Config System
local ConfigFile = "DandysWorld_Apex_Config.json"
local LegacyConfigFile = "DandysHelper_Config.json"

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
    local data = nil
    if isfile and readfile then
        if isfile(ConfigFile) then
            data = DecodeConfigFile(ConfigFile)
        end
        if not data and isfile(LegacyConfigFile) then
            local legacy = DecodeConfigFile(LegacyConfigFile)
            if legacy then
                -- Old configs stored the toggles at the top level.
                data = { Toggles = legacy }
            end
        end
    end

    if type(data) ~= "table" then
        Toggles.Autofarm = false
        return
    end

    if type(data.Toggles) == "table" then
        for key, value in pairs(data.Toggles) do
            if Toggles[key] ~= nil and type(value) == "boolean" then
                Toggles[key] = value
            end
        end
    end

    if type(data.Colors) == "table" then
        for key, fallback in pairs(ESPColors) do
            if data.Colors[key] then
                ESPColors[key] = TableToColor(data.Colors[key], fallback)
            end
        end
    end

    if type(data.ESP) == "table" and data.ESP.FillTransparency ~= nil then
        ESPSettings.FillTransparency = math.clamp(tonumber(data.ESP.FillTransparency) or 0.70, 0, 1)
    end

    -- Autofarm is intentionally not restored between sessions.
    Toggles.Autofarm = false
end

local function SaveScriptConfig()
    pcall(function()
        if not writefile then
            return
        end
        local data = {
            Toggles = {},
            Colors = {},
            ESP = {
                FillTransparency = ESPSettings.FillTransparency
            }
        }
        for key, value in pairs(Toggles) do
            if key ~= "Autofarm" and type(value) == "boolean" then
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

-- // Core Helpers
local function KillVelocity()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
end

local function UpdateLighting()
    if Toggles.FullBright then
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.ColorShift_Bottom = Color3.new(1, 1, 1)
        Lighting.ColorShift_Top = Color3.new(1, 1, 1)
    else
        Lighting.Ambient = DefaultLighting.Ambient
        Lighting.OutdoorAmbient = DefaultLighting.OutdoorAmbient
        Lighting.ColorShift_Bottom = DefaultLighting.ColorShift_Bottom
        Lighting.ColorShift_Top = DefaultLighting.ColorShift_Top
    end
end

local function CollectNamed(root, name)
    local results = {}
    if not root then
        return results
    end
    local seen = {}
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == name and not seen[descendant] then
            seen[descendant] = true
            results[#results + 1] = descendant
        end
    end
    return results
end

local function StopInteraction()
    local character = LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end

    local room = workspace:FindFirstChild("CurrentRoom")
    if not room then
        return
    end

    local closestGen = nil
    local shortestDistance = math.huge

    for _, generators in ipairs(CollectNamed(room, "Generators")) do
        for _, gen in pairs(generators:GetChildren()) do
            local stats = gen:FindFirstChild("Stats")
            local primary = gen.PrimaryPart or (stats and stats.Parent and stats.Parent.PrimaryPart)
            if stats and primary then
                local distance = (rootPart.Position - primary.Position).Magnitude
                if distance < shortestDistance then
                    shortestDistance = distance
                    closestGen = gen
                end
            end
        end
    end

    if closestGen then
        local stats = closestGen:FindFirstChild("Stats")
        local stopRemote = stats and stats:FindFirstChild("StopInteracting")
        if stopRemote then
            pcall(function()
                stopRemote:FireServer("Stop")
            end)
        end
    end
end

local function getRoomFolder(name)
    local room = workspace:FindFirstChild("CurrentRoom")
    if not room then
        return nil
    end
    local direct = room:FindFirstChild(name)
    if direct then
        return direct
    end
    for _, child in pairs(room:GetChildren()) do
        local found = child:FindFirstChild(name, true)
        if found then
            return found
        end
    end
    return nil
end

local function isAreaSafe(targetPosition)
    local monsters = getRoomFolder("Monsters")
    local room = workspace:FindFirstChild("CurrentRoom")

    if monsters then
        for _, monster in pairs(monsters:GetChildren()) do
            if monster.Name ~= "RazzleDazzleMonster"
                and monster.Name ~= "RodgerMonster"
                and monster.Name ~= "BlottMonster"
                and monster.Name ~= "SquirmMonster"
            then
                local part = monster.PrimaryPart or monster:FindFirstChildWhichIsA("BasePart")
                if part and (part.Position - targetPosition).Magnitude < 70 then
                    return false
                end
            end
        end
    end

    if room then
        for _, descendant in pairs(room:GetDescendants()) do
            if (descendant.Name == "SproutTendril" or string.find(descendant.Name, "BlotHandZone", 1, true))
                and descendant:IsA("BasePart")
            then
                if (descendant.Position - targetPosition).Magnitude < 40 then
                    return false
                end
            end
        end
    end

    return true
end

local function TeleportTo(object)
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not object or not object.Parent then
        return
    end

    local target = object:FindFirstChild("ScrapsAttachPoint", true)
    if not target and object:IsA("Model") then
        target = object.PrimaryPart
    end
    if not target then
        target = object
    end

    local targetCFrame = nil
    if target:IsA("Attachment") then
        targetCFrame = target.WorldCFrame
    elseif target:IsA("BasePart") then
        targetCFrame = target.CFrame
    elseif target:IsA("Model") then
        targetCFrame = target:GetPivot()
    end

    if not targetCFrame then
        return
    end

    root.CFrame = targetCFrame + Vector3.new(0, 3, 0)
    task.wait(0.05)
    KillVelocity()
end

local function TeleportToElevator()
    local elevators = workspace:FindFirstChild("Elevators")
    local elevator = elevators and elevators:FindFirstChild("Elevator")
    if not elevator then
        return
    end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end

    local targetCFrame = nil
    if elevator:IsA("Model") then
        targetCFrame = elevator:GetPivot()
    elseif elevator:IsA("BasePart") then
        targetCFrame = elevator.CFrame
    end
    if not targetCFrame then
        return
    end

    root.CFrame = targetCFrame * CFrame.new(0, 3.5, 0)
    KillVelocity()
end

local function TeleportToPlayer(targetName)
    local inGamePlayers = workspace:FindFirstChild("InGamePlayers")
    local folder = inGamePlayers and inGamePlayers:FindFirstChild(targetName)
    if not folder then
        return
    end

    local target = folder:FindFirstChild("HumanoidRootPart", true)
    if not target and folder:IsA("Model") then
        target = folder.PrimaryPart
    end
    if not target then
        target = folder:FindFirstChildWhichIsA("BasePart", true)
    end
    if not target then
        return
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end

    root.CFrame = target.CFrame + Vector3.new(0, 3, 0)
    KillVelocity()
end

local function SendMonsterChat()
    local monsterList = {}
    local seenMonsters = {}
    local room = workspace:FindFirstChild("CurrentRoom")
    if room then
        for _, monsters in ipairs(CollectNamed(room, "Monsters")) do
            for _, monster in pairs(monsters:GetChildren()) do
                if not seenMonsters[monster.Name] then
                    seenMonsters[monster.Name] = true
                    table.insert(monsterList, monster.Name)
                end
            end
        end
    end

    if #monsterList == 0 then
        return
    end

    local message = "Monsters: " .. table.concat(monsterList, ", ")
    local ok = pcall(function()
        if TextChatService.TextChannels:FindFirstChild("RBXGeneral") then
            TextChatService.TextChannels.RBXGeneral:SendAsync(message)
        else
            local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
            local request = events and events:FindFirstChild("SayMessageRequest")
            if request then
                request:FireServer(message, "All")
            end
        end
    end)

    if not ok then
        warn("[Dandys World] Monster chat failed.")
    end
end

-- // ESP Engine
local activeESP = {}
local espTick = 0

local function SetESP(object, color, enabled)
    if not object or not object.Parent then
        return
    end
    if not (object:IsA("Model") or object:IsA("BasePart")) then
        return
    end

    local record = activeESP[object]
    if record and (not record.Highlight or not record.Highlight.Parent) then
        if record.Highlight then
            record.Highlight:Destroy()
        end
        activeESP[object] = nil
        record = nil
    end

    if enabled then
        if not record then
            local highlight = Instance.new("Highlight")
            highlight.Name = "ApexESP"
            highlight.Adornee = object
            highlight.FillTransparency = ESPSettings.FillTransparency
            highlight.OutlineTransparency = 0
            pcall(function()
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            end)
            highlight.Parent = ESPFolder
            record = {
                Highlight = highlight,
                Seen = espTick
            }
            activeESP[object] = record
        end
        record.Highlight.FillColor = color or Color3.fromRGB(255, 255, 255)
        record.Highlight.OutlineColor = color or Color3.fromRGB(255, 255, 255)
        record.Highlight.FillTransparency = ESPSettings.FillTransparency
        record.Seen = espTick
    elseif record then
        record.Highlight:Destroy()
        activeESP[object] = nil
    end
end

local function SweepESP()
    for object, record in pairs(activeESP) do
        if record.Seen ~= espTick or not object.Parent then
            record.Highlight:Destroy()
            activeESP[object] = nil
        end
    end
end

local function ClearAllESP()
    for object, record in pairs(activeESP) do
        record.Highlight:Destroy()
        activeESP[object] = nil
    end
end

-- // Dynamic UI list references (assigned during tab construction)
local TeleportList = nil
local SpyList = nil
local lastTeleportEntries = {}
local lastTeleportSignature = nil
local lastSpySignature = nil

local function UpdateTeleportList(entries)
    lastTeleportEntries = entries or lastTeleportEntries
    if not TeleportList then
        return
    end

    if not Toggles.ShowList then
        if lastTeleportSignature ~= "disabled" then
            lastTeleportSignature = "disabled"
            TeleportList:Clear()
            TeleportList:AddLabel(
                "Live teleport list disabled. Enable SHOW LIVE LIST in the tracking filters above.",
                Color3.fromRGB(150, 150, 165),
                34
            )
        end
        return
    end

    local signatureParts = {}
    for _, entry in ipairs(entries) do
        local id = "nil"
        if entry.Obj then
            local ok, debugId = pcall(function()
                return entry.Obj:GetDebugId()
            end)
            if ok and debugId then
                id = tostring(debugId)
            end
        end
        local colorKey = "none"
        if entry.Color then
            colorKey = string.format("%.3f,%.3f,%.3f", entry.Color.R, entry.Color.G, entry.Color.B)
        end
        signatureParts[#signatureParts + 1] = tostring(entry.Name)
            .. ":" .. id
            .. ":" .. tostring(entry.CanTP)
            .. ":" .. colorKey
    end

    local signature = table.concat(signatureParts, "|")
    if signature == lastTeleportSignature then
        return
    end
    lastTeleportSignature = signature

    TeleportList:Clear()
    if #entries == 0 then
        TeleportList:AddLabel("No tracked objects in this room.", Color3.fromRGB(150, 150, 165), 24)
        return
    end

    for _, entry in ipairs(entries) do
        if entry.CanTP then
            TeleportList:AddButton(entry.Name, entry.Color, function()
                if entry.Obj and entry.Obj.Parent then
                    pcall(TeleportTo, entry.Obj)
                end
            end)
        else
            TeleportList:AddLabel(entry.Name, entry.Color, 18)
        end
    end
end

local function UpdateWorldESP()
    if not SessionActive() then
        return
    end

    espTick = espTick + 1
    local room = workspace:FindFirstChild("CurrentRoom")
    local entries = {}
    local addedEntries = {}
    local function addEntry(entry)
        if entry.Obj and addedEntries[entry.Obj] then
            return
        end
        if entry.Obj then
            addedEntries[entry.Obj] = true
        end
        entries[#entries + 1] = entry
    end

    -- Player ESP
    if Toggles.PlayerESP then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                SetESP(player.Character, ESPColors.PlayerESP, true)
            end
        end
    end

    if room then
        -- Monsters
        for _, monsters in ipairs(CollectNamed(room, "Monsters")) do
            for _, monster in pairs(monsters:GetChildren()) do
                if monster:IsA("Model") or monster:IsA("BasePart") then
                    SetESP(monster, ESPColors.MonsterESP, Toggles.MonsterESP)
                    if Toggles.TrackMonsters then
                        addEntry({
                            Name = "[M] " .. monster.Name,
                            Obj = monster,
                            Color = ESPColors.MonsterESP,
                            Order = 1,
                            CanTP = false
                        })
                    end
                end
            end
        end

        -- Generators
        for _, generators in ipairs(CollectNamed(room, "Generators")) do
            for _, generator in pairs(generators:GetChildren()) do
                if generator:IsA("Model") or generator:IsA("BasePart") then
                    local stats = generator:FindFirstChild("Stats", true)
                    local completed = stats and stats:FindFirstChild("Completed")
                    local isDone = completed and completed.Value == true
                    SetESP(generator, ESPColors.GenESP, Toggles.GenESP and not isDone)
                    if Toggles.TrackGens then
                        addEntry({
                            Name = "[GEN] " .. generator.Name .. (isDone and " (DONE)" or ""),
                            Obj = generator,
                            Color = ESPColors.GenESP,
                            Order = 2,
                            CanTP = true
                        })
                    end
                end
            end
        end

        -- Items
        for _, items in ipairs(CollectNamed(room, "Items")) do
            for _, item in pairs(items:GetChildren()) do
                if item:IsA("Model") or item:IsA("BasePart") then
                    local isHealth = item.Name == "HealthKit" or item.Name == "Bandage"
                    local isCapsule = item.Name == "ResearchCapsule"
                    local color = ESPColors.AllItemsESP
                    local enabled = Toggles.AllItemsESP

                    if isCapsule then
                        color = ESPColors.CapsuleESP
                        enabled = Toggles.CapsuleESP or Toggles.AllItemsESP
                    elseif isHealth then
                        color = ESPColors.HealthESP
                        enabled = Toggles.HealthESP or Toggles.AllItemsESP
                    end

                    SetESP(item, color, enabled)

                    local track = Toggles.TrackAllItems
                        or (isHealth and Toggles.TrackHealth)
                        or (isCapsule and Toggles.TrackCapsules)
                    if track then
                        addEntry({
                            Name = "[ITEM] " .. item.Name,
                            Obj = item,
                            Color = color,
                            Order = 3,
                            CanTP = true
                        })
                    end
                end
            end
        end

        -- Hazard zones
        for _, descendant in pairs(room:GetDescendants()) do
            if descendant:IsA("BasePart")
                and (descendant.Name == "SproutTendril" or string.find(descendant.Name, "BlotHandZone", 1, true))
            then
                SetESP(descendant, ESPColors.HazardESP, Toggles.HazardESP)
                if Toggles.TrackMonsters then
                    addEntry({
                        Name = "[!] " .. descendant.Name,
                        Obj = descendant,
                        Color = ESPColors.HazardESP,
                        Order = 1,
                        CanTP = false
                    })
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.Order == b.Order then
            return a.Name < b.Name
        end
        return a.Order < b.Order
    end)

    SweepESP()
    UpdateTeleportList(entries)
end

local function UpdatePlayerSpy(force)
    if not SessionActive() then
        return
    end
    if not SpyList then
        return
    end

    if not Toggles.ShowSpy then
        if force or lastSpySignature ~= "disabled" then
            lastSpySignature = "disabled"
            SpyList:Clear()
            SpyList:AddLabel("Player spy disabled.", Color3.fromRGB(150, 150, 165), 24)
        end
        return
    end

    local inGamePlayers = workspace:FindFirstChild("InGamePlayers")
    if not inGamePlayers then
        if force or lastSpySignature ~= "waiting" then
            lastSpySignature = "waiting"
            SpyList:Clear()
            SpyList:AddLabel("Waiting for in-game player data...", Color3.fromRGB(150, 150, 165), 24)
        end
        return
    end

    local rows = {}
    local signatureParts = {}

    for _, folder in pairs(inGamePlayers:GetChildren()) do
        local trinkets = folder:FindFirstChild("Trinkets")
        local inventory = folder:FindFirstChild("Inventory")
        local trinketList = {}
        local inventoryList = {}

        if trinkets then
            for _, trinket in pairs(trinkets:GetChildren()) do
                local ok, value = pcall(function()
                    return trinket.Value
                end)
                if ok and value ~= nil then
                    trinketList[#trinketList + 1] = tostring(value)
                end
            end
        end

        if inventory then
            for _, item in pairs(inventory:GetChildren()) do
                local ok, value = pcall(function()
                    return item.Value
                end)
                if ok and value ~= nil then
                    inventoryList[#inventoryList + 1] = tostring(value)
                end
            end
        end

        table.sort(trinketList)
        table.sort(inventoryList)

        rows[#rows + 1] = {
            Name = folder.Name,
            IsYou = folder.Name == PlayerName,
            Trinkets = trinketList,
            Inventory = inventoryList
        }

        signatureParts[#signatureParts + 1] = folder.Name
            .. "|" .. table.concat(trinketList, ",")
            .. "|" .. table.concat(inventoryList, ",")
            .. "|" .. string.format("%.3f,%.3f,%.3f", ESPColors.PlayerESP.R, ESPColors.PlayerESP.G, ESPColors.PlayerESP.B)
    end

    table.sort(rows, function(a, b)
        if a.IsYou ~= b.IsYou then
            return a.IsYou
        end
        return a.Name < b.Name
    end)

    local signature = table.concat(signatureParts, "||")
    if not force and signature == lastSpySignature then
        return
    end
    lastSpySignature = signature

    SpyList:Clear()
    if #rows == 0 then
        SpyList:AddLabel("No players found in run data.", Color3.fromRGB(150, 150, 165), 24)
        return
    end

    for _, row in ipairs(rows) do
        local title = string.upper(row.Name) .. (row.IsYou and "  [YOU]" or "")
        SpyList:AddLabel(title, Color3.fromRGB(240, 245, 255), 18)
        SpyList:AddLabel(
            "TRINKETS: " .. (#row.Trinkets > 0 and table.concat(row.Trinkets, ", ") or "None"),
            Color3.fromRGB(185, 190, 205)
        )
        SpyList:AddLabel(
            "INV: " .. (#row.Inventory > 0 and table.concat(row.Inventory, ", ") or "Empty"),
            Color3.fromRGB(140, 200, 255)
        )
        SpyList:AddButton("TELEPORT // " .. row.Name, ESPColors.PlayerESP, function()
            TeleportToPlayer(row.Name)
        end)
        SpyList:AddSpacer(6)
    end
end

local worldRefreshQueued = false
local function QueueWorldRefresh()
    if worldRefreshQueued then
        return
    end
    worldRefreshQueued = true
    task.defer(function()
        worldRefreshQueued = false
        if SessionActive() then
            pcall(UpdateWorldESP)
        end
    end)
end

local spyRefreshQueued = false
local function QueueSpyRefresh()
    if spyRefreshQueued then
        return
    end
    spyRefreshQueued = true
    task.defer(function()
        spyRefreshQueued = false
        if SessionActive() then
            pcall(UpdatePlayerSpy)
        end
    end)
end

-- // Auto Skill Check Logic
local skillCheckActive = false

local function press()
    if not VIM then
        return
    end
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.01)
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
end

local function UpdateSkillCheck()
    if not (Toggles.AutoSkill or Toggles.Autofarm) or skillCheckActive then
        return
    end

    local circleGui = PlayerGui:FindFirstChild("CircleSkillCheckGui")
    if circleGui then
        local yellow = circleGui:FindFirstChild("YellowCircle", true)
        local shrinking = circleGui:FindFirstChild("ShrinkingCircle", true)
        if yellow and shrinking and shrinking.Visible then
            local difference = shrinking.AbsoluteSize.X - yellow.AbsoluteSize.X
            if difference <= 7 and difference >= -2 then
                skillCheckActive = true
                press()
                task.spawn(function()
                    repeat
                        task.wait()
                    until not PlayerGui:FindFirstChild("CircleSkillCheckGui")
                        or shrinking.AbsoluteSize.X > yellow.AbsoluteSize.X + 20
                    task.wait(0.1)
                    skillCheckActive = false
                end)
            end
        end
    end

    local needleUi = PlayerGui:FindFirstChild("SkillCheckFrame", true)
    if needleUi and needleUi.Visible then
        local marker = needleUi:FindFirstChild("Marker")
        local gold = needleUi:FindFirstChild("GoldArea")
        if marker and gold then
            local markerPosition = marker.AbsolutePosition + (marker.AbsoluteSize / 2)
            local objects = PlayerGui:GetGuiObjectsAtPosition(markerPosition.X, markerPosition.Y)
            for _, object in pairs(objects) do
                if object == gold then
                    skillCheckActive = true
                    press()
                    task.spawn(function()
                        repeat
                            task.wait()
                        until not needleUi.Visible
                        skillCheckActive = false
                    end)
                end
            end
        end
    end
end

local function handleTreadmill(gui)
    if not (Toggles.AutoSkill or Toggles.Autofarm) then
        return
    end

    local frame = gui:WaitForChild("TapSkillCheckFrame", 5)
    if not frame then
        return
    end
    local container = frame:WaitForChild("Container", 5)
    if not container then
        return
    end
    local tapButton = container:WaitForChild("TapButton", 5)
    if not tapButton then
        return
    end

    while gui and gui.Parent and (Toggles.AutoSkill or Toggles.Autofarm) and SessionActive() do
        press()
        task.wait(0.02)
        local counter = container:FindFirstChild("TapCounter")
        if counter and counter.Text == "SUCCESS!" then
            break
        end
    end
end

PlayerGui.ChildAdded:Connect(function(child)
    if not SessionActive() then
        return
    end
    if child.Name == "TreadmillTapSkillCheckGui" then
        task.spawn(function()
            pcall(handleTreadmill, child)
        end)
    end
end)

-- // Autofarm State
local lockedGen = nil
local isInteracting = false
local safetyLock = false
local levelReady = false
local CAMP_CHECK_DISTANCE = 70
local sproutTeleportTimer = 0
local teleportStage = 0
local lastAutofarmTick = 0
local autofarmWarned = false

local function FireProximityPrompt(prompt)
    if not prompt or not prompt.Enabled then
        return false
    end
    if type(fireproximityprompt) ~= "function" then
        return false
    end
    local ok = pcall(fireproximityprompt, prompt)
    return ok
end

local function GetObjectPosition(object)
    if not object then
        return nil
    end
    if object:IsA("Model") then
        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)
        return ok and pivot and pivot.Position or nil
    end
    if object:IsA("BasePart") then
        return object.Position
    end
    return nil
end

-- // Autofarm danger detection / safe reposition
RunService.Heartbeat:Connect(function()
    if not SessionActive() or not Toggles.Autofarm then
        return
    end

    local now = os.clock()
    if now - lastAutofarmTick < 0.1 then
        return
    end
    lastAutofarmTick = now

    local ok, err = pcall(function()
        local monsters = getRoomFolder("Monsters")
        local generators = getRoomFolder("Generators")
        local room = workspace:FindFirstChild("CurrentRoom")
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")

        if not monsters or not generators or not room or not root then
            return
        end

        local playerPosition = root.Position
        local dangerDetected = false
        local isSproutChasing = false

        for _, monster in pairs(monsters:GetChildren()) do
            if monster.Name == "DyleMonster" then
                local part = monster.PrimaryPart or monster:FindFirstChildWhichIsA("BasePart")
                if part and (part.Position - playerPosition).Magnitude < 40 then
                    dangerDetected = true
                end
            end
        end

        for _, monster in pairs(monsters:GetChildren()) do
            if monster.Name ~= "RazzleDazzleMonster"
                and monster.Name ~= "RodgerMonster"
                and monster.Name ~= "BlottMonster"
            then
                local chase = monster:FindFirstChild("ChasingValue")
                if chase and chase.Value
                    and (chase.Value == LocalPlayer or string.lower(tostring(chase.Value)) == string.lower(LocalPlayer.Name))
                then
                    dangerDetected = true
                    if monster.Name == "SproutMonster" then
                        isSproutChasing = true
                    end
                    break
                end
            end
        end

        if not dangerDetected then
            for _, descendant in pairs(room:GetDescendants()) do
                if (descendant.Name == "SproutTendril" or string.find(descendant.Name, "BlotHandZone", 1, true))
                    and descendant:IsA("BasePart")
                then
                    if (descendant.Position - playerPosition).Magnitude < 30 then
                        dangerDetected = true
                        break
                    end
                end
            end
        end

        if dangerDetected then
            safetyLock = true
            StopInteraction()
            isInteracting = false
            lockedGen = nil

            local safetyList = {}
            for _, generator in pairs(generators:GetChildren()) do
                local point = generator:FindFirstChild("ScrapsAttachPoint", true)
                if point then
                    local minDistanceToThreat = 9999
                    for _, monster in pairs(monsters:GetChildren()) do
                        if monster.PrimaryPart then
                            local distance = (point.Position - monster.PrimaryPart.Position).Magnitude
                            if distance < minDistanceToThreat then
                                minDistanceToThreat = distance
                            end
                        end
                    end
                    for _, descendant in pairs(room:GetDescendants()) do
                        if (descendant.Name == "SproutTendril" or string.find(descendant.Name, "BlotHandZone", 1, true))
                            and descendant:IsA("BasePart")
                        then
                            local distance = (point.Position - descendant.Position).Magnitude
                            if distance < minDistanceToThreat then
                                minDistanceToThreat = distance
                            end
                        end
                    end
                    safetyList[#safetyList + 1] = {
                        Part = point,
                        Dist = minDistanceToThreat,
                        Model = generator
                    }
                end
            end

            table.sort(safetyList, function(a, b)
                return a.Dist > b.Dist
            end)

            if #safetyList > 0 then
                local targetData = nil
                if isSproutChasing then
                    if teleportStage == 0 then
                        targetData = safetyList[2] or safetyList[1]
                        teleportStage = 1
                        sproutTeleportTimer = tick()
                    elseif teleportStage == 1 then
                        if tick() - sproutTeleportTimer >= 1.5 then
                            targetData = safetyList[1]
                            teleportStage = 2
                        else
                            targetData = safetyList[2] or safetyList[1]
                        end
                    else
                        targetData = safetyList[1]
                    end
                else
                    targetData = safetyList[1]
                    teleportStage = 0
                end

                if targetData then
                    local currentCharacter = LocalPlayer.Character
                    local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
                    if currentRoot then
                        local point = targetData.Part
                        local model = targetData.Model
                        local modelHeight = 0
                        local modelCenterY = 0
                        if model:IsA("Model") then
                            local sizeOk, extents = pcall(function()
                                return model:GetExtentsSize()
                            end)
                            local pivotOk, pivot = pcall(function()
                                return model:GetPivot()
                            end)
                            if sizeOk and extents and pivotOk and pivot then
                                modelHeight = extents.Y
                                modelCenterY = pivot.Y
                            end
                        elseif model:IsA("BasePart") then
                            modelHeight = model.Size.Y
                            modelCenterY = model.Position.Y
                        end
                        local roofY = modelCenterY + (modelHeight / 2) + 85
                        currentRoot.CFrame = CFrame.new(point.Position.X, roofY, point.Position.Z)
                        KillVelocity()
                    end
                end
            end
        else
            safetyLock = false
            teleportStage = 0
        end
    end)

    if not ok and not autofarmWarned then
        autofarmWarned = true
        warn("[Dandys World] Autofarm heartbeat error: " .. tostring(err))
    end
end)

-- // Autofarm main loop
local function AutofarmStep()
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return
    end

    local root = character.HumanoidRootPart
    local currentRoom = workspace:FindFirstChild("CurrentRoom")
    local generators = getRoomFolder("Generators")
    local items = getRoomFolder("Items")

    if not currentRoom or not generators or #generators:GetChildren() == 0 then
        levelReady = false
        isInteracting = false
        lockedGen = nil
        return
    end

    if not levelReady then
        task.wait(5)
        levelReady = true
    end

    if safetyLock then
        return
    end

    local incompleteGensFound = false

    if lockedGen and (not lockedGen.Parent or not lockedGen:IsDescendantOf(generators)) then
        lockedGen = nil
        isInteracting = false
    end

    if lockedGen then
        local stats = lockedGen:FindFirstChild("Stats", true)
        local completed = stats and stats:FindFirstChild("Completed")
        if not completed or completed.Value == true then
            lockedGen = nil
            isInteracting = false
        end
    end

    for _, generator in pairs(generators:GetChildren()) do
        local stats = generator:FindFirstChild("Stats", true)
        local completed = stats and stats:FindFirstChild("Completed")
        if completed and completed.Value == false then
            incompleteGensFound = true
            local attach = generator:FindFirstChild("ScrapsAttachPoint", true)
            if attach and isAreaSafe(attach.Position) then
                local connie = stats:FindFirstChild("Connie")
                if not (connie and connie.Value == true) and not lockedGen then
                    lockedGen = generator
                    break
                end
            end
        end
    end

    if lockedGen and not safetyLock then
        local point = lockedGen:FindFirstChild("ScrapsAttachPoint", true)
        if point then
            if (root.Position - point.Position).Magnitude > 5 then
                root.CFrame = point.CFrame
                KillVelocity()
                isInteracting = false
                task.wait(0.3)
            end

            while lockedGen and not safetyLock and not isInteracting do
                local prompt = lockedGen:FindFirstChild("ProximityPrompt", true)
                if prompt and prompt.Enabled then
                    local fired = FireProximityPrompt(prompt)
                    if fired then
                        isInteracting = true
                    end
                    break
                else
                    root.CFrame = root.CFrame * CFrame.new(0, 0, 0.05)
                    task.wait(0.1)
                    root.CFrame = root.CFrame * CFrame.new(0, 0, -0.05)
                    KillVelocity()
                end
                task.wait(0.1)
            end
        end
        return
    end

    local capsulesFound = false
    if not incompleteGensFound and items then
        local capsuleList = {}
        for _, item in pairs(items:GetChildren()) do
            if item.Name == "ResearchCapsule" then
                local position = GetObjectPosition(item)
                if position and isAreaSafe(position) then
                    capsuleList[#capsuleList + 1] = item
                end
            end
        end

        if #capsuleList > 0 then
            capsulesFound = true
            local target = capsuleList[1]
            if not safetyLock then
                local position = GetObjectPosition(target)
                if position and (root.Position - position).Magnitude > 5 then
                    root.CFrame = CFrame.new(position)
                    KillVelocity()
                    task.wait(0.3)
                end

                local capsuleGrabbed = false
                while target.Parent ~= nil and not safetyLock and not capsuleGrabbed do
                    local prompt = target:FindFirstChild("ProximityPrompt", true)
                    if prompt and prompt.Enabled then
                        local fired = FireProximityPrompt(prompt)
                        if fired then
                            capsuleGrabbed = true
                            task.wait(0.2)
                        end
                    else
                        root.CFrame = root.CFrame * CFrame.new(0, 0, 0.05)
                        task.wait(0.1)
                        root.CFrame = root.CFrame * CFrame.new(0, 0, -0.05)
                        KillVelocity()
                    end
                    task.wait(0.1)
                end
            end
            return
        end
    end

    if not incompleteGensFound and not capsulesFound and not safetyLock then
        local elevators = workspace:FindFirstChild("Elevators")
        local elevator = elevators and elevators:FindFirstChild("Elevator")
        if elevator then
            local targetCFrame = nil
            if elevator:IsA("Model") then
                targetCFrame = elevator:GetPivot()
            elseif elevator:IsA("BasePart") then
                targetCFrame = elevator.CFrame
            end
            if targetCFrame and (root.Position - targetCFrame.Position).Magnitude > 3 then
                root.CFrame = targetCFrame * CFrame.new(0, 3.5, 0)
                KillVelocity()
                task.wait(2)
            end
        end
    end
end

task.spawn(function()
    while ScriptRunning and SessionActive() do
        task.wait(0.5)
        if Toggles.Autofarm then
            local ok, err = pcall(AutofarmStep)
            if not ok and not autofarmWarned then
                autofarmWarned = true
                warn("[Dandys World] Autofarm loop error: " .. tostring(err))
            end
        end
    end
end)

-- // Card Voting (Autofarm or Auto Vote)
task.spawn(function()
    local info = workspace:WaitForChild("Info")
    if not info then
        return
    end
    local cardVote = info:WaitForChild("CardVote")
    local cardVoting = info:WaitForChild("CardVoting")
    local inGamePlayers = workspace:WaitForChild("InGamePlayers")
    if not cardVote or not cardVoting or not inGamePlayers then
        return
    end

    local voted = false

    cardVoting:GetPropertyChangedSignal("Value"):Connect(function()
        if not cardVoting.Value then
            voted = false
        end
    end)

    cardVote.ChildAdded:Connect(function()
        if not SessionActive() or not (Toggles.Autofarm or Toggles.AutoVote) then
            return
        end
        if voted then
            return
        end

        task.wait(0.5)

        if not SessionActive() or not (Toggles.Autofarm or Toggles.AutoVote) then
            return
        end
        if not cardVoting.Value then
            return
        end
        if voted then
            return
        end

        local character = LocalPlayer.Character
        if not character or character.Parent ~= inGamePlayers then
            return
        end

        local cards = cardVote:GetChildren()
        local dyleFloorPresent = false
        for _, card in ipairs(cards) do
            if card.Name == "DyleFloor" then
                dyleFloorPresent = true
                break
            end
        end
        if not dyleFloorPresent then
            return
        end

        local validCards = {}
        for _, card in ipairs(cards) do
            if card.Name ~= "DyleFloor" then
                validCards[#validCards + 1] = card
            end
        end
        if #validCards == 0 then
            return
        end

        voted = true
        local chosen = validCards[math.random(1, #validCards)]
        local ok = pcall(function()
            ReplicatedStorage.Events.CardVoteEvent:FireServer(chosen)
        end)
        if not ok then
            voted = false
        end
    end)
end)

-- // Infinite Stamina
local function GetLocalStats()
    local inGamePlayers = workspace:FindFirstChild("InGamePlayers")
    local folder = inGamePlayers and inGamePlayers:FindFirstChild(PlayerName)
    return folder and folder:FindFirstChild("Stats")
end

local function ResetWalkSpeed()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    local stats = GetLocalStats()
    local walkSpeed = stats and stats:FindFirstChild("WalkSpeed")
    humanoid.WalkSpeed = walkSpeed and walkSpeed.Value or 16
end

RunService.Heartbeat:Connect(function()
    if not SessionActive() or not Toggles.InfStamina then
        return
    end
    pcall(function()
        local stats = GetLocalStats()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid or not stats then
            return
        end
        local runSpeed = stats:FindFirstChild("RunSpeed")
        local walkSpeed = stats:FindFirstChild("WalkSpeed")
        if not runSpeed or not walkSpeed then
            return
        end
        local isRunning = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        humanoid.WalkSpeed = isRunning and runSpeed.Value or walkSpeed.Value
    end)
end)

-- // Anti-AFK
LocalPlayer.Idled:Connect(function()
    if not SessionActive() or not Toggles.AntiAFK then
        return
    end
    pcall(function()
        VU:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VU:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end)

-- // Auto Monster Chat
workspace.DescendantAdded:Connect(function(descendant)
    if not SessionActive() or not Toggles.AutoChat then
        return
    end
    if descendant.Name == "Monsters" then
        task.wait(2)
        if SessionActive() and Toggles.AutoChat then
            pcall(SendMonsterChat)
        end
    end
end)

-- // Skill check heartbeat / lighting refresh
RunService.Heartbeat:Connect(function()
    if not SessionActive() then
        return
    end
    -- Keep full bright active while the toggle is on, but never override the
    -- game's own lighting when the toggle is off.
    if Toggles.FullBright then
        pcall(UpdateLighting)
    end
    if Toggles.AutoSkill or Toggles.Autofarm then
        pcall(UpdateSkillCheck)
    end
end)

-- // UI
local ApexVersion = tostring(ApexLibrary.Version or "V3.7 PLUS")
ApexVersion = ApexVersion:gsub("^APEX_SYS%s*", "")

local MyWindow = ApexLibrary.new({
    Title = "Dandys World",
    BrandText = "Apex Lib // " .. ApexVersion,
    StatusText = "READY",
    AccentColor = Color3.fromRGB(255, 85, 0),
    HideKey = Enum.KeyCode.RightControl
})

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
        QueueWorldRefresh()
        if key == "PlayerESP" then
            QueueSpyRefresh()
        end
    end
end

local function BindESPToggle(key)
    return BindToggle(key, QueueWorldRefresh)
end

local function BindSpyToggle(key)
    return BindToggle(key, QueueSpyRefresh)
end

local TabDefinitions = {
    {
        Name = "MAIN",
        Subtitle = "DASHBOARD & SCRIPT INFO",
        Build = function(tab)
            tab:CreateReadMeCard(
                "WELCOME // DANDYS WORLD",
                "Press RightControl on PC or tap the claw button on mobile to toggle the menu. ESP colors are fully editable in VISUALS. TELEPORTS tracks live room objects, AUTOMATION handles farming and skill checks, and PLAYERS shows trinkets and inventory.",
                96
            )
            tab:CreateSectionLabel("SESSION INFO")
            tab:CreateInfoCard("PLAYER", PlayerName)
            tab:CreateInfoCard("AUTHOR", "Drk_Duck")
            tab:CreateInfoCard("UI_ENGINE", ApexLibrary.Version or "APEX_SYS")
            tab:CreateReadMeCard(
                "QUICK NOTES",
                "ESP highlights refresh once per second. Color changes apply on the next refresh. Autofarm is not saved between sessions for safety.",
                80
            )
        end
    },
    {
        Name = "VISUALS",
        Subtitle = "ESP & LIGHTING CONFIG",
        Build = function(tab)
            tab:CreateSectionLabel("LIGHTING")
            tab:CreateToggle(
                "FULL_BRIGHT",
                "Force all lighting to maximum brightness",
                Toggles.FullBright,
                function(state)
                    Toggles.FullBright = state
                    SaveScriptConfig()
                    UpdateLighting()
                end
            )

            tab:CreateSectionLabel("PLAYER & ENTITY ESP // EDITABLE COLORS")
            tab:CreateToggleWithColor(
                "PLAYER_ESP",
                "Highlight other players",
                Toggles.PlayerESP,
                ESPColors.PlayerESP,
                BindESPToggle("PlayerESP"),
                BindColor("PlayerESP")
            )
            tab:CreateToggleWithColor(
                "MONSTER_ESP",
                "Highlight monsters in the current room",
                Toggles.MonsterESP,
                ESPColors.MonsterESP,
                BindESPToggle("MonsterESP"),
                BindColor("MonsterESP")
            )
            tab:CreateToggleWithColor(
                "HAZARD_ESP",
                "Highlight Sprout tendrils and Blot hand zones",
                Toggles.HazardESP,
                ESPColors.HazardESP,
                BindESPToggle("HazardESP"),
                BindColor("HazardESP")
            )
            tab:CreateToggleWithColor(
                "GENERATOR_ESP",
                "Highlight unfinished generators",
                Toggles.GenESP,
                ESPColors.GenESP,
                BindESPToggle("GenESP"),
                BindColor("GenESP")
            )
            tab:CreateToggleWithColor(
                "CAPSULE_ESP",
                "Highlight research capsules",
                Toggles.CapsuleESP,
                ESPColors.CapsuleESP,
                BindESPToggle("CapsuleESP"),
                BindColor("CapsuleESP")
            )
            tab:CreateToggleWithColor(
                "HEALTH_ESP",
                "Highlight health kits and bandages",
                Toggles.HealthESP,
                ESPColors.HealthESP,
                BindESPToggle("HealthESP"),
                BindColor("HealthESP")
            )
            tab:CreateToggleWithColor(
                "ALL_ITEMS_ESP",
                "Highlight every item (health and capsules keep their own colors)",
                Toggles.AllItemsESP,
                ESPColors.AllItemsESP,
                BindESPToggle("AllItemsESP"),
                BindColor("AllItemsESP")
            )

            tab:CreateSectionLabel("ESP TUNING")
            local fillInput
            fillInput = tab:CreateInputCard(
                "ESP_FILL_TRANSPARENCY",
                "0 = solid, 1 = invisible (default 0.70)",
                ESPSettings.FillTransparency,
                function(value)
                    local clamped = math.clamp(value, 0, 1)
                    ESPSettings.FillTransparency = clamped
                    if fillInput then
                        fillInput:SetValue(clamped)
                    end
                    SaveScriptConfig()
                    QueueWorldRefresh()
                end
            )
        end
    },
    {
        Name = "TELEPORTS",
        Subtitle = "ROOM TRACKING & MOVEMENT",
        Build = function(tab)
            tab:CreateSectionLabel("TRACKING FILTERS")
            tab:CreateColumnLayout(function(column)
                column:CreateSideToggle(
                    "MONSTERS",
                    Toggles.TrackMonsters,
                    BindToggle("TrackMonsters", QueueWorldRefresh)
                )
                column:CreateSideToggle(
                    "GENERATORS",
                    Toggles.TrackGens,
                    BindToggle("TrackGens", QueueWorldRefresh)
                )
            end)
            tab:CreateColumnLayout(function(column)
                column:CreateSideToggle(
                    "CAPSULES",
                    Toggles.TrackCapsules,
                    BindToggle("TrackCapsules", QueueWorldRefresh)
                )
                column:CreateSideToggle(
                    "HEALTH",
                    Toggles.TrackHealth,
                    BindToggle("TrackHealth", QueueWorldRefresh)
                )
            end)
            tab:CreateColumnLayout(function(column)
                column:CreateSideToggle(
                    "ALL ITEMS",
                    Toggles.TrackAllItems,
                    BindToggle("TrackAllItems", QueueWorldRefresh)
                )
                column:CreateSideToggle(
                    "LIVE LIST",
                    Toggles.ShowList,
                    function(state)
                        Toggles.ShowList = state
                        SaveScriptConfig()
                        lastTeleportSignature = nil
                        UpdateTeleportList(lastTeleportEntries)
                    end
                )
            end)

            tab:CreateSectionLabel("OBJECT TELEPORTS")
            TeleportList = tab:CreateListCard(
                "LIVE TELEPORT LIST",
                "Click to teleport. Monsters and hazards are read-only.",
                250
            )
            tab:CreateButton(
                "TELEPORT_TO_ELEVATOR",
                "Move to the elevator if one exists in the current room.",
                TeleportToElevator
            )
            tab:CreateReadMeCard(
                "TRACKING NOTE",
                "Use SHOW LIVE LIST to pause or resume the teleport list. ESP colors are configured in VISUALS.",
                70
            )
        end
    },
    {
        Name = "AUTOMATION",
        Subtitle = "AUTOFARM & SKILL CHECKS",
        Build = function(tab)
            tab:CreateSectionLabel("CORE AUTOMATION")
            tab:CreateToggle(
                "AUTO_SKILL_CHECK",
                "Automatically press Space during skill checks",
                Toggles.AutoSkill,
                BindToggle("AutoSkill")
            )
            tab:CreateToggle(
                "AUTO_FARM",
                "Complete generators, collect capsules, and use the elevator. Not saved between sessions.",
                Toggles.Autofarm,
                function(state)
                    Toggles.Autofarm = state
                    SaveScriptConfig()
                    if not state then
                        pcall(StopInteraction)
                    end
                end
            )
            tab:CreateToggle(
                "AUTO_VOTE_CARDS",
                "Vote for a non-Dyle card when card voting starts",
                Toggles.AutoVote,
                BindToggle("AutoVote")
            )
            tab:CreateToggle(
                "INFINITE_STAMINA",
                "Keep sprint speed available while sprinting",
                Toggles.InfStamina,
                function(state)
                    Toggles.InfStamina = state
                    SaveScriptConfig()
                    if not state then
                        ResetWalkSpeed()
                    end
                end
            )
            tab:CreateToggle(
                "ANTI_AFK",
                "Prevent idle kicks",
                Toggles.AntiAFK,
                BindToggle("AntiAFK")
            )

            tab:CreateSectionLabel("CHAT UTILITIES")
            tab:CreateToggle(
                "AUTO_MONSTER_CHAT",
                "Announce monsters when a room's monster folder loads",
                Toggles.AutoChat,
                function(state)
                    Toggles.AutoChat = state
                    SaveScriptConfig()
                    if state then
                        task.spawn(function()
                            pcall(SendMonsterChat)
                        end)
                    end
                end
            )
            tab:CreateButton(
                "SEND_MONSTER_CHAT_NOW",
                "Send the current monster list to chat.",
                SendMonsterChat
            )
            tab:CreateReadMeCard(
                "AUTOFARM WARNING",
                "Autofarm moves your character and interacts with generators. It is intentionally not saved. Use at your own risk.",
                82
            )
        end
    },
    {
        Name = "PLAYERS",
        Subtitle = "PLAYER SPY & INVENTORY",
        Build = function(tab)
            tab:CreateSectionLabel("PLAYER SPY")
            tab:CreateToggle(
                "SHOW_PLAYER_SPY",
                "Show in-game player trinkets and inventory",
                Toggles.ShowSpy,
                function(state)
                    Toggles.ShowSpy = state
                    SaveScriptConfig()
                    lastSpySignature = nil
                    UpdatePlayerSpy(true)
                end
            )
            SpyList = tab:CreateListCard(
                "IN-GAME PLAYERS",
                "Auto-updates. TELEPORT moves you to that player.",
                280
            )
            tab:CreateButton(
                "REFRESH_PLAYER_SPY",
                "Force an immediate player spy refresh.",
                function()
                    lastSpySignature = nil
                    UpdatePlayerSpy(true)
                end
            )
            tab:CreateReadMeCard(
                "PLAYER SPY NOTE",
                "Data comes from workspace.InGamePlayers. Players without run data are ignored.",
                64
            )
        end
    },
    {
        Name = "CONFIG",
        Subtitle = "INTERFACE PREFERENCES",
        Build = function(tab)
            -- Reference layout first: keybind + fixed kill button.
            if not UserInputService.TouchEnabled then
                tab:CreateKeybindCard()
            end
            tab:CreateKillButton("KILL SCRIPT & CLEANUP", function()
                MyWindow:Unload()
            end)

            -- Remaining settings stay in CONFIG and scroll below the fold.
            tab:CreateColorPicker(
                "ACCENT_COLOR",
                "Change the overall system color",
                MyWindow.AccentColor,
                function(color)
                    MyWindow:SetAccentColor(color)
                end
            )

            if UserInputService.TouchEnabled then
                tab:CreateToggle(
                    "LOCK_BUTTON_POSITION",
                    "Lock mobile menu button position",
                    MyWindow.IsButtonLocked,
                    function(state)
                        MyWindow.IsButtonLocked = state
                        MyWindow:SaveSettings()
                    end
                )
            end

            tab:CreateInfoCard("LIBRARY_VERSION", ApexLibrary.Version or "APEX_SYS V3.7 PLUS")
            tab:CreateInfoCard("SCRIPT_VERSION", "DANDYS WORLD // APEX 1.0")
            tab:CreateInfoCard("AUTHOR", "Drk_Duck")
            tab:CreateReadMeCard(
                "CONFIG STORAGE",
                "UI settings persist to ApexLibrary_Config.json. Script toggles, ESP colors, and ESP transparency persist to DandysWorld_Apex_Config.json.",
                76
            )
        end
    }
}

-- // Dynamically build every tab from the definition table
local BuiltTabs = {}
for _, definition in ipairs(TabDefinitions) do
    local tab = MyWindow:CreateTab(definition.Name, definition.Subtitle)
    BuiltTabs[definition.Name] = tab

    if definition.Name == "CONFIG" then
        -- Mandatory settings tab is built directly so failures are visible.
        definition.Build(tab)
    else
        local ok, err = pcall(definition.Build, tab)
        if not ok then
            warn("[Dandys World] Failed to build tab " .. definition.Name .. ": " .. tostring(err))
        end
    end
end

-- Spawn on CONFIG so the first frame matches the reference layout.
MyWindow:SelectTab("CONFIG", true)

-- // Initial refresh
UpdateLighting()
pcall(UpdateWorldESP)
pcall(UpdatePlayerSpy, true)

-- // World / spy refresh loop
task.spawn(function()
    while ScriptRunning and SessionActive() do
        pcall(UpdateWorldESP)
        pcall(UpdatePlayerSpy)
        task.wait(1)
    end
end)

-- // Library unload cleanup
MyWindow:RegisterUnloadCallback(function()
    ScriptRunning = false
    Toggles.AutoSkill = false
    Toggles.Autofarm = false
    Toggles.AutoChat = false
    Toggles.InfStamina = false
    Toggles.FullBright = false
    pcall(UpdateLighting)
    ClearAllESP()
    if ESPFolder and ESPFolder.Parent then
        ESPFolder:Destroy()
    end
    if sessionRegistered and getgenv then
        pcall(function()
            if getgenv().DandysApexSession == SESSION then
                getgenv().DandysApexSession = nil
            end
        end)
    end
end)
