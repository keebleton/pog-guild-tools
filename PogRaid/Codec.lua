-- PogRaid codec: boards <-> compact strings for addon messages.
--
-- Wire format (fields separated by ";", text fields percent-escaped):
--   KR1;<mapID or 0>;<zoom*100>;<cx cy>;<name>;<item>;<item>...
-- Coordinates are 0..1 across the map, quantised to 12 bits and written as
-- two base64 characters each. Items:
--   M<icon 1-8><x><y>               raid marker
--   D<class><x><y><name>            player dot (class letter or "-")
--   G<role T/H/M/R><x><y>           role group dot
--   A<color><x1><y1><x2><y2>        arrow
--   L<color><x1><y1><x2><y2>        line (walls)
--   R<color><style><x1><y1><x2><y2> rectangle (corners)
--   C<color><x><y><radius>[style]   circle (radius as a fraction of map width;
--                                   style digit optional, 0.1.0 boards omit it)
--   P<color><x><y><x><y>...         freehand pen stroke, 2..MAX_PEN points
--   T<color><x><y><text>            text label
-- Colours and styles are single digits (see ns.COLORS, ns.STYLES).
local _, ns = ...

local Codec = {}
ns.Codec = Codec

Codec.MAX_ITEMS = 150
Codec.MAX_TEXT = 60
Codec.MAX_NAME = 40
Codec.MAX_PEN = 60

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:sub(i, i)] = i - 1 end
local QMAX = 4095

-- Class letters. Order is part of the wire format: only ever append.
Codec.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local CLASS_TO_LETTER, LETTER_TO_CLASS = {}, {}
for i, class in ipairs(Codec.CLASSES) do
    local letter = string.char(96 + i) -- a, b, c ...
    CLASS_TO_LETTER[class] = letter
    LETTER_TO_CLASS[letter] = class
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function int(v, lo, hi)
    return math.floor(clamp(tonumber(v) or lo, lo, hi))
end

local function encQ(v)
    local n = math.floor(clamp(tonumber(v) or 0, 0, 1) * QMAX + 0.5)
    local hi, lo = math.floor(n / 64), n % 64
    return B64:sub(hi + 1, hi + 1) .. B64:sub(lo + 1, lo + 1)
end

local function decQ(s, i)
    local hi, lo = DEC[s:sub(i, i)], DEC[s:sub(i + 1, i + 1)]
    if not hi or not lo then return nil end
    return (hi * 64 + lo) / QMAX
end

