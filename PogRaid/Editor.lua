-- PogRaid editor: build boards on the raid map and show them to the raid.
--
-- Layout (all sizes fixed so the two columns line up exactly):
--   title bar
--   [board name  ]  [tools ................................]
--   [New][Delete ]  [tool options ....................  hint]
--   [board list  ]  [canvas                                ]
--   [Check raid  ]  [Map][Boss][Undo][Clear]   [Close][Show]
local _, ns = ...
local UI, Codec = ns.UI, ns.Codec

local Editor = {}
ns.Editor = Editor

local PAD, GAP, TITLE_H, BAR_H = 12, 8, 30, 26
local LEFT_W, CANVAS_W, CANVAS_H = 170, 696, 464
local RIGHT_X = PAD + LEFT_W + PAD
local TOOLS_Y = TITLE_H
local OPTS_Y = TOOLS_Y + BAR_H + GAP
local CANVAS_Y = OPTS_Y + BAR_H + GAP
local BOTTOM_Y = CANVAS_Y + CANVAS_H + GAP
local FRAME_W = RIGHT_X + CANVAS_W + PAD
local FRAME_H = BOTTOM_Y + BAR_H + PAD
local TOOL_GAP = 4
local TAB_W = 76 -- starting width only: LayoutTabs fits each tab to its label
-- The title and tabs sit on their own band; pages start a little below it.
-- Pages keep their own 902x608 grid and are simply moved down by PAGE_Y.
local BAND_H = 36
local PAGE_Y = BAND_H + 10 - TITLE_H
local SWATCH, SWATCH_GAP = 26, 3
local ROW_H = 22
local UNDO_MAX = 50
local MIN_ARROW_PX, MIN_CIRCLE_PX, MIN_RECT_PX = 12, 8, 4
local SNAP_PX = 10
local PEN_STEP_PX = 3

