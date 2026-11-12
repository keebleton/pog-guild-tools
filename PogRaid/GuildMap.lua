-- Pog Guild Tools: guildies on the world map (0.18.0, asked for by guildies).
--
-- The game only shows group members on the map, and an addon can't read where
-- anyone else is. So each addon says where its own player is, on the guild's
-- addon channel, and draws a class-coloured dot for everyone it hears from.
-- Only guildies with Pog Guild Tools 0.18 or newer show up, and only out in
-- the world (the game gives no position inside dungeons and raids).
--
-- Wire (Comm kind "G", one short message, never chunked):
--   G1:<map>:<x>:<y>:<continent>:<wx>:<wy>   x, y = 0..10000 across the zone map;
--                                            the last three are the spot in world
--                                            yards (may be empty), for drawing on a
--                                            map other than the sender's own zone
--   G0                                       no position any more (instance, switched off)
-- Sent when we've moved, at most every MIN_GAP seconds, and every BEAT seconds
-- while standing still; a dot is dropped STALE seconds after its last message.
-- "Guildies on the map" (settings.guildMap, /pog map, the minimap button's
-- menu) turns both the sending and the dots off.
local _, ns = ...

local GuildMap = {}
ns.GuildMap = GuildMap

GuildMap.TICK = 5        -- seconds between looks at where we are
GuildMap.MIN_GAP = 20    -- seconds between two messages while moving
GuildMap.BEAT = 120      -- seconds between two messages while standing still
GuildMap.STALE = 300     -- a dot not heard from for this long is dropped
GuildMap.OFFLINE = 45    -- the roster says they logged off: the dot goes after this
GuildMap.MOVE = 0.004    -- of the zone map: less than this isn't "moved"
-- The dots are OneForAll's dots (Jake has both addons and saw two sizes side by side): the game's
-- own party blip, 14px on a zone map and 10px on a continent, tinted to the class, sized against
-- the map's canvas scale exactly as OneForAll does. Our own disc is only for a client without it.
GuildMap.SIZE = 14
GuildMap.SIZE_FAR = 10
GuildMap.BLIP = "PlayerPartyBlip"
GuildMap.CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
GuildMap.DISC = "Interface\\AddOns\\PogRaid\\Media\\disc"
GuildMap.where = {}      -- [name] = { map, x, y, cont, wx, wy, at = GetTime() }
GuildMap.pins = {}

local function secret(v) return issecretvalue and issecretvalue(v) or false end

local function xy(pos)
    if not pos then return nil end
    if pos.GetXY then return pos:GetXY() end
    return pos.x, pos.y
end

function GuildMap:On()
    return ns.db.settings.guildMap ~= false
end

------------------------------------------------------------------------
-- Saying where we are
------------------------------------------------------------------------
-- Where our player is: map, x, y (0..1), and the world spot if the client
-- can work it out. nil where the game gives no position.
function GuildMap:Mine()
    if IsInInstance and IsInInstance() then return nil end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map or secret(map) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    local x, y = xy(ok and pos or nil)
    if not x or not y or secret(x) or secret(y) or (x == 0 and y == 0) then return nil end
    local here = { map = map, x = x, y = y }
    if C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local okWorld, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
        local wx, wy = xy(okWorld and world or nil)
        if cont and wx and wy and not secret(wx) then here.cont, here.wx, here.wy = cont, wx, wy end
    end
    return here
end

function GuildMap.Encode(here)
    local function int(v) return v and ("%d"):format(math.floor(v + 0.5)) or "" end
    return ("1:%d:%d:%d:%s:%s:%s"):format(here.map, math.floor(here.x * 10000 + 0.5), math.floor(here.y * 10000 + 0.5),
        int(here.cont), int(here.wx), int(here.wy))
end

-- What a message says: a place, false for "gone", nil for anything else.
function GuildMap.Decode(body)
    if body == "0" then return false end
    if type(body) ~= "string" or #body > 80 then return nil end
    local map, x, y, cont, wx, wy = body:match("^1:(%d+):(%d+):(%d+):(%-?%d*):(%-?%d*):(%-?%d*)$")
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not map or map > 999999 or x > 10000 or y > 10000 then return nil end
    local place = { map = map, x = x / 10000, y = y / 10000 }
    cont, wx, wy = tonumber(cont), tonumber(wx), tonumber(wy)
    if cont and wx and wy then place.cont, place.wx, place.wy = cont, wx, wy end
    return place
end

function GuildMap:Send(body)
    self.sent, self.sentAt = body, GetTime()
    ns.Comm.Send("G" .. body, "GUILD", nil, true)
end

