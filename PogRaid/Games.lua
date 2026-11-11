-- Pog Raid games: Sapper Sweeper, minesweeper with Goblin Sapper Charges.
--
-- Left-click reveals, right-click marks a tile with a skull, clicking a
-- revealed number whose skulls are all placed opens its neighbours. The
-- first click is always safe. Best times are kept per difficulty.
local _, ns = ...
local UI = ns.UI

local Games = {}
ns.Games = Games

local PAD, GAP, TITLE_H, BAR_H = 12, 8, 30, 26
local FRAME_W, FRAME_H = 902, ns.PAGE_H
local INNER_W = FRAME_W - 2 * PAD
local ROW1_Y = TITLE_H
local STATUS_Y = ROW1_Y + BAR_H + GAP
local STATUS_H = 44
local MSG_H = 18                                  -- win / loss line between the bar and the board
local MSG_Y = STATUS_Y + STATUS_H + 4
local BOARD_Y = MSG_Y + MSG_H + 4
local HELP_H = 0                                  -- (no controls hint under the board: Jake)
local BOARD_MAX_H = FRAME_H - PAD - HELP_H - 6 - BOARD_Y
local MAX_CELL = 40
-- the game and its leaderboard on one page (Jake): the board from the page's
-- left edge, the guild's times for the picked difficulty in a card filling the
-- rest of the width and as tall as the game (bar to board bottom), so nothing
-- floats (UI experiment). LB_W is its narrowest (Expert).
local LB_W = 240
local GAME_W = INNER_W - LB_W - GAP
Games.layout = { LB_W = LB_W, GAME_W = GAME_W, STATUS_Y = STATUS_Y }

local SAPPER_ICON = "Interface\\Icons\\Spell_Fire_SelfDestruct"
local SAPPER_ITEM = 10646 -- Goblin Sapper Charge
local CLOCK_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local SKULL = 8

-- game tabs along the top of the Games page
Games.MODES = {
    { key = "wowdle", label = "Wowdle", w = 76 },
    { key = "sweeper", label = "Sapper Sweeper", w = 128 },
    { key = "gems", label = "Gem Cutter", w = 100 },
    { key = "lode", label = "Motherlode", w = 100 },
    { key = "duels", label = "Ranked Duels", w = 112 },
}

Games.LEVELS = {
    { key = "apprentice", label = "Apprentice", cols = 9, rows = 9, mines = 10 },
    { key = "journeyman", label = "Journeyman", cols = 16, rows = 16, mines = 40 },
    { key = "expert", label = "Expert", cols = 30, rows = 16, mines = 99 },
}

-- classic minesweeper number colours, lifted a little for a dark board
local NUMBER_COLORS = {
    { 0.35, 0.60, 1.00 }, { 0.35, 0.80, 0.35 }, { 0.95, 0.35, 0.30 }, { 0.55, 0.45, 1.00 },
    { 0.85, 0.40, 0.25 }, { 0.30, 0.80, 0.80 }, { 0.90, 0.90, 0.90 }, { 0.60, 0.60, 0.65 },
}

------------------------------------------------------------------------
-- Game logic (no UI): cells are numbered 1..cols*rows, row by row.
------------------------------------------------------------------------
local Sweeper = {}
Sweeper.__index = Sweeper
Games.Sweeper = Sweeper

function Sweeper.New(cols, rows, mines)
    local g = setmetatable({ cols = cols, rows = rows, mines = mines, n = cols * rows, state = "ready",
        mine = {}, open = {}, flag = {}, count = {}, opened = 0, flags = 0 }, Sweeper)
    return g
end

