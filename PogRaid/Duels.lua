-- Pog Raid ranked duels: chess-style ratings for duels between guildies.
--
-- 1. The challenger asks (addon whisper "D1"); the other player gets a
--    pop-up and accepts or declines ("D2"). Only then is the duel ranked.
-- 2. The challenger sends the normal WoW duel. When the game announces the
--    result ("X has defeated Y in a duel", "Y has fled from X in a duel"),
--    each player's addon records it as a report, shared through Sync.
-- 3. A match counts once both players' reports agree. Every addon replays
--    the confirmed matches in order (Elo, start 1200, K = 32), so everyone
--    sees the same ratings.
local _, ns = ...
local UI = ns.UI

local Duels = {}
ns.Duels = Duels

Duels.START = 1200
Duels.K = 32
Duels.ANSWER_WAIT = 60      -- seconds to answer a challenge
Duels.AGREED_FOR = 300      -- an agreement lasts this long without a duel

local function me() return ns.Sync:Me() end
local function key(name) return ns.Attendance:Key(name) end
local function short(name) return name and Ambiguate(name, "short") end
local function same(a, b) return ns.SameName(a, b) end

------------------------------------------------------------------------
-- Shared reports
------------------------------------------------------------------------
ns.Sync:Register({
    name = "duels", code = "d", order = 4,
    fields = { "match", "a", "b", "winner" },
    perRecord = true, -- each report may confirm the player's own match
    valid = function(rec)
        return rec.by == rec.author and rec.match ~= nil and rec.a ~= nil and rec.b ~= nil and rec.a ~= rec.b
            and (rec.author == rec.a or rec.author == rec.b) and (rec.winner == rec.a or rec.winner == rec.b)
            and rec.id == rec.match .. ":" .. rec.author
    end,
    onChange = function(rec) Duels:OnReport(rec) end,
})

-- Elo: expected score and the new ratings after a result.
function Duels.Expected(ra, rb)
    return 1 / (1 + 10 ^ ((rb - ra) / 400))
end

function Duels.Update(ra, rb, aWon)
    local ea = Duels.Expected(ra, rb)
    local sa = aWon and 1 or 0
    local na = ra + Duels.K * (sa - ea)
    local nb = rb + Duels.K * ((1 - sa) - (1 - ea))
    return na, nb
end

