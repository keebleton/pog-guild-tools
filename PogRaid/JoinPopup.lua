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
