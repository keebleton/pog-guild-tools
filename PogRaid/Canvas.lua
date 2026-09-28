-- PogRaid canvas: draws a map's art tiles plus the board items on top,
-- with zoom and pan. Shared by the editor and the viewer.
--
-- Item coordinates are 0..1 across the full map, so a board looks the same
-- at any zoom or window size. Markers, dots and text keep a fixed on-screen
-- size; arrows and circles are tied to the map.
local _, ns = ...
local UI = ns.UI

local Canvas = {}
Canvas.__index = Canvas

local BLANK_W, BLANK_H = 1002, 668   -- stand-in size when a board has no map
local MIN_ZOOM, MAX_ZOOM = 1, 6
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local HIT_PX = 9

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.75, 0.75, 0.78
end

function ns.CreateCanvas(parent, w, h)
    local self = setmetatable({}, Canvas)
    self.w, self.h = w, h
    self.zoom, self.cx, self.cy = 1, 0.5, 0.5
    self.layerW, self.layerH = BLANK_W, BLANK_H

    local clip = CreateFrame("Frame", nil, parent)
    clip:SetSize(w, h)
    clip:SetClipsChildren(true)
    local bg = clip:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.025, 0.025, 0.03, 1)
    self.frame = clip
    -- Border on its own frame above the map, or zoomed art would cover it.
    local edge = CreateFrame("Frame", nil, clip)
    edge:SetAllPoints()
    edge:SetFrameLevel(clip:GetFrameLevel() + 10)
    UI.Border(edge, UI.BORDER)

    self.map = CreateFrame("Frame", nil, clip)
    self.map:SetPoint("TOPLEFT")
    self.overlay = CreateFrame("Frame", nil, self.map)
    self.overlay:SetAllPoints(self.map)
    self.overlay:SetFrameLevel(self.map:GetFrameLevel() + 2)

    self.tiles = {}
    self.gridLines = {}
    self.pools = { tex = { n = 0 }, line = { n = 0 }, font = { n = 0 } }
    self.pulsing = {}
    self.items = {}
    self.hits = {}

    clip:SetScript("OnUpdate", nil)
    return self
end

------------------------------------------------------------------------
-- Map art
------------------------------------------------------------------------
function Canvas:SetMap(mapID)
    self.mapID = mapID
    local layer, textures
    if mapID then
        local layers = C_Map.GetMapArtLayers(mapID)
        layer = layers and layers[1]
        textures = layer and C_Map.GetMapArtLayerTextures(mapID, 1)
    end
    if layer and textures and #textures > 0 then
        self.hasArt = true
        self.layerW, self.layerH = layer.layerWidth, layer.layerHeight
        self.tileW, self.tileH = layer.tileWidth, layer.tileHeight
        self.cols = math.ceil(self.layerW / self.tileW)
        for i, fileID in ipairs(textures) do
            local tex = self.tiles[i]
            if not tex then
                tex = self.map:CreateTexture(nil, "BACKGROUND")
                self.tiles[i] = tex
            end
            tex:SetTexture(fileID, nil, nil, "TRILINEAR")
            tex:Show()
        end
        for i = #textures + 1, #self.tiles do self.tiles[i]:Hide() end
        self.numTiles = #textures
    else
        self.hasArt = false
        self.layerW, self.layerH = BLANK_W, BLANK_H
        for _, tex in ipairs(self.tiles) do tex:Hide() end
        self.numTiles = 0
    end
    self:Layout()
end

function Canvas:MapName()
    if not self.mapID then return "Blank" end
    local info = C_Map.GetMapInfo(self.mapID)
    return info and info.name or ("Map " .. self.mapID)
end

------------------------------------------------------------------------
-- View: zoom + centre
------------------------------------------------------------------------
function Canvas:SetView(zoom, cx, cy)
    self.zoom = clamp(zoom or 1, MIN_ZOOM, MAX_ZOOM)
    self.cx, self.cy = cx or 0.5, cy or 0.5
    self:Layout()
end

function Canvas:GetView()
    return self.zoom, self.cx, self.cy
end

