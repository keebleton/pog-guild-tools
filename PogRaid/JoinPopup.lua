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
    self.frame:Show()
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
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
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
        f:Hide()
    end
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
    f.id = rec.id
    f.icon:SetTexture(ns.Profiles and ns.Profiles:Portrait(rec.author) or 134400)
    f.text:SetText(("%s is forming a group for %s"):format(colorName(rec.author), rec.what))
    local parts = {}
    if rec.need then parts[#parts + 1] = "needs " .. rec.need end
    if rec.size then parts[#parts + 1] = rec.size .. "/" .. rec.max end
    f.sub:SetText(table.concat(parts, "  "))
    self:Fit()
    f.age, f.stay, f.hover = 0, Toast.SHOW, false
    f:SetAlpha(0)
    f:Show()
end

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
        f:Hide()
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
