-- Pog Raid games: Wowdle, a daily five-letter WoW word. Six tries; green =
-- right letter in the right place, gold = in the word elsewhere, grey = not
-- in it. The whole guild gets the same word, which changes at the daily
-- reset. Results (guess count and colours, never letters) are shared.
local _, ns = ...
local UI = ns.UI

local Wowdle = {}
ns.Wowdle = Wowdle

Wowdle.TRIES = 6
Wowdle.MIN_LEN, Wowdle.MAX_LEN = 5, 8

-- The first list (five letters, used until LIST2_DAY). Kept so past days
-- still resolve to the word people actually played.
Wowdle.WORDS = {
    "UTHER", "JAINA", "MAIEV", "MAGNI", "GAMON", "MOIRA", "KALEC", "BAINE", "ELUNE", "YSERA", "AKAMA", "VELEN",
    "GRUUL", "LOKEN", "FREYA", "HODIR", "IGNIS", "EDWIN", "JINDO", "MARLI", "CTHUN", "ULDUM", "ULDIR", "AERIE",
    "ARGUS", "GNOME", "DWARF", "TROLL", "HUMAN", "DRUID", "ROGUE", "GOLEM", "DRAKE", "WHELP", "HARPY", "TROGG",
    "GHOUL", "DEMON", "SATYR", "DRYAD", "SLIME", "BEAST", "GNOLL", "MOUNT", "GUILD", "TOTEM", "TAUNT", "SHEEP",
    "STAFF", "SWORD", "PLATE", "CLOTH", "SPELL", "FROST", "QUEST", "LEVEL", "AGGRO", "BUFFS", "HEALS", "TANKS",
    "PARTY", "SPAWN", "PATCH", "RAIDS", "WIPES", "FLASK", "HERBS", "BLADE", "ARROW", "RUNES", "RELIC", "TOKEN",
    "CHEST", "BOOTS", "CLOAK", "ARENA", "HONOR", "BLOOD", "LIGHT", "TITAN", "NAARU", "HORDE", "GREED", "DUELS",
    "GRIND", "CRYPT", "VAULT", "ALTAR", "SWAMP", "GLYPH", "SCALE", "TRADE", "STEED", "STONE", "SHARD", "BLINK",
    "FEINT", "GOUGE", "SMITE", "RENEW", "CURSE", "DRAIN", "SHOCK", "FLARE", "MELEE", "DODGE", "PARRY", "BLOCK",
    "SNARE", "TRASH", "ELITE", "ORDER", "FLAME", "TIDES", "STORM", "EARTH", "SPIRE", "KEEPS", "TOWER", "FORGE",
    "ANVIL", "GEARS", "BOMBS", "CHAIN",
}

