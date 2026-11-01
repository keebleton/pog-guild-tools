-- PogRaid loot log: who got what, from which boss, on which night.
--
-- Loot is caught from every place the client reports it (boss loot event,
-- loot roll history, chat loot messages) because Forever's loot system is
-- not confirmed yet; the same item for the same player within two minutes
-- is one entry. It records while an attendance night is recording.
--
-- Layout (same grid as the other tabs):
--   [search players/items]  [All nights v]                 [Options]
--   [status line         ]  [N items, M players ..................]
--   [All players         ]  [Date  Player  Item          Boss  Tag]
--   [players ...         ]  [ ...                                 ]
--   [Add loot            ]  [                     [CSV][Discord]  ]
local _, ns = ...
local UI = ns.UI

local Loot = {}
ns.Loot = Loot

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

Loot.DEDUPE_SECONDS = 120
Loot.BOSS_WINDOW = 600   -- loot this soon after a kill is credited to that boss

Loot.TAGS = {
    { key = "ms",   label = "Main spec",    short = "MS" },
    { key = "os",   label = "Off spec",     short = "OS" },
    { key = "alt",  label = "Alt",          short = "Alt" },
    { key = "de",   label = "Disenchanted", short = "DE" },
    { key = "bank", label = "Guild bank",   short = "Bank" },
}
local TAG = {}
for _, t in ipairs(Loot.TAGS) do TAG[t.key] = t end

local QUALITY_BY_COLOR = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5,
    ["e6cc80"] = 6, ["00ccff"] = 7,
}
local QUALITY_NAMES = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }

local function G() return ns.db.guild end
local function display(name) return name and Ambiguate(name, "short") end

local function secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function classColor(name)
    local p = G().players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if c then return c.r, c.g, c.b end
    return 0.75, 0.75, 0.78
end

function Loot.ItemID(link)
    return tonumber(link and link:match("item:(%d+)"))
end

function Loot.ItemName(link)
    return link and link:match("|h%[(.-)%]|h") or link
end

function Loot.Quality(link)
    local hex = link and link:match("|c%x%x(%x%x%x%x%x%x)")
    local q = hex and QUALITY_BY_COLOR[hex:lower()] or tonumber(link and link:match("|cnIQ(%d+):"))
    if q then return q end
    local id = Loot.ItemID(link)
    if id and C_Item and C_Item.GetItemQualityByID then
        local ok, quality = pcall(C_Item.GetItemQualityByID, id)
        if ok then return quality end
    end
end

------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------
function Loot:Entries()
    local out = {}
    for _, e in pairs(G().loot) do
        if not e.deleted then out[#out + 1] = e end
    end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.id > b.id
    end)
    return out
end

-- Most recent boss killed on the active night, if it was recent enough.
local function recentBoss(s)
    if not s or not s.bosses then return nil end
    for i = #s.bosses, 1, -1 do
        local b = s.bosses[i]
        if b.success then
            if ns.Now() - b.t <= Loot.BOSS_WINDOW then return b.name end
            return nil
        end
    end
end

-- Loot is only logged automatically for guild members, so pugs in the group
-- are skipped (Add loot still takes anyone). Until the guild roster has been
-- read once nobody is known yet, so everyone counts.
function Loot.FromGuild(key)
    if not G().scanned then return true end
    local p = G().players[key]
    return p ~= nil and p.inGuild == true
end

-- The one place new loot lands. Returns the entry, or nil if skipped.
function Loot:Record(player, link, source, boss)
    if not player or not link or secret(player) or secret(link) then return nil end
    local s = ns.Attendance:Active()
    if not s then return nil end
    local itemID = Loot.ItemID(link)
    if not itemID then return nil end
    local quality = Loot.Quality(link)
    if quality and quality < (G().lootMinQuality or 3) then return nil end
    local key = ns.Attendance:Key(player)
    if not Loot.FromGuild(key) then return nil end
    local now = ns.Now()
    for _, e in pairs(G().loot) do
        if not e.deleted and e.player == key and e.itemID == itemID and math.abs(now - e.t) <= Loot.DEDUPE_SECONDS then
            if boss and not e.boss then
                e.boss = boss
                ns.Touch(e)
                self:Changed()
            end
            return nil
        end
    end
    local e = { id = ns.NewId(), t = now, player = key, itemID = itemID, link = link, quality = quality,
        boss = boss or recentBoss(s), sessionId = s.id, tag = "ms", source = source }
    ns.Touch(e)
    G().loot[e.id] = e
    self:Changed()
    return e