-- Single line of printable text, capped. Removes control characters (and
-- with them WoW's own "|" escape sequences' ability to do anything).
function Codec.CleanText(s, maxLen)
    s = tostring(s or ""):gsub("%c", " "):gsub("|", "/")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function esc(s)
    return (s:gsub("[%%;~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function split(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            return out
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
end

local function encodeItem(it)
    local t = it.t
    if t == "mark" then
        return "M" .. int(it.i, 1, 8) .. encQ(it.x) .. encQ(it.y)
    elseif t == "dot" then
        return "D" .. (CLASS_TO_LETTER[it.class or ""] or "-") .. encQ(it.x) .. encQ(it.y)
            .. esc(Codec.CleanText(it.name, Codec.MAX_NAME))
    elseif t == "group" then
        local g = ns.GROUPS[it.g or ""] and it.g or "T"
        return "G" .. g .. encQ(it.x) .. encQ(it.y)
    elseif t == "arrow" then
        return "A" .. int(it.c, 1, #ns.COLORS) .. encQ(it.x1) .. encQ(it.y1) .. encQ(it.x2) .. encQ(it.y2)
    elseif t == "line" then
        return "L" .. int(it.c, 1, #ns.COLORS) .. encQ(it.x1) .. encQ(it.y1) .. encQ(it.x2) .. encQ(it.y2)
    elseif t == "rect" then
        return "R" .. int(it.c, 1, #ns.COLORS) .. int(it.s or 1, 1, #ns.STYLES)
            .. encQ(it.x1) .. encQ(it.y1) .. encQ(it.x2) .. encQ(it.y2)
    elseif t == "circle" then
        return "C" .. int(it.c, 1, #ns.COLORS) .. encQ(it.x) .. encQ(it.y) .. encQ(it.r)
            .. int(it.s or 1, 1, #ns.STYLES)
    elseif t == "pen" then
        local pts = it.pts or {}
        local n = math.min(math.floor(#pts / 2), Codec.MAX_PEN)
        if n < 2 then return nil end
        local out = { "P", int(it.c, 1, #ns.COLORS) }
        for i = 1, n do
            out[#out + 1] = encQ(pts[2 * i - 1]) .. encQ(pts[2 * i])
        end
        return table.concat(out)
    elseif t == "text" then
        return "T" .. int(it.c or 5, 1, #ns.COLORS) .. encQ(it.x) .. encQ(it.y)
            .. esc(Codec.CleanText(it.s, Codec.MAX_TEXT))
    end
end

local function digit(s, i, max)
    local n = tonumber(s:sub(i, i))
    if n and n >= 1 and n <= max then return n end
end

local function decodeItem(s)
    local k = s:sub(1, 1)
    local ncol = #ns.COLORS
    if k == "M" and #s == 6 then
        local i, x, y = digit(s, 2, 8), decQ(s, 3), decQ(s, 5)
        if i and x and y then return { t = "mark", i = i, x = x, y = y } end
    elseif k == "D" and #s >= 7 then
        local x, y = decQ(s, 3), decQ(s, 5)
        local name = Codec.CleanText(unesc(s:sub(7)), Codec.MAX_NAME)
        if x and y and name ~= "" then
            return { t = "dot", class = LETTER_TO_CLASS[s:sub(2, 2)], name = name, x = x, y = y }
        end
    elseif k == "G" and #s == 6 then
        local g, x, y = s:sub(2, 2), decQ(s, 3), decQ(s, 5)
        if ns.GROUPS[g] and x and y then return { t = "group", g = g, x = x, y = y } end
    elseif k == "A" and #s == 10 then
        local c, x1, y1, x2, y2 = digit(s, 2, ncol), decQ(s, 3), decQ(s, 5), decQ(s, 7), decQ(s, 9)
        if c and x1 and y1 and x2 and y2 then return { t = "arrow", c = c, x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end
    elseif k == "L" and #s == 10 then
        local c, x1, y1, x2, y2 = digit(s, 2, ncol), decQ(s, 3), decQ(s, 5), decQ(s, 7), decQ(s, 9)
        if c and x1 and y1 and x2 and y2 then return { t = "line", c = c, x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end
    elseif k == "R" and #s == 11 then
        local c, st = digit(s, 2, ncol), digit(s, 3, #ns.STYLES)
        local x1, y1, x2, y2 = decQ(s, 4), decQ(s, 6), decQ(s, 8), decQ(s, 10)
        if c and st and x1 and y1 and x2 and y2 then
            return { t = "rect", c = c, s = st, x1 = math.min(x1, x2), y1 = math.min(y1, y2),
                x2 = math.max(x1, x2), y2 = math.max(y1, y2) }
        end
    elseif k == "C" and (#s == 8 or #s == 9) then
        local c, x, y, r = digit(s, 2, ncol), decQ(s, 3), decQ(s, 5), decQ(s, 7)
        local st = (#s == 9) and digit(s, 9, #ns.STYLES) or 1
        if c and x and y and r and r > 0 and st then return { t = "circle", c = c, s = st, x = x, y = y, r = r } end
    elseif k == "P" and #s >= 10 and (#s - 2) % 4 == 0 then
        local c = digit(s, 2, ncol)
        local n = math.min((#s - 2) / 4, Codec.MAX_PEN)
        local pts = {}
        for i = 1, n do
            local x, y = decQ(s, 4 * i - 1), decQ(s, 4 * i + 1)
            if not x or not y then return nil end
            pts[#pts + 1], pts[#pts + 2] = x, y
        end
        if c then return { t = "pen", c = c, pts = pts } end
    elseif k == "T" and #s >= 7 then
        local c, x, y = digit(s, 2, ncol), decQ(s, 3), decQ(s, 5)
        local text = Codec.CleanText(unesc(s:sub(7)), Codec.MAX_TEXT)
        if c and x and y and text ~= "" then return { t = "text", c = c, x = x, y = y, s = text } end
    end
end

function Codec.Encode(board)
    local parts = {
        "KR1",
        tostring(math.floor(tonumber(board.map) or 0)),
        tostring(math.floor(clamp(tonumber(board.zoom) or 1, 1, 8) * 100 + 0.5)),
        encQ(board.cx or 0.5) .. encQ(board.cy or 0.5),
        esc(Codec.CleanText(board.name, Codec.MAX_NAME)),
    }
    local n = 0
    for _, it in ipairs(board.items or {}) do
        local s = encodeItem(it)
        if s then
            parts[#parts + 1] = s
            n = n + 1
            if n >= Codec.MAX_ITEMS then break end
        end
    end
    return table.concat(parts, ";")
end

-- Returns a board table, or nil plus a reason. Items that fail validation
-- are dropped rather than rejecting the whole board.
function Codec.Decode(str)
    if type(str) ~= "string" then return nil, "not a string" end
    local f = split(str, ";")
    if f[1] ~= "KR1" then return nil, "unknown format" end
    if #f < 5 then return nil, "truncated" end
    local map = tonumber(f[2])
    local zoom = tonumber(f[3])
    local cx, cy = decQ(f[4] or "", 1), decQ(f[4] or "", 3)
    if not map or not zoom or not cx or not cy then return nil, "bad header" end
    local board = {
        map = (map > 0) and map or nil,
        zoom = clamp(zoom / 100, 1, 8),
        cx = cx, cy = cy,
        name = Codec.CleanText(unesc(f[5]), Codec.MAX_NAME),
        items = {},
    }
    if board.name == "" then board.name = "Plan" end
    for i = 6, math.min(#f, 5 + Codec.MAX_ITEMS) do
        local it = decodeItem(f[i])
        if it then board.items[#board.items + 1] = it end
    end
    return board
end

function Codec.CopyItems(items)
    local out = {}
    for i, it in ipairs(items) do
        local c = {}
        for k, v in pairs(it) do
            if type(v) == "table" then
                local copy = {}
                for j, p in ipairs(v) do copy[j] = p end
                v = copy
            end
            c[k] = v
        end
        out[i] = c
    end
    return out
end
