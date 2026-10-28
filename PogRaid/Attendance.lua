-- PogRaid attendance: records who was in the raid each night and turns it
-- into weekly attendance.
--
-- A session (one raid night) is snapshotted every 5 minutes and after each
-- boss, noting when each player was first and last seen. A night counts 100%,
-- or 50% for arriving more than GRACE after the start or leaving more than
-- GRACE before the end, unless they said so ahead of time ("I'll be late" /
-- "I'll leave early": shared `notice` records, full credit). Bench players on
-- that night's roster count as there. Officers can override any credit.
--
-- Weekly: a raid week (Tuesday reset) counts as a player's best night that
-- week, so with two raid teams raiding either one counts. Nights are shared
-- between officers (`nights` records), so both teams' nights add up; two
-- officers recording the same raid show as one night.
--
-- Layout (same grid as the other tabs):
--   [Start raid][End raid]  [session name ............]
--   [status line         ]  [date, length, bosses .....]
--   [Summary             ]  [Player      Status     Credit]
--   [sessions ...        ]  [ ...                         ]
--   [Delete session      ]  [Options][Add player]  [CSV][Discord]
local ADDON, ns = ...
local UI = ns.UI

local Att = {}
ns.Attendance = Att

local PAD, GAP, TITLE_H, BAR_H = 12, 8, 30, 26
local FRAME_W, FRAME_H = 902, 608
local LEFT_W = 262
local RX = PAD + LEFT_W + PAD
local RW = FRAME_W - RX - PAD
local ROW1_Y = TITLE_H
local ROW2_Y = ROW1_Y + BAR_H + GAP
local LIST_Y = ROW2_Y + BAR_H + GAP
local BOTTOM_Y = FRAME_H - PAD - BAR_H
local LIST_H = BOTTOM_Y - GAP - LIST_Y
local ROW_H = 22
local NOTICE_W = 110

Att.SNAP_EVERY = 300   -- seconds between snapshots
Att.END_AFTER = 600    -- out of the raid group this long ends the night
Att.STALE = 4 * 3600   -- a session untouched this long is closed on sight
Att.CHECK_EVERY = 30
Att.GRACE = 15 * 60    -- this late, or this early out, still counts as there
Att.KEEP = 365 * 86400 -- shared nights kept a year

local function G() return ns.db.guild end
local function display(name) return name and Ambiguate(name, "short") end

local function classColor(name)
    local p = G().players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if c then return c.r, c.g, c.b end
    return 0.75, 0.75, 0.78
end

local function pctColor(v)
    if v >= 0.8 then return 0.40, 0.85, 0.45 end
    if v >= 0.5 then return 1.00, 0.82, 0.20 end
    return 0.95, 0.35, 0.30
end
Att.PctColor = pctColor

local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end

------------------------------------------------------------------------
-- Sessions
------------------------------------------------------------------------
-- Two recordings of the same raid: their times mostly overlap and most of
-- one's players are in the other.
local function sameRaid(a, b)
    local aStop, bStop = a.stop or a.lastSnap or a.start, b.stop or b.lastSnap or b.start
    local overlap = math.min(aStop, bStop) - math.max(a.start, b.start)
    if overlap <= 0 or overlap < 0.5 * math.min(aStop - a.start, bStop - b.start) then return false end
    local shared, total = 0, 0
    for n in pairs(a.present) do
        total = total + 1
        if b.present[n] then shared = shared + 1 end
    end
    return total > 0 and shared >= 0.5 * total
end

