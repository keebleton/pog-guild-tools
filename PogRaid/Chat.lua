-- Pog Guild Tools group chat: small conversations between guildies who run
-- the addon, in a window of their own (Jake: like AIM / MSN).
--
-- A chat is its set of people; there is nothing to create or join. Each line
-- is whispered addon to addon to everyone else in the chat who is online
-- (kind "C", chunked like raid plans), carrying the names of the others, so
-- whoever gets a line knows the whole chat. Nobody outside it receives
-- anything. History stays on this computer (per guild).
--
-- Wire (inside chunked "C" payloads):
--   M<n:2><names, comma separated, n bytes><text>   a line; names = everyone but the sender
--   N                                                "I have chat turned off"
-- Text is shown with its "|" escaped, so a line can't carry colours, textures
-- or links (no way to dress a message up as something else).
--
-- Whispers (0.16.7, Jake): the game's own whispers to and from guildmates are
-- kept in the one-to-one chat with them too (lines marked `w`), and a line
-- typed to a guildmate without chat goes out as an ordinary whisper. So the
-- window works with the whole guild, not just who has the addon. A whisper's
-- text is the game's own (the client has checked it), so it is shown as it
-- came, item links and all.
local _, ns = ...
local UI = ns.UI

local Chat = {}
ns.Chat = Chat

Chat.MIN_VERSION = "0.16.5" -- older addons don't answer chat
Chat.MAX_MEMBERS = 8        -- people in one chat, us included (each line is a whisper to every other one)
Chat.MAX_TEXT = 200
Chat.KEEP_LINES = 200       -- per chat
Chat.KEEP_CHATS = 30
Chat.off = {}               -- name -> GetTime() they told us chat is off (this session)
Chat.picked = {}            -- people ticked in the New chat picker
Chat.pending = {}           -- name -> id of a whisper of ours not yet seen going out
Chat.WHISPER_WAIT = 4       -- seconds to see it go before saying it didn't

local function G() return ns.db.guild end
local function me() return ns.Sync:Me() end
local function first(name)
    local s = Ambiguate(name, "short")
    return s:match("^(%S+)") or s
end
local function colored(name, label)
    local p = G().players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, label or first(name)) end
    return label or first(name)
end
local function esc(s) return (tostring(s):gsub("|", "||")) end
local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function clean(text)
    text = tostring(text or ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, Chat.MAX_TEXT)
end

function Chat:Enabled() return ns.db.settings.chat ~= false end
-- Guildmates' whispers are kept in chats, and lines can go out as whispers.
function Chat:Whispers() return self:Enabled() and ns.db.settings.chatWhispers ~= false end

------------------------------------------------------------------------
-- Chats (saved per guild): key = its people, sorted
------------------------------------------------------------------------
function Chat:Store()
    local g = G()
    g.chats = g.chats or {}
    return g.chats
end

function Chat.Key(members)
    local sorted = {}
    for i, n in ipairs(members) do sorted[i] = n end
    table.sort(sorted)
    return table.concat(sorted, ","), sorted
end

