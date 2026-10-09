-- Pog Raid games: Gem Cutter, 2048 with gems. Slide the board; two of the
-- same gem merge into the next gem up. Rough Stone -> ... -> Large Opal
-- (the 2048 tile) -> ... -> Black Diamond.
local _, ns = ...
local UI = ns.UI

local Gems = {}
ns.Gems = Gems

Gems.SIZE = 4
Gems.WIN_TIER = 11          -- Large Opal, the "2048" gem

-- tier -> real gem item (icon from the game) and a name
Gems.TIERS = {
    { 2835, "Rough Stone" }, { 774, "Malachite" }, { 818, "Tigerseye" }, { 1210, "Shadowgem" },
    { 1206, "Moss Agate" }, { 1705, "Lesser Moonstone" }, { 1529, "Jade" }, { 3864, "Citrine" },
    { 7909, "Aquamarine" }, { 7910, "Star Ruby" }, { 12799, "Large Opal" }, { 12364, "Huge Emerald" },
    { 12800, "Azerothian Diamond" }, { 12363, "Arcane Crystal" }, { 11754, "Black Diamond" },
}
-- border colour climbs the rarity ladder as gems get bigger
local RARITY = {
    { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0, 0.44, 0.87 },
    { 0.64, 0.21, 0.93 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 }, { 1, 0.5, 0 }, { 0.9, 0.8, 0.5 },
}
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Gem_Emerald_01"

