-- Pog Guild Tools gear: what each character is wearing, shared with the guild.
--
-- The game only lets you inspect players standing next to you, so each
-- character shares its own gear instead: one `gear` record (item IDs for
-- inventory slots 1-19, race and sex), written when it logs in and a little
-- after its gear changes. Profiles show the account's current character (the
-- one that shared most recently) as a model; Inspect opens a bigger window
-- with the same character sheet as the wishlist.
--
-- The model: someone near you (target, group) is drawn live. Forever can't
-- draw anyone else with skin (no SetCustomRace; models by display ID come out
-- white), so then the profile shows their portrait and their gear icons.
local _, ns = ...
local UI = ns.UI
local Sync = ns.Sync

local Gear = {}
ns.Gear = Gear

Gear.SLOTS = 19    -- inventory slots 1-19 (shirt and tabard too: the model wears them)
Gear.DELAY = 30    -- seconds after a gear change before it's shared (swaps settle)

local function me() return Sync:Me() end
local function secret(v) return issecretvalue and issecretvalue(v) or false end

------------------------------------------------------------------------
-- Records
------------------------------------------------------------------------
-- 19 item IDs, 4 base64 characters each in slot order (0 = empty).
function Gear.Pack(ids)
    local out = {}
    for slot = 1, Gear.SLOTS do out[slot] = Sync.Enc(ids[slot] or 0, 4) end
    return table.concat(out)
end

function Gear.Unpack(s)
    local ids = {}
    if type(s) ~= "string" or #s ~= 4 * Gear.SLOTS then return ids end
    for slot = 1, Gear.SLOTS do
        local id = Sync.Dec(s, (slot - 1) * 4 + 1, 4)
        if id and id > 0 then ids[slot] = id end
    end
    return ids
end

