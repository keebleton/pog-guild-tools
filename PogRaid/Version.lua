-- Pog Raid version check, kept deliberately light:
--   * one tiny guild message at login ("V<version>"),
--   * a handful of the addons that hear it (about REPLIERS, picked at random,
--     everyone in a small guild) whisper their version back, at most once per
--     person every 10 minutes ("W<version>"), so a newer version gets noticed
--     without the whole guild answering every login,
--   * everyone else's version rides along on Sync's fingerprint, sent at
--     login and every 10 minutes; the list is saved between sessions.
-- A newer version seen anywhere gives one chat note per session.
local _, ns = ...

local Version = {}
ns.Version = Version

Version.KEEP = 30 * 86400   -- forget people not seen for a month
Version.seen = {}           -- this session: key -> version
Version.replied = {}        -- key -> GetTime() we last answered them
Version.REPLY_EVERY = 600
Version.REPLIERS = 5

local function parse(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

-- -1 / 0 / 1 like a comparison, or nil if either isn't a version.
function Version.Compare(x, y)
    local a, b = parse(x), parse(y)
    if not a or not b then return nil end
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
    end
    return 0
end

local function store()
    ns.db.versions = ns.db.versions or {}
    return ns.db.versions
end

Version.dev = {}            -- this session: key -> the version a dev build is built on

function Version:Note(sender, version)
    -- a dev build ("0.16.5-dev") is nobody's newer version and isn't listed,
    -- but what it can do (group chat) goes by the version it's built on
    local base = sender and tostring(version or ""):match("^(%d+%.%d+%.%d+)%-dev$")
    if base then self.dev[ns.Attendance:Key(sender)] = base end
    if not sender or not parse(version) then return end
    local key = ns.Attendance:Key(sender)
    if key == ns.Sync:Me() then return end
    self.seen[key] = version
    store()[key] = { v = version, t = ns.Now() }
    if Version.Compare(version, ns.VERSION) == 1 and not self.warned then
        self.warned = true
        ns.Print(("a newer Pog Guild Tools (%s) is out, you have %s. Update it from CurseForge."):format(version, ns.VERSION))
    end
    if ns.Settings then ns.Settings:Changed() end
end

-- Newest version known in the guild (including ours).
function Version:Newest()
    local best = ns.VERSION
    for _, e in pairs(store()) do
        if Version.Compare(e.v, best) == 1 then best = e.v end
    end
    return best
end

-- Guildies known to run Pog Raid: { name, version, t, online }.
function Version:List()
    local now, out = ns.Now(), {}
    for name, e in pairs(store()) do
        if now - e.t > Version.KEEP then
            store()[name] = nil
        else
            out[#out + 1] = { name = name, version = e.v, t = e.t, online = ns.Roster.online[name] == true }
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        local c = Version.Compare(a.version, b.version)
        if c and c ~= 0 then return c == 1 end
        return a.name < b.name
    end)
    return out
end

function Version:Announce()
    if IsInGuild() then ns.Comm.Send("V" .. ns.WireVersion(), "GUILD") end
end

function Version:OnMessage(kind, text, channel, sender)
    local v = text:sub(2)
    if kind == "V" and channel == "GUILD" then
        self:Note(sender, v)
        local key = ns.Attendance:Key(sender)
        local last = self.replied[key]
        if (not last or GetTime() - last >= Version.REPLY_EVERY) and math.random() * ns.Sync:Peers() < Version.REPLIERS then
            self.replied[key] = GetTime()
            ns.Comm.Send("W" .. ns.WireVersion(), "WHISPER", Ambiguate(sender, "none"))
        end
    elseif kind == "W" and channel == "WHISPER" then
        self:Note(sender, v)
    end
end

ns.On("PLAYER_LOGIN", function() C_Timer.After(25, function() Version:Announce() end) end)