-- The current list: 5 to 8 letters, singular words and names (the names that
-- end in S, like Arthas or Tanaris, aren't plurals). Only append at the end:
-- the daily pick walks this list, so reordering would change past puzzles.
-- The count must not be a multiple of 53 (the daily step).
Wowdle.LIST2_DAY = 20723
Wowdle.WORDS2 = {
    "UTHER", "JAINA", "MAIEV", "MAGNI", "GAMON", "MOIRA", "KALEC", "BAINE", "ELUNE", "YSERA", "AKAMA",
    "VELEN", "GRUUL", "LOKEN", "FREYA", "HODIR", "IGNIS", "EDWIN", "JINDO", "CTHUN", "ULDUM", "ULDIR",
    "AERIE", "ARGUS", "GNOME", "DWARF", "TROLL", "HUMAN", "DRUID", "ROGUE", "GOLEM", "DRAKE", "WHELP",
    "HARPY", "TROGG", "GHOUL", "DEMON", "SATYR", "DRYAD", "SLIME", "BEAST", "GNOLL", "MOUNT", "GUILD",
    "TOTEM", "TAUNT", "SHEEP", "STAFF", "SWORD", "PLATE", "CLOTH", "SPELL", "FROST", "QUEST", "LEVEL",
    "AGGRO", "PARTY", "SPAWN", "PATCH", "FLASK", "BLADE", "ARROW", "RELIC", "TOKEN", "CHEST", "CLOAK",
    "ARENA", "HONOR", "BLOOD", "LIGHT", "TITAN", "NAARU", "HORDE", "GREED", "GRIND", "CRYPT", "VAULT",
    "ALTAR", "SWAMP", "GLYPH", "SCALE", "TRADE", "STEED", "STONE", "SHARD", "BLINK", "FEINT", "GOUGE",
    "SMITE", "RENEW", "CURSE", "DRAIN", "SHOCK", "FLARE", "MELEE", "DODGE", "PARRY", "BLOCK", "SNARE",
    "TRASH", "ELITE", "ORDER", "FLAME", "STORM", "EARTH", "SPIRE", "TOWER", "FORGE", "ANVIL", "CHAIN",
    "MURLOC", "ONYXIA", "HOGGER", "ARTHAS", "THRALL", "TAUREN", "KOBOLD", "GOBLIN", "HEARTH", "POTION", "ELIXIR",
    "SHIELD", "PORTAL", "TABARD", "RAPTOR", "SPIDER", "WYVERN", "WRAITH", "ZOMBIE", "LEGION", "MINING", "TALENT",
    "SOCKET", "SILVER", "COPPER", "SADDLE", "VANISH", "SPRINT", "CHARGE", "FRENZY", "VOLJIN", "ANDUIN", "VARIAN",
    "TIRION", "BOLVAR", "CAIRNE", "XAVIUS", "KAZZAK", "HAKKAR", "ARUGAL", "DEFIAS", "EREDAR", "ULDUAR", "HEROIC",
    "MYTHIC", "WEAPON", "HELMET", "BRACER", "PRIEST", "HUNTER", "SHAMAN", "AZSUNA", "DUNGEON", "SURAMAR", "NAGRAND",
    "DRAENOR", "OUTLAND", "AZEROTH", "KHADGAR", "ILLIDAN", "GARROSH", "MURADIN", "SCARLET", "SCOURGE", "DRAENEI", "GRYPHON",
    "ENCHANT", "LEATHER", "BANDAGE", "FISHING", "COOKING", "ALCHEMY", "AUCTION", "DALARAN", "GILNEAS", "TANARIS", "DUROTAR",
    "MULGORE", "FERALAS", "AZSHARA", "LOCKOUT", "TRINKET", "BANSHEE", "PALADIN", "WARRIOR", "WARLOCK", "RAGNAROS", "NEFARIAN",
    "SYLVANAS", "KARAZHAN", "DUSKWOOD", "WESTFALL", "SILITHUS", "ZULGURUB", "GAUNTLET", "SHOULDER", "NECKLACE", "SUCCUBUS", "INFERNAL",
    "GARGOYLE", "SKELETON",
}

------------------------------------------------------------------------
-- Rules
------------------------------------------------------------------------
-- "g" / "y" / "x" per letter; handles repeated letters like the original.
function Wowdle.Score(guess, answer)
    local out, left = {}, {}
    local n = #answer
    for i = 1, n do
        local g, a = guess:sub(i, i), answer:sub(i, i)
        if g == a then
            out[i] = "g"
        else
            left[a] = (left[a] or 0) + 1
        end
    end
    for i = 1, n do
        if not out[i] then
            local g = guess:sub(i, i)
            if (left[g] or 0) > 0 then
                out[i] = "y"
                left[g] = left[g] - 1
            else
                out[i] = "x"
            end
        end
    end
    return table.concat(out)
end

-- Days roll over at the game's daily reset (UTC midnight if unknown).
function Wowdle:Day()
    local now = ns.Now()
    local offset = 0
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local ok, s = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok and s then offset = (now + s) % 86400 end
    end
    return math.floor((now - offset) / 86400)
end

function Wowdle:Word(day)
    day = day or self:Day()
    local list = (day >= Wowdle.LIST2_DAY) and Wowdle.WORDS2 or Wowdle.WORDS
    return list[(day * 53) % #list + 1]
end

function Wowdle:Length(day)
    return #self:Word(day or self:Current().day)
end

-- Puzzle numbers count from the day Wowdle arrived.
Wowdle.FIRST_DAY = 20722
function Wowdle:Number(day)
    return (day or self:Day()) - Wowdle.FIRST_DAY + 1
end

------------------------------------------------------------------------
-- Saved state: today's guesses, and a result per day for the stats
------------------------------------------------------------------------
local function G()
    ns.db.games = ns.db.games or { best = {} }
    ns.db.games.wowdle = ns.db.games.wowdle or { history = {} }
    return ns.db.games.wowdle
end

function Wowdle:Current()
    local g, day = G(), self:Day()
    if not g.current or g.current.day ~= day then g.current = { day = day, guesses = {} } end
    return g.current
end

function Wowdle:State()
    local cur = self:Current()
    local word = self:Word(cur.day)
    local last = cur.guesses[#cur.guesses]
    if last == word then return "won" end
    if #cur.guesses >= Wowdle.TRIES then return "lost" end
    return "playing"
end

function Wowdle:Pattern()
    local cur = self:Current()
    local word, rows = self:Word(cur.day), {}
    for i, g in ipairs(cur.guesses) do rows[i] = Wowdle.Score(g, word) end
    return table.concat(rows, ",")
end

-- Returns nil on success, or why the guess wasn't taken.
function Wowdle:Guess(text)
    if self:State() ~= "playing" then return "done" end
    local g = tostring(text or ""):upper()
    local cur = self:Current()
    local len = self:Length(cur.day)
    if #g ~= len or g:find("[^A-Z]") then return ("%d letters, please"):format(len) end
    cur.guesses[#cur.guesses + 1] = g
    local state = self:State()
    if state ~= "playing" then
        local n = state == "won" and #cur.guesses or (Wowdle.TRIES + 1)
        G().history[cur.day] = n
        self:Publish(cur.day, n, self:Pattern())
        if state == "won" then ns.Sound("UI_EPICLOOT_TOAST") end
    end
    return nil
end

function Wowdle:Stats()
    local h = G().history
    local played, wins, dist = 0, 0, { 0, 0, 0, 0, 0, 0 }
    for _, n in pairs(h) do
        played = played + 1
        if n <= Wowdle.TRIES then
            wins = wins + 1
            dist[n] = dist[n] + 1
        end
    end
    -- streak: solved days in a row, ending today (or yesterday if today isn't done)
    local today = self:Day()
    local d = h[today] and today or (today - 1)
    local streak = 0
    while h[d] and h[d] <= Wowdle.TRIES do
        streak = streak + 1
        d = d - 1
    end
    local best, run = 0, 0
    local days = {}
    for day in pairs(h) do days[#days + 1] = day end
    table.sort(days)
    local prev
    for _, day in ipairs(days) do
        if h[day] <= Wowdle.TRIES and prev and day == prev + 1 and run > 0 then
            run = run + 1
        elseif h[day] <= Wowdle.TRIES then
            run = 1
        else
            run = 0
        end
        best = math.max(best, run)
        prev = day
    end
    return { played = played, wins = wins, streak = streak, best = best, dist = dist }
end

-- The Discord-friendly squares (they show as boxes inside WoW, paste fine).
-- "Wowdle #12  4/6" (X/6 when missed).
function Wowdle:ScoreText()
    local cur = self:Current()
    local n = G().history[cur.day]
    return ("Wowdle #%d  %s/6"):format(self:Number(cur.day), (n and n <= Wowdle.TRIES) and n or "X")
end

-- Guild chat: just the score (the squares look odd in chat). Addons can't
-- post chat on Forever, so it goes into the chat box ready for Enter.
function Wowdle:PostScore()
    local text = "/g " .. self:ScoreText()
    if ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, text, DEFAULT_CHAT_FRAME)
    end
end

function Wowdle:ShareText()
    local cur = self:Current()
    local lines = { self:ScoreText() }
    local squares = { g = "\240\159\159\169", y = "\240\159\159\168", x = "\226\172\155" }
    for row in self:Pattern():gmatch("[gyx]+") do
        lines[#lines + 1] = (row:gsub("[gyx]", squares))
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- Guild results for today (shared)
------------------------------------------------------------------------
ns.Sync:Register({
    name = "wowdle", code = "w", order = 3,
    fields = { "day", "n", "pat" },
    numeric = { day = true, n = true },
    valid = function(rec)
        return rec.by == rec.author and rec.day ~= nil and rec.id == rec.author .. ":" .. rec.day and rec.n ~= nil
            and rec.n >= 1 and rec.n <= Wowdle.TRIES + 1 and type(rec.pat) == "string" and #rec.pat <= 60
            and rec.pat:match("^[gyx,]+$") ~= nil
    end,
    -- only today's board is shown (your own stats are kept locally), so the
    -- guild shares today and yesterday and nothing older
    prune = function(store)
        local cutoff = Wowdle:Day() - 1
        for id, rec in pairs(store) do
            if rec.day < cutoff then store[id] = nil end
        end
    end,
    expired = function(rec) return rec.day < Wowdle:Day() - 1 end,
    onChange = function() Wowdle:Refresh() end,
})

function Wowdle:Publish(day, n, pat)
    if not ns.Sync:GuildName() then return end
    local me = ns.Sync:Me()
    ns.Sync:Write("wowdle", { id = me .. ":" .. day, author = me, t = ns.Now(), day = day, n = n, pat = pat })
end

function Wowdle:Today()
    local day, out = self:Day(), {}
    for _, rec in pairs(ns.Sync:Store("wowdle") or {}) do
        if rec.day == day and not rec.deleted then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n < b.n end
        return a.t < b.t
    end)
    return out
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local PAD, GAP = 12, 8
local LEFT_W = 400
local TILE_MAX, TILE_GAP = 52, 6
local GRID_H = Wowdle.TRIES * TILE_MAX + (Wowdle.TRIES - 1) * TILE_GAP
local KEY_W, KEY_H, KEY_GAP = 32, 36, 4
local SIDE_X = PAD + LEFT_W + PAD
local SIDE_W = 902 - SIDE_X - PAD
local COLORS = { g = { 0.33, 0.66, 0.33 }, y = { 0.82, 0.66, 0.2 }, x = { 0.2, 0.2, 0.23 } }
-- The keyboard (Jake: make it clear which letters are still in play): a letter
-- not tried yet stands out, a letter ruled out sinks away.
Wowdle.KEY_OPEN = { fill = { 0.30, 0.30, 0.34, 0.95 }, edge = { 0.55, 0.53, 0.48, 1 } }
Wowdle.KEY_OUT = { fill = { 0.035, 0.035, 0.04, 0.95 }, edge = { 0.12, 0.12, 0.13, 1 }, alpha = 0.25 }
local ROWS = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }

local function square(c)
    local col = COLORS[c]
    return ("|TInterface\\Buttons\\WHITE8X8:12:12:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(col[1] * 255, col[2] * 255, col[3] * 255)
end

function Wowdle:Build(view, top, height)
    self.view = view
    self.typed = ""
    local grid = CreateFrame("Button", nil, view)
    self.gridTop = top
    grid:SetScript("OnClick", function() self.input:SetFocus() end)
    self.grid = grid
    self.tiles = {}
    for r = 1, Wowdle.TRIES do
        self.tiles[r] = {}
        for c = 1, Wowdle.MAX_LEN do
            local t = CreateFrame("Frame", nil, grid)
            t.bg = t:CreateTexture(nil, "BACKGROUND")
            t.bg:SetAllPoints()
            t.edge = CreateFrame("Frame", nil, t)
            t.edge:SetAllPoints()
            UI.Border(t.edge, { 1, 1, 1, 0.12 }, "OVERLAY")
            t.letter = UI.Text(t, 24)
            t.letter:SetPoint("CENTER", 0, 1)
            self.tiles[r][c] = t
        end
    end

    -- on-screen keyboard
    local ky = top + GRID_H + 12
    self.keys = {}
    for r, letters in ipairs(ROWS) do
        local count = #letters + (r == 3 and 2 or 0)
        local rowW = #letters * KEY_W + (count - 1) * KEY_GAP + (r == 3 and 2 * 52 or 0)
        local x = PAD + (LEFT_W - rowW) / 2
        local function key(label, w, fn)
            local b = UI.Button(view, label, w, KEY_H, fn)
            b:SetPoint("TOPLEFT", x, -(ky + (r - 1) * (KEY_H + KEY_GAP)))
            x = x + w + KEY_GAP
            return b
        end
        if r == 3 then self.enterKey = key("Enter", 52, function() self:Submit() end) end
        for i = 1, #letters do
            local ch = letters:sub(i, i)
            self.keys[ch] = key(ch, KEY_W, function() self:Type(ch) end)
        end
        if r == 3 then self.delKey = key("Del", 52, function() self:Type(nil) end) end
    end
    self.status = UI.Text(view, 12)
    self.status:SetPoint("TOP", view, "TOPLEFT", PAD + LEFT_W / 2, -(ky + 3 * KEY_H + 2 * KEY_GAP + 10))

    -- typing: a hidden edit box takes the keyboard while this page is open
    local input = CreateFrame("EditBox", nil, view)
    input:SetSize(1, 1)
    input:SetPoint("TOPLEFT", -100, 100)
    input:SetAutoFocus(false)
    input:SetFont(UI.FONT, 1, "")
    input:SetScript("OnTextChanged", function(box, userInput)
        if not userInput then return end
        local letters = box:GetText():upper():gsub("[^A-Z]", "")
        self.typed = letters:sub(1, self:Length())
        box:SetText(self.typed)
        self:RefreshGrid()
    end)
    input:SetScript("OnEnterPressed", function() self:Submit() end)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    self.input = input

    -- side: today in the guild, your stats
    local side = CreateFrame("Frame", nil, view)
    side:SetPoint("TOPLEFT", SIDE_X, -top)
    side:SetSize(SIDE_W, height)
    UI.Card(side)
    self.sideArt = ns.Art and ns.Art.Page("wowdle", side) -- faint game art (Art.PAGES)
    self.side = side
    side.title = UI.SectionTitle(side, "Today in the guild")
    side.title:SetPoint("TOPLEFT", 14, -12)
    side.number = UI.Text(side, 10)
    side.number:SetPoint("TOPRIGHT", -14, -13)
    side.number:SetTextColor(0.55, 0.55, 0.6)
    side.rows = {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, side)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 2, -(32 + (i - 1) * 22))
        row:SetPoint("TOPRIGHT", -2, -(32 + (i - 1) * 22))
        row:EnableMouse(true)
        row.mine = row:CreateTexture(nil, "BACKGROUND")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.16)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 14, 0)
        row.score = UI.Text(row, 12)
        row.score:SetPoint("RIGHT", -14, 0)
        row:SetScript("OnEnter", function(f)
            if not f.rec or not GameTooltip then return end
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Ambiguate(f.rec.author, "short"), 1, 1, 1)
            for line in f.rec.pat:gmatch("[gyx]+") do
                GameTooltip:AddLine((line:gsub("[gyx]", square)))
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        side.rows[i] = row
    end
    side.empty = UI.Text(side, 11)
    side.empty:SetPoint("TOPLEFT", 14, -36)
    side.empty:SetTextColor(0.5, 0.5, 0.55)
    side.empty:SetText("Nobody has finished today's word yet.")

    local sy = 32 + 10 * 22 + 12
    side.statsTitle = UI.SectionTitle(side, "Your stats")
    side.statsTitle:SetPoint("TOPLEFT", 14, -sy)
    side.stats = {}
    local labels = { "Played", "Win %", "Streak", "Best streak" }
    local sw = (SIDE_W - 28) / 4
    for i, label in ipairs(labels) do
        local s = CreateFrame("Frame", nil, side)
        s:SetSize(sw, 44)
        s:SetPoint("TOPLEFT", 14 + (i - 1) * sw, -(sy + 18))
        s.value = UI.Text(s, 20)
        s.value:SetPoint("TOP", 0, 0)
        s.label = UI.Text(s, 9)
        s.label:SetPoint("TOP", s.value, "BOTTOM", 0, -3)
        s.label:SetTextColor(0.55, 0.55, 0.6)
        s.label:SetText(label)
        side.stats[i] = s
    end
    side.bars = {}
    local barMax = SIDE_W - 28 - 40
    for i = 1, Wowdle.TRIES do
        local y = sy + 72 + (i - 1) * 20
        local n = UI.Text(side, 11)
        n:SetPoint("TOPLEFT", 16, -y)
        n:SetText(tostring(i))
        local bar = side:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("TOPLEFT", 32, -(y - 1))
        bar:SetHeight(14)
        bar:SetColorTexture(0.3, 0.3, 0.34, 1)
        local count = UI.Text(side, 10)
        count:SetPoint("LEFT", bar, "RIGHT", 6, 0)
        side.bars[i] = { bar = bar, count = count, max = barMax }
    end
    side.share = UI.Button(side, "Copy result", 110, 24, function()
        UI.CopyBox("Wowdle result (squares paste into Discord)", self:ShareText())
    end)
    side.share:SetPoint("BOTTOMRIGHT", -12, 12)
    side.post = UI.Button(side, "Post to guild", 110, 24, function() self:PostScore() end)
    side.post:SetPoint("RIGHT", side.share, "LEFT", -6, 0)
    view:SetScript("OnShow", function() if self:State() == "playing" then input:SetFocus() end end)
    -- leaving the page always gives the keyboard back
    view:SetScript("OnHide", function() input:ClearFocus() end)
end

function Wowdle:Type(ch)
    if self:State() ~= "playing" then return end
    if ch then
        if #self.typed < self:Length() then self.typed = self.typed .. ch end
    else
        self.typed = self.typed:sub(1, -2)
    end
    self.input:SetText(self.typed)
    self:RefreshGrid()
end

function Wowdle:Submit()
    if self:State() ~= "playing" then return end
    local err = self:Guess(self.typed)
    if err then
        self.flash = err
    else
        self.typed = ""
        self.input:SetText("")
        self.flash = nil
        if self:State() ~= "playing" then self.input:ClearFocus() end
    end
    self:Refresh()
end

-- Size and place the tiles for today's word length: tiles shrink so eight
-- letters still fit, and the grid stays centred over the keyboard.
function Wowdle:Layout(len)
    if self.layoutLen == len then return end
    self.layoutLen = len
    local tile = math.min(TILE_MAX, math.floor((LEFT_W - (len - 1) * TILE_GAP) / len))
    local w = len * tile + (len - 1) * TILE_GAP
    self.tileSize = tile
    self.grid:ClearAllPoints()
    self.grid:SetSize(w, GRID_H)
    self.grid:SetPoint("TOPLEFT", self.view, "TOPLEFT", PAD + (LEFT_W - w) / 2, -self.gridTop)
    local rowStep = (GRID_H - tile) / (Wowdle.TRIES - 1)
    for r = 1, Wowdle.TRIES do
        for c = 1, Wowdle.MAX_LEN do
            local t = self.tiles[r][c]
            t:ClearAllPoints()
            t:SetSize(tile, tile)
            t:SetPoint("TOPLEFT", (c - 1) * (tile + TILE_GAP), -((r - 1) * rowStep))
            t.letter:SetFont(UI.FONT, math.floor(tile * 0.46), "")
            t:SetShown(c <= len)
        end
    end
end

function Wowdle:RefreshGrid()
    if not self.tiles then return end
    local cur = self:Current()
    local word = self:Word(cur.day)
    self:Layout(#word)

    local known = {}
    for r = 1, Wowdle.TRIES do
        local guess = cur.guesses[r]
        local score = guess and Wowdle.Score(guess, word)
        local typing = not guess and r == #cur.guesses + 1 and self:State() == "playing"
        for c = 1, #word do
            local t = self.tiles[r][c]
            local ch = guess and guess:sub(c, c) or (typing and self.typed:sub(c, c)) or ""
            t.letter:SetText(ch)
            if score then
                local s = score:sub(c, c)
                local col = COLORS[s]
                t.bg:SetColorTexture(col[1], col[2], col[3], 1)
                UI.SetBorderColor(t.edge, { col[1], col[2], col[3], 1 })
                -- best knowledge per letter for the keyboard: g > y > x
                local rank = { g = 3, y = 2, x = 1 }
                if not known[ch] or rank[s] > rank[known[ch]] then known[ch] = s end
            else
                t.bg:SetColorTexture(0, 0, 0, 0.25)
                UI.SetBorderColor(t.edge, { 1, 1, 1, ch ~= "" and 0.45 or 0.12 })
            end
        end
    end
    for ch, b in pairs(self.keys) do
        local s = known[ch]
        if s == "x" then
            local k = Wowdle.KEY_OUT
            b.bg:SetColorTexture(k.fill[1], k.fill[2], k.fill[3], k.fill[4])
            UI.SetBorderColor(b, k.edge)
            b.label:SetAlpha(k.alpha)
        elseif s then
            local col = COLORS[s]
            b.bg:SetColorTexture(col[1], col[2], col[3], 1)
            UI.SetBorderColor(b, { col[1], col[2], col[3], 1 })
            b.label:SetAlpha(1)
        else
            local k = Wowdle.KEY_OPEN
            b.bg:SetColorTexture(k.fill[1], k.fill[2], k.fill[3], k.fill[4])
            UI.SetBorderColor(b, k.edge)
            b.label:SetAlpha(1)
        end
    end
end

function Wowdle:Refresh()
    if not self.view then return end
    self:RefreshGrid()
    local state = self:State()
    local cur = self:Current()
    if self.flash then
        self.status:SetText("|cffff8866" .. self.flash .. "|r")
    elseif state == "won" then
        self.status:SetText(("|cff66dd77Solved in %d!|r"):format(#cur.guesses))
    elseif state == "lost" then
        self.status:SetText(("The word was |cffffd200%s|r."):format(self:Word(cur.day)))
    else
        -- the word's length lives here, under the keyboard, clear of the game tabs
        self.status:SetText(("|cff8a8a92%d letters|r"):format(self:Length(cur.day)))
    end

    local side = self.side
    side.number:SetText("Wowdle #" .. self:Number(cur.day))
    local me = ns.Sync:Me()
    local list = self:Today()
    for i, row in ipairs(side.rows) do
        local rec = list[i]
        row.rec = rec
        if rec then
            local p = ns.db.guild.players[rec.author]
            local cc = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            row.name:SetText(Ambiguate(rec.author, "short"))
            if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) end
            local solved = rec.n <= Wowdle.TRIES
            row.score:SetText((solved and rec.n or "X") .. "/6")
            if solved then row.score:SetTextColor(0.4, 0.85, 0.45) else row.score:SetTextColor(0.95, 0.4, 0.35) end
            row.mine:SetShown(rec.author == me)
            row:Show()
        else
            row:Hide()
        end
    end
    side.empty:SetShown(#list == 0)

    local st = self:Stats()
    local values = { st.played, st.played > 0 and math.floor(100 * st.wins / st.played + 0.5) or 0, st.streak, st.best }
    for i, s in ipairs(side.stats) do s.value:SetText(tostring(values[i])) end
    local most = 1
    for _, n in ipairs(st.dist) do most = math.max(most, n) end
    local todayN = ns.db.games.wowdle.history[cur.day]
    for i, b in ipairs(side.bars) do
        local n = st.dist[i]
        b.bar:SetWidth(math.max(4, b.max * n / most))
        if todayN == i then b.bar:SetColorTexture(COLORS.g[1], COLORS.g[2], COLORS.g[3], 1) else b.bar:SetColorTexture(0.3, 0.3, 0.34, 1) end
        b.count:SetText(tostring(n))
    end
    side.share:SetEnabledState(state ~= "playing")
    side.post:SetEnabledState(state ~= "playing")
end