local TOOLS = {
    { key = "move",   label = "Move" },
    { key = "mark",   label = "Marker" },
    { key = "dot",    label = "Player" },
    { key = "group",  label = "Group" },
    { key = "arrow",  label = "Arrow" },
    { key = "line",   label = "Line" },
    { key = "pen",    label = "Pen" },
    { key = "rect",   label = "Rect" },
    { key = "circle", label = "Circle" },
    { key = "text",   label = "Text" },
}
local TOOL_W = (CANVAS_W - (#TOOLS - 1) * TOOL_GAP) / #TOOLS

-- Option strips shown for each tool, left to right.
local OPTIONS_FOR = {
    move = {}, mark = { "mark" }, dot = { "dot" }, group = { "group" },
    arrow = { "color" }, line = { "color" }, pen = { "color" }, text = { "color" },
    rect = { "color", "style" }, circle = { "color", "style" },
}

local HINTS = {
    move = "Drag an item to move it. Drag empty space to pan.",
    mark = "Click to place a raid marker.",
    dot = "Pick a player, then click to place them.",
    group = "Click to place a role group.",
    arrow = "Drag to draw an arrow.",
    line = "Drag to draw a wall. Shift: straight. Ends snap together.",
    pen = "Drag to draw freehand.",
    rect = "Drag corner to corner. Shift makes a square.",
    circle = "Drag out from the centre.",
    text = "Click to add a label.",
}

Editor.tool = "move"
Editor.markIcon = 1
Editor.color = 1
Editor.style = 1
Editor.group = "T"
Editor.listOffset = 0
Editor.undo = {}

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function short(name)
    if not name then return nil end
    return Ambiguate and Ambiguate(name, "none") or name
end

local function current()
    return Editor.id and ns.db.boards[Editor.id]
end

local function isDefaultName(name)
    return name == "New board" or name == "First board" or name:match("^Board %d+$") ~= nil
        or name == "New plan" or name == "First plan" or name:match("^Plan %d+$") ~= nil
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function Editor:Build()
    local f = CreateFrame("Frame", "PogRaidEditor", UIParent)
    f:SetSize(FRAME_W, FRAME_H + PAGE_Y)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    UI.Panel(f)
    f:Hide()
    f:SetScript("OnHide", function()
        UI.HideMenu()
        self:StopDrag()
    end)
    tinsert(UISpecialFrames, "PogRaidEditor")
    self.frame = f

    -- Title band with the tabs, which start in line with the right column.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAND_H)
    UI.MakeMovable(f, bar, function() UI.SavePosition(f, "editor") end)
    local band = bar:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("BOTTOMRIGHT", -1, 0)
    band:SetColorTexture(0.095, 0.1, 0.115, 1)
    local divider = bar:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", 1, 0)
    divider:SetPoint("BOTTOMRIGHT", -1, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(UI.BORDER[1], UI.BORDER[2], UI.BORDER[3], 1)
    self.band, self.divider = bar, divider
    local title = UI.Text(bar, 14)
    title:SetPoint("LEFT", PAD, 0)
    title:SetText("Pog Raid")
    local close = UI.Tab(bar, "X", 28, BAND_H, function() f:Hide() end)
    close:SetPoint("RIGHT", -PAD + 7, 0)
    self.closeBtn = close
    table.sort(self.tabs, function(a, b) return a.order < b.order end)
    self.tabButtons = {}
    local list = {}
    for i, tab in ipairs(self.tabs) do
        local b = UI.Tab(bar, tab.label, TAB_W, BAND_H, function() self:ShowTab(tab.key) end)
        self.tabButtons[tab.key] = b
        list[i] = b
    end
    self:LayoutTabs(bar, list)
    UI.RestorePosition(f, "editor", 0)
end

-- The same gap between every pair of tab labels, and between the last one
-- and the X: measured from the labels' own widths, spread from the right
-- column's edge to the close button. Each tab is its label plus half a gap
-- either side, so the whole gap is clickable.
function Editor:LayoutTabs(bar, list)
    local close = self.closeBtn
    local closeCenter = FRAME_W - (PAD - 7) - close:GetWidth() / 2
    local xText = closeCenter - close.label:GetStringWidth() / 2
    local sum = 0
    for _, b in ipairs(list) do sum = sum + b.label:GetStringWidth() end
    local gap = (xText - RIGHT_X - sum) / (#list + 0.5)
    local x = RIGHT_X
    for _, b in ipairs(list) do
        local tw = b.label:GetStringWidth()
        local w = math.floor(tw + gap + 0.5)
        b:SetWidth(w)
        b.underline:SetWidth(math.min(w, tw + 16))
        b:ClearAllPoints()
        -- whole-pixel label centres keep the text crisp
        b:SetPoint("BOTTOM", bar, "BOTTOMLEFT", math.floor(x + (tw + gap) / 2 + 0.5), 0)
        x = x + tw + gap
    end
    self.tabGap = gap
end

-- Tabs: each gets a full-window page under the title bar, built the first
-- time it is shown. Pages use the same PAD/GAP grid as the boards page.
Editor.tabs = {}

-- order: position in the tab row, left to right.
function Editor:RegisterTab(key, label, order, build, onShow)
    table.insert(self.tabs, { key = key, label = label, order = order, build = build, onShow = onShow })
end

function Editor:ShowTab(key)
    if not self.frame then self:Build() end
    local want
    for _, tab in ipairs(self.tabs) do
        if tab.key == key then want = tab end
    end
    want = want or self.tabs[1]
    for _, tab in ipairs(self.tabs) do
        if tab ~= want and tab.page then tab.page:Hide() end
        self.tabButtons[tab.key]:SetSelected(tab == want)
    end
    if not want.page then
        want.page = CreateFrame("Frame", nil, self.frame)
        want.page:SetPoint("TOPLEFT", 0, -PAGE_Y)
        want.page:SetSize(FRAME_W, FRAME_H)
        want.build(want.page)
    end
    want.page:Show()
    self.currentTab = want.key
    ns.db.frames.tab = want.key
    self:StopDrag()
    UI.HideMenu()
    if want.onShow then want.onShow() end
end

function Editor:BuildBoards(page)
    self.page = page
    self:BuildLeft()
    self:BuildTools()

    local canvas = ns.CreateCanvas(page, CANVAS_W, CANVAS_H)
    canvas.frame:SetPoint("TOPLEFT", RIGHT_X, -CANVAS_Y)
    self.canvas = canvas
    self:HookCanvas()

    self:BuildBottom()
    self:SetTool(self.tool)
end

function Editor:OnShowBoards()
    local id = self.id or ns.db.selected
    if not (id and ns.db.boards[id]) then id = ns.db.order[1] end
    self:Select(id)
end

function Editor:BuildLeft()
    local f = self.page

    local name = UI.EditBox(f, LEFT_W, BAR_H)
    name:SetPoint("TOPLEFT", PAD, -TOOLS_Y)
    name:SetScript("OnTextChanged", function(box, userInput)
        if not userInput then return end
        local b = current()
        if not b then return end
        local clean = Codec.CleanText(box:GetText(), Codec.MAX_NAME)
        b.name = clean ~= "" and clean or "Plan"
        self:RefreshList()
    end)
    name:SetScript("OnEnterPressed", name.ClearFocus)
    self.nameBox = name

    local btnW = (LEFT_W - GAP) / 2
    local newBtn = UI.Button(f, "New", btnW, BAR_H, function() self:NewBoard() end)
    newBtn:SetPoint("TOPLEFT", PAD, -OPTS_Y)
    local del = UI.Button(f, "Delete", btnW, BAR_H)
    del:SetScript("OnClick", function(b) UI.ConfirmClick(b, function() self:DeleteCurrent() end) end)
    del:SetPoint("LEFT", newBtn, "RIGHT", GAP, 0)

    local listH = CANVAS_H
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", PAD, -CANVAS_Y)
    list:SetSize(LEFT_W, listH)
    UI.Card(list)
    self.listHint = UI.ScrollHint(list, 2, 2)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        self.listOffset = self.listOffset - delta
        self:RefreshList()
    end)
    self.visibleRows = math.floor((listH - 4) / ROW_H)
    self.rows = {}
    for i = 1, self.visibleRows do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(LEFT_W - 4, ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.18)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        row.label = UI.Text(row, 11)
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(r) if r.id then self:Select(r.id) end end)
        self.rows[i] = row
    end

    local check = UI.Button(f, "Check raid", LEFT_W, BAR_H, function() ns.Comm.CheckRaid() end)
    check:SetPoint("TOPLEFT", PAD, -BOTTOM_Y)
end

function Editor:BuildTools()
    local f = self.page
    self.toolButtons = {}
    for i, tool in ipairs(TOOLS) do
        local b = UI.Button(f, tool.label, TOOL_W, BAR_H, function() self:SetTool(tool.key) end)
        b:SetPoint("TOPLEFT", RIGHT_X + (i - 1) * (TOOL_W + TOOL_GAP), -TOOLS_Y)
        self.toolButtons[tool.key] = b
    end

    -- Option strips live on the row under the tools. SetTool lays out the
    -- ones the current tool uses, left to right.
    local function strip(count, w)
        local o = CreateFrame("Frame", nil, f)
        o:SetSize(count * w + (count - 1) * SWATCH_GAP, BAR_H)
        o:Hide()
        return o
    end
    self.options = {}

    local mark = strip(8, SWATCH)
    self.markButtons = {}
    for i = 1, 8 do
        local b = UI.IconButton(mark, SWATCH, function() self.markIcon = i; self:RefreshOptions() end)
        b:SetPoint("LEFT", (i - 1) * (SWATCH + SWATCH_GAP), 0)
        b.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(b.icon, i)
        self.markButtons[i] = b
    end
    self.options.mark = mark

    local color = strip(#ns.COLORS, SWATCH)
    self.colorButtons = {}
    for i, c in ipairs(ns.COLORS) do
        local b = UI.IconButton(color, SWATCH, function() self.color = i; self:RefreshOptions() end)
        b:SetPoint("LEFT", (i - 1) * (SWATCH + SWATCH_GAP), 0)
        b.icon:SetColorTexture(c[1], c[2], c[3], 1)
        self.colorButtons[i] = b
    end
    self.options.color = color

    -- Style swatches preview the fill in the current colour.
    local style = strip(#ns.STYLES, SWATCH)
    self.styleButtons = {}
    for i = 1, #ns.STYLES do
        local b = UI.IconButton(style, SWATCH, function() self.style = i; self:RefreshOptions() end)
        b:SetPoint("LEFT", (i - 1) * (SWATCH + SWATCH_GAP), 0)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("TOPLEFT", 6, -6)
        b.icon:SetPoint("BOTTOMRIGHT", -6, 6)
        b.frameEdge = CreateFrame("Frame", nil, b)
        b.frameEdge:SetPoint("TOPLEFT", 6, -6)
        b.frameEdge:SetPoint("BOTTOMRIGHT", -6, 6)
        UI.Border(b.frameEdge, { 1, 1, 1, 1 }, "OVERLAY")
        self.styleButtons[i] = b
    end
    self.options.style = style

    local group = strip(4, 80)
    self.groupButtons = {}
    for i, key in ipairs(ns.GROUP_ORDER) do
        local b = UI.Button(group, ns.GROUPS[key].label, 80, BAR_H, function() self.group = key; self:RefreshOptions() end)
        b:SetPoint("LEFT", (i - 1) * (80 + SWATCH_GAP), 0)
        self.groupButtons[key] = b
    end
    self.options.group = group

    local dot = strip(1, 200)
    self.dotBtn = UI.Button(dot, "Pick a player...", 200, BAR_H, function(b) UI.ShowMenu(b, self:RosterEntries()) end)
    self.dotBtn:SetPoint("LEFT")
    self.options.dot = dot

    self.hint = UI.Text(f, 11)
    self.hint:SetPoint("RIGHT", f, "TOPLEFT", RIGHT_X + CANVAS_W, -(OPTS_Y + BAR_H / 2))
    self.hint:SetJustifyH("RIGHT")
    self.hint:SetTextColor(0.55, 0.55, 0.6)
end

function Editor:BuildBottom()
    local f = self.page
    self.mapBtn = UI.Button(f, "Map", 200, BAR_H, function(b) self:MapMenu(b) end)
    self.mapBtn:SetPoint("TOPLEFT", RIGHT_X, -BOTTOM_Y)
    local boss = UI.Button(f, "Zoom to boss", 110, BAR_H, function(b) self:BossMenu(b) end)
    boss:SetPoint("LEFT", self.mapBtn, "RIGHT", TOOL_GAP, 0)
    local undo = UI.Button(f, "Undo", 54, BAR_H, function() self:Undo() end)
    undo:SetPoint("LEFT", boss, "RIGHT", TOOL_GAP, 0)
    local clear = UI.Button(f, "Clear", 54, BAR_H)
    clear:SetScript("OnClick", function(b) UI.ConfirmClick(b, function() self:ClearItems() end) end)
    clear:SetPoint("LEFT", undo, "RIGHT", TOOL_GAP, 0)

    local show = UI.Button(f, "Show to raid", 110, BAR_H, function() self:SendCurrent() end)
    show:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -BOTTOM_Y)
    show:SetPrimary()
    local closeRaid = UI.Button(f, "Close on raid", 104, BAR_H, function()
        ns.Comm.SendClose()
        ns.Print("closing the board on everyone's screen")
    end)
    closeRaid:SetPoint("RIGHT", show, "LEFT", -TOOL_GAP, 0)
end

------------------------------------------------------------------------
-- Tools and options
------------------------------------------------------------------------
function Editor:SetTool(key)
    self.tool = key
    for k, b in pairs(self.toolButtons) do b:SetSelected(k == key) end
    for _, o in pairs(self.options) do o:Hide() end
    local x = RIGHT_X
    for _, name in ipairs(OPTIONS_FOR[key]) do
        local o = self.options[name]
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", self.page, "TOPLEFT", x, -OPTS_Y)
        o:Show()
        x = x + o:GetWidth() + 16
    end
    self.hint:SetText(HINTS[key])
    self:RefreshOptions()
end

function Editor:RefreshOptions()
    for i, b in ipairs(self.markButtons) do b:SetSelected(i == self.markIcon) end
    for i, b in ipairs(self.colorButtons) do b:SetSelected(i == self.color) end
    for k, b in pairs(self.groupButtons) do b:SetSelected(k == self.group) end
    local c = ns.COLORS[self.color]
    for i, b in ipairs(self.styleButtons) do
        b:SetSelected(i == self.style)
        b.icon:SetColorTexture(c[1], c[2], c[3], ns.STYLES[i].fill or 0)
        UI.SetBorderColor(b.frameEdge, c)
    end
end

function Editor:RosterEntries()
    local list = {}
    local function add(name, class)
        name = short(name)
        if not name or name == "" then return end
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        list[#list + 1] = {
            text = name,
            color = c and { c.r, c.g, c.b } or nil,
            func = function() self:SetDotPlayer(name, class) end,
        }
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            add(name, class)
        end
    else
        add(ns.PlayerName(), select(2, UnitClass("player")))
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            add(GetUnitName(unit, true), select(2, UnitClass(unit)))
        end
    end
    table.sort(list, function(a, b) return a.text < b.text end)
    list[#list + 1] = {
        text = "Type a name...",
        color = { 0.6, 0.6, 0.65 },
        func = function()
            UI.Prompt(self.options.dot, 0, -BAR_H - 2, "Player name", "", function(text)
                local clean = Codec.CleanText(text, Codec.MAX_NAME)
                if clean ~= "" then self:SetDotPlayer(clean, nil) end
            end)
        end,
    }
    return list
end

function Editor:SetDotPlayer(name, class)
    self.dotName, self.dotClass = name, class
    self.dotBtn:SetLabel(name)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then self.dotBtn.label:SetTextColor(c.r, c.g, c.b) else self.dotBtn.label:SetTextColor(0.92, 0.92, 0.94) end
end

------------------------------------------------------------------------
-- Boards
------------------------------------------------------------------------
function Editor:Select(id)
    local b = ns.db.boards[id]
    if not b then return end
    self.id = id
    ns.db.selected = id
    self.undo = {}
    self.nameBox:SetText(b.name)
    self.nameBox:ClearFocus()
    local c = self.canvas
    c:SetHighlight(nil, nil)
    c.items = b.items
    c.preview = nil
    c:SetMap(b.map)
    c:SetView(b.zoom, b.cx, b.cy)
    self:RefreshMapButton()

    for i, oid in ipairs(ns.db.order) do
        if oid == id then
            if i <= self.listOffset then self.listOffset = i - 1 end
            if i > self.listOffset + self.visibleRows then self.listOffset = i - self.visibleRows end
        end
    end
    self:RefreshList()
end

function Editor:RefreshList()
    local order = ns.db.order
    self.listOffset = clamp(self.listOffset, 0, math.max(0, #order - self.visibleRows))
    self.listHint:Set(self.listOffset, self.visibleRows, #order)
    for i, row in ipairs(self.rows) do
        local id = order[i + self.listOffset]
        local b = id and ns.db.boards[id]
        if b then
            row.id = id
            row.label:SetText(b.name)
            row.sel:SetShown(id == self.id)
            row:Show()
        else
            row.id = nil
            row:Hide()
        end
    end
end

function Editor:NewBoard()
    local cur = current()
    local b = ns.NewBoard("Plan " .. (#ns.db.order + 1))
    b.map = (cur and cur.map) or C_Map.GetBestMapForUnit("player")
    self:Select(ns.AddBoard(b))
    self.nameBox:SetFocus()
    self.nameBox:HighlightText()
end

function Editor:DeleteCurrent()
    local order = ns.db.order
    local idx = 1
    for i, id in ipairs(order) do if id == self.id then idx = i end end
    ns.DeleteBoard(self.id)
    if #order == 0 then ns.AddBoard(ns.NewBoard("First plan")) end
    self:Select(order[math.min(idx, #order)])
end

------------------------------------------------------------------------
-- Map and boss pickers
------------------------------------------------------------------------
local function mapName(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and info.name or (id and ("Map " .. id)) or "Blank"
end

function Editor:RefreshMapButton()
    self.mapBtn:SetLabel("Map: " .. mapName(current() and current().map))
end

function Editor:SetMap(id)
    local b = current()
    if not b then return end
    b.map = id
    b.zoom, b.cx, b.cy = 1, 0.5, 0.5
    self.canvas:SetMap(id)
    self.canvas:SetView(1, 0.5, 0.5)
    self:RefreshMapButton()
end

function Editor:MapMenu(btn)
    local b = current()
    local entries = {}
    local here = C_Map.GetBestMapForUnit("player")
    if here then
        entries[#entries + 1] = { text = "My current map: " .. mapName(here), func = function() self:SetMap(here) end }
    end
    local base = (b and b.map) or here
    local ok, groupID = pcall(C_Map.GetMapGroupID, base)
    local floors = ok and groupID and C_Map.GetMapGroupMembersInfo(groupID)
    if floors and #floors > 0 then
        entries[#entries + 1] = { text = "Floors", header = true }
        for _, floor in ipairs(floors) do
            local fid = floor.mapID
            entries[#entries + 1] = {
                text = "   " .. (floor.name or mapName(fid)),
                color = (b and b.map == fid) and UI.ACCENT or nil,
                func = function() self:SetMap(fid) end,
            }
        end
    end
    entries[#entries + 1] = { text = "Blank board (no map)", func = function() self:SetMap(nil) end }
    entries[#entries + 1] = {
        text = "Enter a map ID...",
        func = function()
            UI.Prompt(self.canvas.frame, 10, -10, "Map ID", b and b.map and tostring(b.map) or "", function(text)
                local id = tonumber(text)
                if id and C_Map.GetMapInfo(id) then
                    self:SetMap(id)
                else
                    ns.Print("no map with ID " .. tostring(text))
                end
            end)
        end,
    }
    UI.ShowMenu(btn, entries)
end

function Editor:BossMenu(btn)
    local b = current()
    local entries = {}
    if b and b.map then
        local ok, list = pcall(C_EncounterJournal.GetEncountersOnMap, b.map)
        if ok and list then
            for _, e in ipairs(list) do
                local name = EJ_GetEncounterInfo(e.encounterID) or ("Encounter " .. e.encounterID)
                entries[#entries + 1] = { text = name, func = function() self:FocusBoss(name, e.mapX, e.mapY) end }
            end
        end
    end
    if #entries == 0 then
        entries[1] = { text = "No bosses listed on this map", disabled = true }
    end
    UI.ShowMenu(btn, entries)
end

function Editor:FocusBoss(name, x, y)
    local b = current()
    self.canvas:SetView(2.5, x, y)
    self:SaveView()
    if isDefaultName(b.name) then
        b.name = Codec.CleanText(name, Codec.MAX_NAME)
        self.nameBox:SetText(b.name)
        self:RefreshList()
    end
end

------------------------------------------------------------------------
-- Editing
------------------------------------------------------------------------
function Editor:SaveView()
    local b = current()
    if b then b.zoom, b.cx, b.cy = self.canvas:GetView() end
end

function Editor:PushUndo()
    local b = current()
    self.undo[#self.undo + 1] = Codec.CopyItems(b.items)
    if #self.undo > UNDO_MAX then table.remove(self.undo, 1) end
end

function Editor:Undo()
    local b = current()
    local prev = table.remove(self.undo)
    if not b or not prev then return end
    b.items = prev
    self.canvas:SetItems(b.items)
end

function Editor:ClearItems()
    local b = current()
    if not b or #b.items == 0 then return end
    self:PushUndo()
    b.items = {}
    self.canvas:SetItems(b.items)
end

function Editor:AddItem(it)
    local b = current()
    if #b.items >= Codec.MAX_ITEMS then
        ns.Print(("a raid plan holds up to %d items"):format(Codec.MAX_ITEMS))
        self.canvas:SetItems(b.items)
        return
    end
    self:PushUndo()
    b.items[#b.items + 1] = it
    self.canvas:SetItems(b.items)
end

local function moveItem(it, dx, dy)
    if it.t == "pen" then
        local p = it.pts
        local minX, maxX, minY, maxY = 1, 0, 1, 0
        for i = 1, #p, 2 do
            minX, maxX = math.min(minX, p[i]), math.max(maxX, p[i])
            minY, maxY = math.min(minY, p[i + 1]), math.max(maxY, p[i + 1])
        end
        dx, dy = clamp(dx, -minX, 1 - maxX), clamp(dy, -minY, 1 - maxY)
        for i = 1, #p, 2 do
            p[i], p[i + 1] = p[i] + dx, p[i + 1] + dy
        end
    elseif it.x1 then -- arrow, line, rect: two corner points, keep the shape
        dx = clamp(dx, -math.min(it.x1, it.x2), 1 - math.max(it.x1, it.x2))
        dy = clamp(dy, -math.min(it.y1, it.y2), 1 - math.max(it.y1, it.y2))
        it.x1, it.x2 = it.x1 + dx, it.x2 + dx
        it.y1, it.y2 = it.y1 + dy, it.y2 + dy
    else
        it.x = clamp(it.x + dx, 0, 1)
        it.y = clamp(it.y + dy, 0, 1)
    end
end

local function clampedCursor(c)
    local nx, ny = c:CursorToMap()
    return clamp(nx, 0, 1), clamp(ny, 0, 1)
end

local function isShift()
    return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

-- Douglas-Peucker in screen pixels: drops pen points that sit within `tol`
-- pixels of the line between their neighbours.
local function simplify(c, pts, tol)
    local n = #pts / 2
    if n <= 2 then return pts end
    local function at(i) return pts[2 * i - 1] * c.mw, pts[2 * i] * c.mh end
    local keep = { [1] = true, [n] = true }
    local stack = { { 1, n } }
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, z = seg[1], seg[2]
        local ax, ay = at(a)
        local zx, zy = at(z)
        local worst, idx = 0, nil
        for i = a + 1, z - 1 do
            local x, y = at(i)
            local d = ns.SegDist(x, y, ax, ay, zx, zy)
            if d > worst then worst, idx = d, i end
        end
        if idx and worst > tol then
            keep[idx] = true
            stack[#stack + 1] = { a, idx }
            stack[#stack + 1] = { idx, z }
        end
    end
    local out = {}
    for i = 1, n do
        if keep[i] then out[#out + 1], out[#out + 2] = pts[2 * i - 1], pts[2 * i] end
    end
    return out
end

-- End point locked to the nearest 45 degrees (measured on screen).
function Editor:Straighten(x1, y1, x2, y2)
    local c = self.canvas
    local dx, dy = (x2 - x1) * c.mw, (y2 - y1) * c.mh
    local len = math.sqrt(dx * dx + dy * dy)
    local step = math.pi / 4
    local a = math.floor(math.atan2(dy, dx) / step + 0.5) * step
    local ex, ey = math.cos(a), math.sin(a)
    if math.abs(ex) < 1e-9 then ex = 0 end
    if math.abs(ey) < 1e-9 then ey = 0 end
    return clamp(x1 + len * ex / c.mw, 0, 1), clamp(y1 + len * ey / c.mh, 0, 1)
end

-- The shape a drag would make if released now. Returns the item, whether
-- it is big enough to keep, and a snap point to mark (lines only).
function Editor:DragShape(d)
    local c = self.canvas
    local nx, ny = clampedCursor(c)
    if d.kind == "arrow" then
        return { t = "arrow", c = self.color, x1 = d.x1, y1 = d.y1, x2 = nx, y2 = ny },
            c:PixelDistance(d.x1, d.y1, nx, ny) >= MIN_ARROW_PX
    elseif d.kind == "line" then
        local snap
        if isShift() then
            nx, ny = self:Straighten(d.x1, d.y1, nx, ny)
        else
            local sx, sy = c:SnapPoint(nx, ny, SNAP_PX)
            if sx then nx, ny, snap = sx, sy, { x = sx, y = sy } end
        end
        return { t = "line", c = self.color, x1 = d.x1, y1 = d.y1, x2 = nx, y2 = ny },
            c:PixelDistance(d.x1, d.y1, nx, ny) >= MIN_ARROW_PX, snap
    elseif d.kind == "rect" then
        if isShift() then
            local dx, dy = (nx - d.x) * c.mw, (ny - d.y) * c.mh
            local side = math.max(math.abs(dx), math.abs(dy))
            nx = clamp(d.x + (dx < 0 and -side or side) / c.mw, 0, 1)
            ny = clamp(d.y + (dy < 0 and -side or side) / c.mh, 0, 1)
        end
        local it = { t = "rect", c = self.color, s = self.style,
            x1 = math.min(d.x, nx), y1 = math.min(d.y, ny), x2 = math.max(d.x, nx), y2 = math.max(d.y, ny) }
        return it, (it.x2 - it.x1) * c.mw >= MIN_RECT_PX and (it.y2 - it.y1) * c.mh >= MIN_RECT_PX
    elseif d.kind == "circle" then
        local px = c:PixelDistance(d.x, d.y, nx, ny)
        return { t = "circle", c = self.color, s = self.style, x = d.x, y = d.y, r = px / c.mw }, px >= MIN_CIRCLE_PX
    elseif d.kind == "pen" then
        return { t = "pen", c = self.color, pts = d.pts }, #d.pts >= 4 and d.len >= MIN_ARROW_PX
    end
end

-- Pen: add the cursor as a point once it has moved far enough.
function Editor:PenPoint(d, force)
    local c = self.canvas
    local nx, ny = clampedCursor(c)
    local p = d.pts
    local dist = c:PixelDistance(p[#p - 1], p[#p], nx, ny)
    if dist >= PEN_STEP_PX or (force and dist > 0) then
        p[#p + 1], p[#p + 2] = nx, ny
        d.len = d.len + dist
    end
end

function Editor:HookCanvas()
    local c = self.canvas
    local cf = c.frame
    cf:EnableMouse(true)
    cf:EnableMouseWheel(true)
    cf:SetScript("OnMouseWheel", function(_, delta)
        c:ZoomAt(delta, c:CursorToMap())
        self:SaveView()
    end)
    cf:SetScript("OnMouseDown", function(_, button) self:MouseDown(button) end)
    cf:SetScript("OnMouseUp", function(_, button) self:MouseUp(button) end)
end

function Editor:StartDrag(d)
    self.drag = d
    self.frame:SetScript("OnUpdate", function() self:DragUpdate() end)
end

function Editor:StopDrag()
    self.drag = nil
    if self.frame then self.frame:SetScript("OnUpdate", nil) end
end

function Editor:MouseDown(button)
    UI.HideMenu()
    local b = current()
    if not b or self.drag then return end
    local c = self.canvas
    local nx, ny = c:CursorToMap()
    local inside = nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1

    if button == "RightButton" then
        local hit = c:HitTest(nx, ny)
        if hit then
            self:PushUndo()
            table.remove(b.items, hit)
            c:SetItems(b.items)
        else
            local x, y = c:CursorUI()
            self:StartDrag({ kind = "pan", button = button, x = x, y = y })
        end
        return
    end
    if button ~= "LeftButton" then return end

    local tool = self.tool
    if tool == "move" then
        local hit = c:HitTest(nx, ny)
        if hit then
            self:StartDrag({ kind = "move", button = button, index = hit, lx = nx, ly = ny })
        else
            local x, y = c:CursorUI()
            self:StartDrag({ kind = "pan", button = button, x = x, y = y })
        end
        return
    end
    if not inside then return end

    if tool == "mark" then
        self:AddItem({ t = "mark", i = self.markIcon, x = nx, y = ny })
    elseif tool == "dot" then
        if not self.dotName then
            UI.ShowMenu(self.dotBtn, self:RosterEntries())
            return
        end
        self:AddItem({ t = "dot", name = self.dotName, class = self.dotClass, x = nx, y = ny })
    elseif tool == "group" then
        self:AddItem({ t = "group", g = self.group, x = nx, y = ny })
    elseif tool == "arrow" then
        self:StartDrag({ kind = "arrow", button = button, x1 = nx, y1 = ny })
    elseif tool == "line" then
        local sx, sy = c:SnapPoint(nx, ny, SNAP_PX)
        self:StartDrag({ kind = "line", button = button, x1 = sx or nx, y1 = sy or ny })
    elseif tool == "rect" then
        self:StartDrag({ kind = "rect", button = button, x = nx, y = ny })
    elseif tool == "circle" then
        self:StartDrag({ kind = "circle", button = button, x = nx, y = ny })
    elseif tool == "pen" then
        self:StartDrag({ kind = "pen", button = button, pts = { nx, ny }, len = 0 })
    elseif tool == "text" then
        local x, y = c:CursorUI()
        local ox = clamp(x - (c.frame:GetLeft() or 0), 0, CANVAS_W - 220)
        local oy = clamp(y - c.frame:GetTop() - 12, -(CANVAS_H - 52), 0)
        UI.Prompt(c.frame, ox, oy, "Label text", "", function(text)
            local clean = Codec.CleanText(text, Codec.MAX_TEXT)
            if clean ~= "" then self:AddItem({ t = "text", c = self.color, s = clean, x = nx, y = ny }) end
        end)
    end
end

function Editor:DragUpdate()
    local d = self.drag
    if not d then return end
    if IsMouseButtonDown and not IsMouseButtonDown(d.button) then
        self:MouseUp(d.button)
        return
    end
    local c, b = self.canvas, current()
    if d.kind == "pan" then
        local x, y = c:CursorUI()
        if x ~= d.x or y ~= d.y then
            c:Pan(x - d.x, y - d.y)
            d.x, d.y = x, y
        end
    elseif d.kind == "move" then
        local nx, ny = clampedCursor(c)
        local dx, dy = nx - d.lx, ny - d.ly
        if dx == 0 and dy == 0 then return end
        if not d.moved then
            self:PushUndo()
            d.moved = true
        end
        local it = b.items[d.index]
        if it then moveItem(it, dx, dy) end
        d.lx, d.ly = nx, ny
        c:Render()
    else
        if d.kind == "pen" then self:PenPoint(d) end
        local it, _, snap = self:DragShape(d)
        c:SetItems(b.items, it, snap)
    end
end

function Editor:MouseUp(button)
    local d = self.drag
    if not d or d.button ~= button then return end
    self:StopDrag()
    local c, b = self.canvas, current()
    if d.kind == "pan" then
        self:SaveView()
    elseif d.kind ~= "move" then
        if d.kind == "pen" then self:PenPoint(d, true) end
        local it, ok = self:DragShape(d)
        if ok and it.t == "pen" then
            local raw, tol = it.pts, 1.5
            it.pts = simplify(c, raw, tol)
            -- Raising the tolerance always gets there (two points at worst);
            -- the counter is a backstop so a bug can never hang the client.
            local tries = 0
            while #it.pts / 2 > Codec.MAX_PEN and tries < 40 do
                tries = tries + 1
                tol = tol * 1.5
                it.pts = simplify(c, raw, tol)
            end
        end
        if ok then
            self:AddItem(it)
        else
            c:SetItems(b.items)
        end
    end
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
function Editor:SendCurrent(selfTest)
    if not ns.db then return end
    local b = current() or ns.db.boards[ns.db.selected or ns.db.order[1]]
    if not b then return end
    local channel, target
    if selfTest then channel, target = "WHISPER", ns.PlayerName() end
    local ok, used, parts = ns.Comm.SendBoard(b, channel, target)
    if not ok then return end
    if used == "WHISPER" then
        ns.Print(("showing '%s' to yourself (solo test, %d part%s)"):format(b.name, parts, parts == 1 and "" or "s"))
    else
        ns.Print(("showing '%s' to the %s (%d part%s)"):format(b.name, (used:lower():gsub("_", " ")), parts, parts == 1 and "" or "s"))
        if parts > 8 then
            ns.Print("big plan: the game paces addon messages, so it may take a few seconds to arrive")
        end
        if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            ns.Print("|cffff8040you are not leader or assistant, so other players will ignore this plan|r")
        end
    end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
-- Toggle the window; with a tab key, open (or switch) to that tab.
-- Toggle the window on a tab (the first tab, Home, when none is given).
-- Asking for the tab already showing closes the window.
function Editor:Toggle(tab)
    if not self.frame then self:Build() end
    tab = tab or self.tabs[1].key
    if self.frame:IsShown() and tab == self.currentTab then
        self.frame:Hide()
        return
    end
    self.frame:Show()
    self:ShowTab(tab)
end

Editor:RegisterTab("boards", "Raid Plans", 9,
    function(page) Editor:BuildBoards(page) end,
    function() Editor:OnShowBoards() end)

function Editor:ResetPosition()
    if self.frame then UI.RestorePosition(self.frame, "editor", 0) end
end
