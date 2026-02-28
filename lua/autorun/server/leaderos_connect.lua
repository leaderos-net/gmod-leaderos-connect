-- ============================================================
--  LeaderOS Connect
--  Syncs your GMod server with the LeaderOS panel.
--  Fetches the command queue from the API every X minutes
--  and executes the returned commands.
--
--  SETUP:
--    1. Edit lua/leaderos/config.lua
--    2. Add "sv_hibernate_think 1" to server.cfg
-- ============================================================

if not SERVER then return end

LeaderOS = {}

include("leaderos/config.lua")

-- ── Config Validation ────────────────────────────────────────

do
    local url = LeaderOS.Config.WebsiteURL
    local errors = {}

    if type(url) ~= "string" or url == "" then
        table.insert(errors, "WebsiteURL is empty.")
    else
        if not url:match("^https://") then
            table.insert(errors, "WebsiteURL must start with 'https://' (got: '" .. url .. "').")
        end
        if url:sub(-1) == "/" then
            LeaderOS.Config.WebsiteURL = url:sub(1, -2)
            MsgC(Color(255, 200, 80), "[LeaderOS] Trailing slash removed from WebsiteURL.\n")
        end
    end

    if LeaderOS.Config.APIKey == "" or LeaderOS.Config.APIKey == "your-api-key-here" then
        table.insert(errors, "APIKey is not set.")
    end

    if LeaderOS.Config.ConnectToken == "" or LeaderOS.Config.ConnectToken == "your-server-token-here" then
        table.insert(errors, "ConnectToken is not set.")
    end

    if #errors > 0 then
        MsgC(Color(255, 80, 80), "[LeaderOS] Addon could not start due to configuration errors:\n")
        for _, err in ipairs(errors) do
            MsgC(Color(255, 80, 80), "[LeaderOS]   - " .. err .. "\n")
        end
        return
    end
end

-- ── Logging ──────────────────────────────────────────────────

local function log(msg)
    MsgC(Color(100, 200, 255), "[LeaderOS] " .. tostring(msg) .. "\n")
end

local function logDebug(msg)
    if not LeaderOS.Config.DebugMode then return end
    MsgC(Color(80, 200, 120), "[LeaderOS][DEBUG] " .. tostring(msg) .. "\n")
end

local function logError(msg)
    MsgC(Color(255, 80, 80), "[LeaderOS][ERROR] " .. tostring(msg) .. "\n")
end

-- ── HTTP ─────────────────────────────────────────────────────

local function httpGet(endpoint, callback)
    local url = LeaderOS.Config.WebsiteURL .. "/api/" .. endpoint
    logDebug("GET " .. url)

    HTTP({
        url     = url,
        method  = "GET",
        headers = { ["X-Api-Key"] = LeaderOS.Config.APIKey },
        success = function(code, body)
            logDebug("GET " .. endpoint .. " -> " .. code)
            callback(true, body)
        end,
        failed = function(reason)
            logError("GET " .. endpoint .. " -> " .. tostring(reason))
            callback(false, nil)
        end,
    })
end

local function httpPost(endpoint, params, callback)
    local url = LeaderOS.Config.WebsiteURL .. "/api/" .. endpoint
    logDebug("POST " .. url)

    HTTP({
        url        = url,
        method     = "POST",
        headers    = { ["X-Api-Key"] = LeaderOS.Config.APIKey },
        parameters = params,
        success    = function(code, body)
            logDebug("POST " .. endpoint .. " -> " .. code)
            callback(true, body)
        end,
        failed = function(reason)
            logError("POST " .. endpoint .. " -> " .. tostring(reason))
            callback(false, nil)
        end,
    })
end

-- ── Pending Commands (offline players) ───────────────────────

local PENDING_FILE = "leaderos_pending.json"

-- Pending data is stored as an array of objects to avoid Lua/JSON
-- mangling large numeric SteamID64 keys into floats.
-- Format: [{ steamid = "...", cmds = ["...", "..."] }, ...]

local function pendingLoad()
    if not file.Exists(PENDING_FILE, "DATA") then return {} end
    return util.JSONToTable(file.Read(PENDING_FILE, "DATA")) or {}
end

local function pendingSave(data)
    file.Write(PENDING_FILE, util.TableToJSON(data, true))
end

local function pendingAdd(steamid, cmd)
    steamid = tostring(steamid)
    local data = pendingLoad()

    -- Find existing entry for this steamid
    for _, entry in ipairs(data) do
        if entry.steamid == steamid then
            table.insert(entry.cmds, cmd)
            pendingSave(data)
            return
        end
    end

    -- No existing entry, create a new one
    table.insert(data, { steamid = steamid, cmds = { cmd } })
    pendingSave(data)
end

local function pendingFlush(steamid)
    steamid = tostring(steamid)
    local data = pendingLoad()
    local cmds = nil

    for i, entry in ipairs(data) do
        if entry.steamid == steamid then
            cmds = entry.cmds
            table.remove(data, i)
            pendingSave(data)
            break
        end
    end

    return cmds
end

