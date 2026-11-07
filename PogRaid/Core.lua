-- PogRaid core: saved data, event dispatch, slash commands, API probe.
local ADDON, ns = ...

ns.VERSION = "0.16.3"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Page grid: every tab's page is PAGE_H tall. The Raid tab's pages (Roster,
-- Attendance, Loot, Raid Plans) are RAID_H tall under a row of sub-tabs.
ns.SUB_H = 34                    -- the sub-tab row and the gap under it
ns.RAID_H = 608
ns.PAGE_H = ns.RAID_H + ns.SUB_H

-- Colours used by arrows, circles and text. Index is what goes over the wire.
ns.COLORS = {
    { 0.95, 0.25, 0.25 }, -- 1 red
    { 1.00, 0.82, 0.20 }, -- 2 yellow
    { 0.35, 0.90, 0.40 }, -- 3 green
    { 0.35, 0.65, 1.00 }, -- 4 blue
    { 1.00, 1.00, 1.00 }, -- 5 white
    { 0.75, 0.45, 1.00 }, -- 6 purple
    { 0.62, 0.62, 0.66 }, -- 7 gray (walls)
}

-- Fill styles for rectangles and circles. Index goes over the wire.
ns.STYLES = {
    { key = "zone",    label = "Zone",    fill = 0.22 }, -- 1 see-through fill + outline
    { key = "solid",   label = "Solid",   fill = 0.85 }, -- 2 near-opaque fill + outline
    { key = "outline", label = "Outline", fill = nil },  -- 3 outline only
}

-- Role groups: generic dots for "tanks stand here" without naming anyone.
ns.GROUPS = {
    T = { label = "Tanks",   short = "T", color = { 0.45, 0.70, 1.00 } },
    H = { label = "Healers", short = "H", color = { 0.35, 0.90, 0.40 } },
    M = { label = "Melee",   short = "M", color = { 0.95, 0.35, 0.30 } },
    R = { label = "Ranged",  short = "R", color = { 1.00, 0.60, 0.20 } },
}
ns.GROUP_ORDER = { "T", "H", "M", "R" }

------------------------------------------------------------------------
-- Events: one frame, many handlers. Registering an event this client does
-- not have fails quietly instead of breaking the file, and one handler
-- erroring never stops the others.
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
ns.registered = {}

function ns.On(event, fn)
    if not handlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        ns.registered[event] = ok
        if not ok then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            if ns.Bug then pcall(ns.Bug.Record, err) end
            geterrorhandler()(err)
        end
    end
end)

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffPog Guild Tools|r: " .. tostring(msg))
end

-- Plays a SOUNDKIT sound unless sounds are turned off in Settings.
function ns.Sound(name)
    if ns.db and ns.db.settings and ns.db.settings.sounds == false then return end
    if PlaySound and SOUNDKIT and SOUNDKIT[name] then pcall(PlaySound, SOUNDKIT[name]) end
end

-- Our character's name as the rest of the guild sees it. Forever gives
-- characters a surname: UnitName("player") is just "Flyne" while the guild
-- roster, whispers and addon messages all use "Flyne Lee". The full name is
-- found in the guild roster (Roster:ScanGuild) and remembered per character.
function ns.PlayerName()
    return ns.selfName or (UnitName("player"))
end

-- Same character? Allows for realm suffixes, and for Forever surnames when
-- one side has only the first name ("Flyne" and "Flyne Lee").
function ns.SameName(a, b)
    if not a or not b then return false end
    a, b = Ambiguate(a, "none"), Ambiguate(b, "none")
    if a == b then return true end
    if not a:find(" ", 1, true) and b:match("^(%S+) ") == a then return true end
    if not b:find(" ", 1, true) and a:match("^(%S+) ") == b then return true end
    return false
end

