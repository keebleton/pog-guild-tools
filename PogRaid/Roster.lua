-- PogRaid roster builder: pick raiders from the guild into raid groups,
-- save a roster per raid night, invite it and arrange the groups.
--
-- Layout (same grid as the boards tab):
--   [search      ][Ranks]  [Rosters][roster name ...........]  [10][20][40]
--   [N raiders ...][Add ]  [Group 1][Group 2][Group 3][Group 4]
--   [pool list          ]  [Group 5][Group 6][Group 7][Group 8]
--   [                   ]  [Bench .............................]
--   [                   ]  [Composition .......................]
--   [Refresh guild      ]  [Clear]        [Copy][Arrange][Invite]
local _, ns = ...
local UI = ns.UI

local Roster = {}
ns.Roster = Roster

local PAD, GAP, TITLE_H, BAR_H = 12, 8, 30, 26
local FRAME_W, FRAME_H = 902, 608
local POOL_W = 262
local RX = PAD + POOL_W + PAD
local RW = FRAME_W - RX - PAD
local ROW1_Y = TITLE_H
local ROW2_Y = ROW1_Y + BAR_H + GAP
local LIST_Y = ROW2_Y + BAR_H + GAP
local BOTTOM_Y = FRAME_H - PAD - BAR_H
local LIST_H = BOTTOM_Y - GAP - LIST_Y
local SLOT_H = 22
local GROUP_COLS = 4
local GROUP_W = (RW - (GROUP_COLS - 1) * GAP) / GROUP_COLS
local GROUP_HEAD = 20
local GROUP_H = GROUP_HEAD + 5 * SLOT_H + 4
local BENCH_Y = ROW2_Y + 2 * GROUP_H + GAP + GAP
local BENCH_ROWS = 4
local BENCH_SLOTS = BENCH_ROWS * GROUP_COLS
local BENCH_H = GROUP_HEAD + BENCH_ROWS * SLOT_H + 4
local COMP_Y = BENCH_Y + BENCH_H + GAP
local COMP_H = BOTTOM_Y - GAP - COMP_Y
local SIZES = { 10, 20, 40 }
local DRAG_PX = 5

Roster.layout = { POOL_W = POOL_W, RX = RX, RW = RW, GROUP_W = GROUP_W, GROUP_H = GROUP_H,
    BENCH_Y = BENCH_Y, COMP_Y = COMP_Y, COMP_H = COMP_H, LIST_Y = LIST_Y, LIST_H = LIST_H }

-- Roles are only what an officer sets by hand: Tank or Healer. Everyone
-- else has no role (no guessing from class).
Roster.ROLES = { "T", "H" }
local ROLE_SORT = { T = 1, H = 2 }
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }

Roster.online = {}

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Names: records keep the guild's full "Name-Realm"; comparisons against
-- the raid roster go through Ambiguate so same-realm names match.
local function key(name) return name and Ambiguate(name, "none") end
local function display(name) return name and Ambiguate(name, "short") end

local function G() return ns.db.guild end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.75, 0.75, 0.78
end

local function maxLevel()
    return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
end

------------------------------------------------------------------------
-- Players
------------------------------------------------------------------------
function Roster:Player(name)
    local p = G().players[name]
    if not p then
        p = {}
        G().players[name] = p
        if ns.Attendance then ns.Attendance.keyCache = nil end
    end
    return p
end

function Roster:RoleOf(name)
    local p = G().players[name]
    local role = p and p.role
    if role == "T" or role == "H" then return role end
    return nil
end

function Roster:SetRole(name, role)
    local p = self:Player(name)
    p.role = role
    ns.Touch(p)
    self:Refresh()
end