-- Every TICK: tell the guild if we've moved (or it's been a while), and keep
-- an open map's dots current.
function GuildMap:Tick()
    C_Timer.After(GuildMap.TICK, function() self:Tick() end)
    self:Refresh()
    if not self:On() or not ns.Sync:GuildName() then return end
    -- behind a long sync our place would only go stale in the queue: next tick
    if not ns.Comm.BulkIdle() then return end
    local here = self:Mine()
    if not here then
        if self.sent and self.sent ~= "0" then self:Send("0") end
        self.last = nil
        return
    end
    local last = self.last
    local moved = not last or last.map ~= here.map
        or math.abs(last.x - here.x) + math.abs(last.y - here.y) >= GuildMap.MOVE
    local since = GetTime() - (self.sentAt or -1e9)
    if (moved and since >= GuildMap.MIN_GAP) or since >= GuildMap.BEAT then
        self.last = here
        self:Send(GuildMap.Encode(here))
    end
end

function GuildMap:Set(on)
    ns.db.settings.guildMap = on and true or false
    if not on and self.sent and self.sent ~= "0" and ns.Sync:GuildName() then self:Send("0") end
    if on then self.sentAt = nil end
    self.last = nil
    self:Refresh()
    if ns.Settings and ns.Settings.Changed then ns.Settings:Changed() end
end

------------------------------------------------------------------------
-- Hearing where the others are
------------------------------------------------------------------------
function GuildMap:OnMessage(sender, body)
    local name = ns.Attendance:Key(sender)
    if not name then return end
    local place = GuildMap.Decode(body)
    if place == nil then return end
    if place then
        place.at = GetTime()
        self.where[name] = place
    else
        self.where[name] = nil
    end
    self:Changed()
end

-- Is this one still worth a dot? (Also forgets the ones that aren't.)
function GuildMap:Fresh(name, place, now)
    local age = now - place.at
    local p = ns.db.guild and ns.db.guild.players[name]
    local offline = p ~= nil and ns.Roster.online[name] ~= true
    if age > GuildMap.STALE or (offline and age > GuildMap.OFFLINE) then
        self.where[name] = nil
        return false
    end
    return true
end

------------------------------------------------------------------------
-- Living with OneForAll (Jake has both, and so will some guildies)
--
-- OneForAll draws guildies on the map too, from its own messages (prefix
-- "OFAGuildPos" on GUILD: "P<tab>map<tab>x<tab>y..." a place, "X" gone, "I..."
-- inside a dungeon). The two addons use different prefixes and their own
-- frames, so neither can break the other; the one clash is a guildie who runs
-- both getting two dots on top of each other. So we listen to OneForAll's
-- messages (it registered the prefix; we never send on it) and leave a
-- guildie to OneForAll's dot while OneForAll is loaded here with its own
-- guild map switched on and has a place for them.
------------------------------------------------------------------------
GuildMap.OTHER = "OneForAll"
GuildMap.OTHER_PREFIX = "OFAGuildPos"
GuildMap.OTHER_FORGET = 180   -- OneForAll drops a dot this long after its last message
GuildMap.theirs = {}          -- [name] = GetTime() of their last OneForAll place

-- Is OneForAll drawing guildies on this client?
function GuildMap:OtherOn()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(GuildMap.OTHER))
        or (IsAddOnLoaded and IsAddOnLoaded(GuildMap.OTHER))
    if not loaded then return false end
    local q = type(OneForAllDB) == "table" and type(OneForAllDB.qol) == "table" and OneForAllDB.qol
    return not (q and q.guildMap == false)
end

function GuildMap:OnOther(sender, msg)
    local name = ns.Attendance:Key(sender)
    if not name or type(msg) ~= "string" then return end
    local kind = msg:sub(1, 1)
    if kind == "P" then
        self.theirs[name] = GetTime()
    elseif kind == "X" or kind == "I" then
        self.theirs[name] = nil
    else
        return
    end
    self:Changed()
end

-- Does OneForAll have a dot up for this guildie?
function GuildMap:Doubled(name, now)
    local at = self.theirs[name]
    if not at then return false end
    if now - at > GuildMap.OTHER_FORGET then
        self.theirs[name] = nil
        return false
    end
    return self:OtherOn()
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= GuildMap.OTHER_PREFIX or channel ~= "GUILD" or not sender then return end
    GuildMap:OnOther(Ambiguate(sender, "none"), text)
end)

-- Group members are on the map already.
local function inGroup(name)
    if not (IsInGroup and IsInGroup()) then return false end
    local first = name:match("^(%S+)")
    for _, n in ipairs({ name, first }) do
        if (UnitInParty and UnitInParty(n)) or (UnitInRaid and UnitInRaid(n)) then return true end
    end
    return false
