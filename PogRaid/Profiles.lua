-- Pog Raid profiles: a page for every guild member, MySpace style.
--
-- One profile per account: status, About Me, favorites, main role, portrait,
-- color and song are kept in PogRaidDB.account and every character of the
-- account shares them in its own `profile` record, with the list of the
-- account's characters ("chars"). Two characters count as one account only
-- when each one's record lists the other, so nobody can attach themselves to
-- someone else's page. Where the account's records differ, the newest edit
-- ("ed") wins; a character joins once it has logged in with Pog Raid.
--
-- A profile goes by the account's highest level character (its Main), or a
-- nickname the owner sets; the Main's name always shows with a nickname, so
-- nobody can pass as someone else. Whichever character you open, you see the
-- account's page; its Professions card starts on that character.
--
-- Profiles show only for accounts confirmed to run Pog Raid (we've heard
-- their addon, or they've shared a record).
--
-- Most played with: the five guild accounts this account spends the most
-- time grouped with (other accounts' characters added together). Automatic.
--
-- Kudos: give someone a kudos of a kind (Clutch heals, Great tank, ...) with
-- a short message, once a week per kind; one `kudos` record per giver, kind
-- and receiver counts up and keeps the latest message. Profiles list the
-- latest kudos only: no counts for anyone else to see.
--
-- Professions: the character's two main professions (shared by Crafting);
-- click one to browse their recipes.
--
-- Layout (902 x 608 window):
--   [search      ]  [portrait  name, info, status          buttons, song]
--   [members     ]  [About me, characters, favorites]  [Character: model ]
--   [            ]  [Professions                    ]  [   Inspect       ]
--   [            ]  [Most played with               ]  [Kudos (latest)   ]
--   [My profile  ]
local _, ns = ...
local UI = ns.UI
local Sync = ns.Sync

local Profiles = {}
ns.Profiles = Profiles

Profiles.MAX_STATUS = 60
Profiles.MAX_ABOUT = 300
Profiles.MAX_FAV = 40
Profiles.MAX_NICK = 20
Profiles.TOP = 5
Profiles.TICK = 60                -- seconds between group checks
Profiles.CHECK_EVERY = 600        -- our record re-checked (and shared if changed) this often
Profiles.MIN_TOGETHER = 600       -- grouped this long before someone makes your Most played with
Profiles.CLASSIC_ICONS = 140000
Profiles.MAX_CHARS = 10
Profiles.KUDOS_MAX = 520          -- ten years of weekly kudos
Profiles.MAX_KUDOS_MSG = 80

-- Portraits are icon file IDs. These come first in the picker (the first
-- nine are the class defaults); the classic-art icons the client offers for
-- macros follow (file IDs below CLASSIC_ICONS: the original game's art, about
-- 4,000 of them, against 30,000+ in all).
Profiles.ICONS = {
    { 135328, "Warrior" }, { 132325, "Paladin" }, { 135495, "Hunter" }, { 135428, "Rogue" },
    { 135167, "Priest" }, { 136012, "Shaman" }, { 135150, "Mage" }, { 136020, "Warlock" },
    { 134297, "Druid" }, { 135812, "Fire" }, { 135846, "Frost" }, { 135920, "Holy" },
    { 136197, "Shadow" }, { 136048, "Lightning" }, { 136096, "Starfall" }, { 135940, "Shield" },
    { 134153, "Dragon head" }, { 135349, "Thunderfury" }, { 133066, "Sulfuras" }, { 132767, "Crown" },
    { 134952, "Shield wall" }, { 133730, "Skull" }, { 136187, "Raise dead" }, { 133884, "Eye" },
    { 134169, "Murloc" }, { 134170, "Orc" }, { 134164, "Gnome" }, { 136071, "Sheep" },
    { 132203, "Wolf" }, { 132267, "Tiger" }, { 132261, "Horse" }, { 132276, "Bear" },
    { 133784, "Gold" }, { 133639, "Bag" }, { 134414, "Hearthstone" }, { 132932, "Fishing" },
    { 134708, "Mining" }, { 133939, "Flower" }, { 134532, "Mushroom" }, { 132792, "Drink" },
    { 133712, "Bomb" }, { 134481, "Darkmoon ticket" }, { 135458, "Chocolate" }, { 133838, "Kite" },
    { 134140, "Present" }, { 133971, "Fish dinner" }, { 136210, "Soulstone" }, { 133574, "Scarab" },
}
local CLASS_ICON = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 6, MAGE = 7,
    WARLOCK = 8, DRUID = 9 }
local NO_ICON = 134400 -- question mark

-- Theme colors. Index goes over the wire; 0 (or unknown) is the class color.
Profiles.COLORS = {
    { 0.40, 0.80, 1.00, "Pog blue" }, { 0.95, 0.30, 0.30, "Red" }, { 1.00, 0.55, 0.15, "Orange" },
    { 1.00, 0.82, 0.20, "Gold" }, { 0.35, 0.90, 0.40, "Green" }, { 0.25, 0.85, 0.75, "Teal" },
    { 0.70, 0.45, 1.00, "Purple" }, { 1.00, 0.45, 0.75, "Pink" }, { 0.78, 0.80, 0.85, "Silver" },
}

-- Profile songs: classic music by file ID. Index goes over the wire.
Profiles.SONGS = {
    { 53223, "Main Theme" }, { 53211, "Stormwind" }, { 53191, "Ironforge" }, { 53183, "Darnassus" },
    { 53201, "Orgrimmar" }, { 53212, "Thunder Bluff" }, { 53219, "Undercity" }, { 53492, "Elwynn Forest" },
    { 53299, "The Barrens" }, { 53680, "Mulgore" }, { 53486, "Duskwood" }, { 53541, "Stranglethorn Vale" },
    { 53577, "Dun Morogh" }, { 53453, "Ashenvale" }, { 53432, "Tanaris" }, { 53695, "Swamp of Sorrows" },
    { 53426, "Plaguelands" }, { 53254, "Zul'Gurub" }, { 53269, "Ahn'Qiraj" }, { 53614, "Naxxramas" },
    { 53225, "Battle" },
}

-- Kudos kinds: icon file ID and name. Index goes over the wire: only add; a
-- kind taken out stays as `retired` (no longer shown or given).
Profiles.KUDOS = {
    { 135907, "Clutch heals" }, { 132341, "Great tank" }, { 135808, "Big damage" }, { 132245, "Carried me" },
    { 135970, "Helpful" }, { 133785, "Generous" }, { 132333, "Great leader" }, { 136071, "Funny", retired = true },
    { 132483, "GGWP" },
}

-- Main roles: key on the wire, label, color. (M and R, from test builds, read as DPS.)
Profiles.ROLES = {
    { "D", "DPS", { 0.95, 0.35, 0.30 } }, { "T", "Tank", { 0.45, 0.70, 1.00 } }, { "H", "Heals", { 0.35, 0.90, 0.40 } },
}
local ROLE = { D = 1, T = 2, H = 3, M = 1, R = 1 }

-- Main professions only; secondary ones aren't shown.
Profiles.PROF_ICONS = { Alchemy = 136240, Blacksmithing = 136241, Enchanting = 136244, Engineering = 136243,
    Leatherworking = 136247, Tailoring = 136249, Herbalism = 136246, Mining = 136248, Skinning = 134366 }
Profiles.SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true, Archaeology = true }

local CONTENT = { "status", "about", "role", "icon", "color", "song", "fav1", "fav2", "nick", "off" }
local FIELDS = { "status", "about", "role", "icon", "color", "song", "fav1", "fav2", "nick", "ed", "chars", "top", "off" }
local FAVORITES = { { "fav1", "Favorite raid" }, { "fav2", "Favorite dungeon" } }

local function G() return ns.db.guild end
local function me() return Sync:Me() end
local function display(name) return name and Ambiguate(name, "short") end
local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function clean(s, max) return ns.Codec.CleanText(s, max) end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end

local function classColor(name)
    local p = G().players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if c then return c.r, c.g, c.b end
    return 0.75, 0.75, 0.78
end

local function colorName(name)
    local r, g, b = classColor(name)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, display(name))
end

local function inGuild(name)
    local p = name and G().players[name]
    return p ~= nil and p.inGuild == true
end

------------------------------------------------------------------------
-- Shared records
------------------------------------------------------------------------
local function changed() Profiles:Changed() end

local function sane(rec, fields)
    for f, max in pairs(fields) do
        local v = rec[f]
        if v ~= nil and (type(v) ~= "string" or #v > max) then return false end
    end
    return true
end

local function whole(v, lo, hi)
    return v == nil or (v == math.floor(v) and v >= lo and v <= hi)
end

Sync:Register({
    name = "profile", code = "u", order = 3,
    fields = FIELDS,
    numeric = { icon = true, color = true, song = true, ed = true },
    -- your own record only. Color and song numbers past today's lists are
    -- kept (a newer version may have more) and shown as the default.
    valid = function(rec)
        local M, F = Profiles.MAX_STATUS, Profiles.MAX_FAV
        return rec.by == rec.author and rec.id == rec.author
            and sane(rec, { status = M, about = Profiles.MAX_ABOUT, role = 1, off = 1, fav1 = F, fav2 = F, nick = Profiles.MAX_NICK,
                chars = Profiles.MAX_CHARS * 49, top = Profiles.TOP * 81 })
            and whole(rec.icon, 1, 1e8) and whole(rec.color, 0, 99) and whole(rec.song, 0, 999)
            and whole(rec.ed, 0, 2 ^ 36)
    end,
    onChange = changed,
})

Sync:Register({
    name = "kudos", code = "q", order = 3,
    fields = { "to", "kind", "n", "wk", "msg" },
    numeric = { kind = true, n = true, wk = true },
    -- only the giver writes it, never to themselves, always with a message
    valid = function(rec)
        return rec.by == rec.author and type(rec.to) == "string" and #rec.to <= 80 and rec.to ~= rec.author
            and rec.kind ~= nil and whole(rec.kind, 1, 99) and rec.n ~= nil and whole(rec.n, 0, Profiles.KUDOS_MAX)
            and rec.wk ~= nil and whole(rec.wk, 0, 1e6) and rec.id == rec.author .. ":" .. rec.kind .. ":" .. rec.to
            and type(rec.msg) == "string" and rec.msg ~= "" and #rec.msg <= Profiles.MAX_KUDOS_MSG
    end,
    onChange = changed,
})

-- A character's shared record, or nil.
function Profiles:Get(name)
    local rec = name and (Sync:Store("profile") or {})[name]
    if rec and not rec.deleted then return rec end
end

------------------------------------------------------------------------
-- Our account: PogRaidDB.account = { content, ed, chars = { [guild] = {
-- [name] = last seen } }, together }
------------------------------------------------------------------------
function Profiles:Mine()
    local a = ns.db.account
    if a then return a end
    a = { content = {}, chars = {}, together = {} }
    ns.db.account = a
    -- test builds of 0.13 kept Most played with per character, profiles per
    -- character and a wall
    for _, d in pairs(ns.db.profiles or {}) do
        for k, sec in pairs(d.together or {}) do a.together[k] = (a.together[k] or 0) + sec end
    end
    ns.db.profiles = nil
    local newest
    for _, g in pairs(ns.db.sync or {}) do
        g.wall = nil
        for _, name in pairs(ns.db.selfNames or {}) do
            local rec = g.profile and g.profile[name]
            if rec and not rec.deleted and (not newest or rec.rev > newest.rev) then newest = rec end
        end
    end
    if newest then
        for _, f in ipairs(CONTENT) do a.content[f] = newest[f] end
        a.ed = newest.rev
    end
    return a
end

-- Remember this character as one of the account's (once the guild roster
-- knows our full name).
function Profiles:NoteChar()
    local guild, who = Sync:GuildName(), me()
    if not guild or not inGuild(who) then return end
    local a = self:Mine()
    a.chars[guild] = a.chars[guild] or {}
    a.chars[guild][who] = ns.Now()
