-- Minimal WoW client stand-in for running PogRaid headless.
-- Frames are mock objects: PascalCase methods that are not implemented
-- here are no-ops, lowercase keys stay nil (so addon fields behave).

local UI_W, UI_H = 1366, 768
local M = {}
local MT = {
    __index = function(t, k)
        local m = M[k]
        if m then return m end
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end,
}

local eventFrames = {}
STUB = { sent = {}, timers = {}, printed = {}, restricted = false, throttleNext = 0,
    cursorX = 0, cursorY = 0, now = 100, mouseDown = {} }

local function new(kind, parent)
    local f = setmetatable({ __kind = kind, __parent = parent, __shown = true, __scripts = {},
        __w = 0, __h = 0, __scale = 1, __level = 1 }, MT)
    if parent then
        parent.__children = parent.__children or {}
        parent.__children[#parent.__children + 1] = f
    end
    return f
end
STUB.new = new

-- geometry ------------------------------------------------------------
local function rect(f)
    if f.__isUIParent then return 0, UI_H, UI_W, UI_H end
    if f.__all then
        local l, t, w, h = rect(f.__all)
        return l, t, w, h
    end
    local a = f.__anchor
    if not a then return nil end
    local rel = a.rel or f.__parent or UIParent
    local rl, rt, rw, rh = rect(rel)
    if not rl then return nil end
    local function px(name, l, w) return name:find("LEFT") and l or name:find("RIGHT") and l + w or l + w / 2 end
    local function py(name, t, h) return name:find("TOP") and t or name:find("BOTTOM") and t - h or t - h / 2 end
    local x = px(a.relPoint, rl, rw) + a.x
    local y = py(a.relPoint, rt, rh) + a.y
    local w, h = f.__w, f.__h
    local left = a.point:find("LEFT") and x or a.point:find("RIGHT") and x - w or x - w / 2
    local top = a.point:find("TOP") and y or a.point:find("BOTTOM") and y + h or y + h / 2
    return left, top, w, h
end
STUB.rect = rect

-- like the game: in combat a secure frame, and every frame it sits inside or
-- is anchored to, can't be shown, hidden or moved by an addon
STUB.secureFrames = {}
function STUB.Protected(f)
    for _, sf in ipairs(STUB.secureFrames) do
        local x = sf
        while x do
            if x == f then return true end
            x = x.__parent
        end
        if sf.__anchor and sf.__anchor.rel == f then return true end
    end
    return false
end
local function guard(f, what)
    if STUB.combat and STUB.Protected(f) then
        STUB.blocked = (STUB.blocked or 0) + 1
        error("ADDON_ACTION_BLOCKED: " .. what .. " on a protected frame in combat")
    end
end

function M:SetPoint(point, a, b, c, d)
    guard(self, "SetPoint")
    if self.__anchor then return end -- first anchor wins; enough for these tests
    local rel, relPoint, x, y
    if type(a) == "table" then
        rel, relPoint, x, y = a, b, c, d
        if type(relPoint) == "number" then relPoint, x, y = point, b, c end
    elseif type(a) == "string" then
        relPoint, x, y = a, b, c
    else
        x, y = a, b
    end
    self.__anchor = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
end
function M:ClearAllPoints() guard(self, "ClearAllPoints"); self.__anchor = nil; self.__all = nil end
function M:SetAllPoints(rel) self.__all = rel or self.__parent end
function M:SetSize(w, h) self.__w, self.__h = w, h end
function M:SetWidth(w) self.__w = w end
function M:SetHeight(h) self.__h = h end
function M:GetWidth() if self.__all then return select(3, rect(self)) end return self.__w end
function M:GetHeight() if self.__all then return select(4, rect(self)) end return self.__h end
function M:GetLeft() local l = rect(self) return l end
function M:GetTop() local _, t = rect(self) return t end
function M:GetRight() local l, _, w = rect(self) return l and l + w end
function M:GetBottom() local _, t, _, h = rect(self) return t and t - h end
function M:GetCenter()
    local l, t, w, h = rect(self)
    if not l then return nil end
    return l + w / 2, t - h / 2
end
function M:GetEffectiveScale() return 1 end
function M:SetScale(s) self.__scale = s end
function M:GetScale() return self.__scale end
function M:GetFrameLevel() return self.__level end
function M:GetParent() return self.__parent end
function M:SetFrameLevel(l) self.__level = l end

-- visibility / scripts -------------------------------------------------
-- like the game: a frame appearing or going away takes its shown children
-- with it (OnShow / OnHide)
local function cascade(f, script)
    for _, c in ipairs(f.__children or {}) do
        if c.__shown then
            if c.__scripts[script] then c.__scripts[script](c) end
            cascade(c, script)
        end
    end
end
function M:Show()
    guard(self, "Show")
    local was = self.__shown
    self.__shown = true
    if not was then
        if self.__scripts.OnShow then self.__scripts.OnShow(self) end
        cascade(self, "OnShow")
    end
end
function M:Hide()
    guard(self, "Hide")
    local was = self.__shown
    self.__shown = false
    if was then
        if self.__scripts.OnHide then self.__scripts.OnHide(self) end
        cascade(self, "OnHide")
    end
end
function M:IsShown() return self.__shown end
function M:IsVisible() return self.__shown end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:SetScript(name, fn) self.__scripts[name] = fn end
function M:GetScript(name) return self.__scripts[name] end
function M:HookScript(name, fn)
    local old = self.__scripts[name]
    self.__scripts[name] = function(...) if old then old(...) end fn(...) end
end
-- like the game: an addon can't change keyboard capture during combat
function M:EnableKeyboard(on)
    if STUB.combat then STUB.blocked = (STUB.blocked or 0) + 1; error("ADDON_ACTION_BLOCKED: EnableKeyboard in combat") end
    self.__keyboard = on
end
function M:SetPropagateKeyboardInput(on)
    if STUB.combat then STUB.blocked = (STUB.blocked or 0) + 1; error("ADDON_ACTION_BLOCKED: SetPropagateKeyboardInput in combat") end
    self.__propagate = on
end
function M:IsMouseOver() return STUB.hover == self end
function M:SetEnabled(on) self.__disabled = not on end
function M:SetAlpha(a) self.__alpha = a end
-- a ScrollingMessageFrame keeps its lines
function M:AddMessage(msg) self.__messages = self.__messages or {}; table.insert(self.__messages, msg) end
function M:Clear() self.__messages = {} end
function M:SetDesaturated(on) self.__desaturated = on and true or false end
function M:GetAlpha() return self.__alpha or 1 end
function M:IsEnabled() return not self.__disabled end

-- regions ---------------------------------------------------------------
function M:CreateTexture() return new("Texture", self) end
function M:CreateLine() return new("Line", self) end
function M:CreateAnimationGroup() return new("AnimationGroup", self) end
function M:CreateFontString() return new("FontString", self) end
function M:CreateMaskTexture() return new("MaskTexture", self) end
function M:SetFont(font, size) self.__font, self.__fontSize = font, size end
function M:SetText(t)
    if self.__kind == "FontString" and not self.__font then error("FontString:SetText(): Font not set") end
    local was = self.__text
    self.__text = t
    -- like the game: an edit box runs OnTextChanged (userInput false) when its text changes
    if self.__kind == "EditBox" and was ~= t and self.__scripts and self.__scripts.OnTextChanged then
        self.__scripts.OnTextChanged(self, false)
    end
end
function M:GetText() return self.__text end
-- models (DressUpModel): SetUnit dresses in the unit's gear, TryOn adds an item
function M:SetUnit(unit) self.__unit, self.__tried, self.__dressed = unit, {}, (self.__dressed or 0) + 1 end
function M:TryOn(link) table.insert(self.__tried, link) end
function M:SetFacing(f) self.__facing = f end
function M:Undress() self.__tried = {} end
function M:ClearModel() self.__unit, self.__race, self.__tried = nil, nil, {} end
function M:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a } end
function M:SetJustifyH(j) self.__justifyH = j end
function M:GetStringWidth() return #(self.__text or "") * 6 end
function M:SetTexture(t) self.__texture = t; self.__color = nil end
function M:GetTexture() return self.__texture end
function M:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a } end
function M:SetTexCoord(...)
    if self.__mask then error("Texture:SetTexCoord(): can't be used on a texture with a mask") end
    self.__coord = { ... }