-- Raid nights, newest first. Of two officers' recordings of one raid only
-- the fuller one is listed. Cached until something changes.
function Att:Sessions()
    if self.sessionsCache then return self.sessionsCache end
    local all = {}
    for _, s in pairs(G().sessions) do
        if not s.deleted then all[#all + 1] = s end
    end
    table.sort(all, function(a, b)
        if a.snaps ~= b.snaps then return a.snaps > b.snaps end
        return a.id < b.id
    end)
    local out = {}
    for _, s in ipairs(all) do
        local dup = false
        for _, k in ipairs(out) do
            if sameRaid(k, s) or sameRaid(s, k) then
                dup = true
                break
            end
        end
        if not dup then out[#out + 1] = s end
    end
    table.sort(out, function(a, b)
        if a.start ~= b.start then return a.start > b.start end
        return a.id > b.id
    end)
    self.sessionsCache = out
    return out
end

function Att:Active()
    local id = G().activeSession
    local s = id and G().sessions[id]
    if s and not s.deleted and not s.stop then return s end
    G().activeSession = nil
end

-- Guild key for a raid-roster name, so "Name" and "Name-Realm" land on the
-- same record as the guild roster. Forever's game text (loot lines, duel
-- results) may carry only a first name: "Flyne" becomes the one guild member
-- called "Flyne <surname>", or the one of them who is online.
function Att:Key(name)
    local want = Ambiguate(name, "none")
    if not self.keyCache or self.keyCacheSize ~= ns.Count(G().players) then
        self.keyCache = {}
        for full in pairs(G().players) do self.keyCache[Ambiguate(full, "none")] = full end
        self.keyCacheSize = ns.Count(G().players)
    end
    local hit = self.keyCache[want]
    if hit then return hit end
    if not want:find(" ", 1, true) then
        local n, only, nOn, onlyOn = 0, nil, 0, nil
        local prefix = want .. " "
        for short, full in pairs(self.keyCache) do
            if short:sub(1, #prefix) == prefix then
                n, only = n + 1, full
                if ns.Roster.online[full] then nOn, onlyOn = nOn + 1, full end
            end
        end
        if n == 1 then return only end
        if nOn == 1 then return onlyOn end
    end
    return name
end

function Att:ShouldRecord()
    if G().attAuto == false then return false end
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then return true end
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end

function Att:Start()
    local zone = GetInstanceInfo()
    local now = ns.Now()
    local roster = ns.Roster:Current()
    local s = { id = ns.NewId(), name = zone or "Raid", start = now, lastSnap = 0, lastSeen = now, snaps = 0,
        present = {}, firstAt = {}, lastAt = {}, benchSnaps = {}, bosses = {}, overrides = {},
        rosterId = roster and roster.id, rec = ns.Sync:Me() }
    ns.Touch(s)
    G().sessions[s.id] = s
    G().activeSession = s.id
    self.viewing = s.id
    self:Snapshot(s)
    ns.Print(("attendance: recording '%s'"):format(s.name))
    self:Changed()
    return s
end

function Att:End(s)
    s = s or self:Active()
    if not s then return end
    s.stop = (s.lastSnap > 0) and s.lastSnap or ns.Now()
    ns.Touch(s)
    G().activeSession = nil
    ns.Print(("attendance: '%s' saved, %d snapshot%s"):format(s.name, s.snaps, s.snaps == 1 and "" or "s"))
    self:Share(s)
    self:Changed()
end

function Att:Snapshot(s)
    if not IsInRaid() then return end
    local now = ns.Now()
    s.snaps = s.snaps + 1
    s.lastSnap = now
    s.lastSeen = now
    local here = {}
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, class, _, online = GetRaidRosterInfo(i)
        if name and online ~= false then
            local k = self:Key(name)
            here[k] = true
            s.present[k] = (s.present[k] or 0) + 1
            if s.firstAt then
                s.firstAt[k] = s.firstAt[k] or now
                s.lastAt[k] = now
            end
            local p = G().players[k]
            if not p then
                p = { manual = true, class = class }
                G().players[k] = p
            elseif not p.class then
                p.class = class
            end
        end
    end
    local roster = s.rosterId and G().rosters[s.rosterId]
    if roster and roster.bench then
        for _, n in ipairs(roster.bench) do
            if not here[n] then s.benchSnaps[n] = (s.benchSnaps[n] or 0) + 1 end
        end
    end
    ns.Touch(s)
    self:Changed()
end

-- Runs every CHECK_EVERY seconds and on group/zone changes.
function Att:Check()
    local now = ns.Now()
    local s = self:Active()
    if s and now - (s.lastSeen or s.start) > Att.STALE then
        self:End(s)
        s = nil
    end
    if s then
        if IsInRaid() then
            s.lastSeen = now
            if now - s.lastSnap >= Att.SNAP_EVERY then self:Snapshot(s) end
        elseif now - s.lastSeen >= Att.END_AFTER then
            self:End(s)
        end
    elseif IsInRaid() and select(2, GetInstanceInfo()) == "raid" and self:ShouldRecord() then
        self:Start()
    end
end

-- Arrived more than GRACE after the start, left more than GRACE before the
-- end (only once the night is over).
function Att:LateEarly(s, name)
    local first, last = s.firstAt and s.firstAt[name], s.lastAt and s.lastAt[name]
    if not first then return false, false end
    local late = first - s.start > Att.GRACE
    local early = s.stop ~= nil and s.stop - last > Att.GRACE
    return late, early
end

-- They told the raid ahead of time (from any of their characters).
function Att:SaidSo(s, name)
    local store = ns.Sync:Store("notice") or {}
    local day = ns.RaidDay(s.start)
    local late, early = false, false
    for _, c in ipairs(ns.Profiles and ns.Profiles:Linked(name) or { name }) do
        local n = store[c .. ":" .. day]
        if n and not n.deleted then
            late, early = late or n.late == true, early or n.early == true
        end
    end
    return late, early
end

local function benched(s, name)
    return G().benchCredit ~= false and (s.benchSnaps[name] or 0) > 0
end

function Att:Credit(s, name)
    if s.overrides[name] then return s.overrides[name] end
    if s.snaps == 0 then return 0 end
    local p = s.present[name] or 0
    if not s.firstAt then
        -- nights recorded before 0.13.1: the share of snapshots
        local b = (G().benchCredit ~= false) and (s.benchSnaps[name] or 0) or 0
        return math.min(1, (p + b) / s.snaps)
    end
    if p == 0 then return benched(s, name) and 1 or 0 end
    -- swapped in from the bench (or out to it) isn't late or early
    if benched(s, name) then return 1 end
    local late, early = self:LateEarly(s, name)
    local saidLate, saidEarly = self:SaidSo(s, name)
    if (late and not saidLate) or (early and not saidEarly) then return 0.5 end
    return 1
end

function Att:Status(s, name)
    if s.overrides[name] then
        local o = s.overrides[name]
        return o >= 1 and "set present" or (o <= 0 and "set absent" or "set " .. pct(o))
    end
    local p, b = s.present[name] or 0, s.benchSnaps[name] or 0
    if p == 0 and b > 0 then return "bench" end
    if p == 0 then return "absent" end
    if not s.firstAt then
        if s.snaps > 0 and p / s.snaps >= 0.9 then return "present" end
        return "partial"
    end
    if b > 0 and G().benchCredit ~= false then return "present" end
    local late, early = self:LateEarly(s, name)
    if not late and not early then return "present" end
    local saidLate, saidEarly = self:SaidSo(s, name)
    local text = (late and early) and "late, left early" or (late and "late" or "left early")
    if (not late or saidLate) and (not early or saidEarly) then text = text .. " (said so)" end
    return text
end

-- Everyone relevant to a night: seen, benched, overridden, or on its roster.
function Att:SessionNames(s)
    local set = {}
    for n in pairs(s.present) do set[n] = true end
    for n in pairs(s.benchSnaps) do set[n] = true end
    for n in pairs(s.overrides) do set[n] = true end
    local roster = s.rosterId and G().rosters[s.rosterId]
    if roster and roster.groups then
        for g = 1, 8 do
            for sl = 1, 5 do
                local n = roster.groups[g] and roster.groups[g][sl]
                if n then set[n] = true end
            end
        end
    end
    local out = {}
    for n in pairs(set) do out[#out + 1] = n end
    table.sort(out, function(a, b)
        local ca, cb = self:Credit(s, a), self:Credit(s, b)
        if ca ~= cb then return ca > cb end
        return a < b
    end)
    return out
end

function Att:SetOverride(s, name, credit)
    s.overrides[name] = credit
    ns.Touch(s)
    self:Share(s)
    self:Changed()
end

function Att:DeleteSession(s)
    s.deleted = true
    ns.Touch(s)
    self:Share(s)
    s.present, s.benchSnaps, s.bosses, s.overrides, s.firstAt, s.lastAt = {}, {}, {}, {}, nil, nil
    if G().activeSession == s.id then G().activeSession = nil end
    self.viewing = nil
    self:Changed()
end

------------------------------------------------------------------------
-- Sharing nights between officers (`nights`), and "I'll be late / leave
-- early" notices from anyone (`notice`).
-- A night travels as text: "Name:count:first:last/..." with times as
-- seconds after the start; bench "Name:count/...", overrides
-- "Name:credit/...", bosses "Boss:1:seconds/..." (1 = kill).
------------------------------------------------------------------------
-- set once the whole addon has loaded (see the end of this section), so the
-- order files load in doesn't matter
local Sync

local function safe(name) return (tostring(name):gsub("[:/]", " ")) end

function Att:ToRecord(s)
    if s.deleted then
        return { id = s.id, author = s.rec or Sync:Me(), t = s.start, deleted = true, start = s.start, snaps = 0 }
    end
    local seen, bench, over, bosses = {}, {}, {}, {}
    for n, c in pairs(s.present) do
        local f, l = s.firstAt and s.firstAt[n], s.lastAt and s.lastAt[n]
        seen[#seen + 1] = f and ("%s:%d:%d:%d"):format(safe(n), c, f - s.start, l - s.start) or ("%s:%d"):format(safe(n), c)
    end
    for n, c in pairs(s.benchSnaps) do bench[#bench + 1] = ("%s:%d"):format(safe(n), c) end
    for n, c in pairs(s.overrides) do over[#over + 1] = ("%s:%s"):format(safe(n), tostring(c)) end
    for _, b in ipairs(s.bosses) do
        bosses[#bosses + 1] = ("%s:%d:%d"):format(safe(b.name or "?"), b.success and 1 or 0, math.max(0, (b.t or s.start) - s.start))
    end
    table.sort(seen)
    table.sort(bench)
    table.sort(over)
    return { id = s.id, author = s.rec or Sync:Me(), t = s.start, deleted = s.deleted, name = s.name, start = s.start,
        stop = s.stop, snaps = s.snaps, seen = table.concat(seen, "/"), bench = table.concat(bench, "/"),
        over = table.concat(over, "/"), bosses = table.concat(bosses, "/") }
end

function Att:FromRecord(rec)
    local cur = G().sessions[rec.id]
    -- our own change (we already have it), or a night we're still recording
    if cur and (rec.by == Sync:Me() or G().activeSession == rec.id) then return end
    if rec.deleted then
        if cur then
            cur.deleted = true
            if self.viewing == rec.id then self.viewing = nil end
        end
        self:Changed()
        return
    end
    local s = { id = rec.id, name = rec.name or "Raid", start = rec.start, stop = rec.stop, lastSnap = rec.stop,
        snaps = rec.snaps, present = {}, benchSnaps = {}, overrides = {}, bosses = {}, rec = rec.author,
        rosterId = cur and cur.rosterId, rev = rec.rev, by = rec.by }
    local timed = false
    for n, c, f, l in tostring(rec.seen or ""):gmatch("([^:/]+):(%d+):?(%d*):?(%d*)") do
        s.present[n] = tonumber(c)
        if f ~= "" then
            s.firstAt = s.firstAt or {}
            s.lastAt = s.lastAt or {}
            s.firstAt[n], s.lastAt[n] = rec.start + tonumber(f), rec.start + tonumber(l)
            timed = true
        end
    end
    if timed or (rec.seen or "") == "" then
        s.firstAt, s.lastAt = s.firstAt or {}, s.lastAt or {}
    end
    for n, c in tostring(rec.bench or ""):gmatch("([^:/]+):(%d+)") do s.benchSnaps[n] = tonumber(c) end
    for n, c in tostring(rec.over or ""):gmatch("([^:/]+):([%d%.]+)") do s.overrides[n] = tonumber(c) end
    for name, k, at in tostring(rec.bosses or ""):gmatch("([^:/]+):(%d):(%d+)") do
        s.bosses[#s.bosses + 1] = { name = name, success = k == "1", t = rec.start + tonumber(at) }
    end
    G().sessions[rec.id] = s
    self:Changed()
end

-- Share a night we recorded, or changed (officers only: others' addons
-- wouldn't take it). Nights from before sharing stay on this computer.
function Att:Share(s)
    if not s.rec or not Sync:GuildName() or not Sync:AmOfficer() then return end
    Sync:Write("nights", self:ToRecord(s))
end

local function sane(rec, fields)
    for f, max in pairs(fields) do
        local v = rec[f]
        if v ~= nil and (type(v) ~= "string" or #v > max) then return false end
    end
    return true
end

-- Registered once the whole addon has loaded: WoW reads the .toc (file
-- order) only when the game starts, so nothing here relies on Sync.lua
-- loading first.
local function registerSync()
Sync = ns.Sync
Sync:Register({
    name = "nights", code = "n", order = 4,
    fields = { "name", "start", "stop", "snaps", "seen", "bench", "over", "bosses" },
    numeric = { start = true, stop = true, snaps = true },
    perRecord = true,
    valid = function(rec)
        return Sync:IsOfficer(rec.by) and sane(rec, { name = 60, seen = 6000, bench = 2000, over = 2000, bosses = 2000 })
            and (rec.deleted or (rec.start ~= nil and rec.snaps ~= nil and rec.snaps >= 0))
    end,
    prune = function(store)
        local cutoff = ns.Now() - Att.KEEP
        for id, rec in pairs(store) do
            if rec.t < cutoff then store[id] = nil end
        end
    end,
    expired = function(rec) return rec.t < ns.Now() - Att.KEEP end,
    onChange = function(rec) Att:FromRecord(rec) end,
})

Sync:Register({
    name = "notice", code = "a", order = 2,
    fields = { "day", "late", "early" },
    numeric = { day = true },
    bool = { late = true, early = true },
    valid = function(rec)
        return rec.by == rec.author and rec.day ~= nil and rec.id == rec.author .. ":" .. rec.day
    end,
    prune = function(store)
        local cutoff = ns.RaidDay() - 14
        for id, rec in pairs(store) do
            if rec.day < cutoff then store[id] = nil end
        end
    end,
    expired = function(rec) return rec.day < ns.RaidDay() - 14 end,
    onChange = function(rec) Att:OnNotice(rec) end,
})
end

ns.On("ADDON_LOADED", function(name)
    if name == ADDON and not Sync then registerSync() end
end)

-- Our notice for tonight: running late, leaving early, both or neither.
function Att:MyNotice()
    local n = (Sync:Store("notice") or {})[Sync:Me() .. ":" .. ns.RaidDay()]
    if n and not n.deleted then return n.late == true, n.early == true end
    return false, false
end

function Att:SetNotice(late, early)
    if not Sync:GuildName() then return end
    local me, day = Sync:Me(), ns.RaidDay()
    local id = me .. ":" .. day
    local cur = (Sync:Store("notice") or {})[id]
    if not late and not early then
        if cur and not cur.deleted then
            Sync:Write("notice", { id = id, author = me, t = cur.t, day = day, deleted = true })
        end
        ns.Print("noted: on time tonight")
    else
        Sync:Write("notice", { id = id, author = me, t = cur and cur.t or ns.Now(), day = day,
            late = late or nil, early = early or nil })
        ns.Print(("noted: you'll %s tonight"):format(
            (late and early) and "be late and leave early" or (late and "be late" or "leave early")))
    end
    self:Changed()
end

-- Raid leaders and officers hear about tonight's notices as they come in.
function Att:OnNotice(rec)
    self:Changed()
    if rec.deleted or rec.day ~= ns.RaidDay() or rec.author == Sync:Me() or not (rec.late or rec.early) then return end
    local leads = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or Sync:AmOfficer()
    if not leads then return end
    self.told = self.told or {}
    local key = rec.id .. (rec.late and "L" or "") .. (rec.early and "E" or "")
    if self.told[key] then return end
    self.told[key] = true
    ns.Print(("%s will %s tonight"):format(display(rec.author),
        (rec.late and rec.early) and "be late and leave early" or (rec.late and "be late" or "leave early")))
end

function Att:NoticeMenu()
    local late, early = self:MyNotice()
    return {
        { text = "Tonight's raid", header = true },
        { text = (late and "> " or "   ") .. "I'll be late", func = function() self:SetNotice(not late, early) end },
        { text = (early and "> " or "   ") .. "I'll leave early", func = function() self:SetNotice(late, not early) end },
        { text = "   On time after all", disabled = not late and not early, func = function() self:SetNotice(false, false) end },
    }
end

------------------------------------------------------------------------
-- Summary: attendance over the last 4 and 8 raid weeks and all of them; a
-- week counts as a player's best night that week. Cached until data changes.
------------------------------------------------------------------------
function Att:Changed()
    self.cache, self.sessionsCache = nil, nil
    if self.page and self.page:IsShown() then self:Refresh() end
    if ns.Roster.page and ns.Roster.page:IsShown() then ns.Roster:RefreshPool() end
end

function Att:Summary()
    if self.cache then return self.cache end
    local sessions = self:Sessions()
    local weeks, best = {}, {}
    for _, s in ipairs(sessions) do
        local w = ns.Week(s.start)
        if not best[w] then
            best[w] = {}
            weeks[#weeks + 1] = w
        end
        for _, name in ipairs(self:SessionNames(s)) do
            local c = self:Credit(s, name)
            if c > (best[w][name] or 0) then best[w][name] = c end
            best[w][name] = best[w][name] or 0
        end
    end
    table.sort(weeks, function(a, b) return a > b end)
    local rows, byName = {}, {}
    for i, w in ipairs(weeks) do
        for name, c in pairs(best[w]) do
            local r = byName[name]
            if not r then
                r = { name = name, sum4 = 0, sum8 = 0, sumAll = 0, attended = 0 }
                byName[name] = r
                rows[#rows + 1] = r
            end
            if i <= 4 then r.sum4 = r.sum4 + c end
            if i <= 8 then r.sum8 = r.sum8 + c end
            r.sumAll = r.sumAll + c
            if c > 0 then r.attended = r.attended + 1 end
        end
    end
    local n4, n8, nAll = math.min(4, #weeks), math.min(8, #weeks), #weeks
    for _, r in ipairs(rows) do
        r.last4 = n4 > 0 and r.sum4 / n4 or 0
        r.last8 = n8 > 0 and r.sum8 / n8 or 0
        r.all = nAll > 0 and r.sumAll / nAll or 0
    end
    self.cache = { rows = rows, byName = byName, nights = #sessions, weeks = nAll }
    return self.cache
end

-- Attendance over the last 8 weeks, or nil before any night is recorded.
function Att:Percent(name)
    local sum = self:Summary()
    if sum.nights == 0 then return nil end
    local r = sum.byName[name]
    return r and r.last8 or 0
end

function Att:SortedSummary()
    local rows = {}
    for i, r in ipairs(self:Summary().rows) do rows[i] = r end
    local col = self.sortCol or "last8"
    table.sort(rows, function(a, b)
        if col == "name" then return a.name < b.name end
        if a[col] ~= b[col] then return a[col] > b[col] end
        return a.name < b.name
    end)
    return rows
end

function Att:CSV()
    local lines = { "Player,Last 4 weeks,Last 8 weeks,All weeks,Weeks attended" }
    for _, r in ipairs(self:SortedSummary()) do
        lines[#lines + 1] = ("%s,%d,%d,%d,%d"):format(display(r.name),
            math.floor(r.last4 * 100 + 0.5), math.floor(r.last8 * 100 + 0.5), math.floor(r.all * 100 + 0.5), r.attended)
    end
    return table.concat(lines, "\n")
end

function Att:DiscordText()
    local sum = self:Summary()
    local lines = { ("**Attendance, last %d raid week%s**"):format(math.min(8, sum.weeks), sum.weeks == 1 and "" or "s") }
    for _, r in ipairs(self:SortedSummary()) do
        lines[#lines + 1] = ("%s %s"):format(display(r.name), pct(r.last8))
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local SESSION_COLS = { { key = "name", label = "Player", x = 8, left = true },
    { key = "status", label = "Status", x = 300, left = true }, { key = "credit", label = "Credit", x = -12 } }
local SUMMARY_COLS = { { key = "name", label = "Player", x = 8, left = true },
    { key = "last4", label = "Last 4 wks", x = 330 }, { key = "last8", label = "Last 8 wks", x = 420 },
    { key = "all", label = "All", x = 510 }, { key = "attended", label = "Weeks", x = -12 } }

local function placeCell(fs, parent, col, w)
    fs:ClearAllPoints()
    if col.left then
        fs:SetPoint("LEFT", parent, "LEFT", col.x, 0)
        fs:SetJustifyH("LEFT")
    elseif col.x < 0 then
        fs:SetPoint("RIGHT", parent, "RIGHT", col.x, 0)
        fs:SetJustifyH("RIGHT")
    else
        fs:SetPoint("RIGHT", parent, "LEFT", col.x, 0)
        fs:SetJustifyH("RIGHT")
    end
end

function Att:Build(page)
    self.page = page

    -- Row 1: start / end, session name
    local bw = (LEFT_W - GAP) / 2
    self.startBtn = UI.Button(page, "Start raid", bw, BAR_H, function()
        if not IsInRaid() then
            ns.Print("attendance: join a raid group first")
            return
        end
        if not self:Active() then self:Start() end
    end)
    self.startBtn:SetPoint("TOPLEFT", PAD, -ROW1_Y)
    self.endBtn = UI.Button(page, "End raid", bw, BAR_H, function() self:End() end)
    self.endBtn:SetPoint("LEFT", self.startBtn, "RIGHT", GAP, 0)

    self.nameBox = UI.EditBox(page, 250, BAR_H)
    self.nameBox:SetPoint("TOPLEFT", RX, -ROW1_Y)
    self.nameBox:SetScript("OnTextChanged", function(box, userInput)
        local s = self:Viewing()
        if not userInput or not s then return end
        local clean = ns.Codec.CleanText(box:GetText(), ns.Codec.MAX_NAME)
        if clean ~= "" then
            s.name = clean
            ns.Touch(s)
            self.renamed = s
            self:RefreshList()
        end
    end)
    self.nameBox:SetScript("OnEnterPressed", self.nameBox.ClearFocus)
    -- a renamed night is shared once the box is done with
    self.nameBox:HookScript("OnEditFocusLost", function()
        if self.renamed then
            self:Share(self.renamed)
            self.renamed = nil
        end
    end)
    self.title = UI.Text(page, 13)
    self.title:SetPoint("LEFT", page, "TOPLEFT", RX + 2, -(ROW1_Y + BAR_H / 2))

    -- Row 2: status and the "late / early" button (left), info (right)
    self.noticeBtn = UI.Button(page, "Late / early", NOTICE_W, BAR_H, function(b) UI.ShowMenu(b, self:NoticeMenu()) end)
    UI.DropArrow(self.noticeBtn)
    self.noticeBtn:SetPoint("TOPLEFT", PAD + LEFT_W - NOTICE_W, -ROW2_Y)
    self.status = UI.Text(page, 11)
    self.status:SetPoint("LEFT", page, "TOPLEFT", PAD + 2, -(ROW2_Y + BAR_H / 2))
    self.status:SetWidth(LEFT_W - NOTICE_W - GAP - 4)
    self.status:SetJustifyH("LEFT")
    self.status:SetWordWrap(false)
    self.info = UI.Text(page, 11)
    self.info:SetPoint("LEFT", page, "TOPLEFT", RX + 2, -(ROW2_Y + BAR_H / 2))
    self.info:SetTextColor(0.6, 0.6, 0.65)

    -- Session list
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", PAD, -LIST_Y)
    list:SetSize(LEFT_W, LIST_H)
    UI.Card(list)
    self.listHint = UI.ScrollHint(list, 2, 2)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d)
        self.listOffset = (self.listOffset or 0) - d
        self:RefreshList()
    end)
    self.listRows = {}
    self.listVisible = math.floor((LIST_H - 4) / ROW_H)
    for i = 1, self.listVisible do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(LEFT_W - 4, ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        UI.SelBar(row.sel, 0.18)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.06)
        row.label = UI.Text(row, 11)
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -40, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.count = UI.Text(row, 10)
        row.count:SetPoint("RIGHT", -8, 0)
        row.count:SetTextColor(0.55, 0.55, 0.6)
        row:SetScript("OnClick", function(r)
            self.viewing = r.sessionId
            self.tableOffset = 0
            self:Refresh()
        end)
        self.listRows[i] = row
    end

    -- Table
    local tbl = CreateFrame("Frame", nil, page)
    tbl:SetPoint("TOPLEFT", RX, -LIST_Y)
    tbl:SetSize(RW, LIST_H)
    UI.Card(tbl)
    self.tableArt = ns.Art and ns.Art.Page("attendance", tbl) -- faint game art (Art.PAGES)
    self.tableHint = UI.ScrollHint(tbl, 2 + ROW_H + 2, 2)
    tbl:EnableMouseWheel(true)
    tbl:SetScript("OnMouseWheel", function(_, d)
        self.tableOffset = (self.tableOffset or 0) - d * 3
        self:RefreshTable()
    end)
    self.table = tbl
    local head = CreateFrame("Frame", nil, tbl)
    head:SetPoint("TOPLEFT", 2, -2)
    head:SetSize(RW - 4, ROW_H)
    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    UI.Line(line, 0.06)
    self.head = head
    self.headCells = {}
    for i = 1, 5 do
        local b = CreateFrame("Button", nil, head)
        b:SetSize(80, ROW_H)
        b.text = UI.SectionTitle(b, nil, UI.COLUMN_SIZE)
        b:SetScript("OnClick", function(btn)
            if self:Viewing() or not btn.key then return end
            self.sortCol = btn.key
            self:RefreshTable()
        end)
        self.headCells[i] = b
    end
    self.tableRows = {}
    self.tableVisible = math.floor((LIST_H - 4 - ROW_H) / ROW_H)
    for i = 1, self.tableVisible do
        local row = CreateFrame("Button", nil, tbl)
        row:SetSize(RW - 4, ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - i * ROW_H)
        row:RegisterForClicks("RightButtonUp")
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.06)
        row.cells = {}
        for c = 1, 5 do
            row.cells[c] = UI.Text(row, 12)
            row.cells[c]:SetWordWrap(false)
        end
        row:SetScript("OnClick", function(r)
            local s = self:Viewing()
            if s and r.player then UI.ShowMenu(r, self:PlayerMenu(s, r.player)) end
        end)
        self.tableRows[i] = row
    end
    self.empty = UI.Text(tbl, 11)
    self.empty:SetPoint("TOP", 0, -ROW_H - 24)
    self.empty:SetTextColor(0.55, 0.55, 0.6)
    self.empty:SetJustifyH("CENTER")

    -- Bottom row
    local del = UI.Button(page, "Delete night", LEFT_W, BAR_H)
    del:SetScript("OnClick", function(b)
        local s = self:Viewing()
        if s then UI.ConfirmClick(b, function() self:DeleteSession(s) end) end
    end)
    del:SetPoint("TOPLEFT", PAD, -BOTTOM_Y)
    self.deleteBtn = del
    -- the page's tools in one place, at the bottom right: Add player, Options,
    -- Export (CSV and Discord were two buttons: UI experiment)
    self.exportBtn = UI.Button(page, "Export", 92, BAR_H, function(b)
        UI.ShowMenu(b, {
            { text = "Export", header = true },
            { text = "Copy for Discord", func = function() UI.CopyBox("Attendance for Discord", self:DiscordText()) end },
            { text = "Copy as CSV", func = function() UI.CopyBox("Attendance (CSV, paste into a spreadsheet)", self:CSV()) end },
        })
    end)
    UI.DropArrow(self.exportBtn)
    self.exportBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -BOTTOM_Y)
    local opts = UI.Button(page, "Options", 92, BAR_H, function(b) UI.ShowMenu(b, self:OptionsMenu()) end)
    UI.DropArrow(opts)
    opts:SetPoint("RIGHT", self.exportBtn, "LEFT", -4, 0)
    self.optsBtn = opts
    self.addBtn = UI.Button(page, "Add player", 96, BAR_H, function()
        local s = self:Viewing()
        if not s then return end
        UI.Prompt(self.table, 0, -ROW_H, "Player who was there (full credit)", "", function(text)
            local clean = ns.Codec.CleanText(text, ns.Codec.MAX_NAME)
            if clean ~= "" then self:SetOverride(s, self:Key(clean), 1) end
        end)
    end)
    self.addBtn:SetPoint("RIGHT", opts, "LEFT", -4, 0)
end

function Att:Viewing()
    local s = self.viewing and G().sessions[self.viewing]
    if s and not s.deleted then return s end
    self.viewing = nil
end

function Att:PlayerMenu(s, name)
    return {
        { text = display(name), header = true },
        { text = "Present (100%)", func = function() self:SetOverride(s, name, 1) end },
        { text = "Half credit (50%)", func = function() self:SetOverride(s, name, 0.5) end },
        { text = "Absent (0%)", func = function() self:SetOverride(s, name, 0) end },
        { text = "Use recorded credit", disabled = s.overrides[name] == nil,
            func = function() self:SetOverride(s, name, nil) end },
    }
end

function Att:OptionsMenu()
    local g = G()
    return {
        { text = (g.attAuto ~= false and "[x] " or "[  ] ") .. "Record automatically when I lead, assist or am an officer",
            func = function() g.attAuto = (g.attAuto == false) end },
        { text = (g.benchCredit ~= false and "[x] " or "[  ] ") .. "Bench counts as attended",
            func = function() g.benchCredit = (g.benchCredit == false); self:Changed() end },
    }
end

local function duration(s)
    local stop = s.stop or s.lastSnap
    if not stop or stop <= s.start then return "just started" end
    local m = math.floor((stop - s.start) / 60)
    return m >= 60 and ("%dh %02dm"):format(math.floor(m / 60), m % 60) or (m .. "m")
end

function Att:Refresh()
    if not self.page then return end
    local active = self:Active()
    self.startBtn:SetEnabledState(not active)
    self.endBtn:SetEnabledState(active ~= nil)
    if active then
        self.status:SetText(("|cff66dd77Recording|r %s, %d snapshot%s"):format(active.name, active.snaps,
            active.snaps == 1 and "" or "s"))
    elseif G().attAuto == false then
        self.status:SetText("Auto-record off. Use Start raid.")
    else
        self.status:SetText("Waiting for a raid")
    end
    local late, early = self:MyNotice()
    if not active and (late or early) then
        self.status:SetText((late and early) and "You'll be late and leave early" or (late and "You'll be late tonight"
            or "You'll leave early tonight"))
    end
    self.status:SetTextColor(0.6, 0.6, 0.65)

    local s = self:Viewing()
    self.nameBox:SetShown(s ~= nil)
    self.title:SetShown(s == nil)
    self.addBtn:SetEnabledState(s ~= nil)
    self.deleteBtn:SetEnabledState(s ~= nil)
    if s then
        if not self.nameBox:HasFocus() then self.nameBox:SetText(s.name) end
        local kills, wipes = 0, 0
        for _, b in ipairs(s.bosses) do
            if b.success then kills = kills + 1 else wipes = wipes + 1 end
        end
        self.info:SetText(("%s, %s, %d kill%s, %d wipe%s%s"):format(date("%a %m/%d %H:%M", s.start), duration(s),
            kills, kills == 1 and "" or "s", wipes, wipes == 1 and "" or "s", s.stop and "" or ", recording"))
    else
        self.title:SetText("Attendance summary")
        self.info:SetText("")
    end
    self:RefreshList()
    self:RefreshTable()
end

function Att:RefreshList()
    local sessions = self:Sessions()
    local total = #sessions + 1
    self.listOffset = math.max(0, math.min(self.listOffset or 0, total - self.listVisible))
    self.listHint:Set(self.listOffset, self.listVisible, total)
    for i, row in ipairs(self.listRows) do
        local idx = i + self.listOffset
        if idx == 1 then
            row.sessionId = nil
            row.label:SetText("Summary")
            row.label:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
            row.count:SetText("")
            row.sel:SetShown(self.viewing == nil)
            row:Show()
        elseif sessions[idx - 1] then
            local s = sessions[idx - 1]
            row.sessionId = s.id
            row.label:SetText(date("%a %m/%d", s.start) .. "  " .. s.name)
            row.label:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
            row.count:SetText(s.stop and "" or "live")
            row.sel:SetShown(self.viewing == s.id)
            row:Show()
        else
            row.sessionId = nil
            row:Hide()
        end
    end
end

function Att:RefreshTable()
    local s = self:Viewing()
    local cols = s and SESSION_COLS or SUMMARY_COLS
    for i, cell in ipairs(self.headCells) do
        local col = cols[i]
        if col then
            cell.key = col.key
            cell.text:SetText(col.label .. ((not s and self.sortCol == col.key) and " *" or ""))
            placeCell(cell.text, self.head, col)
            cell:ClearAllPoints()
            cell:SetAllPoints(cell.text)
            cell:Show()
        else
            cell:Hide()
        end
    end

    local rows
    if s then
        rows = self:SessionNames(s)
    else
        rows = self:SortedSummary()
    end
    self.tableOffset = math.max(0, math.min(self.tableOffset or 0, #rows - self.tableVisible))
    self.tableHint:Set(self.tableOffset, self.tableVisible, #rows)
    for i, row in ipairs(self.tableRows) do
        local item = rows[i + self.tableOffset]
        for c, cell in ipairs(row.cells) do
            local col = cols[c]
            if col and item then placeCell(cell, row, col) end
            cell:SetShown(col ~= nil and item ~= nil)
        end
        if item then
            local name = s and item or item.name
            row.player = name
            row.cells[1]:SetText(display(name))
            row.cells[1]:SetTextColor(classColor(name))
            if s then
                local status = self:Status(s, name)
                row.cells[2]:SetText(status)
                if status == "absent" then
                    row.cells[2]:SetTextColor(0.95, 0.35, 0.3)
                elseif status:find("said so", 1, true) then
                    row.cells[2]:SetTextColor(0.4, 0.85, 0.45)
                elseif status:find("late", 1, true) or status:find("early", 1, true) then
                    row.cells[2]:SetTextColor(1, 0.82, 0.2)
                else
                    row.cells[2]:SetTextColor(0.7, 0.7, 0.75)
                end
                local c = self:Credit(s, name)
                row.cells[3]:SetText(pct(c))
                row.cells[3]:SetTextColor(pctColor(c))
            else
                for c, k in ipairs({ "last4", "last8", "all" }) do
                    row.cells[c + 1]:SetText(pct(item[k]))
                    row.cells[c + 1]:SetTextColor(pctColor(item[k]))
                end
                row.cells[5]:SetText(tostring(item.attended))
                row.cells[5]:SetTextColor(0.7, 0.7, 0.75)
            end
            row:Show()
        else
            row.player = nil
            row:Hide()
        end
    end
    if #rows == 0 then
        self.empty:SetText(s and "Nobody recorded yet." or
            "No raid nights yet :)")
    end
    self.empty:SetShown(#rows == 0)
    if self.tableArt then self.tableArt:SetSparse(#rows == 0) end -- an empty card shows its whole picture
end

------------------------------------------------------------------------
-- Events, timer, tab
------------------------------------------------------------------------
local function check() if ns.db then Att:Check() end end

local function tick()
    check()
    C_Timer.After(Att.CHECK_EVERY, tick)
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(Att.CHECK_EVERY, tick)
end)
ns.On("GROUP_ROSTER_UPDATE", check)
ns.On("ZONE_CHANGED_NEW_AREA", check)
ns.On("PLAYER_ENTERING_WORLD", check)
ns.On("ENCOUNTER_END", function(encounterID, encounterName, _, _, success)
    local s = Att:Active()
    if not s then return end
    table.insert(s.bosses, { id = encounterID, name = encounterName, success = success == 1, t = ns.Now() })
    Att:Snapshot(s)
end)

ns.Editor:RegisterTab("attendance", "Attendance", 2,
    function(page) Att:Build(page) end,
    function() Att:Refresh() end, "raid")
