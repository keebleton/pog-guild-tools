-- Pog Raid join pop-up: when someone asks to join your group finder
-- listing, a small bar near the top of the screen offers Invite / No thanks.
-- Requests queue; the next one shows after you answer.
local _, ns = ...
local UI = ns.UI

local Popup = {}
ns.JoinPopup = Popup

Popup.queue = {}

function Popup:Build()
    local f = CreateFrame("Frame", "PogRaidJoinPopup", UIParent)
    f:SetSize(360, 64)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("TOP", 0, -140)
    f:EnableMouse(true)
    UI.Panel(f, { 0.05, 0.06, 0.07, 0.97 }, UI.ACCENT)
    UI.Window(f)
    UI.MakeMovable(f, f)
    f.text = UI.Text(f, 12)
    f.text:SetPoint("TOPLEFT", 12, -10)
    f.text:SetPoint("TOPRIGHT", -12, -10)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.no = UI.Button(f, "No thanks", 90, 22, function() self:Answer(false) end)
    f.no:SetPoint("BOTTOMRIGHT", -10, 9)
    f.yes = UI.Button(f, "Invite", 90, 22, function() self:Answer(true) end)
    f.yes:SetPoint("RIGHT", f.no, "LEFT", -6, 0)
    f.yes:SetPrimary()
    f.more = UI.Text(f, 10)
    f.more:SetPoint("BOTTOMLEFT", 12, 13)
    f.more:SetTextColor(0.55, 0.55, 0.6)
    f:Hide()
    self.frame = f
end

function Popup:Add(who, listing)
    table.insert(self.queue, { who = who, what = listing.what })
    self:Show()
end

function Popup:Show()
    if not self.frame then self:Build() end
    -- (a request already answered elsewhere, or for a group since closed)
    while self.queue[1] and not ns.Social.requests[self.queue[1].who] do table.remove(self.queue, 1) end
    local req = self.queue[1]
    if not req then
        self.frame:Hide()
        return
    end
    local p = ns.db.guild.players[req.who]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    local name = Ambiguate(req.who, "short")
    if c then name = ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) end
    local detail = p and p.level and (" (level %d)"):format(p.level) or ""
    self.frame.text:SetText(("%s%s wants to join your %s group"):format(name, detail, req.what))
    self.frame.more:SetText(#self.queue > 1 and ("+%d more"):format(#self.queue - 1) or "")
    local was = self.frame:IsShown()
    self.frame:Show()
    if not was then UI.FadeIn(self.frame, 0.2) end -- (a little motion: UI experiment)
    ns.Sound("IG_PLAYER_INVITE")
end

function Popup:Answer(invite)
    local req = table.remove(self.queue, 1)
    if req then ns.Social:Answer(req.who, invite) end
    self:Show()
end

------------------------------------------------------------------------
-- Group toast: a guildie just posted a group. A small note fades in above
-- the chat box ("Flyne is forming a group for Deadmines"); click it to ask
-- to join, right-click to dismiss. Fades out on its own unless hovered.
------------------------------------------------------------------------
local Toast = {}
ns.GroupToast = Toast

Toast.SHOW = 8        -- seconds on screen
Toast.FADE_IN = 0.3
Toast.FADE_OUT = 0.6
Toast.FRESH = 120     -- only listings posted this recently (not ones caught up on at login)
Toast.MIN_W, Toast.MAX_W = 300, 420   -- grows with its text; past the widest, the line wraps
local TEXT_X, TEXT_R = 50, 12
Toast.seen = {}

local function colorName(name)
    local p = ns.db.guild.players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    local short = Ambiguate(name, "short")
    if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, short) end
    return short
end

