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
--   [members     ]  [About me, characters, favorites]  [Most played with ]
--   [            ]  [Professions                    ]  [Kudos (latest)   ]
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

local CONTENT = { "status", "about", "role", "icon", "color", "song", "fav1", "fav2", "nick" }
local FIELDS = { "status", "about", "role", "icon", "color", "song", "fav1", "fav2", "nick", "ed", "chars", "top" }
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
            and sane(rec, { status = M, about = Profiles.MAX_ABOUT, role = 1, fav1 = F, fav2 = F, nick = Profiles.MAX_NICK,
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

-- The characters on `name`'s account: those whose records and `name`'s list
-- each other (ours: the ones we've played). Always starts with `name`.
function Profiles:Linked(name)
    local memo = self.memo -- only while the page refreshes
    if memo and memo[name] then return memo[name] end
    local out
    if self:IsMine(name) then
        out = { name }
        for _, c in ipairs(self:MyChars()) do
            if c ~= name then out[#out + 1] = c end
        end
    else
        out = { name }
        local rec = self:Get(name)
        if rec and rec.chars then
            for c in rec.chars:gmatch("[^,]+") do
                if c ~= name and lists(self:Get(c), name) then out[#out + 1] = c end
            end
        end
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
    for _, c in ipairs(self:Linked(name)) do
        if versions[c] or seen[c] or self:Get(c) or (profs[c] and not profs[c].deleted) then return true end
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
function Profiles.Week(t)
    return math.floor(((t or ns.Now()) - 5 * 86400 - 15 * 3600) / 604800)
end

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
local FRAME_W, FRAME_H = 902, 608
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
local ABOUT_H = 240
local TOP5_H = 100
local KUDOS_H = BODY_H - TOP5_H - GAP
local PROFS_H = BODY_H - ABOUT_H - GAP
local PORTRAIT = 72
local TILE_W, TILE_ICON = 54, 34
local TILE_GAP = 6
local INFO_ROW_H = 20
local INFO_H = 3 * INFO_ROW_H + 10   -- bottom of the About me card: characters + two favorites
local KUDOS_ROW_H = 38
local BOOK_ROW_H = 20

Profiles.layout = { RX = RX, RW = RW, BODY_Y = BODY_Y, BODY_H = BODY_H, COL_W = COL_W, COL2_X = COL2_X,
    ABOUT_H = ABOUT_H, TOP5_H = TOP5_H, LIST_Y = LIST_Y, LIST_H = LIST_H, BANNER_H = BANNER_H, INFO_H = INFO_H }

local function card(page, title, x, y, w, h)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", x, -y)
    c:SetSize(w, h)
    UI.Card(c)
    c.title = UI.SectionTitle(c, title)
    c.title:SetPoint("LEFT", c, "TOPLEFT", 10, -HEAD_H / 2)
    c.meta = UI.Text(c, 10)
    c.meta:SetPoint("RIGHT", c, "TOPRIGHT", -10, -HEAD_H / 2)
    c.meta:SetTextColor(0.5, 0.5, 0.55)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
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
        row.sel:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.12)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
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

-- One row per account (its Main) that runs Pog Raid, online first, filtered
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
    local online = {}
    for _, m in ipairs(out) do online[m] = anyOnline(self, m) ~= nil end
    table.sort(out, function(a, b)
        if online[a] ~= online[b] then return online[a] end
        return a < b
    end)
    return out, online
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
            local alts = #self:Linked(name) - 1
            row.pic:Set(name)
            local nick = self:Content(name).nick
            local cr, cg, cb = classColor(name)
            local label = nick and ("|cff%02x%02x%02x%s|r  |cff8a8a92%s|r"):format(cr * 255, cg * 255, cb * 255, nick, display(name))
                or colorName(name)
            row.name:SetText(label .. (alts > 0 and ("  |cff8a8a92+%d|r"):format(alts) or ""))
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
        or "Guildies show up here once their\nPog Guild Tools has been heard from.") or "")
    list.empty:SetShown(#members == 0)
end

------------------------------------------------------------------------
-- Banner: portrait, name, status, buttons, song
------------------------------------------------------------------------
function Profiles:BuildBanner(page)
    local b = CreateFrame("Frame", nil, page)
    b:SetPoint("TOPLEFT", RX, -TITLE_H)
    b:SetSize(RW, BANNER_H)
    UI.Card(b)
    self.banner = b
    b.strip = b:CreateTexture(nil, "ARTWORK")
    b.strip:SetPoint("TOPLEFT")
    b.strip:SetPoint("TOPRIGHT")
    b.strip:SetHeight(3)
    b.pic = portrait(b, PORTRAIT)
    b.pic:SetPoint("TOPLEFT", 14, -(BANNER_H - PORTRAIT - 4) / 2)
    local tx = 14 + PORTRAIT + 4 + 14
    b.name = UI.Text(b, 18)
    b.name:SetPoint("TOPLEFT", tx, -16)
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

    -- own profile: Edit, Portrait, Color, Song. Others: Whisper, Invite.
    local function btn(label, w, fn) return UI.Button(b, label, w, 22, fn) end
    b.edit = btn("Edit", 54, function(x) UI.ShowMenu(x, self:EditMenu()) end)
    b.portraitBtn = btn("Portrait", 70, function(x) self:PickPortrait(x) end)
    b.colorBtn = btn("Color", 58, function(x) self:PickColor(x) end)
    b.songBtn = btn("Song", 54, function(x) UI.ShowMenu(x, self:SongMenu()) end)
    b.songBtn:SetPoint("TOPRIGHT", -10, -12)
    b.colorBtn:SetPoint("RIGHT", b.songBtn, "LEFT", -4, 0)
    b.portraitBtn:SetPoint("RIGHT", b.colorBtn, "LEFT", -4, 0)
    b.edit:SetPoint("RIGHT", b.portraitBtn, "LEFT", -4, 0)
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
    b.strip:SetColorTexture(r, g, bl, 1)
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
    if role then
        info[#info + 1] = ("|cff%02x%02x%02x%s|r"):format(role[3][1] * 255, role[3][2] * 255, role[3][3] * 255, role[2])
    end
    if not p.inGuild and p.rank == nil then info[#info + 1] = "not in the guild" end
    b.info:SetText(table.concat(info, ", "))
    if content.status then
        b.status:SetText(content.status)
        b.status:SetTextColor(r, g, bl)
    else
        b.status:SetText(mine and "No status yet. Use Edit to set one." or "No status yet.")
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
    for _, x in ipairs({ b.edit, b.portraitBtn, b.colorBtn, b.songBtn }) do x:SetShown(mine) end
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
            UI.Compose({ heading = "Nickname", label1 = "What the guild calls you (your character's name shows with it)",
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
        { text = "Main role", header = true },
    }
    local current = content.role and ROLE[content.role]
    for i, r in ipairs(Profiles.ROLES) do
        menu[#menu + 1] = { text = (current == i and "> " or "   ") .. r[2], color = r[3],
            func = function() self:Save({ role = r[1] }) end }
    end
    menu[#menu + 1] = { text = (content.role == nil and "> " or "   ") .. "No main role",
        func = function() self:Save({ role = false }) end }
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
    c.text = UI.Text(c, 11)
    c.text:SetPoint("TOPLEFT", 10, -(HEAD_H + 8))
    c.text:SetPoint("TOPRIGHT", -10, -(HEAD_H + 8))
    c.text:SetHeight(ABOUT_H - HEAD_H - 8 - INFO_H - 12)
    c.text:SetJustifyH("LEFT")
    c.text:SetJustifyV("TOP")
    if c.text.SetMaxLines then c.text:SetMaxLines(7) end
    c.text:SetTextColor(0.88, 0.88, 0.91)
    -- a divider, then one row each, centred in the space left
    local div = c:CreateTexture(nil, "ARTWORK")
    div:SetPoint("BOTTOMLEFT", 8, INFO_H)
    div:SetPoint("BOTTOMRIGHT", -8, INFO_H)
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.06)
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
    hl:SetColorTexture(1, 1, 1, 0.05)
    chars:SetScript("OnEnter", function(row)
        if not GameTooltip or not self.viewing then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Characters", 1, 1, 1)
        for _, n in ipairs(self:Linked(self.viewing)) do
            local p = G().players[n] or {}
            GameTooltip:AddDoubleLine(display(n), p.level and ("Level " .. p.level) or "", classColor(n))
        end
        GameTooltip:AddLine("A character joins once it logs in with Pog Guild Tools.", 0.6, 0.6, 0.65, true)
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
        c.text:SetText(self:IsMine(name) and "Nothing here yet. Use Edit to write a little about yourself."
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
        if v then row.value:SetTextColor(0.9, 0.9, 0.93) else row.value:SetTextColor(0.45, 0.45, 0.5) end
    end
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
    c.switch:SetPoint("RIGHT", c, "TOPRIGHT", -5, -HEAD_H / 2)
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
        hl:SetColorTexture(1, 1, 1, 0.05)
        t.pic = portrait(t, 44)
        t.pic:SetPoint("TOP", 0, -14)
        t.pic.ring:SetColorTexture(1, 1, 1, 0.12)
        t.name = UI.Text(t, 13)
        t.name:SetPoint("TOP", t.pic, "BOTTOM", 0, -8)
        t.skill = UI.Text(t, 11)
        t.skill:SetPoint("TOP", t.name, "BOTTOM", 0, -5)
        t.skill:SetTextColor(0.7, 0.7, 0.75)
        t.recipes = UI.Text(t, 10)
        t.recipes:SetPoint("TOP", t.skill, "BOTTOM", 0, -5)
        t.recipes:SetTextColor(0.55, 0.55, 0.6)
        t.hint = UI.Text(t, 10)
        t.hint:SetPoint("BOTTOM", 0, 10)
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
    c.switch:SetLabel(display(name) .. " v")
    local profs = self:Professions(name)
    for i, t in ipairs(c.tiles) do
        local p = profs[i]
        t.prof = p
        if p then
            t.pic.icon:SetTexture(p.icon)
            t.name:SetText(p.name)
            t.skill:SetText(("%d / %d"):format(p.rank, p.max))
            t.recipes:SetText(p.gathering and "gathering" or (p.recipes and (p.recipes == 1 and "1 recipe"
                or (p.recipes .. " recipes")) or "recipes not shared yet"))
            t.hint:SetText(p.gathering and "" or "Browse recipes")
        end
        t:SetShown(p ~= nil)
    end
    c.empty:SetText(self:IsMine(name) and "Your professions share themselves.\nOpen a profession window once to add its recipes."
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
    line:SetColorTexture(1, 1, 1, 0.06)
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
        hl:SetColorTexture(1, 1, 1, 0.05)
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
    f.meta:SetText(p and ("%d / %d, %s"):format(p.rank, p.max, #recipes == 1 and "1 recipe" or (#recipes .. " recipes")) or "")
    local visible = #f.rows
    f.offset = math.max(0, math.min(f.offset or 0, math.ceil((#recipes - visible) / 2) * 2))
    f.hint:Set(f.offset / 2, f.perCol, math.ceil(#recipes / 2))
    for i, row in ipairs(f.rows) do
        local e = recipes[i + f.offset]
        row.recipe = e
        if e then
            row.text:SetText(e.name)
            if e.unknown then row.text:SetTextColor(0.5, 0.5, 0.55) else row.text:SetTextColor(0.9, 0.9, 0.93) end
            row:Show()
        else
            row:Hide()
        end
    end
    if not shared then
        f.empty:SetText(("%s hasn't shared their %s recipes yet.\nThey share them by opening their %s window with Pog Guild Tools.")
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
    local c = card(page, "Most played with", COL2_X, BODY_Y, COL_W, TOP5_H)
    self.topCard = c
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
        hl:SetColorTexture(1, 1, 1, 0.05)
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
    c.meta:SetText(mine and "by time grouped" or "")
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
    c.empty:SetText(mine and "Group up with guildies and the ones\nyou play with most show up here." or "Nobody here yet.")
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
        local together = sec < 3600 and (math.floor(sec / 60) .. "m") or (math.floor(sec / 3600) .. "h")
        GameTooltip:AddLine("Grouped " .. together, 0.6, 0.6, 0.65)
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
    local c = card(page, "Kudos", COL2_X, BODY_Y + TOP5_H + GAP, COL_W, KUDOS_H)
    self.kudosCard = c
    c.give = UI.Button(c, "Give kudos", 80, 18, function(x) UI.ShowMenu(x, self:KudosMenu()) end)
    c.give:SetPoint("RIGHT", c, "TOPRIGHT", -5, -HEAD_H / 2)
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
    -- only you see your own total
    c.meta:SetText(mine and total > 0 and (total == 1 and "1 so far" or (total .. " so far")) or "")
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
    c.empty:SetText(mine and "No kudos yet. Guildies give them\nfrom your profile."
        or "No kudos yet. Use Give kudos to be the first!")
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
    for _, f in ipairs({ self.aboutCard, self.profCard, self.topCard, self.kudosCard }) do f:SetShown(guild and not book) end
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