-- `st`: the character sheet's numbers at the time, "hp,mana,str,agi,sta,int,
-- spi,armor" (max health and mana; 0 mana for rage and energy classes), shown
-- on a profile's Character card when we can't draw them (Jake). Older versions
-- ignore the field (records are read by their known fields).
Gear.STATS = { "hp", "mana", "str", "agi", "sta", "int", "spi", "armor" }
Sync:Register({
    name = "gear", code = "h", order = 5,
    fields = { "items", "race", "sex", "st" },
    numeric = { race = true, sex = true },
    valid = function(rec)
        if rec.by ~= rec.author or rec.id ~= rec.author then return false end
        if rec.deleted then return true end
        return type(rec.items) == "string" and #rec.items == 4 * Gear.SLOTS and rec.items:match("^[A-Za-z0-9+/]*$") ~= nil
            and type(rec.race) == "number" and rec.race >= 1 and rec.race <= 99 and rec.race % 1 == 0
            and (rec.sex == 2 or rec.sex == 3)
            and (rec.st == nil or (type(rec.st) == "string" and #rec.st <= 80 and rec.st:match("^[%d,]+$") ~= nil
                and select(2, rec.st:gsub(",", "")) == #Gear.STATS - 1))
    end,
    onChange = function(rec) Gear:Changed(rec) end,
})

function Gear:Record(name)
    local rec = name and (Sync:Store("gear") or {})[name]
    if rec and not rec.deleted then return rec end
end

-- What we're wearing now: { [slot] = itemID }.
function Gear:Worn()
    local ids = {}
    for slot = 1, Gear.SLOTS do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id and not secret(id) then ids[slot] = id end
    end
    return ids
end

-- Our character sheet's numbers, packed for `st` (nil if the client won't say).
function Gear.StatsNow()
    local function num(fn, ...)
        if not fn then return nil end
        local ok, v = pcall(fn, ...)
        if not ok or v == nil or secret(v) or type(v) ~= "number" then return nil end
        return math.max(0, math.floor(v + 0.5))
    end
    local function stat(i)
        if not UnitStat then return nil end
        local ok, _, effective = pcall(UnitStat, "player", i)
        if not ok or effective == nil or secret(effective) or type(effective) ~= "number" then return nil end
        return math.max(0, math.floor(effective + 0.5))
    end
    local armor
    if UnitArmor then
        local ok, _, effective = pcall(UnitArmor, "player")
        if ok and type(effective) == "number" and not secret(effective) then armor = math.floor(effective + 0.5) end
    end
    local v = { num(UnitHealthMax, "player"), num(UnitPowerMax, "player", 0), stat(1), stat(2), stat(3), stat(4), stat(5), armor }
    for i = 1, #Gear.STATS do if v[i] == nil then return nil end end
    return table.concat(v, ",")
end

-- A record's `st` as { hp = 1234, mana = ..., ... }, or nil.
function Gear.Stats(rec)
    if not rec or type(rec.st) ~= "string" then return nil end
    local out, i = {}, 0
    for n in rec.st:gmatch("%d+") do
        i = i + 1
        if Gear.STATS[i] then out[Gear.STATS[i]] = tonumber(n) end
    end
    return i == #Gear.STATS and out or nil
end

function Gear:Publish()
    if not ns.db or not Sync:GuildName() then return end
    local who = me()
    local _, _, race = UnitRace("player")
    local sex = UnitSex("player")
    if not race or secret(race) or not sex or secret(sex) then return end
    local items = Gear.Pack(self:Worn())
    local st = Gear.StatsNow()
    local cur = self:Record(who)
    if cur and cur.items == items and cur.race == race and cur.sex == sex and cur.st == st then return end
    Sync:Write("gear", { id = who, author = who, t = ns.Now(), items = items, race = race, sex = sex, st = st })
end

-- The character of an account to show: the one we're playing, or the one
-- that shared its gear most recently. Returns name, record (or nil).
function Gear:Current(chars)
    local best
    for _, c in ipairs(chars) do
        if c == me() then return c, self:Record(c) end
        local rec = self:Record(c)
        if rec and (not best or rec.rev > best.rev) then best = rec end
    end
    if best then return best.id, best end
    return chars[1], nil
end

-- A unit token for someone we can draw live (ourselves, target, group).
function Gear:UnitOf(name)
    if not name then return nil end
    if ns.SameName(name, me()) then return "player" end
    local units = { "target", "mouseover" }
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitIsPlayer(u) and (not UnitIsVisible or UnitIsVisible(u)) then
            local n = UnitName(u)
            if n and not secret(n) and ns.SameName(n, name) and (not UnitIsInMyGuild or UnitIsInMyGuild(u)) then return u end
        end
    end
end

------------------------------------------------------------------------
-- Words
------------------------------------------------------------------------
local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }

local function raceName(id)
    if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local ok, info = pcall(C_CreatureInfo.GetRaceInfo, id)
        if ok and type(info) == "table" and info.raceName then return info.raceName end
    end
    return RACES[id]
end

local function className(token)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if names and token and names[token] then return names[token] end
    return token and (token:sub(1, 1) .. token:sub(2):lower()) or nil
end