end

-- Our characters in this guild (the most recent MAX_CHARS), us included.
function Profiles:MyChars()
    local guild = Sync:GuildName()
    local list = guild and self:Mine().chars[guild] or {}
    local out = {}
    for name in pairs(list) do out[#out + 1] = name end
    table.sort(out, function(x, y)
        if list[x] ~= list[y] then return list[x] > list[y] end
        return x < y
    end)
    for i = #out, Profiles.MAX_CHARS + 1, -1 do out[i] = nil end
    local who, found = me(), false
    for _, n in ipairs(out) do found = found or n == who end
    if not found then table.insert(out, 1, who) end
    return out
end

function Profiles:IsMine(name)
    if name == me() then return true end
    local guild = Sync:GuildName()
    local list = guild and self:Mine().chars[guild]
    return list ~= nil and list[name] ~= nil
end

-- One of our characters isn't ours any more (deleted, renamed, given away).
function Profiles:Forget(name)
    local guild = Sync:GuildName()
    local list = guild and self:Mine().chars[guild]
    if not list or name == me() then return end
    list[name] = nil
    self:Publish()
end

local function lists(rec, name)
    return rec ~= nil and rec.chars ~= nil and ("," .. rec.chars .. ","):find("," .. name .. ",", 1, true) ~= nil
end

-- name -> characters whose records list it (built once per page refresh).
function Profiles:Claims()
    local memo = self.memo
    if memo and memo.__claims then return memo.__claims end
    local claims = {}
    for id, rec in pairs(Sync:Store("profile") or {}) do
        if not rec.deleted and rec.chars then
            for c in rec.chars:gmatch("[^,]+") do
                if c ~= id then
                    claims[c] = claims[c] or {}
                    table.insert(claims[c], id)
                end
            end
        end
    end
    if memo then memo.__claims = claims end
    return claims
end

-- The characters on `name`'s account (ours: the ones we've played). Always
-- starts with `name`. Two records are one account when they list each other,
-- or when one lists the other and the other was last shared before the
-- account knew about it (no list yet) with the very same profile edit.
function Profiles:Linked(name)
    local memo = self.memo -- only while the page refreshes
    if memo and memo[name] then return memo[name] end
    local out = { name }
    if self:IsMine(name) then
        for _, c in ipairs(self:MyChars()) do
            if c ~= name then out[#out + 1] = c end
        end
    else
        local rec = self:Get(name)
        local seen = { [name] = true }
        local function consider(c)
            if seen[c] then return end
            seen[c] = true
            local other = self:Get(c)
            if not rec or not other then return end
            local mine, theirs = lists(rec, c), lists(other, name)
            local sameEdit = rec.ed ~= nil and rec.ed == other.ed
            if (mine and theirs) or (theirs and not rec.chars and sameEdit) or (mine and not other.chars and sameEdit) then
                out[#out + 1] = c
            end
        end
        for c in tostring(rec and rec.chars or ""):gmatch("[^,]+") do consider(c) end
        for _, c in ipairs(self:Claims()[name] or {}) do consider(c) end
    end
    if memo then memo[name] = out end
    return out
end

-- Who stands for an account in lists: its highest level guild member.
function Profiles:Main(name)
    local best, bestLevel
    for _, c in ipairs(self:Linked(name)) do
        local p = G().players[c]
        if p and p.inGuild then
            local l = p.level or 0
            if not best or l > bestLevel or (l == bestLevel and c < best) then best, bestLevel = c, l end
        end
    end
    return best or name
end

-- Pog Raid confirmed on `name`'s account: we've heard their addon (version
-- check, sync fingerprints) or they've shared a profile or professions.
function Profiles:HasAddon(name)
    if not name then return false end
    if self:IsMine(name) then return true end
    local versions = ns.db.versions or {}
    local seen = ns.Version and ns.Version.seen or {}
    local profs = Sync:Store("profs") or {}
    local gear = Sync:Store("gear") or {}
    for _, c in ipairs(self:Linked(name)) do
        if versions[c] or seen[c] or self:Get(c) or (profs[c] and not profs[c].deleted)
            or (gear[c] and not gear[c].deleted) then return true end
    end
    return false
end

-- The account's profile content: ours as saved, others' newest edit.
function Profiles:Content(name)
    if self:IsMine(name) then return self:Mine().content end
    local best
    for _, c in ipairs(self:Linked(name)) do
        local rec = self:Get(c)
        if rec and (not best or (rec.ed or 0) > (best.ed or 0)
            or ((rec.ed or 0) == (best.ed or 0) and rec.rev > best.rev)) then
            best = rec
        end
    end
    return best or {}
end

-- What a profile goes by: its nickname, else its Main's name. `full` adds
-- the Main's name after a nickname ("Jake (Flyne Lee)").
function Profiles:Name(name, full)
    local main = self:Main(name)
    local nick = self:Content(main).nick
    if not nick then return display(main) end
    return full and ("%s (%s)"):format(nick, display(main)) or nick
end

-- Change our profile. `changes` maps field -> value; false or "" clears it.
function Profiles:Save(changes)
    local a = self:Mine()
    for k, v in pairs(changes) do
        if v == false or v == "" then a.content[k] = nil else a.content[k] = v end
    end
    a.ed = ns.Now()
    self:Publish()
    self:Changed()
end

-- Share our record if it differs from what it should be: the account's
-- profile, our characters and Most played with. Someone with nothing to
-- show yet shares nothing.
function Profiles:Publish()
    if not Sync:GuildName() then return end
    self:NoteChar()
    local a = self:Mine()
    local who = me()
    local want = {}
    for _, f in ipairs(CONTENT) do want[f] = a.content[f] end
    want.ed = a.ed
    local chars = self:MyChars()
    table.sort(chars)
    want.chars = #chars > 1 and table.concat(chars, ",") or nil
    local top = table.concat(self:TopNames(), ",")
    want.top = top ~= "" and top or nil
    local cur = self:Get(who)
    if cur then
        local same = true
        for _, f in ipairs(FIELDS) do
            if cur[f] ~= want[f] then same = false end
        end
        if same then return end
    else
        local any = false
        for _, f in ipairs(FIELDS) do any = any or want[f] ~= nil end
        if not any then return end
    end
    local rec = { id = who, author = who, t = cur and cur.t or ns.Now() }
    for _, f in ipairs(FIELDS) do rec[f] = want[f] end
    Sync:Write("profile", rec)
    self:Changed()
end

function Profiles:Portrait(name)
    local icon = self:Content(name).icon
    if icon then return icon end
    local p = G().players[name]
    local i = p and p.class and CLASS_ICON[p.class]
    return i and self.ICONS[i][1] or NO_ICON
end

function Profiles:Color(name)
    local i = self:Content(name).color
    local c = i and self.COLORS[i]
    if c then return c[1], c[2], c[3] end
    return classColor(name)
end

function Profiles:Song(name)
    local i = self:Content(name).song
    return i and self.SONGS[i]
end

------------------------------------------------------------------------
-- Most played with: time grouped (per account)
------------------------------------------------------------------------
-- Guild members in our group right now (not us).
function Profiles:GroupMates()
    local out = {}
    if not IsInGroup() then return out end
    local seen = {}
    local function add(name)
        if not name or secret(name) then return end
        local k = ns.Attendance:Key(name)
        if not seen[k] and inGuild(k) and not self:IsMine(k) then
            seen[k] = true
            out[#out + 1] = k
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if online ~= false then add(name) end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if not (UnitIsConnected and UnitIsConnected(unit) == false) then add(GetUnitName(unit, true)) end
        end
    end
    return out
end

function Profiles:Tick()
    local t = self:Mine().together
    for _, k in ipairs(self:GroupMates()) do t[k] = (t[k] or 0) + Profiles.TICK end
    local now = GetTime()
    if now - (self.checkedAt or -1e9) >= Profiles.CHECK_EVERY then
        self.checkedAt = now
        self:Publish()
    end
end

-- Our Most played with: the accounts we've grouped with most, each
-- account's characters added together. Second result: seconds together per
-- account (by its Main).
function Profiles:TopNames()
    local a = self:Mine()
    local totals = {}
    for k, sec in pairs(a.together) do
        if inGuild(k) and not self:IsMine(k) then
            local m = self:Main(k)
            totals[m] = (totals[m] or 0) + sec
        end
    end
    local out = {}
    for m, sec in pairs(totals) do
        if sec >= Profiles.MIN_TOGETHER then out[#out + 1] = m end
    end
    table.sort(out, function(x, y)
        if totals[x] ~= totals[y] then return totals[x] > totals[y] end
        return x < y
    end)
    for i = #out, Profiles.TOP + 1, -1 do out[i] = nil end
    return out, totals
end

-- Most played with as shown on a profile: ours live, everyone else's as
-- their account last shared it.
-- Everyone we've grouped with, most time first: { { main, seconds } }.
function Profiles:Together()
    local _, totals = self:TopNames()
    local out = {}
    for m, sec in pairs(totals) do
        if sec >= 60 then out[#out + 1] = { m, sec } end
    end
    table.sort(out, function(x, y)
        if x[2] ~= y[2] then return x[2] > y[2] end
        return x[1] < y[1]
    end)
    return out
end

function Profiles.Duration(sec)
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    return m > 0 and (h .. "h " .. m .. "m") or (h .. "h")
end

function Profiles:Top(name)
    if self:IsMine(name) then return (self:TopNames()) end
    local newest
    for _, c in ipairs(self:Linked(name)) do
        local rec = self:Get(c)
        if rec and (not newest or rec.rev > newest.rev) then newest = rec end
    end
    local out = {}
    for k in tostring(newest and newest.top or ""):gmatch("[^,]+") do
        if #out < Profiles.TOP then out[#out + 1] = k end
    end
    return out
end

------------------------------------------------------------------------
-- Kudos
------------------------------------------------------------------------
-- Weeks counted from the weekly reset (Tuesday 15:00 UTC).
Profiles.Week = ns.Week

-- Kudos to an account: per kind { n, givers, gave = we gave it this week },
-- the latest records, the total and how many accounts gave. Kudos between
-- the account's own characters don't count.
function Profiles:Kudos(name)
    local group = {}
    for _, c in ipairs(self:Linked(name)) do group[c] = true end
    local kinds, recent, givers, total = {}, {}, {}, 0
    for i = 1, #Profiles.KUDOS do kinds[i] = { n = 0, givers = {} } end
    local week = Profiles.Week()
    for _, rec in pairs(Sync:Store("kudos") or {}) do
        local k = kinds[rec.kind]
        local kind = Profiles.KUDOS[rec.kind]
        if k and not kind.retired and not rec.deleted and rec.n > 0 and group[rec.to] and not group[rec.author] then
            local giver = self:Main(rec.author)
            k.n = k.n + rec.n
            k.givers[giver] = true
            givers[giver] = true
            total = total + rec.n
            if self:IsMine(rec.author) and rec.wk == week then k.gave = rec end
            recent[#recent + 1] = rec
        end
    end
    table.sort(recent, function(x, y)
        if x.rev ~= y.rev then return x.rev > y.rev end
        if x.t ~= y.t then return x.t > y.t end
        return x.id < y.id
    end)
    return kinds, recent, total, ns.Count(givers)
end

-- Give `name` a kudos of `kind` with a message (required), or take back
-- the one we gave this week (no message needed). Returns true (given), false
-- (taken back) or nil (not allowed).
function Profiles:GiveKudos(name, kind, msg)
    local kindInfo = Profiles.KUDOS[kind]
    if not Sync:GuildName() or not name or self:IsMine(name) or not kindInfo or kindInfo.retired then return nil end
    local kinds = self:Kudos(name)
    local week = Profiles.Week()
    local given = kinds[kind].gave
    if given then
        if given.author ~= me() then
            ns.Print(("you gave that from %s this week"):format(display(given.author)))
            return nil
        end
        local c = {}
        for k, v in pairs(given) do c[k] = v end
        c.n, c.wk = math.max(0, given.n - 1), week - 1
        Sync:Write("kudos", c)
        self:Changed()
        return false
    end
    msg = clean(msg, Profiles.MAX_KUDOS_MSG)
    if msg == "" then return nil end
    local id = me() .. ":" .. kind .. ":" .. name
    local cur = (Sync:Store("kudos") or {})[id]
    Sync:Write("kudos", { id = id, author = me(), t = cur and cur.t or ns.Now(), to = name, kind = kind,
        n = math.min(Profiles.KUDOS_MAX, (cur and not cur.deleted and cur.n or 0) + 1), wk = week, msg = msg })
    self:Changed()
    return true
end

------------------------------------------------------------------------
-- Professions
------------------------------------------------------------------------
-- A character's main professions (at most two): { name, rank, max, icon,
-- recipes = count or nil, gathering = no recipes to show }.
function Profiles:Professions(name)
    local rec = (Sync:Store("profs") or {})[name]
    local recipes = Sync:Store("recipes") or {}
    local out = {}
    for _, p in ipairs(ns.Crafting.ParseList(rec and not rec.deleted and rec.list)) do
        if not Profiles.SECONDARY[p.name] and #out < 2 then
            local r = recipes[name .. ":" .. p.name]
            p.icon = Profiles.PROF_ICONS[p.name] or NO_ICON
            p.recipes = (r and not r.deleted) and #r.ids / 4 or nil
            p.gathering = ns.Crafting.NO_RECIPES[p.name] == true
            out[#out + 1] = p
        end
    end
    return out
end

------------------------------------------------------------------------
-- Profile song
------------------------------------------------------------------------
function Profiles:PlaySong(song)
    self:StopSong()
    if not song or not PlayMusic then return end
    if pcall(PlayMusic, song[1]) then self.playing = song end
end

function Profiles:StopSong()
    if not self.playing then return end
    self.playing = nil
    if StopMusic then pcall(StopMusic) end
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local PAD, GAP, TITLE_H, BAR_H = 12, 8, 30, 26
local FRAME_W, FRAME_H = 902, ns.PAGE_H
local LEFT_W = 262
local RX = PAD + LEFT_W + PAD
local RW = FRAME_W - RX - PAD
local LIST_Y = TITLE_H + BAR_H + GAP
local BOTTOM_Y = FRAME_H - PAD - BAR_H
local LIST_H = BOTTOM_Y - GAP - LIST_Y
local MEMBER_H = 36
local HEAD_H = 26
local BANNER_H = 104
local BODY_Y = TITLE_H + BANNER_H + GAP
local BODY_H = FRAME_H - PAD - BODY_Y
local COL_W = (RW - GAP) / 2
local COL2_X = RX + COL_W + GAP
local ABOUT_H = 166
local TOP5_H = 100
local PROFS_H = BODY_H - ABOUT_H - TOP5_H - 2 * GAP
local TOP_Y = BODY_Y + ABOUT_H + GAP + PROFS_H + GAP  -- Most played with, under Professions
local CHAR_H = 248                   -- the current character's model, Inspect under it
local KUDOS_H = BODY_H - CHAR_H - GAP
local PORTRAIT = 72
local TILE_W, TILE_ICON = 54, 34
local TILE_GAP = 6
local INFO_ROW_H = 18
local INFO_H = 3 * INFO_ROW_H + 10   -- bottom of the About me card: characters + two favorites
local KUDOS_ROW_H = 38
local BOOK_ROW_H = 20

Profiles.layout = { RX = RX, RW = RW, BODY_Y = BODY_Y, BODY_H = BODY_H, COL_W = COL_W, COL2_X = COL2_X,
    ABOUT_H = ABOUT_H, TOP5_H = TOP5_H, CHAR_H = CHAR_H, TOP_Y = TOP_Y, LIST_Y = LIST_Y, LIST_H = LIST_H, BANNER_H = BANNER_H, INFO_H = INFO_H }

local function card(page, title, x, y, w, h)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", x, -y)
    c:SetSize(w, h)
    UI.Card(c)
    c.title = UI.SectionTitle(c, title)
    c.title:SetPoint("LEFT", c, "TOPLEFT", 10, -UI.HeadMid(HEAD_H))
    c.meta = UI.Text(c, 10)
    c.meta:SetPoint("RIGHT", c, "TOPRIGHT", -10, -UI.HeadMid(HEAD_H))
    c.meta:SetTextColor(0.5, 0.5, 0.55)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    UI.Line(line, 0.06)
    c.empty = UI.Text(c, 11)
    c.empty:SetPoint("TOP", 0, -HEAD_H - 18)
    c.empty:SetWidth(w - 24)
    c.empty:SetTextColor(0.5, 0.5, 0.55)
    c.empty:SetJustifyH("CENTER")
    c.empty:Hide()
    return c
end

-- An icon in a thin colored frame (portraits, Most played with, badges).
local function portrait(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size + 4, size + 4)
    f.ring = f:CreateTexture(nil, "BORDER")
    f.ring:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    function f:Set(name)
        self.icon:SetTexture(Profiles:Portrait(name))
        local r, g, b = Profiles:Color(name)
        self.ring:SetColorTexture(r, g, b, 1)
    end
    return f
end

function Profiles:Build(page)
    self.page = page
    page:SetScript("OnHide", function()
        self:StopSong()
        self.songFor = nil
        UI.HideMenu()
        if UI.pickerFrame then UI.pickerFrame:Hide() end
    end)
    self:BuildList(page)
    self:BuildBanner(page)
    self:BuildAbout(page)
    self:BuildProfessions(page)
    self:BuildCharacter(page)
    self:BuildTop(page)
    self:BuildKudos(page)
    self.none = UI.Text(page, 12)
    self.none:SetPoint("TOP", page, "TOPLEFT", RX + RW / 2, -(TITLE_H + 60))
    self.none:SetTextColor(0.55, 0.55, 0.6)
    self.none:SetText("Join a guild to have a profile.")
end

------------------------------------------------------------------------
-- Members list: one row per account
------------------------------------------------------------------------
function Profiles:BuildList(page)
    local search = UI.EditBox(page, LEFT_W, BAR_H)
    search:SetPoint("TOPLEFT", PAD, -TITLE_H)
    search.placeholder = UI.Text(search, 11)
    search.placeholder:SetPoint("LEFT", 8, 0)
    search.placeholder:SetTextColor(0.45, 0.45, 0.5)
    search.placeholder:SetText("Find a guild member")
    search:SetScript("OnTextChanged", function(box)
        self.search = box:GetText()
        search.placeholder:SetShown(self.search == "")
        self.listOffset = 0
        self:RefreshList()
    end)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    self.searchBox = search

    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", PAD, -LIST_Y)
    list:SetSize(LEFT_W, LIST_H)
    UI.Card(list)
    list.hint = UI.ScrollHint(list, 4, 4)
    list.visible = math.floor((LIST_H - 8) / MEMBER_H)
    list.rows = {}
    for i = 1, list.visible do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(MEMBER_H)
        row:SetPoint("TOPLEFT", 2, -(4 + (i - 1) * MEMBER_H))
        row:SetPoint("TOPRIGHT", -2, -(4 + (i - 1) * MEMBER_H))
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        UI.SelBar(row.sel, 0.12)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        row.pic = portrait(row, 24)
        row.pic:SetPoint("LEFT", 6, 0)
        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetTexture(ns.MEDIA .. "disc")
        row.dot:SetVertexColor(0.4, 0.85, 0.45, 1)
        row.dot:SetSize(7, 7)
        row.dot:SetPoint("RIGHT", -10, 0)
        row.level = UI.Text(row, 10)
        row.level:SetPoint("RIGHT", -24, 0)
        row.level:SetTextColor(0.5, 0.5, 0.55)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("TOPLEFT", 40, -4)
        row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.status = UI.Text(row, 10)
        row.status:SetPoint("TOPLEFT", 40, -20)
        row.status:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
        row.status:SetJustifyH("LEFT")
        row.status:SetWordWrap(false)
        row.status:SetTextColor(0.6, 0.6, 0.65)
        row:SetScript("OnClick", function(r) if r.member then self:Open(r.member) end end)
        list.rows[i] = row
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d)
        self.listOffset = (self.listOffset or 0) - d * 2
        self:RefreshList()
    end)
    list.empty = UI.Text(list, 11)
    list.empty:SetPoint("TOP", 0, -24)
    list.empty:SetTextColor(0.5, 0.5, 0.55)
    self.list = list

    self.mine = UI.Button(page, "My profile", LEFT_W, BAR_H, function() self:Open(me()) end)
    self.mine:SetPoint("TOPLEFT", PAD, -BOTTOM_Y)
end

local function anyOnline(self, name)
    for _, c in ipairs(self:Linked(name)) do
        if ns.Roster.online[c] then return c end
    end
end

-- One row per account (its Main) that runs Pog Raid, filtered
-- by the search box (which matches any of the account's characters or its
-- nickname).
function Profiles:Members()
    local out, seen = {}, {}
    local q = (self.search or ""):lower()
    for name, p in pairs(G().players) do
        local nick = q ~= "" and self:Content(name).nick
        if p.inGuild and (q == "" or display(name):lower():find(q, 1, true) or (nick and nick:lower():find(q, 1, true))) then
            local m = self:Main(name)
            if not seen[m] then
                seen[m] = true
                if self:HasAddon(m) then out[#out + 1] = m end
            end
        end
    end
    -- online first (on any of their characters; Jake), then set-up profiles,
    -- then everyone else, each alphabetical by the name shown (nickname or main)
    local online, custom, shown = {}, {}, {}
    for _, m in ipairs(out) do
        online[m] = anyOnline(self, m) ~= nil
        custom[m] = self:Customized(m)
        shown[m] = self:Name(m):lower()
    end
    table.sort(out, function(a, b)
        if online[a] ~= online[b] then return online[a] end
        if custom[a] ~= custom[b] then return custom[a] end
        if shown[a] ~= shown[b] then return shown[a] < shown[b] end
        return a < b
    end)
    return out, online
end

-- Someone has set something on their profile (not just the automatic parts).
function Profiles:Customized(name)
    local content = self:Content(name)
    for _, f in ipairs(CONTENT) do
        if content[f] ~= nil then return true end
    end
    return false
end

function Profiles:RefreshList()
    local list = self.list
    local members, online = self:Members()
    self.listOffset = math.max(0, math.min(self.listOffset or 0, #members - list.visible))
    list.hint:Set(self.listOffset, list.visible, #members)
    local viewingMain = self.viewing and self:Main(self.viewing)
    for i, row in ipairs(list.rows) do
        local name = members[i + self.listOffset]
        row.member = name
        if name then
            local p = G().players[name] or {}
            row.pic:Set(name)
            local nick = self:Content(name).nick
            local cr, cg, cb = classColor(name)
            local label = nick and ("|cff%02x%02x%02x%s|r  |cff8a8a92%s|r"):format(cr * 255, cg * 255, cb * 255, nick, display(name))
                or colorName(name)
            row.name:SetText(label) -- (no "+1" alt count: fewer numbers)
            row.status:SetText(self:Content(name).status or "")
            row.level:SetText(p.level or "")
            row.dot:SetShown(online[name] == true)
            row.sel:SetShown(name == viewingMain)
            row:Show()
        else
            row:Hide()
        end
    end
    list.empty:SetText(IsInGuild() and ((self.search or "") ~= "" and "Nobody with Pog Guild Tools matches."
        or "Nobody yet.") or "")
    list.empty:SetShown(#members == 0)
end

------------------------------------------------------------------------
-- Banner: portrait, name, status, buttons, song
------------------------------------------------------------------------
Profiles.WASH = 0.22 -- the banner's colour wash at its left edge
function Profiles:BuildBanner(page)
    local b = CreateFrame("Frame", nil, page)
    b:SetPoint("TOPLEFT", RX, -TITLE_H)
    b:SetSize(RW, BANNER_H)
    UI.Card(b)
    self.banner = b
    -- their colour as a soft wash from the left (it was a hard 3px line on top
    -- that matched nothing else: UI experiment)
    b.wash = b:CreateTexture(nil, "BACKGROUND", nil, 3)
    b.wash:SetAllPoints()
    b.wash:SetColorTexture(1, 1, 1, 1)
    b.pic = portrait(b, PORTRAIT)
    b.pic:SetPoint("TOPLEFT", 14, -(BANNER_H - PORTRAIT - 4) / 2)
    local tx = 14 + PORTRAIT + 4 + 14
    b.name = UI.Headline(b, 22) -- the page's headline: who this is
    b.name:SetPoint("TOPLEFT", tx, -14)
    b.info = UI.Text(b, 11)
    b.info:SetPoint("TOPLEFT", tx, -40)
    b.info:SetTextColor(0.7, 0.7, 0.75)
    b.status = UI.Text(b, 12)
    b.status:SetPoint("TOPLEFT", tx, -58)
    b.status:SetWidth(RW - tx - 180)
    b.status:SetJustifyH("LEFT")
    b.status:SetWordWrap(false)
    b.online = UI.Text(b, 10)
    b.online:SetPoint("TOPLEFT", tx, -78)

    -- own profile: one Edit profile menu (status, nickname, favourites,
    -- portrait, colour, song, roles: it was four buttons). Others: Whisper, Invite.
    local function btn(label, w, fn) return UI.Button(b, label, w, 22, fn) end
    b.edit = btn("Edit profile", 110, function(x) UI.ShowMenu(x, self:EditMenu()) end)
    UI.DropArrow(b.edit)
    b.edit:SetPoint("TOPRIGHT", -10, -12)
    b.invite = btn("Invite", 60, function() if self.viewing then ns.Home.Invite(self.viewing) end end)
    b.invite:SetPoint("TOPRIGHT", -10, -12)
    b.whisper = btn("Whisper", 66, function() if self.viewing then ns.Home.Whisper(self.viewing) end end)
    b.whisper:SetPoint("RIGHT", b.invite, "LEFT", -4, 0)

    b.play = UI.Button(b, "Play", 50, 20, function()
        if self.playing then self:StopSong() else self:PlaySong(self:Song(self.viewing)) end
        self:RefreshBanner()
    end)
    b.play:SetPoint("BOTTOMRIGHT", -10, 12)
    b.song = UI.Text(b, 11)
    b.song:SetPoint("RIGHT", b.play, "LEFT", -8, 0)
    b.song:SetJustifyH("RIGHT")
    b.song:SetTextColor(0.7, 0.7, 0.75)
end

local function className(token)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if names and token and names[token] then return names[token] end
    return token and (token:sub(1, 1) .. token:sub(2):lower()) or nil
end

function Profiles:RefreshBanner()
    local b, name = self.banner, self.viewing
    local content = self:Content(name)
    local p = G().players[name] or {}
    local mine = self:IsMine(name)
    local r, g, bl = self:Color(name)
    local ok = CreateColor and b.wash.SetGradient and pcall(b.wash.SetGradient, b.wash, "HORIZONTAL",
        CreateColor(r, g, bl, Profiles.WASH), CreateColor(r, g, bl, 0))
    if not ok then b.wash:SetColorTexture(r, g, bl, Profiles.WASH / 2) end
    b.washColor = { r, g, bl }
    b.pic:Set(name)
    local nick = content.nick
    if nick then
        local cr, cg, cb = classColor(name)
        b.name:SetText(("|cff%02x%02x%02x%s|r"):format(cr * 255, cg * 255, cb * 255, nick))
    else
        b.name:SetText(colorName(name))
    end
    local info = {}
    if nick then info[#info + 1] = colorName(name) end
    if p.level then info[#info + 1] = ("Level %d %s"):format(p.level, className(p.class) or "") end
    if p.rank then info[#info + 1] = p.rank end
    local role = content.role and Profiles.ROLES[ROLE[content.role] or 0]
    local off = content.off and Profiles.ROLES[ROLE[content.off] or 0]
    local function colored(r) return ("|cff%02x%02x%02x%s|r"):format(r[3][1] * 255, r[3][2] * 255, r[3][3] * 255, r[2]) end
    if role and off and off ~= role then
        info[#info + 1] = colored(role) .. " |cff8a8a92(off spec|r " .. colored(off) .. "|cff8a8a92)|r"
    elseif role then
        info[#info + 1] = colored(role)
    elseif off then
        info[#info + 1] = "|cff8a8a92off spec|r " .. colored(off)
    end
    if not p.inGuild and p.rank == nil then info[#info + 1] = "not in the guild" end
    b.info:SetText(table.concat(info, ", "))
    if content.status then
        b.status:SetText(content.status)
        b.status:SetTextColor(r, g, bl)
    else
        b.status:SetText("No status yet.")
        b.status:SetTextColor(0.5, 0.5, 0.55)
    end
    -- online on this character, or on another of theirs
    local on = ns.Roster.online[name] and name or anyOnline(self, name)
    local zone = on and (G().players[on] or {}).zone
    local where = (zone and zone ~= "") and (", " .. zone) or ""
    if on == name then
        b.online:SetText("Online" .. where)
    elseif on then
        b.online:SetText(("Online as %s%s"):format(display(on), where))
    else
        b.online:SetText("Offline")
    end
    if on then b.online:SetTextColor(0.4, 0.85, 0.45) else b.online:SetTextColor(0.5, 0.5, 0.55) end
    b.edit:SetShown(mine)
    b.whisper:SetShown(not mine)
    b.invite:SetShown(not mine)
    local song = self:Song(name)
    b.song:SetText(song and ("Song: " .. song[2]) or "")
    b.play:SetShown(song ~= nil)
    b.play:SetLabel(self.playing and "Stop" or "Play")
end

function Profiles:EditMenu()
    local content = self:Mine().content
    local menu = {
        { text = "Status and About Me...", func = function()
            UI.Compose({ heading = "Status and About Me", label1 = "Status (one line)", label2 = "About me",
                max1 = Profiles.MAX_STATUS, max2 = Profiles.MAX_ABOUT, text1 = content.status or "",
                text2 = content.about or "", button = "Save", optional = true }, function(status, about)
                self:Save({ status = clean(status, Profiles.MAX_STATUS), about = clean(about, Profiles.MAX_ABOUT) })
            end)
        end },
        { text = "Nickname...", func = function()
            UI.Compose({ heading = "Nickname", label1 = "Nickname",
                max1 = Profiles.MAX_NICK, text1 = content.nick or "", text2 = "", button = "Save", optional = true,
                noArea = true }, function(nick)
                self:Save({ nick = clean(nick, Profiles.MAX_NICK) })
            end)
        end },
        { text = "Favorites...", func = function()
            UI.Compose({ heading = "Favorites", label1 = "Favorite raid", labelMid = "Favorite dungeon",
                max1 = Profiles.MAX_FAV, maxMid = Profiles.MAX_FAV, text1 = content.fav1 or "",
                textMid = content.fav2 or "", text2 = "", button = "Save", optional = true, noArea = true },
                function(raid, _, dungeon)
                    self:Save({ fav1 = clean(raid, Profiles.MAX_FAV), fav2 = clean(dungeon, Profiles.MAX_FAV) })
                end)
        end },
        { text = "Portrait...", func = function() self:PickPortrait(self.banner.edit) end },
        { text = "Color...", func = function() self:PickColor(self.banner.edit) end },
        { text = "Song...", func = function() UI.ShowMenu(self.banner.edit, self:SongMenu()) end },
        { text = "Main role", header = true },
    }
    local current = content.role and ROLE[content.role]
    for i, r in ipairs(Profiles.ROLES) do
        menu[#menu + 1] = { text = (current == i and "> " or "   ") .. r[2], color = r[3],
            func = function() self:Save({ role = r[1] }) end }
    end
    menu[#menu + 1] = { text = (content.role == nil and "> " or "   ") .. "No main role",
        func = function() self:Save({ role = false }) end }
    menu[#menu + 1] = { text = "Off spec", header = true }
    local off = content.off and ROLE[content.off]
    for i, r in ipairs(Profiles.ROLES) do
        menu[#menu + 1] = { text = (off == i and "> " or "   ") .. r[2], color = r[3],
            func = function() self:Save({ off = r[1] }) end }
    end
    menu[#menu + 1] = { text = (content.off == nil and "> " or "   ") .. "No off spec",
        func = function() self:Save({ off = false }) end }
    return menu
end

-- Our picks first, then the client's classic-art macro icons (all real
-- files on this client), without repeats: plain file IDs, built the first
-- time the picker opens.
function Profiles:IconChoices()
    if self.iconChoices then return self.iconChoices end
    local out, seen = {}, {}
    local function add(file)
        if type(file) == "number" and file < Profiles.CLASSIC_ICONS and not seen[file] then
            seen[file] = true
            out[#out + 1] = file
        end
    end
    for _, icon in ipairs(self.ICONS) do add(icon[1]) end
    -- by name: any of these may be missing on a client
    for _, fn in ipairs({ "GetLooseMacroIcons", "GetMacroIcons", "GetLooseMacroItemIcons", "GetMacroItemIcons" }) do
        local list = {}
        if _G[fn] then
            local ok, ret = pcall(_G[fn], list)
            if ok and type(ret) == "table" then list = ret end
        end
        for _, file in ipairs(list) do add(file) end
    end
    self.iconChoices = out
    return out
end

function Profiles:PickPortrait(anchor)
    local current = self:Portrait(me())
    local choices = self:IconChoices()
    local selected
    for i, file in ipairs(choices) do
        if file == current then
            selected = i
            break
        end
    end
    self.iconTips = self.iconTips or {}
    for _, icon in ipairs(self.ICONS) do self.iconTips[icon[1]] = icon[2] end
    UI.Picker(anchor, choices, 12, 32, function(i) self:Save({ icon = choices[i] }) end, 8, selected, self.iconTips)
end

function Profiles:PickColor(anchor)
    local content = self:Mine().content
    local r, g, b = classColor(me())
    local items = { { color = { r, g, b }, tip = "Class color", selected = content.color == nil } }
    for i, c in ipairs(self.COLORS) do
        items[i + 1] = { color = c, tip = c[4], selected = content.color == i }
    end
    UI.Picker(anchor, items, 5, 26, function(i) self:Save({ color = i > 1 and (i - 1) or false }) end)
end

function Profiles:SongMenu()
    local content = self:Mine().content
    local menu = { { text = (content.song == nil and "> " or "   ") .. "No song", func = function()
        self:StopSong()
        self:Save({ song = false })
    end } }
    for i, s in ipairs(self.SONGS) do
        menu[#menu + 1] = { text = (content.song == i and "> " or "   ") .. s[2], func = function()
            self:Save({ song = i })
            self:PlaySong(s)
            self:RefreshBanner()
        end }
    end
    return menu
end

------------------------------------------------------------------------
-- About me: text, then characters and favorites
------------------------------------------------------------------------
function Profiles:BuildAbout(page)
    local c = card(page, "About me", RX, BODY_Y, COL_W, ABOUT_H)
    self.aboutCard = c
    UI.Parchment(c)
    c.text = UI.Text(c, 11)
    c.text:SetPoint("TOPLEFT", 10, -(HEAD_H + 8))
    c.text:SetPoint("TOPRIGHT", -10, -(HEAD_H + 8))
    c.text:SetHeight(ABOUT_H - HEAD_H - 8 - INFO_H - 12)
    c.text:SetJustifyH("LEFT")
    c.text:SetJustifyV("TOP")
    if c.text.SetMaxLines then c.text:SetMaxLines(math.floor((ABOUT_H - HEAD_H - 8 - INFO_H - 12) / 13)) end
    c.text:SetTextColor(0.88, 0.88, 0.91)
    -- a long About me is cut short: hover for all of it
    c.textHit = CreateFrame("Frame", nil, c)
    c.textHit:SetAllPoints(c.text)
    c.textHit:EnableMouse(true)
    c.textHit:SetScript("OnEnter", function(f)
        if not GameTooltip or not (c.text.IsTruncated and c.text:IsTruncated()) then return end
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:AddLine(c.text:GetText(), 0.9, 0.9, 0.93, true)
        GameTooltip:Show()
    end)
    c.textHit:SetScript("OnLeave", hideTip)
    -- a divider, then one row each, centred in the space left
    local div = c:CreateTexture(nil, "ARTWORK")
    div:SetPoint("BOTTOMLEFT", 8, INFO_H)
    div:SetPoint("BOTTOMRIGHT", -8, INFO_H)
    div:SetHeight(1)
    UI.Line(div, 0.06)
    local rowsTop = ABOUT_H - INFO_H + (INFO_H - 3 * INFO_ROW_H) / 2
    c.infoRows = {}
    local labels = { "Characters", FAVORITES[1][2], FAVORITES[2][2] }
    for i, text in ipairs(labels) do
        local row = CreateFrame("Button", nil, c)
        row:SetHeight(INFO_ROW_H)
        row:SetPoint("TOPLEFT", 2, -(rowsTop + (i - 1) * INFO_ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(rowsTop + (i - 1) * INFO_ROW_H))
        local label = UI.Text(row, 10)
        label:SetPoint("LEFT", 8, 0)
        label:SetTextColor(0.55, 0.55, 0.6)
        label:SetText(text)
        row.value = UI.Text(row, 11)
        row.value:SetPoint("LEFT", 120, 0)
        row.value:SetPoint("RIGHT", -8, 0)
        row.value:SetJustifyH("LEFT")
        row.value:SetWordWrap(false)
        c.infoRows[i] = row
    end
    -- characters: hover lists them, click opens one (or forgets one of ours)
    local chars = c.infoRows[1]
    local hl = chars:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Hover(hl, 0.05)
    chars:SetScript("OnEnter", function(row)
        if not GameTooltip or not self.viewing then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Characters", 1, 1, 1)
        for _, n in ipairs(self:Linked(self.viewing)) do
            local p = G().players[n] or {}
            GameTooltip:AddDoubleLine(display(n), p.level and ("Level " .. p.level) or "", classColor(n))
        end
        GameTooltip:Show()
    end)
    chars:SetScript("OnLeave", hideTip)
    chars:SetScript("OnClick", function(row)
        if not self.viewing then return end
        local menu = { { text = "Characters", header = true } }
        for _, n in ipairs(self:Linked(self.viewing)) do
            if n ~= (self.profChar or self.viewing) then
                menu[#menu + 1] = { text = display(n) .. "'s professions", color = { classColor(n) },
                    func = function() self.profChar = n; self:Refresh() end }
            end
        end
        if self:IsMine(self.viewing) then
            for _, n in ipairs(self:Linked(self.viewing)) do
                if n ~= me() then
                    menu[#menu + 1] = { text = ("%s isn't mine any more"):format(display(n)), color = { 0.95, 0.4, 0.4 },
                        func = function() self:Forget(n) end }
                end
            end
        end
        if #menu > 1 then UI.ShowMenu(row, menu) end
    end)
end

function Profiles:RefreshAbout()
    local c, name = self.aboutCard, self.viewing
    local content = self:Content(name)
    if content.about then
        c.text:SetText(content.about)
        c.text:SetTextColor(0.88, 0.88, 0.91)
    else
        local any = self:IsMine(name) or next(content) ~= nil
        c.text:SetText(self:IsMine(name) and "Nothing here yet."
            or (any and "Nothing here yet." or (display(name) .. " hasn't set up a profile yet.")))
        c.text:SetTextColor(0.5, 0.5, 0.55)
    end
    local others = {}
    for _, n in ipairs(self:Linked(name)) do
        if n ~= name then others[#others + 1] = display(n) end
    end
    local values = { #others > 0 and table.concat(others, ", ") or nil }
    for i, f in ipairs(FAVORITES) do values[i + 1] = content[f[1]] end
    for i, row in ipairs(c.infoRows) do
        local v = values[i]
        row.value:SetText(v or (i == 1 and "just this one" or "-"))
        if v then row.value:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) else row.value:SetTextColor(0.45, 0.45, 0.5) end
    end
end

------------------------------------------------------------------------
-- Character: the account's current character (Gear.lua), Inspect for more
------------------------------------------------------------------------
local INSPECT_W, INSPECT_H = 92, 22
-- Their gear laid out like the game's character pane (slot IDs): a column
-- down each side, the weapons along the bottom between them, Inspect above
-- the weapons. In the middle: the model when it can show them (ourselves,
-- target, group), else their class icon. It uses the art's full height.
local MINI = { left = { 1, 2, 3, 15, 5, 4, 19, 9 }, right = { 10, 6, 7, 8, 11, 12, 13, 14 }, bottom = { 16, 17, 18 } }
local MINI_ICON, MINI_PITCH, MINI_EDGE, MINI_ROW_GAP = 24, 27, 12, 8
local SLOT_INV = { "HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "BackSlot", "MainHandSlot",
    "SecondaryHandSlot", "RangedSlot", "TabardSlot" }
local MINI_COLOR = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 },
    { 1, 0.5, 0 } }
Profiles.MINI = MINI

-- Inspect: a magnifying glass and the word, centred together.
local function inspectButton(self, parent)
    local btn = UI.Button(parent, "Inspect", INSPECT_W, INSPECT_H, function() self:Inspect() end)
    btn.glass = btn:CreateTexture(nil, "ARTWORK")
    btn.glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    btn.glass:SetSize(14, 14)
    local tw = math.floor(btn.label:GetStringWidth() + 0.5)
    local x0 = math.floor((INSPECT_W - (14 + 5 + tw)) / 2)
    btn.glass:SetPoint("LEFT", x0, 0)
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", x0 + 14 + 5, 0)
    btn.label:SetJustifyH("LEFT")
    return btn
end

-- The Character card's numbers (Gear.STATS keys): label, colour (health green,
-- mana blue, the rest the soft label colour).
-- Health and mana as bars, like the game's unit frames (Jake), the stats close
-- together under them.
Profiles.STAT_BARS = { { "hp", "Health", { 0.10, 0.72, 0.15 } }, { "mana", "Mana", { 0.12, 0.38, 0.92 } } }
Profiles.STAT_ROWS = { { "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" },
    { "spi", "Spirit" }, { "armor", "Armor" } }
Profiles.STAT_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
Profiles.STAT_BAR_H, Profiles.STAT_BAR_GAP, Profiles.STAT_BARS_GAP, Profiles.STAT_ROW_H = 16, 3, 8, 13
Profiles.STAT_COL_W = 128 -- the stats sit in a narrower column, centred, names near their numbers (Jake)

function Profiles:BuildCharacter(page)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", COL2_X, -BODY_Y)
    c:SetSize(COL_W, CHAR_H)
    UI.Card(c)
    self.charCard = c
    local mw, mh = COL_W - 16, CHAR_H - 8 - INSPECT_H - 24
    local artH = CHAR_H - 16
    local colsH = (#MINI.left - 1) * MINI_PITCH + MINI_ICON
    local miniTop = math.floor((artH - colsH) / 2)
    local lastY = miniTop + (#MINI.left - 1) * MINI_PITCH
    local inspectY = lastY - 8 - INSPECT_H
    -- the model: between the gear columns, down to Inspect
    local modelX = MINI_EDGE + MINI_ICON + 4
    local modelW, modelH = mw - 2 * modelX, inspectY - 2
    c.model = ns.Wishlist and ns.Wishlist.Model(c, 8 + modelX, 8, modelW, modelH)
    if c.model then
        c.model.zoom = 1 -- the game's own framing: a small card needs the whole height
        -- the art fills the card 8px in all round, the Inspect button on it too
        c.artArea = CreateFrame("Frame", nil, c)
        c.artArea:SetPoint("TOPLEFT", 8, -8)
        c.artArea:SetSize(COL_W - 16, CHAR_H - 16)
        c.backdrop = ns.Wishlist.Backdrop(c, c.model, c.artArea)
    end
    -- nothing shared and out of range: their portrait
    c.pic = portrait(c, 64)
    c.pic:SetPoint("CENTER", c, "TOPLEFT", COL_W / 2, -(8 + mh / 2))
    c.open = CreateFrame("Button", nil, c)
    c.open:SetPoint("TOPLEFT", 8 + modelX, -8)
    c.open:SetSize(modelW, modelH)
    c.open:SetFrameLevel(c:GetFrameLevel() + 3)
    c.open:SetScript("OnClick", function() self:Inspect() end)
    -- ... and their gear around it (hover for the item, click for Inspect)
    c.mini = {}
    local function icon(slotID, x, y)
        local b = CreateFrame("Button", nil, c)
        b:SetSize(MINI_ICON, MINI_ICON)
        b:SetPoint("TOPLEFT", 8 + x, -(8 + y))
        b:SetFrameLevel(c:GetFrameLevel() + 4)
        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetPoint("TOPLEFT", -1, 1)
        b.border:SetSize(MINI_ICON + 2, MINI_ICON + 2)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        b.slot = slotID
        b:SetScript("OnClick", function() self:Inspect() end)
        b:SetScript("OnEnter", function(btn)
            if not btn.link or not GameTooltip then return end
            UI.ItemTip(btn, btn.link)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", hideTip)
        b:Hide()
        c.mini[#c.mini + 1] = b
    end
    for i, s in ipairs(MINI.left) do icon(s, MINI_EDGE, miniTop + (i - 1) * MINI_PITCH) end
    for i, s in ipairs(MINI.right) do icon(s, mw - MINI_EDGE - MINI_ICON, miniTop + (i - 1) * MINI_PITCH) end
    local rowW = #MINI.bottom * MINI_ICON + (#MINI.bottom - 1) * MINI_ROW_GAP
    for i, s in ipairs(MINI.bottom) do
        icon(s, math.floor((mw - rowW) / 2) + (i - 1) * (MINI_ICON + MINI_ROW_GAP), lastY)
    end
    -- the middle: the model or their numbers, a button above the weapons to
    -- switch between them (Jake; clicking the art or a gear icon opens Inspect)
    c.viewBtn = UI.Button(c, "Show stats", INSPECT_W + 12, INSPECT_H, function()
        ns.db.frames.charStats = not self:StatsView()
        self:RefreshCharacter()
    end)
    c.viewBtn:SetPoint("TOP", c, "TOPLEFT", COL_W / 2, -(8 + inspectY))
    c.viewBtn:SetFrameLevel(c:GetFrameLevel() + 4)
    c.viewBtn:Hide()
    c.classIcon = portrait(c, 48)
    c.classIcon:SetPoint("CENTER", c, "TOPLEFT", COL_W / 2, -(8 + math.floor((miniTop + inspectY) / 2)))
    c.classIcon:Hide()
    -- ... or, when they've shared them, their character sheet's numbers (Jake)
    local st = CreateFrame("Frame", nil, c)
    st:SetSize(modelW - 20, 100) -- (its height is set by what shows)
    st:SetPoint("CENTER", c, "TOPLEFT", COL_W / 2, -(8 + math.floor((miniTop + inspectY) / 2)))
    st:SetFrameLevel(c:GetFrameLevel() + 4)
    st.bg = st:CreateTexture(nil, "BACKGROUND")
    st.bg:SetPoint("TOPLEFT", -8, 6)
    st.bg:SetPoint("BOTTOMRIGHT", 8, -6)
    st.bg:SetColorTexture(0, 0, 0, 0.55)
    st.bars = {}
    for _, r in ipairs(Profiles.STAT_BARS) do
        local b = CreateFrame("Frame", nil, st)
        b:SetSize(modelW - 20, Profiles.STAT_BAR_H)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(0, 0, 0, 0.7)
        b.fill = b:CreateTexture(nil, "BORDER")
        b.fill:SetPoint("TOPLEFT", 1, -1)
        b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        b.fill:SetTexture(Profiles.STAT_BAR)
        b.fill:SetVertexColor(r[3][1], r[3][2], r[3][3])
        b.label = UI.Text(b, 10)
        b.label:SetPoint("LEFT", 5, 0)
        b.label:SetText(r[2])
        b.label:SetTextColor(1, 1, 1)
        b.value = UI.Text(b, 11)
        b.value:SetPoint("RIGHT", -5, 0)
        b.value:SetJustifyH("RIGHT")
        b.value:SetTextColor(1, 1, 1)
        b.key = r[1]
        st.bars[#st.bars + 1] = b
    end
    st.rows = {}
    for i, r in ipairs(Profiles.STAT_ROWS) do
        local label = UI.Text(st, 10)
        label:SetText(r[2])
        label:SetTextColor(0.72, 0.70, 0.64)
        local value = UI.Text(st, 11)
        value:SetJustifyH("RIGHT")
        st.rows[i] = { key = r[1], label = label, value = value }
    end
    st:Hide()
    c.stats = st
    local btn = inspectButton(self, c)
    btn:SetPoint("BOTTOM", 0, 16) -- 8px inside the art, which is 8px inside the card
    c.inspect = btn
end

-- The Character card shows numbers rather than the model (the toggle; on by
-- default while Jake works on their look).
Profiles.STATS_DEFAULT = true
function Profiles:StatsView()
    local v = ns.db.frames.charStats
    if v == nil then return Profiles.STATS_DEFAULT end
    return v
end

function Profiles:RefreshCharacter()
    local c = self.charCard
    local Gear = ns.Gear
    local who, rec = self.viewing, nil
    if Gear then who, rec = Gear:Current(self:Linked(self.viewing)) end
    self.charFor = who
    local p = G().players[who]
    if c.backdrop then c.backdrop:SetClass(p and p.class) end
    -- their numbers: ours read live, others' from what they shared
    local mine = Gear and Gear:UnitOf(who) == "player"
    local stats = Gear and (mine and Gear.Stats({ st = Gear.StatsNow() }) or (rec and Gear.Stats(rec))) or nil
    local live = Gear and Gear:UnitOf(who) ~= nil and c.model ~= nil
    -- the model stays hidden while showing numbers, and while the Inspect
    -- window is open (a model draws through windows over it: Jake saw ours
    -- inside Inspect)
    local inspecting = Gear and Gear.window and Gear.window:IsShown()
    local useStats = stats ~= nil and (not live or self:StatsView())
    local shows = false
    if live and not useStats and not inspecting then
        shows = Gear:Dress(c.model, who)
    elseif c.model then
        c.model:Hide()
        c.model.dressed = nil -- (dressed again when it shows)
    end
    if c.backdrop and c.backdrop.shadow then c.backdrop.shadow:SetShown(shows) end
    -- their gear around the model (ours as we wear it now), or around their
    -- class icon; nothing shown or shared: their portrait
    local ids
    if Gear and Gear:UnitOf(who) == "player" then
        ids = Gear:Worn()
    elseif rec then
        ids = Gear.Unpack(rec.items)
    end
    c.pic:SetShown(not shows and not ids)
    if not shows and not ids then c.pic:Set(self.viewing) end
    c.inspect:SetShown(ids == nil)
    if not ids then stats, useStats = nil, false end
    c.viewBtn:SetShown(ids ~= nil and live and stats ~= nil)
    c.viewBtn:SetLabel(useStats and "Show model" or "Show stats")
    c.stats:SetShown(useStats)
    if useStats then
        -- the bars (no mana bar for rage and energy classes), then the stats
        local y = 0
        for _, b in ipairs(c.stats.bars) do
            local v = stats[b.key] or 0
            local show = not (b.key == "mana" and v == 0)
            b:SetShown(show)
            if show then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 0, -y)
                b.value:SetText(tostring(v))
                y = y + Profiles.STAT_BAR_H + Profiles.STAT_BAR_GAP
            end
        end
        y = y - Profiles.STAT_BAR_GAP + Profiles.STAT_BARS_GAP
        local inset = math.max(0, math.floor((c.stats:GetWidth() - Profiles.STAT_COL_W) / 2))
        for _, r in ipairs(c.stats.rows) do
            r.label:ClearAllPoints()
            r.label:SetPoint("TOPLEFT", inset, -y)
            r.value:ClearAllPoints()
            r.value:SetPoint("TOPRIGHT", -inset, -y)
            r.value:SetText(tostring(stats[r.key] or 0))
            y = y + Profiles.STAT_ROW_H
        end
        c.stats:SetHeight(y)
    end
    local icon = ids ~= nil and not shows and not useStats and not (live and inspecting)
    c.classIcon:SetShown(icon)
    if icon then
        local i = p and p.class and CLASS_ICON[p.class]
        c.classIcon.icon:SetTexture(i and self.ICONS[i][1] or NO_ICON)
        c.classIcon.ring:SetColorTexture(classColor(who))
    end
    for _, b in ipairs(c.mini) do
        b:SetShown(ids ~= nil)
        if ids then
            local id = ids[b.slot]
            if id then
                b.link = Gear.Link(id)
                local ok, tex = false, nil
                if C_Item and C_Item.GetItemIconByID then ok, tex = pcall(C_Item.GetItemIconByID, id) end
                b.icon:SetTexture(ok and tex or 134400)
                b.icon:SetAlpha(1)
                local col = MINI_COLOR[ns.Loot.Quality(b.link) or 1] or MINI_COLOR[1]
                b.border:SetColorTexture(col[1], col[2], col[3], 0.9)
            else
                b.link = nil
                local tex
                if GetInventorySlotInfo and SLOT_INV[b.slot] then
                    local ok, _, t = pcall(GetInventorySlotInfo, SLOT_INV[b.slot])
                    if ok then tex = t end
                end
                b.icon:SetTexture(tex or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
                b.icon:SetAlpha(0.45)
                b.border:SetColorTexture(0.2, 0.2, 0.23, 1)
            end
        end
    end
    c.inspect:SetEnabledState(Gear ~= nil and (rec ~= nil or Gear:UnitOf(who) ~= nil))
end

function Profiles:Inspect()
    if ns.Gear and self.charFor then ns.Gear:Inspect(self.charFor) end
end

------------------------------------------------------------------------
-- Professions: two big tiles; click one to browse its recipes
------------------------------------------------------------------------
function Profiles:BuildProfessions(page)
    local c = card(page, "Professions", RX, BODY_Y + ABOUT_H + GAP, COL_W, PROFS_H)
    self.profCard = c
    -- which of the account's characters
    c.switch = UI.Button(c, "", 110, 18, function(x)
        local menu = { { text = "Professions of", header = true } }
        for _, n in ipairs(self:Linked(self.viewing)) do
            menu[#menu + 1] = { text = (n == self.profChar and "> " or "   ") .. display(n), color = { classColor(n) },
                func = function() self.profChar = n; self:Refresh() end }
        end
        UI.ShowMenu(x, menu)
    end)
    c.switch:SetPoint("RIGHT", c, "TOPRIGHT", -UI.HeadInset(), -UI.HeadMid(HEAD_H))
    UI.DropArrow(c.switch)
    c.tiles = {}
    local w = (COL_W - 16 - TILE_GAP) / 2
    for i = 1, 2 do
        local t = CreateFrame("Button", nil, c)
        t:SetSize(w, PROFS_H - HEAD_H - 16)
        t:SetPoint("TOPLEFT", 8 + (i - 1) * (w + TILE_GAP), -(HEAD_H + 8))
        t.bg = t:CreateTexture(nil, "BACKGROUND")
        t.bg:SetAllPoints()
        t.bg:SetColorTexture(1, 1, 1, 0.03)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        -- (no recipe count: Jake; the icon and text are bigger to fill the tile)
        t.pic = portrait(t, 56)
        t.pic:SetPoint("TOP", 0, -16)
        t.pic.ring:SetColorTexture(1, 1, 1, 0.12)
        t.name = UI.Text(t, 15)
        t.name:SetPoint("TOP", t.pic, "BOTTOM", 0, -10)
        t.skill = UI.Text(t, 12)
        t.skill:SetPoint("TOP", t.name, "BOTTOM", 0, -6)
        t.skill:SetTextColor(0.7, 0.7, 0.75)
        t.hint = UI.Text(t, 11)
        t.hint:SetPoint("BOTTOM", 0, 12)
        t.hint:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
        t:SetScript("OnClick", function(tile)
            if tile.prof and not tile.prof.gathering then self:OpenBook(self.profChar or self.viewing, tile.prof.name) end
        end)
        c.tiles[i] = t
    end
end

function Profiles:RefreshProfessions()
    local c = self.profCard
    -- the character the card is on: the one opened, if it's this account's
    local linked = self:Linked(self.viewing)
    local name = self.viewing
    for _, n in ipairs(linked) do
        if n == self.profChar then name = n end
    end
    self.profChar = name
    c.switch:SetShown(#linked > 1)
    c.switch:SetLabel(display(name))
    local profs = self:Professions(name)
    for i, t in ipairs(c.tiles) do
        local p = profs[i]
        t.prof = p
        if p then
            t.pic.icon:SetTexture(p.icon)
            t.name:SetText(p.name)
            t.skill:SetText(("%d / %d"):format(p.rank, p.max))
            t.hint:SetText(p.gathering and "" or (p.recipes and "Browse recipes" or "Recipes not shared yet"))
            if p.recipes then t.hint:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) else t.hint:SetTextColor(0.55, 0.55, 0.6) end
        end
        t:SetShown(p ~= nil)
    end
    c.empty:SetText(self:IsMine(name) and "No professions shared yet."
        or "No professions shared yet.")
    c.empty:SetShown(#profs == 0)
end

------------------------------------------------------------------------
-- Recipe book: one profession's recipes, over the profile's body
------------------------------------------------------------------------
function Profiles:BuildBook(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", RX, -BODY_Y)
    f:SetSize(RW, BODY_H)
    UI.Card(f)
    f:Hide()
    self.book = f
    f.back = UI.Button(f, "< Back", 60, 22, function() self:CloseBook() end)
    f.back:SetPoint("TOPLEFT", 8, -8)
    f.title = UI.Text(f, 13)
    f.title:SetPoint("LEFT", f.back, "RIGHT", 10, 0)
    f.search = UI.EditBox(f, 200, 22)
    f.search:SetPoint("TOPRIGHT", -8, -8)
    f.search.placeholder = UI.Text(f.search, 11)
    f.search.placeholder:SetPoint("LEFT", 8, 0)
    f.search.placeholder:SetTextColor(0.45, 0.45, 0.5)
    f.search.placeholder:SetText("Search recipes")
    f.search:SetScript("OnTextChanged", function(box)
        f.search.placeholder:SetShown(box:GetText() == "")
        f.offset = 0
        self:RefreshBook()
    end)
    f.search:SetScript("OnEnterPressed", f.search.ClearFocus)
    f.meta = UI.Text(f, 10)
    f.meta:SetPoint("RIGHT", f.search, "LEFT", -10, 0)
    f.meta:SetTextColor(0.55, 0.55, 0.6)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -38)
    line:SetPoint("TOPRIGHT", -1, -38)
    line:SetHeight(1)
    UI.Line(line, 0.06)
    -- two columns, read across
    local top = 42
    f.perCol = math.floor((BODY_H - top - 6) / BOOK_ROW_H)
    f.rows = {}
    local colW = (RW - 16) / 2
    for i = 1, f.perCol * 2 do
        local r = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local row = CreateFrame("Button", nil, f)
        row:SetSize(colW, BOOK_ROW_H)
        row:SetPoint("TOPLEFT", 8 + col * colW, -(top + r * BOOK_ROW_H))
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        row.text = UI.Text(row, 11)
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(x)
            if not x.recipe or not GameTooltip then return end
            GameTooltip:SetOwner(x, "ANCHOR_RIGHT")
            local ok = GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, x.recipe.id)
            if not ok then GameTooltip:AddLine(x.recipe.name, 1, 0.82, 0) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", hideTip)
        f.rows[i] = row
    end
    f.hint = UI.ScrollHint(f, top, 4)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d)
        f.offset = (f.offset or 0) - d * 4
        self:RefreshBook()
    end)
    f.empty = UI.Text(f, 11)
    f.empty:SetPoint("TOP", 0, -80)
    f.empty:SetWidth(RW - 60)
    f.empty:SetTextColor(0.5, 0.5, 0.55)
end

function Profiles:OpenBook(name, prof)
    if not self.book then self:BuildBook(self.page) end -- built the first time it's needed
    self.bookFor = { name = name, prof = prof }
    self.book.offset = 0
    self.book.search:SetText("")
    self:Refresh()
end

function Profiles:CloseBook()
    self.bookFor = nil
    self:Refresh()
end

function Profiles:RefreshBook()
    local f, b = self.book, self.bookFor
    if not b then return end
    local recipes, shared = ns.Crafting:MemberRecipes(b.name, b.prof, f.search:GetText())
    local p
    for _, x in ipairs(self:Professions(b.name)) do
        if x.name == b.prof then p = x end
    end
    f.title:SetText(("%s's %s"):format(colorName(b.name), b.prof))
    f.meta:SetText(p and ("%d / %d"):format(p.rank, p.max) or "")
    local visible = #f.rows
    f.offset = math.max(0, math.min(f.offset or 0, math.ceil((#recipes - visible) / 2) * 2))
    f.hint:Set(f.offset / 2, f.perCol, math.ceil(#recipes / 2))
    for i, row in ipairs(f.rows) do
        local e = recipes[i + f.offset]
        row.recipe = e
        if e then
            row.text:SetText(e.name)
            if e.unknown then row.text:SetTextColor(0.5, 0.5, 0.55) else row.text:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) end
            row:Show()
        else
            row:Hide()
        end
    end
    if not shared then
        f.empty:SetText(("%s hasn't shared their %s recipes yet.")
            :format(display(b.name), b.prof, b.prof))
    else
        f.empty:SetText("No recipes match.")
    end
    f.empty:SetShown(#recipes == 0)
end

------------------------------------------------------------------------
-- Most played with
------------------------------------------------------------------------
function Profiles:BuildTop(page)
    local c = card(page, "Most played with", RX, TOP_Y, COL_W, TOP5_H)
    self.topCard = c
    -- your own: everyone you've grouped with, and for how long
    c.all = UI.Button(c, "See all", 64, 18, function(b)
        local menu = { { text = "Grouped with", header = true } }
        for _, e in ipairs(self:Together()) do
            local who, sec = e[1], e[2]
            menu[#menu + 1] = { text = self:Name(who) .. "  |cff8a8a92" .. Profiles.Duration(sec) .. "|r",
                color = { classColor(who) }, func = function() if self:HasAddon(who) then self:Open(who) end end }
        end
        if #menu == 1 then menu[2] = { text = "Nobody yet", disabled = true } end
        UI.ShowMenu(b, menu)
    end)
    c.all:SetPoint("RIGHT", c, "TOPRIGHT", -UI.HeadInset(), -UI.HeadMid(HEAD_H))
    c.tiles = {}
    local inner = COL_W - 16
    local gap = (inner - Profiles.TOP * TILE_W) / (Profiles.TOP - 1)
    for i = 1, Profiles.TOP do
        local t = CreateFrame("Button", nil, c)
        t:SetSize(TILE_W, TOP5_H - HEAD_H - 12)
        t:SetPoint("TOPLEFT", 8 + (i - 1) * (TILE_W + gap), -(HEAD_H + 6))
        t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        t.pic = portrait(t, TILE_ICON)
        t.pic:SetPoint("TOP", 0, -4)
        t.name = UI.Text(t, 10)
        t.name:SetPoint("TOP", t.pic, "BOTTOM", 0, -4)
        t.name:SetWidth(TILE_W)
        t.name:SetJustifyH("CENTER")
        t.name:SetWordWrap(false)
        t:SetScript("OnClick", function(tile) self:TileClick(tile) end)
        t:SetScript("OnEnter", function(tile) self:TileTooltip(tile) end)
        t:SetScript("OnLeave", hideTip)
        c.tiles[i] = t
    end
end

function Profiles:RefreshTop()
    local c, name = self.topCard, self.viewing
    local mine = self:IsMine(name)
    local top = self:Top(name)
    c.meta:SetText("")
    c.all:SetShown(mine)
    for i, t in ipairs(c.tiles) do
        local who = top[i]
        t.member = who
        if who then
            t.pic:Set(who)
            local cr, cg, cb = classColor(who)
            t.name:SetText(("|cff%02x%02x%02x%s|r"):format(cr * 255, cg * 255, cb * 255, self:Name(who)))
        end
        t:SetShown(who ~= nil)
    end
    c.empty:SetText("Nobody here yet.")
    c.empty:SetShown(#top == 0)
end

function Profiles:TileTooltip(tile)
    local who = tile.member
    if not who or not GameTooltip then return end
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self:Name(who, true), classColor(who))
    local status = self:Content(who).status
    if status then GameTooltip:AddLine(status, 0.85, 0.85, 0.9, true) end
    if self:IsMine(self.viewing) then
        local _, totals = self:TopNames()
        local sec = totals[self:Main(who)] or 0
        GameTooltip:AddLine("Grouped " .. Profiles.Duration(sec), 0.6, 0.6, 0.65)
    end
    if not self:HasAddon(who) then GameTooltip:AddLine("Doesn't have Pog Guild Tools yet", 0.6, 0.6, 0.65) end
    GameTooltip:Show()
end

function Profiles:TileClick(tile)
    if tile.member and self:HasAddon(tile.member) then self:Open(tile.member) end
end

------------------------------------------------------------------------
-- Kudos: the latest ones someone was given (who, which kind, their
-- message). No counts: nobody sees how many anyone has, or hasn't, got.
------------------------------------------------------------------------
function Profiles:BuildKudos(page)
    local c = card(page, "Kudos", COL2_X, BODY_Y + CHAR_H + GAP, COL_W, KUDOS_H)
    self.kudosCard = c
    UI.Parchment(c)
    c.give = UI.Button(c, "Give kudos", 80, 18, function(x) UI.ShowMenu(x, self:KudosMenu()) end)
    c.give:SetPoint("RIGHT", c, "TOPRIGHT", -UI.HeadInset(), -UI.HeadMid(HEAD_H))
    c.offset = 0
    c.visible = math.floor((KUDOS_H - HEAD_H - 8) / KUDOS_ROW_H)
    c.rows = {}
    for i = 1, c.visible do
        local r = CreateFrame("Frame", nil, c)
        r:EnableMouse(true)
        r:SetHeight(KUDOS_ROW_H)
        r:SetPoint("TOPLEFT", 2, -(HEAD_H + 4 + (i - 1) * KUDOS_ROW_H))
        r:SetPoint("TOPRIGHT", -2, -(HEAD_H + 4 + (i - 1) * KUDOS_ROW_H))
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(26, 26)
        r.icon:SetPoint("LEFT", 8, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.age = UI.Text(r, 10)
        r.age:SetPoint("TOPRIGHT", -8, -5)
        r.age:SetTextColor(0.5, 0.5, 0.55)
        r.head = UI.Text(r, 11)
        r.head:SetPoint("TOPLEFT", 42, -4)
        r.head:SetPoint("RIGHT", r.age, "LEFT", -8, 0)
        r.head:SetJustifyH("LEFT")
        r.head:SetWordWrap(false)
        r.msg = UI.Text(r, 11)
        r.msg:SetPoint("TOPLEFT", 42, -20)
        r.msg:SetPoint("RIGHT", -8, 0)
        r.msg:SetJustifyH("LEFT")
        r.msg:SetWordWrap(false)
        r.msg:SetTextColor(0.8, 0.8, 0.84)
        -- the whole message
        r:SetScript("OnEnter", function(row)
            local rec = row.rec
            if not rec or not GameTooltip then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Profiles.KUDOS[rec.kind][2], 1, 1, 1)
            GameTooltip:AddLine("from " .. self:Name(rec.author, true), classColor(rec.author))
            GameTooltip:AddLine(rec.msg, 0.85, 0.85, 0.9, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", hideTip)
        c.rows[i] = r
    end
    c.hint = UI.ScrollHint(c, HEAD_H + 4, 4)
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, d)
        c.offset = c.offset - d
        self:RefreshKudos()
    end)
end

function Profiles:RefreshKudos()
    local c, name = self.kudosCard, self.viewing
    local mine = self:IsMine(name)
    local _, recent, total = self:Kudos(name)
    -- only on your own profile: how many you've received (nobody else sees a count)
    c.meta:SetText(mine and total > 0 and (total .. " received") or "")
    c.give:SetShown(not mine)
    c.offset = math.max(0, math.min(c.offset, #recent - c.visible))
    c.hint:Set(c.offset, c.visible, #recent)
    for i, r in ipairs(c.rows) do
        local rec = recent[i + c.offset]
        r.rec = rec
        if rec then
            local k = Profiles.KUDOS[rec.kind]
            r.icon:SetTexture(k[1])
            local cr, cg, cb = classColor(rec.author)
            r.head:SetText(("%s  |cff8a8a92from|r |cff%02x%02x%02x%s|r"):format(k[2], cr * 255, cg * 255, cb * 255,
                self:Name(rec.author)))
            r.msg:SetText(rec.msg)
            r.age:SetText(ns.Home.Ago(rec.rev))
            r:Show()
        else
            r:Hide()
        end
    end
    c.empty:SetText("No kudos yet.")
    c.empty:SetShown(#recent == 0)
end

-- Give kudos: each kind with its icon; one we gave this week can be taken back.
function Profiles:KudosMenu()
    local name = self.viewing
    local kinds = self:Kudos(name)
    local menu = { { text = "Give " .. display(name) .. " kudos for...", header = true } }
    for kind, k in ipairs(Profiles.KUDOS) do
        if not k.retired then
            if kinds[kind].gave then
                menu[#menu + 1] = { text = ("|T%d:16|t %s  |cff8a8a92(given this week, take back)|r"):format(k[1], k[2]),
                    func = function() self:GiveKudos(name, kind) end }
            else
                menu[#menu + 1] = { text = ("|T%d:16|t %s"):format(k[1], k[2]), func = function()
                    UI.Compose({ heading = ("%s for %s"):format(k[2], display(name)), label2 = "Say why (a few words)",
                        max2 = Profiles.MAX_KUDOS_MSG, button = "Give" }, function(_, msg)
                        self:GiveKudos(name, kind, msg)
                    end)
                end }
            end
        end
    end
    return menu
end

------------------------------------------------------------------------
-- Show / refresh
------------------------------------------------------------------------
-- Open someone's profile (from a name anywhere in Pog Raid).
function Profiles:Open(name)
    if not name then return end
    local key = ns.Attendance:Key(name)
    if not self:HasAddon(key) then
        ns.Print(("%s doesn't have Pog Guild Tools yet, so there's no profile to show"):format(display(key)))
        return
    end
    self.viewing = self:Main(key)
    self.profChar = key
    self.bookFor = nil
    if self.page and self.page:IsShown() then
        self:Refresh()
    else
        ns.Editor:Toggle("profiles")
    end
end

function Profiles:Changed()
    if self.page and self.page:IsShown() then self:Refresh() end
end

function Profiles:Refresh()
    if not self.page then return end
    self.memo = {}
    self:RefreshAll()
    self.memo = nil
end

function Profiles:RefreshAll()
    local guild = Sync:GuildName() ~= nil
    self.viewing = self.viewing or me()
    local book = guild and self.bookFor ~= nil
    self.banner:SetShown(guild)
    for _, f in ipairs({ self.aboutCard, self.profCard, self.charCard, self.topCard, self.kudosCard }) do f:SetShown(guild and not book) end
    if self.book then self.book:SetShown(book) end
    self.mine:SetShown(guild)
    self.none:SetShown(not guild)
    self:RefreshList()
    if not guild then return end
    -- a new profile on screen: its song plays (if the owner picked one and
    -- profile songs are on), except our own
    if self.songFor ~= self.viewing then
        self.songFor = self.viewing
        self:StopSong()
        if not self:IsMine(self.viewing) and ns.db.settings.profileSongs ~= false then
            self:PlaySong(self:Song(self.viewing))
        end
    end
    self:RefreshBanner()
    if book then
        self:RefreshBook()
        return
    end
    self:RefreshAbout()
    self:RefreshProfessions()
    self:RefreshCharacter()
    self:RefreshTop()
    self:RefreshKudos()
end

------------------------------------------------------------------------
-- Events, timer, tab
------------------------------------------------------------------------
local function tick()
    if ns.db then Profiles:Tick() end
    C_Timer.After(Profiles.TICK, tick)
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(Profiles.TICK, tick)
end)

ns.Editor:RegisterTab("profiles", "Profiles", 0.5,
    function(page) Profiles:Build(page) end,
    function() Profiles:Refresh() end)
