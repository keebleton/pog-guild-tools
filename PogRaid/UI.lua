-- PogRaid UI kit: flat panels, buttons, edit boxes, a popup menu and a
-- text prompt. Built from plain textures so nothing depends on Blizzard
-- templates that may differ on this client.
local _, ns = ...

local UI = {}
ns.UI = UI

UI.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
UI.BG = { 0.06, 0.06, 0.07, 0.96 }
UI.BORDER = { 0.24, 0.24, 0.27, 1 }
UI.BUTTON = { 0.15, 0.15, 0.17, 0 }   -- buttons are outlines; only selected / primary ones fill
UI.CARD = { 0.09, 0.095, 0.11, 1 }     -- cards: a lighter fill instead of an outline
UI.TITLE = { 0.55, 0.56, 0.62 }        -- small capital section titles
UI.BUTTON_BORDER = { 0.30, 0.30, 0.34, 1 }
UI.ACCENT = { 0.40, 0.80, 1.00 }
UI.SEL_FILL = { 0.12, 0.26, 0.34, 1 } -- a selected button
UI.BAND = { 0.095, 0.1, 0.115, 1 }     -- the title band
UI.TEXT = { 0.92, 0.92, 0.94 }         -- body text
UI.BACKING = { 0.135, 0.13, 0.122 }    -- behind a classic window (UI.SetTheme)
UI.SURFACE = "Interface\\FrameGeneral\\UI-Background-Marble" -- the theme's texture over its colours
UI.SURFACE_TINT = 1                    -- how strongly it's laid on

------------------------------------------------------------------------
-- Classic look (Settings, on by default): the game's own gold, window
-- borders, red buttons, check boxes, list highlights and sounds, all from the
-- client's files (nothing shipped). Set once at load, before anything is
-- built (UI.SetClassic); switching it reloads the UI.
------------------------------------------------------------------------
UI.classic = false
local CLASSIC = {
    BG = { 0.05, 0.045, 0.04, 0.97 },
    BORDER = { 0.34, 0.29, 0.20, 1 },
    BUTTON_BORDER = { 0.42, 0.36, 0.25, 1 },
    CARD = { 0.085, 0.082, 0.078, 1 },
    TITLE = { 0.80, 0.74, 0.58 }, -- parchment, not gold: gold is for selected and primary (UI experiment)
    ACCENT = { 1, 0.82, 0 },
    SEL_FILL = { 0.24, 0.17, 0.04, 1 },
    BAND = { 0.02, 0.018, 0.015, 0.55 },
    TAB_TEXT = { 0.86, 0.70, 0.22 },
    TAB_HOVER = { 1, 0.86, 0.30 },
}
UI.FILES = {
    marble = "Interface\\FrameGeneral\\UI-Background-Marble",
    stone = "Interface\\FrameGeneral\\UI-Background-Rock",
    dark = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    dialog = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tooltip = "Interface\\Tooltips\\UI-Tooltip-Border",
    red = "Interface\\Buttons\\UI-Panel-Button-",
    check = "Interface\\Buttons\\UI-CheckBox-",
    close = "Interface\\Buttons\\UI-Panel-MinimizeButton-",
    questBar = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    parchment = "Interface\\ACHIEVEMENTFRAME\\UI-Achievement-Parchment-Horizontal",
    letter = "Interface\\Stationery\\StationeryTest1",
}

-- Tokens are changed in place, so tables already handed out follow.
function UI.SetClassic(on)
    UI.classic = on and true or false
    if not UI.classic then return end
    for k, v in pairs(CLASSIC) do
        local t = UI[k]
        for i = 1, 4 do t[i] = v[i] end
    end
end

------------------------------------------------------------------------
-- Themes (Settings > Theme; Jake, Oct 2026): the classic look in a few
-- moods, plus the plain modern look. Each sets what's behind the window
-- (backing), the cards a shade darker, their soft edge, the title band and
-- the body text (never pure white: Jake liked the pale yellow of the game's
-- "Apprentice" text). Set once at load (UI.SetTheme); switching reloads.
------------------------------------------------------------------------
-- Each classic theme has its own surface: a smooth, mottled tile from the
-- client (Jake liked marble's feel; planks, bricks and quilting didn't land),
-- laid additively over the theme's colours at `tint` strength (brighter tiles
-- turned down), behind the window, on the cards and on the band. All are
-- long-standing client files.
local FG = "Interface\\FrameGeneral\\"
UI.THEMES = {
    { key = "stone", name = "Stone", surface = FG .. "UI-Background-Marble", tint = 1, -- grey marble (Jake's favourite)
        backing = { 0.135, 0.13, 0.122 }, card = { 0.085, 0.082, 0.078, 1 },
        edge = { 0.27, 0.26, 0.24, 0.7 }, band = { 0.06, 0.058, 0.055, 1 }, text = { 0.88, 0.82, 0.64 } },
    { key = "ember", name = "Ember", surface = FG .. "UI-Background-Marble", tint = 1, -- marble over red-brown
        backing = { 0.16, 0.07, 0.05 }, card = { 0.11, 0.045, 0.03, 1 },
        edge = { 0.42, 0.18, 0.10, 0.8 }, band = { 0.08, 0.03, 0.02, 1 }, text = { 0.94, 0.80, 0.62 } },
    { key = "sandstone", name = "Sandstone", surface = FG .. "UI-Background-Rock", tint = 0.5, -- soft warm stone
        backing = { 0.10, 0.086, 0.068 }, card = { 0.05, 0.04, 0.03, 1 },
        edge = { 0.38, 0.33, 0.25, 0.75 }, band = { 0.02, 0.018, 0.01, 1 }, text = { 0.90, 0.85, 0.70 } },
    { key = "leather", name = "Leather", surface = "Interface\\Collections\\CollectionsBackgroundTile", tint = 0.55,
        backing = { 0.10, 0.055, 0.015 }, card = { 0.05, 0.015, 0, 1 }, -- the Collections window's tan leather
        edge = { 0.40, 0.27, 0.11, 0.8 }, band = { 0.01, 0, 0, 1 }, text = { 0.93, 0.84, 0.66 } },
    { key = "night", name = "Night", surface = FG .. "UIFrameOribosBackground", tint = 1, -- smooth mottled deep blue
        backing = { 0.075, 0.08, 0.105 }, card = { 0.035, 0.04, 0.055, 1 },
        edge = { 0.22, 0.25, 0.32, 0.7 }, band = { 0, 0, 0.01, 1 }, text = { 0.82, 0.84, 0.90 } },
    { key = "plain", name = "Plain (modern)", plain = true },
}
UI.theme = "plain"
UI.DEFAULT_THEME = "night" -- Jake's pick, Oct 2026

function UI.Theme(key)
    for _, t in ipairs(UI.THEMES) do
        if t.key == key then return t end
    end
end

function UI.SetTheme(key)
    local t = UI.Theme(key) or UI.Theme(UI.DEFAULT_THEME)
    UI.theme = t.key
    UI.SetClassic(not t.plain)
    if t.plain then return end
    local function put(name, v)
        local dst = UI[name]
        for i = 1, 4 do dst[i] = v[i] end
    end
    put("BACKING", t.backing)
    put("CARD", t.card)
    put("BAND", t.band)
    put("TEXT", t.text)
    UI.CARD_EDGE = t.edge
    UI.SURFACE, UI.SURFACE_TINT = t.surface, t.tint or 1
end

-- The accent as a chat colour code, for marking words inside a line.
function UI.AccentCode()
    return ("|cff%02x%02x%02x"):format(UI.ACCENT[1] * 255, UI.ACCENT[2] * 255, UI.ACCENT[3] * 255)
end

-- Does the client have this file? (Unknown when it can't say: assume yes.)
function UI.HasFile(path)
    if not GetFileIDFromPath then return true end
    for _, p in ipairs({ path, path .. ".blp" }) do
        local ok, id = pcall(GetFileIDFromPath, p)
        if ok and id then return true end
    end
    return false
end

-- The game's interface sounds, with the classic look only.
function UI.Sound(name)
    if not UI.classic or not (PlaySound and SOUNDKIT and SOUNDKIT[name]) then return end
    pcall(PlaySound, SOUNDKIT[name])
end

-- A hover highlight (a soft gold glow), a divider line and a selected row
-- (the quest log's bar): white tints in the plain look.
function UI.Hover(tex, a)
    if UI.classic then
        tex:SetColorTexture(1, 0.82, 0, (a or 0.05) * 1.4)
        if tex.SetBlendMode then tex:SetBlendMode("ADD") end
    else
        tex:SetColorTexture(1, 1, 1, a or 0.05)
    end
end

function UI.Line(tex, a)
    if UI.classic then
        tex:SetColorTexture(0.62, 0.56, 0.45, (a or 0.06) * 2)
    else
        tex:SetColorTexture(1, 1, 1, a or 0.06)
    end
end

UI.SEL_WASH = { 0.20, 0.02 } -- the selected row's gold: left edge, right edge
function UI.SelBar(tex, a)
    if UI.classic then
        tex:SetColorTexture(1, 1, 1, 1)
        local ok = CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, "HORIZONTAL",
            CreateColor(1, 0.80, 0.25, UI.SEL_WASH[1]), CreateColor(1, 0.80, 0.25, UI.SEL_WASH[2]))
        if not ok then tex:SetColorTexture(1, 0.80, 0.25, (UI.SEL_WASH[1] + UI.SEL_WASH[2]) / 2) end
    else
        tex:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], a or 0.12)
    end