function ns.SetSelfName(name)
    if not name or name == "" then return end
    name = Ambiguate(name, "none")
    if name == ns.selfName then return end
    -- records may be under the bare name we used before (UnitName)
    local old = ns.Sync and ns.Sync:GuildName() and ns.PlayerName()
    ns.selfName = name
    local guid = UnitGUID and UnitGUID("player")
    if guid and ns.db then
        ns.db.selfNames = ns.db.selfNames or {}
        ns.db.selfNames[guid] = name
    end
    if ns.db and ns.db.versions then ns.db.versions[ns.Sync:Me()] = nil end
    -- records we shared under the short name move to the full one
    if old and ns.Sync then ns.Sync:MoveAuthor(old, ns.Sync:Me()) end
end

local function restoreSelfName()
    local guid = UnitGUID and UnitGUID("player")
    local saved = guid and ns.db and ns.db.selfNames and ns.db.selfNames[guid]
    if saved and not ns.selfName then ns.selfName = saved end
end

-- Records that officers will sync (rosters, attendance, loot) carry an id,
-- a revision time and an author, so copies can be merged later.
function ns.Now()
    return GetServerTime and GetServerTime() or time()
end

-- Raid weeks run from the weekly reset (Tuesday 15:00 UTC); raid days from
-- 10:00 UTC, so an evening raid that runs past midnight is still one day.
function ns.Week(t)
    return math.floor(((t or ns.Now()) - 5 * 86400 - 15 * 3600) / 604800)
end

function ns.RaidDay(t)
    return math.floor(((t or ns.Now()) - 10 * 3600) / 86400)
end

local idCounter = 0
function ns.NewId()
    idCounter = idCounter + 1
    return ("%s-%d-%d"):format(ns.PlayerName() or "?", ns.Now(), idCounter)
end

function ns.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function ns.Touch(record)
    record.rev = ns.Now()
    record.by = ns.PlayerName()
end

------------------------------------------------------------------------
-- Saved data
------------------------------------------------------------------------
local DB_VERSION = 4

local function NewBoard(name)
    return { name = name or "New plan", map = nil, zoom = 1, cx = 0.5, cy = 0.5, items = {} }
end
ns.NewBoard = NewBoard

function ns.AddBoard(board)
    local db = ns.db
    db.nextId = db.nextId + 1
    local id = db.nextId
    db.boards[id] = board
    table.insert(db.order, id)
    return id
end

function ns.DeleteBoard(id)
    local db = ns.db
    db.boards[id] = nil
    for i = #db.order, 1, -1 do
        if db.order[i] == id then table.remove(db.order, i) end
    end
end

------------------------------------------------------------------------
-- Guild data: one table per guild, so an alt in another guild keeps its own
-- roster, attendance, loot and activity instead of marking the first guild
-- as having left. ns.db.guild is the one in use: only a pointer into
-- db.guilds, dropped at logout so it isn't saved twice.
--
-- Keyed by the guild's name alone. 0.16.1 and 0.16.2 added its realm, but on
-- connected realms the game names the guild's realm only some of the time,
-- so one guild ended up with two tables (and two sync stores) that took
-- turns; version 4 merges them back (mergeSplitGuilds).
------------------------------------------------------------------------
local NO_GUILD = "(no guild)"
ns.NO_GUILD = NO_GUILD

local function fillGuild(g)
    g.players = g.players or {}
    g.rosters = g.rosters or {}
    g.sessions = g.sessions or {}
    g.loot = g.loot or {}
    g.feed = g.feed or {}
    g.chat = g.chat or {}
    g.seenLoot = g.seenLoot or {}
    if g.maxLevelOnly == nil then g.maxLevelOnly = false end
    return g
end

-- Our guild's name, NO_GUILD outside one, nil while the client can't say
-- yet. Just after login the client says "not in a guild" even when we are
-- (0.16.2 filed a whole guild roster under "no guild" that way), so that's
-- only believed once the guild has had time to load (ns.guildKnown).
function ns.GuildKey()
    if IsInGuild() then
        local name = GetGuildInfo("player")
        if name and name ~= "" then return name end
        return nil
    end
    return ns.guildKnown and NO_GUILD or nil