end
function M:SetMask(path) self.__mask = path end
function M:SetAtlas(name) self.__atlas = name end
function M:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a }; self.__texture = nil end
function M:SetBlendMode(mode) self.__blend = mode end
function M:SetGradient(orientation, minColor, maxColor) self.__gradient = { orientation, minColor, maxColor } end
-- frames made with "BackdropTemplate" (the game's border and fill mixin)
function M:SetBackdrop(b) self.__backdrop = b end
function M:SetBackdropBorderColor(r, g, b, a) self.__borderColor = { r, g, b, a } end
function M:SetAttribute(k, v) self.__attr = self.__attr or {}; self.__attr[k] = v end
function M:RegisterForClicks(...) self.__clicks = { ... } end
function M:SetStartPoint(_, _, x, y) self.__start = { x, y } end
function M:SetEndPoint(_, _, x, y) self.__end = { x, y } end

-- edit boxes --------------------------------------------------------------
function M:SetFocus() self.__focus = true; if self.__scripts.OnEditFocusGained then self.__scripts.OnEditFocusGained(self) end end
function M:ClearFocus()
    local had = self.__focus
    self.__focus = false
    if had and self.__scripts.OnEditFocusLost then self.__scripts.OnEditFocusLost(self) end
end
function M:HasFocus() return self.__focus end
function M:Insert(t) self.__text = (self.__text or "") .. t end

-- events ----------------------------------------------------------------
local UNKNOWN_EVENTS = { NOT_A_REAL_EVENT = true }
function M:RegisterEvent(event)
    if UNKNOWN_EVENTS[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
    eventFrames[event] = eventFrames[event] or {}
    table.insert(eventFrames[event], self)
end

function STUB.Fire(event, ...)
    for _, f in ipairs(eventFrames[event] or {}) do
        local fn = f.__scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end

function STUB.Script(frame, name, ...)
    local fn = frame.__scripts[name]
    assert(fn, "no script " .. name)
    return fn(frame, ...)
end

function CreateFrame(kind, name, parent, template)
    local f = new(kind, parent or UIParent)
    if type(template) == "string" and template:find("Secure", 1, true) then
        f.__secure = true
        STUB.secureFrames[#STUB.secureFrames + 1] = f
    end
    if name then _G[name] = f end
    return f
end

UIParent = new("Frame")
UIParent.__isUIParent = true
UIParent.__w, UIParent.__h = UI_W, UI_H

-- world ------------------------------------------------------------------
STUB.player = "Jake"
STUB.roster = nil -- { {name=, rank=, class=} } when in raid
STUB.party = nil  -- { {name=, class=, leader=} } when in party

function UnitName(unit) if unit == "player" then return STUB.player end end
STUB.realm = "Realm"
function GetRealmName() return STUB.realm end
function UnitGUID(unit) if unit == "player" then return STUB.guid end end
function UnitClass(unit)
    if unit == "player" then return "Hunter", "HUNTER" end
    local i = unit:match("^party(%d)")
    local p = i and STUB.party and STUB.party[tonumber(i)]
    if p then return p.class, p.class end
end
function GetUnitName(unit)
    if unit == "player" then return STUB.player end
    local i = unit:match("^party(%d)")
    local p = i and STUB.party and STUB.party[tonumber(i)]
    return p and p.name
end
function UnitGroupRolesAssigned() return "DAMAGER" end
function IsInRaid() return STUB.roster ~= nil end
function IsInGroup() return STUB.roster ~= nil or STUB.party ~= nil end
function GetNumGroupMembers() return STUB.roster and #STUB.roster or (STUB.party and #STUB.party + 1 or 0) end
function GetNumSubgroupMembers() return STUB.party and #STUB.party or 0 end
function GetRaidRosterInfo(i)
    local r = STUB.roster and STUB.roster[i]
    if r then return r.name, r.rank or 0, r.sub or 1, 60, r.class, r.class, "Zone", r.online ~= false end
end
function UnitIsGroupLeader(unit)
    if unit == "player" then return STUB.isLeader end
    local i = unit:match("^party(%d)")
    local p = i and STUB.party and STUB.party[tonumber(i)]
    return p and p.leader or false
end
function UnitIsGroupAssistant(unit) if unit == "player" then return STUB.isAssist or false end return false end
function Ambiguate(name) return (name:match("^[^-]+")) end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2

RAID_CLASS_COLORS = { HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 } }

function GetTime() return STUB.now end
function GetCursorPosition() return STUB.cursorX, STUB.cursorY end
function IsMouseButtonDown(b) return STUB.mouseDown[b] or false end
STUB.race, STUB.sex = 7, 2 -- gnome, male
function UnitRace(unit) if unit == "player" then return "Gnome", "Gnome", STUB.race end end
function UnitSex(unit) if unit == "player" then return STUB.sex end end
function UnitIsVisible(unit) return UnitExists(unit) end
function GetInventoryItemID(unit, slot) return unit == "player" and STUB.worn and STUB.worn[slot] or nil end
function GetInventorySlotInfo(name) return 1, "slot-" .. name end
function IsShiftKeyDown() return STUB.shift or false end
-- the player's numbers, shaped like the game's returns (base, effective, ...)
STUB.unitStats = { hp = 4200, mana = 3100, stats = { 120, 95, 140, 210, 180 }, armor = 1850 }
function UnitHealthMax(unit) return unit == "player" and STUB.unitStats.hp or 0 end
function UnitPowerMax(unit) return unit == "player" and STUB.unitStats.mana or 0 end
function UnitStat(unit, i) local v = STUB.unitStats.stats[i] or 0 return v, v, 0, 0 end
function UnitArmor(unit) local v = STUB.unitStats.armor return v, v, v, 0, 0 end
function GetBuildInfo() return "1.60.1", "70009", "Sep 24 2026", 16001 end
STUB.instance = { "Stormwind", "none" }
function GetInstanceInfo() return STUB.instance[1], STUB.instance[2], 0, "", 0, 0, false, 0 end
function SetRaidTargetIconTexture(tex, i) tex.__raidIcon = i end
STUB.sounds = {}
function PlaySound(id) table.insert(STUB.sounds, id) end
-- like the game: an addon calling ReloadUI is blocked ("Interface action failed because of an AddOn")
function ReloadUI() error("ADDON_ACTION_BLOCKED: ReloadUI") end
-- the game's frame layouts: lays a named border kit onto a "NineSlicePanelTemplate" frame,
-- creating its corner and edge pieces as textures like the game does
local NINE_SLICE_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
NineSliceUtil = { ApplyLayoutByName = function(f, name)
    f.__layout = name
    for _, key in ipairs(NINE_SLICE_PIECES) do
        if rawget(f, key) == nil then rawset(f, key, f:CreateTexture()) end
    end
end }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- where each class sits on Interface\TargetingFrame\UI-Classes-Circles (the game's own table)
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 } }
-- music: PlayMusic replaces the zone music until StopMusic
function PlayMusic(file) STUB.music = file return true end
function StopMusic() STUB.music = nil end
SOUNDKIT = { RAID_WARNING = 8959, IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840, IG_CHARACTER_INFO_TAB = 841,
    IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857, TELL_MESSAGE = 3081,
    IG_QUEST_LIST_COMPLETE = 878 }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
STUB.errorHandler = function(e) error(e, 0) end
function geterrorhandler() return STUB.errorHandler end
function seterrorhandler(fn) STUB.errorHandler = fn end
function debugstack() return STUB.stack or "" end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(STUB.printed, msg) end }