function Sweeper:Neighbors(i)
    local out = {}
    local c, r = (i - 1) % self.cols, math.floor((i - 1) / self.cols)
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local nc, nr = c + dc, r + dr
                if nc >= 0 and nc < self.cols and nr >= 0 and nr < self.rows then
                    out[#out + 1] = nr * self.cols + nc + 1
                end
            end
        end
    end
    return out
end

-- Place mines anywhere except the first click and its neighbours (when the
-- board has room), then count each cell's neighbouring mines.
function Sweeper:Place(safe)
    local keepClear = { [safe] = true }
    if self.n - self.mines >= 9 then
        for _, j in ipairs(self:Neighbors(safe)) do keepClear[j] = true end
    end
    local pool = {}
    for i = 1, self.n do
        if not keepClear[i] then pool[#pool + 1] = i end
    end
    for k = 1, self.mines do
        local pick = math.random(k, #pool)
        pool[k], pool[pick] = pool[pick], pool[k]
        self.mine[pool[k]] = true
    end
    for i = 1, self.n do
        local c = 0
        for _, j in ipairs(self:Neighbors(i)) do
            if self.mine[j] then c = c + 1 end
        end
        self.count[i] = c
    end
    self.state = "playing"
end

-- Reveal a cell (flood-filling zeros). Returns "boom" on a mine.
function Sweeper:Reveal(i)
    if self.state == "won" or self.state == "lost" then return end
    if self.state == "ready" then self:Place(i) end
    if self.open[i] or self.flag[i] then return end
    if self.mine[i] then
        self.open[i] = true
        self.boom = i
        self.state = "lost"
        return "boom"
    end
    local stack = { i }
    while #stack > 0 do
        local j = table.remove(stack)
        if not self.open[j] and not self.flag[j] then
            self.open[j] = true
            self.opened = self.opened + 1
            if self.count[j] == 0 then
                for _, k in ipairs(self:Neighbors(j)) do
                    if not self.open[k] and not self.mine[k] then stack[#stack + 1] = k end
                end
            end
        end
    end
    if self.opened == self.n - self.mines then
        self.state = "won"
        for j = 1, self.n do
            if self.mine[j] and not self.flag[j] then
                self.flag[j] = true
                self.flags = self.flags + 1
            end
        end
    end
end

function Sweeper:ToggleFlag(i)
    if self.open[i] or self.state == "won" or self.state == "lost" then return end
    self.flag[i] = not self.flag[i] or nil
    self.flags = self.flags + (self.flag[i] and 1 or -1)
end

-- Clicking a revealed number with that many skulls around it opens the rest.
function Sweeper:Chord(i)
    if not self.open[i] or self.state ~= "playing" or (self.count[i] or 0) == 0 then return end
    local flagged = 0
    for _, j in ipairs(self:Neighbors(i)) do
        if self.flag[j] then flagged = flagged + 1 end
    end
    if flagged ~= self.count[i] then return end
    local result
    for _, j in ipairs(self:Neighbors(i)) do
        if not self.open[j] and not self.flag[j] then result = self:Reveal(j) or result end
    end
    return result
end

function Sweeper:Left()
    return self.mines - self.flags
end

------------------------------------------------------------------------
-- Guild leaderboard: one shared record per player per difficulty, synced
-- like the message board. The id is fixed (player:level) so a new best
-- replaces the old one everywhere.
------------------------------------------------------------------------
local LEVEL_KEYS = {}
for _, lv in ipairs(Games.LEVELS) do LEVEL_KEYS[lv.key] = true end

ns.Sync:Register({
    name = "scores", code = "s", order = 4,
    fields = { "level", "best" },
    numeric = { best = true },
    valid = function(rec)
        return rec.by == rec.author and LEVEL_KEYS[rec.level or ""] and rec.best ~= nil and rec.best > 0
            and rec.best < 100000 and rec.id == rec.author .. ":" .. rec.level
    end,
    onChange = function() Games:Changed() end,
})

function Games:Publish(level, best)
    local me = ns.Sync:Me()
    if not ns.Sync:GuildName() then return end
    local store = ns.Sync:Store("scores")
    local id = me .. ":" .. level
    local cur = store and store[id]
    best = math.floor(best * 10 + 0.5) / 10
    if cur and not cur.deleted and cur.best <= best then return end
    ns.Sync:Write("scores", { id = id, author = me, t = ns.Now(), level = level, best = best })
end

-- Share best times earned before the leaderboard existed (or while offline).
function Games:PublishAll()
    for level, best in pairs((ns.db.games and ns.db.games.best) or {}) do
        if LEVEL_KEYS[level] then self:Publish(level, best) end
    end
end

-- Fastest first; ties go to whoever set it first.
function Games:Leaderboard(level)
    local out = {}
    for _, rec in pairs(ns.Sync:Store("scores") or {}) do
        if rec.level == level and not rec.deleted then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b)
        if a.best ~= b.best then return a.best < b.best end
        if a.t ~= b.t then return a.t < b.t end
        return a.author < b.author
    end)
    return out
end

function Games:Rank(level, who)
    for i, rec in ipairs(self:Leaderboard(level)) do
        if rec.author == who then return i end
    end
end

function Games:Changed()
    if self.page and self.page:IsVisible() and self.mode == "sweeper" then self:RefreshScores() end
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local function G()
    ns.db.games = ns.db.games or { best = {} }
    return ns.db.games
end

local function sapperIcon()
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, SAPPER_ITEM)
        if ok and icon then return icon end
    end
    return SAPPER_ICON
end

local function fmtTime(s)
    s = math.floor(s)
    if s < 60 then return s .. "s" end
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end
Games.FormatTime = fmtTime

-- Leaderboard times keep tenths under a minute, so near-ties read apart.
local function fmtBest(s)
    if s < 60 then return ("%.1fs"):format(math.floor(s * 10 + 0.5) / 10) end
    return fmtTime(s)
end
Games.FormatBest = fmtBest

function Games:Build(page)
    self.page = page

    -- which game: tabs along the top left; the game's own controls sit on the right
    self.modeTabs = {}
    local tx = PAD
    for _, m in ipairs(Games.MODES) do
        -- the talent window's tabs in the classic look, else underlined text tabs
        local t = UI.SubTab(page, m.label, function() self:SetMode(m.key) end)
            or UI.Tab(page, m.label, m.w, BAR_H, function() self:SetMode(m.key) end)
        t:SetPoint("TOPLEFT", tx, -ROW1_Y)
        self.modeTabs[m.key] = t
        tx = tx + t:GetWidth() + (UI.classic and UI.SUBTAB_GAP or 4)
    end
    self.levelButtons = {}
    local x = FRAME_W - PAD - (3 * 96 + 2 * 4)
    for _, lv in ipairs(Games.LEVELS) do
        local b = UI.Button(page, lv.label, 96, BAR_H, function() self:NewGame(lv.key) end)
        b:SetPoint("TOPLEFT", x, -ROW1_Y)
        self.levelButtons[lv.key] = b
        x = x + 96 + 4
    end

    -- status bar: sappers left | new game | timer
    local bar = CreateFrame("Frame", nil, page)
    bar:SetHeight(STATUS_H)
    UI.Card(bar)
    self.bar = bar
    bar.sapper = bar:CreateTexture(nil, "ARTWORK")
    bar.sapper:SetSize(24, 24)
    bar.sapper:SetPoint("LEFT", 10, 0)
    bar.sapper:SetTexture(sapperIcon())
    bar.sapper:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.left = UI.Text(bar, 18)
    bar.left:SetPoint("LEFT", bar.sapper, "RIGHT", 8, 0)
    bar.left:SetTextColor(0.95, 0.35, 0.3)
    bar.clock = bar:CreateTexture(nil, "ARTWORK")
    bar.clock:SetSize(24, 24)
    bar.clock:SetPoint("RIGHT", -10, 0)
    bar.clock:SetTexture(CLOCK_ICON)
    bar.clock:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.time = UI.Text(bar, 18)
    bar.time:SetPoint("RIGHT", bar.clock, "LEFT", -8, 0)
    bar.time:SetJustifyH("RIGHT")
    local face = CreateFrame("Button", nil, bar)
    face:SetSize(38, 38)
    face:SetPoint("CENTER")
    face.plate = face:CreateTexture(nil, "BACKGROUND")
    face.plate:SetAllPoints()
    face.plate:SetTexture(ns.MEDIA .. "disc")
    face.plate:SetVertexColor(0.13, 0.14, 0.17, 1)
    face.icon = face:CreateTexture(nil, "ARTWORK")
    face.icon:SetSize(34, 34)
    face.icon:SetPoint("CENTER", 0, 1)
    face.icon:SetTexture(ns.MEDIA .. "logo")
    local hl = face:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(ns.MEDIA .. "disc")
    hl:SetVertexColor(1, 1, 1, 0.12)
    face:SetScript("OnClick", function() self:NewGame(self.level) end)
    bar.face = face
    -- own line under the bar, so the board never covers it
    bar.message = UI.Text(page, 12)
    bar.message:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    bar.message:SetHeight(MSG_H)
    bar.message:SetTextColor(0.8, 0.8, 0.85)

    local board = CreateFrame("Frame", nil, page)
    UI.Card(board, { 0.03, 0.03, 0.035, 1 })
    self.board = board
    self.cells = {}


    self:BuildScores(page)
    -- the other games each get a full-page view under the tabs
    self.views = {}
    for key, mod in pairs({ duels = ns.Duels, gems = ns.Gems, wowdle = ns.Wowdle, lode = ns.Lode }) do
        local v = CreateFrame("Frame", nil, page)
        v:SetAllPoints()
        v:Hide()
        mod:Build(v, STATUS_Y, FRAME_H - PAD - STATUS_Y)
        self.views[key] = v
    end
    self.duelsView = self.views.duels
    self:NewGame(G().level or "apprentice")
    self:SetMode(G().mode or Games.MODES[1].key)
end

function Games:SetMode(mode)
    if not self.modeTabs[mode or ""] then mode = Games.MODES[1].key end
    self.mode = mode
    G().mode = mode
    local sweeper = mode == "sweeper"
    for key, t in pairs(self.modeTabs) do t:SetSelected(key == mode) end
    for _, b in pairs(self.levelButtons) do b:SetShown(sweeper) end
    for key, v in pairs(self.views) do v:SetShown(key == mode) end
    if sweeper then
        self.scores:Show()
        self.bar:Show()
        self.board:Show()
        self.bar.message:Show()
        self:PublishAll()
        self:RefreshScores()
    else
        self.scores:Hide()
        self.bar:Hide()
        self.board:Hide()
        self.bar.message:Hide()
        local mod = ({ duels = ns.Duels, gems = ns.Gems, wowdle = ns.Wowdle, lode = ns.Lode })[mode]
        mod:Refresh()
    end
end

-- The leaderboard card: the picked difficulty's fastest times.
local SCORE_ROWS = 20
local SCORE_H = 22

function Games:BuildScores(page)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", FRAME_W - PAD - LB_W, -STATUS_Y)
    c:SetSize(LB_W, FRAME_H - PAD - STATUS_Y)
    UI.Card(c)
    self.scores = c
    c.title = UI.SectionTitle(c, "Leaderboard")
    c.title:SetPoint("LEFT", c, "TOPLEFT", 10, -UI.HeadMid(32))
    c.sub = UI.Text(c, 11)
    c.sub:SetPoint("RIGHT", c, "TOPRIGHT", -10, -UI.HeadMid(32))
    c.sub:SetTextColor(0.6, 0.6, 0.65)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -32)
    line:SetPoint("TOPRIGHT", -1, -32)
    line:SetHeight(1)
    UI.Line(line, 0.06)
    c.rows = {}
    for r = 1, SCORE_ROWS + 1 do
        local row = CreateFrame("Frame", nil, c)
        row:SetHeight(SCORE_H)
        if r > SCORE_ROWS then
            -- your own place sits at the card's bottom
            row:SetPoint("BOTTOMLEFT", 2, 6)
            row:SetPoint("BOTTOMRIGHT", -2, 6)
        else
            local y = -36 - (r - 1) * SCORE_H
            row:SetPoint("TOPLEFT", 2, y)
            row:SetPoint("TOPRIGHT", -2, y)
        end
        row.mine = row:CreateTexture(nil, "BACKGROUND")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.16)
        row.rank = UI.Text(row, 11)
        row.rank:SetPoint("RIGHT", row, "LEFT", 32, 0)
        row.rank:SetJustifyH("RIGHT")
        row.rank:SetTextColor(0.6, 0.6, 0.65)
        row.ago = UI.Text(row, 10)
        row.ago:SetPoint("RIGHT", -8, 0)
        row.ago:SetTextColor(0.5, 0.5, 0.55)
        row.time = UI.Text(row, 12)
        row.time:SetPoint("RIGHT", row, "RIGHT", -44, 0)
        row.time:SetJustifyH("RIGHT")
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 42, 0)
        row.name:SetPoint("RIGHT", row.time, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        c.rows[r] = row
    end
    c.empty = UI.Text(c, 11)
    c.empty:SetPoint("TOP", 0, -56)
    c.empty:SetTextColor(0.5, 0.5, 0.55)
    c.empty:SetText("No times yet.")
end

local MEDALS = { { 1, 0.82, 0.2 }, { 0.8, 0.82, 0.88 }, { 0.85, 0.55, 0.3 } }

function Games:RefreshScores()
    local me = ns.Sync:Me()
    local c, level = self.scores, self.level
    for _, lv in ipairs(Games.LEVELS) do
        if lv.key == level then c.sub:SetText(lv.label) end
    end
    local list = self:Leaderboard(level)
    local myRank = self:Rank(level, me)
    local fit = self.scoresFit or SCORE_ROWS
    for r, row in ipairs(c.rows) do
        local rec, rank = list[r], r
        if r > SCORE_ROWS then
            -- your own place, if you're below the rows that fit
            rank = myRank
            rec = (myRank and myRank > fit) and list[myRank] or nil
        elseif r > fit then
            rec = nil
        end
        if rec then
            row.rank:SetText(rank .. ".")
            local medal = MEDALS[rank]
            if medal then row.rank:SetTextColor(medal[1], medal[2], medal[3]) else row.rank:SetTextColor(0.6, 0.6, 0.65) end
            local p = ns.db.guild.players[rec.author]
            local cc = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            row.name:SetText(Ambiguate(rec.author, "short"))
            if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) end
            row.time:SetText(fmtBest(rec.best))
            row.ago:SetText(ns.Home and ns.Home.Ago(rec.t) or "")
            row.mine:SetShown(rec.author == me)
            row:Show()
        else
            row:Hide()
        end
    end
    c.empty:SetShown(#list == 0)
end

local function makeCell(board)
    local c = CreateFrame("Button", nil, board)
    -- act on the press (Jake: fast clicking lost clicks when the mouse drifted
    -- onto the next tile before the release)
    c:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    -- bevel: light top/left, dark bottom/right while the tile is covered
    c.lightT = c:CreateTexture(nil, "BORDER")
    c.lightT:SetPoint("TOPLEFT")
    c.lightT:SetPoint("TOPRIGHT")
    c.lightT:SetHeight(2)
    c.lightL = c:CreateTexture(nil, "BORDER")
    c.lightL:SetPoint("TOPLEFT")
    c.lightL:SetPoint("BOTTOMLEFT")
    c.lightL:SetWidth(2)
    c.darkB = c:CreateTexture(nil, "BORDER")
    c.darkB:SetPoint("BOTTOMLEFT")
    c.darkB:SetPoint("BOTTOMRIGHT")
    c.darkB:SetHeight(2)
    c.darkR = c:CreateTexture(nil, "BORDER")
    c.darkR:SetPoint("TOPRIGHT")
    c.darkR:SetPoint("BOTTOMRIGHT")
    c.darkR:SetWidth(2)
    c.lightT:SetColorTexture(1, 1, 1, 0.14)
    c.lightL:SetColorTexture(1, 1, 1, 0.14)
    c.darkB:SetColorTexture(0, 0, 0, 0.45)
    c.darkR:SetColorTexture(0, 0, 0, 0.45)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    UI.Hover(c.hl, 0.07)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("CENTER")
    c.num = c:CreateFontString(nil, "OVERLAY")
    c.num:SetFont(UI.FONT, 12, "OUTLINE")
    c.num:SetPoint("CENTER", 0, 0)
    c.cross = c:CreateFontString(nil, "OVERLAY")
    c.cross:SetFont(UI.FONT, 12, "OUTLINE")
    c.cross:SetPoint("CENTER")
    c.cross:SetTextColor(1, 0.25, 0.2)
    c:SetScript("OnClick", function(self, button) Games:Click(self.index, button) end)
    return c
end

function Games:NewGame(key)
    local lv = Games.LEVELS[1]
    for _, l in ipairs(Games.LEVELS) do
        if l.key == key then lv = l end
    end
    self.level = lv.key
    G().level = lv.key
    self.game = Sweeper.New(lv.cols, lv.rows, lv.mines)
    self.started, self.finished = nil, nil
    self.newBest, self.newRank = nil, nil
    for k, b in pairs(self.levelButtons) do b:SetSelected(k == lv.key) end

    -- size cells to fit the window, centre the board
    local cell = math.min(math.floor((GAME_W - 4) / lv.cols), math.floor((BOARD_MAX_H - 4) / lv.rows), MAX_CELL)
    self.cellSize = cell
    local w, h = lv.cols * cell + 4, lv.rows * cell + 4
    local bx = PAD
    if self.scores then
        local sh = (BOARD_Y - STATUS_Y) + h
        self.scores:ClearAllPoints()
        self.scores:SetPoint("TOPLEFT", self.page, "TOPLEFT", bx + w + GAP, -STATUS_Y)
        self.scores:SetSize(INNER_W - w - GAP, sh)
        self.scoresFit = math.min(SCORE_ROWS, math.floor((sh - 36 - SCORE_H - 14) / SCORE_H))
    end
    self.board:ClearAllPoints()
    self.board:SetSize(w, h)
    self.board:SetPoint("TOPLEFT", self.page, "TOPLEFT", bx, -BOARD_Y)
    self.bar:ClearAllPoints()
    self.bar:SetSize(w, STATUS_H)
    self.bar:SetPoint("TOPLEFT", self.page, "TOPLEFT", bx, -STATUS_Y)

    local n = lv.cols * lv.rows
    for i = 1, n do
        local c = self.cells[i] or makeCell(self.board)
        self.cells[i] = c
        c.index = i
        local col, row = (i - 1) % lv.cols, math.floor((i - 1) / lv.cols)
        c:ClearAllPoints()
        c:SetSize(cell - 1, cell - 1)
        c:SetPoint("TOPLEFT", self.board, "TOPLEFT", 2 + col * cell, -(2 + row * cell))
        c.icon:SetSize(cell - 8, cell - 8)
        local size = math.max(10, math.floor(cell * 0.55))
        c.num:SetFont(UI.FONT, size, "OUTLINE")
        c.cross:SetFont(UI.FONT, size, "OUTLINE")
        c:Show()
    end
    for i = n + 1, #self.cells do self.cells[i]:Hide() end
    self.page:SetScript("OnUpdate", nil)
    self:Refresh()
    if self.scores then self:RefreshScores() end
end

function Games:Click(i, button)
    local g = self.game
    if not g or g.state == "won" or g.state == "lost" then return end
    if button == "RightButton" then
        g:ToggleFlag(i)
    elseif g.open[i] then
        g:Chord(i)
    else
        g:Reveal(i)
    end
    if g.state == "playing" and not self.started then
        self.started = GetTime()
        self.page:SetScript("OnUpdate", function()
            if not self.lastSecond or GetTime() - self.lastSecond >= 0.2 then
                self.lastSecond = GetTime()
                self:RefreshBar()
            end
        end)
    end
    if g.state == "won" or g.state == "lost" then
        self.finished = GetTime()
        self.page:SetScript("OnUpdate", nil)
        if g.state == "won" then
            local t = self.finished - (self.started or self.finished)
            local best = G().best[self.level]
            if not best or t < best then
                G().best[self.level] = t
                self.newBest = true
                self:Publish(self.level, t)
                self.newRank = self:Rank(self.level, ns.Sync:Me())
            end
            ns.Sound("UI_EPICLOOT_TOAST")
        end
    end
    self:Refresh()
end

function Games:Elapsed()
    if not self.started then return 0 end
    return (self.finished or GetTime()) - self.started
end

function Games:RefreshBar()
    local g = self.game
    self.bar.left:SetText(tostring(g:Left()))
    self.bar.time:SetText(fmtTime(self:Elapsed()))
    local msg = ""
    if g.state == "lost" then
        msg = "|cffff5040KABOOM!|r Click the gnome to try again"
    elseif g.state == "won" then
        local extra = ""
        if self.newBest then
            extra = self.newRank and (", new best! #%d in the guild"):format(self.newRank) or ", new best!"
        end
        msg = ("|cff66dd77Cleared in %s|r%s"):format(fmtTime(self:Elapsed()), extra)
    end
    if msg == "" then msg = "|cff8a8a92" .. (self.bestText or "") .. "|r" end
    self.bar.message:SetText(msg)
    local lost = g.state == "lost"
    self.bar.face.icon:SetVertexColor(1, lost and 0.45 or 1, lost and 0.45 or 1)
end

function Games:Refresh()
    local g = self.game
    local icon = sapperIcon()
    for i = 1, g.n do
        local c = self.cells[i]
        local open, flag, mine = g.open[i], g.flag[i], g.mine[i]
        local over = g.state == "lost"
        c.num:SetText("")
        c.cross:SetText("")
        c.icon:Hide()
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.icon:SetVertexColor(1, 1, 1, 1)
        local covered = not open and not (over and mine)
        c.lightT:SetShown(covered)
        c.lightL:SetShown(covered)
        c.darkB:SetShown(covered)
        c.darkR:SetShown(covered)
        if covered then
            c.bg:SetColorTexture(0.22, 0.23, 0.27, 1)
            if flag then
                c.icon:SetTexture(RAID_ICONS)
                SetRaidTargetIconTexture(c.icon, SKULL)
                c.icon:Show()
                if over and not mine then c.cross:SetText("X") end
            end
        elseif mine then
            -- the charge you hit glows red; the rest are shown where they were
            c.bg:SetColorTexture(i == g.boom and 0.75 or 0.1, i == g.boom and 0.12 or 0.1, i == g.boom and 0.1 or 0.11, 1)
            c.icon:SetTexture(icon)
            c.icon:Show()
            if flag then c.icon:SetVertexColor(0.6, 1, 0.6, 1) end
        else
            c.bg:SetColorTexture(0.1, 0.1, 0.115, 1)
            local n = g.count[i] or 0
            if n > 0 then
                local col = NUMBER_COLORS[n]
                c.num:SetText(tostring(n))
                c.num:SetTextColor(col[1], col[2], col[3])
            end
        end
    end
    local best = G().best[self.level]
    self.bestText = best and ("Best on %s: %s"):format(self.level:sub(1, 1):upper() .. self.level:sub(2), fmtTime(best))
        or "No best time yet"
    self:RefreshBar()
end

-- share best times a little after login, once the guild is known
ns.On("PLAYER_LOGIN", function() C_Timer.After(20, function() Games:PublishAll() end) end)

ns.Editor:RegisterTab("games", "Games", 5,
    function(page) Games:Build(page) end,
    function()
        Games:Refresh()
        if Games.mode ~= "sweeper" then Games:SetMode(Games.mode) end
    end)

------------------------------------------------------------------------
-- On a flight path there's nothing to do but wait: with "Open Games on
-- flight paths" ticked in Settings (off unless you tick it; Jake, 0.16.9),
-- taking one opens the Games tab on the game you last played. The game says
-- we've lost control of our character for other reasons too (a fear, a
-- cutscene), so we look a moment later whether we're really on a taxi. A
-- window already open is left as it is, and nothing closes on landing.
------------------------------------------------------------------------
Games.FLIGHT_WAIT = 1 -- seconds after losing control before asking the game if we're flying

function Games:OnControlLost()
    if ns.db.settings.gamesOnFlight ~= true then return end
    C_Timer.After(Games.FLIGHT_WAIT, function()
        if ns.db.settings.gamesOnFlight ~= true or not (UnitOnTaxi and UnitOnTaxi("player")) then return end
        local E = ns.Editor
        if E.frame and E.frame:IsShown() then return end
        E:Toggle("games")
    end)
end

ns.On("PLAYER_CONTROL_LOST", function() Games:OnControlLost() end)
