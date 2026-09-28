-- Pog Raid minimap button: the gnome on the minimap ring. Left-click opens
-- Pog Raid, right-click offers Settings / Hide, drag moves it around the
-- ring. Hidden buttons come back from Settings or /pog minimap. Pog Raid is
-- also in Blizzard's AddOns menu (AddonCompartmentFunc in the .toc).
local _, ns = ...
local UI = ns.UI

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local function settings()
    return ns.db.settings.minimap
end

function MinimapButton:Build()
    if self.button or not Minimap then return end
    local b = CreateFrame("Button", "PogRaidMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    -- The tracking-border art sits off-centre in its own file; at 50x50 from
    -- the button's top-left its ring is centred one pixel above the button's
    -- centre, so the plate and gnome go there too (the standard minimap
    -- button layout). 18px keeps the gnome's ears inside the ring.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", 0, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "logo")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 1)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function(btn, button)
        if button == "RightButton" then
            UI.ShowMenu(btn, {
                { text = "Pog Raid", header = true },
                { text = "Settings", func = function() ns.Editor:Toggle("settings") end },
                { text = "Hide minimap button", func = function() self:SetHidden(true) end },
            })
        else
            ns.Editor:Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(btn)
        btn:SetScript("OnUpdate", function() self:FollowCursor() end)
    end)
    b:SetScript("OnDragStop", function(btn) btn:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(btn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:AddLine("Pog Raid", 1, 1, 1)
        GameTooltip:AddLine("Left-click: open", 0.8, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: settings or hide", 0.8, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.button = b
    self:Place()
    self:Update()
end

-- Put the button on the ring at the saved angle (degrees, 0 = east).
function MinimapButton:Place()
    local a = math.rad(settings().angle or 220)
    local r = (Minimap:GetWidth() / 2) + 5
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function MinimapButton:FollowCursor()
    local mx, my = Minimap:GetCenter()
    local x, y = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    settings().angle = math.deg(math.atan2(y / s - my, x / s - mx)) % 360
    self:Place()
end

function MinimapButton:SetHidden(hidden)
    settings().hide = hidden or nil
    self:Update()
    if hidden then ns.Print("minimap button hidden. Bring it back from Settings or with /pog minimap.") end
    if ns.Settings then ns.Settings:Changed() end
end

function MinimapButton:Update()
    if self.button then self.button:SetShown(not settings().hide) end
end

ns.On("PLAYER_LOGIN", function() MinimapButton:Build() end)

-- Blizzard's AddOns menu next to the minimap (see the .toc)
function PogRaid_OnAddonCompartmentClick()
    ns.Editor:Toggle()
end