function Canvas:Layout()
    local fit = math.min(self.w / self.layerW, self.h / self.layerH)
    local s = fit * self.zoom
    local mw, mh = self.layerW * s, self.layerH * s
    self.scale, self.mw, self.mh = s, mw, mh

    local ox = self.w / 2 - self.cx * mw
    local oy = self.h / 2 - self.cy * mh
    if mw <= self.w then ox = (self.w - mw) / 2 else ox = clamp(ox, self.w - mw, 0) end
    if mh <= self.h then oy = (self.h - mh) / 2 else oy = clamp(oy, self.h - mh, 0) end
    self.ox, self.oy = ox, oy
    self.cx, self.cy = (self.w / 2 - ox) / mw, (self.h / 2 - oy) / mh

    self.map:SetSize(mw, mh)
    self.map:ClearAllPoints()
    self.map:SetPoint("TOPLEFT", self.frame, "TOPLEFT", ox, -oy)

    if self.hasArt then
        local tw, th = self.tileW * s, self.tileH * s
        for i = 1, self.numTiles do
            local tex = self.tiles[i]
            local row, col = math.floor((i - 1) / self.cols), (i - 1) % self.cols
            tex:ClearAllPoints()
            tex:SetSize(tw, th)
            tex:SetPoint("TOPLEFT", self.map, "TOPLEFT", col * tw, -row * th)
        end
    end
    self:LayoutGrid()
    self:Render()
end

-- Faint grid so a blank board still reads as a floor plan.
function Canvas:LayoutGrid()
    local n = 0
    if not self.hasArt then
        local step = self.mw / 12
        local function line(x1, y1, x2, y2)
            n = n + 1
            local l = self.gridLines[n]
            if not l then
                l = self.map:CreateLine(nil, "BACKGROUND")
                l:SetThickness(1)
                l:SetColorTexture(1, 1, 1, 0.06)
                self.gridLines[n] = l
            end
            l:SetStartPoint("TOPLEFT", self.map, x1, -y1)
            l:SetEndPoint("TOPLEFT", self.map, x2, -y2)
            l:Show()
        end
        for i = 1, 11 do line(i * step, 0, i * step, self.mh) end
        for i = 1, math.floor(self.mh / step) do line(0, i * step, self.mw, i * step) end
    end
    for i = n + 1, #self.gridLines do self.gridLines[i]:Hide() end
end

-- Zoom by wheel steps, keeping the map point under the cursor still.
function Canvas:ZoomAt(delta, nx, ny)
    local old = self.zoom
    local z = clamp(old * (1.25 ^ delta), MIN_ZOOM, MAX_ZOOM)
    if z == old then return end
    local px, py = self.ox + nx * self.mw, self.oy + ny * self.mh
    local fit = math.min(self.w / self.layerW, self.h / self.layerH)
    local mw, mh = self.layerW * fit * z, self.layerH * fit * z
    self.zoom = z
    self.cx = (self.w / 2 - (px - nx * mw)) / mw
    self.cy = (self.h / 2 - (py - ny * mh)) / mh
    self:Layout()
end

function Canvas:Pan(dx, dy)
    self.cx = self.cx - dx / self.mw
    self.cy = self.cy + dy / self.mh
    self:Layout()
end

-- Cursor position in UI units and in 0..1 map coordinates.
function Canvas:CursorUI()
    local x, y = GetCursorPosition()
    local s = self.map:GetEffectiveScale()
    return x / s, y / s
end

function Canvas:CursorToMap()
    local x, y = self:CursorUI()
    local left, top = self.map:GetLeft(), self.map:GetTop()
    if not left then return 0.5, 0.5 end
    return (x - left) / self.mw, (top - y) / self.mh
end

------------------------------------------------------------------------
-- Item drawing (pooled regions)
------------------------------------------------------------------------
function Canvas:Acquire(kind, layer, sub)
    local pool = self.pools[kind]
    pool.n = pool.n + 1
    local r = pool[pool.n]
    if not r then
        if kind == "tex" then
            r = self.overlay:CreateTexture(nil, layer)
        elseif kind == "line" then
            r = self.overlay:CreateLine(nil, layer)
        else
            r = self.overlay:CreateFontString(nil, layer)
            r:SetFont(UI.FONT, 11, "OUTLINE")
        end
        pool[pool.n] = r
    end
    r:SetDrawLayer(layer, sub or 0)
    r:ClearAllPoints()
    r:SetAlpha(1)
    if kind == "tex" then
        r:SetTexCoord(0, 1, 0, 1)
        r:SetVertexColor(1, 1, 1, 1)
    end
    r:Show()
    return r
end

function Canvas:Disc(x, y, size, r, g, b, a, sub, file)
    local t = self:Acquire("tex", "OVERLAY", sub)
    t:SetTexture(ns.MEDIA .. (file or "disc"))
    t:SetVertexColor(r, g, b, a or 1)
    t:SetSize(size, size)
    t:SetPoint("CENTER", self.overlay, "TOPLEFT", x, -y)
    return t