function Toast:Build()
    local f = CreateFrame("Button", "PogRaidGroupToast", UIParent)
    f:SetSize(300, 50)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    -- above the chat box, where the game's own friend toasts show
    local chat = DEFAULT_CHAT_FRAME
    if chat and chat.GetObjectType then
        f:SetPoint("BOTTOMLEFT", chat, "TOPLEFT", 0, 40)
    else
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 260)
    end
    UI.Panel(f, { 0.05, 0.06, 0.07, 0.95 }, UI.ACCENT)
    UI.Window(f, "tooltip")
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Hover(hl, 0.05)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("LEFT", 9, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.text = UI.Text(f, 12)
    f.text:SetPoint("TOPLEFT", TEXT_X, -9)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f.text:SetWordWrap(false)
    f.sub = UI.Text(f, 10)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    f.sub:SetTextColor(0.6, 0.6, 0.65)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", function(_, button) self:Click(button) end)
    f:SetScript("OnEnter", function() f.hover = true end)
    f:SetScript("OnLeave", function() f.hover = false end)
    f:SetScript("OnUpdate", function(_, elapsed) self:Step(elapsed) end)
    f:Hide()
    self.frame = f
end

-- Fade in, stay (longer while hovered), fade out.
function Toast:Step(elapsed)
    local f = self.frame
    f.age = f.age + (elapsed or 0)
    if f.hover and f.age > Toast.FADE_IN then f.age = math.min(f.age, f.stay) end
    if f.age < Toast.FADE_IN then
        f:SetAlpha(f.age / Toast.FADE_IN)
    elseif f.age < f.stay then
        f:SetAlpha(1)
    elseif f.age < f.stay + Toast.FADE_OUT then
        f:SetAlpha(1 - (f.age - f.stay) / Toast.FADE_OUT)
    else
        self:Dismiss()
    end
end

-- Gone; the next waiting note (if any) takes its place.
function Toast:Dismiss()
    self.frame:Hide()
    self:NextNote()
end

-- A listing arrived (or changed): toast it if it's a guildie's new one.
function Toast:Consider(rec)
    if not rec or rec.deleted or self.seen[rec.id] then return end
    local now = ns.Now()
    if rec.author == ns.Sync:Me() or rec.exp <= now or rec.t < now - Toast.FRESH then return end
    self.seen[rec.id] = true
    if ns.db.settings.groupToasts == false or (InCombatLockdown and InCombatLockdown()) then return end
    self:Show(rec)
end

function Toast:Show(rec)
    if not self.frame then self:Build() end
    local f = self.frame
    f.id, f.note = rec.id, nil
    f.icon:SetTexture(ns.Profiles and ns.Profiles:Portrait(rec.author) or 134400)
    f.text:SetText(("%s is forming a group for %s"):format(colorName(rec.author), rec.what))
    local parts = {}
    if rec.need then parts[#parts + 1] = "needs " .. rec.need end
    if rec.size then parts[#parts + 1] = rec.size .. "/" .. (rec.max or 5) end
    f.sub:SetText(table.concat(parts, "  "))
    self:Fit()
    f.age, f.stay, f.hover = 0, Toast.SHOW, false
    f:SetAlpha(0)
    f:Show()
end

-- Other news in the same pop-up (a chat line, kudos): { icon, text, sub,
-- onClick }. One at a time; the rest wait their turn, and all of them wait
-- out a fight.
Toast.notes = {}
Toast.MAX_NOTES = 5

function Toast:Note(note)
    self.notes[#self.notes + 1] = note
    while #self.notes > Toast.MAX_NOTES do table.remove(self.notes, 1) end
    self:NextNote()
end

function Toast:NextNote()
    if not self.notes[1] or (self.frame and self.frame:IsShown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not self.frame then self:Build() end
    local f = self.frame
    local note = table.remove(self.notes, 1)
    f.id, f.note = nil, note
    f.icon:SetTexture(note.icon or 134400)
    f.text:SetText(note.text or "")
    f.sub:SetText(note.sub or "")
    self:Fit()
    f.age, f.stay, f.hover = 0, Toast.SHOW, false
    f:SetAlpha(0)
    f:Show()
end

ns.On("PLAYER_REGEN_ENABLED", function() Toast:NextNote() end)

-- As wide as the text needs (between MIN_W and MAX_W); a longer first line
-- wraps onto a second and the toast grows taller.
local function textWidth(fs)
    return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

function Toast:Fit()
    local f = self.frame
    local textW, subW = textWidth(f.text), textWidth(f.sub)
    local w = math.floor(math.max(Toast.MIN_W, math.min(Toast.MAX_W, math.max(textW, subW) + TEXT_X + TEXT_R)) + 0.5)
    local room = w - TEXT_X - TEXT_R
    local two = textW > room
    f:SetSize(w, two and 64 or 50)
    f.text:SetWidth(room)
    f.text:SetHeight(two and 30 or 15)
    f.text:SetWordWrap(two)
    if f.text.SetMaxLines then f.text:SetMaxLines(two and 2 or 1) end
    f.sub:SetWidth(room)
    f.sub:ClearAllPoints()
    f.sub:SetPoint("TOPLEFT", TEXT_X, two and -41 or -27)
    f.two = two
end

function Toast:Click(button)
    local f = self.frame
    if button == "RightButton" then
        self:Dismiss()
        return
    end
    if f.note then
        local note = f.note
        self:Dismiss()
        if note.onClick then note.onClick() end
        return
    end
    local g = f.id and (ns.Sync:Store("lfg") or {})[f.id]
    if not g or g.deleted or g.exp <= ns.Now() then
        f.sub:SetText("That group closed")
    elseif ns.Social:IsFull(g) then
        f.sub:SetText("That group is full")
    elseif ns.Social.requested[g.id] or ns.Social:RequestJoin(g) then
        f.sub:SetText("Asked to join")
    end
    -- leave soon after a click
    f.stay = math.min(f.stay, f.age + 1.5)
end

------------------------------------------------------------------------
-- Level milestones (Jake, 0.16.9): a guildie reaching level 20, 30, 40 or
-- 50 gets a pop-up like a new group's; reaching 60 gets a banner across
-- the top of the screen. Every addon sees it for itself in the guild
-- roster (Roster:ScanGuild), so the one levelling doesn't need the addon.
-- Only for level-ups seen as they happen: not what's caught up on at login,
-- nor an offline member's. Settings turns them off; /pog ding previews one.
------------------------------------------------------------------------
local Milestone = {}
ns.Milestone = Milestone

Milestone.LEVELS = { 20, 30, 40, 50, 60 }
Milestone.TOP = 60                 -- this one gets the banner
Milestone.IN, Milestone.HOLD, Milestone.OUT = 0.45, 7, 1.2 -- seconds: the banner arriving, staying, leaving
Milestone.SPARKS = 16
Milestone.queue = {}               -- banners waiting their turn (or for a fight to end)
local GOLD = { 1.00, 0.82, 0.20 }
local BANNER_W, BANNER_H, LINE_W = 520, 150, 380

-- The highest milestone passed going from level `from` to level `to`, or nil.
function Milestone.Crossed(from, to)
    local best
    for _, level in ipairs(Milestone.LEVELS) do
        if from < level and to >= level then best = level end
    end
    return best
end

-- A guildie's level went from `from` to `to` (`away`: we weren't there to see it).
function Milestone:OnLevel(name, from, to, away)
    if away or not name or not from or not to then return end
    local level = Milestone.Crossed(from, to)
    if not level or ns.db.settings.levelToasts == false then return end
    self:Celebrate(name, level)
end

function Milestone:Celebrate(name, level)
    if level >= Milestone.TOP then
        self.queue[#self.queue + 1] = { name = name, level = level }
        self:Next()
    else
        self:Toast(name, level)
    end
end

-- 20 to 50: the small pop-up, with their portrait. Clicking it opens a chat with them to say so.
function Milestone:Toast(name, level)
    local mine = name == ns.Sync:Me()
    local canChat = not mine and ns.Chat and ns.Chat:CanChat(name)
    -- (silent, like a new group's: the game's level-up sound here made it seem we'd levelled ourselves, Jake)
    Toast:Note({
        icon = ns.Profiles and ns.Profiles:Portrait(name) or 134400,
        text = mine and ("You reached level %d!"):format(level) or ("%s reached level %d!"):format(colorName(name), level),
        sub = canChat and "Click to say grats" or "",
        onClick = canChat and function() ns.Chat:OpenWith({ name }) end or nil,
    })
end

function Milestone:Build()
    local f = CreateFrame("Button", "PogRaidLevelBanner", UIParent)
    f:SetSize(BANNER_W, BANNER_H)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("TOP", 0, -150)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", function() self:Dismiss() end)
    f:SetScript("OnUpdate", function(_, elapsed) self:Step(elapsed) end)
    -- no box: a soft dark cloud behind gold light, like the game's own level-up
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetTexture(ns.MEDIA .. "glow")
    f.back:SetSize(BANNER_W + 160, BANNER_H + 110)
    f.back:SetPoint("CENTER")
    f.back:SetVertexColor(0, 0, 0, 0.85)
    f.shine = f:CreateTexture(nil, "BORDER")
    f.shine:SetTexture(ns.MEDIA .. "glow")
    f.shine:SetSize(BANNER_W - 60, BANNER_H + 30)
    f.shine:SetPoint("CENTER", 0, -6)
    f.shine:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
    if f.shine.SetBlendMode then f.shine:SetBlendMode("ADD") end
    -- two gold rules that open out from the middle
    f.lines = {}
    for i, y in ipairs({ -52, -134 }) do
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetPoint("CENTER", f, "TOP", 0, y)
        line:SetSize(1, 2)
        line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
        f.lines[i] = line
    end
    -- their portrait in a gold ring, sitting on the top rule
    f.portrait = UI.RoundIcon(f, 44)
    f.portrait:SetPoint("CENTER", f, "TOP", 0, -26)
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(ns.MEDIA .. "ring")
    f.ring:SetSize(58, 58)
    f.ring:SetPoint("CENTER", f.portrait, "CENTER")
    f.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    f.who = UI.Text(f, 18)
    f.who:SetFont(UI.FONT, 18, "OUTLINE")
    f.who:SetPoint("TOP", 0, -60)
    f.level = UI.Text(f, 36)
    f.level:SetFont(UI.FONT, 36, "OUTLINE")
    f.level:SetPoint("TOP", 0, -82)
    f.level:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.sub = UI.Text(f, 12)
    f.sub:SetPoint("TOP", 0, -122)
    f.sub:SetTextColor(0.85, 0.8, 0.65)
    -- gold sparks drifting up through it
    f.sparks = {}
    for i = 1, Milestone.SPARKS do
        local s = f:CreateTexture(nil, "OVERLAY")
        s:SetTexture(ns.MEDIA .. "disc")
        s:SetVertexColor(1, 0.9, 0.55, 1)
        if s.SetBlendMode then s:SetBlendMode("ADD") end
        f.sparks[i] = s
    end
    f:Hide()
    self.frame = f
end

-- The next banner in the queue, unless one is up or we're in a fight.
function Milestone:Next()
    if not self.queue[1] or (self.frame and self.frame:IsShown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not self.frame then self:Build() end
    local f = self.frame
    local it = table.remove(self.queue, 1)
    local mine = it.name == ns.Sync:Me()
    local p = ns.db.guild.players[it.name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    f.name = it.name
    f.portrait:SetTexture(ns.Profiles and ns.Profiles:Portrait(it.name) or 134400)
    f.who:SetText(mine and "You" or Ambiguate(it.name, "short"))
    f.who:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
    f.level:SetText(("LEVEL %d"):format(it.level))
    local guild = ns.Sync:GuildName()
    f.sub:SetText(mine and "The long road ends. Well played." or guild and ("One of <%s> has made it."):format(guild) or "A guildmate has made it.")
    f.age = 0
    for i, s in ipairs(f.sparks) do
        -- (spread by number, not by chance: the same banner every time)
        s.x = (i - 0.5) / #f.sparks * (BANNER_W - 80) - (BANNER_W - 80) / 2
        s.phase = (i * 0.37) % 1
        s.size = 3 + (i % 3)
        s:SetSize(s.size, s.size)
    end
    f:SetAlpha(0)
    f:Show()
    self:Step(0)
    ns.Sound("IG_QUEST_LIST_COMPLETE") -- (a chime of our own, never the game's level-up sound)
end

function Milestone:Step(elapsed)
    local f = self.frame
    f.age = f.age + (elapsed or 0)
    local M = Milestone
    local age = f.age
    if age >= M.IN + M.HOLD + M.OUT then return self:Dismiss() end
    local arrive = math.min(1, age / M.IN)
    local ease = 1 - (1 - arrive) ^ 3
    f:SetAlpha(age > M.IN + M.HOLD and 1 - (age - M.IN - M.HOLD) / M.OUT or ease)
    -- it lands a little large and settles; the rules open out
    f:SetScale(1.18 - 0.18 * ease)
    for _, line in ipairs(f.lines) do line:SetWidth(math.max(1, LINE_W * ease)) end
    f.shine:SetAlpha(0.38 + 0.14 * math.sin(age * 2.4))
    for _, s in ipairs(f.sparks) do
        local k = (age * 0.32 + s.phase) % 1
        s:ClearAllPoints()
        s:SetPoint("CENTER", f, "BOTTOM", s.x + 10 * math.sin(age * 1.7 + s.phase * 6.3), 6 + k * (BANNER_H - 10))
        s:SetAlpha(math.sin(math.pi * k) * 0.9)
    end
end

function Milestone:Dismiss()
    if self.frame then self.frame:Hide() end
    self:Next()
end

ns.On("PLAYER_REGEN_ENABLED", function() Milestone:Next() end)