end

-- A window's classic dress: stone behind everything and the game's border
-- just outside its edge (so nothing inside moves). kind: "dialog" (windows
-- and pop-ups) or "tooltip" (menus and small boxes).
local EDGES = {
    dialog = { size = 32, out = 10 },
    tooltip = { size = 16, out = 3 },
}
-- Behind a window: a mid grey with the game's marble laid over it (Jake: "a
-- slightly textured grey"). It's what shows between the cards, so it sits
-- just a shade lighter than them and the breaks stay gentle (like the
-- Dungeon Journal's panels on their content panel), not dark gutters.
-- Without marble: dimmed stone, else the dark dialog background.
-- The theme's surface tile, else marble, else nil (no texture).
function UI.Surface()
    if UI.SURFACE and UI.HasFile(UI.SURFACE) then return UI.SURFACE end
    if UI.HasFile(UI.FILES.marble) then return UI.FILES.marble end
end

local function stone(f)
    f.stone = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.stone:SetAllPoints()
    local surface = UI.Surface()
    if surface then
        if f.bg then f.bg:SetColorTexture(UI.BACKING[1], UI.BACKING[2], UI.BACKING[3], 1) end
        f.stone:SetTexture(surface, "REPEAT", "REPEAT")
        if f.stone.SetBlendMode then f.stone:SetBlendMode("ADD") end
        f.stone:SetVertexColor(UI.SURFACE_TINT, UI.SURFACE_TINT, UI.SURFACE_TINT)
    else
        f.stone:SetTexture(UI.HasFile(UI.FILES.stone) and UI.FILES.stone or UI.FILES.dark, "REPEAT", "REPEAT")
        f.stone:SetVertexColor(0.55, 0.55, 0.55)
    end
    if f.stone.SetHorizTile then f.stone:SetHorizTile(true) end
    if f.stone.SetVertTile then f.stone:SetVertTile(true) end
end

function UI.Window(f, kind)
    if not UI.classic then return end
    kind = kind or "dialog"
    for _, e in ipairs(f.edges or {}) do e:Hide() end
    if kind == "dialog" then stone(f) end
    local e = EDGES[kind]
    local ok, b = pcall(CreateFrame, "Frame", nil, f, "BackdropTemplate")
    if not ok or not b or not b.SetBackdrop then return end
    b:SetPoint("TOPLEFT", -e.out, e.out)
    b:SetPoint("BOTTOMRIGHT", e.out, -e.out)
    b:SetFrameLevel(f:GetFrameLevel() + 30)
    b:SetBackdrop({ edgeFile = UI.FILES[kind], edgeSize = e.size })
    f.frameBorder = b
end

-- The game's metal window (as on Professions or the Spellbook): a round
-- portrait in the top-left corner, the title centred in a strip along the
-- top, the square red X at its right. The strip sits just above the window,
-- so nothing inside moves. Drawn by the client's own layout (NineSliceUtil,
-- "PortraitFrameTemplate"); returns nil (use UI.Window) when it isn't there.
-- Returns { edge, strip, title, close, portrait }; drag the window by `strip`.
UI.TITLE_STRIP, UI.PORTRAIT = 21, 62
UI.LIP_TUCK = 4 -- the top edge starts this far under the corner's ring
UI.PORTRAIT_CLEAR = 66 -- band content starts here, clear of the portrait (it hangs 34px into the window)
function UI.PortraitFrame(f, title, portrait, onClose)
    if not (UI.classic and NineSliceUtil and NineSliceUtil.ApplyLayoutByName) then return nil end
    local ok, edge = pcall(CreateFrame, "Frame", nil, f, "NineSlicePanelTemplate")
    if not ok or not edge then return nil end
    edge:SetPoint("TOPLEFT", 0, UI.TITLE_STRIP)
    edge:SetPoint("BOTTOMRIGHT", 0, 0)
    edge:SetFrameLevel(f:GetFrameLevel() + 30)
    if not pcall(NineSliceUtil.ApplyLayoutByName, edge, "PortraitFrameTemplate") then
        edge:Hide()
        return nil
    end
    -- the title bar's gold lip stops a hair short of the ring and its square
    -- end showed (Jake): start the top edge a little under the corner, which
    -- draws over it
    local corner, top = edge.TopLeftCorner, edge.TopEdge
    if corner and top and top.ClearAllPoints and corner.GetDrawLayer then
        local layer = corner:GetDrawLayer()
        corner:SetDrawLayer(layer, 7)
        if top.SetDrawLayer then top:SetDrawLayer(layer, 6) end
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", corner, "TOPRIGHT", -UI.LIP_TUCK, 0)
        if edge.TopRightCorner then top:SetPoint("TOPRIGHT", edge.TopRightCorner, "TOPLEFT", 0, 0) end
    end
    for _, e in ipairs(f.edges or {}) do e:Hide() end
    stone(f)
    -- the strip: a dark fill, the title, the X; it's the drag handle too
    -- (the fill starts under the portrait's middle: from the window's edge its
    -- square corner showed outside the round ring, Jake)
    local fill = f:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("BOTTOMLEFT", f, "TOPLEFT", UI.PORTRAIT / 2 - 5, 0)
    fill:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
    fill:SetHeight(UI.TITLE_STRIP)
    fill:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], 1)
    local strip = CreateFrame("Frame", nil, f)
    strip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
    strip:SetHeight(UI.TITLE_STRIP)
    strip:SetFrameLevel(f:GetFrameLevel() + 31)
    local text = UI.Text(strip, 12)
    text:SetPoint("CENTER", 0, 0)
    text:SetText(title or "")
    text:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
    local close = UI.CloseButton(strip, 22, 22, onClose)
    close:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
    close:SetFrameLevel(strip:GetFrameLevel() + 1)
    close.inStrip = true
    -- the portrait, under the corner's ring: our logo on a dark disc, kept round
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(UI.PORTRAIT, UI.PORTRAIT)
    p:SetPoint("TOPLEFT", f, "TOPLEFT", -5, UI.TITLE_STRIP + 7)
    p:SetFrameLevel(f:GetFrameLevel() + 29)
    p.plate = p:CreateTexture(nil, "BACKGROUND")
    p.plate:SetAllPoints()
    p.plate:SetTexture(ns.MEDIA .. "disc")
    p.plate:SetVertexColor(0.08, 0.08, 0.1, 1)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", 4, -4)
    p.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    p.icon:SetTexture(portrait)
    -- what the frame adds around the window still counts for staying on screen
    if f.SetClampRectInsets then f:SetClampRectInsets(-16, 6, UI.TITLE_STRIP + 18, -6) end
    return { edge = edge, strip = strip, title = text, close = close, portrait = p, fill = fill }
end