-- Flush pending commands when a player connects
hook.Add("PlayerInitialSpawn", "LeaderOS_PendingFlush", function(ply)
    timer.Simple(3, function()
        if not IsValid(ply) then return end

        local cmds = pendingFlush(ply:SteamID64())
        if not cmds or #cmds == 0 then return end

        log("Executing " .. #cmds .. " pending command(s) for '" .. ply:Nick() .. "'.")
        for _, cmd in ipairs(cmds) do
            game.ConsoleCommand(cmd .. "\n")
        end
    end)
end)

-- ── Command Executor ─────────────────────────────────────────

local function executeCommands(cmds, steamid)
    -- Find the player in-game
    local ply = nil
    for _, p in ipairs(player.GetAll()) do
        if p:SteamID64() == steamid then
            ply = p
            break
        end
    end

    -- Queue commands for offline players if CheckOnline is enabled
    if LeaderOS.Config.CheckOnline and not IsValid(ply) then
        log("Player " .. steamid .. " is offline. Queuing " .. #cmds .. " command(s).")
        for _, cmd in ipairs(cmds) do
            pendingAdd(steamid, cmd)
        end
        return
    end

    -- Execute commands with optional placeholder replacement
    for _, cmd in ipairs(cmds) do
        if IsValid(ply) then
            cmd = cmd:gsub("{steamid}",   ply:SteamID64())
            cmd = cmd:gsub("{steamid32}", ply:SteamID())
            cmd = cmd:gsub("{name}",      ply:Nick())
        end
        log("Executing: " .. cmd)
        game.ConsoleCommand(cmd .. "\n")
    end
end

-- ── Queue Poller ─────────────────────────────────────────────

local function validateAndExecute(ids)
    local params = { token = LeaderOS.Config.ConnectToken }
    for i, id in ipairs(ids) do
        params["commands[" .. (i - 1) .. "]"] = id
    end

    httpPost("command-logs/validate", params, function(ok, body)
        if not ok then return end

        local data = util.JSONToTable(body)
        if not data or not data.commands then
            logError("Invalid validate response: " .. tostring(body))
            return
        end

        -- Collect all commands and the target player's steamid
        local cmds     = {}
        local username = ""

        for _, item in ipairs(data.commands) do
            local cmd = item.command or ""
            if cmd ~= "" then table.insert(cmds, cmd) end
            if username == "" and (item.username or "") ~= "" then
                username = item.username
            end
        end

        if #cmds > 0 and username ~= "" then
            executeCommands(cmds, username)
        end
    end)
end

local function pollQueue()
    logDebug("Polling queue...")

    httpGet("command-logs/" .. LeaderOS.Config.ConnectToken .. "/queue", function(ok, body)
        if not ok then return end

        local data = util.JSONToTable(body)
        if type(data) ~= "table" then
            logError("Invalid queue response.")
            return
        end

        -- API returns a root-level array: [{...}, {...}]
        local arr = data.array or data.data or data

        local ids = {}
        for _, entry in ipairs(arr) do
            if entry.id then table.insert(ids, tostring(entry.id)) end
        end

        logDebug("Queue: " .. #ids .. " item(s) found.")

        if #ids > 0 then
            validateAndExecute(ids)
        end
    end)
end

-- ── Startup ──────────────────────────────────────────────────

hook.Add("InitPostEntity", "LeaderOS_Init", function()
    hook.Remove("InitPostEntity", "LeaderOS_Init")

    local interval = LeaderOS.Config.FreqMinutes * 60
    timer.Create("LeaderOS_Poller", interval, 0, pollQueue)

    log("Started. Queue will be checked every " .. LeaderOS.Config.FreqMinutes .. " minute(s).")
end)

-- ── Console Commands ─────────────────────────────────────────

-- Reload config and restart the timer
concommand.Add("leaderos_reload", function(ply)
    if IsValid(ply) then return end
    include("leaderos/config.lua")
    timer.Remove("LeaderOS_Poller")
    timer.Create("LeaderOS_Poller", LeaderOS.Config.FreqMinutes * 60, 0, pollQueue)
    pollQueue()
    log("Reloaded.")
end)

-- Trigger an immediate poll
concommand.Add("leaderos_poll", function(ply)
    if IsValid(ply) then return end
    pollQueue()
end)

-- Toggle debug mode
concommand.Add("leaderos_debug", function(ply)
    if IsValid(ply) then return end
    LeaderOS.Config.DebugMode = not LeaderOS.Config.DebugMode
    log("Debug mode: " .. tostring(LeaderOS.Config.DebugMode))
end)

-- Print current status
concommand.Add("leaderos_status", function(ply)
    if IsValid(ply) then return end
    log("=== LeaderOS Connect Status ===")
    log("URL:          " .. LeaderOS.Config.WebsiteURL)
    log("Token:        " .. LeaderOS.Config.ConnectToken)
    log("Frequency:    " .. LeaderOS.Config.FreqMinutes .. " minute(s)")
    log("Check Online: " .. tostring(LeaderOS.Config.CheckOnline))
    log("Debug:        " .. tostring(LeaderOS.Config.DebugMode))
    log("Timer active: " .. tostring(timer.Exists("LeaderOS_Poller")))
    if timer.Exists("LeaderOS_Poller") then
        log("Next poll:    " .. math.floor(timer.TimeLeft("LeaderOS_Poller")) .. " second(s)")
    end
end)