end

local function charKey()
    return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "")
end

-- Saves from before 0.16.1 had one table for every guild. It goes to the
-- first guild that one of its own members logs in with.
local function legacyIsOurs(db)
    local first = UnitName("player")
    if not db.legacyGuild or not first then return false end
    for full in pairs(db.legacyGuild.players or {}) do
        local short = Ambiguate(full, "none")
        if short == first or short:sub(1, #first + 1) == first .. " " then return true end
    end
    return false
end

local guildHooks = {}
-- `fn` runs when the guild in use changes (caches built from its data).
function ns.OnGuildChanged(fn) guildHooks[#guildHooks + 1] = fn end

function ns.UseGuild(key)
    local db = ns.db
    if not db or not key or (db.guild and ns.guildKey == key) then return end
    local g = db.guilds[key]
    if not g and key ~= NO_GUILD and legacyIsOurs(db) then g = db.legacyGuild end
    g = fillGuild(g or {})
    if db.legacyGuild == g then db.legacyGuild = nil end
    db.guilds[key] = g
    local switched = db.guild ~= nil
    db.guild, ns.guildKey = g, key
    db.charGuild[charKey()] = key
    if switched then
        for _, fn in ipairs(guildHooks) do pcall(fn) end
    end
end

local function useCurrentGuild() ns.UseGuild(ns.GuildKey()) end
-- The guild has loaded (or there isn't one) once the client says so, or a
-- while after login.
local function guildKnown()
    ns.guildKnown = true
    useCurrentGuild()
end
ns.GUILD_LOAD_WAIT = 20
ns.On("PLAYER_LOGIN", function()
    useCurrentGuild()
    C_Timer.After(ns.GUILD_LOAD_WAIT, guildKnown)
end)
ns.On("PLAYER_GUILD_UPDATE", guildKnown)

-- v4: merge what 0.16.1 and 0.16.2 split ("Name-Realm" keys) back into one
-- table and one sync store per guild name, and empty the roster that the
-- login race filed under "no guild". Nothing a player made is dropped: of two
-- copies of a record the newer one is kept, and lists are joined.
local function guildName(key)
    return key ~= NO_GUILD and key:match("^([^-]+)%-.") or nil
end

local function newer(a, b)
    if not a then return b end
    if not b then return a end
    if (b.rev or 0) ~= (a.rev or 0) then return (b.rev or 0) > (a.rev or 0) and b or a end
    return a
end

local function joinList(a, b, max, keyOf)
    local seen, out = {}, {}
    for _, list in ipairs({ a or {}, b or {} }) do
        for _, e in ipairs(list) do
            local k = keyOf(e)
            if not seen[k] then
                seen[k] = true
                out[#out + 1] = e
            end
        end
    end
    table.sort(out, function(x, y) return (x.t or 0) > (y.t or 0) end)
    for i = #out, max + 1, -1 do out[i] = nil end
    return out
end

local function lastActive(g)
    local t = 0
    for _, list in ipairs({ g.feed or {}, g.chat or {} }) do
        for _, e in ipairs(list) do t = math.max(t, e.t or 0) end
    end
    return t
end

local function mergeGuildTables(into, from)
    for name, p in pairs(from.players or {}) do into.players[name] = into.players[name] or p end
    for _, field in ipairs({ "rosters", "sessions", "loot" }) do
        for id, rec in pairs(from[field] or {}) do into[field][id] = newer(into[field][id], rec) end
    end
    into.feed = joinList(into.feed, from.feed, 60, function(e)
        return tostring(e.t) .. (e.kind or "") .. tostring(e.name) .. tostring(e.value) end)
    into.chat = joinList(into.chat, from.chat, 100, function(e) return tostring(e.t) .. tostring(e.name) .. tostring(e.text) end)
    into.seenLoot = joinList(into.seenLoot, from.seenLoot, 100, function(e)
        return tostring(e.t) .. tostring(e.player) .. tostring(e.itemID) end)
    into.scanned = into.scanned or from.scanned
    into.fullScan = into.fullScan or from.fullScan
    into.activeSession = into.activeSession or from.activeSession
    for _, field in ipairs({ "officerRank", "benchCredit", "attAuto", "lootMinQuality" }) do
        if into[field] == nil then into[field] = from[field] end
    end
end

local function mergeSplitGuilds(db)
    local groups = {}
    for key in pairs(db.guilds) do
        local name = guildName(key)
        if name then
            groups[name] = groups[name] or {}
            table.insert(groups[name], key)
        end
    end
    for name, keys in pairs(groups) do
        -- the one used most recently is the base; the others join it
        local all = {}
        if db.guilds[name] then all[1] = db.guilds[name] end
        for _, k in ipairs(keys) do all[#all + 1] = db.guilds[k] end
        table.sort(all, function(a, b) return lastActive(a) > lastActive(b) end)
        local base = fillGuild(all[1])
        for i = 2, #all do mergeGuildTables(base, fillGuild(all[i])) end
        for _, k in ipairs(keys) do db.guilds[k] = nil end
        db.guilds[name] = base
    end
    -- shared records: one store per guild name, the newer copy of each record
    -- (keys gathered first: adding stores while walking the list skips some)
    local split = {}
    for key in pairs(db.sync or {}) do
        if guildName(key) then split[#split + 1] = key end
    end
    for _, key in ipairs(split) do
        local name, store = guildName(key), db.sync[key]
        local target = db.sync[name] or {}
        db.sync[name] = target
        for collection, recs in pairs(store) do
            target[collection] = target[collection] or {}
            for id, rec in pairs(recs) do target[collection][id] = newer(target[collection][id], rec) end
        end
        db.sync[key] = nil
    end
    for char, key in pairs(db.charGuild) do db.charGuild[char] = guildName(key) or key end
    -- "no guild" never holds a guild roster: drop what the login race filed
    -- there (guild members, their activity and guild chat), keep the rest
    local none = db.guilds[NO_GUILD]
    if none then
        for name, p in pairs(none.players or {}) do
            if p.inGuild then none.players[name] = nil end
        end
        none.feed, none.chat, none.scanned, none.fullScan = {}, {}, nil, nil
    end
end
ns.On("PLAYER_LOGOUT", function()
    if ns.db then ns.db.guild = nil end
end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    PogRaidDB = PogRaidDB or {}
    local db = PogRaidDB
    db.boards = db.boards or {}
    db.order = db.order or {}
    db.nextId = db.nextId or 0
    db.frames = db.frames or {}
    db.encounters = db.encounters or {}
    db.guilds = db.guilds or {}
    db.charGuild = db.charGuild or {}
    -- v3: per-guild data; the old single table waits for its guild
    if (db.version or 1) < 3 and db.guild then db.legacyGuild = fillGuild(db.guild) end
    db.guild = nil
    if (db.version or 1) < 4 then mergeSplitGuilds(db) end
    db.settings = db.settings or {}
    local st = db.settings
    st.minimap = st.minimap or { angle = 220 }
    if st.sounds == nil then st.sounds = true end
    if st.joinPopups == nil then st.joinPopups = true end
    if st.duelChallenges == nil then st.duelChallenges = true end
    if st.profileSongs == nil then st.profileSongs = true end
    if st.groupToasts == nil then st.groupToasts = true end
    if st.theme == nil then st.theme = st.classic == false and "plain" or ns.UI.DEFAULT_THEME end
    st.classic = nil
    ns.UI.SetTheme(st.theme)
    -- v2: "max level only" used to default on, which hid every raider on the
    -- beta (nobody at cap yet). It was never a choice, so reset it.
    if (db.version or 1) < 2 and db.legacyGuild then db.legacyGuild.maxLevelOnly = false end
    db.version = DB_VERSION
    ns.db = db
    -- the guild we're in, else the one this character was in last time,
    -- else a blank table until the client tells us (it moves over then)
    ns.guildKey = nil
    ns.UseGuild(ns.GuildKey() or db.charGuild[charKey()])
    if not db.guild then db.guild = fillGuild({}) end
    if #db.order == 0 then ns.AddBoard(NewBoard("First plan")) end
    restoreSelfName()
end)

ns.On("PLAYER_LOGIN", restoreSelfName)

-- Remember every boss we see engaged, so boards can be matched to
-- encounter IDs later (Forever's new raids have no published IDs yet).
ns.On("ENCOUNTER_START", function(encounterID, encounterName, difficultyID, groupSize)
    if not ns.db then return end
    ns.db.encounters[tostring(encounterID)] = encounterName
    if ns.probeVerbose then
        ns.Print(("ENCOUNTER_START %s (%s), difficulty %s, size %s"):format(
            tostring(encounterID), tostring(encounterName), tostring(difficultyID), tostring(groupSize)))
    end
end)

------------------------------------------------------------------------
-- /pog probe: report what this client supports, for the beta checks.
------------------------------------------------------------------------
local function yesno(v) return v and "|cff40ff40yes|r" or "|cffff4040no|r" end

function ns.Probe()
    ns.probeVerbose = true
    local version, build, _, iface = GetBuildInfo()
    ns.Print(("probe: client %s build %s interface %s"):format(tostring(version), tostring(build), tostring(iface)))

    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    ns.Print(("map: %s (%s)"):format(tostring(mapID), info and info.name or "?"))
    if mapID then
        local layers = C_Map.GetMapArtLayers(mapID)
        local layer = layers and layers[1]
        if layer then
            local tiles = C_Map.GetMapArtLayerTextures(mapID, 1) or {}
            ns.Print(("map art: %d layer(s), %dx%d, tile %dx%d, %d textures"):format(
                #layers, layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight, #tiles))
        else
            ns.Print("map art: none for this map")
        end
        local groupID = C_Map.GetMapGroupID(mapID)
        local floors = groupID and C_Map.GetMapGroupMembersInfo(groupID)
        ns.Print(("floors in this map group: %d"):format(floors and #floors or 0))
        local EJ = C_EncounterJournal
        local ok, bosses = false, nil
        if EJ and EJ.GetEncountersOnMap then ok, bosses = pcall(EJ.GetEncountersOnMap, mapID) end
        ns.Print(("bosses on this map (Encounter Journal): %s"):format(ok and tostring(bosses and #bosses or 0) or "call failed"))
    end

    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    ns.Print(("instance ID: %s, in raid: %s, in group: %s"):format(tostring(instanceID), yesno(IsInRaid()), yesno(IsInGroup())))
    ns.Print(("draw lines: %s, clip children: %s"):format(
        yesno(UIParent.CreateLine ~= nil), yesno(UIParent.SetClipsChildren ~= nil)))
    ns.Print(("events: ENCOUNTER_START %s, CHAT_MSG_ADDON %s"):format(
        yesno(ns.registered.ENCOUNTER_START), yesno(ns.registered.CHAT_MSG_ADDON)))
    local function raw(fn)
        if not fn then return "missing" end
        local ok, v = pcall(fn)
        return ok and tostring(v) or "error"
    end
    ns.Print(("addon message lockdown: %s (InChatMessagingLockdown %s, AreOutgoingAddonChatMessagesRestricted %s)"):format(
        yesno(ns.Comm.IsRestricted()), raw(C_ChatInfo.InChatMessagingLockdown), raw(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)))
    local profs, readable = ns.Crafting:ReadProfessions()
    local names = {}
    for _, p in ipairs(profs) do names[#names + 1] = ("%s %d/%d"):format(p.name, p.rank, p.max) end
    ns.Print(("professions: %s (%s)"):format(readable and (names[1] and table.concat(names, ", ") or "none") or "can't read",
        GetProfessions and "profession slots" or "skill list"))
    ns.Print(("recipe reading: %s, events: TRADE_SKILL_SHOW %s"):format(
        yesno(C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs), yesno(ns.registered.TRADE_SKILL_SHOW)))
    local ok, n = pcall(GetNumGuildTradeSkill or function() return nil end)
    ns.Print(("built-in guild professions: %s"):format(ok and n and (n .. " entries") or "not available"))
    local okModel, model = pcall(CreateFrame, "DressUpModel")
    ns.Print(("character models: %s"):format(yesno(okModel and model)))
    if okModel and model then model:Hide() end
    for _, line in ipairs(ns.Bug:Performance()) do ns.Print(line) end
    ns.Comm.Ping()
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_POGRAID1 = "/pog"
SLASH_POGRAID2 = "/pograid"
SlashCmdList.POGRAID = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" then
        ns.Editor:Toggle()
    elseif cmd == "demo" then
        if (msg or ""):lower():match("clear") then ns.Demo:Clear() else ns.Demo:Add() end
    elseif cmd == "minimap" then
        ns.MinimapButton:SetHidden(not ns.db.settings.minimap.hide)
        if not ns.db.settings.minimap.hide then ns.Print("minimap button shown") end
    elseif cmd == "settings" then
        ns.Editor:Toggle("settings")
    elseif cmd == "duels" or cmd == "wowdle" or cmd == "gems" then
        ns.Editor:Toggle("games")
        if ns.Games.page then ns.Games:SetMode(cmd) end
    elseif cmd == "late" then
        local _, early = ns.Attendance:MyNotice()
        ns.Attendance:SetNotice(true, early)
    elseif cmd == "early" then
        local late = ns.Attendance:MyNotice()
        ns.Attendance:SetNotice(late, true)
    elseif cmd == "ontime" then
        ns.Attendance:SetNotice(false, false)
    elseif cmd == "profile" or cmd == "profiles" then
        local who = (msg or ""):match("^%s*%S+%s+(.-)%s*$")
        if who and who ~= "" then ns.Profiles:Open(who) else ns.Editor:Toggle("profiles") end
    elseif cmd == "crafting" or cmd == "craft" then
        ns.Editor:Toggle("crafting")
    elseif cmd == "plans" then
        ns.Editor:Toggle("boards")
    elseif cmd == "home" or cmd == "boards" or cmd == "roster" or cmd == "attendance" or cmd == "loot" or cmd == "games" then
        ns.Editor:Toggle(cmd)
    elseif cmd == "sync" then
        if (msg or ""):lower():match("ping") then ns.Comm.GuildPing() else ns.Bug:ShowSync() end
    elseif cmd == "bug" then
        if (msg or ""):lower():match("clear") then
            ns.Bug:Clear()
            ns.Print("error log cleared")
        else
            ns.Bug:Show()
        end
    elseif cmd == "probe" then
        ns.Probe()
    elseif cmd == "art" then
        if ns.Art then ns.Art:Toggle() end
    elseif cmd == "check" then
        ns.Comm.CheckRaid()
    elseif cmd == "test" then
        ns.Editor:SendCurrent(true)
    elseif cmd == "reset" then
        wipe(ns.db.frames)
        ns.Editor:ResetPosition()
        ns.Viewer:ResetPosition()
        ns.Print("window positions reset")
    else
        ns.Print("/pog opens the window. Also: home, roster, attendance, loot, crafting, games, gems, wowdle, duels, plans, settings, minimap, probe, art, bug, sync, check, test, reset")
    end
end