C_Timer = {
    After = function(delay, fn) table.insert(STUB.timers, { at = STUB.now + delay, fn = fn }) end,
}
function STUB.Advance(sec)
    STUB.now = STUB.now + sec
    local ran = true
    while ran do
        ran = false
        for i, t in ipairs(STUB.timers) do
            if t.at <= STUB.now then
                table.remove(STUB.timers, i)
                t.fn()
                ran = true
                break
            end
        end
    end
end

-- maps --------------------------------------------------------------------
local MAPS = {
    [1453] = { name = "Stormwind City", group = 7, layer = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } },
    [2001] = { name = "Skyreach Hall", group = 9, layer = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } },
    [2002] = { name = "Skyreach Spire", group = 9, layer = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } },
}
STUB.currentMap = 1453
C_Map = {
    GetBestMapForUnit = function() return STUB.currentMap end,
    GetMapInfo = function(id) local m = MAPS[id] return m and { mapID = id, name = m.name } end,
    GetMapArtLayers = function(id) local m = MAPS[id] return m and { m.layer } end,
    GetMapArtLayerTextures = function(id)
        local m = MAPS[id]
        if not m then return nil end
        local cols = math.ceil(m.layer.layerWidth / m.layer.tileWidth)
        local rows = math.ceil(m.layer.layerHeight / m.layer.tileHeight)
        local out = {}
        for i = 1, cols * rows do out[i] = 100000 + i end
        return out
    end,
    GetMapGroupID = function(id) local m = MAPS[id] return m and m.group end,
    GetMapGroupMembersInfo = function(g)
        if g == 9 then return { { mapID = 2001, name = "Skyreach Hall" }, { mapID = 2002, name = "Skyreach Spire" } } end
        return nil
    end,
}
C_EncounterJournal = {
    GetEncountersOnMap = function(id)
        if id == 2001 then return { { encounterID = 3001, mapX = 0.3, mapY = 0.4 } } end
        return {}
    end,
}
function EJ_GetEncounterInfo(id) if id == 3001 then return "Stormcaller Vael" end end