-- "Level 24 Gnome Mage" (whatever we know of it).
function Gear:Describe(name)
    local p = ns.db.guild.players[name] or {}
    local rec = self:Record(name)
    local race = rec and raceName(rec.race)
    local parts = {}
    if p.level then parts[#parts + 1] = "Level " .. p.level end
    if race then parts[#parts + 1] = race end
    if p.class then parts[#parts + 1] = className(p.class) end
    return table.concat(parts, " ")
end

function Gear:When(name)
    if self:UnitOf(name) == "player" then return "" end
    local rec = self:Record(name)
    if not rec then return "No gear shared yet" end
    local ago = ns.Home.Ago(rec.t)
    return ago == "now" and "Updated just now" or ("Updated %s ago"):format(ago)
end

------------------------------------------------------------------------
-- Models
------------------------------------------------------------------------
-- Dress a model as someone. Returns true if it shows them. Dressed again
-- only when what it would show changes.
function Gear:Dress(m, name)
    if not m then return false end
    local unit = self:UnitOf(name)
    local rec = self:Record(name)
    local sig = ("%s:%s:%s"):format(tostring(name), unit or "", rec and rec.rev or 0)
    if m.dressed == sig then return m.shows end
    m:Show() -- a hidden model doesn't take a unit
    m.dressed = sig
    m.shows = false
    if unit and pcall(m.SetUnit, m, unit) then
        m.shows = true
    else
        pcall(m.ClearModel, m)
    end
    if m.shows then pcall(m.SetCamDistanceScale, m, m.zoom or ns.Wishlist.MODEL_ZOOM) end
    if not m.shows then
        m:Hide()
        m.dressed = sig -- (hiding forgets it)
    end
    return m.shows
end

------------------------------------------------------------------------
-- Inspect window
------------------------------------------------------------------------
local PAD, BAND_H = 12, 36

function Gear.Link(id)
    if C_Item and C_Item.GetItemInfo then
        local ok, _, link = pcall(C_Item.GetItemInfo, id)
        if ok and type(link) == "string" then return link end
    end
    local name, quality
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, id)
        if ok then name = n end
    end
    if C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, id)
        if ok then quality = q end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return ns.Wishlist.MakeLink(id, name or "Loading...", quality)
end

function Gear:BuildWindow()
    local D = ns.Wishlist
    local L = D.layout
    local f = CreateFrame("Frame", "PogRaidInspect", UIParent)
    f:SetSize(L.RW + 2 * PAD, BAND_H + PAD + L.LIST_H + PAD)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    UI.Panel(f)
    -- the game's metal window, like its own Inspect: their name in the strip,
    -- their class in the portrait ring (else the dialog border)
    f.metal = UI.PortraitFrame(f, "", ns.MEDIA .. "logo", function() f:Hide() end)
    if not f.metal then UI.Window(f) end
    f:Hide()
    -- the profile card's model hides while this is open (it would draw through)
    f:SetScript("OnShow", function() if ns.Profiles and ns.Profiles.charCard then ns.Profiles:RefreshCharacter() end end)
    f:SetScript("OnHide", function()
        UI.HideMenu()
        if ns.Profiles and ns.Profiles.charCard then ns.Profiles:RefreshCharacter() end
    end)
    tinsert(UISpecialFrames, "PogRaidInspect")

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAND_H)
    UI.MakeMovable(f, bar, function() UI.SavePosition(f, "inspect") end)
    local band = bar:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("BOTTOMRIGHT", -1, 0)
    local divider = bar:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", 1, 0)
    divider:SetPoint("BOTTOMRIGHT", -1, 0)
    divider:SetHeight(1)
    f.info = UI.Text(bar, 11)
    f.info:SetTextColor(0.6, 0.6, 0.65)
    f.when = UI.Text(bar, 11)
    f.when:SetTextColor(0.55, 0.55, 0.6)
    if f.metal then
        f.title = f.metal.title
        f.close = f.metal.close
        UI.Band(band, divider)
        f.info:SetPoint("LEFT", UI.PORTRAIT_CLEAR, 0)
        f.when:SetPoint("RIGHT", -PAD, 0)
        UI.MakeMovable(f, f.metal.strip, function() UI.SavePosition(f, "inspect") end)
    else
        f.title = UI.Text(bar, 14)
        f.title:SetPoint("LEFT", PAD, 0)
        UI.Band(band, divider, f.title)
        f.info:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
        f.close = UI.CloseButton(bar, 28, BAND_H, function() f:Hide() end)
        f.close:SetPoint("RIGHT", -PAD + 7, 0)
        f.when:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
    end

    f.sheet = D.Sheet(f, function(b, button) self:SlotClick(b, button) end, true)
    f.sheet:SetPoint("TOPLEFT", PAD, -(BAND_H + PAD))
    -- the backdrop fills the whole window under the title band
    f.artArea = CreateFrame("Frame", nil, f)
    f.artArea:SetPoint("TOPLEFT", 1, -BAND_H)
    f.artArea:SetSize(f:GetWidth() - 2, f:GetHeight() - BAND_H - 1)
    f.backdrop = f.sheet.model and D.Backdrop(f, f.sheet.model, f.artArea)
    UI.RestorePosition(f, "inspect", 0)
    self.window = f
    return f
