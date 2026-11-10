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
Chat.picked = {}            -- buddies ticked for a new chat

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
local function clean(text)
    text = tostring(text or ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, Chat.MAX_TEXT)
end

function Chat:Enabled() return ns.db.settings.chat ~= false end

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
-- Who can be chatted with: online, on a version with chat, and not known
-- to have it turned off.
------------------------------------------------------------------------
function Chat:CanChat(name)
    if not self:Enabled() or not name or name == me() or not ns.Roster.online[name] or self.off[name] then return false end
    local saved = ns.db.versions and ns.db.versions[name]
    local v = ns.Version.dev[name] or ns.Version.seen[name] or (saved and saved.v)
    local c = v and ns.Version.Compare(v, Chat.MIN_VERSION)
    return c == 0 or c == 1
end

function Chat:Buddies()
    local out = {}
    for name in pairs(ns.Roster.online) do
        if G().players[name] and self:CanChat(name) then out[#out + 1] = name end
    end
    table.sort(out)
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
    local watching = self.frame and self.frame:IsShown() and self.current == c
    if not watching then
        c.unread = (c.unread or 0) + 1
        self:Notify(c, line)
        self:Badge()
    end
    self:Changed(c, line)
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
local PANE_X = PAD + LIST_W + GAP
local PANE_W = W - PANE_X - PAD
local BODY_H = H - TITLE_H - PAD
Chat.layout = { W = W, H = H, LIST_W = LIST_W, PANE_X = PANE_X, PANE_W = PANE_W, ROW_H = ROW_H }

function Chat:Format(line)
    local at = date("%H:%M", line.t)
    if line.sys then return ("|cff8a8a92%s  %s|r"):format(at, esc(line.text)) end
    return ("|cff8a8a92%s|r  %s: %s"):format(at, colored(line.from), esc(line.text))
end

-- A line into the open chat's log, in the theme's text colour.
function Chat:Say(line)
    self.log:AddMessage(self:Format(line), UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
end

function Chat:Build()
    local f = CreateFrame("Frame", "PogRaidChat", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    UI.Panel(f)
    UI.Window(f)
    f:Hide()
    tinsert(UISpecialFrames, "PogRaidChat")
    self.frame = f

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TITLE_H)
    UI.MakeMovable(f, bar, function() UI.SavePosition(f, "chat") end)
    self.title = UI.Text(bar, 13)
    if UI.classic then self.title:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) end
    self.title:SetPoint("LEFT", PAD + 2, 0)
    self.title:SetText("Chat")
    local close = UI.CloseButton(bar, 28, TITLE_H, function() f:Hide() end)
    close:SetPoint("RIGHT", -PAD + 7, 0)

    -- left: chats, then who's online to start one with
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
    self.startBtn = UI.Button(left, "Start chat", LIST_W - 16, BTN_H, function() self:StartPicked() end)
    self.startBtn:SetPoint("BOTTOM", 0, 8)

    -- right: the open chat
    local pane = CreateFrame("Frame", nil, f)
    pane:SetPoint("TOPLEFT", PANE_X, -TITLE_H)
    pane:SetSize(PANE_W, BODY_H)
    UI.Card(pane)
    self.pane = pane
    pane.with = UI.Text(pane, 12)
    pane.with:SetPoint("LEFT", pane, "TOPLEFT", 10, -UI.HeadMid(HEAD_H))
    pane.with:SetPoint("RIGHT", pane, "TOPRIGHT", -10, -UI.HeadMid(HEAD_H))
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
    self.log = log

    local input = UI.EditBox(pane, PANE_W - 16, INPUT_H)
    input:SetPoint("BOTTOMLEFT", 8, 8)
    input:SetMaxLetters(Chat.MAX_TEXT)
    input:SetScript("OnEnterPressed", function(box)
        if self:Send(self.current, box:GetText()) then box:SetText("") end
    end)
    self.input = input
    -- a box with focus would type letters instead of casting
    ns.On("PLAYER_REGEN_DISABLED", function() input:ClearFocus() end)
    f:SetScript("OnHide", function() input:ClearFocus() end)
    UI.RestorePosition(f, "chat", 40)
end

-- The left list: our chats, a heading, then who's online with chat.
function Chat:Items()
    local items = {}
    for _, c in ipairs(self:List()) do items[#items + 1] = { chat = c } end
    local buddies = self:Buddies()
    -- (short enough for the list: "Nobody else online has chat" was cut off)
    items[#items + 1] = { head = buddies[1] and "Online" or "Nobody online yet" }
    for _, n in ipairs(buddies) do items[#items + 1] = { buddy = n } end
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
                row.sel:SetShown(c == self.current)
                if (c.unread or 0) > 0 then
                    row.right:SetText(tostring(c.unread))
                    row.right:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
                end
            elseif it.buddy then
                row.text:SetText(colored(it.buddy, Ambiguate(it.buddy, "short")))
                row.sel:SetShown(self.picked[it.buddy] == true)
            else
                row.text:SetText("|cff8a8a92" .. it.head .. "|r")
            end
            row:SetEnabled(it.head == nil)
            row:Show()
        else
            row:Hide()
        end
    end
    local n = 0
    for name in pairs(self.picked) do
        if self:CanChat(name) then n = n + 1 else self.picked[name] = nil end
    end
    self.startBtn:SetLabel(n > 1 and ("Start chat (%d)"):format(n) or "Start chat")
    self.startBtn:SetEnabledState(n > 0)
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
    elseif it.buddy then
        local n = 0
        for _ in pairs(self.picked) do n = n + 1 end
        if self.picked[it.buddy] then
            self.picked[it.buddy] = nil
        elseif n < Chat.MAX_MEMBERS - 1 then
            self.picked[it.buddy] = true
        else
            ns.Print(("a chat holds %d people at most"):format(Chat.MAX_MEMBERS))
        end
        self:RefreshList()
    end
end

function Chat:StartPicked()
    local names = {}
    for name in pairs(self.picked) do names[#names + 1] = name end
    if not names[1] then return end
    wipe(self.picked)
    self:OpenWith(names)
end

function Chat:RefreshPane()
    local pane, c = self.pane, self.current
    self.log:Clear()
    pane.with:SetText(c and self:Title(c) or "")
    pane.empty:SetShown(c == nil)
    self.log:SetShown(c ~= nil)
    self.input:SetShown(c ~= nil)
    if not c then
        pane.empty:SetText(self:Buddies()[1] and "Pick people on the left, then Start chat."
            or "Chat reaches guildies who are online with Pog Guild Tools " .. Chat.MIN_VERSION .. " or newer.")
        return
    end
    for _, line in ipairs(c.log) do self:Say(line) end
end

function Chat:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:RefreshList()
    self:RefreshPane()
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
    c = c or self.current
    if c then
        self.current = c
        c.unread = 0
        self:Badge()
    end
    self.frame:Show()
    self:Refresh()
    if focus and self.current and not (InCombatLockdown and InCombatLockdown()) then self.input:SetFocus() end
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

ns.On("GUILD_ROSTER_UPDATE", function() Chat:Refresh() end)