end

function Loot:AddManual(player, link)
    local itemID = Loot.ItemID(link)
    if not itemID then
        ns.Print("loot: shift-click the item into the box so it is a real item link")
        return nil
    end
    local s = ns.Attendance:Active() or ns.Attendance:Viewing() or ns.Attendance:Sessions()[1]
    local e = { id = ns.NewId(), t = ns.Now(), player = ns.Attendance:Key(player), itemID = itemID, link = link,
        quality = Loot.Quality(link), sessionId = s and s.id, tag = "ms", source = "manual" }
    ns.Touch(e)
    G().loot[e.id] = e
    self:Changed()
    return e
end

function Loot:SetTag(e, tag)
    e.tag = tag
    ns.Touch(e)
    self:Changed()
end

function Loot:Reassign(e, player)
    e.player = ns.Attendance:Key(player)
    ns.Touch(e)
    self:Changed()
end

function Loot:Delete(e)
    e.deleted = true
    ns.Touch(e)
    self:Changed()
end

-- Chat loot messages, matched with the client's own localized formats.
local function toPattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

function Loot:ChatPatterns()
    if self.patterns then return self.patterns end
    local list = {}
    local function add(fmt, self_)
        local p = toPattern(fmt)
        if p then list[#list + 1] = { p = p, self = self_ } end
    end
    -- multiple-count formats first, or "x2" would stick to the item. Not the
    -- "You receive item:" lines (LOOT_ITEM_PUSHED_SELF): those are quest
    -- rewards, vendor buys and things made in your bags, never a drop.
    add(LOOT_ITEM_MULTIPLE, false)
    add(LOOT_ITEM_SELF_MULTIPLE, true)
    add(LOOT_ITEM, false)
    add(LOOT_ITEM_SELF, true)
    self.patterns = list
    return list
end

-- "Name receives loot: [item]." -> name, link (nil if not a loot line).
function Loot:ParseChat(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    for _, pat in ipairs(self:ChatPatterns()) do
        local a, b = msg:match(pat.p)
        if a then
            if pat.self then return ns.PlayerName(), a end
            return a, b
        end
    end
end

function Loot:OnChat(msg)
    local player, link = self:ParseChat(msg)
    if player then self:Record(player, link, "chat") end
end

------------------------------------------------------------------------
-- Summaries
------------------------------------------------------------------------
function Loot:Changed()
    self.counts = nil
    if self.page and self.page:IsShown() then self:Refresh() end
end

-- Per player: main spec items and all items over the last 8 nights, and
-- their most recent item.
function Loot:Counts()
    if self.counts then return self.counts end
    local recent = {}
    for i, s in ipairs(ns.Attendance:Sessions()) do
        if i > 8 then break end
        recent[s.id] = true
    end
    local counts = {}
    for _, e in ipairs(self:Entries()) do
        local c = counts[e.player]
        if not c then
            c = { ms = 0, total = 0, last = e }
            counts[e.player] = c
        end
        if e.sessionId and recent[e.sessionId] then
            c.total = c.total + 1
            if e.tag == "ms" then c.ms = c.ms + 1 end
        end
    end
    self.counts = counts
    return counts
end

function Loot:Filtered()
    local out = {}
    local q = self.search and self.search ~= "" and self.search:lower()
    for _, e in ipairs(self:Entries()) do
        local ok = (not self.night or e.sessionId == self.night) and (not self.player or e.player == self.player)
        if ok and q then
            ok = display(e.player):lower():find(q, 1, true) or (Loot.ItemName(e.link) or ""):lower():find(q, 1, true)
        end
        if ok then out[#out + 1] = e end
    end
    return out
end

local function nightName(id)
    local s = id and G().sessions[id]
    return s and (date("%a %m/%d", s.start) .. " " .. s.name) or ""
end

function Loot:CSV()
    local lines = { "Date,Player,Item,Item ID,Boss,Tag,Night" }
    for _, e in ipairs(self:Filtered()) do
        local item = (Loot.ItemName(e.link) or ""):gsub(",", "")
        lines[#lines + 1] = ("%s,%s,%s,%d,%s,%s,%s"):format(date("%Y-%m-%d", e.t), display(e.player), item, e.itemID,
            (e.boss or ""):gsub(",", ""), TAG[e.tag] and TAG[e.tag].short or "", (nightName(e.sessionId):gsub(",", "")))
    end
    return table.concat(lines, "\n")
end

function Loot:DiscordText()
    local title = self.night and nightName(self.night) or "all nights"
    local lines = { ("**Loot, %s**"):format(title) }
    for _, e in ipairs(self:Filtered()) do
        local tag = TAG[e.tag] and TAG[e.tag].short or ""
        lines[#lines + 1] = ("%s: %s (%s)%s"):format(display(e.player), Loot.ItemName(e.link), tag,
            e.boss and (", " .. e.boss) or "")
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local COLS = {
    { key = "date",   label = "Date",   x = 8,   w = 70 },
    { key = "player", label = "Player", x = 84,  w = 106 },
    { key = "item",   label = "Item",   x = 196, w = 238 },
    { key = "boss",   label = "Boss",   x = 440, w = 110 },
    { key = "tag",    label = "Tag",    x = -10, w = 40, right = true },
}

local function place(fs, parent, col)
    fs:ClearAllPoints()
    fs:SetWidth(col.w)
    if col.right then
        fs:SetPoint("RIGHT", parent, "RIGHT", col.x, 0)
        fs:SetJustifyH("RIGHT")
    else
        fs:SetPoint("LEFT", parent, "LEFT", col.x, 0)
        fs:SetJustifyH("LEFT")
    end
end

function Loot:Build(page)
    self.page = page

    -- Row 1
    local search = UI.EditBox(page, LEFT_W, BAR_H)
    search:SetPoint("TOPLEFT", PAD, -ROW1_Y)
    search.placeholder = UI.Text(search, 11)
    search.placeholder:SetPoint("LEFT", 8, 0)
    search.placeholder:SetTextColor(0.45, 0.45, 0.5)
    search.placeholder:SetText("Search players or items")
    search:SetScript("OnTextChanged", function(box)
        self.search = box:GetText()
        search.placeholder:SetShown(self.search == "")
        self.tableOffset = 0
        self:Refresh()
    end)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    self.searchBox = search
    self.nightBtn = UI.Button(page, "All nights", 220, BAR_H, function(b) UI.ShowMenu(b, self:NightMenu()) end)
    UI.DropArrow(self.nightBtn)
    self.nightBtn:SetPoint("TOPLEFT", RX, -ROW1_Y)
    local opts = UI.Button(page, "Options", 92, BAR_H, function(b) UI.ShowMenu(b, self:OptionsMenu()) end)
    UI.DropArrow(opts)
    opts:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -ROW1_Y)

    -- Row 2
    self.status = UI.Text(page, 11)
    self.status:SetPoint("LEFT", page, "TOPLEFT", PAD + 2, -(ROW2_Y + BAR_H / 2))
    self.status:SetTextColor(0.6, 0.6, 0.65)

    -- Players list
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", PAD, -LIST_Y)
    list:SetSize(LEFT_W, LIST_H)
    UI.Card(list)
    self.listHint = UI.ScrollHint(list, 2, 2)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d)
        self.listOffset = (self.listOffset or 0) - d * 3
        self:RefreshPlayers()
    end)
    self.playerRows = {}
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
        row.label = UI.Text(row, 12)
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -40, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(r)
            self.player = r.playerKey
            self.tableOffset = 0
            self:Refresh()
        end)
        self.playerRows[i] = row
    end

    -- Table
    local tbl = CreateFrame("Frame", nil, page)
    tbl:SetPoint("TOPLEFT", RX, -LIST_Y)
    tbl:SetSize(RW, LIST_H)
    UI.Card(tbl)
    self.tableArt = ns.Art and ns.Art.Page("loot", tbl) -- faint game art (Art.PAGES)
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
    for _, col in ipairs(COLS) do
        local fs = UI.SectionTitle(head, col.label, UI.COLUMN_SIZE)
        place(fs, head, col)
    end
    self.rows = {}
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
        for c, col in ipairs(COLS) do
            local fs = UI.Text(row, c == 3 and 12 or 11)
            fs:SetWordWrap(false)
            place(fs, row, col)
            row.cells[col.key] = fs
        end
        row:SetScript("OnClick", function(r) if r.entry then UI.ShowMenu(r, self:EntryMenu(r.entry)) end end)
        row:SetScript("OnEnter", function(r)
            if r.entry and GameTooltip then
                UI.ItemTip(r, r.entry.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        self.rows[i] = row
    end
    self.empty = UI.Text(tbl, 11)
    self.empty:SetPoint("TOP", 0, -ROW_H - 24)
    self.empty:SetTextColor(0.55, 0.55, 0.6)
    self.empty:SetJustifyH("CENTER")

    -- Bottom row
    local add = UI.Button(page, "Add loot", LEFT_W, BAR_H, function() self:PromptAdd() end)
    add:SetPoint("TOPLEFT", PAD, -BOTTOM_Y)
    -- one Export menu (CSV and Discord were two buttons: UI experiment)
    self.exportBtn = UI.Button(page, "Export", 92, BAR_H, function(b)
        UI.ShowMenu(b, {
            { text = "Export", header = true },
            { text = "Copy for Discord", func = function() UI.CopyBox("Loot for Discord", self:DiscordText()) end },
            { text = "Copy as CSV", func = function() UI.CopyBox("Loot (CSV, paste into a spreadsheet)", self:CSV()) end },
        })
    end)
    UI.DropArrow(self.exportBtn)
    self.exportBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -BOTTOM_Y)
end

-- Manual entry: item first (shift-click it in), then who got it.
function Loot:PromptAdd()
    UI.Prompt(self.table, 0, -ROW_H, "Shift-click the item, then Enter", "", function(link)
        if not Loot.ItemID(link) then
            ns.Print("loot: shift-click the item into the box so it is a real item link")
            return
        end
        C_Timer.After(0, function()
            UI.Prompt(self.table, 0, -ROW_H, "Who received " .. (Loot.ItemName(link) or "it") .. "?",
                self.player and display(self.player) or "", function(name)
                    local clean = ns.Codec.CleanText(name, ns.Codec.MAX_NAME)
                    if clean ~= "" then self:AddManual(clean, link) end
                end)
        end)
    end)
end

-- Shift-clicking an item while the prompt has focus puts the link there.
if hooksecurefunc and ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(text)
        local p = UI.promptFrame
        if p and p:IsShown() and p.box:HasFocus() and text then p.box:Insert(text) end
    end)