-- Matches both players reported the same way, oldest first.
function Duels:Confirmed()
    local byMatch = {}
    for _, rec in pairs(ns.Sync:Store("duels") or {}) do
        if not rec.deleted then
            local m = byMatch[rec.match]
            if not m then
                m = { reports = {} }
                byMatch[rec.match] = m
            end
            m.reports[rec.author] = rec
        end
    end
    local out = {}
    for id, m in pairs(byMatch) do
        local any
        for _, r in pairs(m.reports) do any = r break end
        local ra, rb = m.reports[any.a], m.reports[any.b]
        if ra and rb and ra.winner == rb.winner and ra.a == rb.a and ra.b == rb.b then
            out[#out + 1] = { id = id, t = ra.t, a = ra.a, b = ra.b, winner = ra.winner }
        end
    end
    table.sort(out, function(x, y)
        if x.t ~= y.t then return x.t < y.t end
        return x.id < y.id
    end)
    return out
end

-- Replays every confirmed match. Cached until a report arrives.
function Duels:Table()
    if self.cache then return self.cache end
    local players, history = {}, {}
    local function player(name)
        local p = players[name]
        if not p then
            p = { name = name, rating = Duels.START, wins = 0, losses = 0 }
            players[name] = p
        end
        return p
    end
    for _, m in ipairs(self:Confirmed()) do
        local pa, pb = player(m.a), player(m.b)
        local aWon = m.winner == m.a
        local oldA, oldB = pa.rating, pb.rating
        pa.rating, pb.rating = Duels.Update(pa.rating, pb.rating, aWon)
        local w, l = aWon and pa or pb, aWon and pb or pa
        w.wins, l.losses = w.wins + 1, l.losses + 1
        history[#history + 1] = { t = m.t, winner = w.name, loser = l.name,
            gain = (aWon and pa.rating - oldA or pb.rating - oldB) }
    end
    local list = {}
    for _, p in pairs(players) do list[#list + 1] = p end
    table.sort(list, function(x, y)
        if math.floor(x.rating + 0.5) ~= math.floor(y.rating + 0.5) then return x.rating > y.rating end
        local gx, gy = x.wins + x.losses, y.wins + y.losses
        if gx ~= gy then return gx > gy end
        return x.name < y.name
    end)
    for i, p in ipairs(list) do p.rank = i end
    self.cache = { players = players, list = list, history = history }
    return self.cache
end

function Duels:Rating(name)
    local p = self:Table().players[name]
    return p and p.rating or Duels.START
end

function Duels:OnReport(rec)
    local before = self.cache and self.cache.players[me()]
    local beforeRating = before and before.rating or Duels.START
    self.cache = nil
    -- tell the player once their own match is confirmed by both sides
    if (rec.a == me() or rec.b == me()) and not (self.announced or {})[rec.match] then
        for _, m in ipairs(self:Confirmed()) do
            if m.id == rec.match then
                self.announced = self.announced or {}
                self.announced[rec.match] = true
                local now = self:Rating(me())
                local won = m.winner == me()
                ns.Print(("ranked duel %s: %d -> %d (%s%d)"):format(won and "won" or "lost", math.floor(beforeRating + 0.5),
                    math.floor(now + 0.5), won and "+" or "", math.floor(now + 0.5) - math.floor(beforeRating + 0.5)))
            end
        end
    end
    self:Refresh()
end

------------------------------------------------------------------------
-- Challenges (addon whispers)
------------------------------------------------------------------------
Duels.outgoing = nil   -- { id, opp, t, state = "asked" }
Duels.agreed = nil     -- { id, opp, challenger, t, expires }

local function whisper(text, name)
    ns.Comm.Send(text, "WHISPER", Ambiguate(name, "none"))
end

function Duels:Busy()
    if self.agreed and ns.Now() > self.agreed.expires then self.agreed = nil end
    return self.outgoing ~= nil or self.agreed ~= nil
end

function Duels:Challenge(name)
    if not name or same(name, me()) then return false end
    if self:Busy() then
        ns.Print("you already have a ranked duel lined up")
        return false
    end
    local id, t = ns.NewId(), ns.Now()
    self.outgoing = { id = id, opp = key(name), t = t }
    whisper(("D1%d:%s"):format(t, id), name)
    ns.Print(("ranked duel challenge sent to %s"):format(short(name)))
    local o = self.outgoing
    C_Timer.After(Duels.ANSWER_WAIT, function()
        if self.outgoing == o then
            self.outgoing = nil
            ns.Print(("%s didn't answer (they may not have Pog Guild Tools)"):format(short(name)))
            self:Refresh()
        end
    end)
    self:Refresh()
    return true
end

function Duels:OnMessage(sender, text)
    local op = text:sub(2, 2)
    if op == "1" then
        local t, id = text:match("^D1(%d+):(.+)$")
        if not id then return end
        -- busy, or challenges turned off in Settings: decline straight away
        if self:Busy() or (ns.DuelPopup and ns.DuelPopup.current) or ns.db.settings.duelChallenges == false then
            whisper("D20" .. id, sender)
            return
        end
        if ns.DuelPopup then ns.DuelPopup:Ask(key(sender), id, tonumber(t)) end
    elseif op == "2" then
        local ok, id = text:sub(3, 3) == "1", text:sub(4)
        local o = self.outgoing
        if not o or o.id ~= id or not same(o.opp, sender) then return end
        self.outgoing = nil
        if ok then
            self.agreed = { id = id, opp = o.opp, challenger = me(), t = o.t, expires = ns.Now() + Duels.AGREED_FOR }
            ns.Print(("%s accepted: send the duel from the Ranked Duels page"):format(short(sender)))
        else
            ns.Print(("%s declined the ranked duel"):format(short(sender)))
        end
        self:Refresh()
    end
end

function Duels:Answer(from, id, t, accept)
    whisper("D2" .. (accept and "1" or "0") .. id, from)
    if accept then
        self.agreed = { id = id, opp = from, challenger = from, t = t or ns.Now(), expires = ns.Now() + Duels.AGREED_FOR }
        ns.Print(("ranked duel agreed with %s: they'll send the duel"):format(short(from)))
    end
    self:Refresh()
end

-- The challenger's button: send the real duel.
function Duels:SendDuel()
    local a = self.agreed
    if not a then return end
    local ok = pcall(StartDuel, Ambiguate(a.opp, "none"))
    if not ok then ns.Print("couldn't send the duel automatically: target them and duel as usual") end
end

------------------------------------------------------------------------
-- Results from the game's duel announcement
------------------------------------------------------------------------
local function pattern(fmt)
    if not fmt then return nil end
    local order = {}
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%(%d)%%%$s", function(n) order[#order + 1] = tonumber(n) return "(.+)" end)
    p = p:gsub("%%s", function() order[#order + 1] = #order + 1 return "(.+)" end)
    return "^" .. p .. "$", order
end

-- Returns winner, loser from a duel announcement, or nil.
function Duels:ParseResult(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
    for _, fmt in ipairs({ DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT }) do
        local p, order = pattern(fmt)
        if p then
            local caps = { msg:match(p) }
            if #caps == 2 then
                local byArg = {}
                for i, argN in ipairs(order) do byArg[argN] = caps[i] end
                return byArg[1], byArg[2]    -- %1$s is the winner in both messages
            end
        end
    end
end

function Duels:OnSystem(msg)
    local winner, loser = self:ParseResult(msg)
    local a = self.agreed
    if not winner or not a then return end
    if ns.Now() > a.expires then
        self.agreed = nil
        return
    end
    local mine = same(winner, me()) or same(loser, me())
    local theirs = same(winner, a.opp) or same(loser, a.opp)
    if not (mine and theirs) then return end
    self.agreed = nil
    local challenger = a.challenger
    local other = challenger == me() and a.opp or me()
    local winnerKey = same(winner, me()) and me() or a.opp
    ns.Sync:Write("duels", { id = a.id .. ":" .. me(), author = me(), t = a.t, match = a.id,
        a = challenger, b = other, winner = winnerKey })
    ns.Print(("ranked duel %s, waiting for %s's addon to confirm"):format(winnerKey == me() and "won" or "lost", short(a.opp)))
    self:Refresh()
end

------------------------------------------------------------------------
-- Ranked Duels page (lives inside the Games tab)
------------------------------------------------------------------------
local PAD, GAP = 12, 8
local LEFT_W, RX = 262, 286
local RW = 902 - RX - PAD
local ROW_H = 22
local HISTORY_ROWS = 8

local function classColor(name)
    local p = ns.db.guild.players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.93
end

local function colorName(name)
    local r, g, b = classColor(name)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, short(name))
end

function Duels:Build(view, top, height)
    self.view = view
    -- your card
    local card = CreateFrame("Frame", nil, view)
    card:SetPoint("TOPLEFT", PAD, -top)
    card:SetSize(LEFT_W, height)
    UI.Card(card)
    self.card = card
    card.title = UI.SectionTitle(card, "Your rating")
    card.title:SetPoint("TOPLEFT", 12, -12)
    card.rating = UI.Text(card, 32)
    card.rating:SetPoint("TOPLEFT", 12, -28)
    card.rank = UI.Text(card, 11)
    card.rank:SetPoint("TOPLEFT", 14, -68)
    card.rank:SetTextColor(0.6, 0.6, 0.65)
    card.record = UI.Text(card, 12)
    card.record:SetPoint("TOPLEFT", 14, -86)

    card.challengeTarget = UI.Button(card, "Challenge your target", LEFT_W - 24, 24, function()
        local name = UnitExists and UnitExists("target") and UnitIsPlayer("target") and UnitName("target")
        if not name then
            ns.Print("target a guildie first")
            return
        end
        self:Challenge(name)
    end)
    card.challengeTarget:SetPoint("TOPLEFT", 12, -114)
    card.challengeOnline = UI.Button(card, "Challenge someone online", LEFT_W - 24, 24, function(b)
        local menu = {}
        for _, name in ipairs(ns.Home and ns.Home:OnlineList() or {}) do
            if name ~= me() then
                local r, g, bl = classColor(name)
                menu[#menu + 1] = { text = short(name) .. ("  |cff8a8a92%d|r"):format(math.floor(self:Rating(name) + 0.5)),
                    color = { r, g, bl }, func = function() self:Challenge(name) end }
            end
        end
        if #menu == 0 then menu[1] = { text = "Nobody else is online", disabled = true } end
        UI.ShowMenu(b, menu)
    end)
    card.challengeOnline:SetPoint("TOPLEFT", 12, -144)
    card.status = UI.Text(card, 11)
    card.status:SetPoint("TOPLEFT", 14, -180)
    card.status:SetWidth(LEFT_W - 28)
    card.status:SetJustifyH("LEFT")
    card.status:SetTextColor(0.85, 0.85, 0.9)
    card.send = UI.Button(card, "Send duel", LEFT_W - 24, 24, function() self:SendDuel() end)
    card.send:SetPoint("TOPLEFT", 12, -204)
    card.send:SetPrimary()

    card.histTitle = UI.SectionTitle(card, "Recent matches")
    card.histTitle:SetPoint("TOPLEFT", 12, -244)
    card.hist = {}
    for i = 1, HISTORY_ROWS do
        local row = CreateFrame("Frame", nil, card)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 4, -(260 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -4, -(260 + (i - 1) * ROW_H))
        row.text = UI.Text(row, 11)
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetWordWrap(false)
        row.delta = UI.Text(row, 11)
        row.delta:SetPoint("RIGHT", -8, 0)
        card.hist[i] = row
    end
    card.histEmpty = UI.Text(card, 11)
    card.histEmpty:SetPoint("TOPLEFT", 14, -262)
    card.histEmpty:SetTextColor(0.5, 0.5, 0.55)
    card.histEmpty:SetText("No ranked duels yet.")

    -- leaderboard
    local board = CreateFrame("Frame", nil, view)
    board:SetPoint("TOPLEFT", RX, -top)
    board:SetSize(RW, height)
    UI.Card(board)
    self.boardArt = ns.Art and ns.Art.Page("duels", board) -- faint game art (Art.PAGES)
    board:EnableMouseWheel(true)
    board:SetScript("OnMouseWheel", function(_, d)
        self.offset = (self.offset or 0) - d * 3
        self:Refresh()
    end)
    self.board = board
    local cols = {
        { "#", 36, "RIGHT" }, { "Player", 52, "LEFT" }, { "Rating", 380, "RIGHT" },
        { "W-L", 470, "RIGHT" }, { "Win %", 560, "RIGHT" },
    }
    board.cols = cols
    for _, c in ipairs(cols) do
        local fs = UI.SectionTitle(board, c[1])
        if c[3] == "RIGHT" then fs:SetPoint("RIGHT", board, "TOPLEFT", c[2], -14) else fs:SetPoint("LEFT", board, "TOPLEFT", c[2], -14) end
    end
    local line = board:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -28)
    line:SetPoint("TOPRIGHT", -1, -28)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    board.rows = {}
    board.visible = math.floor((height - 34) / ROW_H)
    for i = 1, board.visible do
        local row = CreateFrame("Frame", nil, board)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(32 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(32 + (i - 1) * ROW_H))
        row.mine = row:CreateTexture(nil, "BACKGROUND")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.16)
        row.cells = {}
        for c, col in ipairs(cols) do
            local fs = UI.Text(row, 12)
            if col[3] == "RIGHT" then fs:SetPoint("RIGHT", row, "LEFT", col[2] - 2, 0) else fs:SetPoint("LEFT", row, "LEFT", col[2] - 2, 0) end
            row.cells[c] = fs
        end
        board.rows[i] = row
    end
    board.hint = UI.ScrollHint(board, 32, 2)
    board.empty = UI.Text(board, 11)
    board.empty:SetPoint("TOP", 0, -56)
    board.empty:SetTextColor(0.5, 0.5, 0.55)
    board.empty:SetText("No ranked duels yet.")
end

local MEDALS = { { 1, 0.82, 0.2 }, { 0.8, 0.82, 0.88 }, { 0.85, 0.55, 0.3 } }

function Duels:Refresh()
    if not self.view or not self.view:IsShown() then return end
    local tbl = self:Table()
    local mine = tbl.players[me()]
    local card = self.card
    card.rating:SetText(tostring(math.floor((mine and mine.rating or Duels.START) + 0.5)))
    card.rank:SetText(mine and ("Rank #%d of %d"):format(mine.rank, #tbl.list) or "Unranked")
    local w, l = mine and mine.wins or 0, mine and mine.losses or 0
    card.record:SetText(("%d W  %d L%s"):format(w, l, (w + l) > 0 and ("  (%d%%)"):format(math.floor(100 * w / (w + l) + 0.5)) or ""))

    -- status of a challenge in progress
    self:Busy()
    local status, canSend = "", false
    if self.outgoing then
        status = ("Waiting for %s to answer..."):format(colorName(self.outgoing.opp))
    elseif self.agreed then
        if self.agreed.challenger == me() then
            status = ("%s agreed. Send the duel:"):format(colorName(self.agreed.opp))
            canSend = true
        else
            status = ("Ranked duel agreed with %s. Accept their duel when it comes."):format(colorName(self.agreed.opp))
        end
    end
    card.status:SetText(status)
    card.send:SetShown(canSend)
    card.challengeTarget:SetEnabledState(not self:Busy())
    card.challengeOnline:SetEnabledState(not self:Busy())

    -- my recent matches
    local hist = {}
    for i = #tbl.history, 1, -1 do
        local h = tbl.history[i]
        if h.winner == me() or h.loser == me() then hist[#hist + 1] = h end
        if #hist >= HISTORY_ROWS then break end
    end
    for i, row in ipairs(card.hist) do
        local h = hist[i]
        if h then
            local won = h.winner == me()
            row.text:SetText((won and "Beat " or "Lost to ") .. colorName(won and h.loser or h.winner))
            local d = math.floor(math.abs(h.gain) + 0.5)
            row.delta:SetText((won and "+" or "-") .. d)
            if won then row.delta:SetTextColor(0.4, 0.85, 0.45) else row.delta:SetTextColor(0.95, 0.4, 0.35) end
            row:Show()
        else
            row:Hide()
        end
    end
    card.histEmpty:SetShown(#hist == 0)

    -- leaderboard
    local board = self.board
    local list = tbl.list
    self.offset = math.max(0, math.min(self.offset or 0, #list - board.visible))
    board.hint:Set(self.offset, board.visible, #list)
    for i, row in ipairs(board.rows) do
        local p = list[i + self.offset]
        if p then
            local rank = i + self.offset
            local games = p.wins + p.losses
            row.cells[1]:SetText(rank .. ".")
            local medal = MEDALS[rank]
            if medal then row.cells[1]:SetTextColor(medal[1], medal[2], medal[3]) else row.cells[1]:SetTextColor(0.6, 0.6, 0.65) end
            row.cells[2]:SetText(short(p.name))
            row.cells[2]:SetTextColor(classColor(p.name))
            row.cells[3]:SetText(tostring(math.floor(p.rating + 0.5)))
            row.cells[4]:SetText(p.wins .. "-" .. p.losses)
            row.cells[4]:SetTextColor(0.75, 0.75, 0.8)
            row.cells[5]:SetText(games > 0 and (math.floor(100 * p.wins / games + 0.5) .. "%") or "-")
            row.cells[5]:SetTextColor(0.75, 0.75, 0.8)
            row.mine:SetShown(p.name == me())
            row:Show()
        else
            row:Hide()
        end
    end
    board.empty:SetShown(#list == 0)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
ns.On("CHAT_MSG_SYSTEM", function(msg) Duels:OnSystem(msg) end)
ns.On("DUEL_REQUESTED", function(name)
    local a = Duels.agreed
    if a and same(name, a.opp) then ns.Print("this is your ranked duel, accept it to play") end
end)

------------------------------------------------------------------------
-- Challenge pop-up: "Keeb (1216) challenges you to a ranked duel"
------------------------------------------------------------------------
local Popup = {}
ns.DuelPopup = Popup

function Popup:Build()
    local f = CreateFrame("Frame", "PogRaidDuelPopup", UIParent)
    f:SetSize(380, 64)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("TOP", 0, -210)
    f:EnableMouse(true)
    UI.Panel(f, { 0.05, 0.06, 0.07, 0.97 }, UI.ACCENT)
    UI.MakeMovable(f, f)
    f.text = UI.Text(f, 12)
    f.text:SetPoint("TOPLEFT", 12, -10)
    f.text:SetPoint("TOPRIGHT", -12, -10)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.no = UI.Button(f, "Decline", 90, 22, function() self:Answer(false) end)
    f.no:SetPoint("BOTTOMRIGHT", -10, 9)
    f.yes = UI.Button(f, "Accept", 90, 22, function() self:Answer(true) end)
    f.yes:SetPoint("RIGHT", f.no, "LEFT", -6, 0)
    f.yes:SetPrimary()
    f:Hide()
    self.frame = f
end

function Popup:Ask(from, id, t)
    if not self.frame then self:Build() end
    local ask = { from = from, id = id, t = t }
    self.current = ask
    self.frame.text:SetText(("%s (%d) challenges you to a ranked duel"):format(colorName(from),
        math.floor(Duels:Rating(from) + 0.5)))
    self.frame:Show()
    ns.Sound("IG_PLAYER_INVITE")
    -- no answer in time counts as a decline
    C_Timer.After(Duels.ANSWER_WAIT - 5, function()
        if self.current == ask then self:Answer(false) end
    end)
end

function Popup:Answer(accept)
    local c = self.current
    self.current = nil
    if self.frame then self.frame:Hide() end
    if c then Duels:Answer(c.from, c.id, c.t, accept) end
end
