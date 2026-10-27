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
        https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua?v=3
]================================================================]--

-- // Apex Library Loader
-- The version query bypasses executor HTTP caches that still hold the old
-- library. LayoutRevision below rejects any stale copy that slips through.
local LIBRARY_URL = "https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua?v=3"
local MIN_LAYOUT_REVISION = 3

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

-- // Shared room threats (monsters + hazards)
-- One cache feeds target selection, safety checks, and flight steering so the
-- whole room is not rescanned every frame. Everything is scoped inside the
-- table to keep the main chunk under Lua's 200-local limit.
local Nav
local Threat = {}
do
    local ignored = {
        RazzleDazzleMonster = true,
        RodgerMonster = true,
        BlottMonster = true,
        SquirmMonster = true,
    }
    local cache = {
        At = 0,
        Monsters = {},
        MonsterParts = {},
        HazardParts = {},
    }
    local CACHE_TTL = 0.4

    function Threat.IsIgnored(name)
        return ignored[name] == true
    end

    function Threat.Refresh(now)
        now = now or os.clock()
        if now - cache.At < CACHE_TTL then
            return cache
        end

        cache.At = now
        cache.Monsters = {}
        cache.MonsterParts = {}
        cache.HazardParts = {}

        local monsters = getRoomFolder("Monsters")
        if monsters then
            for _, monster in pairs(monsters:GetChildren()) do
                if not ignored[monster.Name] then
                    local part = monster.PrimaryPart or monster:FindFirstChildWhichIsA("BasePart")
                    if part then
                        cache.MonsterParts[#cache.MonsterParts + 1] = part
                        cache.Monsters[#cache.Monsters + 1] = {
                            Model = monster,
                            Part = part,
                            Chasing = monster:FindFirstChild("ChasingValue"),
                        }
                    end
                end
            end
        end

        local room = workspace:FindFirstChild("CurrentRoom")
        if room then
            for _, descendant in pairs(room:GetDescendants()) do
                if (descendant.Name == "SproutTendril" or string.find(descendant.Name, "BlotHandZone", 1, true))
                    and descendant:IsA("BasePart")
                then
                    cache.HazardParts[#cache.HazardParts + 1] = descendant
                end
            end
        end

        return cache
    end

    function Threat.Distances(position, now)
        local currentCache = Threat.Refresh(now)
        local nearestMonster = math.huge
        local nearestHazard = math.huge
        local monsterPart = nil
        local hazardPart = nil

        for _, part in pairs(currentCache.MonsterParts) do
            if part.Parent then
                local distance = (part.Position - position).Magnitude
                if distance < nearestMonster then
                    nearestMonster = distance
                    monsterPart = part
                end
            end
        end

        for _, part in pairs(currentCache.HazardParts) do
            if part.Parent then
                local distance = (part.Position - position).Magnitude
                if distance < nearestHazard then
                    nearestHazard = distance
                    hazardPart = part
                end
            end
        end

        return nearestMonster, monsterPart, nearestHazard, hazardPart
    end

    function Threat.Nearby(position, monsterRadius, hazardRadius, verticalLimit)
        local currentCache = Threat.Refresh()
        verticalLimit = verticalLimit or 24

        for _, part in pairs(currentCache.MonsterParts) do
            if part.Parent then
                local dx = part.Position.X - position.X
                local dz = part.Position.Z - position.Z
                if (dx * dx + dz * dz) < monsterRadius * monsterRadius
                    and math.abs(part.Position.Y - position.Y) < verticalLimit
                then
                    return true
                end
            end
        end

        for _, part in pairs(currentCache.HazardParts) do
            if part.Parent then
                local dx = part.Position.X - position.X
                local dz = part.Position.Z - position.Z
                if (dx * dx + dz * dz) < hazardRadius * hazardRadius
                    and math.abs(part.Position.Y - position.Y) < verticalLimit
                then
                    return true
                end
            end
        end

        return false
    end

    function Threat.GetMonsters()
        return Threat.Refresh().Monsters
    end

    function Threat.GetHazards()
        return Threat.Refresh().HazardParts
    end

    function Threat.GetPartRadius(part)
        local size = part and part.Size
        if not size then
            return 0
        end
        return math.max(size.X, size.Z) * 0.5
    end

    function Threat.IsChasingPlayer(entry)
        local chase = entry and entry.Chasing
        if not chase or not chase.Value then
            return false
        end
        if chase.Value == LocalPlayer then
            return true
        end
        return string.lower(tostring(chase.Value)) == string.lower(LocalPlayer.Name)
    end

    -- A monster is a threat when it is actively chasing us or when it has a
    -- clear line of sight inside its vision range. Walls therefore hide us:
    -- proximity alone no longer drags the autofarm away from cover.
    function Threat.GetAttackers(position, radius)
        local currentCache = Threat.Refresh()
        local attackers = {}
        radius = radius or 75

        for _, entry in ipairs(currentCache.Monsters) do
            local part = entry.Part
            if part and part.Parent then
                local dx = part.Position.X - position.X
                local dz = part.Position.Z - position.Z
                local dy = part.Position.Y - position.Y
                local flat = math.sqrt(dx * dx + dz * dz)
                local distance = math.sqrt(flat * flat + dy * dy)
                if distance <= radius and math.abs(dy) <= 36 then
                    local chasing = Threat.IsChasingPlayer(entry)
                    local visible = false
                    if flat <= 60 and Nav then
                        visible = Nav.HasLineOfSight(
                            part.Position + Vector3.new(0, 2, 0),
                            position
                        )
                    end
                    if chasing or visible then
                        attackers[#attackers + 1] = {
                            Part = part,
                            Model = entry.Model,
                            Distance = distance,
                            Visible = visible,
                            Chasing = chasing,
                        }
                    end
                end
            end
        end

        return attackers
    end

    -- Weighted run-away vector. Closer monsters push harder; when several
    -- monsters are attacking, their vectors combine into one escape direction.
    function Threat.GetFleeVector(position, attackers)
        local x, z = 0, 0
        local nearest = math.huge
        local nearestX, nearestZ = 1, 0

        for _, entry in ipairs(attackers or {}) do
            local part = entry.Part
            if part and part.Parent then
                local dx = position.X - part.Position.X
                local dz = position.Z - part.Position.Z
                local distance = math.sqrt(dx * dx + dz * dz)
                if distance < 0.01 then
                    dx, dz, distance = 1, 0, 1
                end
                if distance < nearest then
                    nearest = distance
                    nearestX, nearestZ = dx / distance, dz / distance
                end
                local weight = 1 + math.max(0, 36 - distance) / 18
                x = x + (dx / distance) * weight
                z = z + (dz / distance) * weight
            end
        end

        local length = math.sqrt(x * x + z * z)
        if length < 0.01 then
            return nearestX, nearestZ
        end
        return x / length, z / length
    end
end

-- // Navigation, line of sight, and wall-aware steering
-- PathfindingService supplies the route around static walls. Flight still
-- probes every step and steers around whatever the pathfinder could not see:
-- moving monsters, hazards, and corners. Sight rays are separate so a monster
-- behind a wall does not count as seeing us.
Nav = {}
do
    local WALL_RADIUS = 2.4
    local WALL_OFFSETS = { 0, 1, -1 }
    local WALL_ANGLES = { 0, 25, -25, 50, -50, 75, -75, 100, -100, 125, -125, 150, -150 }
    local ESCAPE_ANGLES = { 0, 20, -20, 40, -40, 60, -60, 80, -80, 100, -100, 120, -120, 150, -150, 180 }

    local function atan2(y, x)
        if math.atan2 then
            return math.atan2(y, x)
        end
        return math.atan(y, x)
    end

    local function addIgnore(list, object)
        if object then
            list[#list + 1] = object
        end
    end

    function Nav.GetRayParams(forSight)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        params.RespectCanCollide = true

        local ignore = {}
        addIgnore(ignore, LocalPlayer.Character)
        local room = workspace:FindFirstChild("CurrentRoom")
        if room then
            addIgnore(ignore, room:FindFirstChild("Monsters"))
            addIgnore(ignore, room:FindFirstChild("Items"))
        end
        addIgnore(ignore, workspace:FindFirstChild("InGamePlayers"))

        if forSight then
            for _, hazard in ipairs(Threat.GetHazards()) do
                addIgnore(ignore, hazard)
            end
        end

        params.FilterDescendantsInstances = ignore
        return params
    end

    local function raycast(origin, delta, params)
        if type(workspace.Raycast) ~= "function" then
            return nil
        end
        local ok, result = pcall(function()
            return workspace:Raycast(origin, delta, params)
        end)
        if ok then
            return result
        end
        return nil
    end

    -- True when no wall blocks the segment. Monsters, players, items and
    -- hazards are ignored so this answers "can they see each other?" only.
    function Nav.HasLineOfSight(from, to)
        if type(workspace.Raycast) ~= "function" then
            return true
        end
        local delta = to - from
        if delta.Magnitude < 0.05 then
            return true
        end
        return raycast(from, delta, Nav.GetRayParams(true)) == nil
    end

    -- Three parallel probes approximate the character capsule. Returns the
    -- distance available before a wall, whether the full probe was clear,
    -- and the normal of the closest hit for wall following.
    function Nav.Probe(origin, direction, distance, radius)
        if type(workspace.Raycast) ~= "function" then
            return distance, true, nil
        end

        local params = Nav.GetRayParams(false)
        local side = Vector3.new(-direction.Z, 0, direction.X) * (radius or WALL_RADIUS)
        local shortest = distance
        local shortestNormal = nil

        for _, offset in ipairs(WALL_OFFSETS) do
            local shift = side * offset
            local hit = raycast(origin + shift, direction * distance, params)
            if hit and hit.Distance < shortest then
                shortest = hit.Distance
                shortestNormal = hit.Normal
            end
        end

        shortest = math.max(0, shortest)
        return shortest, shortest >= distance - 0.2, shortestNormal
    end

    function Nav.SegmentClear(from, to, radius)
        local delta = to - from
        local length = delta.Magnitude
        if length < 0.01 then
            return true
        end
        local direction = delta * (1 / length)
        local _, clear = Nav.Probe(from, direction, length, radius)
        return clear
    end

    -- Pick the closest clear heading to the desired direction. When a wall
    -- blocks the way, follow the wall's tangent instead of aiming at the
    -- goal. Preferred keeps the same side of the wall while rounding a
    -- corner, so the route does not flip back and forth.
    function Nav.AvoidWalls(current, desired, goal, distance, threatParts, threatClearance, preferred)
        local available, clear, hitNormal = Nav.Probe(
            current,
            desired,
            distance,
            WALL_RADIUS
        )
        if clear then
            return desired, available, false
        end

        local clearance = threatClearance or 18
        local goalX, goalZ = 0, 0
        local goalLength = 0
        if goal then
            goalX = goal.X - current.X
            goalZ = goal.Z - current.Z
            goalLength = math.sqrt(goalX * goalX + goalZ * goalZ)
        end

        local normalX, normalZ = 0, 0
        if hitNormal then
            normalX = hitNormal.X
            normalZ = hitNormal.Z
            local normalLength = math.sqrt(normalX * normalX + normalZ * normalZ)
            if normalLength > 0.1 then
                normalX = normalX / normalLength
                normalZ = normalZ / normalLength
            else
                normalLength = 0
            end
            if normalLength <= 0.1 then
                normalX, normalZ = 0, 0
            end
        end

        if normalX ~= 0 or normalZ ~= 0 then
            -- Keep the established wall side while it is still a tangent
            -- along the same surface and remains walkable.
            if preferred then
                local pX, pZ = preferred.X, preferred.Z
                local pLength = math.sqrt(pX * pX + pZ * pZ)
                if pLength > 0.1 then
                    pX, pZ = pX / pLength, pZ / pLength
                    local parallel = math.abs(pX * normalX + pZ * normalZ)
                    if parallel < 0.5 then
                        local pDirection = Vector3.new(pX, 0, pZ)
                        local pAvailable, pClear = Nav.Probe(
                            current,
                            pDirection,
                            distance,
                            WALL_RADIUS
                        )
                        if pClear or pAvailable > 1.5 then
                            return pDirection, pAvailable, true
                        end
                    end
                end
            end

            local tangentX, tangentZ = -normalZ, normalX
            local tangentDot = 0
            if goalLength > 0.01 then
                tangentDot = tangentX * goalX + tangentZ * goalZ
            end
            if tangentDot < 0 then
                tangentX, tangentZ = -tangentX, -tangentZ
            end

            local tangent = Vector3.new(tangentX, 0, tangentZ)
            local tangentAvailable, tangentClear = Nav.Probe(
                current,
                tangent,
                distance,
                WALL_RADIUS
            )
            if tangentClear or tangentAvailable > 1.5 then
                return tangent, tangentAvailable, true
            end

            local other = Vector3.new(-tangentX, 0, -tangentZ)
            local otherAvailable, otherClear = Nav.Probe(
                current,
                other,
                distance,
                WALL_RADIUS
            )
            if otherClear or otherAvailable > 1.5 then
                return other, otherAvailable, true
            end
        end

        -- Wedged between walls: fall back to the widest nearby heading,
        -- using progress toward the goal as the tie breaker.
        local baseAngle = atan2(desired.Z, desired.X)
        local candidates = {}
        local bestAvailable = 0

        for _, offset in ipairs(WALL_ANGLES) do
            local angle = baseAngle + math.rad(offset)
            local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
            local probeAvailable = Nav.Probe(
                current,
                direction,
                distance,
                WALL_RADIUS
            )
            if probeAvailable > 0.75 then
                candidates[#candidates + 1] = {
                    Direction = direction,
                    Available = probeAvailable,
                }
                local usable = math.min(probeAvailable, distance)
                if usable > bestAvailable then
                    bestAvailable = usable
                end
            end
        end

        if #candidates == 0 then
            return nil, 0, true
        end

        local required = math.max(0.75, bestAvailable - 2)
        local bestDirection = nil
        local bestProbeAvailable = 0
        local bestScore = -math.huge

        for _, candidate in ipairs(candidates) do
            local direction = candidate.Direction
            local probeAvailable = candidate.Available
            if math.min(probeAvailable, distance) >= required then
                local score = math.min(probeAvailable, distance) * 2
                    + (direction.X * desired.X + direction.Z * desired.Z) * 10
                if goalLength > 0.01 then
                    score = score
                        + ((direction.X * goalX + direction.Z * goalZ) / goalLength) * 5
                end

                local checkDistance = math.min(probeAvailable, 14)
                local checkX = current.X + direction.X * checkDistance
                local checkZ = current.Z + direction.Z * checkDistance
                for _, part in ipairs(threatParts or {}) do
                    if part.Parent then
                        local dx = part.Position.X - checkX
                        local dz = part.Position.Z - checkZ
                        local flat = math.sqrt(dx * dx + dz * dz)
                        local radius = clearance + Threat.GetPartRadius(part)
                        if flat < radius then
                            score = score - (radius - flat) * 3
                        end
                    end
                end

                if score > bestScore then
                    bestScore = score
                    bestDirection = direction
                    bestProbeAvailable = probeAvailable
                end
            end
        end

        if not bestDirection then
            return nil, 0, true
        end
        return bestDirection, bestProbeAvailable, true
    end

    -- Static route around walls. Direct routes skip pathfinding entirely.
    function Nav.BuildPath(from, to, options)
        options = options or {}
        if Nav.SegmentClear(from, to, WALL_RADIUS) then
            return { to }
        end

        local hover = options.Hover or 3
        local points = {}
        local ok = pcall(function()
            local pathService = game:GetService("PathfindingService")
            local path = pathService:CreatePath({
                AgentRadius = 3,
                AgentHeight = 6,
                AgentCanJump = true,
                AgentCanClimb = false,
                WaypointSpacing = 6,
            })
            path:ComputeAsync(
                from - Vector3.new(0, hover, 0),
                to - Vector3.new(0, hover, 0)
            )
            if path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                for index = 2, #waypoints do
                    local point = waypoints[index].Position
                    points[#points + 1] = Vector3.new(
                        point.X,
                        point.Y + hover,
                        point.Z
                    )
                end
            end
        end)

        if not ok or #points == 0 then
            return { to }
        end

        local last = points[#points]
        if (last - to).Magnitude > 1 and Nav.SegmentClear(last, to, WALL_RADIUS) then
            points[#points + 1] = to
        end

        -- Smooth the path without cutting through a wall.
        local simplified = {}
        local anchor = from
        local index = 1
        while index <= #points do
            local chosen = index
            for candidate = #points, index, -1 do
                if Nav.SegmentClear(anchor, points[candidate], WALL_RADIUS) then
                    chosen = candidate
                    break
                end
            end
            simplified[#simplified + 1] = points[chosen]
            anchor = points[chosen]
            index = chosen + 1
        end

        return simplified
    end

    -- Run directly away from the current attackers. Candidates are clamped
    -- before the first wall and scored by distance, threat clearance, and
    -- whether the endpoint breaks line of sight.
    function Nav.FindEscapePoint(position, attackers, hover)
        local baseX, baseZ = Threat.GetFleeVector(position, attackers)
        local baseAngle = atan2(baseZ, baseX)
        local hazards = Threat.GetHazards()
        local best = nil
        local bestScore = -math.huge

        for _, offset in ipairs(ESCAPE_ANGLES) do
            local angle = baseAngle + math.rad(offset)
            local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
            local available = Nav.Probe(position, direction, 68, WALL_RADIUS)
            local travel = math.min(56, math.max(0, available - 5))

            if travel >= 16 then
                local endpoint = position
                    + Vector3.new(direction.X * travel, hover or 0, direction.Z * travel)
                local score = travel * 1.5
                    + (direction.X * baseX + direction.Z * baseZ) * 22

                for _, entry in ipairs(attackers or {}) do
                    local part = entry.Part
                    if part and part.Parent then
                        local dx = endpoint.X - part.Position.X
                        local dz = endpoint.Z - part.Position.Z
                        local flat = math.sqrt(dx * dx + dz * dz)
                        local radius = 22 + Threat.GetPartRadius(part)
                        if flat < radius then
                            score = score - (radius - flat) * 4
                        end
                        if Nav.HasLineOfSight(
                            part.Position + Vector3.new(0, 2, 0),
                            endpoint
                        ) then
                            score = score - 6
                        else
                            score = score + 8
                        end
                    end
                end

                for _, hazard in ipairs(hazards) do
                    if hazard.Parent then
                        local dx = endpoint.X - hazard.Position.X
                        local dz = endpoint.Z - hazard.Position.Z
                        local flat = math.sqrt(dx * dx + dz * dz)
                        if flat < 18 then
                            score = score - (18 - flat) * 3
                        end
                    end
                end

                if score > bestScore then
                    bestScore = score
                    best = endpoint
                end
            end
        end

        return best
    end
end

local function isAreaSafe(targetPosition)
    if #Threat.GetAttackers(targetPosition, 55) > 0 then
        return false
    end
    local _, _, nearestHazard = Threat.Distances(targetPosition)
    return nearestHazard >= 35
end

-- // Incremental CFrame flight
-- Every teleport in this script uses this instead of assigning a distant
-- CFrame in one frame. Movement is smooth, capped per step, follows a
-- wall-aware path, and steers around visible monsters/hazards. Sight is
-- blocked by walls, so a monster behind a wall does not pull the route.
-- Safety logic cancels an in-flight move by bumping the sequence counter.
local Flight = {}
do
    local MAX_STEP = 6
    local DEFAULT_SPEED = 85
    local TIMEOUT = 25
    local sequence = 0

    Flight.FarmSpeed = 65

    function Flight.Cancel()
        sequence = sequence + 1
    end

    local function normalize2(x, z)
        local length = math.sqrt(x * x + z * z)
        if length < 0.0001 then
            return 1, 0, 0
        end
        return x / length, z / length, length
    end

    local function isThreatVisible(part, position)
        if not part or not part.Parent then
            return false
        end
        local dx = part.Position.X - position.X
        local dz = part.Position.Z - position.Z
        if (dx * dx + dz * dz) > 3600 then
            return false
        end
        return Nav.HasLineOfSight(
            part.Position + Vector3.new(0, 1.5, 0),
            position
        )
    end

    local function steerThreats(current, directionX, directionZ, remaining, monsters, hazards, clearance)
        local steerX, steerZ = directionX, directionZ

        local function apply(parts, baseClearance)
            for _, part in ipairs(parts) do
                if part.Parent and isThreatVisible(part, current) then
                    local toX = part.Position.X - current.X
                    local toZ = part.Position.Z - current.Z
                    local flat = math.sqrt(toX * toX + toZ * toZ)
                    local radius = baseClearance + Threat.GetPartRadius(part)
                    if flat < radius + 10 then
                        local forward = toX * directionX + toZ * directionZ
                        if forward > -8 and forward < remaining + radius then
                            local awayWeight = (radius + 10 - flat) / (radius + 10)
                            if flat > 0.01 then
                                steerX = steerX - (toX / flat) * awayWeight * 1.8
                                steerZ = steerZ - (toZ / flat) * awayWeight * 1.8
                            end

                            local perpX = toX - directionX * forward
                            local perpZ = toZ - directionZ * forward
                            local perpDistance = math.sqrt(perpX * perpX + perpZ * perpZ)
                            if perpDistance < radius then
                                local push = (radius - perpDistance) / radius
                                if perpDistance > 0.01 then
                                    steerX = steerX - (perpX / perpDistance) * push * 2.4
                                    steerZ = steerZ - (perpZ / perpDistance) * push * 2.4
                                else
                                    -- Dead-on collision: pick a stable side.
                                    steerX = steerX - directionZ * push * 3
                                    steerZ = steerZ + directionX * push * 3
                                end
                            end
                        end
                    end
                end
            end
        end

        apply(monsters, clearance)
        apply(hazards, math.min(clearance, 10))
        local x, z = normalize2(steerX, steerZ)
        return x, z
    end

    function Flight.To(targetPosition, options)
        if not targetPosition then
            return false
        end

        options = options or {}
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return false
        end

        sequence = sequence + 1
        local currentSequence = sequence
        local flightCharacter = character
        local speed = options.Speed or DEFAULT_SPEED
        local arriveDistance = options.ArriveDistance or 2
        local timeout = options.Timeout or TIMEOUT
        local avoidThreats = options.AvoidThreats ~= false
        local clearance = options.Clearance or 18
        local hover = options.Hover or 3
        local startedAt = os.clock()
        local lastThreatScan = 0
        local cachedMonsters = {}
        local cachedHazards = {}

        local waypoints = Nav.BuildPath(root.Position, targetPosition, { Hover = hover })
        local waypointIndex = 1
        local lastProgressAt = startedAt
        local lastProgressPosition = root.Position
        local lastRepathAt = startedAt
        local lastAvoidDirection = nil
        local lastAvoidAt = 0

        while sequence == currentSequence do
            character = LocalPlayer.Character
            if character ~= flightCharacter then
                -- Died or respawned mid-flight; do not drag the new
                -- character toward an old destination.
                return false
            end
            root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then
                return false
            end

            local current = root.Position
            local targetDelta = targetPosition - current
            if targetDelta.Magnitude <= arriveDistance then
                KillVelocity()
                return true
            end
            if os.clock() - startedAt > timeout then
                return false
            end

            local waypoint = waypoints[waypointIndex]
            while waypoint
                and (waypoint - current).Magnitude <= math.max(2.5, arriveDistance)
            do
                waypointIndex = waypointIndex + 1
                waypoint = waypoints[waypointIndex]
            end

            local moveGoal = waypoint or targetPosition
            local delta = moveGoal - current
            local distance = delta.Magnitude

            if distance < 0.05 then
                if waypoint then
                    waypointIndex = waypointIndex + 1
                else
                    KillVelocity()
                    return true
                end
            else
                local now = os.clock()
                if avoidThreats and now - lastThreatScan >= 0.2 then
                    lastThreatScan = now
                    local cache = Threat.Refresh(now)
                    cachedMonsters = cache.MonsterParts
                    cachedHazards = cache.HazardParts
                end

                local flatLength = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
                local directionX, directionZ = 0, 0
                if flatLength > 0.01 then
                    directionX = delta.X / flatLength
                    directionZ = delta.Z / flatLength
                end

                -- Run away from visible threats and give them a wide berth,
                -- but still allow passing at a safe distance.
                if avoidThreats and flatLength > 0.01 then
                    directionX, directionZ = steerThreats(
                        current,
                        directionX,
                        directionZ,
                        distance,
                        cachedMonsters,
                        cachedHazards,
                        clearance
                    )
                end

                local moveX, moveZ = directionX, directionZ
                local available = nil
                if flatLength > 0.01 then
                    local probeDistance = math.max(MAX_STEP + 3, 7)
                    local wallDirection, wallAvailable, avoiding = Nav.AvoidWalls(
                        current,
                        Vector3.new(directionX, 0, directionZ),
                        moveGoal,
                        probeDistance,
                        cachedMonsters,
                        clearance,
                        lastAvoidDirection
                    )
                    if wallDirection then
                        moveX = wallDirection.X
                        moveZ = wallDirection.Z
                        available = wallAvailable
                        if avoiding then
                            -- Remember which side of the wall we picked so a
                            -- corner is rounded in one direction instead of
                            -- zig-zagging between both sides.
                            lastAvoidDirection = Vector3.new(
                                wallDirection.X,
                                0,
                                wallDirection.Z
                            )
                            lastAvoidAt = now
                        elseif lastAvoidDirection and now - lastAvoidAt > 1 then
                            lastAvoidDirection = nil
                        end
                    else
                        moveX, moveZ = 0, 0
                        available = 0
                    end
                end

                local dt = RunService.Heartbeat:Wait()
                if sequence ~= currentSequence then
                    return false
                end
                if type(dt) ~= "number" or dt <= 0 then
                    dt = 0.03
                end
                dt = math.min(dt, 0.1)

                local step = math.min(distance, math.max(speed * dt, 1.5), MAX_STEP)
                local yStep = 0
                if math.abs(delta.Y) > 0.05 then
                    yStep = math.clamp(delta.Y / distance * step, -step * 0.5, step * 0.5)
                end
                local horizontalStep = math.sqrt(math.max(0, step * step - yStep * yStep))
                if available then
                    horizontalStep = math.min(horizontalStep, math.max(0, available - 1.0))
                end

                if horizontalStep >= 0.15 or math.abs(yStep) >= 0.15 then
                    local currentCFrame = root.CFrame
                    local rotation = currentCFrame - currentCFrame.Position
                    root.CFrame = CFrame.new(
                        current.X + moveX * horizontalStep,
                        current.Y + yStep,
                        current.Z + moveZ * horizontalStep
                    ) * rotation
                end
                KillVelocity()
            end

            if sequence ~= currentSequence then
                return false
            end

            local now = os.clock()
            if (root.Position - lastProgressPosition).Magnitude >= 3 then
                lastProgressAt = now
                lastProgressPosition = root.Position
            end

            -- A moving monster can invalidate the static route. Rebuild once
            -- progress stalls instead of pushing into the same corner.
            if now - lastProgressAt > 2.5 and now - lastRepathAt > 1.5 then
                waypoints = Nav.BuildPath(root.Position, targetPosition, { Hover = hover })
                waypointIndex = 1
                lastProgressAt = now
                lastProgressPosition = root.Position
                lastRepathAt = now
            end
        end

        return false
    end
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

    Flight.To(targetCFrame.Position + Vector3.new(0, 3, 0), {
        Speed = 90,
        Clearance = 18,
        AvoidThreats = true,
    })
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

    Flight.To(targetCFrame.Position + Vector3.new(0, 3.5, 0), {
        Speed = 90,
        Clearance = 18,
        AvoidThreats = true,
    })
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

    Flight.To(target.CFrame.Position + Vector3.new(0, 3, 0), {
        Speed = 90,
        Clearance = 18,
        AvoidThreats = true,
    })
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
local levelReady = false
local lastAutofarmTick = 0
local autofarmWarned = false

-- Safety movement is sticky: one destination, a hold window, and no instant
-- snap-back when the threat briefly drops out of range.
local Safety = {
    Locked = false,
    Target = nil,
    TargetGen = nil,
    Room = nil,
    Until = 0,
    StartedAt = 0,
    DangerActive = false,
    Relocated = false,
    Hold = 2.5,
    Height = 12,
    Speed = 110,
    TargetAt = 0,
}

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

function Safety.GetAnchor(generator)
    if not generator then
        return nil
    end
    local point = generator:FindFirstChild("ScrapsAttachPoint", true)
    if point and point:IsA("BasePart") then
        return point
    end
    return generator.PrimaryPart or generator:FindFirstChildWhichIsA("BasePart")
end

function Safety.IsCompromised(position)
    return #Threat.GetAttackers(position, 42) > 0
        or Threat.Nearby(position, 0, 22, 16)
end

-- One-time farm relocation target. Generators are the only stable landmarks
-- in every room, so the safest one (fewest attackers, farthest from threats)
-- wins. This is only used after a chase refuses to break, at most once per
-- floor. Escape motion itself stays with Nav.FindEscapePoint.
function Safety.FindTarget()
    local generators = getRoomFolder("Generators")
    local character = LocalPlayer.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    local bestGenerator = nil
    local bestScore = -math.huge

    if generators then
        for _, generator in pairs(generators:GetChildren()) do
            local anchor = Safety.GetAnchor(generator)
            if anchor then
                local nearestMonster, _, nearestHazard = Threat.Distances(anchor.Position)
                local threatDistance = math.min(nearestMonster, nearestHazard)
                local attackers = Threat.GetAttackers(anchor.Position, 65)
                local playerDistance = playerRoot and (playerRoot.Position - anchor.Position).Magnitude or 0
                local score = threatDistance - #attackers * 40 - math.min(playerDistance, 250) * 0.1
                if score > bestScore then
                    bestScore = score
                    bestGenerator = generator
                end
            end
        end
    end

    return nil, bestGenerator
end

function Safety.Reset()
    Safety.Locked = false
    Safety.Target = nil
    Safety.TargetGen = nil
    Safety.Room = nil
    Safety.DangerActive = false
    Safety.Relocated = false
    Safety.Until = 0
    Safety.StartedAt = 0
    Safety.TargetAt = 0
    lockedGen = nil
    isInteracting = false
    Flight.Cancel()
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
        local room = workspace:FindFirstChild("CurrentRoom")
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")

        if not room or not root then
            return
        end

        -- Never carry a safe spot across floors.
        if Safety.Room ~= nil and Safety.Room ~= room then
            Safety.Reset()
        end

        local playerPosition = root.Position
        local attackers = Threat.GetAttackers(playerPosition, 72)
        local _, _, nearestHazard, hazardPart = Threat.Distances(playerPosition)
        local hazardDanger = hazardPart
            and nearestHazard < 22
            and math.abs(hazardPart.Position.Y - playerPosition.Y) < 12

        -- Monsters only count while they can see us or are already chasing.
        -- Proximity alone does not: a wall is real cover.
        local dangerDetected = #attackers > 0 or hazardDanger

        if dangerDetected then
            Safety.Locked = true
            Safety.Until = now + Safety.Hold

            if not Safety.DangerActive then
                Safety.DangerActive = true
                Safety.StartedAt = now
                Safety.Target = nil
                Safety.TargetAt = 0
                Flight.Cancel()
                StopInteraction()
                isInteracting = false
            end

            if not Safety.TargetGen and lockedGen and lockedGen.Parent then
                local generators = getRoomFolder("Generators")
                if generators and lockedGen:IsDescendantOf(generators) then
                    Safety.TargetGen = lockedGen
                end
            end
            if not Safety.Room then
                Safety.Room = room
            end

            -- Run opposite the chasing/visible monsters. When several are on
            -- us, their weighted away-vectors combine into one escape heading.
            local nearestAttacker = math.huge
            for _, entry in ipairs(attackers) do
                if entry.Distance < nearestAttacker then
                    nearestAttacker = entry.Distance
                end
            end

            local reached = Safety.Target
                and (playerPosition - Safety.Target).Magnitude <= 10
            local targetAge = now - (Safety.TargetAt or 0)

            if not Safety.Target or reached
                or (targetAge >= 1.25 and nearestAttacker < 32)
            then
                local fleeAttackers = attackers
                if #fleeAttackers == 0 and hazardPart then
                    fleeAttackers = { { Part = hazardPart } }
                end

                local escape = Nav.FindEscapePoint(
                    playerPosition,
                    fleeAttackers,
                    Safety.Height
                )
                if escape and (
                    not Safety.Target
                    or reached
                    or (escape - Safety.Target).Magnitude > 12
                ) then
                    Safety.Target = escape
                    Safety.TargetAt = now
                    Flight.Cancel()
                elseif not Safety.Target then
                    local awayX, awayZ = Threat.GetFleeVector(
                        playerPosition,
                        fleeAttackers
                    )
                    local awayDirection = Vector3.new(awayX, 0, awayZ)
                    local available = Nav.Probe(
                        playerPosition,
                        awayDirection,
                        40,
                        2.4
                    )
                    local travel = math.min(40, math.max(0, available - 5))
                    if travel >= 6 then
                        Safety.Target = playerPosition + Vector3.new(
                            awayX * travel,
                            Safety.Height,
                            awayZ * travel
                        )
                    else
                        -- Boxed in: gain height instead of aiming through a
                        -- wall at a point outside the room.
                        Safety.Target = playerPosition
                            + Vector3.new(0, Safety.Height, 0)
                    end
                    Safety.TargetAt = now
                    Flight.Cancel()
                else
                    -- Throttle re-scoring when the new point barely moved.
                    Safety.TargetAt = now
                end
            end

            -- One deliberate farm relocation per floor after a chase refuses
            -- to break. Movement stays a run-away point, not a generator hop.
            if not Safety.Relocated and now - Safety.StartedAt >= 8 then
                Safety.Relocated = true
                local _, newGen = Safety.FindTarget()
                if newGen and newGen ~= Safety.TargetGen then
                    Safety.TargetGen = newGen
                end
            end
        else
            Safety.DangerActive = false
            if Safety.Locked and now >= Safety.Until then
                local currentSafe = not Safety.IsCompromised(playerPosition)
                local resumeGen = Safety.TargetGen
                local resumeAnchor = resumeGen and Safety.GetAnchor(resumeGen)
                local resumeSafe = not resumeAnchor or isAreaSafe(resumeAnchor.Position)

                -- Once cover breaks line of sight we can stop running without
                -- waiting to reach the old escape point.
                if currentSafe and resumeSafe then
                    Safety.Locked = false
                    Flight.Cancel()

                    Safety.Target = nil
                    Safety.TargetAt = 0
                    Safety.TargetGen = nil
                    -- Keep Safety.Room for floor-change detection; it is
                    -- cleared by Safety.Reset or the next floor transition.

                    if resumeGen and resumeGen.Parent then
                        local attach = Safety.GetAnchor(resumeGen)
                        if attach and isAreaSafe(attach.Position) then
                            lockedGen = resumeGen
                        end
                    end
                end
            end
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
        if Safety.Room ~= nil and Safety.Room ~= currentRoom then
            Safety.Reset()
        end
        return
    end

    if not levelReady then
        task.wait(5)
        levelReady = true
    end

    if Safety.Locked then
        if Safety.Target then
            Flight.To(Safety.Target, {
                Speed = Safety.Speed,
                Clearance = 18,
                ArriveDistance = 4,
                Timeout = 15,
            })
        end
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

    if lockedGen and not Safety.Locked then
        local point = lockedGen:FindFirstChild("ScrapsAttachPoint", true)
        if point then
            if (root.Position - point.Position).Magnitude > 5 then
                isInteracting = false
                local arrived = Flight.To(point.Position, {
                    Speed = Flight.FarmSpeed,
                    Clearance = 18,
                    ArriveDistance = 4,
                    Timeout = 15,
                })
                if Safety.Locked or not arrived then
                    return
                end
                task.wait(0.15)
            end

            -- Retry the prompt a few times instead of wiggling back and forth
            -- forever while the prompt is still initializing.
            for _ = 1, 3 do
                if not lockedGen or Safety.Locked or isInteracting then
                    break
                end
                local prompt = lockedGen:FindFirstChild("ProximityPrompt", true)
                if prompt and prompt.Enabled then
                    if FireProximityPrompt(prompt) then
                        isInteracting = true
                    end
                    break
                end
                task.wait(0.15)
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
            if not Safety.Locked then
                local position = GetObjectPosition(target)
                if position and (root.Position - position).Magnitude > 5 then
                    local arrived = Flight.To(position, {
                        Speed = Flight.FarmSpeed,
                        Clearance = 18,
                        ArriveDistance = 4,
                        Timeout = 15,
                    })
                    if Safety.Locked or not arrived then
                        return
                    end
                    task.wait(0.15)
                end

                for _ = 1, 8 do
                    if target.Parent == nil or Safety.Locked then
                        break
                    end
                    local prompt = target:FindFirstChild("ProximityPrompt", true)
                    if prompt and prompt.Enabled then
                        if FireProximityPrompt(prompt) then
                            task.wait(0.2)
                        end
                        break
                    end
                    task.wait(0.15)
                end
            end
            return
        end
    end

    if not incompleteGensFound and not capsulesFound and not Safety.Locked then
        local elevators = workspace:FindFirstChild("Elevators")
        local elevator = elevators and elevators:FindFirstChild("Elevator")
        if elevator then
            local targetCFrame = nil
            if elevator:IsA("Model") then
                targetCFrame = elevator:GetPivot()
            elseif elevator:IsA("BasePart") then
                targetCFrame = elevator.CFrame
            end
            if targetCFrame then
                local destination = targetCFrame.Position + Vector3.new(0, 3.5, 0)
                if (root.Position - destination).Magnitude > 3 then
                    Flight.To(destination, {
                        Speed = Flight.FarmSpeed,
                        Clearance = 18,
                        ArriveDistance = 3,
                        Timeout = 15,
                    })
                end
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
    Title = "Dandys World // Menu",
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
                "Click to fly there. Monsters and hazards are read-only.",
                250
            )
            tab:CreateButton(
                "TELEPORT_TO_ELEVATOR",
                "Fly to the elevator if one exists in the current room.",
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
                        pcall(Safety.Reset)
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
    pcall(Safety.Reset)
    pcall(StopInteraction)
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