end

function Canvas:Line(x1, y1, x2, y2, thick, r, g, b, a, sub)
    local l = self:Acquire("line", "ARTWORK", sub)
    l:SetColorTexture(r, g, b, a or 1)
    l:SetThickness(thick)
    l:SetStartPoint("TOPLEFT", self.overlay, x1, -y1)
    l:SetEndPoint("TOPLEFT", self.overlay, x2, -y2)
    return l
end

-- Outlined by default (text over map art). Pass plain = true for text on a
-- solid badge, where an outline only smears small glyphs.
function Canvas:Label(x, y, text, size, r, g, b, anchor, sub, plain)
    local fs = self:Acquire("font", "OVERLAY", sub or 5)
    fs:SetFont(UI.FONT, size, plain and "" or "OUTLINE")
    fs:SetShadowOffset(plain and 1 or 0, plain and -1 or 0)
    fs:SetShadowColor(0, 0, 0, plain and 0.9 or 0)
    fs:SetTextColor(r, g, b, 1)
    fs:SetText(text)
    fs:SetPoint(anchor or "CENTER", self.overlay, "TOPLEFT", x, -y)
    return fs
end

function Canvas:Pulse(tex)
    self.pulsing[#self.pulsing + 1] = tex
end

function Canvas:SetHighlight(name, group)
    self.highlightName, self.highlightGroup = name, group
end

function Canvas:DrawItem(it, index)
    local mw, mh = self.mw, self.mh
    local t = it.t
    local hit
    if t == "mark" then
        local x, y = it.x * mw, it.y * mh
        local tex = self:Acquire("tex", "OVERLAY", 3)
        tex:SetTexture(RAID_ICONS)
        SetRaidTargetIconTexture(tex, it.i)
        tex:SetSize(24, 24)
        tex:SetPoint("CENTER", self.overlay, "TOPLEFT", x, -y)
        hit = { kind = "point", x = x, y = y, r = 13 }
    elseif t == "dot" or t == "group" then
        local x, y = it.x * mw, it.y * mh
        local r, g, b, size, label, mine
        if t == "dot" then
            r, g, b = classColor(it.class)
            size, label = 13, it.name
            mine = self.highlightName and it.name == self.highlightName
        else
            local grp = ns.GROUPS[it.g]
            r, g, b = grp.color[1], grp.color[2], grp.color[3]
            size, label = 24, grp.label
            mine = self.highlightGroup and it.g == self.highlightGroup
        end
        if mine then
            self:Pulse(self:Disc(x, y, size + 18, 1, 0.9, 0.3, 1, 0, "ring"))
        end
        if t == "dot" then
            self:Disc(x, y, size + 4, 0, 0, 0, 0.85, 1)
            self:Disc(x, y, size, r, g, b, 1, 2)
        else
            -- role badge: dark face, coloured rim, coloured letter
            self:Disc(x, y, size, 0.07, 0.07, 0.08, 0.94, 1)
            self:Disc(x, y, size, r, g, b, 1, 2, "ring")
            self:Label(x, y, ns.GROUPS[it.g].short, 13, r, g, b, "CENTER", 4, true)
        end
        local fs = self:Label(x, y + size / 2 + 2, label, mine and 12 or 10,
            mine and 1 or 0.95, mine and 0.9 or 0.95, mine and 0.3 or 0.95, "TOP", 5)
        hit = { kind = "point", x = x, y = y, r = size / 2 + 4 }
        hit.labelW = fs:GetStringWidth()
    elseif t == "arrow" then
        local x1, y1, x2, y2 = it.x1 * mw, it.y1 * mh, it.x2 * mw, it.y2 * mh
        local c = ns.COLORS[it.c] or ns.COLORS[1]
        local a = math.atan2(y2 - y1, x2 - x1)
        local head = 14
        local hx1, hy1 = x2 - head * math.cos(a - 0.5), y2 - head * math.sin(a - 0.5)
        local hx2, hy2 = x2 - head * math.cos(a + 0.5), y2 - head * math.sin(a + 0.5)
        -- dark underlay keeps the arrow readable on busy map art
        self:Line(x1, y1, x2, y2, 7, 0, 0, 0, 0.55, 2)
        self:Line(x2, y2, hx1, hy1, 7, 0, 0, 0, 0.55, 2)
        self:Line(x2, y2, hx2, hy2, 7, 0, 0, 0, 0.55, 2)
        self:Line(x1, y1, x2, y2, 3.5, c[1], c[2], c[3], 1, 3)
        self:Line(x2, y2, hx1, hy1, 3.5, c[1], c[2], c[3], 1, 3)
        self:Line(x2, y2, hx2, hy2, 3.5, c[1], c[2], c[3], 1, 3)
        hit = { kind = "segment", x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    elseif t == "line" then
        local x1, y1, x2, y2 = it.x1 * mw, it.y1 * mh, it.x2 * mw, it.y2 * mh
        local c = ns.COLORS[it.c] or ns.COLORS[5]
        self:Line(x1, y1, x2, y2, 6, 0, 0, 0, 0.45, 2)
        self:Line(x1, y1, x2, y2, 3.5, c[1], c[2], c[3], 1, 3)
        hit = { kind = "segment", x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    elseif t == "pen" then
        local c = ns.COLORS[it.c] or ns.COLORS[5]
        local pts, px = it.pts, {}
        for i = 1, #pts, 2 do
            px[#px + 1], px[#px + 2] = pts[i] * mw, pts[i + 1] * mh
        end
        for i = 1, #px - 3, 2 do
            self:Line(px[i], px[i + 1], px[i + 2], px[i + 3], 6, 0, 0, 0, 0.45, 2)
        end
        for i = 1, #px - 3, 2 do
            self:Line(px[i], px[i + 1], px[i + 2], px[i + 3], 3.5, c[1], c[2], c[3], 1, 3)
        end
        hit = { kind = "poly", pts = px }
    elseif t == "rect" then
        local x1, y1, x2, y2 = it.x1 * mw, it.y1 * mh, it.x2 * mw, it.y2 * mh
        local c = ns.COLORS[it.c] or ns.COLORS[5]
        local style = ns.STYLES[it.s or 1] or ns.STYLES[1]
        if style.fill then
            local fill = self:Acquire("tex", "ARTWORK", 0)
            fill:SetTexture("Interface\\Buttons\\WHITE8X8")
            fill:SetVertexColor(c[1], c[2], c[3], style.fill)
            fill:SetSize(x2 - x1, y2 - y1)
            fill:SetPoint("TOPLEFT", self.overlay, "TOPLEFT", x1, -y1)
        end
        -- edges overlap by half the thickness so the corners close squarely
        local e = 1.25
        self:Line(x1 - e, y1, x2 + e, y1, 2.5, c[1], c[2], c[3], 0.95, 1)
        self:Line(x1 - e, y2, x2 + e, y2, 2.5, c[1], c[2], c[3], 0.95, 1)
        self:Line(x1, y1, x1, y2, 2.5, c[1], c[2], c[3], 0.95, 1)
        self:Line(x2, y1, x2, y2, 2.5, c[1], c[2], c[3], 0.95, 1)
        hit = { kind = "box", x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    elseif t == "circle" then
        local x, y, r = it.x * mw, it.y * mh, it.r * mw
        local c = ns.COLORS[it.c] or ns.COLORS[1]
        local style = ns.STYLES[it.s or 1] or ns.STYLES[1]
        if style.fill then
            local fill = self:Acquire("tex", "ARTWORK", 0)
            fill:SetTexture(ns.MEDIA .. "disc")
            fill:SetVertexColor(c[1], c[2], c[3], style.fill)
            fill:SetSize(r * 2, r * 2)
            fill:SetPoint("CENTER", self.overlay, "TOPLEFT", x, -y)
        end
        local n = clamp(math.floor(r / 4), 16, 64)
        local px, py = x + r, y
        for i = 1, n do
            local ang = i / n * 2 * math.pi
            local qx, qy = x + r * math.cos(ang), y + r * math.sin(ang)
            self:Line(px, py, qx, qy, 2.5, c[1], c[2], c[3], 0.95, 1)
            px, py = qx, qy
        end
        hit = { kind = "circle", x = x, y = y, r = r }
    elseif t == "text" then
        local x, y = it.x * mw, it.y * mh
        local c = ns.COLORS[it.c] or ns.COLORS[5]
        local fs = self:Label(x, y, it.s, 13, c[1], c[2], c[3], "CENTER", 6)
        hit = { kind = "rect", x = x, y = y, hw = fs:GetStringWidth() / 2 + 4, hh = 10 }
    end
    if hit and index then
        hit.index = index
        self.hits[#self.hits + 1] = hit
    end
end

-- snap: optional {x, y} (0..1) to mark a point a line end will snap to.
function Canvas:SetItems(items, preview, snap)
    self.items = items or {}
    self.preview = preview
    self.snapMark = snap
    self:Render()
end

function Canvas:Render()
    if not self.mw then return end
    for _, pool in pairs(self.pools) do pool.n = 0 end
    wipe(self.hits)
    wipe(self.pulsing)
    for i, it in ipairs(self.items or {}) do self:DrawItem(it, i) end
    if self.preview then self:DrawItem(self.preview) end
    if self.snapMark then
        self:Disc(self.snapMark.x * self.mw, self.snapMark.y * self.mh, 14, 1, 1, 1, 0.9, 7, "ring")
    end
    for _, pool in pairs(self.pools) do
        for i = pool.n + 1, #pool do pool[i]:Hide() end
    end
    if #self.pulsing > 0 then
        self.frame:SetScript("OnUpdate", function()
            local a = 0.55 + 0.45 * math.sin(GetTime() * 5)
            for _, tex in ipairs(self.pulsing) do tex:SetAlpha(a) end
        end)
    else
        self.frame:SetScript("OnUpdate", nil)
    end
end

------------------------------------------------------------------------
-- Hit testing (editor). Returns the index of the topmost item under the
-- given map point, or nil.
------------------------------------------------------------------------
local function segDist(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and clamp(((px - x1) * dx + (py - y1) * dy) / len2, 0, 1) or 0
    local cx, cy = x1 + t * dx, y1 + t * dy
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

-- Markers, dots, lines and text win over filled shapes, so anything
-- sitting inside a zone stays clickable. Circles and rectangles count
-- anywhere inside them (plus a little slack past the edge); when they
-- overlap, the smallest one wins.
ns.SegDist = segDist

function Canvas:HitTest(nx, ny)
    local px, py = nx * self.mw, ny * self.mh
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if h.kind == "point" then
            if math.sqrt((px - h.x) ^ 2 + (py - h.y) ^ 2) <= h.r then return h.index end
        elseif h.kind == "segment" then
            if segDist(px, py, h.x1, h.y1, h.x2, h.y2) <= HIT_PX then return h.index end
        elseif h.kind == "poly" then
            local p = h.pts
            for j = 1, #p - 3, 2 do
                if segDist(px, py, p[j], p[j + 1], p[j + 2], p[j + 3]) <= HIT_PX then return h.index end
            end
        elseif h.kind == "rect" then
            if math.abs(px - h.x) <= h.hw and math.abs(py - h.y) <= h.hh then return h.index end
        end
    end
    local best, bestArea
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        local area
        if h.kind == "circle" then
            if math.sqrt((px - h.x) ^ 2 + (py - h.y) ^ 2) <= h.r + HIT_PX then area = math.pi * h.r * h.r end
        elseif h.kind == "box" then
            if px >= h.x1 - HIT_PX and px <= h.x2 + HIT_PX and py >= h.y1 - HIT_PX and py <= h.y2 + HIT_PX then
                area = (h.x2 - h.x1) * (h.y2 - h.y1)
            end
        end
        if area and (not bestArea or area < bestArea) then best, bestArea = h.index, area end
    end
    return best
end

-- Nearest wall end (line/pen ends, rectangle corners) within `radius`
-- screen pixels of a 0..1 point. Returns the snapped point, or nil.
function Canvas:SnapPoint(nx, ny, radius)
    local px, py = nx * self.mw, ny * self.mh
    local bestX, bestY, bestD
    local function try(x, y)
        local d = math.sqrt((px - x * self.mw) ^ 2 + (py - y * self.mh) ^ 2)
        if d <= radius and (not bestD or d < bestD) then bestX, bestY, bestD = x, y, d end
    end
    for _, it in ipairs(self.items or {}) do
        if it.t == "line" then
            try(it.x1, it.y1)
            try(it.x2, it.y2)
        elseif it.t == "pen" then
            local p = it.pts
            try(p[1], p[2])
            try(p[#p - 1], p[#p])
        elseif it.t == "rect" then
            try(it.x1, it.y1)
            try(it.x2, it.y1)
            try(it.x1, it.y2)
            try(it.x2, it.y2)
        end
    end
    if bestX then return bestX, bestY end
end

-- Map-pixel distance between two 0..1 points (used for drag thresholds).
function Canvas:PixelDistance(x1, y1, x2, y2)
    return math.sqrt(((x2 - x1) * self.mw) ^ 2 + ((y2 - y1) * self.mh) ^ 2)
end