end

function Loot:EntryMenu(e)
    local menu = { { text = Loot.ItemName(e.link) or "Item", header = true } }
    for _, t in ipairs(Loot.TAGS) do
        menu[#menu + 1] = { text = (e.tag == t.key and "> " or "   ") .. t.label, func = function() self:SetTag(e, t.key) end }
    end
    menu[#menu + 1] = { text = "Give to someone else...", func = function()
        UI.Prompt(self.table, 0, -ROW_H, "Who has it now?", "", function(name)
            local clean = ns.Codec.CleanText(name, ns.Codec.MAX_NAME)
            if clean ~= "" then self:Reassign(e, clean) end
        end)
    end }
    menu[#menu + 1] = { text = "Delete entry", color = { 0.95, 0.4, 0.4 }, func = function() self:Delete(e) end }
    return menu
end

function Loot:NightMenu()
    local menu = { { text = "All nights", color = not self.night and UI.ACCENT or nil,
        func = function() self.night = nil; self:Refresh() end } }
    for i, s in ipairs(ns.Attendance:Sessions()) do
        if i > 18 then break end
        menu[#menu + 1] = { text = date("%a %m/%d", s.start) .. "  " .. s.name,
            color = self.night == s.id and UI.ACCENT or nil,
            func = function() self.night = s.id; self.tableOffset = 0; self:Refresh() end }
    end
    return menu
end

function Loot:OptionsMenu()
    local g = G()
    local menu = { { text = "Record items of at least", header = true } }
    for q = 2, 4 do
        menu[#menu + 1] = { text = ((g.lootMinQuality or 3) == q and "> " or "   ") .. QUALITY_NAMES[q] .. " quality",
            func = function() g.lootMinQuality = q end }
    end
    return menu
end

function Loot:Refresh()
    if not self.page then return end
    local s = ns.Attendance:Active()
    self.status:SetText(s and ("|cff66dd77Recording|r loot for " .. s.name) or "Not recording")
    self.nightBtn:SetLabel(self.night and nightName(self.night) or "All nights")
    local rows = self:Filtered()
    self:RefreshPlayers()
    self:RefreshTable()
end

function Loot:RefreshPlayers()
    -- counts within the current night filter (and search), all players
    local per, order = {}, {}
    local keepPlayer = self.player
    self.player = nil
    local rows = self:Filtered()
    self.player = keepPlayer
    for _, e in ipairs(rows) do
        if not per[e.player] then
            per[e.player] = 0
            order[#order + 1] = e.player
        end
        per[e.player] = per[e.player] + 1
    end
    table.sort(order, function(a, b)
        if per[a] ~= per[b] then return per[a] > per[b] end
        return a < b
    end)
    self.listOffset = math.max(0, math.min(self.listOffset or 0, #order + 1 - self.listVisible))
    self.listHint:Set(self.listOffset, self.listVisible, #order + 1)
    for i, row in ipairs(self.playerRows) do
        local idx = i + self.listOffset
        if idx == 1 then
            row.playerKey = nil
            row.label:SetText("All players")
            row.label:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
            row.sel:SetShown(self.player == nil)
            row:Show()
        elseif order[idx - 1] then
            local k = order[idx - 1]
            row.playerKey = k
            row.label:SetText(display(k))
            row.label:SetTextColor(classColor(k))
            row.sel:SetShown(self.player == k)
            row:Show()
        else
            row.playerKey = nil
            row:Hide()
        end
    end
end

function Loot:RefreshTable()
    local rows = self:Filtered()
    self.tableOffset = math.max(0, math.min(self.tableOffset or 0, #rows - self.tableVisible))
    self.tableHint:Set(self.tableOffset, self.tableVisible, #rows)
    for i, row in ipairs(self.rows) do
        local e = rows[i + self.tableOffset]
        row.entry = e
        if e then
            row.cells.date:SetText(date("%m/%d", e.t))
            row.cells.date:SetTextColor(0.6, 0.6, 0.65)
            row.cells.player:SetText(display(e.player))
            row.cells.player:SetTextColor(classColor(e.player))
            row.cells.item:SetText(e.link)
            row.cells.boss:SetText(e.boss or "")
            row.cells.boss:SetTextColor(0.7, 0.7, 0.75)
            local tag = TAG[e.tag]
            row.cells.tag:SetText(tag and tag.short or "")
            local off = e.tag ~= "ms"
            row.cells.tag:SetTextColor(off and 0.6 or 0.4, off and 0.6 or 0.85, off and 0.65 or 0.45)
            row:Show()
        else
            row:Hide()
        end
    end
    if #rows == 0 then
        local anything = #self:Entries() > 0
        self.empty:SetText(anything and "Nothing matches these filters." or
            "No loot yet.")
    end
    self.empty:SetShown(#rows == 0)
    if self.tableArt then self.tableArt:SetSparse(#rows == 0) end -- an empty card shows its whole picture
end

------------------------------------------------------------------------
-- Events, tab
------------------------------------------------------------------------
ns.On("CHAT_MSG_LOOT", function(msg) Loot:OnChat(msg) end)

-- Personal loot on modern clients: (encounterID, itemID, itemLink, quantity, playerName, className)
ns.On("ENCOUNTER_LOOT_RECEIVED", function(encounterID, _, itemLink, _, playerName)
    local boss
    if encounterID and not secret(encounterID) and EJ_GetEncounterInfo then
        local ok, name = pcall(EJ_GetEncounterInfo, encounterID)
        boss = ok and name or nil
    end
    Loot:Record(playerName, itemLink, "encounter", boss)
end)

-- Group loot rolls: the winner of each drop in the loot history.
ns.On("LOOT_HISTORY_UPDATE_DROP", function(encounterID, lootListID)
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
    local ok, drop = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListID)
    if not ok or type(drop) ~= "table" or not drop.winner then return end
    local boss
    local okE, enc = pcall(C_LootHistory.GetInfoForEncounter, encounterID)
    if okE and type(enc) == "table" then boss = enc.encounterName end
    Loot:Record(drop.winner.playerName, drop.itemHyperlink, "history", boss)
end)

ns.Editor:RegisterTab("loot", "Loot", 3,
    function(page) Loot:Build(page) end,
    function() Loot:Refresh() end, "raid")
