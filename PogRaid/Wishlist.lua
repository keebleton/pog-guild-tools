-- Pog Guild Tools wishlist tab.
--
-- A character sheet of the gear you're after, one item per slot (like Sixty
-- Upgrades), with your character in the middle wearing it. Shift-click items
-- in (from bags, chat or another addon's loot window), or pick a slot on the
-- left (or an empty slot on the sheet) to see every item for it, best item
-- level first, and where it drops. Drop sources come from the DungeonJournal
-- addon when it is installed (ns.Journal, below: ForeverDungeonJournal_NS.DB,
-- dungeons, bosses and their loot, quest rewards). Items you get (in your
-- bags or equipped) check themselves off. Your list is per character; what
-- you still want is shared with the guild as one `wish` record of item IDs.
--
-- Layout (902 x PAGE_H window):
--   [Shift-click an item ]  [My wishlist               5 of 17 slots, 2 got]
--   [My wishlist       5 ]  [[] Head                            Hands   []]
--   [Head             34 ]  [[] Neck          (model)           Waist   []]
--   [...slots            ]  [ ...                                 ...       ]
local _, ns = ...
local UI = ns.UI
local Sync = ns.Sync

local Wishlist = {}
ns.Wishlist = Wishlist
local Journal = {}
ns.Journal = Journal

Wishlist.SETS = 3 -- wishlists per character (at most)
Wishlist.MAX = 60 -- shared IDs accepted per player (3 lists of 17 slots, some slack)
Wishlist.MAX_NAME = 20
local NO_ICON = 134400
local QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee",
    [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff" }

local function me() return Sync:Me() end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end

------------------------------------------------------------------------
-- Slots
------------------------------------------------------------------------
-- Inventory slot IDs, the character sheet's two columns (side 1 left).
Wishlist.SLOTS = {
    { id = 1, name = "Head", inv = "HeadSlot", side = 1 },
    { id = 2, name = "Neck", inv = "NeckSlot", side = 1 },
    { id = 3, name = "Shoulder", inv = "ShoulderSlot", side = 1 },
    { id = 15, name = "Back", inv = "BackSlot", side = 1 },
    { id = 5, name = "Chest", inv = "ChestSlot", side = 1 },
    { id = 9, name = "Wrist", inv = "WristSlot", side = 1 },
    { id = 16, name = "Main Hand", inv = "MainHandSlot", side = 1 },
    { id = 17, name = "Off Hand", inv = "SecondaryHandSlot", side = 1 },
    { id = 18, name = "Ranged", inv = "RangedSlot", side = 1 },
    { id = 10, name = "Hands", inv = "HandsSlot", side = 2 },
    { id = 6, name = "Waist", inv = "WaistSlot", side = 2 },
    { id = 7, name = "Legs", inv = "LegsSlot", side = 2 },
    { id = 8, name = "Feet", inv = "FeetSlot", side = 2 },
    { id = 11, name = "Finger", inv = "Finger0Slot", side = 2 },
    { id = 12, name = "Finger", inv = "Finger1Slot", side = 2 },
    { id = 13, name = "Trinket", inv = "Trinket0Slot", side = 2 },
    { id = 14, name = "Trinket", inv = "Trinket1Slot", side = 2 },
}

-- Where each kind of gear goes (first empty slot of the list).
local EQUIP = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
-- The journal's slot text ("Wrist, Cloth"), when the client can't say.
local BY_TEXT = {
    Head = "INVTYPE_HEAD", Neck = "INVTYPE_NECK", Shoulder = "INVTYPE_SHOULDER", Back = "INVTYPE_CLOAK",
    Chest = "INVTYPE_CHEST", Wrist = "INVTYPE_WRIST", Hands = "INVTYPE_HAND", Waist = "INVTYPE_WAIST",
    Legs = "INVTYPE_LEGS", Feet = "INVTYPE_FEET", Finger = "INVTYPE_FINGER", Trinket = "INVTYPE_TRINKET",
    ["One-Hand"] = "INVTYPE_WEAPON", Weapon = "INVTYPE_WEAPON", ["Two-Hand"] = "INVTYPE_2HWEAPON",
    ["Main Hand"] = "INVTYPE_WEAPONMAINHAND", ["Off Hand"] = "INVTYPE_WEAPONOFFHAND", Shield = "INVTYPE_SHIELD",
    ["Held In Off-hand"] = "INVTYPE_HOLDABLE", Ranged = "INVTYPE_RANGED", Thrown = "INVTYPE_THROWN",
}

------------------------------------------------------------------------
-- The journal (DungeonJournal's data, if it's installed)
------------------------------------------------------------------------
function Journal:DB()
    local fdj = _G.ForeverDungeonJournal_NS
    return type(fdj) == "table" and type(fdj.DB) == "table" and fdj.DB or nil
end

-- Wishlist by level: { { name, level, data } }.
function Journal:List()
    local db, out = self:DB(), {}
    for name, d in pairs(db or {}) do
        if type(d) == "table" then
            out[#out + 1] = { name = name, level = tostring(d.level or ""), min = tonumber(tostring(d.level or ""):match("(%d+)")) or 99, data = d }
        end
    end
    table.sort(out, function(a, b)
        if a.min ~= b.min then return a.min < b.min end
        return a.name < b.name
    end)
    return out
end

-- Everything a dungeon gives: fn(itemID, name, slot, quality, from), where
-- from is a boss, "Trash" or "Quest: <name>".
local function eachItem(d, fn)
    for _, b in ipairs(d.bosses or {}) do
        for _, it in ipairs(b.loot or {}) do
            if type(it) == "table" and tonumber(it[1]) then fn(it[1], it[2], it[3], it[4], b.trash and "Trash" or b.name) end
        end
    end
    for _, q in ipairs(d.quests or {}) do
        for _, key in ipairs({ "rewardItems", "additionalRewardItems", "noteRewardItems" }) do
            for _, it in ipairs(type(q[key]) == "table" and q[key] or {}) do
                if type(it) == "table" and tonumber(it[1]) then fn(it[1], it[2], nil, it[3], "Quest: " .. tostring(q.name or "?")) end
            end
        end
    end
end
Journal.EachItem = eachItem

-- Where the given items come from, and how many of them each dungeon has:
-- sources[id] = { dungeon, from, slot }, counts[dungeon] = n. One pass.
function Journal:Sources(ids)
    local sources, counts = {}, {}
    for _, dg in ipairs(self:List()) do
        eachItem(dg.data, function(id, _, slot, _, from)
            if ids[id] then
                if not sources[id] then sources[id] = { dungeon = dg.name, from = from, slot = slot } end
                counts[dg.name] = (counts[dg.name] or 0) + 1
            end
        end)
    end
    return sources, counts
end

-- The kind of gear an item is (INVTYPE_...), or nil if it isn't gear.
function Wishlist.EquipLoc(id, slotText)
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, id)
        if ok and EQUIP[loc] then return loc end
    end
    if not slotText then
        local src = Journal:Sources({ [id] = true })[id]
        slotText = src and src.slot
    end
    return slotText and BY_TEXT[slotText:match("^[^,]+")] or nil
end

------------------------------------------------------------------------
-- Our list (per character) and what we share
------------------------------------------------------------------------
-- { { id, link, t, slot, got } }, one item per slot.
-- Per character: { sets = { { name, items }, ... up to SETS }, cur }. Lists are
-- made with New; there's always one. A list from before there were sets
-- becomes the first.
function Wishlist:Data()
    ns.db.wishlist = ns.db.wishlist or {}
    local key = (UnitGUID and UnitGUID("player")) or ns.PlayerName()
    local data = ns.db.wishlist[key]
    if not data or not data.sets then
        data = { sets = { { items = data or {} } }, cur = 1 }
        ns.db.wishlist[key] = data
    end
    if #data.sets == 0 then data.sets[1] = { items = {} } end
    if not data.sets[data.cur or 1] then data.cur = 1 end
    return data
end

function Wishlist:SetName(i)
    local s = self:Data().sets[i]
    return s and s.name or ("Wishlist " .. i)
end

function Wishlist:Rename(i, name)
    local s = self:Data().sets[i]
    if not s then return end
    name = ns.Codec.CleanText(name or "", Wishlist.MAX_NAME)
    s.name = name ~= "" and name or nil
    self:Changed()
end

function Wishlist:UseSet(i)
    local data = self:Data()
    if not data.sets[i] then return end
    data.cur = i
    self:ShowSheet()
end

-- A new, empty wishlist (up to SETS), shown straight away.
function Wishlist:NewSet()
    local data = self:Data()
    if #data.sets >= Wishlist.SETS then return end
    data.sets[#data.sets + 1] = { items = {} }
    data.cur = #data.sets
    self:ShowSheet()
    return data.cur
end

-- Never the last one.
function Wishlist:DeleteSet(i)
    local data = self:Data()
    if #data.sets <= 1 or not data.sets[i] then return end
    table.remove(data.sets, i)
    if data.cur > i or data.cur > #data.sets then data.cur = data.cur - 1 end
    self:Publish()
    self:ShowSheet()
end

-- Back to the sheet (out of a slot list or a search).
function Wishlist:ShowSheet()
    self.list, self.offset = nil, 0
    if self.addBox and self.addBox:GetText() ~= "" then self.addBox:SetText("") end
    self:Changed()
end

function Wishlist:SetsMenu(anchor)
    local data = self:Data()
    local entries = { { text = "Wishlists", header = true } }
    for i in ipairs(data.sets) do
        local mark = i == data.cur and "> " or "   "
        entries[#entries + 1] = { text = mark .. self:SetName(i), func = function() self:UseSet(i) end }
    end
    if #data.sets < Wishlist.SETS then
        entries[#entries + 1] = { text = "New wishlist", color = { UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3] },
            func = function() self:NewSet() end }
    end
    local cur = data.cur
    entries[#entries + 1] = { text = "Rename this one...", func = function()
        UI.Compose({ heading = "Rename this wishlist", label1 = "Name", max1 = Wishlist.MAX_NAME,
            text1 = data.sets[cur] and data.sets[cur].name or "", text2 = "", button = "Save", optional = true, noArea = true },
            function(name) self:Rename(cur, name) end)
    end }
    if #data.sets > 1 then
        entries[#entries + 1] = { text = "Delete this one", color = { 0.95, 0.4, 0.4 }, func = function()
            UI.ShowMenu(anchor, {
                { text = "Delete " .. self:SetName(cur) .. "?", header = true },
                { text = "Sure? Delete it", color = { 0.95, 0.4, 0.4 }, func = function() self:DeleteSet(cur) end },
                { text = "Keep it" },
            })
        end }
    end
    UI.ShowMenu(anchor, entries)
end

-- The list on screen: { { id, link, t, slot, got } }, one item per slot.
function Wishlist:Mine()
    local list = self:Data().sets[self:Data().cur].items
    -- items from before the sheet (no slot): into a free slot, or off the list
    for i = #list, 1, -1 do
        local it = list[i]
        if not it.slot then
            local loc, taken = Wishlist.EquipLoc(it.id), {}
            for _, other in ipairs(list) do if other.slot then taken[other.slot] = true end end
            for _, s in ipairs(loc and EQUIP[loc] or {}) do
                if not taken[s] then it.slot = s break end
            end
            if not it.slot then table.remove(list, i) end
        end
    end
    return list
end

function Wishlist:Find(id)
    for i, it in ipairs(self:Mine()) do
        if it.id == id then return it, i end
    end
end

function Wishlist:BySlot()
    local by = {}
    for _, it in ipairs(self:Mine()) do
        if it.slot then by[it.slot] = it end
    end
    return by
end

-- A link for an item we only know by ID and name (from the journal).
function Wishlist.MakeLink(id, name, quality)
    return ("|cff%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(QUALITY_HEX[quality or 1] or "ffffff", id, name or ("item " .. id))
end

local function owned(id)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, id, true)
        if ok and tonumber(n) and n > 0 then return true end
    end
    if GetInventoryItemID then
        for slot = 1, 19 do
            local ok, worn = pcall(GetInventoryItemID, "player", slot)
            if ok and worn == id then return true end
        end
    end
    return false
end

-- Add an item from its link, into its slot (a ring or trinket takes the free
-- one of the pair). An item already in that slot is replaced. Returns the
-- entry, or nil (with a note why).
function Wishlist:AddLink(link, slotText)
    local id = ns.Loot.ItemID(link)
    if not id then return nil end
    link = link:match("(|c%x+|Hitem:.-|h.-|h|r)") or link:match("(|Hitem:.-|h.-|h)") or link
    if self:Find(id) then
        if not (self.lastAdd == id and GetTime() - (self.lastAddAt or 0) < 1) then
            ns.Print(("%s is already on your wishlist"):format(link))
        end
        return nil
    end
    local loc = Wishlist.EquipLoc(id, slotText)
    if not loc then
        ns.Print(("%s isn't gear: only gear goes on your wishlist"):format(link))
        return nil
    end
    local by, slot = self:BySlot(), nil
    for _, s in ipairs(EQUIP[loc]) do
        if not by[s] then slot = s break end
    end
    slot = slot or EQUIP[loc][1]
    local old = by[slot]
    if old then
        local _, i = self:Find(old.id)
        table.remove(self:Mine(), i)
        ns.Print(("%s replaces %s on your wishlist"):format(link, old.link))
    end
    local it = { id = id, link = link, t = ns.Now(), slot = slot }
    if owned(id) then it.got = ns.Now() end
    table.insert(self:Mine(), it)
    self.lastAdd, self.lastAddAt = id, GetTime()
    self:Publish()
    self:Changed()
    return it
end

function Wishlist:Remove(id)
    local _, i = self:Find(id)
    if not i then return end
    table.remove(self:Mine(), i)
    self:Publish()
    self:Changed()
end

function Wishlist:SetGot(id, got)
    local it = self:Find(id)
    if not it then return end
    it.got = got and ns.Now() or nil
    self:Publish()
    self:Changed()
end

-- Got something we wanted? Check it off, on every list it's on.
function Wishlist:CheckOwned()
    local changed, said = false, {}
    for _, set in ipairs(self:Data().sets) do
        for _, it in ipairs(set.items) do
            if not it.got and owned(it.id) then
                it.got = ns.Now()
                changed = true
                if not said[it.id] then ns.Print(("wishlist: got %s!"):format(it.link)) end
                said[it.id] = true
            end
        end
    end
    if changed then
        self:Publish()
        self:Changed()
    end
end

-- What we still want, on any of our lists, as the guild sees it.
function Wishlist:Wanted()
    local ids, seen = {}, {}
    for _, set in ipairs(self:Data().sets) do
        for _, it in ipairs(set.items) do
            if not it.got and not seen[it.id] then
                seen[it.id] = true
                ids[#ids + 1] = it.id
            end
        end
    end
    return ids
end

function Wishlist:Publish()
    if not Sync:GuildName() then return end
    local who = me()
    local packed = ns.Crafting.Pack(self:Wanted())
    local cur = (Sync:Store("wish") or {})[who]
    if packed == "" then packed = nil end
    if cur and not cur.deleted and cur.ids == packed then return end
    if not cur and not packed then return end
    Sync:Write("wish", { id = who, author = who, t = cur and cur.t or ns.Now(), ids = packed })
end

-- Someone's shared wishlist: a list of item IDs.
function Wishlist:WantedBy(name)
    local rec = (Sync:Store("wish") or {})[name]
    if not rec or rec.deleted then return {} end
    return ns.Crafting.Unpack(rec.ids)
end

Sync:Register({
    name = "wish", code = "i", order = 5,
    fields = { "ids" },
    valid = function(rec)
        if rec.by ~= rec.author or rec.id ~= rec.author then return false end
        if rec.ids == nil then return true end
        return type(rec.ids) == "string" and #rec.ids % 4 == 0 and #rec.ids <= 4 * Wishlist.MAX
            and rec.ids:match("^[A-Za-z0-9+/]*$") ~= nil
    end,
    onChange = function() Wishlist:Changed() end,
})

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local PAD, GAP, TITLE_H, BAR_H = 12, 8, 30, 26
local FRAME_W, FRAME_H = 902, ns.PAGE_H
local LEFT_W = 262
local RX = PAD + LEFT_W + PAD
local RW = FRAME_W - RX - PAD
local LIST_Y = TITLE_H + BAR_H + GAP
local LIST_H = FRAME_H - PAD - LIST_Y
local SIDE_ROW = 24
local ROW_H = 34
-- the character sheet: two columns of slots, the model between them
local SLOT, PITCH, EDGE, TEXT_W = 36, 58, 16, 140
local SLOT_TOP = math.floor((LIST_H - (8 * PITCH + SLOT)) / 2)
local TEXT_X = EDGE + SLOT + 10
local MODEL_X = EDGE + SLOT + 8
local MODEL_W = RW - 2 * MODEL_X
local MODEL_ZOOM = 1.15 -- camera a little further back than the game's default

Wishlist.layout = { RX = RX, RW = RW, LIST_Y = LIST_Y, LIST_H = LIST_H, SLOT = SLOT, PITCH = PITCH, EDGE = EDGE,
    SLOT_TOP = SLOT_TOP, MODEL_X = MODEL_X, MODEL_W = MODEL_W }

local function iconOf(id)
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        if ok and icon then return icon end
        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    return NO_ICON
end

local function emptyIcon(slot)
    if GetInventorySlotInfo then
        local ok, _, tex = pcall(GetInventorySlotInfo, slot.inv)
        if ok and tex then return tex end
    end
    return "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
end

-- The item's quality colour: from the link (a hex colour, or a quality code
-- in newer links), else what the client knows of the item.
local function hexOf(link)
    if not link then return nil end
    local hex = link:match("^|c%x%x(%x%x%x%x%x%x)")
    if hex then return hex end
    local q = ns.Loot.Quality(link)
    return q and QUALITY_HEX[q]
end

local function colored(link)
    local name = ns.Loot.ItemName(link) or link
    local hex = hexOf(link)
    return hex and ("|cff%s%s|r"):format(hex, name) or name
end

local function rgb(link)
    local hex = hexOf(link)
    if not hex then return 0.5, 0.5, 0.5 end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- One slot of the character sheet: icon (with a quality border), the item's
-- name and where it drops, mirrored on the right-hand side.
local function slotButton(parent, slot, i, onClick)
    local left = slot.side == 1
    local b = CreateFrame("Button", nil, parent)
    b.slot = slot
    b:SetSize(SLOT + 10 + TEXT_W, SLOT)
    local y = -(SLOT_TOP + (i - 1) * PITCH)
    if left then b:SetPoint("TOPLEFT", EDGE, y) else b:SetPoint("TOPRIGHT", -EDGE, y) end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetSize(SLOT + 2, SLOT + 2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(SLOT, SLOT)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if left then
        b.icon:SetPoint("TOPLEFT", 0, 0)
        b.border:SetPoint("TOPLEFT", -1, 1)
    else
        b.icon:SetPoint("TOPRIGHT", 0, 0)
        b.border:SetPoint("TOPRIGHT", 1, 1)
    end
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(14, 14)
    b.check:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 3, -3)
    b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.name = UI.Text(b, 12)
    b.name:SetWidth(TEXT_W)
    b.name:SetWordWrap(true)
    b.name:SetMaxLines(2)
    b.sub = UI.Text(b, 10)
    b.sub:SetWidth(TEXT_W)
    b.sub:SetWordWrap(false)
    if left then
        b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -1)
        b.name:SetJustifyH("LEFT")
        b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
        b.sub:SetJustifyH("LEFT")
    else
        b.name:SetPoint("TOPRIGHT", b.icon, "TOPLEFT", -10, -1)
        b.name:SetJustifyH("RIGHT")
        b.sub:SetPoint("TOPRIGHT", b.name, "BOTTOMRIGHT", 0, -3)
        b.sub:SetJustifyH("RIGHT")
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.12)
    b:SetScript("OnClick", function(btn, button) if onClick then onClick(btn, button) end end)
    b:SetScript("OnEnter", function(btn)
        if not GameTooltip then return end
        if btn.item then
            UI.ItemTip(btn, btn.item.link, left and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
        else
            GameTooltip:SetOwner(btn, left and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
            GameTooltip:AddLine(slot.name, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", hideTip)
    return b
end

-- A character model, turned by dragging. Not every client has the model
-- type; the sheet works without it. `m.dressed` is forgotten when it hides
-- (a hidden model loses what it wore).
function Wishlist.Model(parent, x, y, w, h)
    local ok, m = pcall(CreateFrame, "DressUpModel", nil, parent)
    if not ok or not m then return nil end
    m:SetPoint("TOPLEFT", x, -y)
    m:SetSize(w, h)
    m:SetFrameLevel(parent:GetFrameLevel() + 1)
    m:EnableMouse(true)
    m:SetScript("OnMouseDown", function(f)
        f.turning = GetCursorPosition()
    end)
    m:SetScript("OnMouseUp", function(f) f.turning = nil end)
    m:SetScript("OnHide", function(f)
        f.turning = nil
        f.dressed = nil
    end)
    m:SetScript("OnUpdate", function(f)
        if not f.turning then return end
        local x = GetCursorPosition()
        f.facing = (f.facing or 0) + (x - f.turning) * 0.02
        f.turning = x
        f:SetFacing(f.facing)
    end)
    return m
end

-- Behind a model: the game's dressing room art for the class when the client
-- has it (cropped to fit, dimmed), else a soft glow in the class colour; a
-- shadow at the feet either way. bd:SetClass(classFile).
Wishlist.BACKDROP_ALPHA = 0.7 -- the dressing room art, strong (Jake: was 0.55)
function Wishlist.Backdrop(parent, m, area)
    local bd = {}
    local w, h = (area or m):GetWidth(), (area or m):GetHeight()
    local mh = m:GetHeight()
    bd.art = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    bd.art:SetAllPoints(area or m)
    bd.art:SetAlpha(Wishlist.BACKDROP_ALPHA)
    bd.art:Hide()
    bd.glow = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
    bd.glow:SetTexture(ns.MEDIA .. "glow")
    bd.glow:SetSize(math.min(m:GetWidth(), mh * 0.9), mh * 0.9)
    bd.glow:SetPoint("CENTER", m, "CENTER", 0, 0)
    bd.shadow = parent:CreateTexture(nil, "BORDER")
    bd.shadow:SetTexture(ns.MEDIA .. "glow")
    bd.shadow:SetVertexColor(0, 0, 0, 0.7)
    bd.shadow:SetSize(math.floor(mh * 0.42), math.floor(mh * 0.08))
    bd.shadow:SetPoint("CENTER", m, "BOTTOM", 0, math.floor(mh * 0.07))
    function bd:SetShown(on)
        self.hidden = not on
        if on then
            self:SetClass(self.class)
        else
            self.art:Hide()
            self.glow:Hide()
            self.shadow:Hide()
        end
    end
    function bd:SetClass(class)
        self.class = class
        if self.hidden then return end
        self.shadow:Show()
        local atlas = class and C_Texture and C_Texture.GetAtlasInfo and ("dressingroom-background-" .. class:lower())
        local ok, info = false, nil
        if atlas then ok, info = pcall(C_Texture.GetAtlasInfo, atlas) end
        if ok and type(info) == "table" and info.file and (info.width or 0) > 0 and (info.height or 0) > 0 then
            -- crop the art to the model's shape, keeping its middle
            local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
            local want, have = w / h, info.width / info.height
            if want > have then
                local cut = (b - t) * (1 - have / want) / 2
                t, b = t + cut, b - cut
            else
                local cut = (r - l) * (1 - want / have) / 2
                l, r = l + cut, r - cut
            end
            self.art:SetTexture(info.file)
            self.art:SetTexCoord(l, r, t, b)
            self.art:Show()
            self.glow:Hide()
        else
            local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            self.art:Hide()
            self.glow:SetVertexColor(c and c.r or 0.6, c and c.g or 0.6, c and c.b or 0.65, 0.22)
            self.glow:Show()
        end
    end
    return bd
end

-- The character sheet (RW x LIST_H): the slots in two columns, a model
-- behind them. onClick(slotButton, mouseButton). `bare`: no backdrop (the
-- caller draws its own).
function Wishlist.Sheet(parent, onClick, bare)
    local doll = CreateFrame("Frame", nil, parent)
    doll:SetSize(RW, LIST_H)
    doll.slots = {}
    local n = { 0, 0 }
    for _, slot in ipairs(Wishlist.SLOTS) do
        n[slot.side] = n[slot.side] + 1
        doll.slots[#doll.slots + 1] = slotButton(doll, slot, n[slot.side], onClick)
    end
    doll.model = Wishlist.Model(doll, MODEL_X, 12, MODEL_W, LIST_H - 24)
    doll.backdrop = doll.model and not bare and Wishlist.Backdrop(doll, doll.model) or nil
    for _, b in ipairs(doll.slots) do b:SetFrameLevel(doll:GetFrameLevel() + 3) end
    return doll
end
Wishlist.MODEL_ZOOM = MODEL_ZOOM

-- Show an item in a slot (it = { id, link }, or nil for an empty slot), with
-- a line under it.
function Wishlist.FillSlot(b, it, sub, subColor, got)
    b.item = it
    if it then
        b.icon:SetTexture(iconOf(it.id))
        b.icon:SetAlpha(1)
        local r, g, bl = rgb(it.link)
        b.border:SetColorTexture(r, g, bl, 0.9)
        b.name:SetText(colored(it.link))
        b.sub:SetText(sub or "")
        local c = subColor or { 0.6, 0.6, 0.65 }
        b.sub:SetTextColor(c[1], c[2], c[3])
        b.check:SetShown(got == true)
    else
        b.icon:SetTexture(emptyIcon(b.slot))
        b.icon:SetAlpha(0.6)
        b.border:SetColorTexture(0.2, 0.2, 0.23, 1)
        b.name:SetText(b.slot.name)
        b.name:SetTextColor(0.42, 0.42, 0.46)
        b.sub:SetText("")
        b.check:Hide()
    end
end

-- The side panel: a list per kind of slot (both rings share one, both
-- trinkets too), each item from the journal that fits it.
Wishlist.LISTS = {
    { name = "Head", slot = 1, locs = { INVTYPE_HEAD = true } },
    { name = "Neck", slot = 2, locs = { INVTYPE_NECK = true } },
    { name = "Shoulder", slot = 3, locs = { INVTYPE_SHOULDER = true } },
    { name = "Back", slot = 15, locs = { INVTYPE_CLOAK = true } },
    { name = "Chest", slot = 5, locs = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { name = "Wrist", slot = 9, locs = { INVTYPE_WRIST = true } },
    { name = "Hands", slot = 10, locs = { INVTYPE_HAND = true } },
    { name = "Waist", slot = 6, locs = { INVTYPE_WAIST = true } },
    { name = "Legs", slot = 7, locs = { INVTYPE_LEGS = true } },
    { name = "Feet", slot = 8, locs = { INVTYPE_FEET = true } },
    { name = "Finger", slot = 11, also = 12, locs = { INVTYPE_FINGER = true } },
    { name = "Trinket", slot = 13, also = 14, locs = { INVTYPE_TRINKET = true } },
    { name = "Main Hand", slot = 16, locs = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true } },
    { name = "Off Hand", slot = 17, locs = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true } },
    { name = "Ranged", slot = 18, locs = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
        INVTYPE_RELIC = true } },
}

function Wishlist.ListFor(slotID)
    for _, l in ipairs(Wishlist.LISTS) do
        if l.slot == slotID or l.also == slotID then return l end
    end
end

local function slotOf(id)
    for _, s in ipairs(Wishlist.SLOTS) do
        if s.id == id then return s end
    end
end

-- Item level, a proper link and the kind of item ("Mail", "Dagger"), if the
-- client has the item loaded (it's asked for when not).
local function itemInfo(id)
    local ilvl, link, kind
    if C_Item and C_Item.GetItemInfo then
        local ok, name, l, _, level = pcall(C_Item.GetItemInfo, id)
        if ok and name then
            ilvl, link = tonumber(level), l
        elseif C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, sub = pcall(C_Item.GetItemInfoInstant, id)
        if ok and type(sub) == "string" then kind = sub end
    end
    return ilvl, link, kind
end

-- Every journal item for a list, best item level first (unknown last):
-- { id, link, ilvl, kind, slot, from, dungeon }. `list` is a slot list, or
-- { search = "words" } for gear whose name has them.
function Wishlist:Items(list)
    local seen, out = {}, {}
    for _, dg in ipairs(Journal:List()) do
        Journal.EachItem(dg.data, function(id, name, slot, quality, from)
            if seen[id] then return end
            local loc = Wishlist.EquipLoc(id, slot or "")
            local fits = loc and (list.locs and list.locs[loc]
                or list.search and tostring(name):lower():find(list.search, 1, true))
            if fits then
                seen[id] = true
                local ilvl, link, kind = itemInfo(id)
                out[#out + 1] = { id = id, link = link or Wishlist.MakeLink(id, name, quality), ilvl = ilvl,
                    kind = kind or (slot and slot:match(",%s*(.+)$")), slot = slot, from = from, dungeon = dg.name,
                    quality = quality or 1 }
            end
        end)
    end
    table.sort(out, function(a, b)
        if (a.ilvl or -1) ~= (b.ilvl or -1) then return (a.ilvl or -1) > (b.ilvl or -1) end
        if a.quality ~= b.quality then return a.quality > b.quality end
        return (ns.Loot.ItemName(a.link) or "") < (ns.Loot.ItemName(b.link) or "")
    end)
    return out
end

function Wishlist:Build(page)
    self.page = page
    -- add box: shift-click an item while it has focus
    local box = UI.EditBox(page, LEFT_W, BAR_H)
    box:SetPoint("TOPLEFT", PAD, -TITLE_H)
    box.placeholder = UI.Text(box, 11)
    box.placeholder:SetPoint("LEFT", 8, 0)
    box.placeholder:SetTextColor(0.45, 0.45, 0.5)
    box.placeholder:SetText("Search...")
    box:SetScript("OnTextChanged", function(b)
        local text = b:GetText()
        b.placeholder:SetShown(text == "")
        if text:find("|Hitem:", 1, true) then
            -- a shift-clicked item goes straight on the wishlist
            self:AddLink(text)
            b:SetText("")
            return
        end
        local q = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
        self.search = #q >= 2 and q or nil
        self.offset = 0
        self:Refresh()
    end)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    self.addBox = box

    -- left: our wishlist, then a list per kind of slot
    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", PAD, -LIST_Y)
    side:SetSize(LEFT_W, LIST_H)
    UI.Card(side)
    side.rows = {}
    local entries = { { set = true, icon = "Interface\\Icons\\INV_Misc_Note_01" } }
    for i, l in ipairs(Wishlist.LISTS) do
        entries[#entries + 1] = { label = l.name, list = l, index = i, icon = emptyIcon(slotOf(l.slot)) }
    end
    for i, e in ipairs(entries) do
        local row = CreateFrame("Button", nil, side)
        row:SetHeight(SIDE_ROW)
        row:SetPoint("TOPLEFT", 2, -(4 + (i - 1) * SIDE_ROW))
        row:SetPoint("TOPRIGHT", -2, -(4 + (i - 1) * SIDE_ROW))
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        UI.SelBar(row.sel, 0.12)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 8, 0)
        row.icon:SetTexture(e.icon)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = UI.Text(row, 11)
        row.name:SetPoint("LEFT", 32, 0)
        row.name:SetText(e.label or "")
        row.entry = e
        row:SetScript("OnClick", function(r)
            self.list = r.entry.list
            self.offset = 0
            if self.addBox:GetText() ~= "" then self.addBox:SetText("") end -- (refreshes)
            self:Refresh()
        end)
        side.rows[i] = row
    end
    side.note = UI.Text(side, 11)
    side.note:SetPoint("BOTTOMLEFT", 10, 12)
    side.note:SetWidth(LEFT_W - 20)
    side.note:SetJustifyH("LEFT")
    side.note:SetTextColor(0.5, 0.5, 0.55)
    side.note:SetText("Install DungeonJournal to see where\nitems drop and every item for a slot.")
    self.side = side

    -- right: title row, then the character sheet (or a slot's items)
    self.title = UI.Text(page, 13)
    self.title:SetPoint("LEFT", page, "TOPLEFT", RX + 2, -(TITLE_H + BAR_H / 2))
    self.setsBtn = UI.Button(page, "Wishlists", 84, 20, function(b) self:SetsMenu(b) end)
    self.setsBtn:SetPoint("RIGHT", page, "TOPLEFT", RX + RW, -(TITLE_H + BAR_H / 2))
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", RX, -LIST_Y)
    card:SetSize(RW, LIST_H)
    UI.Card(card)
    self.card = card

    local doll = Wishlist.Sheet(card, function(b, button) self:SlotClick(b, button) end, true)
    doll:SetPoint("TOPLEFT", 0, 0)
    self.doll = doll
    -- the art fills the whole card, behind the slots too
    self.backdrop = doll.model and Wishlist.Backdrop(card, doll.model, card)

    local browse = CreateFrame("Frame", nil, card)
    browse:SetAllPoints()
    browse.hint = UI.ScrollHint(browse, 4, 4)
    browse.visible = math.floor((LIST_H - 8) / ROW_H)
    browse.rows = {}
    for i = 1, browse.visible do
        local row = CreateFrame("Button", nil, browse)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(4 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(4 + (i - 1) * ROW_H))
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        UI.Hover(row.hl, 0.05)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(26, 26)
        row.icon:SetPoint("LEFT", 8, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.right = UI.Text(row, 11)
        row.right:SetPoint("TOPRIGHT", -10, -4)
        row.right:SetJustifyH("RIGHT")
        row.right2 = UI.Text(row, 10)
        row.right2:SetPoint("TOPRIGHT", -10, -19)
        row.right2:SetJustifyH("RIGHT")
        row.name = UI.Text(row, 12)
        row.name:SetPoint("TOPLEFT", 44, -4)
        row.name:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.sub = UI.Text(row, 10)
        row.sub:SetPoint("TOPLEFT", 44, -19)
        row.sub:SetPoint("RIGHT", row.right2, "LEFT", -8, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row.sub:SetTextColor(0.6, 0.6, 0.65)
        row:SetScript("OnClick", function(r, button) self:RowClick(r, button) end)
        row:SetScript("OnEnter", function(r)
            local it = r.data
            if not it or not GameTooltip then return end
            UI.ItemTip(r, it.link)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Wishlist.SourceText(it), 0.5, 0.85, 0.55)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", hideTip)
        browse.rows[i] = row
    end
    browse:EnableMouseWheel(true)
    browse:SetScript("OnMouseWheel", function(_, d)
        self.offset = (self.offset or 0) - d * 3
        self:Refresh()
    end)
    browse.empty = UI.Text(browse, 11)
    browse.empty:SetPoint("TOP", 0, -40)
    browse.empty:SetTextColor(0.5, 0.5, 0.55)
    self.browse = browse
end

-- "Magmatus, Hall of Thanes" or "Quest: An Ancient Grudge, Hall of Thanes".
function Wishlist.SourceText(it)
    return it.from .. ", " .. it.dungeon
end

function Wishlist:Changed()
    if self.page and self.page:IsShown() then self:Refresh() end
end

-- The model wears our gear with the wishlist tried on over it. Dressed again
-- only when the list changes (dressing resets how it's turned).
function Wishlist:Dress()
    local m = self.doll and self.doll.model
    if not m or not m:IsVisible() then return end
    local ids = {}
    for _, it in ipairs(self:Mine()) do ids[#ids + 1] = it.id end
    local sig = table.concat(ids, ",")
    if m.dressed == sig then return end
    m.dressed = sig
    pcall(m.SetUnit, m, "player")
    pcall(m.SetCamDistanceScale, m, MODEL_ZOOM)
    if m.facing then pcall(m.SetFacing, m, m.facing) end
    for _, it in ipairs(self:Mine()) do pcall(m.TryOn, m, it.link) end
end

function Wishlist:Refresh()
    if not self.page then return end
    -- left list: our wishlist on top, then each kind of slot
    self.side.note:SetShown(Journal:DB() == nil)
    local data = self:Data()
    for _, row in ipairs(self.side.rows) do
        local e = row.entry
        if e.set then
            row.name:SetText(self:SetName(data.cur))
            row.sel:SetShown(not self.search and not self.list)
            row.name:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
        else
            row.sel:SetShown(not self.search and e.list == self.list)
            row.name:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
        end
    end

    local listing = self.list ~= nil or self.search ~= nil
    self.doll:SetShown(not listing)
    self.browse:SetShown(listing)
    if self.backdrop then self.backdrop:SetShown(not listing) end
    if listing then
        self:RefreshBrowse()
    else
        self.title:SetText(self:SetName(data.cur))
        self:RefreshDoll()
    end
end

function Wishlist:RefreshDoll()
    local by = self:BySlot()
    local ids = {}
    for _, it in ipairs(self:Mine()) do ids[it.id] = true end
    local sources = Journal:Sources(ids)
    for _, b in ipairs(self.doll.slots) do
        local it = by[b.slot.id]
        if it and it.got then
            Wishlist.FillSlot(b, it, "Got it", { 0.4, 0.85, 0.45 }, true)
        elseif it then
            local src = sources[it.id]
            Wishlist.FillSlot(b, it, src and (src.from .. ", " .. src.dungeon) or "")
        else
            Wishlist.FillSlot(b, nil)
        end
    end
    if self.backdrop then self.backdrop:SetClass(select(2, UnitClass("player"))) end
    self:Dress()
end

function Wishlist:RefreshBrowse()
    local l = self.search and { search = self.search, name = "Search" } or self.list
    local items = self:Items(l)
    local browse = self.browse
    self.title:SetText(self.search and ('Search: "%s"'):format(self.search) or l.name)
    self.offset = math.max(0, math.min(self.offset or 0, #items - browse.visible))
    browse.hint:Set(self.offset, browse.visible, #items)
    for i, row in ipairs(browse.rows) do
        local it = items[i + self.offset]
        row.data = it
        if it then
            local mine = self:Find(it.id)
            it.mine, it.got = mine ~= nil, mine and mine.got ~= nil
            row.icon:SetTexture(iconOf(it.id))
            row.name:SetText(colored(it.link))
            row.sub:SetText(Wishlist.SourceText(it))
            row.right:SetText(it.ilvl and ("ilvl " .. it.ilvl) or "")
            row.right:SetTextColor(0.85, 0.85, 0.88)
            if it.got then
                row.right2:SetText("got it")
                row.right2:SetTextColor(0.4, 0.85, 0.45)
            elseif it.mine then
                row.right2:SetText("on your wishlist")
                row.right2:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
            else
                row.right2:SetText(it.kind or "")
                row.right2:SetTextColor(0.55, 0.55, 0.6)
            end
            row:Show()
        else
            row:Hide()
        end
    end
    browse.empty:SetText(not Journal:DB() and "Install DungeonJournal to see every item for a slot."
        or self.search and "No gear by that name."
        or ("No " .. l.name:lower() .. " items in the journal yet."))
    browse.empty:SetShown(#items == 0)
end

-- A slot's list: a click adds the item, or takes it off again.
function Wishlist:RowClick(row, button)
    local it = row.data
    if not it then return end
    if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(it.link)
        return
    end
    if it.mine then
        self:Remove(it.id)
    else
        self:AddLink(it.link, it.slot)
    end
end

-- Open a slot's list (an empty slot on the sheet does this too).
function Wishlist:OpenList(slotID)
    local l = Wishlist.ListFor(slotID)
    if not l then return end
    self.list = l
    self.offset = 0
    if self.addBox:GetText() ~= "" then self.addBox:SetText("") end
    self:Refresh()
end

-- The sheet: an empty slot opens its list; an item opens its menu.
function Wishlist:SlotClick(b, button)
    local it = b.item
    if not it then
        self:OpenList(b.slot.id)
        return
    end
    if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(it.link)
        return
    end
    local l = Wishlist.ListFor(b.slot.id)
    UI.ShowMenu(b, {
        { text = ns.Loot.ItemName(it.link) or "Item", header = true },
        { text = it.got and "Not got yet" or "Got it", func = function() self:SetGot(it.id, not it.got) end },
        { text = "Browse " .. (l and l.name or "items"), func = function() self:OpenList(b.slot.id) end },
        { text = "Remove from wishlist", color = { 0.95, 0.4, 0.4 }, func = function() self:Remove(it.id) end },
    })
end

------------------------------------------------------------------------
-- Events, tab
------------------------------------------------------------------------
-- Shift-clicking an item while the add box has focus adds it.
if hooksecurefunc and ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(text)
        local box = Wishlist.addBox
        if box and box:IsVisible() and box:HasFocus() and type(text) == "string" and text:find("|Hitem:", 1, true) then
            Wishlist:AddLink(text)
        end
    end)
end

local pending
local function checkSoon()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = nil
        if ns.db then Wishlist:CheckOwned() end
    end)
end
ns.On("BAG_UPDATE_DELAYED", checkSoon)
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    if Wishlist.doll and Wishlist.doll.model then Wishlist.doll.model.dressed = nil end
    checkSoon()
end)
ns.On("PLAYER_LOGIN", function() C_Timer.After(10, checkSoon) end)
-- items load in bursts: refresh once they settle (item levels sort the lists)
local loadPending
ns.On("ITEM_DATA_LOAD_RESULT", function()
    if loadPending then return end
    loadPending = true
    C_Timer.After(0.3, function()
        loadPending = nil
        Wishlist:Changed()
    end)
end)

ns.Editor:RegisterTab("wishlist", "Wishlist", 0.9,
    function(page) Wishlist:Build(page) end,
    function()
        if Wishlist.doll and Wishlist.doll.model then Wishlist.doll.model.dressed = nil end
        Wishlist:Refresh()
    end)