function Gems.Rarity(tier)
    return RARITY[math.min(tier, #RARITY)]
end

function Gems.Name(tier)
    local t = Gems.TIERS[tier]
    return t and t[2] or ("Gem " .. tier)
end

function Gems.Icon(tier)
    local t = Gems.TIERS[math.min(tier, #Gems.TIERS)]
    if t and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, t[1])
        if ok and icon then return icon end
    end
    return FALLBACK_ICON
end

------------------------------------------------------------------------
-- Rules (no UI). cells[1..16] hold tiers, 0 = empty; row by row.
------------------------------------------------------------------------
local Board = {}
Board.__index = Board
Gems.Board = Board

function Board.New(cells, score)
    local b = setmetatable({ cells = {}, score = score or 0 }, Board)
    for i = 1, Gems.SIZE * Gems.SIZE do b.cells[i] = cells and cells[i] or 0 end
    return b
end

-- Slide one line toward its start: merge equal neighbours once each.
-- Returns the new line, points gained, and whether anything moved.
function Gems.SlideLine(line)
    local tiles = {}
    for _, v in ipairs(line) do
        if v > 0 then tiles[#tiles + 1] = v end
    end
    local out, gained, i = {}, 0, 1
    while i <= #tiles do
        if tiles[i + 1] and tiles[i + 1] == tiles[i] then
            local merged = tiles[i] + 1
            out[#out + 1] = merged
            gained = gained + 2 ^ merged
            i = i + 2
        else
            out[#out + 1] = tiles[i]
            i = i + 1
        end
    end
    for k = #out + 1, #line do out[k] = 0 end
    local moved = false
    for k = 1, #line do
        if out[k] ~= line[k] then moved = true end
    end
    return out, gained, moved
end

-- indexes of each line, in slide order, for a direction
local function lines(dir)
    local n, out = Gems.SIZE, {}
    for a = 1, n do
        local l = {}
        for b = 1, n do
            local r, c
            if dir == "left" then r, c = a, b
            elseif dir == "right" then r, c = a, n + 1 - b
            elseif dir == "up" then r, c = b, a
            else r, c = n + 1 - b, a end
            l[b] = (r - 1) * n + c
        end
        out[a] = l
    end
    return out
end

-- Returns true if the board changed (a new gem should then appear).
function Board:Move(dir)
    local moved = false
    for _, idx in ipairs(lines(dir)) do
        local line = {}
        for k, i in ipairs(idx) do line[k] = self.cells[i] end
        local out, gained, m = Gems.SlideLine(line)
        if m then
            moved = true
            for k, i in ipairs(idx) do self.cells[i] = out[k] end
            self.score = self.score + gained
        end
    end
    return moved
end

function Board:Empty()
    local out = {}
    for i, v in ipairs(self.cells) do
        if v == 0 then out[#out + 1] = i end
    end
    return out
end

-- A new rough gem: Rough Stone nine times in ten, Malachite otherwise.
function Board:Spawn()
    local empty = self:Empty()
    if #empty == 0 then return nil end
    local i = empty[math.random(1, #empty)]
    self.cells[i] = (math.random() < 0.9) and 1 or 2
    return i
end

function Board:CanMove()
    if #self:Empty() > 0 then return true end
    local n = Gems.SIZE
    for r = 1, n do
        for c = 1, n do
            local v = self.cells[(r - 1) * n + c]
            if c < n and self.cells[(r - 1) * n + c + 1] == v then return true end
            if r < n and self.cells[r * n + c] == v then return true end
        end
    end
    return false
end

function Board:Best()
    local best = 0
    for _, v in ipairs(self.cells) do best = math.max(best, v) end
    return best
end

------------------------------------------------------------------------
-- Guild leaderboard: one record per player with their best score.
------------------------------------------------------------------------
ns.Sync:Register({
    name = "gems", code = "e", order = 4,
    fields = { "best", "tier" },
    numeric = { best = true, tier = true },
    valid = function(rec)
        return rec.by == rec.author and rec.id == rec.author and rec.best ~= nil and rec.best >= 0 and rec.best < 1e8
            and rec.tier ~= nil and rec.tier >= 1 and rec.tier <= 20
    end,
    onChange = function() Gems:RefreshBoard() end,
})

local function G()
    ns.db.games = ns.db.games or { best = {} }
    ns.db.games.gems = ns.db.games.gems or { best = 0, bestTier = 0 }
    return ns.db.games.gems
end

function Gems:Publish()
    local g = G()
    if g.best <= 0 or not ns.Sync:GuildName() then return end
    local me = ns.Sync:Me()
    local cur = (ns.Sync:Store("gems") or {})[me]
    if cur and not cur.deleted and cur.best >= g.best and (cur.tier or 0) >= g.bestTier then return end
    ns.Sync:Write("gems", { id = me, author = me, t = ns.Now(), best = g.best, tier = math.max(g.bestTier, 1) })
end

function Gems:Leaderboard()
    local out = {}
    for _, rec in pairs(ns.Sync:Store("gems") or {}) do
        if not rec.deleted then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b)
        if a.best ~= b.best then return a.best > b.best end
        return a.author < b.author
    end)
    return out
end

------------------------------------------------------------------------
-- Play
------------------------------------------------------------------------
function Gems:NewGame()
    self:Record()
    self.board = Board.New()
    self.board:Spawn()
    self.board:Spawn()
    self.over, self.announcedWin = nil, nil
    self:Save()
    self:Refresh()
end

-- Keep the best score / gem, and share it.
function Gems:Record()
    local b = self.board
    if not b then return end
    local g = G()
    local changed = false
    if b.score > g.best then g.best, changed = b.score, true end
    if b:Best() > g.bestTier then g.bestTier, changed = b:Best(), true end
    if changed then self:Publish() end
end

function Gems:Save()
    local b = self.board
    G().current = b and { cells = { unpack(b.cells) }, score = b.score, over = self.over } or nil
end

function Gems:Load()
    local cur = G().current
    if cur and cur.cells then
        self.board = Board.New(cur.cells, cur.score)
        self.over = cur.over
        self.announcedWin = self.board:Best() >= Gems.WIN_TIER
    else
        self.board = nil
    end
end

function Gems:Move(dir)
    if not self.board or self.over then return end
    if not self.board:Move(dir) then return end
    self.board:Spawn()
    if self.board:Best() >= Gems.WIN_TIER and not self.announcedWin then
        self.announcedWin = true
        self.message = "|cffff9933You cut a Large Opal!|r Keep going for the diamonds."
        ns.Sound("UI_EPICLOOT_TOAST")
    end
    if not self.board:CanMove() then
        self.over = true
        self.message = ("No moves left. Final score %d."):format(self.board.score)
    end
    self:Record()
    self:Save()
    self:Refresh()
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local PAD, GAP = 12, 8
local TILE, TILE_GAP = 92, 8
local BOARD_W = Gems.SIZE * TILE + (Gems.SIZE + 1) * TILE_GAP
local SIDE_X = PAD + BOARD_W + PAD
local SIDE_W = 902 - SIDE_X - PAD
local ROW_H = 22
local KEYS = { UP = "up", DOWN = "down", LEFT = "left", RIGHT = "right", W = "up", S = "down", A = "left", D = "right" }

function Gems:Build(view, top, height)
    self.view = view
    local board = CreateFrame("Button", nil, view)
    board:SetPoint("TOPLEFT", PAD, -top)
    board:SetSize(BOARD_W, BOARD_W)
    UI.Card(board, { 0.035, 0.035, 0.04, 1 })
    board:RegisterForClicks("LeftButtonUp")
    -- keys only while the mouse is over the board, so movement keys still work otherwise
    board:SetScript("OnEnter", function(f)
        if not InCombatLockdown() then f:EnableKeyboard(true) end
    end)
    board:SetScript("OnLeave", function(f)
        if not InCombatLockdown() then f:EnableKeyboard(false) end
    end)
    board:SetScript("OnKeyDown", function(f, key)
        local dir = KEYS[key]
        if not InCombatLockdown() then f:SetPropagateKeyboardInput(dir == nil) end
        if dir then self:Move(dir) end
    end)
    -- mouse drag: the longer axis of the drag is the direction
    board:SetScript("OnMouseDown", function()
        self.dragFrom = { GetCursorPosition() }
    end)
    board:SetScript("OnMouseUp", function()
        local from = self.dragFrom
        self.dragFrom = nil
        if not from then return end
        local x, y = GetCursorPosition()
        local dx, dy = x - from[1], y - from[2]
        if math.max(math.abs(dx), math.abs(dy)) < 30 then return end
        if math.abs(dx) > math.abs(dy) then self:Move(dx > 0 and "right" or "left") else self:Move(dy > 0 and "up" or "down") end
    end)
    self.boardFrame = board
    self.tiles = {}
    for i = 1, Gems.SIZE * Gems.SIZE do
        local r, c = math.floor((i - 1) / Gems.SIZE), (i - 1) % Gems.SIZE
        local t = CreateFrame("Frame", nil, board)
        t:SetSize(TILE, TILE)
        t:SetPoint("TOPLEFT", TILE_GAP + c * (TILE + TILE_GAP), -(TILE_GAP + r * (TILE + TILE_GAP)))
        t.bg = t:CreateTexture(nil, "BACKGROUND")
        t.bg:SetAllPoints()
        t.edge = CreateFrame("Frame", nil, t)
        t.edge:SetAllPoints()
        UI.Border(t.edge, { 1, 1, 1, 1 }, "OVERLAY")
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(52, 52)
        t.icon:SetPoint("TOP", 0, -12)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.name = UI.Text(t, 9)
        t.name:SetPoint("BOTTOM", 0, 8)
        t.name:SetWidth(TILE - 8)
        t.name:SetWordWrap(false)
        self.tiles[i] = t
    end
    -- on-screen arrows under the board
    local arrows = { { "left", "<" }, { "up", "^" }, { "down", "v" }, { "right", ">" } }
    local aw = 44
    local ax = PAD + (BOARD_W - (4 * aw + 3 * 6)) / 2
    for i, a in ipairs(arrows) do
        local btn = UI.Button(view, a[2], aw, 26, function() self:Move(a[1]) end)
        btn:SetPoint("TOPLEFT", ax + (i - 1) * (aw + 6), -(top + BOARD_W + GAP))
    end

    -- side: score, best, new game, message, leaderboard
    local side = CreateFrame("Frame", nil, view)
    side:SetPoint("TOPLEFT", SIDE_X, -top)
    side:SetSize(SIDE_W, height)
    UI.Card(side)
    self.side = side
    local function stat(label, x)
        local s = CreateFrame("Frame", nil, side)
        s:SetSize(120, 60)
        s:SetPoint("TOPLEFT", x, -12)
        s.label = UI.SectionTitle(s, label)
        s.label:SetPoint("TOPLEFT", 0, 0)
        s.value = UI.Text(s, 24)
        s.value:SetPoint("TOPLEFT", 0, -16)
        return s
    end
    side.score = stat("Score", 14)
    side.best = stat("Best", 150)
    side.new = UI.Button(side, "New game", 100, 24, function() self:NewGame() end)
    side.new:SetPoint("TOPRIGHT", -12, -16)
    side.gem = UI.Text(side, 11)
    side.gem:SetPoint("TOPLEFT", 14, -72)
    side.gem:SetTextColor(0.75, 0.75, 0.8)
    side.message = UI.Text(side, 12)
    side.message:SetPoint("TOPLEFT", 14, -92)
    side.message:SetWidth(SIDE_W - 28)
    side.message:SetJustifyH("LEFT")
    local lt = UI.SectionTitle(side, "Guild leaderboard")
    lt:SetPoint("TOPLEFT", 14, -126)
    local line = side:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -142)
    line:SetPoint("TOPRIGHT", -1, -142)
    line:SetHeight(1)
    UI.Line(line, 0.06)
    side.rows = {}
    for i = 1, math.floor((height - 150) / ROW_H) do
        local row = CreateFrame("Frame", nil, side)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(146 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(146 + (i - 1) * ROW_H))
        row.mine = row:CreateTexture(nil, "BACKGROUND")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.16)
        row.rank = UI.Text(row, 11)
        row.rank:SetPoint("RIGHT", row, "LEFT", 30, 0)
        row.rank:SetTextColor(0.6, 0.6, 0.65)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 38, 0)
        row.score = UI.Text(row, 12)
        row.score:SetPoint("RIGHT", -12, 0)
        row.gem = row:CreateTexture(nil, "ARTWORK")
        row.gem:SetSize(16, 16)
        row.gem:SetPoint("RIGHT", row.score, "LEFT", -90, 0)
        row.gem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        side.rows[i] = row
    end
    side.empty = UI.Text(side, 11)
    side.empty:SetPoint("TOPLEFT", 14, -152)
    side.empty:SetTextColor(0.5, 0.5, 0.55)
    side.empty:SetText("No scores yet.")
    self:Load()
    if not self.board then self:NewGame() end
end

function Gems:Refresh()
    if not self.view then return end
    local b = self.board
    for i, t in ipairs(self.tiles) do
        local v = b.cells[i]
        if v > 0 then
            local r = Gems.Rarity(v)
            t.bg:SetColorTexture(r[1] * 0.18, r[2] * 0.18, r[3] * 0.18, 1)
            UI.SetBorderColor(t.edge, { r[1], r[2], r[3], 0.9 })
            t.icon:SetTexture(Gems.Icon(v))
            t.icon:Show()
            t.name:SetText(Gems.Name(v))
            t.name:SetTextColor(r[1], r[2], r[3])
        else
            t.bg:SetColorTexture(0, 0, 0, 0.3)
            UI.SetBorderColor(t.edge, { 1, 1, 1, 0.04 })
            t.icon:Hide()
            t.name:SetText("")
        end
    end
    local side = self.side
    side.score.value:SetText(tostring(b.score))
    side.best.value:SetText(tostring(math.max(G().best, b.score)))
    local top = b:Best()
    local r = Gems.Rarity(math.max(top, 1))
    side.gem:SetText(("Biggest gem: |cff%02x%02x%02x%s|r"):format(r[1] * 255, r[2] * 255, r[3] * 255, Gems.Name(math.max(top, 1))))
    side.message:SetText(self.message or "")
    self:RefreshBoard()
end

function Gems:RefreshBoard()
    if not self.side then return end
    local me = ns.Sync:Me()
    local list = self:Leaderboard()
    for i, row in ipairs(self.side.rows) do
        local rec = list[i]
        if rec then
            row.rank:SetText(i .. ".")
            local p = ns.db.guild.players[rec.author]
            local cc = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            row.name:SetText(Ambiguate(rec.author, "short"))
            if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) end
            row.score:SetText(tostring(rec.best))
            row.gem:SetTexture(Gems.Icon(rec.tier))
            row.mine:SetShown(rec.author == me)
            row:Show()
        else
            row:Hide()
        end
    end
    self.side.empty:SetShown(#list == 0)
end

ns.On("PLAYER_LOGIN", function() C_Timer.After(22, function() Gems:Publish() end) end)
