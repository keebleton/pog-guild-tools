-- PogRaid viewer: the window that pops up on everyone's screen when the
-- raid leader shows a board. Read-only; wheel zooms, drag pans.
local _, ns = ...
local UI = ns.UI

local Viewer = {}
ns.Viewer = Viewer

local PAD, TITLE_H = 8, 30
local CANVAS_W, CANVAS_H = 600, 400
local SCALES = { 0.75, 1, 1.25, 1.5 }

-- Melee/ranged by class, for highlighting the right role group. Hybrids
-- are left out rather than guessed.
local MELEE = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true }
local RANGED = { MAGE = true, WARLOCK = true, PRIEST = true, HUNTER = true, EVOKER = true }

local function myGroup()
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if role == "TANK" then return "T" end
    if role == "HEALER" then return "H" end
    local _, class = UnitClass("player")
    if MELEE[class] then return "M" end
    if RANGED[class] then return "R" end
end

function Viewer:Build()
    local f = CreateFrame("Frame", "PogRaidViewer", UIParent)
    f:SetSize(PAD + CANVAS_W + PAD, TITLE_H + CANVAS_H + PAD)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    UI.Panel(f)
    local metal = UI.PortraitFrame(f, "", ns.MEDIA .. "logo", function() f:Hide() end)
    if not metal then UI.Window(f) end
    f:Hide()
    tinsert(UISpecialFrames, "PogRaidViewer")
    self.frame = f

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TITLE_H)
    UI.MakeMovable(f, bar, function() UI.SavePosition(f, "viewer") end)

    self.from = UI.Text(bar, 11)
    self.from:SetTextColor(0.55, 0.55, 0.6)
    local size = UI.Button(bar, "Size", 44, 22, function() self:CycleScale() end)
    if metal then
        -- the plan's name in the strip; who sent it in the bar, clear of the portrait
        self.title = metal.title
        self.from:SetPoint("LEFT", UI.PORTRAIT_CLEAR, 0)
        size:SetPoint("RIGHT", -PAD, 0)
        UI.MakeMovable(f, metal.strip, function() UI.SavePosition(f, "viewer") end)
    else
        self.title = UI.Text(bar, 13)
        if UI.classic then self.title:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) end
        self.title:SetPoint("LEFT", PAD + 2, 0)
        self.from:SetPoint("LEFT", self.title, "RIGHT", 8, 0)
        local close = UI.CloseButton(bar, 28, TITLE_H, function() f:Hide() end)
        close:SetPoint("RIGHT", -PAD + 7, 0)
        size:SetPoint("RIGHT", close, "LEFT", -4, 0)
    end

    local canvas = ns.CreateCanvas(f, CANVAS_W, CANVAS_H)
    canvas.frame:SetPoint("TOPLEFT", PAD, -TITLE_H)
    self.canvas = canvas

    local cf = canvas.frame
    cf:EnableMouse(true)
    cf:EnableMouseWheel(true)
    cf:SetScript("OnMouseWheel", function(_, delta)
        canvas:ZoomAt(delta, canvas:CursorToMap())
    end)
    cf:SetScript("OnMouseDown", function()
        local x, y = canvas:CursorUI()
        self.drag = { x = x, y = y }
        f:SetScript("OnUpdate", function()
            local nx, ny = canvas:CursorUI()
            canvas:Pan(nx - self.drag.x, ny - self.drag.y)
            self.drag.x, self.drag.y = nx, ny
        end)
    end)
    cf:SetScript("OnMouseUp", function()
        self.drag = nil
        f:SetScript("OnUpdate", nil)
    end)

    f:SetScale(ns.db.frames.viewerScale or 1)
    UI.RestorePosition(f, "viewer", 60)
end

function Viewer:ShowBoard(board, sender)
    if not self.frame then self:Build() end
    self.sender = sender
    self.title:SetText(board.name)
    self.from:SetText(sender and ("from " .. sender) or "")
    local c = self.canvas
    c:SetHighlight(ns.PlayerName(), myGroup())
    c.items = board.items
    c:SetMap(board.map)
    c:SetView(board.zoom, board.cx, board.cy)
    self.frame:Show()
    ns.Sound("RAID_WARNING")
end

function Viewer:CloseFrom(sender)
    if self.frame and self.frame:IsShown() and self.sender == sender then
        self.frame:Hide()
    end
end

function Viewer:CycleScale()
    local cur = ns.db.frames.viewerScale or 1
    local nextScale = SCALES[1]
    for i, s in ipairs(SCALES) do
        if math.abs(s - cur) < 0.01 then nextScale = SCALES[i % #SCALES + 1] end
    end
    ns.db.frames.viewerScale = nextScale
    self.frame:SetScale(nextScale)
    UI.RestorePosition(self.frame, "viewer", 60)
end

function Viewer:ResetPosition()
    if not self.frame then return end
    self.frame:SetScale(1)
    UI.RestorePosition(self.frame, "viewer", 60)
end