-- A window's title band (Editor, Inspect, gallery): its fill, the line under
-- it and its title.
function UI.Band(band, divider, title)
    band:SetColorTexture(UI.BAND[1], UI.BAND[2], UI.BAND[3], UI.BAND[4])
    local surface = UI.classic and band.GetParent and UI.Surface()
    if surface then
        -- a solid header strip, textured and lit like the cards (it looked flat)
        local bar = band:GetParent()
        local marble = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
        marble:SetAllPoints(band)
        marble:SetTexture(surface, "REPEAT", "REPEAT")
        if marble.SetHorizTile then marble:SetHorizTile(true) end
        if marble.SetVertTile then marble:SetVertTile(true) end
        if marble.SetBlendMode then marble:SetBlendMode("ADD") end
        marble:SetVertexColor(UI.SURFACE_TINT, UI.SURFACE_TINT, UI.SURFACE_TINT)
        local shade = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
        shade:SetAllPoints(band)
        shade:SetColorTexture(1, 1, 1, 1)
        local ok = CreateColor and shade.SetGradient and pcall(shade.SetGradient, shade, "VERTICAL",
            CreateColor(0, 0, 0, 0.35), CreateColor(1, 1, 1, 0.08))
        if not ok then shade:Hide() end
        band.marble, band.shade = marble, shade
    end
    if UI.classic then
        divider:SetColorTexture(0.86, 0.70, 0.30, 0.35)
        if title then title:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) end
    else
        divider:SetColorTexture(UI.BORDER[1], UI.BORDER[2], UI.BORDER[3], 1)
    end
end

-- Faint parchment behind a card meant for reading (classic look only).
function UI.Parchment(card, alpha)
    if not UI.classic then return end
    local t = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetAllPoints()
    t:SetTexture(UI.HasFile(UI.FILES.parchment) and UI.FILES.parchment or UI.FILES.letter)
    t:SetAlpha(alpha or 0.2)
    card.parchment = t
    return t
end

function UI.Border(f, color, layer)
    local c = color or UI.BORDER
    local function edge(a, b, horizontal)
        local e = f:CreateTexture(nil, layer or "BORDER")
        e:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        e:SetPoint(a)
        e:SetPoint(b)
        if horizontal then e:SetHeight(1) else e:SetWidth(1) end
        return e
    end
    f.edges = {
        edge("TOPLEFT", "TOPRIGHT", true), edge("BOTTOMLEFT", "BOTTOMRIGHT", true),
        edge("TOPLEFT", "BOTTOMLEFT", false), edge("TOPRIGHT", "BOTTOMRIGHT", false),
    }
end

function UI.SetBorderColor(f, c)
    for _, e in ipairs(f.edges) do e:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

-- A card: filled, no outline. Edges stay empty so SetBorderColor is harmless.
-- Classic look: a card is grey stone a shade darker than what's behind it,
-- lit from above, with the game's soft tooltip edge toned down nearly to its
-- own colour (Jake: flat panels looked flat, borders harsh; the Dungeon
-- Journal's gentle breaks were the model): the grey fill, the marble laid
-- over it additively, a soft falloff (a touch lighter at the top, darker at
-- the bottom), all under sublevel 1 where card art draws; the edge on a
-- child frame. UI.CARD_EDGE = nil drops the edges. A card given its own
-- colour stays flat.
UI.CARD_SHADE_TOP, UI.CARD_SHADE_BOTTOM = 0.06, 0.30
UI.CARD_EDGE = { 0.27, 0.26, 0.24, 0.7 }
-- A card header's titles and buttons sit in the middle of what shows: the
-- soft edge covers about 3px of the card's top, so with it they go 1.5px
-- lower than the header's centre, and buttons keep 6px from the right
-- (Jake: they leaned on the edge and the title sat high).
UI.EDGE_NUDGE, UI.HEAD_INSET_EDGE = 1.5, 6
function UI.HeadMid(headH)
    if UI.classic and UI.CARD_EDGE then return headH / 2 + UI.EDGE_NUDGE end
    return headH / 2
end
function UI.HeadInset()
    return (UI.classic and UI.CARD_EDGE) and UI.HEAD_INSET_EDGE or 5
end

function UI.Card(f, color)
    local c = color or UI.CARD
    local surface = UI.classic and not color and UI.Surface()
    local stoneCard = surface and true or false
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, stoneCard and -2 or 0)
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    f.edges = {}
    if not stoneCard then return end
    f.marble = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.marble:SetAllPoints()
    f.marble:SetTexture(surface, "REPEAT", "REPEAT")
    if f.marble.SetHorizTile then f.marble:SetHorizTile(true) end
    if f.marble.SetVertTile then f.marble:SetVertTile(true) end
    if f.marble.SetBlendMode then f.marble:SetBlendMode("ADD") end
    f.marble:SetVertexColor(UI.SURFACE_TINT, UI.SURFACE_TINT, UI.SURFACE_TINT)
    f.shade = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.shade:SetAllPoints()
    f.shade:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and f.shade.SetGradient and pcall(f.shade.SetGradient, f.shade, "VERTICAL",
        CreateColor(0, 0, 0, UI.CARD_SHADE_BOTTOM), CreateColor(1, 1, 1, UI.CARD_SHADE_TOP))
    if not ok then f.shade:Hide() end
    if UI.CARD_EDGE then
        local made, edge = pcall(CreateFrame, "Frame", nil, f, "BackdropTemplate")
        if made and edge and edge.SetBackdrop then
            edge:SetAllPoints()
            edge:SetBackdrop({ edgeFile = UI.FILES.tooltip, edgeSize = 12 })
            local e = UI.CARD_EDGE
            if edge.SetBackdropBorderColor then edge:SetBackdropBorderColor(e[1], e[2], e[3], e[4]) end
            f.softEdge = edge
        end
    end
end

-- An icon with rounded corners (Jake: square icons looked rigid): the game's
-- rounded icon mask, set a few pixels inside a slightly bigger icon so it
-- also trims the icon's own border (a masked texture can't be cropped).
-- `size` is what shows; anchor the icon by its CENTER. Falls back to a
-- plain cropped square.
UI.ICON_MASK = "Interface\\Common\\common-iconmask"
UI.ICON_TRIM = 3
function UI.RoundIcon(parent, size, layer)
    local icon = parent:CreateTexture(nil, layer or "ARTWORK")
    if parent.CreateMaskTexture and icon.AddMaskTexture and UI.HasFile(UI.ICON_MASK) then
        icon:SetSize(size + 2 * UI.ICON_TRIM, size + 2 * UI.ICON_TRIM)
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(UI.ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", icon, "TOPLEFT", UI.ICON_TRIM, -UI.ICON_TRIM)
        mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -UI.ICON_TRIM, UI.ICON_TRIM)
        icon:AddMaskTexture(mask)
        icon.mask = mask
    else
        icon:SetSize(size, size)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    return icon
end

-- A clickable tile that reads as a button on a card (Jake: the profession
-- tiles blended into the background): the soft rounded edge, a fill a shade
-- lighter, lit from the top. Its fill, highlight and selection sit inside the
-- edge so no square corner shows. UI.TileSelected(tile, on) turns the edge gold.
UI.TILE_EDGE = { 0.40, 0.38, 0.34, 0.9 }
UI.TILE_SEL_EDGE = { 0.70, 0.56, 0.22, 1 }
UI.TILE_SEL_ALPHA = 0.8 -- the picked tile's wash (Jake: the old glow was a little bright)
UI.TILE_FILL = { 0.10, 0.03 } -- white: top, bottom
UI.TILE_INSET = 4
function UI.Tile(t)
    local n = UI.TILE_INSET
    local function inside(tex)
        tex:SetPoint("TOPLEFT", n, -n)
        tex:SetPoint("BOTTOMRIGHT", -n, n)
        return tex
    end
    t.bg = inside(t:CreateTexture(nil, "BACKGROUND", nil, 1))
    t.bg:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and t.bg.SetGradient and pcall(t.bg.SetGradient, t.bg, "VERTICAL",
        CreateColor(1, 1, 1, UI.TILE_FILL[2]), CreateColor(1, 1, 1, UI.TILE_FILL[1]))
    if not ok then t.bg:SetColorTexture(1, 1, 1, (UI.TILE_FILL[1] + UI.TILE_FILL[2]) / 2) end
    t.sel = inside(t:CreateTexture(nil, "BACKGROUND", nil, 2))
    UI.SelBar(t.sel, 0.08)
    t.sel:SetAlpha(UI.TILE_SEL_ALPHA)
    t.sel:Hide()
    -- act on the press, as Sapper Sweeper's tiles (Jake: fast clicks were lost
    -- when the mouse drifted off before the release)
    if t.RegisterForClicks then t:RegisterForClicks("LeftButtonDown") end
    local hl = inside(t:CreateTexture(nil, "HIGHLIGHT"))
    UI.Hover(hl, 0.06)
    local made, edge = pcall(CreateFrame, "Frame", nil, t, "BackdropTemplate")
    if made and edge and edge.SetBackdrop then
        edge:SetAllPoints()
        edge:SetBackdrop({ edgeFile = UI.FILES.tooltip, edgeSize = 12 })
        t.edge = edge
    end
    UI.TileSelected(t, false)
    return t