end

-- A window's portrait: the class's round icon (the game's own circles), else our logo.
Gear.CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
function Gear.SetClassPortrait(tex, class)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture(Gear.CLASS_CIRCLES)
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        tex:SetTexture(ns.MEDIA .. "logo")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

function Gear:Inspect(name)
    if not name then return end
    local f = self.window or self:BuildWindow()
    f.name = name
    if f.sheet.model then f.sheet.model.dressed = nil end
    f:Show()
    self:RefreshWindow()
end

function Gear:RefreshWindow()
    local f = self.window
    if not f or not f:IsShown() then return end
    local name = f.name
    local p = ns.db.guild.players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    f.title:SetText(Ambiguate(name, "short"))
    if f.metal then Gear.SetClassPortrait(f.metal.portrait.icon, p and p.class) end
    if c then f.title:SetTextColor(c.r, c.g, c.b) else f.title:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) end
    f.info:SetText(self:Describe(name))
    f.when:SetText(self:When(name))
    if f.backdrop then f.backdrop:SetClass(p and p.class) end
    local ids
    if self:UnitOf(name) == "player" then
        ids = self:Worn()
    else
        local rec = self:Record(name)
        ids = rec and Gear.Unpack(rec.items) or {}
    end
    local want = {}
    for _, id in pairs(ids) do want[id] = true end
    local sources = ns.Journal:Sources(want)
    for _, b in ipairs(f.sheet.slots) do
        local id = ids[b.slot.id]
        if id then
            local src = sources[id]
            ns.Wishlist.FillSlot(b, { id = id, link = Gear.Link(id) }, src and (src.from .. ", " .. src.dungeon) or "")
        else
            ns.Wishlist.FillSlot(b, nil)
        end
    end
    self:Dress(f.sheet.model, name)
end

-- An item in the window: shift-click links it, a click offers the wishlist.
function Gear:SlotClick(b, button)
    local it = b.item
    if not it then return end
    if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(it.link)
        return
    end
    local D = ns.Wishlist
    local have = D:Find(it.id) ~= nil
    UI.ShowMenu(b, {
        { text = ns.Loot.ItemName(it.link) or "Item", header = true },
        { text = have and "On your wishlist" or "Add to my wishlist", disabled = have,
            func = function() D:AddLink(it.link) end },
    })
end

function Gear:Changed(rec)
    local f = self.window
    if f and f:IsShown() then self:RefreshWindow() end -- (a page of records reports only its last)
    if ns.Profiles then ns.Profiles:Changed() end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local pendingAt
local function publishSoon()
    local at = GetTime()
    pendingAt = at
    C_Timer.After(Gear.DELAY, function()
        if pendingAt == at then
            pendingAt = nil
            Gear:Publish()
        end
    end)
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(20, function() Gear:Publish() end)
    C_Timer.After(90, function() Gear:Publish() end) -- in case the guild roster was slow
end)
-- a new level changes the numbers too (buffs don't trigger a share)
ns.On("PLAYER_LEVEL_UP", function() publishSoon() end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    publishSoon()
    local f = Gear.window
    if f and f:IsShown() and f.name and Gear:UnitOf(f.name) == "player" then
        if f.sheet.model then f.sheet.model.dressed = nil end
        Gear:RefreshWindow()
    end
    local P = ns.Profiles
    if P and P.charCard and P.charCard:IsVisible() and P.charFor and Gear:UnitOf(P.charFor) == "player" then
        P:RefreshCharacter()
    end
end)
-- items load in bursts: refresh once they settle, and only while the window is open
local loadPending
ns.On("ITEM_DATA_LOAD_RESULT", function()
    if loadPending or not (Gear.window and Gear.window:IsShown()) then return end
    loadPending = true
    C_Timer.After(0.3, function()
        loadPending = nil
        Gear:RefreshWindow()
    end)
end)