-- chat -------------------------------------------------------------------
Enum = { SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2,
    AddonMessageThrottle = 3, InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6,
    InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9 } }
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) STUB.prefix = p return true end,
    SendAddonMessage = function(prefix, text, channel, target)
        assert(#text <= 255, "addon message over 255 bytes: " .. #text)
        if STUB.restricted then return Enum.SendAddonMessageResult.GeneralError end
        if STUB.throttleNext > 0 then
            STUB.throttleNext = STUB.throttleNext - 1
            return Enum.SendAddonMessageResult.AddonMessageThrottle
        end
        -- the live client's per-prefix allowance: 10 messages, 1 back per second
        if STUB.realThrottle then
            local b = math.min(10, (STUB.allowance or 10) + (STUB.now - (STUB.allowanceAt or STUB.now)))
            STUB.allowanceAt = STUB.now
            if b < 1 then
                STUB.allowance = b
                return Enum.SendAddonMessageResult.AddonMessageThrottle
            end
            STUB.allowance = b - 1
        end
        table.insert(STUB.sent, { prefix = prefix, text = text, channel = channel, target = target, at = STUB.now })
        return Enum.SendAddonMessageResult.Success
    end,
    InChatMessagingLockdown = function() return STUB.restricted end,
    -- Forever answers true all the time (it's about ordinary chat); must not block addon messages
    AreOutgoingAddonChatMessagesRestricted = function() return true end,
}

-- Deliver everything sent so far as CHAT_MSG_ADDON, as if from `sender`.
-- `order` optionally permutes the messages.
function STUB.Deliver(sender, order)
    local msgs = STUB.sent
    STUB.sent = {}
    local list = {}
    if order then
        for _, i in ipairs(order) do list[#list + 1] = msgs[i] end
    else
        list = msgs
    end
    for _, m in ipairs(list) do
        STUB.Fire("CHAT_MSG_ADDON", m.prefix, m.text, m.channel, sender or (STUB.player .. "-Realm"))
    end
    return #list
end


-- guild -------------------------------------------------------------------
STUB.guild = nil -- list of { name, rank, rankIndex, level, online, class }
STUB.ranks = { "Guild Master", "Officer", "Raider", "Trial", "Social" }
-- like the game: just after login it can say "not in a guild" (guildLoading), or know the guild without
-- its name yet (guildNameLoading); on connected realms the guild's realm comes and goes (guildRealm)
function IsInGuild() return STUB.guild ~= nil and not STUB.guildLoading end
function GetGuildInfo(unit)
    if STUB.guild and not STUB.guildLoading and not STUB.guildNameLoading then
        return STUB.guildName or "Pog Squad", "Member", 3, STUB.guildRealm
    end
end
function GetNumGuildMembers() return STUB.guild and #STUB.guild or 0 end
function GetGuildRosterInfo(i)
    local m = STUB.guild and STUB.guild[i]
    if m then
        return m.name, STUB.ranks[m.rankIndex + 1], m.rankIndex, m.level, m.class, m.zone or "", "", "", m.online, 0, m.class,
            0, 0, false, false, 0, m.guid
    end
end
function GuildControlGetNumRanks() return #STUB.ranks end
function GuildControlGetRankName(i) return STUB.ranks[i] end
STUB.motd, STUB.guildInfo, STUB.showOffline = "", "", true
C_GuildInfo = {
    GuildRoster = function() STUB.guildRequests = (STUB.guildRequests or 0) + 1 end,
    GetMOTD = function() return STUB.motd end,
    GetInfoText = function() return STUB.guildInfo end,
    SetMOTD = function(t) STUB.motd = t end,
}
function CanEditMOTD() return STUB.canEditMOTD or false end
function GetGuildRosterShowOffline() return STUB.showOffline end
function GetServerTime() return math.floor(STUB.now) + 1790000000 end
date = os.date
time = os.time
function GetMaxPlayerLevel() return 60 end
function InCombatLockdown() return STUB.combat or false end

-- party / raid control ------------------------------------------------------
STUB.invites, STUB.converts, STUB.raidMoves = {}, 0, 0
C_PartyInfo = {
    InviteUnit = function(name) table.insert(STUB.invites, name) end,
    ConvertToRaid = function() STUB.converts = STUB.converts + 1 end,
}
local function groupCount(g)
    local n = 0
    for _, r in ipairs(STUB.roster or {}) do if (r.sub or 1) == g then n = n + 1 end end
    return n
end
function SetRaidSubgroup(i, g)
    assert(groupCount(g) < 5, "SetRaidSubgroup into a full group")
    STUB.roster[i].sub = g
    STUB.raidMoves = STUB.raidMoves + 1
end
function SwapRaidSubgroup(i, j)
    STUB.roster[i].sub, STUB.roster[j].sub = STUB.roster[j].sub or 1, STUB.roster[i].sub or 1
    STUB.raidMoves = STUB.raidMoves + 1
end


-- loot ----------------------------------------------------------------------
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
function STUB.Link(id, name, color)
    return ("|cff%s|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(color or "a335ee", id, name)
end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
function ChatEdit_InsertLink(text) return false end
function hooksecurefunc(name, fn)
    local orig = _G[name]
    _G[name] = function(...) local r = orig(...) fn(...) return r end
end
-- Like the game: an item link brings up the "Currently equipped" comparison
-- (ShoppingTooltip1/2) when the client always compares (STUB.alwaysCompare,
-- on by default as on Jake's client) or Shift is held; it goes with the tooltip.
ShoppingTooltip1 = CreateFrame("Frame")
ShoppingTooltip2 = CreateFrame("Frame")
STUB.alwaysCompare = true
local function hideCompare() ShoppingTooltip1:Hide() ShoppingTooltip2:Hide() end
GameTooltip = setmetatable({ lines = {}, shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 } }, { __index = function(t, k)
    if k == "AddLine" then return function(self, text) table.insert(self.lines, text) end end
    if k == "AddDoubleLine" then return function(self, a, b) table.insert(self.lines, a .. " | " .. tostring(b)) end end
    if k == "SetOwner" then return function(self, owner) self.owner = owner self.lines = {} self.shown = false hideCompare() end end
    if k == "GetOwner" then return function(self) return self.owner end end
    if k == "IsShown" then return function(self) return self.shown end end
    if k == "Show" then return function(self) self.shown = true end end
    if k == "Hide" then return function(self) self.shown = false hideCompare() end end
    if k == "SetHyperlink" then return function(self, link)
        self.link = link
        self.shown = true
        if link:find("|Hitem:", 1, true) and (STUB.alwaysCompare or IsShiftKeyDown()) then ShoppingTooltip1:Show() end
    end end
    return nil
end })

-- duels -------------------------------------------------------------------
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
STUB.duels = {}
function StartDuel(name) table.insert(STUB.duels, name) end
function UnitExists(unit) return unit == "target" and STUB.target ~= nil end
function UnitIsPlayer(unit) return unit == "target" and STUB.target ~= nil end
local baseUnitName = UnitName
function UnitName(unit) if unit == "target" then return STUB.target end return baseUnitName(unit) end

-- macro icons ---------------------------------------------------------------
-- the client's macro icons: file IDs, classic art below 140000 and later art
-- above (a name now and then, and repeats of ours)
function GetMacroIcons(t)
    for i = 1, 300 do t[#t + 1] = 139000 + i end
    for i = 1, 50 do t[#t + 1] = 236000 + i end
    t[#t + 1] = "INV_Misc_QuestionMark"
    t[#t + 1] = 134169
end

-- minimap -------------------------------------------------------------------
Minimap = new("Frame")
Minimap.__w, Minimap.__h = 140, 140
Minimap.__anchor = { point = "TOPRIGHT", rel = UIParent, relPoint = "TOPRIGHT", x = -20, y = -20 }