-- Reads the guild roster into the players table and reports what changed
-- (level-ups, joins, leaves) to the home page. Skips a roster that has not
-- loaded yet, and when the guild window hides offline members it only
-- updates who it can see, so offline raiders never look like they left.
function Roster:ScanGuild()
    -- only once the game says which guild this is: just after login it may
    -- not, and a roster filed under the wrong guild split 0.16.2's data
    local guildKey = ns.GuildKey()
    if guildKey == ns.NO_GUILD then ns.UseGuild(guildKey) end
    if not guildKey or guildKey == ns.NO_GUILD or not IsInGuild() then return end
    ns.UseGuild(guildKey) -- (this guild's own players, not another's)
    local count = GetNumGuildMembers()
    if not count or count == 0 then return end
    local players = G().players
    local complete = not GetGuildRosterShowOffline or GetGuildRosterShowOffline()
    local firstScan = not G().scanned
    -- The first read after logging in finds what changed while we were away,
    -- and an offline member's level-up wasn't just now either: Home shows
    -- those without a time.
    self.sessionScan = self.sessionScan or {}
    local catchUp = not self.sessionScan[guildKey]
    local levels, joined, left = {}, {}, {}
    local seen = {}
    local myGuid = UnitGUID and UnitGUID("player")
    local first = UnitName("player")
    local byGuid, byFirst = nil, {}
    wipe(self.online)
    for i = 1, count do
        local name, rank, rankIndex, level, _, zone, _, _, online, _, class,
            _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name then
            if myGuid and guid == myGuid then byGuid = name end
            local short = Ambiguate(name, "none")
            if online and first and (short == first or short:sub(1, #first + 1) == first .. " ") then
                byFirst[#byFirst + 1] = name
            end
            local p = players[name]
            if not firstScan then
                if not p or not p.inGuild then
                    joined[#joined + 1] = name
                elseif p.level and level and level > p.level then
                    levels[#levels + 1] = { name = name, level = level, from = p.level, away = catchUp or not online }
                end
            end
            p = self:Player(name)
            p.class, p.rank, p.rankIndex, p.level, p.zone = class, rank, rankIndex, level, zone
            p.inGuild = true
            p.manual = nil
            seen[name] = true
            if online then self.online[name] = true end
        end
    end
    if complete then
        G().fullScan = true -- (every member seen: Sync:IsOfficer stops guessing)
        for name, p in pairs(players) do
            if p.inGuild and not seen[name] then
                p.inGuild = false
                if not firstScan then left[#left + 1] = name end
            end
        end
    end
    G().scanned = true
    self.sessionScan[guildKey] = true
    -- which roster entry is us (our full name: see ns.PlayerName)
    local me = byGuid or (#byFirst == 1 and byFirst[1]) or nil
    if me then ns.SetSelfName(me) end
    if ns.Home then ns.Home:OnGuildScan(levels, joined, left, catchUp) end
end

function Roster:RequestGuild()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    self:ScanGuild()
end

function Roster:AddManual(name, class)
    local clean = ns.Codec.CleanText(name, ns.Codec.MAX_NAME)
    if clean == "" then return end
    clean = clean:sub(1, 1):upper() .. clean:sub(2)
    local p = self:Player(clean)
    if not p.inGuild then
        p.manual = true
        p.class = p.class or class
        ns.Touch(p)
    end
    self:Refresh()
    return clean
end

-- Raider pool: guild members in the chosen ranks (max level only, unless
-- turned off) plus players added by hand, and anyone already rostered.
function Roster:PoolNames()
    local g = G()
    local r = self:Current()
    local out = {}
    for name, p in pairs(g.players) do
        local ok = p.manual
        if p.inGuild then
            ok = (not g.ranks or g.ranks[p.rankIndex]) and (not g.maxLevelOnly or (p.level or 0) >= maxLevel())
        end
        if not ok and r and self:Locate(name) then ok = true end
        if ok and self.search and self.search ~= "" then
            ok = display(name):lower():find(self.search:lower(), 1, true) ~= nil
        end
        if ok then out[#out + 1] = name end
    end
    local marks = r and r.marks or {}
    table.sort(out, function(a, b)
        local ao, bo = marks[a] == "out" and 1 or 0, marks[b] == "out" and 1 or 0
        if ao ~= bo then return ao < bo end
        local ai, bi = self:Locate(a) and 1 or 0, self:Locate(b) and 1 or 0
        if ai ~= bi then return ai < bi end
        local ar, br = ROLE_SORT[self:RoleOf(a) or ""] or 3, ROLE_SORT[self:RoleOf(b) or ""] or 3
        if ar ~= br then return ar < br end
        local ac, bc = (g.players[a].class or ""), (g.players[b].class or "")
        if ac ~= bc then return ac < bc end
        return a < b
    end)
    return out
end

------------------------------------------------------------------------
-- Rosters
------------------------------------------------------------------------
local function newRoster(name, size)
    local groups = {}
    for i = 1, 8 do groups[i] = {} end
    local r = { id = ns.NewId(), name = name, size = size or 20, groups = groups, bench = {}, marks = {},
        created = ns.Now() }
    ns.Touch(r)
    return r
end

function Roster:List()
    local out = {}
    for _, r in pairs(G().rosters) do
        if not r.deleted then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return (a.created or 0) > (b.created or 0) end)
    return out
end

function Roster:Current()
    local r = G().selected and G().rosters[G().selected]
    if r and not r.deleted then return r end
    local list = self:List()
    if list[1] then
        G().selected = list[1].id
        return list[1]
    end
end

function Roster:Select(id)
    G().selected = id
    self:Refresh()
end

function Roster:New(copyFrom)
    local r = newRoster(date("%a %m/%d"), copyFrom and copyFrom.size or 20)
    if copyFrom then
        for g = 1, 8 do
            for s = 1, 5 do r.groups[g][s] = copyFrom.groups[g][s] end
        end
        for i, n in ipairs(copyFrom.bench) do r.bench[i] = n end
        r.name = copyFrom.name .. " (copy)"
    end
    G().rosters[r.id] = r
    self:Select(r.id)
    return r
end

function Roster:Delete()
    local r = self:Current()
    if not r then return end
    r.deleted = true
    r.groups, r.bench, r.marks = nil, nil, nil
    ns.Touch(r)
    G().selected = nil
    if not self:Current() then self:New() end
    self:Refresh()
end

function Roster:Changed()
    local r = self:Current()
    if r then ns.Touch(r) end
    -- rostered-but-absent players count in attendance, so recompute it
    if ns.Attendance then ns.Attendance.cache = nil end
    self:Refresh()
end

function Roster:Groups()
    local r = self:Current()
    return r and r.size / 5 or 4
end

-- Where a player sits: "group", g, s / "bench", i / nil.
function Roster:Locate(name)
    local r = self:Current()
    if not r then return nil end
    for g = 1, 8 do
        for s = 1, 5 do
            if r.groups[g][s] == name then return "group", g, s end
        end
    end
    for i, n in ipairs(r.bench) do
        if n == name then return "bench", i end
    end
end

function Roster:Remove(name)
    local r = self:Current()
    local where, a, b = self:Locate(name)
    if where == "group" then
        r.groups[a][b] = nil
    elseif where == "bench" then
        table.remove(r.bench, a)
    end
end

function Roster:FirstEmpty()
    local r = self:Current()
    for g = 1, self:Groups() do
        for s = 1, 5 do
            if not r.groups[g][s] then return g, s end
        end
    end
end

-- Click on a pool player: first open raid slot, else the bench.
function Roster:Add(name)
    if self:Locate(name) then return end
    local r = self:Current()
    local g, s = self:FirstEmpty()
    if g then
        r.groups[g][s] = name
    else
        r.bench[#r.bench + 1] = name
    end
    self:Changed()
end

-- Drop `name` on a target: { kind = "slot", g, s } / { kind = "group", g }
-- / { kind = "bench" } / { kind = "pool" }. Dropping on an occupied slot
-- swaps when the player came from the roster; from the pool, the occupant
-- goes back to the pool.
function Roster:Drop(name, target)
    local r = self:Current()
    if not r or not target then return end
    local where, a, b = self:Locate(name)
    if target.kind == "pool" then
        self:Remove(name)
    elseif target.kind == "bench" then
        if where == "bench" then return end
        self:Remove(name)
        r.bench[#r.bench + 1] = name
    elseif target.kind == "group" then
        if where == "group" and a == target.g then return end
        local slot
        for s = 1, 5 do
            if not r.groups[target.g][s] then slot = s break end
        end
        if not slot then
            ns.Print(("group %d is full"):format(target.g))
            return
        end
        self:Remove(name)
        r.groups[target.g][slot] = name
    elseif target.kind == "slot" then
        local occupant = r.groups[target.g][target.s]
        if occupant == name then return end
        if where == "group" then
            r.groups[a][b] = occupant
        elseif where == "bench" then
            if occupant then r.bench[a] = occupant else table.remove(r.bench, a) end
        end
        r.groups[target.g][target.s] = name
    end
    self:Changed()
end

function Roster:SetSize(size)
    local r = self:Current()
    if not r or r.size == size then return end
    local moved = 0
    for g = size / 5 + 1, 8 do
        for s = 1, 5 do
            if r.groups[g][s] then
                r.bench[#r.bench + 1] = r.groups[g][s]
                r.groups[g][s] = nil
                moved = moved + 1
            end
        end
    end
    r.size = size
    if moved > 0 then ns.Print(("%d player%s moved to the bench"):format(moved, moved == 1 and "" or "s")) end
    self:Changed()
end

function Roster:Clear()
    local r = self:Current()
    if not r then return end
    for g = 1, 8 do wipe(r.groups[g]) end
    wipe(r.bench)
    self:Changed()
end

function Roster:SetMark(name, mark)
    local r = self:Current()
    r.marks[name] = mark
    self:Changed()
end

function Roster:Composition()
    local r = self:Current()
    local roles, classes, total = { T = 0, H = 0 }, {}, 0
    if not r then return roles, classes, total end
    for g = 1, self:Groups() do
        for s = 1, 5 do
            local name = r.groups[g][s]
            if name then
                total = total + 1
                local role = self:RoleOf(name)
                if role then roles[role] = roles[role] + 1 end
                local class = G().players[name] and G().players[name].class
                if class then classes[class] = (classes[class] or 0) + 1 end
            end
        end
    end
    return roles, classes, total
end

function Roster:DiscordText()
    local r = self:Current()
    if not r then return "" end
    local lines = { ("**%s** (%d)"):format(r.name, r.size) }
    for g = 1, self:Groups() do
        local names = {}
        for s = 1, 5 do
            local n = r.groups[g][s]
            if n then names[#names + 1] = display(n) end
        end
        lines[#lines + 1] = ("Group %d: %s"):format(g, #names > 0 and table.concat(names, ", ") or "-")
    end
    if #r.bench > 0 then
        local names = {}
        for _, n in ipairs(r.bench) do names[#names + 1] = display(n) end
        lines[#lines + 1] = "Bench: " .. table.concat(names, ", ")
    end
    local roles = self:Composition()
    lines[#lines + 1] = ("Tanks %d, Healers %d"):format(roles.T, roles.H)
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- Invites and group arranging
------------------------------------------------------------------------
-- The roster's name for someone in our group. Forever's roster names carry a
-- surname ("Flyne Lee") and a group name may not, so both sides go through
-- Attendance:Key, which maps either one to the roster's name.
local function who(name) return name and ns.Attendance:Key(name) end

local function groupKeys()
    local set = { [who(ns.PlayerName())] = true }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = GetRaidRosterInfo(i)
            if n then set[who(n)] = true end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local n = GetUnitName("party" .. i, true)
            if n then set[who(n)] = true end
        end
    end
    return set
end

local function invite(name)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    local ok, err = pcall(fn, name)
    if not ok then ns.Print("invite failed for " .. display(name) .. ": " .. tostring(err)) end
    return ok
end

local function convertToRaid()
    local fn = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
    if fn then pcall(fn) end
end

-- In a raid the leader or an assistant can invite; in a party only the
-- leader (who also makes it a raid).
local function canInvite()
    if not IsInGroup() then return true end
    if IsInRaid() then return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") end
    return UnitIsGroupLeader("player")
end

-- Invites waiting for the group to become a raid are dropped after this
-- long (nobody accepted), so they can't go out hours later.
Roster.PENDING_FOR = 120

function Roster:Invite()
    local r = self:Current()
    if not r then return end
    local have = groupKeys()
    local todo = {}
    for g = 1, self:Groups() do
        for s = 1, 5 do
            local n = r.groups[g][s]
            if n and not have[who(n)] and r.marks[n] ~= "out" then todo[#todo + 1] = n end
        end
    end
    if #todo == 0 then
        ns.Print("everyone on the roster is already in your group")
        return
    end
    if not canInvite() then
        ns.Print(IsInRaid() and "only the raid leader or an assistant can invite" or "only the party leader can invite")
        return
    end
    -- A party holds 5, so outside a raid invite 4 now and the rest after
    -- the group converts to a raid.
    self.pendingAt = GetTime()
    if IsInRaid() then
        for _, n in ipairs(todo) do invite(n) end
        self.pendingInvites = nil
    elseif IsInGroup() then
        -- convert first; the rest go out once we are a raid
        convertToRaid()
        self.pendingInvites = todo
    else
        local room = math.min(4, #todo)
        for i = 1, room do invite(todo[i]) end
        self.pendingInvites = (room < #todo) and { unpack(todo, room + 1) } or nil
    end
    ns.Print(("inviting %d player%s"):format(#todo, #todo == 1 and "" or "s"))
end

function Roster:OnGroupChanged()
    if self.pendingInvites and GetTime() - (self.pendingAt or 0) > Roster.PENDING_FOR then
        self.pendingInvites = nil
    end
    if self.pendingInvites and IsInGroup() and canInvite() then
        if not IsInRaid() then
            convertToRaid()
        else
            local todo = self.pendingInvites
            self.pendingInvites = nil
            for _, n in ipairs(todo) do invite(n) end
        end
    end
    if self.arranging then self:ArrangeStep() end
    if self.page and self.page:IsVisible() then self:Refresh() end
end

function Roster:Arrange()
    if not IsInRaid() then
        ns.Print("arrange groups needs a raid group")
        return
    end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        ns.Print("arrange groups needs leader or assistant")
        return
    end
    if InCombatLockdown() then
        ns.Print("can't move raid groups in combat")
        return
    end
    self.arranging = { steps = 0 }
    self:ArrangeStep()
end

-- One move per roster update: the raid list reorders after each change,
-- so indexes are only trusted fresh.
function Roster:ArrangeStep()
    local job = self.arranging
    if not job then return end
    job.steps = job.steps + 1
    if job.steps > 80 or InCombatLockdown() then
        self.arranging = nil
        ns.Print("stopped arranging groups")
        return
    end
    local r = self:Current()
    local want = {}
    for g = 1, self:Groups() do
        for s = 1, 5 do
            local n = r.groups[g][s]
            if n then want[who(n)] = g end
        end
    end
    local members, counts = {}, {}
    for i = 1, GetNumGroupMembers() do
        local n, _, sub = GetRaidRosterInfo(i)
        if n then
            members[#members + 1] = { index = i, key = who(n), group = sub }
            counts[sub] = (counts[sub] or 0) + 1
        end
    end
    for _, m in ipairs(members) do
        local g = want[m.key]
        if g and m.group ~= g then
            if (counts[g] or 0) < 5 then
                SetRaidSubgroup(m.index, g)
            else
                for _, o in ipairs(members) do
                    if o.group == g and want[o.key] ~= g then
                        SwapRaidSubgroup(m.index, o.index)
                        break
                    end
                end
            end
            -- continue on the next roster update; a timer backs that up in
            -- case no update arrives (only if no step has run since)
            local token = job.steps
            C_Timer.After(0.5, function()
                if self.arranging == job and job.steps == token then self:ArrangeStep() end
            end)
            return
        end
    end
    self.arranging = nil
    ns.Print("groups arranged")
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
-- A player row: class-coloured name (left aligned, cut off with "..." before
-- the right-side note), note on the right.
local function makeRow(parent, w, onDown, onUp)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(w, SLOT_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Hover(hl, 0.06)
    row.roleBar = row:CreateTexture(nil, "ARTWORK")
    row.roleBar:SetPoint("TOPLEFT", 0, -3)
    row.roleBar:SetPoint("BOTTOMLEFT", 0, 3)
    row.roleBar:SetWidth(3)
    row.roleBar:Hide()
    row.note = UI.Text(row, 10)
    row.note:SetPoint("RIGHT", -8, 0)
    row.note:SetJustifyH("RIGHT")
    row.name = UI.Text(row, 12)
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnMouseDown", onDown)
    row:SetScript("OnMouseUp", onUp)
    row:SetScript("OnEnter", function(r) Roster:ShowTooltip(r.player, r) end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

-- Hovering a raider: rank and level, attendance, recent loot.
function Roster:ShowTooltip(name, row)
    if not name or not GameTooltip or (self.press and self.press.dragging) then return end
    local p = G().players[name]
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(display(name), classColor(p and p.class))
    local role = self:RoleOf(name)
    if role then
        local grp = ns.GROUPS[role]
        GameTooltip:AddLine(grp.label:sub(1, -2), grp.color[1], grp.color[2], grp.color[3])
    end
    if p and p.rank then
        GameTooltip:AddLine(("%s, level %d"):format(p.rank, p.level or 0), 0.7, 0.7, 0.75)
    elseif p and p.manual then
        GameTooltip:AddLine("Not in the guild", 0.7, 0.7, 0.75)
    end
    local att = ns.Attendance and ns.Attendance:Summary()
    if att and att.nights > 0 then
        local a = att.byName[name]
        GameTooltip:AddDoubleLine("Attendance, weeks (4 / 8 / all)",
            a and ("%d%% / %d%% / %d%%"):format(math.floor(a.last4 * 100 + 0.5), math.floor(a.last8 * 100 + 0.5),
                math.floor(a.all * 100 + 0.5)) or "never",
            0.8, 0.8, 0.85, 1, 1, 1)
    end
    local loot = ns.Loot and ns.Loot:Counts()[name]
    if loot then
        GameTooltip:AddDoubleLine("Loot, last 8 nights", ("%d main spec, %d total"):format(loot.ms, loot.total),
            0.8, 0.8, 0.85, 1, 1, 1)
        GameTooltip:AddDoubleLine("Last item", loot.last.link, 0.8, 0.8, 0.85, 1, 1, 1)
    end
    GameTooltip:Show()
end

-- No levels after names (Jake: everyone raiding will be max level).
-- Spot bars: darker when empty, a touch lighter with someone in it.
local WELL_EMPTY = { 0, 0, 0, 0.28 }
local WELL_FILLED = { 1, 1, 1, 0.05 }

function Roster:FillRow(row, name, note, noteColor)
    row.player = name
    if row.well then
        local c = name and WELL_FILLED or WELL_EMPTY
        row.well:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    if not name then
        row.name:SetText("")
        row.note:SetText("")
        row.roleBar:Hide()
        return
    end
    local p = G().players[name]
    local role = self:RoleOf(name)
    if role then
        local c = ns.GROUPS[role].color
        row.roleBar:SetColorTexture(c[1], c[2], c[3], 1)
        row.roleBar:Show()
    else
        row.roleBar:Hide()
    end
    row.name:SetText(display(name))
    row.name:SetTextColor(classColor(p and p.class))
    row.note:SetText(note or "")
    local c = noteColor or { 0.55, 0.55, 0.6 }
    row.note:SetTextColor(c[1], c[2], c[3])
end

local MARK_TEXT = { tent = { "tentative", { 1, 0.82, 0.2 } }, out = { "out", { 0.95, 0.3, 0.3 } } }

function Roster:Build(page)
    self.page = page

    -- Row 1, left: search + rank filter
    local search = UI.EditBox(page, POOL_W - GAP - 80, BAR_H)
    search:SetPoint("TOPLEFT", PAD, -ROW1_Y)
    search.placeholder = UI.Text(search, 11)
    search.placeholder:SetPoint("LEFT", 8, 0)
    search.placeholder:SetTextColor(0.45, 0.45, 0.5)
    search.placeholder:SetText("Search raiders")
    search:SetScript("OnTextChanged", function(box)
        self.search = box:GetText()
        search.placeholder:SetShown(self.search == "")
        self.poolOffset = 0
        self:RefreshPool()
    end)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    self.searchBox = search
    local ranks = UI.Button(page, "Ranks", 80, BAR_H, function(b) UI.ShowMenu(b, self:RankEntries()) end)
    UI.DropArrow(ranks)
    ranks:SetPoint("TOPLEFT", PAD + POOL_W - 80, -ROW1_Y)

    -- Row 1, right: roster picker, name, size
    local pick = UI.Button(page, "Rosters", 110, BAR_H, function(b) UI.ShowMenu(b, self:RosterEntries()) end)
    UI.DropArrow(pick)
    pick:SetPoint("TOPLEFT", RX, -ROW1_Y)
    local nameBox = UI.EditBox(page, 250, BAR_H)
    nameBox:SetPoint("TOPLEFT", RX + 110 + GAP, -ROW1_Y)
    nameBox:SetScript("OnTextChanged", function(box, userInput)
        if not userInput then return end
        local r = self:Current()
        local clean = ns.Codec.CleanText(box:GetText(), ns.Codec.MAX_NAME)
        if r and clean ~= "" then
            r.name = clean
            ns.Touch(r)
        end
    end)
    nameBox:SetScript("OnEnterPressed", nameBox.ClearFocus)
    self.nameBox = nameBox
    -- fills the space between the name and the size buttons
    local sizesX = RX + RW - (#SIZES * 44 + (#SIZES - 1) * 4)
    local delX = RX + 110 + GAP + 250 + GAP
    local del = UI.Button(page, "Delete", sizesX - GAP - delX, BAR_H)
    del:SetScript("OnClick", function(b) UI.ConfirmClick(b, function() self:Delete() end) end)
    del:SetPoint("TOPLEFT", delX, -ROW1_Y)
    self.deleteBtn = del
    self.sizeButtons = {}
    for i, size in ipairs(SIZES) do
        local b = UI.Button(page, tostring(size), 44, BAR_H, function() self:SetSize(size) end)
        b:SetPoint("TOPLEFT", RX + RW - (#SIZES - i + 1) * 44 - (#SIZES - i) * 4, -ROW1_Y)
        self.sizeButtons[size] = b
    end

    -- Row 2, left: pool summary + add
    local add = UI.Button(page, "Add player", 84, BAR_H, function()
        UI.Prompt(self.poolPanel, 0, 0, "Player name (pug or alt)", "", function(text)
            local name = self:AddManual(text)
            if name then self:Add(name) end
        end)
    end)
    add:SetPoint("TOPLEFT", PAD + POOL_W - 84, -ROW2_Y)

    -- Pool list
    local pool = CreateFrame("Frame", nil, page)
    pool:SetPoint("TOPLEFT", PAD, -LIST_Y)
    pool:SetSize(POOL_W, LIST_H)
    UI.Card(pool)
    self.poolArt = ns.Art and ns.Art.Page("roster", pool) -- faint game art (Art.PAGES)
    self.poolHint = UI.ScrollHint(pool, 2, 2)
    pool:EnableMouseWheel(true)
    pool:SetScript("OnMouseWheel", function(_, delta)
        self.poolOffset = (self.poolOffset or 0) - delta * 3
        self:RefreshPool()
    end)
    self.poolPanel = pool
    self.poolEmpty = UI.Text(pool, 11)
    self.poolEmpty:SetPoint("TOP", 0, -24)
    self.poolEmpty:SetTextColor(0.55, 0.55, 0.6)
    self.poolEmpty:SetJustifyH("CENTER")
    self.poolEmpty:Hide()
    self.poolRows = {}
    self.poolVisible = math.floor((LIST_H - 4) / SLOT_H)
    for i = 1, self.poolVisible do
        local row = makeRow(pool, POOL_W - 4,
            function(r, button) self:Press(r, button) end,
            function(r, button) self:Release(r, button, "pool") end)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * SLOT_H)
        -- a small green dot marks who is online; notes sit to its left
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetTexture(ns.MEDIA .. "disc")
        row.dot:SetVertexColor(0.4, 0.85, 0.45, 1)
        row.dot:SetSize(7, 7)
        row.dot:SetPoint("RIGHT", -9, 0)
        row.dot:Hide()
        row.note:ClearAllPoints()
        row.note:SetPoint("RIGHT", -22, 0)
        self.poolRows[i] = row
    end

    -- Groups
    self.groupBoxes, self.slots = {}, {}
    for g = 1, 8 do
        local col, rowN = (g - 1) % GROUP_COLS, math.floor((g - 1) / GROUP_COLS)
        local box = CreateFrame("Frame", nil, page)
        box:SetSize(GROUP_W, GROUP_H)
        box:SetPoint("TOPLEFT", RX + col * (GROUP_W + GAP), -(ROW2_Y + rowN * (GROUP_H + GAP)))
        UI.Card(box)
        box.title = UI.SectionTitle(box, "Group " .. g)
        box.title:SetPoint("TOPLEFT", 8, -6)
        box.count = UI.Text(box, 10)
        box.count:SetPoint("TOPRIGHT", -8, -6)
        box.count:SetTextColor(0.5, 0.5, 0.55)
        self.groupBoxes[g] = box
        self.slots[g] = {}
        for s = 1, 5 do
            local slot = makeRow(box, GROUP_W - 4,
                function(r, button) self:Press(r, button) end,
                function(r, button) self:Release(r, button, "slot") end)
            slot:SetPoint("TOPLEFT", 2, -(GROUP_HEAD + (s - 1) * SLOT_H))
            slot.g, slot.s = g, s
            -- every spot shows as a faint recessed bar, so a group reads as
            -- five places even when empty; the role stripe sits on its edge
            slot.well = slot:CreateTexture(nil, "BACKGROUND")
            slot.well:SetPoint("TOPLEFT", 2, -1)
            slot.well:SetPoint("BOTTOMRIGHT", -2, 1)
            slot.roleBar:ClearAllPoints()
            slot.roleBar:SetPoint("TOPLEFT", 2, -1)
            slot.roleBar:SetPoint("BOTTOMLEFT", 2, 1)
            self.slots[g][s] = slot
        end
    end

    -- Bench: slots line up with the group columns above
    local bench = CreateFrame("Frame", nil, page)
    bench:SetSize(RW, BENCH_H)
    bench:SetPoint("TOPLEFT", RX, -BENCH_Y)
    UI.Card(bench)
    bench.title = UI.SectionTitle(bench, "Bench")
    bench.title:SetPoint("TOPLEFT", 8, -6)
    bench.count = UI.Text(bench, 10)
    bench.count:SetPoint("TOPRIGHT", -8, -6)
    bench.count:SetTextColor(0.5, 0.5, 0.55)
    self.benchBox = bench
    self.benchSlots = {}
    for i = 1, BENCH_SLOTS do
        local col, rowN = (i - 1) % GROUP_COLS, math.floor((i - 1) / GROUP_COLS)
        local slot = makeRow(bench, GROUP_W - 4,
            function(r, button) self:Press(r, button) end,
            function(r, button) self:Release(r, button, "bench") end)
        slot:SetPoint("TOPLEFT", 2 + col * (GROUP_W + GAP), -(GROUP_HEAD + rowN * SLOT_H))
        slot.bench = i
        self.benchSlots[i] = slot
    end

    -- Composition
    local comp = CreateFrame("Frame", nil, page)
    comp:SetSize(RW, COMP_H)
    comp:SetPoint("TOPLEFT", RX, -COMP_Y)
    UI.Card(comp)
    self.compRoles = {}
    local roleW = RW / 5
    self.compTotal = UI.Text(comp, 12)
    self.compTotal:SetPoint("TOPLEFT", 10, -10)
    for i, role in ipairs(Roster.ROLES) do
        local fs = UI.Text(comp, 12)
        fs:SetPoint("TOPLEFT", 10 + i * roleW, -10)
        self.compRoles[role] = fs
    end
    self.compClasses = {}
    for i = 1, 10 do
        local col, rowN = (i - 1) % 5, math.floor((i - 1) / 5)
        local fs = UI.Text(comp, 11)
        fs:SetPoint("TOPLEFT", 10 + col * roleW, -(38 + rowN * 22))
        self.compClasses[i] = fs
    end

    -- Bottom row
    local refresh = UI.Button(page, "Refresh guild", POOL_W, BAR_H, function()
        self:RequestGuild()
        self:Refresh()
    end)
    refresh:SetPoint("TOPLEFT", PAD, -BOTTOM_Y)
    local clear = UI.Button(page, "Clear", 70, BAR_H)
    clear:SetScript("OnClick", function(b) UI.ConfirmClick(b, function() self:Clear() end) end)
    clear:SetPoint("TOPLEFT", RX, -BOTTOM_Y)
    local inviteBtn = UI.Button(page, "Invite roster", 120, BAR_H, function() self:Invite() end)
    inviteBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -BOTTOM_Y)
    inviteBtn:SetPrimary()
    local arrange = UI.Button(page, "Arrange groups", 120, BAR_H, function() self:Arrange() end)
    arrange:SetPoint("RIGHT", inviteBtn, "LEFT", -4, 0)
    local copyBtn = UI.Button(page, "Copy for Discord", 130, BAR_H, function()
        UI.CopyBox("Roster for Discord", self:DiscordText())
    end)
    copyBtn:SetPoint("RIGHT", arrange, "LEFT", -4, 0)

    -- drag ghost
    local ghost = CreateFrame("Frame", nil, page)
    ghost:SetSize(140, SLOT_H)
    ghost:SetFrameStrata("TOOLTIP")
    UI.Panel(ghost, { 0.08, 0.14, 0.18, 0.95 }, UI.ACCENT)
    ghost.text = UI.Text(ghost, 12)
    ghost.text:SetPoint("LEFT", 8, 0)
    ghost:Hide()
    self.ghost = ghost
end

------------------------------------------------------------------------
-- Mouse: click adds/removes, drag moves, right-click opens a menu
------------------------------------------------------------------------
function Roster:Press(row, button)
    if button ~= "LeftButton" or not row.player then return end
    local x, y = GetCursorPosition()
    self.press = { row = row, name = row.player, x = x, y = y }
    self.page:SetScript("OnUpdate", function() self:DragUpdate() end)
end

function Roster:DragUpdate()
    local p = self.press
    if not p then return end
    local x, y = GetCursorPosition()
    if not p.dragging and (math.abs(x - p.x) > DRAG_PX or math.abs(y - p.y) > DRAG_PX) then
        p.dragging = true
        self.ghost.text:SetText(display(p.name))
        self.ghost.text:SetTextColor(classColor(G().players[p.name] and G().players[p.name].class))
        self.ghost:Show()
    end
    if p.dragging then
        local s = UIParent:GetEffectiveScale()
        self.ghost:ClearAllPoints()
        self.ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 12, y / s)
    end
end

function Roster:TargetUnderCursor()
    for g = 1, self:Groups() do
        for s = 1, 5 do
            if self.slots[g][s]:IsMouseOver() then return { kind = "slot", g = g, s = s } end
        end
        if self.groupBoxes[g]:IsMouseOver() then return { kind = "group", g = g } end
    end
    if self.benchBox:IsMouseOver() then return { kind = "bench" } end
    if self.poolPanel:IsMouseOver() then return { kind = "pool" } end
end

function Roster:Release(row, button, from)
    local p = self.press
    self.press = nil
    self.page:SetScript("OnUpdate", nil)
    self.ghost:Hide()
    if button == "RightButton" then
        if from == "pool" and row.player then
            UI.ShowMenu(row, self:PlayerEntries(row.player))
        elseif row.player then
            self:Remove(row.player)
            self:Changed()
        end
        return
    end
    if not p then return end
    if p.dragging then
        self:Drop(p.name, self:TargetUnderCursor())
    elseif from == "pool" then
        self:Add(p.name)
    end
end

------------------------------------------------------------------------
-- Menus
------------------------------------------------------------------------
function Roster:PlayerEntries(name)
    local r = self:Current()
    local mark = r and r.marks[name]
    local role = self:RoleOf(name)
    local e = {
        { text = display(name), header = true },
        { text = (not mark and "> " or "   ") .. "Available", func = function() self:SetMark(name, nil) end },
        { text = (mark == "tent" and "> " or "   ") .. "Tentative", func = function() self:SetMark(name, "tent") end },
        { text = (mark == "out" and "> " or "   ") .. "Out", func = function() self:SetMark(name, "out") end },
        { text = "Role", header = true },
    }
    for _, k in ipairs(Roster.ROLES) do
        local grp = ns.GROUPS[k]
        e[#e + 1] = { text = (role == k and "> " or "   ") .. grp.label:sub(1, -2), color = grp.color,
            func = function() self:SetRole(name, k) end }
    end
    if ns.Profiles:HasAddon(name) then
        table.insert(e, 2, { text = "View profile", func = function() ns.Profiles:Open(name) end })
    end
    e[#e + 1] = { text = (not role and "> " or "   ") .. "No role", func = function() self:SetRole(name, nil) end }
    local p = G().players[name]
    if p and p.manual then
        e[#e + 1] = { text = "Remove from pool", color = { 0.95, 0.4, 0.4 }, func = function()
            self:Remove(name)
            G().players[name] = nil
            if ns.Attendance then ns.Attendance.keyCache = nil end
            self:Changed()
        end }
    end
    return e
end

function Roster:RankEntries()
    local g = G()
    local e = { { text = "Raider ranks", header = true } }
    local numRanks = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 10
    for i = 1, numRanks do
        local rankName = GuildControlGetRankName(i)
        if rankName and rankName ~= "" then
            local idx = i - 1 -- GetGuildRosterInfo's rankIndex starts at 0
            local on = not g.ranks or g.ranks[idx]
            e[#e + 1] = { text = (on and "[x] " or "[  ] ") .. rankName, func = function() self:ToggleRank(idx, numRanks) end }
        end
    end
    e[#e + 1] = { text = (g.maxLevelOnly and "[x] " or "[  ] ") .. ("Max level only (%d)"):format(maxLevel()), func = function()
        g.maxLevelOnly = not g.maxLevelOnly
        self:Refresh()
    end }
    return e
end

function Roster:ToggleRank(idx, numRanks)
    local g = G()
    if not g.ranks then
        g.ranks = {}
        for i = 0, numRanks - 1 do g.ranks[i] = true end
    end
    g.ranks[idx] = not g.ranks[idx] or nil
    self.poolOffset = 0
    self:Refresh()
end

function Roster:RosterEntries()
    local e = {}
    local cur = self:Current()
    for _, r in ipairs(self:List()) do
        e[#e + 1] = { text = r.name, color = (cur and r.id == cur.id) and UI.ACCENT or nil,
            func = function() self:Select(r.id) end }
    end
    e[#e + 1] = { text = "New roster", color = { 0.6, 0.85, 0.6 }, func = function() self:New() end }
    if cur then
        e[#e + 1] = { text = "Duplicate this roster", func = function() self:New(cur) end }
    end
    return e
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function Roster:Refresh()
    if not self.page then return end
    local r = self:Current()
    if not r then return end
    if not self.nameBox:HasFocus() then self.nameBox:SetText(r.name) end
    for size, b in pairs(self.sizeButtons) do b:SetSelected(size == r.size) end

    local groups = self:Groups()
    for g = 1, 8 do
        local box = self.groupBoxes[g]
        box:SetShown(g <= groups)
        local n = 0
        for s = 1, 5 do
            local name = r.groups[g][s]
            if name then n = n + 1 end
            local mark = name and MARK_TEXT[r.marks[name]]
            self:FillRow(self.slots[g][s], name, mark and mark[1], mark and mark[2])
        end
        box.count:SetText(n > 0 and (n .. "/5") or "")
    end
    for i, slot in ipairs(self.benchSlots) do
        local name = r.bench[i]
        local mark = name and MARK_TEXT[r.marks[name]]
        self:FillRow(slot, name, mark and mark[1], mark and mark[2])
    end
    local extra = #r.bench - BENCH_SLOTS
    self.benchBox.count:SetText(#r.bench == 0 and "" or (#r.bench .. (extra > 0 and (" (" .. extra .. " not shown)") or "")))

    local roles, classes, total = self:Composition()
    self.compTotal:SetText(("%d / %d"):format(total, r.size))
    for role, fs in pairs(self.compRoles) do
        local grp = ns.GROUPS[role]
        fs:SetText(("%s %d"):format(grp.label, roles[role]))
        fs:SetTextColor(grp.color[1], grp.color[2], grp.color[3])
    end
    local i = 0
    for _, class in ipairs(CLASS_ORDER) do
        if classes[class] then
            i = i + 1
            local fs = self.compClasses[i]
            if fs then
                local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class:sub(1, 1) .. class:sub(2):lower()
                fs:SetText(("%s %d"):format(label, classes[class]))
                fs:SetTextColor(classColor(class))
            end
        end
    end
    for j = i + 1, #self.compClasses do self.compClasses[j]:SetText("") end

    self:RefreshPool()
end

function Roster:RefreshPool()
    if not self.page then return end
    local r = self:Current()
    local names = self:PoolNames()
    self.poolOffset = clamp(self.poolOffset or 0, 0, math.max(0, #names - self.poolVisible))
    self.poolHint:Set(self.poolOffset, self.poolVisible, #names)
    if #names == 0 then
        if not IsInGuild() then
            self.poolEmpty:SetText("You are not in a guild.\nUse Add player for pugs.")
        elseif self.search and self.search ~= "" then
            self.poolEmpty:SetText("Nobody matches that search.")
        else
            self.poolEmpty:SetText("No raiders match the filters.\nOpen Ranks to change them.")
        end
    end
    self.poolEmpty:SetShown(#names == 0)
    for i, row in ipairs(self.poolRows) do
        local name = names[i + self.poolOffset]
        local note, color
        if name then
            local where, a = self:Locate(name)
            local mark = r and MARK_TEXT[r.marks[name]]
            if where == "group" then
                note = "G" .. a
            elseif where == "bench" then
                note = "bench"
            elseif mark then
                note, color = mark[1], mark[2]
            end
            row:SetAlpha((where or (r and r.marks[name] == "out")) and 0.45 or 1)
        end
        self:FillRow(row, name, note, color)
        row.dot:SetShown(name ~= nil and self.online[name] == true)
        row:SetShown(name ~= nil)
    end
end

------------------------------------------------------------------------
-- Events and tab
------------------------------------------------------------------------
ns.On("GUILD_ROSTER_UPDATE", function()
    Roster:ScanGuild()
    if Roster.page and Roster.page:IsVisible() then Roster:Refresh() end
end)
ns.On("GROUP_ROSTER_UPDATE", function() Roster:OnGroupChanged() end)
ns.OnGuildChanged(function() wipe(Roster.online) end)
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(5, function() Roster:RequestGuild() end)
end)

ns.Editor:RegisterTab("roster", "Roster", 1,
    function(page) Roster:Build(page) end,
    function()
        if not Roster:Current() then Roster:New() end
        Roster:RequestGuild()
        Roster:Refresh()
    end, "raid")