-- Newest first.
function Chat:List()
    local out = {}
    for _, c in pairs(self:Store()) do out[#out + 1] = c end
    table.sort(out, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.key < b.key
    end)
    return out
end

-- The chat between these people (us included), made if `create`.
function Chat:Get(members, create)
    local key, sorted = Chat.Key(members)
    local store = self:Store()
    local c = store[key]
    if not c and create then
        c = { key = key, members = sorted, log = {}, last = ns.Now(), unread = 0 }
        store[key] = c
        local all = self:List()
        for i = Chat.KEEP_CHATS + 1, #all do
            if all[i] ~= self.current then store[all[i].key] = nil end
        end
    end
    return c
end

function Chat:Delete(c)
    self:Store()[c.key] = nil
    if self.current == c then self.current = nil end
    self:Badge()
    self:Refresh()
end

local function add(c, from, text, sys)
    local line = { t = ns.Now(), from = from, text = text, sys = sys or nil }
    c.log[#c.log + 1] = line
    while #c.log > Chat.KEEP_LINES do table.remove(c.log, 1) end
    c.last = line.t
    return line
end

-- Everyone in the chat but us.
function Chat:Others(c)
    local out = {}
    for _, n in ipairs(c.members) do
        if n ~= me() then out[#out + 1] = n end
    end
    return out
end

-- "Flyne, Mira" (class coloured unless `plain`).
function Chat:Title(c, plain)
    local names = {}
    for i, n in ipairs(self:Others(c)) do names[i] = plain and first(n) or colored(n) end
    return table.concat(names, ", ")
end

function Chat:Unread()
    local n = 0
    for _, c in pairs(self:Store()) do n = n + (c.unread or 0) end
    return n
end

------------------------------------------------------------------------
-- Who can be chatted with. Addon lines reach someone on a version with chat
-- who hasn't turned it off (HasChat); anyone else in the guild can still be
-- whispered, one to one. Either way they have to be online.
------------------------------------------------------------------------
function Chat:HasChat(name)
    if not name or name == me() or self.off[name] then return false end
    local saved = ns.db.versions and ns.db.versions[name]
    local v = ns.Version.dev[name] or ns.Version.seen[name] or (saved and saved.v)
    local c = v and ns.Version.Compare(v, Chat.MIN_VERSION)
    return c == 0 or c == 1
end

function Chat:CanChat(name)
    if not self:Enabled() or not name or name == me() or not ns.Roster.online[name] then return false end
    if self:HasChat(name) then return true end
    local p = G().players[name]
    return self:Whispers() and p ~= nil and p.inGuild == true
end

-- Who's online to chat with: those with chat first, then the whisper-only.
function Chat:Buddies()
    local out = {}
    for name in pairs(ns.Roster.online) do
        if G().players[name] and self:CanChat(name) then out[#out + 1] = name end
    end
    table.sort(out, function(a, b)
        local ca, cb = self:HasChat(a), self:HasChat(b)
        if ca ~= cb then return ca end
        return a < b
    end)
    return out
end

------------------------------------------------------------------------
-- Sending and receiving
------------------------------------------------------------------------
local function whisper(payload, name)
    ns.Comm.SendChunked("C", payload, "WHISPER", Ambiguate(name, "none"))
end

function Chat:Send(c, text)
    if not self:Enabled() or not c then return false end
    text = clean(text)
    if text == "" then return false end
    local others = self:Others(c)
    -- one to one with someone the addon can't reach: an ordinary whisper
    if not c.test and #others == 1 and ns.Roster.online[others[1]] and not self:HasChat(others[1]) and self:Whispers() then
        return self:SendWhisper(c, others[1], text)
    end
    local list = table.concat(others, ",")
    local payload = "M" .. ns.Sync.Enc(#list, 2) .. list .. text
    local sent, off = 0, nil
    for _, to in ipairs(others) do
        if c.test or not ns.Roster.online[to] then
            -- (nobody to send it to)
        elseif self.off[to] then
            off = off or to
        else
            whisper(payload, to)
            sent = sent + 1
        end
    end
    local line = add(c, me(), text)
    self:Changed(c, line)
    if c.test then
        C_Timer.After(Chat.TEST_DELAY, function() self:TestReply(c) end)
    elseif sent == 0 then
        self:Changed(c, add(c, nil, off and ("Not sent: %s has chat turned off."):format(first(off))
            or "Nobody in this chat is online right now.", true))
    end
    return true
end

-- A line to a guildmate as the game's own whisper. The line isn't added
-- here: the game tells us when our whisper went (OnWhisper), which is the
-- one place whispers are logged, typed here or in the game's chat box. If it
-- never does, the game refused it, and the chat says so. Returns false (the
-- text stays in the box) when it can't be tried at all.
function Chat:SendWhisper(c, to, text)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send or ns.Comm.IsRestricted() then
        self:Changed(c, add(c, nil, "Whispers can't be sent from here right now. Use the game's chat box.", true))
        return false
    end
    self.whisperId = (self.whisperId or 0) + 1
    local id = self.whisperId
    self.pending[to] = id
    -- ("|" starts the game's colour and link codes: a bare one is refused)
    local ok = pcall(send, (text:gsub("|", "||")), "WHISPER", nil, Ambiguate(to, "none"))
    if not ok then self.pending[to] = nil end
    local function failed()
        if ok and self.pending[to] ~= id then return end
        self.pending[to] = nil
        if self:Store()[c.key] == c then
            self:Changed(c, add(c, nil, ("That didn't reach %s. Whisper them from the game's chat box."):format(first(to)), true))
        end
    end
    if ok then C_Timer.After(Chat.WHISPER_WAIT, failed) else failed() end
    return ok
end

-- The game's own whisper, to us (`incoming`) or from us, with a guildmate:
-- kept in the chat with them. No pop-up or sound: the game has shown it.
function Chat:OnWhisper(text, who, incoming)
    if not self:Whispers() or type(text) ~= "string" or type(who) ~= "string" or secret(text) or secret(who) then return end
    local name = ns.Attendance:Key(who)
    local p = G().players[name]
    if text == "" or not p or not p.inGuild or name == me() then return end
    if not incoming then self.pending[name] = nil end
    local c = self:Get({ me(), name }, true)
    c.test, c.testAt = nil, nil
    local line = add(c, incoming and name or me(), text)
    line.w = true
    if not incoming then
        c.unread = 0 -- (answered: read)
    elseif not self:Watching(c) then
        c.unread = (c.unread or 0) + 1
    end
    self:Badge()
    self:Changed(c, line)
end

-- /pog chat test: a practice chat with someone from the guild list who
-- answers back, to see the window and the pop-up without a second person.
-- Nothing is sent to anyone; right-click the chat to delete it.
Chat.TEST_DELAY = 3 -- seconds before the answer: time to close the window and see the pop-up
Chat.TEST_LINES = { "hey! this is a practice chat", "send a line, then close the window to see the pop-up",
    "nothing here is sent to anyone", "right-click this chat on the left to delete it" }

function Chat:Test()
    if not self:Enabled() then
        ns.Print("group chat is turned off in Settings")
        return
    end
    -- someone we have no real chat with (their real lines would land in this one)
    local who
    for name, p in pairs(G().players) do
        local c = self:Get({ me(), name })
        if p.inGuild and name ~= me() and (not c or c.test) and (not who or name < who) then who = name end
    end
    if not who then
        ns.Print("the practice chat needs a guildie you have no chat with yet")
        return
    end
    local c = self:Get({ me(), who }, true)
    -- (said once: asking for the practice chat again just carries it on)
    if not c.test then self:Changed(c, add(c, nil, "Practice chat: nothing here is sent to anyone.", true)) end
    c.test = true
    self:Open(c, true)
    self:TestReply(c)
end

function Chat:TestReply(c)
    if not c.test or self:Store()[c.key] ~= c then return end
    c.testAt = (c.testAt or 0) % #Chat.TEST_LINES + 1
    self:Received(c, add(c, self:Others(c)[1], Chat.TEST_LINES[c.testAt]))
end

-- Tell someone who wrote to us that chat is off here (once a minute at most).
function Chat:SayOff(to)
    self.saidOff = self.saidOff or {}
    local last = self.saidOff[to]
    if last and GetTime() - last < 60 then return end
    self.saidOff[to] = GetTime()
    whisper("N", to)
end

function Chat:OnOff(from)
    local told = self.off[from]
    self.off[from] = GetTime()
    self.picked[from] = nil
    if not told then
        for _, c in pairs(self:Store()) do
            for _, n in ipairs(c.members) do
                if n == from then self:Changed(c, add(c, nil, first(from) .. " has chat turned off.", true)) end
            end
        end
    end
    self:Refresh()
end

function Chat:OnMessage(sender, payload)
    if type(payload) ~= "string" then return end
    local from = ns.Attendance:Key(sender)
    local p = G().players[from]
    if not p or not p.inGuild or from == me() then return end
    local op = payload:sub(1, 1)
    if op == "N" then return self:OnOff(from) end
    if op ~= "M" then return end
    local n = ns.Sync.Dec(payload, 2, 2)
    if not n or n < 1 or #payload < 3 + n then return end
    local text = clean(payload:sub(4 + n))
    if text == "" then return end
    local members, seen, mine = { from }, { [from] = true }, false
    for name in payload:sub(4, 3 + n):gmatch("[^,]+") do
        if #name > 48 or name:find("%c") or seen[name] then return end
        seen[name] = true
        members[#members + 1] = name
        if name == me() then mine = true end
    end
    if not mine or #members > Chat.MAX_MEMBERS then return end
    if not self:Enabled() then return self:SayOff(from) end
    self.off[from] = nil
    local c = self:Get(members, true)
    c.test, c.testAt = nil, nil -- (a real line: no longer the practice chat)
    self:Received(c, add(c, from, text))
end

-- Someone's line was added to `c`: unread, with a sound and a pop-up, unless
-- that chat is open in front of us.
function Chat:Received(c, line)
    if not self:Watching(c) then
        c.unread = (c.unread or 0) + 1
        self:Notify(c, line)
        self:Badge()
    end
    self:Changed(c, line)
end

-- Is `c` open in front of us? (Not while the New chat picker is over it.)
function Chat:Watching(c)
    return self.frame ~= nil and self.frame:IsShown() and self.current == c and not self.picking
end

-- Home's Chat button counts unread lines.
function Chat:Badge()
    if ns.Home then ns.Home:Changed() end
end

-- A line arrived in a chat we aren't looking at: a sound and a pop-up.
function Chat:Notify(c, line)
    ns.Sound("TELL_MESSAGE")
    if not (ns.GroupToast and ns.GroupToast.Note) then return end
    local text = line.text
    if #text > 80 then text = text:sub(1, 77) .. "..." end
    ns.GroupToast:Note({
        icon = ns.Profiles and ns.Profiles:Portrait(line.from) or 134400,
        text = colored(line.from) .. ": " .. esc(text),
        sub = #c.members > 2 and ("Chat with " .. self:Title(c, true)) or "Click to reply",
        onClick = function() self:Open(c, true) end,
    })
end

------------------------------------------------------------------------
-- The window: chats and who's online on the left, the open chat on the right
------------------------------------------------------------------------
local W, H, TITLE_H, PAD, GAP = 540, 340, 30, 10, 8
local LIST_W, ROW_H, HEAD_H, INPUT_H, BTN_H = 170, 20, 26, 24, 22
local WHISPER_W = 118 -- the Guild whispers check in the title bar: its box, 8px, the words
-- the New chat picker, in the right card: a search box, who's online, Cancel and Start chat
local SEARCH_H, PICK_START_W, PICK_CANCEL_W = 22, 104, 64
local PICK_TOP = HEAD_H + 6 + SEARCH_H + 6
local PANE_X = PAD + LIST_W + GAP
local PANE_W = W - PANE_X - PAD
local BODY_H = H - TITLE_H - PAD
local PICK_ROWS = math.floor((BODY_H - PICK_TOP - 8 - BTN_H - 8) / ROW_H)
local PICK_HINT_W = PANE_W - 10 - 8 - PICK_START_W - 6 - PICK_CANCEL_W - 8
Chat.layout = { W = W, H = H, LIST_W = LIST_W, PANE_X = PANE_X, PANE_W = PANE_W, ROW_H = ROW_H, PICK_TOP = PICK_TOP,
    PICK_ROWS = PICK_ROWS, PICK_HINT_W = PICK_HINT_W }

function Chat:Format(line)
    local at = date("%H:%M", line.t)
    if line.sys then return ("|cff8a8a92%s  %s|r"):format(at, esc(line.text)) end
    -- (a whisper is the game's own text, links and all; an addon line is anyone's, so it's escaped)
    return ("|cff8a8a92%s|r  %s: %s"):format(at, colored(line.from), line.w and line.text or esc(line.text))
end

-- A line into the open chat's log, in the theme's text colour.
function Chat:Say(line)
    self.log:AddMessage(self:Format(line), UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
end

function Chat:Build()
    local f = CreateFrame("Frame", "PogRaidChat", UIParent)
    f:SetSize(W, H)
    -- a layer above the main window (HIGH, and it brings itself to the front
    -- on every click): on the same layer the chat opened behind it, so the
    -- Chat button on Home seemed to do nothing (Jake, 0.16.5)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    UI.Panel(f)
    UI.Window(f)
    f:Hide()
    tinsert(UISpecialFrames, "PogRaidChat")
    self.frame = f

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetSize(W, TITLE_H)
    UI.MakeMovable(f, bar, function() UI.SavePosition(f, "chat") end)
    self.title = UI.Text(bar, 13)
    if UI.classic then self.title:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) end
    self.title:SetPoint("LEFT", PAD + 2, 0)
    self.title:SetText("Chat")
    local close = UI.CloseButton(bar, 28, TITLE_H, function() f:Hide() end)
    close:SetPoint("RIGHT", -PAD + 7, 0)
    -- guildmates' whispers kept here too (and lines sent as whispers), or not
    self.whisperCheck = UI.Check(bar, "Guild whispers", function() return ns.db.settings.chatWhispers ~= false end, function(v)
        ns.db.settings.chatWhispers = v and true or false
        self:Refresh()
    end)
    self.whisperCheck:SetWidth(WHISPER_W)
    self.whisperCheck:SetPoint("RIGHT", close, "LEFT", -6, 0)
    self.whisperCheck:SetScript("OnEnter", function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Guild whispers", 1, 1, 1)
        GameTooltip:AddLine("Whispers to and from guildmates are kept in your chat with them, and you can whisper anyone in the guild from here.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    self.whisperCheck:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- left: our chats, and New chat under them (Jake: the people you've
    -- messaged, not the whole guild; who's online is in the picker)
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", PAD, -TITLE_H)
    left:SetSize(LIST_W, BODY_H)
    UI.Card(left)
    self.left = left
    left.rows = {}
    left.offset = 0
    left.visible = math.floor((BODY_H - 8 - BTN_H - 8) / ROW_H)
    for i = 1, left.visible do
        local row = CreateFrame("Button", nil, left)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(4 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(4 + (i - 1) * ROW_H))
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        UI.SelBar(row.sel)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        row.right = UI.Text(row, 10)
        row.right:SetPoint("RIGHT", -8, 0)
        row.right:SetJustifyH("RIGHT")
        row.text = UI.Text(row, 11)
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(r, button) self:RowClick(r, button) end)
        left.rows[i] = row
    end
    left:EnableMouseWheel(true)
    left:SetScript("OnMouseWheel", function(_, d)
        left.offset = left.offset - d * 2
        self:RefreshList()
    end)
    self.newBtn = UI.Button(left, "New chat", LIST_W - 16, BTN_H, function() self:NewChat() end)
    self.newBtn:SetPoint("BOTTOM", 0, 8)

    -- right: the open chat
    local pane = CreateFrame("Frame", nil, f)
    pane:SetPoint("TOPLEFT", PANE_X, -TITLE_H)
    pane:SetSize(PANE_W, BODY_H)
    UI.Card(pane)
    self.pane = pane
    -- (how a line gets there, when it isn't the addon's own way)
    pane.how = UI.Text(pane, 10)
    pane.how:SetPoint("RIGHT", pane, "TOPRIGHT", -10, -UI.HeadMid(HEAD_H))
    pane.how:SetJustifyH("RIGHT")
    pane.how:SetTextColor(0.5, 0.5, 0.55)
    pane.with = UI.Text(pane, 12)
    pane.with:SetPoint("LEFT", pane, "TOPLEFT", 10, -UI.HeadMid(HEAD_H))
    pane.with:SetPoint("RIGHT", pane.how, "LEFT", -8, 0)
    pane.with:SetJustifyH("LEFT")
    pane.with:SetWordWrap(false)
    local line = pane:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    UI.Line(line, 0.06)
    pane.empty = UI.Text(pane, 11)
    pane.empty:SetPoint("CENTER", 0, 0)
    pane.empty:SetWidth(PANE_W - 60)
    pane.empty:SetJustifyH("CENTER")
    pane.empty:SetTextColor(0.5, 0.5, 0.55)

    local log = CreateFrame("ScrollingMessageFrame", nil, pane)
    log:SetPoint("TOPLEFT", 10, -(HEAD_H + 6))
    log:SetSize(PANE_W - 20, BODY_H - HEAD_H - 6 - INPUT_H - 16)
    log:SetFont(UI.FONT, 12, "")
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(Chat.KEEP_LINES)
    if log.SetIndentedWordWrap then log:SetIndentedWordWrap(true) end -- a long line's second row sits in from the time
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(l, d)
        if d > 0 then l:ScrollUp() else l:ScrollDown() end
    end)
    -- an item linked in a whisper opens like it does in the game's chat
    if log.SetHyperlinksEnabled then
        log:SetHyperlinksEnabled(true)
        log:SetScript("OnHyperlinkClick", function(_, link, text, button)
            if SetItemRef then pcall(SetItemRef, link, text, button) end
        end)
    end
    self.log = log

    local input = UI.EditBox(pane, PANE_W - 16, INPUT_H)
    input:SetPoint("BOTTOMLEFT", 8, 8)
    input:SetMaxLetters(Chat.MAX_TEXT)
    input:SetScript("OnEnterPressed", function(box)
        if self:Send(self.current, box:GetText()) then box:SetText("") end
    end)
    self.input = input

    -- New chat: who to start one with. A search box, everyone online (those
    -- the addon can't reach are marked "whisper"), Cancel and Start chat.
    local picker = CreateFrame("Frame", nil, pane)
    picker:SetAllPoints(pane)
    picker:Hide()
    picker.offset = 0
    self.picker = picker
    local search = UI.EditBox(picker, PANE_W - 16, SEARCH_H)
    search:SetPoint("TOPLEFT", 8, -(HEAD_H + 6))
    search:SetMaxLetters(24)
    search.ghost = UI.Text(search, 11)
    search.ghost:SetPoint("LEFT", 8, 0)
    search.ghost:SetTextColor(0.5, 0.5, 0.55)
    search.ghost:SetText("Search by name")
    search:SetScript("OnTextChanged", function()
        picker.offset = 0
        self:RefreshPicker()
    end)
    search:SetScript("OnEnterPressed", function() self:StartPicked(true) end)
    picker.search = search
    picker.rows = {}
    for i = 1, PICK_ROWS do
        local row = CreateFrame("Button", nil, picker)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(PICK_TOP + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(PICK_TOP + (i - 1) * ROW_H))
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        UI.SelBar(row.sel)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        row.right = UI.Text(row, 10)
        row.right:SetPoint("RIGHT", -10, 0)
        row.right:SetJustifyH("RIGHT")
        row.right:SetTextColor(0.5, 0.5, 0.55)
        row.text = UI.Text(row, 11)
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(r) self:PickClick(r) end)
        picker.rows[i] = row
    end
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function(_, d)
        picker.offset = picker.offset - d * 2
        self:RefreshPicker()
    end)
    picker.scroll = UI.ScrollHint(picker, PICK_TOP, BTN_H + 16)
    picker.empty = UI.Text(picker, 11)
    picker.empty:SetPoint("TOP", 0, -(PICK_TOP + 40))
    picker.empty:SetWidth(PANE_W - 60)
    picker.empty:SetJustifyH("CENTER")
    picker.empty:SetTextColor(0.5, 0.5, 0.55)
    picker.start = UI.Button(picker, "Start chat", PICK_START_W, BTN_H, function() self:StartPicked() end)
    picker.start:SetPoint("BOTTOMRIGHT", -8, 8)
    picker.cancel = UI.Button(picker, "Cancel", PICK_CANCEL_W, BTN_H, function() self:CancelPick() end)
    picker.cancel:SetPoint("RIGHT", picker.start, "LEFT", -6, 0)
    UI.Unred(picker.cancel) -- (one action button a view: Start chat)
    -- why some names are greyed out, or what to do (two short lines at most)
    picker.hint = UI.Text(picker, 10)
    picker.hint:SetPoint("BOTTOMLEFT", 10, 8)
    picker.hint:SetSize(PICK_HINT_W, BTN_H)
    picker.hint:SetJustifyH("LEFT")
    picker.hint:SetJustifyV("MIDDLE")
    picker.hint:SetTextColor(0.5, 0.5, 0.55)

    -- a box with focus would type letters instead of casting
    local function letGo()
        input:ClearFocus()
        search:ClearFocus()
    end
    ns.On("PLAYER_REGEN_DISABLED", letGo)
    f:SetScript("OnHide", letGo)
    UI.RestorePosition(f, "chat", 40)
end

-- The left list: our chats, newest first (0.16.7: it also listed everyone
-- online under them, which read as one long muddle, Jake).
function Chat:Items()
    local items = {}
    for _, c in ipairs(self:List()) do items[#items + 1] = { chat = c } end
    if not items[1] then items[1] = { head = "No chats yet" } end
    return items
end

function Chat:RefreshList()
    local left = self.left
    local items = self:Items()
    left.offset = math.max(0, math.min(left.offset, #items - left.visible))
    left.hint = left.hint or UI.ScrollHint(left, 4, BTN_H + 16)
    left.hint:Set(left.offset, left.visible, #items)
    for i, row in ipairs(left.rows) do
        local it = items[i + left.offset]
        row.item = it
        if it then
            row.right:SetText("")
            row.sel:Hide()
            if it.chat then
                local c = it.chat
                row.text:SetText(self:Title(c))
                row.sel:SetShown(c == self.current and not self.picking)
                if (c.unread or 0) > 0 then
                    row.right:SetText(tostring(c.unread))
                    row.right:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
                end
            else
                row.text:SetText("|cff8a8a92" .. it.head .. "|r")
            end
            row:SetEnabled(it.head == nil)
            row:Show()
        else
            row:Hide()
        end
    end
    self.newBtn:SetSelected(self.picking == true)
end

function Chat:RowClick(row, button)
    local it = row.item
    if not it then return end
    if it.chat then
        if button == "RightButton" then
            UI.ShowMenu(row, {
                { text = self:Title(it.chat, true), header = true },
                { text = "Delete chat", color = { 0.95, 0.4, 0.4 }, func = function() self:Delete(it.chat) end },
            })
        else
            self:Open(it.chat, true)
        end
    end
end

------------------------------------------------------------------------
-- New chat: the picker
------------------------------------------------------------------------
function Chat:NewChat()
    if self.picking then return self:CancelPick() end
    self.picking = true
    wipe(self.picked)
    self.picker.offset = 0
    self.picker.search:SetText("")
    self:Refresh()
    if not (InCombatLockdown and InCombatLockdown()) then self.picker.search:SetFocus() end
end

function Chat:CancelPick()
    self.picking = nil
    wipe(self.picked)
    self.picker.search:ClearFocus()
    -- (the chat that was under the picker is in front of us again)
    if self.current and (self.current.unread or 0) > 0 then
        self.current.unread = 0
        self:Badge()
    end
    self:Refresh()
end

-- Who's online, narrowed to what's typed in the search box.
function Chat:PickList()
    local want = (self.picker.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local out = {}
    for _, name in ipairs(self:Buddies()) do
        if want == "" or Ambiguate(name, "short"):lower():find(want, 1, true) then out[#out + 1] = name end
    end
    return out
end

-- Can `name` be added to who's picked? One person is anyone; a chat of three
-- or more goes the addon's way, so everyone in it needs chat ("addon"), and
-- it holds only so many ("full").
function Chat:Pickable(name)
    local n, lacking = 0, false
    for p in pairs(self.picked) do
        n = n + 1
        if not self:HasChat(p) then lacking = true end
    end
    if self.picked[name] or n == 0 then return true end
    if n >= Chat.MAX_MEMBERS - 1 then return false, "full" end
    if lacking or not self:HasChat(name) then return false, "addon" end
    return true
end

function Chat:RefreshPicker()
    local picker = self.picker
    local n = 0
    for name in pairs(self.picked) do
        if self:CanChat(name) then n = n + 1 else self.picked[name] = nil end
    end
    local list = self:PickList()
    picker.offset = math.max(0, math.min(picker.offset, #list - PICK_ROWS))
    picker.scroll:Set(picker.offset, PICK_ROWS, #list)
    local why
    for _, name in ipairs(list) do
        local ok, reason = self:Pickable(name)
        if not ok then why = why or reason end
    end
    for i, row in ipairs(picker.rows) do
        local name = list[i + picker.offset]
        row.item = name
        if name then
            local ok = self:Pickable(name)
            row.text:SetText(colored(name, Ambiguate(name, "short")))
            row.right:SetText(self:HasChat(name) and "" or "whisper")
            row.sel:SetShown(self.picked[name] == true)
            row.dim = not ok
            row:SetAlpha(ok and 1 or 0.35)
            row:SetEnabled(ok)
            row:Show()
        else
            row:Hide()
        end
    end
    local typed = (picker.search:GetText() or "") ~= ""
    picker.search.ghost:SetShown(not typed)
    picker.empty:SetShown(list[1] == nil)
    if not list[1] then
        picker.empty:SetText(typed and "Nobody online matches that."
            or self:Whispers() and "Nobody else from the guild is online."
            or "Nobody online has Pog Guild Tools " .. Chat.MIN_VERSION .. " or newer.")
    end
    picker.hint:SetText(why == "addon" and "A group chat needs the addon on everyone."
        or why == "full" and ("A chat holds %d people at most."):format(Chat.MAX_MEMBERS)
        or n == 0 and list[1] and "Pick one person, or several for a group."
        or "")
    picker.start:SetLabel(n > 1 and ("Start chat (%d)"):format(n) or "Start chat")
    picker.start:SetEnabledState(n > 0)
end

function Chat:PickClick(row)
    local name = row.item
    if not name or row.dim then return end
    self.picked[name] = not self.picked[name] or nil
    self:RefreshPicker()
end

-- Start the chat with who's picked. From the search box's Enter (`typed`),
-- one name left by the search is as good as picked.
function Chat:StartPicked(typed)
    local names = {}
    for name in pairs(self.picked) do names[#names + 1] = name end
    if not names[1] and typed then
        local list = self:PickList()
        if #list == 1 then names[1] = list[1] end
    end
    if not names[1] then return end
    self.picking = nil
    wipe(self.picked)
    self.picker.search:ClearFocus()
    self:OpenWith(names)
end

-- Who the open chat is with, and how a line reaches them if not the addon's way.
function Chat:RefreshHead()
    local pane, c = self.pane, self.current
    if self.picking then
        pane.with:SetText("New chat")
        pane.how:SetText("")
        return
    end
    pane.with:SetText(c and self:Title(c) or "")
    local others = c and self:Others(c) or {}
    local whisper = c and not c.test and #others == 1 and ns.Roster.online[others[1]] and not self:HasChat(others[1])
        and self:Whispers()
    pane.how:SetText(whisper and "Sent as whispers" or "")
end

function Chat:RefreshPane()
    local pane, c = self.pane, self.current
    local picking = self.picking == true
    self.picker:SetShown(picking)
    self:RefreshHead()
    if picking then
        -- the picker has the card: the chat under it waits
        pane.empty:Hide()
        self.log:Hide()
        self.input:Hide()
        self:RefreshPicker()
        return
    end
    self.log:Clear()
    pane.empty:SetShown(c == nil)
    self.log:SetShown(c ~= nil)
    self.input:SetShown(c ~= nil)
    if not c then
        pane.empty:SetText("Click New chat to message someone.")
        return
    end
    for _, line in ipairs(c.log) do self:Say(line) end
end

function Chat:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self.whisperCheck:Update()
    self:RefreshList()
    self:RefreshPane()
end

-- Someone came or went: the list and the heading, not the log (redrawing
-- that would throw away how far back it's scrolled).
function Chat:RosterChanged()
    if not self.frame or not self.frame:IsShown() then return end
    self:RefreshList()
    self:RefreshHead()
    if self.picking then self:RefreshPicker() end
end

-- A line was added to `c`.
function Chat:Changed(c, line)
    if not self.frame or not self.frame:IsShown() then return end
    if c == self.current and line then
        self:Say(line)
    end
    self:RefreshList()
end

function Chat:Open(c, focus)
    if not self:Enabled() then
        ns.Print("group chat is turned off in Settings")
        return
    end
    if not self.frame then self:Build() end
    if c then
        -- (a chat was asked for: the picker gives way)
        self.picking = nil
        wipe(self.picked)
    end
    c = c or self.current
    if c and not self.picking then
        self.current = c
        c.unread = 0
        self:Badge()
    end
    self.frame:Show()
    self.frame:Raise()
    self:Refresh()
    if focus and self.current and not self.picking and not (InCombatLockdown and InCombatLockdown()) then self.input:SetFocus() end
end

-- Open (making it if need be) the chat with these people.
function Chat:OpenWith(names)
    local members, seen = { me() }, { [me()] = true }
    for _, n in ipairs(names) do
        if not seen[n] then
            seen[n] = true
            members[#members + 1] = n
        end
    end
    if #members < 2 then return end
    if #members > Chat.MAX_MEMBERS then
        ns.Print(("a chat holds %d people at most"):format(Chat.MAX_MEMBERS))
        return
    end
    self:Open(self:Get(members, true), true)
end

function Chat:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end

-- Turned off in Settings: the window goes, and anyone who writes is told.
function Chat:SetEnabled(on)
    ns.db.settings.chat = on and true or false
    if not on and self.frame then self.frame:Hide() end
end

ns.On("GUILD_ROSTER_UPDATE", function() Chat:RosterChanged() end)
ns.On("CHAT_MSG_WHISPER", function(text, who) Chat:OnWhisper(text, who, true) end)
ns.On("CHAT_MSG_WHISPER_INFORM", function(text, who) Chat:OnWhisper(text, who, false) end)
