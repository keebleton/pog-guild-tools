-- Pog Raid bug reports and performance numbers.
--
--   * Every Pog Raid error is remembered (the last KEEP different ones, kept
--     across reloads; a repeat bumps its count instead of adding a line).
--     Errors in event handlers are caught in Core; everything else (timers,
--     clicks) through the game's error handler, which we wrap and pass on.
--   * /pog bug opens a copy box with them, plus the version and client
--     build, ready to paste into Discord. /pog bug clear empties it.
--   * /pog probe adds CPU time (Blizzard's addon profiler) and memory.
local ADDON, ns = ...

local Bug = {}
ns.Bug = Bug

Bug.KEEP = 25
Bug.session = {}  -- messages seen this session
local pending = {} -- caught before saved data loaded

local function clean(msg)
    msg = tostring(msg or "?"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    msg = msg:gsub("Interface[\\/]AddOns[\\/]", "")
    return msg:sub(1, 300)
end

local function ours(msg, stack)
    return tostring(msg):find(ADDON, 1, true) ~= nil
        or (type(stack) == "string" and stack:find("AddOns[\\/]" .. ADDON) ~= nil)
end

-- Just our own lines of a stack, a few of them.
local function trimStack(stack)
    local out = {}
    for line in tostring(stack or ""):gmatch("[^\n]+") do
        if line:find(ADDON, 1, true) and #out < 6 then out[#out + 1] = clean(line) end
    end
    return table.concat(out, "\n")
end

local function store()
    if not ns.db then return nil end
    ns.db.errors = ns.db.errors or {}
    return ns.db.errors
end

function Bug.Record(msg, stack)
    msg = clean(msg)
    Bug.lastMsg, Bug.lastAt = msg, GetTime()
    local list = store()
    if not list then
        pending[#pending + 1] = { msg, stack }
        return
    end
    Bug.session[msg] = true
    local now = ns.Now()
    for i, e in ipairs(list) do
        if e.msg == msg then
            e.count, e.last, e.v = e.count + 1, now, ns.VERSION
            if (e.stack or "") == "" then e.stack = trimStack(stack) end
            table.remove(list, i)
            table.insert(list, 1, e)
            return
        end
    end
    table.insert(list, 1, { msg = msg, stack = trimStack(stack), count = 1, last = now, v = ns.VERSION })
    while #list > Bug.KEEP do table.remove(list) end
end

-- Wrap the game's error handler so errors outside event handlers (timers,
-- clicks) are remembered too. It always passes the error on unchanged.
local function install()
    if not (geterrorhandler and seterrorhandler) then return end
    local prev = geterrorhandler()
    pcall(seterrorhandler, function(msg, ...)
        local stack = debugstack and debugstack(2) or nil
        -- Core already recorded the ones it caught (same message, same moment)
        if ours(msg, stack) and not (clean(msg) == Bug.lastMsg and GetTime() == Bug.lastAt) then
            pcall(Bug.Record, msg, stack)
        end
        if prev then return prev(msg, ...) end
    end)
end
install()

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    for _, p in ipairs(pending) do Bug.Record(p[1], p[2]) end
    pending = {}
end)

function Bug:Clear()
    local list = store()
    if list then wipe(list) end
    Bug.session = {}
end

function Bug:Report()
    local version, build = GetBuildInfo()
    local lines = { ("Pog Guild Tools %s, client %s (%s), %s"):format(ns.VERSION, tostring(version), tostring(build),
        date("%Y-%m-%d %H:%M", ns.Now())) }
    local list = store() or {}
    if not list[1] then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "No Pog Guild Tools errors recorded."
        return table.concat(lines, "\n")
    end
    local now, earlier = {}, {}
    for _, e in ipairs(list) do
        table.insert(Bug.session[e.msg] and now or earlier, e)
    end
    local function section(title, items)
        if not items[1] then return end
        lines[#lines + 1] = ""
        lines[#lines + 1] = title
        for _, e in ipairs(items) do
            lines[#lines + 1] = ("[x%d] %s  %s%s"):format(e.count, date("%m-%d %H:%M", e.last), e.msg,
                e.v ~= ns.VERSION and ("  (on " .. tostring(e.v) .. ")") or "")
            for line in tostring(e.stack or ""):gmatch("[^\n]+") do lines[#lines + 1] = "    " .. line end
        end
    end
    section("This session:", now)
    section("Earlier:", earlier)
    return table.concat(lines, "\n")
end

function Bug:Show()
    ns.UI.CopyBox("Pog Guild Tools bug report", self:Report())
end

------------------------------------------------------------------------
-- /pog sync: is shared data getting through?
------------------------------------------------------------------------
local function counts(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. " " .. t[k] end
    return out[1] and table.concat(out, ", ") or "none"
end

local function ago(at)
    local s = math.floor(GetTime() - at + 0.5)
    return s < 120 and (s .. "s ago") or (math.floor(s / 60) .. "m ago")
end

function Bug:SyncReport()
    local Sync, Comm = ns.Sync, ns.Comm
    local st = Comm.stats
    local lines = { ("Pog Guild Tools %s sync check, %s"):format(ns.VERSION, date("%Y-%m-%d %H:%M", ns.Now())) }
    local guild = Sync:GuildName()
    lines[#lines + 1] = ("You: %s   guild: %s   messages locked: %s"):format(tostring(Sync:Me()),
        guild and ('"' .. guild .. '"') or (IsInGuild() and "in a guild, name not loaded yet" or "not in a guild"),
        Comm.IsRestricted() and "YES" or "no")
    if guild then
        local sums, n = Sync:Hash()
        lines[#lines + 1] = ("Shared records: %d   fingerprint %s"):format(n, sums:sub(1, 10))
    end
    local q, b = Comm.QueueLengths()
    lines[#lines + 1] = ("Waiting to send: %d now, %d background, %d records in the outbox"):format(q, b, #Sync.outbox)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Sent: " .. counts(st.sent)
    lines[#lines + 1] = "Send problems: " .. counts(st.failed)
    if st.lastFail then
        lines[#lines + 1] = ("  last: %s -> %s, %s"):format(st.lastFail.what, st.lastFail.why, ago(st.lastFail.at))
    end
    lines[#lines + 1] = "Received: " .. counts(st.recv)
    lines[#lines + 1] = ("Records taken: %d, turned down: %d%s, dropped before the guild loaded: %d"):format(
        Sync.stats.taken, Sync.stats.refused,
        Sync.stats.lastRefused and (" (last: " .. Sync.stats.lastRefused .. ")") or "", Sync.stats.noGuild)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Heard from:"
    local any = false
    for name, f in pairs(st.from) do
        any = true
        local p = Sync.peers[name]
        local data = p and (" | their data: %d records, %s, %s"):format(p.count or 0,
            p.differ == 0 and "same as yours" or (p.differ .. " of 32 groups differ"), ago(p.at)) or " | no fingerprint yet"
        lines[#lines + 1] = ("  %s: %s on %s, %s%s"):format(name, f.what, f.channel, ago(f.at), data)
    end
    if not any then lines[#lines + 1] = "  nobody yet this session" end
    return table.concat(lines, "\n")
end

function Bug:ShowSync()
    ns.UI.CopyBox("Pog Guild Tools sync check", self:SyncReport())
end

------------------------------------------------------------------------
-- Performance
------------------------------------------------------------------------
-- Enum.AddOnProfilerMetric, in case the client doesn't expose the enum.
local METRIC = { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4, CountTimeOver5Ms = 6 }

local function metric(key)
    local E = Enum and Enum.AddOnProfilerMetric
    return (E and E[key]) or METRIC[key]
end

local function call(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    return ok and tonumber(v) or nil
end

-- Lines for /pog probe.
function Bug:Performance()
    local out = {}
    local P = C_AddOnProfiler
    local enabled = P ~= nil and P.GetAddOnMetric ~= nil
    if enabled and P.IsEnabled then
        local ok, on = pcall(P.IsEnabled)
        if ok and on == false then enabled = false end
    end
    if enabled then
        local avg = call(P.GetAddOnMetric, ADDON, metric("SessionAverageTime"))
        local recent = call(P.GetAddOnMetric, ADDON, metric("RecentAverageTime"))
        local peak = call(P.GetAddOnMetric, ADDON, metric("PeakTime"))
        local slow = call(P.GetAddOnMetric, ADDON, metric("CountTimeOver5Ms"))
        local all = call(P.GetOverallMetric, metric("SessionAverageTime"))
        if avg then
            local share = (all and all > 0) and (" (%d%% of all addons)"):format(math.floor(100 * avg / all + 0.5)) or ""
            out[#out + 1] = ("performance: %.3f ms a frame on average%s, recent %.3f ms, slowest %.1f ms, frames over 5 ms: %d"):format(
                avg, share, recent or 0, peak or 0, slow or 0)
        end
    end
    if not out[1] then out[1] = "performance: the addon profiler isn't available on this client" end
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        local kb = call(GetAddOnMemoryUsage, ADDON)
        if kb then
            local idx = ns.Sync and ns.Sync:GuildName() and ns.Sync:Index()
            out[#out + 1] = ("memory: %.1f MB%s"):format(kb / 1024, idx and (", shared records: " .. idx.count) or "")
        end
    end
    return out
end