end

-- Where a place falls on the map being looked at (0..1), or nil if it's off it.
function GuildMap:Place(place, shown)
    if place.map == shown then return place.x, place.y end
    if not (place.cont and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, place.cont, CreateVector2D(place.wx, place.wy), shown)
    local x, y = xy(ok and pos or nil)
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
    return nil
end

------------------------------------------------------------------------
-- The dots
------------------------------------------------------------------------
function GuildMap:Pin(i, canvas)
    local pin = self.pins[i]
    if pin then return pin end
    pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(GuildMap.SIZE, GuildMap.SIZE)
    pin.dot = pin:CreateTexture(nil, "ARTWORK")
    if pin.dot.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GuildMap.BLIP) then
        pin.dot:SetAllPoints()
        pin.dot:SetAtlas(GuildMap.BLIP)
    else
        pin.edge = pin:CreateTexture(nil, "BACKGROUND")
        pin.edge:SetAllPoints()
        pin.edge:SetTexture(GuildMap.DISC)
        pin.edge:SetVertexColor(0, 0, 0, 0.9)
        pin.dot:SetPoint("TOPLEFT", 1, -1)
        pin.dot:SetPoint("BOTTOMRIGHT", -1, 1)
        pin.dot:SetTexture(GuildMap.DISC)
    end
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(p) self:Tip(p) end)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.pins[i] = pin
    return pin
end

function GuildMap:Tip(pin)
    local name, place = pin.name, pin.place
    if not name or not place or not GameTooltip then return end
    local p = ns.db.guild.players[name] or {}
    local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Ambiguate(name, "short"), c and c.r or 1, c and c.g or 1, c and c.b or 1)
    if p.level then GameTooltip:AddLine("Level " .. p.level, 1, 1, 1) end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(place.map)
    if info and info.name then GameTooltip:AddLine(info.name, 0.8, 0.8, 0.85) end
    local age = GetTime() - place.at
    if age >= 60 then GameTooltip:AddLine(("%dm ago"):format(math.floor(age / 60)), 0.6, 0.6, 0.65) end
    GameTooltip:Show()
end

function GuildMap:Refresh()
    for _, pin in ipairs(self.pins) do pin:Hide() end
    local map = WorldMapFrame
    if not map or not map:IsShown() or not map.GetCanvas or not map.GetMapID or not self:On() then return 0 end
    local shown, canvas = map:GetMapID(), map:GetCanvas()
    if not shown or not canvas then return 0 end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    -- the canvas grows when the map is zoomed: the dots stay the same size on screen
    local scale
    local sc = map.ScrollContainer
    if type(sc) == "table" and sc.GetCanvasScale then
        scale = 1 / math.max(0.1, sc:GetCanvasScale() or 1)
    else
        scale = map:GetEffectiveScale() / canvas:GetEffectiveScale()
    end
    if not scale or scale <= 0 then scale = 1 end
    -- smaller on a continent (or the whole world), where a zone is a thumbnail
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(shown)
    local size = (info and info.mapType and info.mapType <= GuildMap.CONTINENT) and GuildMap.SIZE_FAR or GuildMap.SIZE
    local level = math.min(9000, canvas:GetFrameLevel() + 2500)
    local now, used = GetTime(), 0
    local names = {}
    for name in pairs(self.where) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local place = self.where[name]
        if self:Fresh(name, place, now) and not inGroup(name) and not self:Doubled(name, now) then
            local x, y = self:Place(place, shown)
            if x then
                used = used + 1
                local pin = self:Pin(used, canvas)
                pin.name, pin.place = name, place
                local p = ns.db.guild.players[name]
                local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
                pin.dot:SetVertexColor(c and c.r or 0.8, c and c.g or 0.8, c and c.b or 0.8)
                pin:SetSize(size, size)
                pin:SetScale(scale)
                pin:SetFrameLevel(level)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", x * w / scale, -y * h / scale)
                pin:Show()
            end
        end
    end
    return used
end

-- News while the map is open: redraw, but not for every message.
function GuildMap:Changed()
    if self.pending or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    self.pending = true
    C_Timer.After(1, function()
        self.pending = false
        self:Refresh()
    end)
end

ns.On("PLAYER_LOGIN", function()
    local map = WorldMapFrame
    if map then
        local function redraw() GuildMap:Refresh() end
        if map.HookScript then map:HookScript("OnShow", redraw) end
        if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", redraw) end
        if map.OnCanvasScaleChanged then hooksecurefunc(map, "OnCanvasScaleChanged", redraw) end
    end
    C_Timer.After(GuildMap.TICK, function() GuildMap:Tick() end)
end)