end
function UI.TileSelected(t, on)
    t.sel:SetShown(on and true or false)
    local e = on and UI.TILE_SEL_EDGE or UI.TILE_EDGE
    if t.edge and t.edge.SetBackdropBorderColor then t.edge:SetBackdropBorderColor(e[1], e[2], e[3], e[4]) end
    t.edgeColor = e
end

-- A section's label ("Message board"), in the title colour, as the game
-- writes them: no capitals (Jake). `size`: 12, or smaller for table columns.
UI.TITLE_SIZE, UI.COLUMN_SIZE = 12, 11
function UI.SectionTitle(parent, text, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(UI.FONT, size or UI.TITLE_SIZE, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetTextColor(UI.TITLE[1], UI.TITLE[2], UI.TITLE[3])
    if text then fs:SetText(text) end
    return fs
end

-- A page's headline in the game's book and quest title font (Morpheus): one
-- per page, for the thing that page is about (UI experiment). Plain look: our font.
UI.HEADLINE_FONT = "Fonts\\MORPHEUS.TTF"
UI.HEADLINE = { 0.97, 0.88, 0.66 }
function UI.Headline(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    if not (UI.classic and fs:SetFont(UI.HEADLINE_FONT, size or 18, "") ~= false) then
        fs:SetFont(UI.FONT, size or 18, "")
    end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    local c = UI.classic and UI.HEADLINE or UI.TEXT
    fs:SetTextColor(c[1], c[2], c[3])
    fs.headline = true
    return fs
end

-- 9. a little motion: fade a frame in (page switches, toasts). One shared
-- driver; a frame faded again restarts.
local fading, fader = {}, nil
UI.FADE_TIME = 0.15
function UI.FadeIn(f, dur) UI.Fade(f, 0, 1, dur) end
-- From one alpha to another over `dur` seconds (a flash fades 0.35 -> 0).
function UI.Fade(f, from, to, dur)
    if not f or not f.SetAlpha then return end
    f:SetAlpha(from)
    fading[f] = { t = 0, dur = dur or UI.FADE_TIME, from = from, to = to }
    if not fader then
        fader = CreateFrame("Frame")
        fader:SetScript("OnUpdate", function(self, elapsed)
            local busy = false
            for fr, s in pairs(fading) do
                s.t = s.t + (elapsed or 0)
                local k = math.min(1, s.t / s.dur)
                fr:SetAlpha(s.from + (s.to - s.from) * k)
                if k >= 1 then fading[fr] = nil else busy = true end
            end
            if not busy then self:Hide() end
        end)
        UI.fader = fader
    end
    fader:Show()
end

-- A thin bar on the right edge of a scrolling list, shown only when the list
-- has more rows than fit. hint:Set(offset, visible, total).
function UI.ScrollHint(frame, top, bottom)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetWidth(2)
    tex:SetColorTexture(1, 1, 1, 0.22)
    tex:Hide()
    local hint = { tex = tex, frame = frame, top = top or 4, bottom = bottom or 4 }
    function hint:Set(offset, visible, total)
        if visible <= 0 or total <= visible then
            self.tex:Hide()
            return
        end
        local h = self.frame:GetHeight() - self.top - self.bottom
        local th = math.max(14, h * visible / total)
        local y = (h - th) * math.min(1, math.max(0, offset / (total - visible)))
        self.tex:ClearAllPoints()
        self.tex:SetHeight(th)
        self.tex:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -2, -(self.top + y))
        self.tex:Show()
    end
    return hint
end

function UI.Panel(f, bg, border)
    local c = bg or UI.BG
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    UI.Border(f, border)
end

function UI.Text(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(UI.FONT, size or 12, "")
    fs:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    return fs
end

function UI.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    UI.Panel(b, UI.BUTTON, UI.BUTTON_BORDER)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Hover(hl, 0.07)
    b.hl = hl
    b.label = UI.Text(b, 11)
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    b.label:SetText(text or "")
    b:RegisterForClicks("LeftButtonUp")
    if onClick then b:SetScript("OnClick", onClick) end

    function b:SetLabel(t) self.label:SetText(t) end
    function b:SetSelected(on)
        self.selected = on
        if self.red then UI.Unred(self) end
        if on then
            self.bg:SetColorTexture(UI.SEL_FILL[1], UI.SEL_FILL[2], UI.SEL_FILL[3], UI.SEL_FILL[4])
            UI.SetBorderColor(self, { UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1 })
        else
            self.bg:SetColorTexture(UI.BUTTON[1], UI.BUTTON[2], UI.BUTTON[3], UI.BUTTON[4])
            UI.SetBorderColor(self, UI.BUTTON_BORDER)
        end
    end
    function b:SetPrimary()
        if UI.classic then
            UI.RedButton(self)
            return
        end
        self.bg:SetColorTexture(0.10, 0.36, 0.52, 1)
        UI.SetBorderColor(self, { 0.30, 0.62, 0.82, 1 })
    end
    function b:SetEnabledState(on)
        self:SetEnabled(on)
        self.label:SetAlpha(on and 1 or 0.4)
        if self.red then self:SetRed(on and "Up" or "Disabled") end
    end
    if UI.classic and h >= UI.RED_MIN_H then UI.RedButton(b) end
    return b
end
UI.RED_MIN_H = 20 -- smaller buttons (card headers) stay outlines

-- The game's red panel button (as on Accept / Decline), in three slices so
-- it stretches to any width: caps 12px, the art is 80x22 of a 128x32 file.
local function slices(b, layer, file)
    local l, m, r = b:CreateTexture(nil, layer), b:CreateTexture(nil, layer), b:CreateTexture(nil, layer)
    for _, t in ipairs({ l, m, r }) do t:SetTexture(file) end
    l:SetTexCoord(0, 0.09375, 0, 0.6875)
    l:SetPoint("TOPLEFT")
    l:SetPoint("BOTTOMLEFT")
    l:SetWidth(12)
    r:SetTexCoord(0.53125, 0.625, 0, 0.6875)
    r:SetPoint("TOPRIGHT")
    r:SetPoint("BOTTOMRIGHT")
    r:SetWidth(12)
    m:SetTexCoord(0.09375, 0.53125, 0, 0.6875)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT")
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    return { l, m, r }
end

function UI.RedButton(b)
    if b.red then return end
    b.edges = b.edges or {}
    b.bg:Hide()
    for _, e in ipairs(b.edges) do e:Hide() end
    b.hl:Hide()
    b.red = slices(b, "BACKGROUND", UI.FILES.red .. "Up")
    b.redHL = slices(b, "HIGHLIGHT", UI.FILES.red .. "Highlight")
    for _, t in ipairs(b.redHL) do
        if t.SetBlendMode then t:SetBlendMode("ADD") end
    end
    b.label:SetTextColor(1, 0.82, 0)
    function b:SetRed(state)
        self.redState = state
        for _, t in ipairs(self.red) do t:SetTexture(UI.FILES.red .. state) end
        local c = state == "Disabled" and { 0.5, 0.5, 0.5 } or { 1, 0.82, 0 }
        self.label:SetTextColor(c[1], c[2], c[3])
    end
    b:HookScript("OnMouseDown", function(self) if self.red and self:IsEnabled() then self:SetRed("Down") end end)
    b:HookScript("OnMouseUp", function(self) if self.red and self:IsEnabled() then self:SetRed("Up") end end)
    b:SetRed(b:IsEnabled() and "Up" or "Disabled")
end

-- Back to the outline look (a toggle or a menu button isn't an action).
function UI.Unred(b)
    if not b.red then return end
    for _, t in ipairs(b.red) do t:Hide() end
    for _, t in ipairs(b.redHL or {}) do t:Hide() end
    b.red, b.redHL, b.SetRed = nil, nil, nil
    b.bg:Show()
    for _, e in ipairs(b.edges or {}) do e:Show() end
    b.hl:Show()
    b.label:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
end

-- A button that reloads the UI. Addons can't call ReloadUI themselves on
-- this client (the game blocks it: "Interface action failed because of an
-- AddOn"), so this is the game's secure button running the /reload macro on
-- the player's own click. Styled like UI.Button; nil if the client has no
-- secure buttons (then the caller asks for /reload in chat). Not in combat.
--
-- A secure frame locks every frame it sits inside, or is anchored to, during
-- combat: inside the window it made opening, closing, Esc, dragging and tabs
-- fail ("Interface action failed because of an AddOn") once Settings had
-- been opened. So it lives on UIParent, is placed over `anchor` (by `place`)
-- only while offered out of combat, and lets go (hidden, unanchored) as
-- combat starts, which PLAYER_REGEN_DISABLED still allows.
function UI.ReloadButton(anchor, text, w, h, place)
    local ok, b = pcall(CreateFrame, "Button", nil, UIParent, "SecureActionButtonTemplate")
    if not ok or not b or not b.SetAttribute then return nil end
    local function inCombat() return InCombatLockdown and InCombatLockdown() end
    local function letGo()
        b:Hide()
        b:ClearAllPoints()
    end
    -- show it (over the anchor) or not; `wanted` is remembered for after combat
    function b:Offer(on)
        self.wanted = on and true or false
        if inCombat() then return end
        letGo()
        if self.wanted and anchor:IsVisible() then
            place(self)
            self:SetFrameStrata(anchor:GetFrameStrata())
            self:SetFrameLevel(anchor:GetFrameLevel() + 20)
            self:Show()
        end
    end
    anchor:HookScript("OnShow", function() b:Offer(b.wanted) end)
    anchor:HookScript("OnHide", function() if not inCombat() then letGo() end end)
    ns.On("PLAYER_REGEN_DISABLED", letGo)
    ns.On("PLAYER_REGEN_ENABLED", function() b:Offer(b.wanted) end)
    letGo()
    b:SetSize(w, h)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "/reload")
    b:RegisterForClicks("AnyUp", "AnyDown")
    UI.Panel(b, UI.BUTTON, UI.BUTTON_BORDER)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Hover(hl, 0.07)
    b.hl = hl
    b.label = UI.Text(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    if UI.classic then UI.RedButton(b) end
    return b
end

-- A button that opens a menu gets the game's small down arrow at its right
-- (not a letter "v"); its label moves over to make room.
UI.DROP_ARROW = "Interface\\Buttons\\Arrow-Down-Up"
function UI.DropArrow(b)
    UI.Unred(b)
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetSize(12, 12)
    b.arrow:SetPoint("RIGHT", -5, -2)
    b.arrow:SetTexture(UI.DROP_ARROW)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -20, 0)
    return b.arrow
end

-- Two-click confirm for destructive buttons: the first click turns the
-- label into "Sure?", a second click within 3 seconds does it.
function UI.ConfirmClick(btn, action)
    local label = btn.baseLabel or btn.label:GetText()
    btn.baseLabel = label
    if btn.armed then
        btn.armed = nil
        btn:SetLabel(label)
        action()
        return
    end
    btn.armed = true
    btn:SetLabel("Sure?")
    C_Timer.After(3, function()
        if btn.armed then
            btn.armed = nil
            btn:SetLabel(label)
        end
    end)
end

-- Item tooltips: the game's "Currently equipped" comparison shows only while
-- Shift is held. UI.ItemTip(owner, link, anchor) sets the tooltip (the caller
-- adds lines and Shows it). Nothing is written to GameTooltip (taint): the
-- comparison tooltips are hidden as they show, while the tooltip is ours, and
-- pressing or letting go of Shift redraws it through the owner's OnEnter.
local compareTips
local function ourItemTip()
    local o = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
    return o and o.pogItemTip and o or nil
end
local function shiftDown() return IsShiftKeyDown and IsShiftKeyDown() end

local function hookCompare()
    compareTips = {}
    for _, t in pairs(GameTooltip.shoppingTooltips or { _G.ShoppingTooltip1, _G.ShoppingTooltip2 }) do
        if t and t.HookScript then
            compareTips[#compareTips + 1] = t
            t:HookScript("OnShow", function(self)
                if ourItemTip() and not shiftDown() then self:Hide() end
            end)
        end
    end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("MODIFIER_STATE_CHANGED")
    watch:SetScript("OnEvent", function(_, _, key)
        if type(key) ~= "string" or not key:find("SHIFT", 1, true) then return end
        local o = GameTooltip:IsShown() and ourItemTip()
        local onEnter = o and o:IsMouseOver() and o:GetScript("OnEnter")
        if not onEnter then return end
        onEnter(o)
        if not shiftDown() then
            for _, t in ipairs(compareTips) do t:Hide() end
        end
    end)
end

function UI.ItemTip(owner, link, anchor)
    if not compareTips then hookCompare() end
    owner.pogItemTip = true
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not ok then GameTooltip:AddLine(link) end
    return ok
end

-- Square button holding a texture (raid markers, colour swatches).
function UI.IconButton(parent, size, onClick)
    local b = UI.Button(parent, "", size, size, onClick)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    return b
end

function UI.EditBox(parent, w, h)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h)
    e:SetAutoFocus(false)
    e:SetFont(UI.FONT, 12, "")
    e:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
    e:SetTextInsets(7, 7, 0, 0)
    UI.Panel(e, { 0.02, 0.02, 0.03, 1 }, UI.BUTTON_BORDER)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEditFocusGained", function(self) UI.SetBorderColor(self, UI.ACCENT) end)
    e:SetScript("OnEditFocusLost", function(self) UI.SetBorderColor(self, UI.BUTTON_BORDER) end)
    return e
end

function UI.MakeMovable(f, handle, onStop)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() f:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if onStop then onStop() end
    end)
end

-- Save/restore a frame's centre as an offset from UIParent's centre, in
-- UIParent units (GetPoint is unreliable after StartMoving).
function UI.SavePosition(f, key)
    local x, y = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s = f:GetScale()
    if not x or not ux then return end
    ns.db.frames[key] = { x = x * s - ux, y = y * s - uy }
end

function UI.RestorePosition(f, key, defaultY)
    local p = ns.db.frames[key]
    local s = f:GetScale()
    f:ClearAllPoints()
    if p then
        f:SetPoint("CENTER", UIParent, "CENTER", p.x / s, p.y / s)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, (defaultY or 0) / s)
    end
end

------------------------------------------------------------------------
-- Popup menu: UI.ShowMenu(anchor, entries)
-- entry = { text, func, color = {r,g,b}, disabled = bool, header = bool }
------------------------------------------------------------------------
local ROW_H, ROWS_PER_COL, MENU_PAD = 20, 20, 4
local menu

local function hideMenu()
    if menu then menu:Hide() end
end
UI.HideMenu = hideMenu

local function buildMenu()
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    UI.Panel(menu, { 0.05, 0.05, 0.06, 0.98 }, UI.BORDER)
    UI.Window(menu, "tooltip")
    menu.rows = {}
    menu:Hide()
    menu:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
            self:Hide()
        end
    end)
    pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
    UI.menuFrame = menu
end

function UI.ShowMenu(anchor, entries)
    if not menu then buildMenu() end
    if menu:IsShown() and menu.anchor == anchor then
        menu:Hide()
        return
    end
    menu.anchor = anchor
    local widest = anchor:GetWidth() - 2 * MENU_PAD
    for i, entry in ipairs(entries) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(ROW_H)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            UI.Hover(hl, 0.08)
            row.label = UI.Text(row, 11)
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnClick", function(self)
                hideMenu()
                if self.func then self.func() end
            end)
            menu.rows[i] = row
        end
        row.func = entry.func
        row.label:SetText(entry.text)
        local c = entry.color or (entry.header and { 0.55, 0.55, 0.6 }) or UI.TEXT
        row.label:SetTextColor(c[1], c[2], c[3])
        row:SetEnabled(not (entry.disabled or entry.header))
        row.label:SetAlpha(entry.disabled and 0.45 or 1)
        widest = math.max(widest, row.label:GetStringWidth() + 16)
        row:Show()
    end
    for i = #entries + 1, #menu.rows do menu.rows[i]:Hide() end

    local cols = math.max(1, math.ceil(#entries / ROWS_PER_COL))
    local rows = math.min(#entries, ROWS_PER_COL)
    local colW = math.ceil(widest)
    for i = 1, #entries do
        local row = menu.rows[i]
        local col = math.floor((i - 1) / ROWS_PER_COL)
        local r = (i - 1) % ROWS_PER_COL
        row:ClearAllPoints()
        row:SetWidth(colW)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD + col * colW, -MENU_PAD - r * ROW_H)
    end
    menu:SetSize(cols * colW + 2 * MENU_PAD, math.max(1, rows) * ROW_H + 2 * MENU_PAD)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

------------------------------------------------------------------------
-- Picker: a grid of icons or colour swatches under a button.
-- items = { { tex = file, color = {r,g,b}, tip = text, selected = bool } },
-- or plain textures (long icon lists stay light): then `selected` is an index
-- and `tips` maps texture -> tooltip. onPick(index). Clicking the same button
-- again closes it. With `rows`, longer lists get pages (< > under the grid,
-- or the mouse wheel), opening on the page with the selected item.
------------------------------------------------------------------------
local picker
local PICK_GAP, PICK_PAD, PICK_NAV = 3, 6, 26

local function pickerCell(i, size)
    local b = picker.cells[i]
    if not b then
        b = UI.IconButton(picker, size, function(self)
            picker:Hide()
            if picker.onPick then picker.onPick(self.index) end
        end)
        b:SetScript("OnEnter", function(self)
            if not self.tip or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        picker.cells[i] = b
    end
    return b
end

local function pickerPage()
    local p = picker
    local per = p.cols * p.rows
    local pages = math.max(1, math.ceil(#p.items / per))
    p.page = math.max(1, math.min(p.page, pages))
    local first = (p.page - 1) * per
    local shownCells = math.min(per, #p.items)
    for i = 1, shownCells do
        local b = pickerCell(i, p.size)
        local it = p.items[first + i]
        if it then
            local plain = type(it) ~= "table"
            local tex = plain and it or it.tex
            b.index, b.tip = first + i, plain and p.tips and p.tips[it] or (not plain and it.tip) or nil
            b:SetSize(p.size, p.size)
            if not plain and it.color then
                b.icon:SetColorTexture(it.color[1], it.color[2], it.color[3], 1)
            else
                b.icon:SetTexture(tex)
                b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            end
            b:SetSelected((not plain and it.selected) or first + i == p.selected)
            local col, row = (i - 1) % p.cols, math.floor((i - 1) / p.cols)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", p, "TOPLEFT", PICK_PAD + col * (p.size + PICK_GAP), -(PICK_PAD + row * (p.size + PICK_GAP)))
            b:Show()
        else
            b:Hide()
        end
    end
    for i = shownCells + 1, #p.cells do p.cells[i]:Hide() end
    p.nav:SetShown(pages > 1)
    p.pageText:SetText(("Page %d of %d"):format(p.page, pages))
    p.prev:SetEnabledState(p.page > 1)
    p.next:SetEnabledState(p.page < pages)
    p.pages = pages
end

function UI.Picker(anchor, items, cols, size, onPick, rows, selected, tips)
    if not picker then
        picker = CreateFrame("Frame", nil, UIParent)
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetClampedToScreen(true)
        picker:EnableMouse(true)
        UI.Panel(picker, { 0.05, 0.05, 0.06, 0.98 }, UI.BORDER)
        UI.Window(picker, "tooltip")
        picker.cells = {}
        picker:Hide()
        picker:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
                self:Hide()
            end
        end)
        pcall(picker.RegisterEvent, picker, "GLOBAL_MOUSE_DOWN")
        local nav = CreateFrame("Frame", nil, picker)
        nav:SetPoint("BOTTOMLEFT", PICK_PAD, PICK_PAD)
        nav:SetPoint("BOTTOMRIGHT", -PICK_PAD, PICK_PAD)
        nav:SetHeight(PICK_NAV - PICK_GAP)
        picker.nav = nav
        local function turn(d)
            picker.page = picker.page + d
            pickerPage()
        end
        picker.prev = UI.Button(nav, "<", 30, 20, function() turn(-1) end)
        picker.prev:SetPoint("LEFT", 0, 0)
        picker.next = UI.Button(nav, ">", 30, 20, function() turn(1) end)
        picker.next:SetPoint("RIGHT", 0, 0)
        picker.pageText = UI.Text(nav, 11)
        picker.pageText:SetPoint("CENTER", 0, 0)
        picker.pageText:SetTextColor(0.7, 0.7, 0.75)
        picker:EnableMouseWheel(true)
        picker:SetScript("OnMouseWheel", function(_, d) turn(-d) end)
        UI.pickerFrame = picker
    end
    if picker:IsShown() and picker.anchor == anchor then
        picker:Hide()
        return
    end
    picker.anchor = anchor
    picker.onPick = onPick
    picker.items, picker.cols, picker.size, picker.selected, picker.tips = items, cols, size, selected, tips
    picker.rows = rows or math.max(1, math.ceil(#items / cols))
    picker.page = 1
    if not selected then
        for i, it in ipairs(items) do
            if type(it) == "table" and it.selected then selected = i end
        end
    end
    if selected then picker.page = math.floor((selected - 1) / (cols * picker.rows)) + 1 end
    pickerPage()
    local shownRows = math.min(picker.rows, math.max(1, math.ceil(#items / cols)))
    local shownCols = math.min(cols, #items)
    picker:SetSize(2 * PICK_PAD + shownCols * size + (shownCols - 1) * PICK_GAP,
        2 * PICK_PAD + shownRows * size + (shownRows - 1) * PICK_GAP + (picker.pages > 1 and PICK_NAV or 0))
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    picker:Show()
end

------------------------------------------------------------------------
-- Text prompt: a small edit box that floats where you need it.
------------------------------------------------------------------------
local prompt

function UI.Prompt(anchorFrame, x, y, label, initial, onAccept)
    if not prompt then
        prompt = CreateFrame("Frame", nil, UIParent)
        prompt:SetFrameStrata("FULLSCREEN_DIALOG")
        prompt:SetSize(220, 52)
        prompt:EnableMouse(true)
        UI.Panel(prompt, { 0.05, 0.05, 0.06, 0.98 }, UI.ACCENT)
        UI.Window(prompt, "tooltip")
        prompt.label = UI.Text(prompt, 11)
        prompt.label:SetPoint("TOPLEFT", 8, -6)
        prompt.label:SetTextColor(0.7, 0.7, 0.75)
        prompt.box = UI.EditBox(prompt, 204, 22)
        prompt.box:SetPoint("BOTTOMLEFT", 8, 7)
        prompt.box:SetScript("OnEnterPressed", function(self)
            local text = self:GetText()
            local cb = prompt.onAccept
            prompt:Hide()
            if cb then cb(text) end
        end)
        prompt.box:SetScript("OnEscapePressed", function() prompt:Hide() end)
        prompt.box:HookScript("OnEditFocusLost", function() prompt:Hide() end)
        UI.promptFrame = prompt
    end
    prompt.onAccept = onAccept
    prompt.label:SetText(label)
    prompt:ClearAllPoints()
    prompt:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", x, y)
    prompt:Show()
    prompt.box:SetText(initial or "")
    prompt.box:SetFocus()
    prompt.box:HighlightText()
end

------------------------------------------------------------------------
-- Copy box: read-only multi-line text, pre-selected for Ctrl+C.
------------------------------------------------------------------------
local copy

function UI.CopyBox(title, text)
    if not copy then
        copy = CreateFrame("Frame", "PogRaidCopy", UIParent)
        copy:SetSize(460, 340)
        copy:SetFrameStrata("FULLSCREEN_DIALOG")
        copy:SetPoint("CENTER")
        copy:EnableMouse(true)
        UI.Panel(copy)
        copy.metal = UI.PortraitFrame(copy, "", ns.MEDIA .. "logo", function() copy:Hide() end)
        if not copy.metal then UI.Window(copy) end
        tinsert(UISpecialFrames, "PogRaidCopy")
        UI.MakeMovable(copy, copy)
        if copy.metal then
            copy.title = copy.metal.title
            UI.MakeMovable(copy, copy.metal.strip)
        else
            copy.title = UI.Text(copy, 12)
            copy.title:SetPoint("TOPLEFT", 12, -10)
            local close = UI.CloseButton(copy, 28, 30, function() copy:Hide() end)
            close:SetPoint("TOPRIGHT", -4, 0)
        end
        local hint = UI.Text(copy, 10)
        hint:SetPoint("BOTTOMLEFT", 12, 10)
        hint:SetTextColor(0.55, 0.55, 0.6)
        hint:SetText("Ctrl+C to copy, Esc to close")

        local area = CreateFrame("ScrollFrame", nil, copy)
        area:SetPoint("TOPLEFT", 12, -36)
        area:SetPoint("BOTTOMRIGHT", -12, 30)
        local bg = area:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.02, 0.02, 0.03, 1)
        local edit = CreateFrame("EditBox", nil, area)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFont(UI.FONT, 12, "")
        edit:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
        edit:SetWidth(436)
        edit:SetTextInsets(6, 6, 6, 6)
        area:SetScrollChild(edit)
        area:EnableMouseWheel(true)
        area:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, edit:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 36)))
        end)
        edit:SetScript("OnEscapePressed", function() copy:Hide() end)
        -- read-only: typing puts the original text back
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(copy.text)
                self:HighlightText()
            end
        end)
        copy.edit = edit
    end
    copy.text = text
    copy.title:SetText(title)
    copy:Show()
    copy.edit:SetText(text)
    copy.edit:SetFocus()
    copy.edit:HighlightText()
end

------------------------------------------------------------------------
-- Compose: a small dialog with up to two one-line fields and a text area.
-- opts = { heading, label1, labelMid, label2, max1, maxMid, max2, text1,
-- textMid, text2, button, optional, noArea }. onSubmit(text1, text2, textMid).
-- Enter moves to the next box; Enter in the last one submits. `noArea`: only
-- the one-line fields.
------------------------------------------------------------------------
local compose

function UI.Compose(opts, onSubmit)
    if not compose then
        compose = CreateFrame("Frame", "PogRaidCompose", UIParent)
        compose:SetSize(400, 250)
        compose:SetFrameStrata("FULLSCREEN_DIALOG")
        compose:SetPoint("CENTER", 0, 80)
        compose:EnableMouse(true)
        UI.Panel(compose, { 0.05, 0.05, 0.06, 0.98 }, UI.ACCENT)
        UI.Window(compose)
        tinsert(UISpecialFrames, "PogRaidCompose")
        UI.MakeMovable(compose, compose)
        compose.heading = UI.Text(compose, 13)
        compose.heading:SetPoint("TOPLEFT", 12, -10)
        compose.label1 = UI.Text(compose, 11)
        compose.label1:SetPoint("TOPLEFT", 12, -34)
        compose.label1:SetTextColor(0.6, 0.6, 0.65)
        compose.field1 = UI.EditBox(compose, 376, 24)
        compose.field1:SetPoint("TOPLEFT", 12, -50)
        compose.labelMid = UI.Text(compose, 11)
        compose.labelMid:SetTextColor(0.6, 0.6, 0.65)
        compose.fieldMid = UI.EditBox(compose, 376, 24)
        compose.label2 = UI.Text(compose, 11)
        compose.label2:SetTextColor(0.6, 0.6, 0.65)
        local area = CreateFrame("Frame", nil, compose)
        area:SetSize(376, 96)
        UI.Panel(area, { 0.02, 0.02, 0.03, 1 }, UI.BUTTON_BORDER)
        compose.area = area
        local body = CreateFrame("EditBox", nil, area)
        body:SetMultiLine(true)
        body:SetAutoFocus(false)
        body:SetFont(UI.FONT, 12, "")
        body:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
        body:SetPoint("TOPLEFT", 6, -6)
        body:SetPoint("BOTTOMRIGHT", -6, 6)
        compose.field2 = body
        area:EnableMouse(true)
        area:SetScript("OnMouseDown", function() body:SetFocus() end)
        compose.count = UI.Text(compose, 10)
        compose.count:SetPoint("TOPRIGHT", area, "BOTTOMRIGHT", 0, -6)
        compose.count:SetTextColor(0.5, 0.5, 0.55)
        compose.submit = UI.Button(compose, "Post", 90, 24)
        compose.submit:SetPoint("BOTTOMRIGHT", -12, 12)
        compose.submit:SetPrimary()
        local cancel = UI.Button(compose, "Cancel", 80, 24, function() compose:Hide() end)
        cancel:SetPoint("RIGHT", compose.submit, "LEFT", -6, 0)

        local function submit()
            local a, b = compose.field1:GetText(), compose.field2:GetText()
            -- `optional`: empty boxes are fine (they clear what was there)
            if not compose.opts.optional then
                if compose.opts.label1 and a:gsub("%s", "") == "" then
                    compose.field1:SetFocus()
                    return
                end
                if not compose.opts.label1 and b:gsub("%s", "") == "" then return end
            end
            local mid = compose.fieldMid:GetText()
            local cb = compose.onSubmit
            compose:Hide()
            if cb then cb(a, b, mid) end
        end
        compose.submit:SetScript("OnClick", submit)
        compose.field1:SetScript("OnEnterPressed", function()
            if compose.fieldMid:IsShown() then
                compose.fieldMid:SetFocus()
            elseif compose.opts.noArea then
                submit()
            else
                body:SetFocus()
            end
        end)
        compose.field1:SetScript("OnEscapePressed", function() compose:Hide() end)
        compose.fieldMid:SetScript("OnEnterPressed", function()
            if compose.opts.noArea then submit() else body:SetFocus() end
        end)
        compose.fieldMid:SetScript("OnEscapePressed", function() compose:Hide() end)
        body:SetScript("OnEnterPressed", submit)
        body:SetScript("OnEscapePressed", function() compose:Hide() end)
        local function limit(box, max)
            box:SetScript("OnTextChanged", function(self)
                local t = self:GetText()
                if #t > max then self:SetText(t:sub(1, max)) end
                if self == body then compose.count:SetText(("%d / %d"):format(#self:GetText(), max)) end
            end)
        end
        compose.limit = limit
        UI.composeFrame = compose
    end
    compose.opts = opts
    compose.onSubmit = onSubmit
    compose.heading:SetText(opts.heading or "")
    compose.submit:SetLabel(opts.button or "Post")
    -- stack the boxes: each one-line field takes 50px, then the text area
    local has1, hasMid = opts.label1 ~= nil, opts.labelMid ~= nil
    local y = -34
    local function place(label, box, shown)
        label:SetShown(shown)
        box:SetShown(shown)
        if not shown then return end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 12, y)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", 12, y - 16)
        y = y - 50
    end
    place(compose.label1, compose.field1, has1)
    place(compose.labelMid, compose.fieldMid, hasMid)
    compose.label1:SetText(opts.label1 or "")
    compose.labelMid:SetText(opts.labelMid or "")
    compose.label2:ClearAllPoints()
    compose.label2:SetPoint("TOPLEFT", 12, y)
    compose.label2:SetText(opts.label2 or "")
    compose.area:ClearAllPoints()
    compose.area:SetPoint("TOPLEFT", 12, y - 16)
    local area = not opts.noArea
    compose.label2:SetShown(area)
    compose.area:SetShown(area)
    compose.count:SetShown(area)
    compose:SetHeight(area and (-y + 16 + 96 + 54) or (-y + 50))
    compose.limit(compose.field1, opts.max1 or 60)
    compose.limit(compose.fieldMid, opts.maxMid or 60)
    compose.limit(compose.field2, opts.max2 or 300)
    compose.fieldMid:SetText(opts.textMid or "")
    compose.field1:SetText(opts.text1 or "")
    compose.field2:SetText(opts.text2 or "")
    compose.count:SetText(("%d / %d"):format(#(opts.text2 or ""), opts.max2 or 300))
    compose:Show()
    if has1 then compose.field1:SetFocus() else compose.field2:SetFocus() end
end

------------------------------------------------------------------------
-- Tab: navigation text with an underline when selected, no box, so it
-- reads differently from the action buttons on each page.
------------------------------------------------------------------------
UI.TAB_TEXT = { 0.62, 0.62, 0.68 }
UI.TAB_HOVER = { 0.88, 0.88, 0.92 }

function UI.Tab(parent, text, w, h, onClick, size)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(w, h)
    t.label = t:CreateFontString(nil, "OVERLAY")
    t.label:SetFont(UI.FONT, size or 13, "")
    t.label:SetShadowOffset(1, -1)
    t.label:SetShadowColor(0, 0, 0, 0.8)
    t.label:SetPoint("CENTER", 0, 1)
    t.label:SetText(text)
    t.label:SetTextColor(UI.TAB_TEXT[1], UI.TAB_TEXT[2], UI.TAB_TEXT[3])
    t.underline = t:CreateTexture(nil, "OVERLAY")
    t.underline:SetHeight(2)
    t.underline:SetPoint("BOTTOM", 0, 0)
    t.underline:SetWidth(math.min(w, t.label:GetStringWidth() + 16))
    t.underline:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
    t.underline:Hide()
    t:SetScript("OnClick", onClick)
    t:SetScript("OnEnter", function(self)
        if not self.selected then self.label:SetTextColor(UI.TAB_HOVER[1], UI.TAB_HOVER[2], UI.TAB_HOVER[3]) end
    end)
    t:SetScript("OnLeave", function(self)
        if not self.selected then self.label:SetTextColor(UI.TAB_TEXT[1], UI.TAB_TEXT[2], UI.TAB_TEXT[3]) end
    end)
    function t:SetSelected(on)
        self.selected = on
        self.underline:SetShown(on)
        local c = on and { 1, 1, 1 } or UI.TAB_TEXT
        self.label:SetTextColor(c[1], c[2], c[3])
    end
    return t
end

------------------------------------------------------------------------
-- Close: a window's X. The classic look uses the game's red one: the square
-- atlas this client's windows have, else the round classic art (32px with the
-- circle about 20 across), drawn centred on the button;
-- the plain look, an X like the tabs. Either way the button is w x h, so
-- whatever sits beside it stays put. `visualW`: how wide it looks.
------------------------------------------------------------------------
UI.CLOSE_ART, UI.CLOSE_VISUAL, UI.CLOSE_SQUARE = 32, 20, 22
UI.CLOSE_ATLAS = { Up = "RedButton-Exit", Down = "RedButton-exit-pressed", Highlight = "RedButton-Highlight" }

function UI.HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and type(info) == "table"
end

function UI.CloseButton(parent, w, h, onClick)
    if not UI.classic then
        local t = UI.Tab(parent, "X", w, h, onClick)
        t.visualW = t.label:GetStringWidth()
        return t
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    -- this client's square red X (its windows use it), else the round classic one
    local square = UI.HasAtlas(UI.CLOSE_ATLAS.Up)
    local size = square and UI.CLOSE_SQUARE or UI.CLOSE_ART
    local function set(t, state)
        if square then t:SetAtlas(UI.CLOSE_ATLAS[state]) else t:SetTexture(UI.FILES.close .. state) end
    end
    local function art(layer, state)
        local t = b:CreateTexture(nil, layer)
        t:SetSize(size, size)
        t:SetPoint("CENTER")
        set(t, state)
        return t
    end
    b.tex = art("ARTWORK", "Up")
    local glow = art("HIGHLIGHT", "Highlight")
    if glow.SetBlendMode then glow:SetBlendMode("ADD") end
    b:SetScript("OnMouseDown", function(self) set(self.tex, "Down") end)
    b:SetScript("OnMouseUp", function(self) set(self.tex, "Up") end)
    b:SetScript("OnClick", onClick)
    b.square = square
    b.visualW = square and UI.CLOSE_SQUARE or UI.CLOSE_VISUAL
    return b
end

------------------------------------------------------------------------
-- SubTab: a page's own tabs (Raid's Roster/Attendance/..., Games), drawn like
-- the talent window's Primary / Secondary tabs (Jake): a dark tab with a thin
-- muted edge; the open one warm gold with a bright gold edge and light text.
-- Classic look only (nil otherwise: callers keep the underlined tabs). Its
-- width follows its label. t:SetSelected(on).
------------------------------------------------------------------------
UI.SUBTAB_PAD, UI.SUBTAB_GAP, UI.SUBTAB_H, UI.SUBTAB_MIN = 14, 6, 26, 80
UI.SUBTAB_COLORS = {
    fill = { 0.07, 0.068, 0.064, 0.95 }, edge = { 0.30, 0.28, 0.24, 1 }, text = { 0.62, 0.60, 0.56 },
    hoverEdge = { 0.48, 0.42, 0.30, 1 }, hoverText = { 0.85, 0.80, 0.66 },
    -- the open tab, toned down (Jake: it looked a little bright)
    selFill = { 0.21, 0.145, 0.04, 1 }, selEdge = { 0.74, 0.59, 0.20, 1 }, selText = { 0.95, 0.91, 0.80 },
}
UI.SUBTAB_SHEEN = { 0.15, 0.02 } -- the open tab's gold sheen: bottom, top
function UI.SubTab(parent, text, onClick)
    if not UI.classic then return nil end
    local C = UI.SUBTAB_COLORS
    local b = CreateFrame("Button", nil, parent)
    b.label = UI.Text(b, 12)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(text)
    b:SetSize(math.max(UI.SUBTAB_MIN, math.floor(b.label:GetStringWidth() + 2 * UI.SUBTAB_PAD + 0.5)), UI.SUBTAB_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    -- the open tab's sheen: brighter gold toward the bottom, as on the talent tabs
    b.glow = b:CreateTexture(nil, "BORDER")
    b.glow:SetAllPoints()
    b.glow:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and b.glow.SetGradient and pcall(b.glow.SetGradient, b.glow, "VERTICAL",
        CreateColor(1, 0.78, 0.25, UI.SUBTAB_SHEEN[1]), CreateColor(1, 0.85, 0.40, UI.SUBTAB_SHEEN[2]))
    if not ok then b.glow:SetColorTexture(1, 0.8, 0.3, UI.SUBTAB_SHEEN[1] / 2) end
    UI.Border(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Hover(hl, 0.05)
    local function paint(self, hover)
        local f, e, t = C.fill, C.edge, C.text
        if self.selected then
            f, e, t = C.selFill, C.selEdge, C.selText
        elseif hover then
            e, t = C.hoverEdge, C.hoverText
        end
        self.bg:SetColorTexture(f[1], f[2], f[3], f[4])
        UI.SetBorderColor(self, e)
        self.label:SetTextColor(t[1], t[2], t[3])
        self.glow:SetShown(self.selected and true or false)
    end
    function b:SetSelected(on)
        self.selected = on and true or false
        paint(self, false)
    end
    b:SetScript("OnEnter", function(self) paint(self, true) end)
    b:SetScript("OnLeave", function(self) paint(self, false) end)
    b:SetScript("OnClick", onClick)
    b:SetSelected(false)
    return b
end

------------------------------------------------------------------------
-- Check: a small box and a label. get() -> bool, set(bool). Call
-- :Update() to re-read the value; :SetEnabledState(on) greys it out.
------------------------------------------------------------------------
function UI.Check(parent, label, get, set)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(300, 22)
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(14, 14)
    c.box:SetPoint("LEFT", 0, 0)
    UI.Panel(c.box, { 0.02, 0.02, 0.03, 1 }, UI.BUTTON_BORDER)
    c.mark = c.box:CreateTexture(nil, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.mark:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
    if UI.classic then
        -- the textures are 32px with the box drawn inside: 22 shows a 14px box
        c.box.bg:Hide()
        for _, e in ipairs(c.box.edges) do e:Hide() end
        local function tex(layer, name)
            local t = c.box:CreateTexture(nil, layer)
            t:SetSize(22, 22)
            t:SetPoint("CENTER")
            t:SetTexture(UI.FILES.check .. name)
            return t
        end
        c.frameTex = tex("BACKGROUND", "Up")
        c.mark:Hide()
        c.mark = tex("ARTWORK", "Check")
        c.glow = tex("OVERLAY", "Highlight")
        if c.glow.SetBlendMode then c.glow:SetBlendMode("ADD") end
        c.glow:Hide()
    end
    c.label = UI.Text(c, 12)
    c.label:SetPoint("LEFT", c.box, "RIGHT", 8, 0)
    c.label:SetText(label)
    c.enabled = true
    function c:Update()
        self.checked = get() and true or false
        self.mark:SetShown(self.checked)
    end
    function c:SetEnabledState(on)
        self.enabled = on
        self:SetAlpha(on and 1 or 0.45)
    end
    c:SetScript("OnClick", function(self)
        if not self.enabled then return end
        set(not self.checked)
        self:Update()
        UI.Sound(self.checked and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    end)
    c:SetScript("OnEnter", function(self)
        if not self.enabled then return end
        UI.SetBorderColor(self.box, UI.ACCENT)
        if self.glow then self.glow:Show() end
    end)
    c:SetScript("OnLeave", function(self)
        UI.SetBorderColor(self.box, UI.BUTTON_BORDER)
        if self.glow then self.glow:Hide() end
    end)
    c:Update()
    return c
end
