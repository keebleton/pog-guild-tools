-- Pog Guild Tools LFG tab: the guild's groups and who's looking.
--
-- Left: you (your role, a note, whether you're looking) and the dungeons by
-- level: click one (or its tick box) and you're looking for it. Dungeons in
-- your level range stand out. Right: the group finder's listings as tiles
-- (Join right there, or manage your own with Home's menu), then everyone
-- looking, the ones after the same dungeons as you first.
--
-- Looking: one `lfd` record per player (the dungeons, comma separated; a
-- role; a short note), gone after LOOK_HOURS or when you stop. Any change
-- renews it. Dungeon names come from the DungeonJournal addon when it's
-- installed, else the list below.
--
-- Layout (902 x PAGE_H window), both columns from the top:
--   [You               Stop ]  [Groups                                Post group  ]
--   [[Tank][Heals][DPS]     ]  [[tile: what, leader, pips  Join] [tile ...]        ]
--   [Note (optional)        ]  [LOOKING FOR GROUP                                 ]
--   [DUNGEONS               ]  [(role) Name 24   Deadmines, SFK       online  3h  ]
--   [x Hall of Thanes   13-20]  [ ...                                              ]
local _, ns = ...
local UI = ns.UI
local Sync = ns.Sync

local Dungeons = {}
ns.Dungeons = Dungeons

Dungeons.LOOK_HOURS = 4
Dungeons.ART = "Hunter: Beast Mastery" -- behind the dungeon list (Jake's pick)
Dungeons.MAX_NAMES = 400 -- characters of dungeon names in one record
Dungeons.MAX_NOTE = 40
Dungeons.ROLES = { { "D", "DPS", { 0.95, 0.35, 0.30 }, "DAMAGER" }, { "T", "Tank", { 0.45, 0.70, 1.00 }, "TANK" },
    { "H", "Heals", { 0.35, 0.90, 0.40 }, "HEALER" } }
local ROLE = { D = 1, T = 2, H = 3, M = 1, R = 1 }

-- The dungeons when DungeonJournal isn't installed (name, level range).
Dungeons.KNOWN = {
    { "Hall of Thanes", "13-20" }, { "Ragefire Chasm", "13-18" }, { "Ruins of Lordaeron", "15-22" },
    { "Wailing Caverns", "15-24" }, { "The Deadmines", "17-26" }, { "Shadowfang Keep", "20-30" },
    { "Blackfathom Deeps", "22-32" }, { "The Stockade", "24-32" }, { "Excavation Site: Wetlands", "26-31" },
    { "City of Dalaran", "28-33" }, { "Gnomeregan", "29-38" }, { "Razorfen Kraul", "29-38" },
    { "Scarlet Monastery: Graveyard", "30-38" }, { "Scarlet Monastery: Library", "33-41" },
}
local function me() return Sync:Me() end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end
local function display(name) return name and Ambiguate(name, "short") end
local function G() return ns.db.guild end

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

local function roleOf(key) return Dungeons.ROLES[ROLE[key or "D"] or 1] end

-- The game's role icon on a texture: the large group finder icons (sharp at
-- any size here; the small ones blur when scaled up), else the classic round
-- role icons.
local ROLE_ATLAS = {
    TANK = { "groupfinder-icon-role-large-tank", "UI-LFG-RoleIcon-Tank" },
    HEALER = { "groupfinder-icon-role-large-heal", "UI-LFG-RoleIcon-Healer" },
    DAMAGER = { "groupfinder-icon-role-large-dps", "UI-LFG-RoleIcon-DPS" },
}
Dungeons.ROLE_ATLAS = ROLE_ATLAS

function Dungeons.RoleIcon(tex, key)
    local role = roleOf(key)[4]
    if C_Texture and C_Texture.GetAtlasInfo and tex.SetAtlas then
        for _, atlas in ipairs(ROLE_ATLAS[role]) do
            local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
            if ok and type(info) == "table" and pcall(tex.SetAtlas, tex, atlas) then return end
        end
    end
    tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    if GetTexCoordsForRoleSmallCircle then
        local ok, l, r, t, b = pcall(GetTexCoordsForRoleSmallCircle, role)
        if ok and l then tex:SetTexCoord(l, r, t, b) end
    end
end

------------------------------------------------------------------------
-- Looking for a group (shared)
------------------------------------------------------------------------
Sync:Register({
    name = "lfd", code = "f", order = 2,
    fields = { "list", "role", "exp", "note" },
    numeric = { exp = true },
    valid = function(rec)
        if rec.by ~= rec.author or rec.id ~= rec.author or type(rec.exp) ~= "number" then return false end
        if rec.exp - rec.t > Dungeons.LOOK_HOURS * 3600 + 60 then return false end
        if rec.deleted then return true end
        return type(rec.list) == "string" and rec.list ~= "" and #rec.list <= Dungeons.MAX_NAMES
            and not rec.list:find("[%c|]") and (rec.role == nil or (type(rec.role) == "string" and #rec.role <= 3
                and rec.role:match("^[DTH]+$") ~= nil))
            and (rec.note == nil or (type(rec.note) == "string" and #rec.note <= Dungeons.MAX_NOTE and not rec.note:find("[%c|]")))
    end,
    prune = function(store)
        local cutoff = ns.Now() - 86400
        for id, rec in pairs(store) do
            if (rec.exp or 0) < cutoff then store[id] = nil end
        end
    end,
    expired = function(rec) return rec.exp < ns.Now() end,
    onChange = function() Dungeons:Changed() end,
})

local function split(list)
    local out = {}
    for name in (list or ""):gmatch("[^,]+") do out[#out + 1] = name end
    return out
end

-- Everyone looking right now: { name, list = {dungeons}, role, note, exp,
-- online, level, shared (dungeons in common with ours) }.
function Dungeons:Looking()
    local out, now = {}, ns.Now()
    for name, rec in pairs(Sync:Store("lfd") or {}) do
        if not rec.deleted and rec.exp > now then
            local p = G().players[name]
            out[#out + 1] = { name = name, list = split(rec.list), role = rec.role, note = rec.note, exp = rec.exp,
                online = (p and p.online) or name == me(), level = p and p.level }
        end
    end
    -- ours first, then those after the same dungeons as us, online, by name
    local mine = {}
    local rec = self:MyLooking()
    for _, d in ipairs(split(rec and rec.list)) do mine[d] = true end
    for _, l in ipairs(out) do
        l.shared = 0
        for _, d in ipairs(l.list) do if mine[d] then l.shared = l.shared + 1 end end
    end
    table.sort(out, function(a, b)
        if (a.name == me()) ~= (b.name == me()) then return a.name == me() end
        if (a.shared > 0) ~= (b.shared > 0) then return a.shared > 0 end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end

-- Who's looking for one dungeon.
function Dungeons:LookingFor(dungeon)
    local out = {}
    for _, l in ipairs(self:Looking()) do
        for _, d in ipairs(l.list) do
            if d == dungeon then out[#out + 1] = l break end
        end
    end
    return out
end

function Dungeons:MyLooking()
    local rec = (Sync:Store("lfd") or {})[me()]
    if rec and not rec.deleted and rec.exp > ns.Now() then return rec end
end

function Dungeons:IsLooking(dungeon)
    local rec = self:MyLooking()
    for _, d in ipairs(split(rec and rec.list)) do
        if d == dungeon then return true end
    end
    return false
end

-- Our roles, as letters in Tank, Heals, DPS order ("TD"): picked here, else
-- our profile's main role and off spec, else DPS.
local ORDER = { "T", "H", "D" }
local function sortRoles(set)
    local out = ""
    for _, k in ipairs(ORDER) do if set[k] then out = out .. k end end
    return out
end
Dungeons.SortRoles = sortRoles

function Dungeons:Role()
    if ns.db.lookRole and ns.db.lookRole ~= "" then return ns.db.lookRole end
    local content = ns.Profiles and ns.Profiles:Content(me()) or {}
    local set = {}
    for _, r in ipairs({ content.role, content.off }) do
        local i = r and ROLE[r]
        if i then set[Dungeons.ROLES[i][1]] = true end
    end
    local roles = sortRoles(set)
    return roles ~= "" and roles or "D"
end

function Dungeons:Note() return ns.db.lookNote end

local function write(list)
    local who, now = me(), ns.Now()
    if #list == 0 then
        local cur = (Sync:Store("lfd") or {})[who]
        if cur and not cur.deleted then
            Sync:Write("lfd", { id = who, author = who, t = now, exp = now, deleted = true })
        end
    else
        Sync:Write("lfd", { id = who, author = who, t = now, exp = now + Dungeons.LOOK_HOURS * 3600,
            list = table.concat(list, ","), role = Dungeons:Role(), note = Dungeons:Note() })
    end
    Dungeons:Changed()
end

function Dungeons:SetLooking(dungeon, on)
    if not Sync:GuildName() or not dungeon or dungeon:find("[,%c|]") then return end
    local list = {}
    local rec = self:MyLooking()
    for _, d in ipairs(split(rec and rec.list)) do
        if d ~= dungeon then list[#list + 1] = d end
    end
    if on then list[#list + 1] = dungeon end
    write(list)
end

function Dungeons:StopLooking() write({}) end

-- Roles toggle: any of the three, at least one.
function Dungeons:SetRole(key)
    local set = {}
    for k in self:Role():gmatch(".") do set[k] = true end
    set[key] = not set[key] or nil
    local roles = sortRoles(set)
    if roles == "" then return end
    ns.db.lookRole = roles
    local rec = self:MyLooking()
    if rec then write(split(rec.list)) else self:Changed() end
end

function Dungeons:SetNote(text)
    text = ns.Codec.CleanText(text or "", Dungeons.MAX_NOTE):gsub("[,|]", "")
    if text == "" then text = nil end
    if text == ns.db.lookNote then return end
    ns.db.lookNote = text
    local rec = self:MyLooking()
    if rec then write(split(rec.list)) end
end

-- Level ranges we show instead of the journal's (it has Blackfathom Deeps as
-- an open-ended "22+"; Jake: 22-32).
Dungeons.LEVEL_FIX = { ["Blackfathom Deeps"] = "22-32" }

-- The dungeons by level: { name, level, min, max }.
function Dungeons:List()
    local out = {}
    local journal = ns.Journal and ns.Journal:List() or {}
    if #journal > 0 then
        for _, dg in ipairs(journal) do out[#out + 1] = { name = dg.name, level = dg.level } end
    else
        for _, k in ipairs(Dungeons.KNOWN) do out[#out + 1] = { name = k[1], level = k[2] } end
    end
    for _, d in ipairs(out) do
        d.level = Dungeons.LEVEL_FIX[d.name] or d.level
        d.min = tonumber(d.level:match("^(%d+)")) or 1
        d.max = tonumber(d.level:match("%-(%d+)$")) or (d.min + 10)
    end
    return out
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local PAD, GAP, TITLE_H, BAR_H = 12, 8, 30, 26
local FRAME_W, FRAME_H = 902, ns.PAGE_H
local LEFT_W = 262
local RX = PAD + LEFT_W + PAD
local RW = FRAME_W - RX - PAD
local LIST_Y = TITLE_H
local LIST_H = FRAME_H - PAD - LIST_Y
local HEAD_H = 26
local YOU_H = HEAD_H + 10 + 30 + 8 + 24 + 12
local DUNGEON_ROW = 26
local LEVEL_W = 40 -- the level ranges: one right-aligned column
local TILE_W = math.floor((RW - 24 - 8) / 2)
local TILE_H = 82
local GROUPS_H = HEAD_H + 8 + 2 * TILE_H + 8 + 8
local LOOK_ROW = 42
local ROLES_W = 8 + 3 * 21 + 8 -- room for three role icons before a name

Dungeons.layout = { RX = RX, RW = RW, LIST_Y = LIST_Y, LIST_H = LIST_H, YOU_H = YOU_H, GROUPS_H = GROUPS_H,
    TILE_W = TILE_W, TILE_H = TILE_H }

local function card(page, title, x, y, w, h, icon)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", x, -y)
    c:SetSize(w, h)
    UI.Card(c)
    c.title = UI.SectionTitle(c, title)
    if icon and (not ns.Art or ns.Art.Has({ kind = "file", path = icon }) ~= false) then
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(14, 14)
        c.icon:SetPoint("LEFT", c, "TOPLEFT", 10, -HEAD_H / 2)
        c.icon:SetTexture(icon)
        c.icon:SetTexCoord(0.04, 0.96, 0.04, 0.96) -- (a light crop: some icons' art runs to the edge)
        c.title:SetPoint("LEFT", c, "TOPLEFT", 10 + 14 + 6, -HEAD_H / 2)
    else
        c.title:SetPoint("LEFT", c, "TOPLEFT", 10, -HEAD_H / 2)
    end
    c.meta = UI.Text(c, 10)
    c.meta:SetPoint("RIGHT", c, "TOPRIGHT", -10, -HEAD_H / 2)
    c.meta:SetTextColor(0.5, 0.5, 0.55)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    UI.Line(line, 0.06)
    c.empty = UI.Text(c, 11)
    c.empty:SetPoint("TOP", 0, -HEAD_H - 24)
    c.empty:SetWidth(w - 24)
    c.empty:SetTextColor(0.5, 0.5, 0.55)
    c.empty:Hide()
    return c
end

function Dungeons:Build(page)
    self.page = page
    self:BuildYou(page)
    self:BuildDungeons(page)
    self:BuildGroups(page)
    self:BuildLooking(page)
end

-- You: role, note, looking or not.
function Dungeons:BuildYou(page)
    local c = card(page, "You", PAD, LIST_Y, LEFT_W, YOU_H)
    c.stop = UI.Button(c, "Stop looking", 90, 18, function() self:StopLooking() end)
    c.stop:SetPoint("RIGHT", c, "TOPRIGHT", -5, -HEAD_H / 2)
    c.roles = {}
    local bw = math.floor((LEFT_W - 24 - 8) / 3)
    for i, r in ipairs({ Dungeons.ROLES[2], Dungeons.ROLES[3], Dungeons.ROLES[1] }) do
        local b = UI.Button(c, r[2], bw, 30, function() self:SetRole(r[1]) end)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * (bw + 4), -(HEAD_H + 10))
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        Dungeons.RoleIcon(b.icon, r[1])
        local tw = math.floor(b.label:GetStringWidth() + 0.5)
        local x0 = math.floor((bw - (18 + 5 + tw)) / 2)
        b.icon:SetPoint("LEFT", x0, 0)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", x0 + 18 + 5, 0)
        b.label:SetJustifyH("LEFT")
        b.key = r[1]
        c.roles[i] = b
    end
    local note = UI.EditBox(c, LEFT_W - 24, 24)
    note:SetPoint("TOPLEFT", 12, -(HEAD_H + 10 + 30 + 8))
    note:SetMaxLetters(Dungeons.MAX_NOTE)
    note.placeholder = UI.Text(note, 11)
    note.placeholder:SetPoint("LEFT", 8, 0)
    note.placeholder:SetTextColor(0.45, 0.45, 0.5)
    note.placeholder:SetText("Note (optional)")
    note:SetScript("OnTextChanged", function(b) b.placeholder:SetShown(b:GetText() == "") end)
    note:SetScript("OnEnterPressed", function(b)
        b:ClearFocus()
        self:SetNote(b:GetText())
    end)
    note:SetScript("OnEditFocusLost", function(b)
        UI.SetBorderColor(b, UI.BUTTON_BORDER)
        self:SetNote(b:GetText())
    end)
    c.note = note
    self.you = c
end

-- The dungeons: click one (or its tick box) to look for it, again to stop.
function Dungeons:BuildDungeons(page)
    local y = LIST_Y + YOU_H + GAP
    local h = LIST_H - YOU_H - GAP
    local c = card(page, "Dungeons", PAD, y, LEFT_W, h)
    if ns.Art then -- faint game art behind the list
        c.art = ns.Art.CardArt(c)
        c.art:Show(ns.Art.Find("Talent trees", Dungeons.ART))
    end
    c.offset = 0
    c.visible = math.floor((h - HEAD_H - 8) / DUNGEON_ROW)
    c.hint = UI.ScrollHint(c, HEAD_H + 4, 4)
    c.rows = {}
    for i = 1, c.visible do
        local row = CreateFrame("Button", nil, c)
        row:SetHeight(DUNGEON_ROW)
        row:SetPoint("TOPLEFT", 2, -(HEAD_H + 4 + (i - 1) * DUNGEON_ROW))
        row:SetPoint("TOPRIGHT", -2, -(HEAD_H + 4 + (i - 1) * DUNGEON_ROW))
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        -- the tick box: looking for this one
        row.box = CreateFrame("Button", nil, row)
        row.box.row = row
        row.box:SetSize(22, DUNGEON_ROW)
        row.box:SetPoint("LEFT", 4, 0)
        row.box.frame = CreateFrame("Frame", nil, row.box)
        row.box.frame:SetSize(14, 14)
        row.box.frame:SetPoint("CENTER", 0, 0)
        UI.Panel(row.box.frame, { 0.02, 0.02, 0.03, 1 }, UI.BUTTON_BORDER)
        row.box.mark = row.box.frame:CreateTexture(nil, "ARTWORK")
        row.box.mark:SetPoint("TOPLEFT", 3, -3)
        row.box.mark:SetPoint("BOTTOMRIGHT", -3, 3)
        row.box.mark:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
        row.box:SetScript("OnClick", function(b)
            local r = b.row
            if r.dungeon then self:SetLooking(r.dungeon, not self:IsLooking(r.dungeon)) end
        end)
        row.box:SetScript("OnEnter", function(b) UI.SetBorderColor(b.frame, UI.ACCENT) end)
        row.box:SetScript("OnLeave", function(b) UI.SetBorderColor(b.frame, UI.BUTTON_BORDER) end)
        row.level = UI.Text(row, 10)
        row.level:SetPoint("RIGHT", -12, 0)
        row.level:SetWidth(LEVEL_W)
        row.level:SetJustifyH("RIGHT")
        row.level:SetTextColor(0.5, 0.5, 0.55)
        row.name = UI.Text(row, 11)
        row.name:SetPoint("LEFT", 30, 0)
        row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", function(r)
            if r.dungeon then self:SetLooking(r.dungeon, not self:IsLooking(r.dungeon)) end
        end)
        c.rows[i] = row
    end
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, d)
        c.offset = c.offset - d * 2
        self:Refresh()
    end)
    self.dungeons = c
end

-- A group as a tile: what, who leads it and what they need, how full, time
-- left; Join (or, for ours, the group finder's menu).
local function tile(self, parent)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(TILE_W, TILE_H)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t.bg = t:CreateTexture(nil, "BACKGROUND", nil, 1)
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(1, 1, 1, 0.035)
    t.edge = t:CreateTexture(nil, "BORDER")
    t.edge:SetPoint("TOPLEFT")
    t.edge:SetSize(2, TILE_H)
    t.edge:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.8)
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Hover(hl, 0.04)
    t.left = UI.Text(t, 10)
    t.left:SetPoint("TOPRIGHT", -10, -11)
    t.left:SetTextColor(0.55, 0.55, 0.6)
    t.what = UI.Text(t, 13)
    t.what:SetPoint("TOPLEFT", 12, -10)
    t.what:SetPoint("RIGHT", t.left, "LEFT", -8, 0)
    t.what:SetJustifyH("LEFT")
    t.what:SetWordWrap(false)
    t.who = UI.Text(t, 10)
    t.who:SetPoint("TOPLEFT", 12, -30)
    t.who:SetPoint("RIGHT", -10, 0)
    t.who:SetJustifyH("LEFT")
    t.who:SetWordWrap(false)
    t.pips = {}
    for i = 1, 5 do
        local p = t:CreateTexture(nil, "ARTWORK")
        p:SetSize(12, 12)
        p:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 15, 15)
        t.pips[i] = p
    end
    t.size = UI.Text(t, 10)
    t.size:SetPoint("BOTTOMLEFT", 12, 15)
    t.join = UI.Button(t, "Join", 84, 22, function()
        local g = t.item
        if not g then return end
        if g.author == me() then
            if ns.Home then ns.Home:GroupMenu(t) end
        elseif not ns.Social.requested[g.id] and not ns.Social:IsFull(g) then
            ns.Social:RequestJoin(g)
            self:Refresh()
        end
    end)
    t.join:SetPoint("BOTTOMRIGHT", -10, 10)
    t:SetScript("OnClick", function(b) if ns.Home then ns.Home:GroupMenu(b) end end)
    t:SetScript("OnEnter", function(b) if ns.Home then ns.Home:GroupTooltip(b) end end)
    t:SetScript("OnLeave", hideTip)
    return t
end

function Dungeons:BuildGroups(page)
    local c = card(page, "Groups", RX, LIST_Y, RW, GROUPS_H, "Interface\\Icons\\INV_Misc_Spyglass_02")
    -- posting a group sits in the card's header, as on Home
    self.postBtn = UI.Button(c, "Post group", 74, 18, function()
        if ns.Home then ns.Home:PostGroupDialog() end
    end)
    self.postBtn:SetPoint("RIGHT", c, "TOPRIGHT", -5, -HEAD_H / 2)
    c.offset = 0
    c.tiles = {}
    for i = 1, 4 do
        local t = tile(self, c)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        t:SetPoint("TOPLEFT", 12 + col * (TILE_W + 8), -(HEAD_H + 8 + row * (TILE_H + 8)))
        c.tiles[i] = t
    end
    c.hint = UI.ScrollHint(c, HEAD_H + 4, 4)
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, d)
        c.offset = c.offset - d * 2
        self:Refresh()
    end)
    self.groups = c
end

function Dungeons:BuildLooking(page)
    local y = LIST_Y + GROUPS_H + GAP
    local h = LIST_H - GROUPS_H - GAP
    local c = card(page, "Looking for group", RX, y, RW, h, "Interface\\Icons\\Ability_Warrior_BattleShout")
    c.offset = 0
    c.visible = math.floor((h - HEAD_H - 8) / LOOK_ROW)
    c.hint = UI.ScrollHint(c, HEAD_H + 4, 4)
    c.rows = {}
    for i = 1, c.visible do
        local row = CreateFrame("Button", nil, c)
        row:SetHeight(LOOK_ROW)
        row:SetPoint("TOPLEFT", 2, -(HEAD_H + 4 + (i - 1) * LOOK_ROW))
        row:SetPoint("TOPRIGHT", -2, -(HEAD_H + 4 + (i - 1) * LOOK_ROW))
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        row.roles = {}
        for k = 1, 3 do
            local t = row:CreateTexture(nil, "ARTWORK")
            t:SetSize(20, 20)
            t:SetPoint("LEFT", 8 + (k - 1) * 21, 0)
            row.roles[k] = t
        end
        row.right = UI.Text(row, 10)
        row.right:SetPoint("TOPRIGHT", -10, -7)
        row.right:SetJustifyH("RIGHT")
        row.text = UI.Text(row, 12)
        row.text:SetPoint("TOPLEFT", ROLES_W, -6)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.sub = UI.Text(row, 10)
        row.sub:SetPoint("TOPLEFT", ROLES_W, -23)
        row.sub:SetPoint("RIGHT", -10, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row.sub:SetTextColor(0.65, 0.65, 0.7)
        row:SetScript("OnClick", function(r) self:LookingMenu(r) end)
        c.rows[i] = row
    end
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, d)
        c.offset = c.offset - d * 3
        self:Refresh()
    end)
    self.looking = c
end

function Dungeons:Changed()
    if self.page and self.page:IsShown() then self:Refresh() end
end

local function timeLeft(exp)
    local left = math.max(0, exp - ns.Now())
    return left >= 3600 and (math.floor(left / 3600) .. "h left") or (math.ceil(left / 60) .. "m left")
end
Dungeons.TimeLeft = timeLeft

function Dungeons:Refresh()
    if not self.page then return end
    local inGuild = Sync:GuildName() ~= nil
    self.postBtn:SetShown(inGuild)
    local looking = self:Looking()
    local groups = ns.Social:Groups()
    local mine = self:MyLooking()
    local myLevel = UnitLevel and UnitLevel("player") or 0

    -- you
    local you = self.you
    local role = self:Role()
    for _, b in ipairs(you.roles) do b:SetSelected(role:find(b.key, 1, true) ~= nil) end
    you.stop:SetShown(mine ~= nil)
    you.meta:SetShown(mine == nil)
    you.meta:SetText("Not looking")
    if not you.note:HasFocus() then you.note:SetText(self:Note() or "") end

    -- the dungeons
    local list = self:List()
    local c = self.dungeons
    local entries = list
    c.meta:SetText(mine and "Looking" or "")
    if mine then c.meta:SetTextColor(0.4, 0.85, 0.45) else c.meta:SetTextColor(0.5, 0.5, 0.55) end
    c.offset = math.max(0, math.min(c.offset, #entries - c.visible))
    c.hint:Set(c.offset, c.visible, #entries)
    for i, row in ipairs(c.rows) do
        local e = entries[i + c.offset]
        row.dungeon = e and e.name
        if e then
            local fits = myLevel >= e.min - 2 and myLevel <= e.max
            row.name:SetText(e.name)
            if fits then row.name:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) else row.name:SetTextColor(0.5, 0.5, 0.55) end
            row.level:SetText(e.level)
            row.box:SetShown(inGuild)
            row.box.mark:SetShown(self:IsLooking(e.name))
            row:Show()
        else
            row:Hide()
        end
    end

    self:RefreshGroups(groups, inGuild)
    self:RefreshLooking(looking, inGuild, mine)
end

function Dungeons:RefreshGroups(groups, inGuild)
    local c = self.groups
    c.offset = math.max(0, math.min(c.offset, #groups - 4))
    c.offset = c.offset - c.offset % 2
    c.hint:Set(c.offset, 4, #groups)
    for i, t in ipairs(c.tiles) do
        local g = groups[i + c.offset]
        t.item = g
        if g then
            local full = ns.Social:IsFull(g)
            local ours = g.author == me()
            t.what:SetText(g.what)
            t.who:SetText(colorName(g.author) .. (g.need and ("  |cff9a9aa2needs " .. g.need .. "|r") or ""))
            t.left:SetText(math.max(0, math.ceil((g.exp - ns.Now()) / 60)) .. "m left")
            local size, max = g.size or 1, g.max or 5
            for k, p in ipairs(t.pips) do
                p:SetShown(max == 5)
                if k <= size then p:SetColorTexture(0.4, 0.85, 0.45, 0.95) else p:SetColorTexture(1, 1, 1, 0.12) end
            end
            t.size:SetShown(max ~= 5)
            t.size:SetText(size .. "/" .. max)
            t.edge:SetShown(ours)
            if ours then
                local n = ns.Social:RequestCount()
                t.join:SetLabel(n > 0 and (n .. (n == 1 and " request" or " requests")) or "Manage")
                t.join:SetEnabledState(true)
            elseif ns.Social.requested[g.id] then
                t.join:SetLabel("Requested")
                t.join:SetEnabledState(false)
            elseif full then
                t.join:SetLabel("Full")
                t.join:SetEnabledState(false)
            else
                t.join:SetLabel("Join")
                t.join:SetEnabledState(true)
            end
            t:Show()
        else
            t:Hide()
        end
    end
    c.empty:SetText(inGuild and "No groups up." or "")
    c.empty:SetShown(#groups == 0)
end

function Dungeons:RefreshLooking(looking, inGuild, mine)
    local c = self.looking
    local wanted = {}
    for _, d in ipairs(split(mine and mine.list)) do wanted[d] = true end
    c.offset = math.max(0, math.min(c.offset, #looking - c.visible))
    c.hint:Set(c.offset, c.visible, #looking)
    for i, row in ipairs(c.rows) do
        local l = looking[i + c.offset]
        row.item = l
        if l then
            local k = 0
            for key in tostring(l.role or "D"):gmatch(".") do
                k = k + 1
                if row.roles[k] then
                    Dungeons.RoleIcon(row.roles[k], key)
                    row.roles[k]:Show()
                end
            end
            for j = k + 1, 3 do row.roles[j]:Hide() end
            row.text:SetText(colorName(l.name) .. (l.level and ("  |cff8a8a92" .. l.level .. "|r") or ""))
            local names = {}
            for _, d in ipairs(l.list) do
                names[#names + 1] = (wanted[d] and l.name ~= me()) and (UI.AccentCode() .. d .. "|r") or d
            end
            row.sub:SetText(table.concat(names, ", ") .. (l.note and ('  |cff9a9aa2"' .. l.note .. '"|r') or ""))
            row.right:SetText(l.online and "online" or "offline")
            if l.online then row.right:SetTextColor(0.4, 0.85, 0.45) else row.right:SetTextColor(0.5, 0.5, 0.55) end
            row:Show()
        else
            row:Hide()
        end
    end
    c.empty:SetText(inGuild and "Nobody is looking right now." or "")
    c.empty:SetShown(#looking == 0)
end

-- Someone looking: whisper or invite them; ours: stop.
function Dungeons:LookingMenu(row)
    local l = row.item
    if not l then return end
    local menu = { { text = display(l.name) .. ", " .. table.concat(l.list, ", "), header = true } }
    if l.name == me() then
        menu[#menu + 1] = { text = "Stop looking", color = { 0.95, 0.4, 0.4 }, func = function() self:StopLooking() end }
    else
        menu[#menu + 1] = { text = "Whisper " .. display(l.name), func = function()
            if ns.Home and ns.Home.Whisper then ns.Home.Whisper(l.name) end
        end }
        if l.online then
            menu[#menu + 1] = { text = "Invite " .. display(l.name), color = { 0.5, 0.9, 0.55 },
                func = function() if ns.Home then ns.Home.Invite(l.name) end end }
        end
    end
    UI.ShowMenu(row, menu)
end

ns.Editor:RegisterTab("lfg", "LFG", 0.8,
    function(page) Dungeons:Build(page) end,
    function() Dungeons:Refresh() end)
