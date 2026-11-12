-- Pog Guild Tools games: Motherlode, a peg-drop roguelike (Jake, 0.16.9).
--
-- You bomb your way down a mine. Each floor is a board of ore pegs: aim with
-- the mouse, click to drop a bomb from the top, and every peg it bounces off
-- is mined. The pocket it lands in multiplies what that bomb mined. Reach
-- the floor's ore quota before the bombs run out and you go down a floor,
-- picking one of three upgrades on the way; miss it and the run is over.
--
-- The rules (Lode.Run) know nothing of the screen and take their dice from a
-- seeded generator, so a run can be replayed step for step in the tests.
-- Board space: Lode.W x Lode.H, x to the right, y DOWN from the top edge.
local _, ns = ...
local UI = ns.UI

local Lode = {}
ns.Lode = Lode

Lode.W, Lode.H = 560, 566
Lode.BALL_R, Lode.PEG_R = 7, 11
Lode.GRAVITY = 700          -- px/s^2
Lode.SPEED = 480            -- a bomb's launch speed
Lode.BOUNCE = 0.78          -- speed kept bouncing off a peg
Lode.WALL_BOUNCE = 0.70
Lode.STEP = 1 / 240         -- the physics tick (a bomb moves well under its radius in one)
Lode.MAX_AIM = math.rad(80) -- either side of straight down
Lode.LAUNCH_Y = 26
Lode.POCKETS = { 1, 2, 5, 2, 1 }
Lode.POCKET_H = 34
Lode.BOMBS = 5              -- per floor
Lode.MAX_HITS = 3           -- a peg bounced on this often crumbles at once (so nothing rests on it)
Lode.SHOT_CAP = 12          -- seconds: a bomb still in the air then just lands
Lode.MAX_BALLS = 8
Lode.KEG_R = 62
Lode.PEGS, Lode.GOLD, Lode.KEGS, Lode.CRYSTALS = 46, 5, 3, 2
-- The first floor's quota and how it grows. Tuned by playing a few hundred runs headless: clicking at random
-- clears about 2 floors, picking the best of four aims about 7, of ten about 9 (at 250 and 1.3 random play
-- cleared 19).
Lode.QUOTA, Lode.QUOTA_GROWTH = 450, 1.5
Lode.share = true           -- our best run is shared with the guild (the "lode" collection below)

-- the seam changes every two floors: { item (for its icon), name, icon if the item isn't known }
Lode.ORES = {
    { 2770, "Copper", "Interface\\Icons\\INV_Ore_Copper_01" }, { 2771, "Tin", "Interface\\Icons\\INV_Ore_Tin_01" },
    { 2772, "Iron", "Interface\\Icons\\INV_Ore_Iron_01" }, { 3858, "Mithril", "Interface\\Icons\\INV_Ore_Mithril_02" },
    { 10620, "Thorium", "Interface\\Icons\\INV_Ore_Thorium_02" }, { 11370, "Dark Iron", "Interface\\Icons\\INV_Ore_Mithril_01" },
}
Lode.KINDS = {
    gold = { 2776, "Gold vein", "Interface\\Icons\\INV_Ore_Copper_01", { 1.00, 0.82, 0.20 } },
    keg = { 4378, "Powder keg", "Interface\\Icons\\INV_Misc_Bomb_06", { 0.95, 0.35, 0.25 } },
    crystal = { 12363, "Crystal", "Interface\\Icons\\INV_Misc_Gem_Sapphire_01", { 0.45, 0.80, 1.00 } },
    ore = { nil, "Ore", nil, { 0.62, 0.55, 0.45 } },
}

-- key, name, what it does, how many times it can be taken
Lode.UPGRADES = {
    { "spare", "Spare Bomb", "+1 bomb every floor.", 5 },
    { "fever", "Gold Fever", "Gold veins pay double.", 5 },
    { "rich", "Rich Seams", "+3 ore from every peg.", 9 },
    { "loaded", "Loaded Pockets", "+1 to every pocket's multiplier.", 4 },
    { "prospector", "Prospector", "2 extra gold veins every floor.", 4 },
    { "big", "Big Kegs", "Kegs blow up a bigger area.", 3 },
    { "twin", "Twin Fuse", "Your bomb splits in two on its first hit.", 1 },
    { "rubber", "Rubber Shell", "Bouncier bombs.", 3 },
    { "lucky", "Lucky Strike", "+10% chance for ore to count double.", 5 },
    { "deep", "Deep Pockets", "Leftover bombs carry over to the next floor.", 1 },
}
Lode.UPGRADE = {}
for _, u in ipairs(Lode.UPGRADES) do Lode.UPGRADE[u[1]] = u end

------------------------------------------------------------------------
-- Rules (no UI)
------------------------------------------------------------------------
-- A seeded generator (Park-Miller): the same seed gives the same run.
function Lode.Rng(seed)
    local s = math.floor(tonumber(seed) or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return (s - 1) / 2147483646
    end
end

function Lode.Quota(floor)
    return math.floor(Lode.QUOTA * Lode.QUOTA_GROWTH ^ (floor - 1) / 10 + 0.5) * 10
end

function Lode.Ore(floor)
    return Lode.ORES[math.min(#Lode.ORES, math.floor((floor - 1) / 2) + 1)]
end

-- A floor's pegs: a staggered grid of spots, jittered, a random lot of them
-- filled. `gold` veins, the kegs and crystals, the rest ore.
function Lode.Board(rand, gold)
    local W, H = Lode.W, Lode.H
    local left, right, top, bottom = 36, W - 36, 96, H - Lode.POCKET_H - 60
    local cols, rows = 9, 8
    local dx, dy = (right - left) / (cols - 1), (bottom - top) / (rows - 1)
    local spots = {}
    for r = 0, rows - 1 do
        local odd = r % 2 == 1
        for c = 0, (odd and cols - 2 or cols - 1) do
            spots[#spots + 1] = { x = left + c * dx + (odd and dx / 2 or 0), y = top + r * dy }
        end
    end
    for i = #spots, 2, -1 do
        local j = math.floor(rand() * i) + 1
        spots[i], spots[j] = spots[j], spots[i]
    end
    local pegs = {}
    local n = math.min(#spots, Lode.PEGS)
    local kegs, crystals = Lode.KEGS, Lode.CRYSTALS
    gold = math.min(gold or Lode.GOLD, n - kegs - crystals)
    for i = 1, n do
        local kind = i <= kegs and "keg" or i <= kegs + crystals and "crystal" or i <= kegs + crystals + gold and "gold" or "ore"
        pegs[i] = { x = spots[i].x + (rand() - 0.5) * 10, y = spots[i].y + (rand() - 0.5) * 10, kind = kind, hits = 0 }
    end
    return pegs
end

local Run = {}
Run.__index = Run
Lode.Run = Run

function Run.New(seed)
    -- `events` is what has happened since someone last looked (a peg mined, a keg gone up, a bomb landed):
    -- the screen shows them and empties the list; the rules never read it
    local run = setmetatable({ seed = seed, rand = Lode.Rng(seed), floor = 0, total = 0, cleared = 0, shots = 0,
        upgrades = {}, carried = 0, balls = {}, events = {}, state = "aim" }, Run)
    run:NextFloor()
    return run
end

function Run:Has(key) return self.upgrades[key] or 0 end
function Run:OreValue() return 10 + 2 * (self.floor - 1) + 3 * self:Has("rich") end
function Run:GoldValue() return self:OreValue() * 5 * (1 + self:Has("fever")) end
function Run:KegRadius() return Lode.KEG_R * (1 + 0.3 * self:Has("big")) end
function Run:PocketMult(p) return Lode.POCKETS[p] + self:Has("loaded") end

function Run:NextFloor()
    self.floor = self.floor + 1
    self.ore, self.quota = 0, Lode.Quota(self.floor)
    self.bombs = Lode.BOMBS + self:Has("spare") + self.carried
    self.carried = 0
    self.pegs = Lode.Board(self.rand, Lode.GOLD + 2 * self:Has("prospector"))
    self.balls, self.offers, self.last = {}, nil, nil
    self.state = "aim"
    self.dirty = true
end

-- Drop a bomb. `angle` is from straight down, in radians, right positive.
function Run:Fire(angle)
    if self.state ~= "aim" or self.bombs <= 0 then return false end
    angle = math.max(-Lode.MAX_AIM, math.min(Lode.MAX_AIM, tonumber(angle) or 0))
    self.bombs = self.bombs - 1
    self.shots = self.shots + 1
    self.balls = { { x = Lode.W / 2, y = Lode.LAUNCH_Y, vx = Lode.SPEED * math.sin(angle), vy = Lode.SPEED * math.cos(angle),
        ore = 0, first = true } }
    self.landed, self.events, self.pegsHit = {}, {}, 0
    self.state, self.shotTime, self.acc = "flying", 0, 0
    self.dirty = true
    return true
end

-- A peg is mined (once): its ore goes to the bomb that did it.
function Run:Mine(peg, ball)
    if peg.lit then return end
    peg.lit = true
    local v = self:OreValue()
    if peg.kind == "gold" then
        v = self:GoldValue()
    elseif peg.kind == "ore" and self.rand() < 0.1 * self:Has("lucky") then
        v = v * 2
        peg.lucky = true
    end
    ball.ore = ball.ore + v
    self.pegsHit = (self.pegsHit or 0) + 1
    self.events[#self.events + 1] = { kind = "mine", x = peg.x, y = peg.y, v = v, peg = peg.kind, lucky = peg.lucky, ref = peg }
    self.dirty = true
end

-- A keg goes up: everything near it is mined and gone, other kegs in turn.
function Run:Explode(keg, ball)
    keg.gone = true
    local r2 = self:KegRadius() ^ 2
    for _, p in ipairs(self.pegs) do
        if not p.gone and (p.x - keg.x) ^ 2 + (p.y - keg.y) ^ 2 <= r2 then
            self:Mine(p, ball)
            if p.kind == "keg" then self:Explode(p, ball) else p.gone = true end
        end
    end
    self.blasts = self.blasts or {}
    self.blasts[#self.blasts + 1] = { x = keg.x, y = keg.y, r = self:KegRadius() }
    self.events[#self.events + 1] = { kind = "blast", x = keg.x, y = keg.y, r = self:KegRadius() }
end

-- A second bomb from where this one is, going the other way.
function Run:Split(ball)
    if #self.balls >= Lode.MAX_BALLS then return end
    local vx = -ball.vx
    if math.abs(vx) < 60 then vx = (ball.vx >= 0 and -1 or 1) * 120 end
    self.balls[#self.balls + 1] = { x = ball.x, y = ball.y, vx = vx, vy = ball.vy, ore = 0 }
end

function Run:Hit(peg, ball)
    peg.hits = peg.hits + 1
    if peg.lit then self.events[#self.events + 1] = { kind = "hit", ref = peg } end
    self:Mine(peg, ball)
    if peg.kind == "keg" then
        self:Explode(peg, ball)
    elseif peg.kind == "crystal" then
        peg.gone = true
        self:Split(ball)
    elseif peg.hits >= Lode.MAX_HITS then
        peg.gone = true
    end
    if ball.first then
        ball.first = nil
        if self:Has("twin") > 0 then self:Split(ball) end
    end
    self.dirty = true
end

-- A bomb reaches the bottom: its pocket multiplies what it mined.
function Run:Land(ball)
    ball.done = true
    local p = math.max(1, math.min(#Lode.POCKETS, math.floor(ball.x / (Lode.W / #Lode.POCKETS)) + 1))
    local mult = self:PocketMult(p)
    local gain = ball.ore * mult
    self.ore, self.total = self.ore + gain, self.total + gain
    self.landed[#self.landed + 1] = { pocket = p, mult = mult, ore = ball.ore, gain = gain }
    self.events[#self.events + 1] = { kind = "land", pocket = p, mult = mult, gain = gain }
    self.dirty = true
end

function Run:Tick(h)
    local W, r, R = Lode.W, Lode.BALL_R, Lode.PEG_R
    local reach = (r + R) ^ 2
    local e = Lode.BOUNCE + 0.06 * self:Has("rubber")
    self.shotTime = self.shotTime + h
    local flying = false
    for i = 1, #self.balls do
        local b = self.balls[i]
        if not b.done then
            b.vy = b.vy + Lode.GRAVITY * h
            b.x, b.y = b.x + b.vx * h, b.y + b.vy * h
            if b.x < r then
                b.x = r
                if b.vx < 0 then b.vx = -b.vx * Lode.WALL_BOUNCE end
            elseif b.x > W - r then
                b.x = W - r
                if b.vx > 0 then b.vx = -b.vx * Lode.WALL_BOUNCE end
            end
            if b.y < r then
                b.y = r
                if b.vy < 0 then b.vy = -b.vy * Lode.WALL_BOUNCE end
            end
            for _, p in ipairs(self.pegs) do
                if not p.gone then
                    local dx, dy = b.x - p.x, b.y - p.y
                    local d2 = dx * dx + dy * dy
                    if d2 < reach then
                        local d = math.sqrt(d2)
                        local nx, ny = 0, -1
                        if d > 0 then nx, ny = dx / d, dy / d end
                        b.x, b.y = p.x + nx * (r + R), p.y + ny * (r + R)
                        local vn = b.vx * nx + b.vy * ny
                        if vn < 0 then
                            b.vx, b.vy = b.vx - (1 + e) * vn * nx, b.vy - (1 + e) * vn * ny
                            self:Hit(p, b)
                        end
                    end
                end
            end
            if b.y >= Lode.H - Lode.POCKET_H / 2 or self.shotTime > Lode.SHOT_CAP then
                self:Land(b)
            else
                flying = true
            end
        end
    end
    if not flying then self:EndShot() end
end

-- Every bomb is down: what was mined is cleared away, and the floor is won,
-- lost or goes on.
function Run:EndShot()
    local gain = 0
    for _, l in ipairs(self.landed) do gain = gain + l.gain end
    self.last = { gain = gain, landed = self.landed }
    for _, p in ipairs(self.pegs) do
        if p.lit then p.gone = true end
    end
    self.balls = {}
    if self.ore >= self.quota then
        self.cleared = self.floor
        if self:Has("deep") > 0 then self.carried = self.bombs end
        self.offers = self:Offers()
        self.state = self.offers[1] and "choose" or "aim"
        if not self.offers[1] then self:NextFloor() end
    elseif self.bombs <= 0 then
        self.state = "over"
    else
        self.state = "aim"
    end
    self.dirty = true
end

-- Advance the bombs in the air by `dt` seconds of real time.
function Run:Step(dt)
    if self.state ~= "flying" then return end
    self.acc = self.acc + math.min(dt or 0, 0.05)
    while self.acc >= Lode.STEP and self.state == "flying" do
        self.acc = self.acc - Lode.STEP
        self:Tick(Lode.STEP)
    end
end

-- Three upgrades to pick from (fewer once most are taken as often as they can be).
function Run:Offers()
    local pool = {}
    for _, u in ipairs(Lode.UPGRADES) do
        if self:Has(u[1]) < u[4] then pool[#pool + 1] = u[1] end
    end
    local out = {}
    for _ = 1, math.min(3, #pool) do
        out[#out + 1] = table.remove(pool, math.floor(self.rand() * #pool) + 1)
    end
    return out
end

function Run:Choose(i)
    local key = self.state == "choose" and self.offers and self.offers[i]
    if not key then return false end
    self.upgrades[key] = self:Has(key) + 1
    self:NextFloor()
    return true
end

-- Where a bomb dropped at `angle` would go until it first touches a peg (or
-- lands): points `gap` seconds apart, for the aiming dots.
function Run:Preview(angle, count, gap)
    angle = math.max(-Lode.MAX_AIM, math.min(Lode.MAX_AIM, tonumber(angle) or 0))
    local W, r = Lode.W, Lode.BALL_R
    local reach = (r + Lode.PEG_R) ^ 2
    local x, y, vx, vy = W / 2, Lode.LAUNCH_Y, Lode.SPEED * math.sin(angle), Lode.SPEED * math.cos(angle)
    local out, h, t = {}, Lode.STEP, 0
    while #out < count do
        vy = vy + Lode.GRAVITY * h
        x, y = x + vx * h, y + vy * h
        if x < r then x, vx = r, math.abs(vx) * Lode.WALL_BOUNCE elseif x > W - r then x, vx = W - r, -math.abs(vx) * Lode.WALL_BOUNCE end
        if y >= Lode.H - Lode.POCKET_H / 2 then break end
        for _, p in ipairs(self.pegs) do
            if not p.gone and (x - p.x) ^ 2 + (y - p.y) ^ 2 < reach then return out end
        end
        t = t + h
        if t >= gap then
            t = t - gap
            out[#out + 1] = { x = x, y = y }
        end
    end
    return out
end

------------------------------------------------------------------------
-- Bests, and the guild's (not shared yet)
------------------------------------------------------------------------
local function G()
    ns.db.games = ns.db.games or { best = {} }
    ns.db.games.lode = ns.db.games.lode or { depth = 0, ore = 0, runs = 0 }
    return ns.db.games.lode
end
Lode.Saved = G

-- A run is over: counted, and kept if it's our deepest (most ore breaks a tie).
function Lode:Finish(run)
    local g = G()
    g.runs = g.runs + 1
    if run.cleared > g.depth or (run.cleared == g.depth and run.total > g.ore) then
        g.depth, g.ore = run.cleared, run.total
        self:Publish()
        return true
    end
    return false
end

-- The guild's hiscores: one record a player, their deepest run (Jake: "add a
-- hiscore"). A new kind of record costs something while the guild is on
-- mixed versions: an addon older than 0.16.9 can't file it and asks for it
-- again at every check-in (a few small messages every ten minutes while old
-- and new are online together), until it updates. Jake's call to have the
-- board now; Lode.share = false turns the writing off again.
ns.Sync:Register({
    name = "lode", code = "m", order = 4,
    fields = { "depth", "ore" },
    numeric = { depth = true, ore = true },
    valid = function(rec)
        return rec.by == rec.author and rec.id == rec.author and rec.depth ~= nil and rec.depth >= 0 and rec.depth <= 999
            and rec.depth == math.floor(rec.depth) and rec.ore ~= nil and rec.ore >= 0 and rec.ore < 1e9
    end,
    onChange = function() Lode:Refresh() end,
})

function Lode:Publish()
    if not Lode.share or not ns.Sync:GuildName() then return false end
    local g, me = G(), ns.Sync:Me()
    local cur = (ns.Sync:Store("lode") or {})[me]
    if cur and not cur.deleted and (cur.depth > g.depth or (cur.depth == g.depth and cur.ore >= g.ore)) then return false end
    ns.Sync:Write("lode", { id = me, author = me, t = ns.Now(), depth = g.depth, ore = math.floor(g.ore) })
    return true
end

-- Deepest first, then most ore.
function Lode:Leaderboard()
    local out = {}
    for _, rec in pairs(ns.Sync:Store("lode") or {}) do
        if not rec.deleted then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b)
        if a.depth ~= b.depth then return a.depth > b.depth end
        if a.ore ~= b.ore then return a.ore > b.ore end
        return a.author < b.author
    end)
    return out
end

------------------------------------------------------------------------
-- UI: the board on the left, the run beside it
------------------------------------------------------------------------
local PAD, GAP = 12, 8
local SIDE_X = PAD + Lode.W + GAP
local SIDE_W = 902 - PAD - SIDE_X
local HEAD_H = 32
local LINE_H = 20
local PEG_D = 2 * Lode.PEG_R
local BALL_D = 2 * Lode.BALL_R
local DOTS, DOT_GAP = 14, 0.045
local TILE_W, TILE_H, TILE_GAP = 164, 138, 10
local TRAIL = 7                 -- sparks behind a bomb
local FLOATS, RINGS = 30, 6     -- "+10"s in the air at once, keg blasts
local PIPS = 10                 -- bombs shown as pips on the run card
local POP, FADE = 0.2, 0.28     -- seconds: a peg's ring jumps when hit; a mined peg fades away
local APPEAR, STAGGER = 0.25, 0.4 -- a new floor's pegs fade in, the top rows first
local LIT_GLOW, IDLE_GLOW = 0.5, 0.22 -- a hit peg's halo; the slow pulse of gold, kegs and crystals
local FOOT_H = 70               -- the run card's foot: our best, Hiscores and New run
local SCORE_ROWS, SCORE_W, SCORE_TOP = 8, 340, 322 -- the guild's hiscores on the board's overlay
local LEGEND_H = 100            -- "Pegs" and its four rows above it
-- Aiming far to one side takes the mouse off the board, and off the window
-- (Jake): while a bomb is waiting, a click this far outside still drops it.
local CATCH = { side = 320, bottom = 170 }
local GOLD = { 1.00, 0.82, 0.20 }
local HOT = { 1.00, 0.60, 0.15 }  -- the bomb's glow and sparks
-- pegs hit by one bomb: a word of praise as the count climbs
Lode.PRAISE = { [6] = "Nice!", [10] = "Great!", [14] = "Rich vein!", [18] = "MOTHERLODE!" }
Lode.ART = { "Talent trees", "Shaman: Enhancement" } -- the board's backdrop: earth and stone
Lode.ART_ALPHA = 0.45           -- fainter than a page's so the pegs read
Lode.layout = { SIDE_X = SIDE_X, SIDE_W = SIDE_W, HEAD_H = HEAD_H, TILE_W = TILE_W, TILE_H = TILE_H, TILE_GAP = TILE_GAP,
    CATCH = CATCH, TRAIL = TRAIL, POP = POP, FADE = FADE, APPEAR = APPEAR, STAGGER = STAGGER, LIT_GLOW = LIT_GLOW,
    IDLE_GLOW = IDLE_GLOW, FOOT_H = FOOT_H, LEGEND_H = LEGEND_H, SCORE_ROWS = SCORE_ROWS, SCORE_W = SCORE_W, SCORE_TOP = SCORE_TOP }

local function commas(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
Lode.Commas = commas

local function itemIcon(item, fallback)
    if item and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, item)
        if ok and icon then return icon end
    end
    return fallback or 134400
end

function Lode.PegIcon(kind, floor)
    if kind == "ore" then
        local ore = Lode.Ore(floor)
        return itemIcon(ore[1], ore[3])
    end
    local k = Lode.KINDS[kind]
    return itemIcon(k[1], k[3])
end

-- an upgrade's picture, from an item everyone knows
Lode.UPGRADE_ITEMS = { spare = 4390, fever = 2776, rich = 3858, loaded = 4500, prospector = 2901, big = 10646, twin = 4394,
    rubber = 18662, lucky = 19972, deep = 4496 }
function Lode.UpgradeIcon(key) return itemIcon(Lode.UPGRADE_ITEMS[key]) end

local function disc(parent, layer, sub, d, r, g, b, a)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(ns.MEDIA .. "disc")
    t:SetSize(d, d)
    t:SetVertexColor(r, g, b, a)
    return t
end

local function additive(t)
    if t.SetBlendMode then t:SetBlendMode("ADD") end
    return t
end

-- A round picture `d` across: the icon behind a disc-shaped mask. Where the
-- client can't mask, `icon.masked` is nil and the caller tints a plain disc.
local function roundIcon(parent, d, layer, sub)
    local icon = parent:CreateTexture(nil, layer, nil, sub)
    local mask = parent.CreateMaskTexture and icon.AddMaskTexture and parent:CreateMaskTexture()
    if mask then
        icon:SetSize(d + 4, d + 4)
        mask:SetTexture(ns.MEDIA .. "disc", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(d, d)
        mask:SetPoint("CENTER", icon, "CENTER")
        icon:AddMaskTexture(mask)
        icon.masked = true
    else
        icon:SetSize(d, d)
    end
    return icon
end

-- A peg: a soft shadow under it, its round picture, a ring in its colour,
-- a glow behind and a flash over it for when it's been hit.
local function pegArt(parent)
    local p = {}
    p.glow = additive(parent:CreateTexture(nil, "ARTWORK", nil, 1))
    p.glow:SetTexture(ns.MEDIA .. "glow")
    p.glow:SetSize(PEG_D + 22, PEG_D + 22)
    p.glow:Hide()
    p.shadow = disc(parent, "ARTWORK", 2, PEG_D + 3, 0, 0, 0, 0.45)
    p.icon = roundIcon(parent, PEG_D, "ARTWORK", 3)
    p.flash = additive(disc(parent, "ARTWORK", 4, PEG_D, 1, 0.9, 0.7, 0.14))
    p.flash:Hide()
    p.ring = parent:CreateTexture(nil, "ARTWORK", nil, 5)
    p.ring:SetTexture(ns.MEDIA .. "ring")
    p.ring:SetSize(PEG_D + 6, PEG_D + 6)
    return p
end

local function place(tex, parent, x, y)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
end

-- (Siegebreaker draws with the same pieces)
Lode.util = { commas = commas, itemIcon = itemIcon, disc = disc, additive = additive, roundIcon = roundIcon, place = place }

function Lode:Build(view, top, height)
    self.view = view
    local board = CreateFrame("Button", nil, view)
    board:SetPoint("TOPLEFT", PAD, -top)
    board:SetSize(Lode.W, Lode.H)
    UI.Card(board, { 0.035, 0.035, 0.04, 1 })
    board:RegisterForClicks("LeftButtonUp")
    board:SetScript("OnClick", function() self:Click() end)
    board:SetScript("OnUpdate", function(_, elapsed) self:Update(elapsed) end)
    self.board = board

    -- the mine behind it: a picture from the game (faint, and not one of the
    -- gallery's pages: its "Use on" row is full), darker the deeper it goes
    if ns.Art then
        local ctl = ns.Art.CardArt(board)
        board.artAlpha = Lode.ART_ALPHA
        ctl:SetSparse(true)
        ctl:Show(ns.Art.Find(Lode.ART[1], Lode.ART[2]))
        self.boardArt = ctl
    end
    local depth = board:CreateTexture(nil, "BACKGROUND", nil, 3)
    depth:SetPoint("TOPLEFT", 1, -1)
    depth:SetPoint("BOTTOMRIGHT", -1, 1)
    depth:SetColorTexture(1, 1, 1, 1)
    local shaded = CreateColor and depth.SetGradient
        and pcall(depth.SetGradient, depth, "VERTICAL", CreateColor(0, 0, 0, 0.62), CreateColor(0, 0, 0, 0.05))
    if not shaded then depth:SetColorTexture(0, 0, 0, 0.3) end
    self.depth = depth
    -- the walls fall into shadow
    self.walls = {}
    for i, side in ipairs({ "LEFT", "RIGHT" }) do
        local w = board:CreateTexture(nil, "BACKGROUND", nil, 4)
        w:SetPoint("TOP" .. side, side == "LEFT" and 1 or -1, -1)
        w:SetPoint("BOTTOM" .. side, side == "LEFT" and 1 or -1, 1)
        w:SetWidth(44)
        w:SetColorTexture(1, 1, 1, 1)
        local dark, clear = CreateColor and CreateColor(0, 0, 0, 0.5), CreateColor and CreateColor(0, 0, 0, 0)
        local ok = dark and w.SetGradient and pcall(w.SetGradient, w, "HORIZONTAL", side == "LEFT" and dark or clear, side == "LEFT" and clear or dark)
        if not ok then w:Hide() end
        self.walls[i] = w
    end
    -- how far to the quota, along the top of the board where the eyes are
    local quota = CreateFrame("Frame", nil, board)
    quota:SetPoint("TOPLEFT", 1, -1)
    quota:SetPoint("TOPRIGHT", -1, -1)
    quota:SetHeight(3)
    quota.bg = quota:CreateTexture(nil, "BACKGROUND")
    quota.bg:SetAllPoints()
    quota.bg:SetColorTexture(0, 0, 0, 0.5)
    quota.fill = quota:CreateTexture(nil, "ARTWORK")
    quota.fill:SetPoint("TOPLEFT")
    quota.fill:SetPoint("BOTTOMLEFT")
    quota.fill:SetWidth(1)
    quota.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    self.topBar = quota

    -- clicks that miss the board while aiming (see CATCH): under the board and the run card
    local catcher = CreateFrame("Button", nil, view)
    catcher:SetPoint("TOPLEFT", board, "TOPLEFT", -CATCH.side, 0)
    catcher:SetSize(CATCH.side + Lode.W + GAP + SIDE_W + CATCH.side, Lode.H + CATCH.bottom)
    catcher:SetFrameLevel(view:GetFrameLevel())
    catcher:RegisterForClicks("LeftButtonUp")
    catcher:SetScript("OnClick", function() self:Click() end)
    catcher:Hide()
    self.catcher = catcher

    -- the pockets along the bottom: the richer the pocket, the warmer it glows
    self.pockets = {}
    local pw = Lode.W / #Lode.POCKETS
    local best = 0
    for _, m in ipairs(Lode.POCKETS) do best = math.max(best, m) end
    for i = 1, #Lode.POCKETS do
        local p = CreateFrame("Frame", nil, board)
        p:SetSize(pw, Lode.POCKET_H)
        p:SetPoint("BOTTOMLEFT", (i - 1) * pw, 0)
        local share = Lode.POCKETS[i] / best
        p.fill = p:CreateTexture(nil, "BORDER")
        p.fill:SetPoint("TOPLEFT", 1, 0)
        p.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        p.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.05 + 0.2 * share)
        p.shine = p:CreateTexture(nil, "BORDER", nil, 1)
        p.shine:SetAllPoints(p.fill)
        p.shine:SetColorTexture(1, 1, 1, 1)
        local lit = CreateColor and p.shine.SetGradient and pcall(p.shine.SetGradient, p.shine, "VERTICAL",
            CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.10 + 0.25 * share), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0))
        if not lit then p.shine:Hide() end
        p.flash = p:CreateTexture(nil, "ARTWORK")
        p.flash:SetAllPoints(p.fill)
        p.flash:SetColorTexture(1, 0.95, 0.7, 0.55)
        p.flash:Hide()
        p.text = UI.Text(p, Lode.POCKETS[i] == best and 16 or 13)
        p.text:SetPoint("CENTER")
        p.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.55 + 0.45 * share)
        if i > 1 then
            local wall = p:CreateTexture(nil, "ARTWORK")
            wall:SetPoint("BOTTOMLEFT", 0, 0)
            wall:SetSize(1, Lode.POCKET_H + 6)
            wall:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
        end
        self.pockets[i] = p
    end
    local lip = board:CreateTexture(nil, "ARTWORK")
    lip:SetPoint("BOTTOMLEFT", 1, Lode.POCKET_H)
    lip:SetPoint("BOTTOMRIGHT", -1, Lode.POCKET_H)
    lip:SetHeight(1)
    lip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)

    -- the mortar the bombs drop from: a goblin one, ringed in gold
    self.mortarGlow = additive(board:CreateTexture(nil, "ARTWORK", nil, 1))
    self.mortarGlow:SetTexture(ns.MEDIA .. "glow")
    self.mortarGlow:SetSize(64, 64)
    self.mortarGlow:SetVertexColor(HOT[1], HOT[2], HOT[3], 0.5)
    place(self.mortarGlow, board, Lode.W / 2, Lode.LAUNCH_Y)
    -- (the Goblin Mortar's own icon read as a black crescent at this size: a plain dark bowl
    -- with a barrel that turns to the aim says "this is where it comes from" better)
    self.barrel = board:CreateTexture(nil, "ARTWORK", nil, 2)
    self.barrel:SetSize(9, 20)
    self.barrel:SetColorTexture(0.32, 0.26, 0.16, 1)
    self.mortar = disc(board, "ARTWORK", 3, 30, 0.09, 0.08, 0.07, 1)
    place(self.mortar, board, Lode.W / 2, Lode.LAUNCH_Y)
    self:AimBarrel(0)
    self.mortarRing = board:CreateTexture(nil, "ARTWORK", nil, 5)
    self.mortarRing:SetTexture(ns.MEDIA .. "ring")
    self.mortarRing:SetSize(36, 36)
    self.mortarRing:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    place(self.mortarRing, board, Lode.W / 2, Lode.LAUNCH_Y)

    self.dots = {}
    for i = 1, DOTS do
        local d = disc(board, "ARTWORK", 6, math.max(3, 6 - i * 0.2), 1, 0.92, 0.62, 0.75 * (1 - (i - 1) / DOTS) + 0.15)
        d:Hide()
        self.dots[i] = d
    end
    self.pegArt = {}
    -- the bombs: a white-hot core in a glow, sparks trailing behind. The last
    -- one is the bomb waiting in the mortar.
    self.ballArt = {}
    for i = 1, Lode.MAX_BALLS + 1 do
        local b = disc(board, "OVERLAY", 3, BALL_D, 1, 0.80, 0.32, 1)
        b.glow = additive(board:CreateTexture(nil, "OVERLAY", nil, 1))
        b.glow:SetTexture(ns.MEDIA .. "glow")
        b.glow:SetSize(BALL_D + 34, BALL_D + 34)
        b.glow:SetVertexColor(HOT[1], HOT[2], HOT[3], 0.95)
        b.hot = additive(disc(board, "OVERLAY", 4, BALL_D - 5, 1, 1, 0.85, 0.95))
        b.trail = {}
        for k = 1, TRAIL do
            local size = BALL_D * (1 - k / (TRAIL + 2))
            b.trail[k] = additive(disc(board, "OVERLAY", 2, size, HOT[1], HOT[2], HOT[3], 0.6 * (1 - k / (TRAIL + 1))))
            b.trail[k]:Hide()
        end
        b.path = {}
        b:Hide()
        b.glow:Hide()
        b.hot:Hide()
        self.ballArt[i] = b
    end

    -- over the pegs: ore numbers floating up, keg blasts, the peg count
    local fx = CreateFrame("Frame", nil, board)
    fx:SetAllPoints()
    fx:SetFrameLevel(board:GetFrameLevel() + 3)
    self.fx = fx
    self.floats, self.floatAt = {}, 1
    for i = 1, FLOATS do
        local f = UI.Text(fx, 13)
        f:SetFont(UI.FONT, 13, "OUTLINE")
        f:Hide()
        self.floats[i] = f
    end
    self.rings, self.ringAt = {}, 1
    for i = 1, RINGS do
        local r = additive(fx:CreateTexture(nil, "ARTWORK"))
        r:SetTexture(ns.MEDIA .. "ring")
        r:Hide()
        self.rings[i] = r
    end
    self.flash = additive(fx:CreateTexture(nil, "BACKGROUND"))
    self.flash:SetAllPoints()
    self.flash:SetColorTexture(1, 0.9, 0.7, 1)
    self.flash:Hide()
    self.combo = UI.Text(fx, 14)
    self.combo:SetFont(UI.FONT, 14, "OUTLINE")
    self.combo:SetPoint("TOPRIGHT", board, "TOPRIGHT", -12, -10)
    self.combo:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    self.combo:Hide()
    -- what the last bomb did, top left of the board
    self.message = UI.Text(fx, 12)
    self.message:SetPoint("TOPLEFT", board, "TOPLEFT", 12, -10)
    self.message:SetTextColor(0.85, 0.85, 0.9)

    self:BuildSide(view, top, height)
    self:BuildOverlays(board)
    if G().depth > 0 or G().ore > 0 then self:Publish() end
end

-- The run, beside the board. From the top: the floor (big) and the seam's
-- ore; ore against the quota; the bombs left; the upgrades taken; what each
-- kind of peg does; and at the foot our best and New run.
function Lode:BuildSide(view, top, height)
    local s = CreateFrame("Frame", nil, view)
    s:SetPoint("TOPLEFT", SIDE_X, -top)
    s:SetSize(SIDE_W, height)
    UI.Card(s)
    self.side = s
    s.title = UI.SectionTitle(s, "Motherlode")
    s.title:SetPoint("LEFT", s, "TOPLEFT", 10, -UI.HeadMid(HEAD_H))
    s.seam = UI.Text(s, 11)
    s.seam:SetPoint("RIGHT", s, "TOPRIGHT", -10, -UI.HeadMid(HEAD_H))
    s.seam:SetTextColor(0.6, 0.6, 0.65)
    local function rule(y, inset)
        local line = s:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", inset, -y)
        line:SetPoint("TOPRIGHT", -inset, -y)
        line:SetHeight(1)
        UI.Line(line, 0.06)
        return line
    end
    local function label(y, text)
        local l = UI.Text(s, 12)
        l:SetPoint("TOPLEFT", 12, -y)
        l:SetText(text)
        l:SetTextColor(0.6, 0.6, 0.65)
        return l
    end
    rule(HEAD_H, 1)

    -- the floor, big, with the ore this seam gives
    local y = HEAD_H + 12
    s.floorLabel = UI.Text(s, 10)
    s.floorLabel:SetPoint("TOPLEFT", 12, -y)
    s.floorLabel:SetText("FLOOR")
    s.floorLabel:SetTextColor(0.6, 0.6, 0.65)
    s.floor = UI.Text(s, 30)
    s.floor:SetPoint("TOPLEFT", 12, -(y + 13))
    s.floor:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    s.seamIcon = UI.RoundIcon(s, 40)
    s.seamIcon:SetPoint("CENTER", s, "TOPRIGHT", -(12 + 20), -(y + 24))

    -- ore against the quota
    y = y + 56
    label(y, "Ore")
    s.ore = UI.Text(s, 13)
    s.ore:SetPoint("TOPRIGHT", -12, -y)
    s.ore:SetJustifyH("RIGHT")
    s.bar = CreateFrame("Frame", nil, s)
    s.bar:SetPoint("TOPLEFT", 12, -(y + 20))
    s.bar:SetSize(SIDE_W - 24, 12)
    s.bar.bg = s.bar:CreateTexture(nil, "BACKGROUND")
    s.bar.bg:SetAllPoints()
    s.bar.bg:SetColorTexture(0, 0, 0, 0.45)
    s.bar.fill = s.bar:CreateTexture(nil, "ARTWORK")
    s.bar.fill:SetPoint("TOPLEFT")
    s.bar.fill:SetPoint("BOTTOMLEFT")
    s.bar.fill:SetWidth(1)
    s.bar.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
    s.togo = UI.Text(s, 10)
    s.togo:SetPoint("TOPLEFT", 12, -(y + 37))
    s.togo:SetTextColor(0.5, 0.5, 0.55)

    -- the bombs left: a pip each, counting down
    y = y + 58
    label(y, "Bombs")
    s.bombs = UI.Text(s, 13)
    s.bombs:SetPoint("TOPRIGHT", -12, -y)
    s.bombs:SetJustifyH("RIGHT")
    s.pips = {}
    for i = 1, PIPS do
        local pip = disc(s, "ARTWORK", 1, 10, 1, 0.80, 0.32, 1)
        pip:SetPoint("RIGHT", s, "TOPRIGHT", -(40 + (i - 1) * 14), -(y + 7))
        s.pips[i] = pip
    end

    -- the upgrades taken
    y = y + 26
    rule(y, 8)
    s.upTitle = label(y + 10, "Upgrades")
    s.ups = {}
    for i = 1, #Lode.UPGRADES do
        local row = CreateFrame("Frame", nil, s)
        row:SetHeight(LINE_H)
        row:SetPoint("TOPLEFT", 12, -(y + 30 + (i - 1) * LINE_H))
        row:SetPoint("TOPRIGHT", -12, -(y + 30 + (i - 1) * LINE_H))
        row:EnableMouse(true)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 22, 0)
        row.count = UI.Text(row, 11)
        row.count:SetPoint("RIGHT")
        row.count:SetTextColor(0.6, 0.6, 0.65)
        row:SetScript("OnEnter", function(r)
            if not r.key or not GameTooltip then return end
            GameTooltip:SetOwner(r, "ANCHOR_LEFT")
            GameTooltip:AddLine(Lode.UPGRADE[r.key][2], 1, 1, 1)
            GameTooltip:AddLine(Lode.UPGRADE[r.key][3], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        s.ups[i] = row
    end
    s.upsTop = y + 30
    s.noUps = UI.Text(s, 11)
    s.noUps:SetPoint("TOPLEFT", 12, -(y + 32))
    s.noUps:SetTextColor(0.5, 0.5, 0.55)
    s.noUps:SetText("Clear a floor to get one.")

    -- what each kind of peg does (and is worth, this floor), above the foot
    local ly = height - FOOT_H - LEGEND_H
    s.legendRule = rule(ly - 6, 8)
    s.legendTitle = label(ly + 2, "Pegs")
    s.legend = {}
    for i, kind in ipairs({ "ore", "gold", "keg", "crystal" }) do
        local row = CreateFrame("Frame", nil, s)
        row:SetHeight(LINE_H)
        row:SetPoint("TOPLEFT", 12, -(ly + 20 + (i - 1) * LINE_H))
        row:SetPoint("TOPRIGHT", -12, -(ly + 20 + (i - 1) * LINE_H))
        row.kind = kind
        row.icon = UI.RoundIcon(row, 16)
        row.icon:SetPoint("CENTER", row, "LEFT", 8, 0)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 22, 0)
        row.what = UI.Text(row, 11)
        row.what:SetPoint("RIGHT")
        row.what:SetTextColor(0.6, 0.6, 0.65)
        s.legend[i] = row
    end

    -- the foot: our best, and New run
    rule(height - FOOT_H, 8)
    s.newRun = UI.Button(s, "New run", 120, 24, function(b)
        local run = self.run
        if run and run.state ~= "over" and run.shots > 0 then
            UI.ConfirmClick(b, function() self:NewRun() end)
        else
            self:NewRun()
        end
    end)
    s.newRun:SetWidth(96)
    s.newRun:SetPoint("BOTTOM", 52, 12)
    -- a look at the guild's hiscores in the middle of a run (they're on the board before and after one)
    s.scoresBtn = UI.Button(s, "Hiscores", 96, 24, function()
        local run = self.run
        if not run or run.state ~= "aim" then return end
        self.showScores = not self.showScores or nil
        self:Refresh()
    end)
    s.scoresBtn:SetPoint("BOTTOM", -52, 12)
    UI.Unred(s.scoresBtn) -- (one action button: New run)
    s.best = UI.Text(s, 11)
    s.best:SetPoint("BOTTOM", s, "BOTTOM", 0, 46)
    s.best:SetTextColor(0.6, 0.6, 0.65)
end

-- Over the board: how to play (before a run), three upgrades to pick from
-- (a floor cleared), and how it went (the run over).
function Lode:BuildOverlays(board)
    local o = CreateFrame("Frame", nil, board)
    o:SetAllPoints()
    o:SetFrameLevel(board:GetFrameLevel() + 5)
    o:EnableMouse(true) -- (clicks here aren't shots)
    o.shade = o:CreateTexture(nil, "BACKGROUND")
    o.shade:SetAllPoints()
    o.shade:SetColorTexture(0, 0, 0, 0.66)
    o.title = UI.Text(o, 22)
    o.title:SetPoint("TOP", 0, -140)
    o.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    o.sub = UI.Text(o, 12)
    o.sub:SetPoint("TOP", o.title, "BOTTOM", 0, -10)
    o.sub:SetWidth(Lode.W - 120)
    o.sub:SetJustifyH("CENTER")
    o.sub:SetTextColor(0.85, 0.85, 0.9)
    o.start = UI.Button(o, "Start run", 130, 24, function()
        if self.showScores then
            self.showScores = nil
            self:Refresh()
        else
            self:NewRun()
        end
    end)
    o.start:SetPoint("TOP", o.sub, "BOTTOM", 0, -18)
    -- the guild's hiscores: deepest run first. Up before a run, after one, and when asked for.
    o.scoreTitle = UI.Text(o, 13)
    o.scoreTitle:SetPoint("TOP", 0, -(SCORE_TOP - 24))
    o.scoreTitle:SetText("Guild hiscores")
    o.scoreTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    o.scores = {}
    for i = 1, SCORE_ROWS do
        local row = CreateFrame("Frame", nil, o)
        row:SetSize(SCORE_W, LINE_H)
        row:SetPoint("TOP", 0, -(SCORE_TOP + (i - 1) * LINE_H))
        row.mine = row:CreateTexture(nil, "BACKGROUND")
        row.mine:SetAllPoints()
        row.mine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.14)
        row.rank = UI.Text(row, 11)
        row.rank:SetPoint("LEFT", 6, 0)
        row.rank:SetTextColor(0.6, 0.6, 0.65)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 34, 0)
        row.ore = UI.Text(row, 11)
        row.ore:SetPoint("RIGHT", -6, 0)
        row.ore:SetJustifyH("RIGHT")
        row.ore:SetTextColor(0.6, 0.6, 0.65)
        row.floor = UI.Text(row, 12)
        row.floor:SetPoint("RIGHT", -110, 0)
        row.floor:SetJustifyH("RIGHT")
        o.scores[i] = row
    end
    o.noScores = UI.Text(o, 11)
    o.noScores:SetPoint("TOP", 0, -(SCORE_TOP + 4))
    o.noScores:SetTextColor(0.5, 0.5, 0.55)
    o.noScores:SetText("No scores yet. Be the first.")
    o.tiles = {}
    local total = 3 * TILE_W + 2 * TILE_GAP
    for i = 1, 3 do
        local t = CreateFrame("Button", nil, o)
        t:SetSize(TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (Lode.W - total) / 2 + (i - 1) * (TILE_W + TILE_GAP), -224)
        UI.Card(t)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.09)
        t.icon = UI.RoundIcon(t, 34)
        t.icon:SetPoint("CENTER", t, "TOP", 0, -30)
        t.name = UI.Text(t, 13)
        t.name:SetPoint("TOP", 0, -56)
        t.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        t.desc = UI.Text(t, 11)
        t.desc:SetPoint("TOP", t.name, "BOTTOM", 0, -6)
        t.desc:SetWidth(TILE_W - 20)
        t.desc:SetJustifyH("CENTER")
        t.own = UI.Text(t, 10)
        t.own:SetPoint("BOTTOM", 0, 8)
        t.own:SetTextColor(0.5, 0.5, 0.55)
        t:SetScript("OnClick", function() self:Pick(i) end)
        o.tiles[i] = t
    end
    o:Hide()
    self.overlay = o
end

------------------------------------------------------------------------
-- Playing
------------------------------------------------------------------------
function Lode:NewRun(seed)
    self.run = Run.New(seed or (math.floor(GetTime() * 1000) % 2147483646 + math.random(1, 100000)))
    self.newBest, self.showScores = nil, nil
    self.message:SetText("")
    self:Refresh()
end

-- The angle from the mortar to the mouse, from straight down.
function Lode:AimAngle()
    local x, y = GetCursorPosition()
    local s = self.board:GetEffectiveScale()
    local left, top = self.board:GetLeft(), self.board:GetTop()
    if not left or not top then return 0 end
    local bx, by = x / s - left, top - y / s
    local dx, dy = bx - Lode.W / 2, math.max(1, by - Lode.LAUNCH_Y)
    return math.max(-Lode.MAX_AIM, math.min(Lode.MAX_AIM, math.atan2(dx, dy)))
end

function Lode:Click()
    local run = self.run
    if not run or run.state ~= "aim" or self.showScores then return end
    if run:Fire(self:AimAngle()) then
        for _, art in ipairs(self.ballArt) do wipe(art.path) end
        self.combo:Hide()
        self:Refresh()
    end
end

function Lode:Pick(i)
    local run = self.run
    if run and run:Choose(i) then
        ns.Sound("IG_CHARACTER_INFO_TAB")
        self.message:SetText("")
        self:Refresh()
    end
end

------------------------------------------------------------------------
-- Effects: numbers floating up, blasts, pops and fades. All of it is for
-- show; the rules never wait on any of it.
------------------------------------------------------------------------
-- `text` rising from (x, y) on the board and fading.
function Lode:Float(x, y, text, size, color, life, rise)
    local f = self.floats[self.floatAt]
    self.floatAt = self.floatAt % FLOATS + 1
    f:SetFont(UI.FONT, size or 13, "OUTLINE")
    f:SetText(text)
    f:SetTextColor(color[1], color[2], color[3])
    f.x, f.y, f.age, f.life, f.rise = x, y, 0, life or 0.8, rise or 26
    f:SetAlpha(1)
    place(f, self.board, x, y)
    f:Show()
    return f
end

-- A ring spreading from (x, y) out to `radius`.
function Lode:Burst(x, y, radius, color)
    local r = self.rings[self.ringAt]
    self.ringAt = self.ringAt % RINGS + 1
    r.x, r.y, r.to, r.age, r.life = x, y, 2 * radius, 0, 0.38
    r:SetVertexColor(color[1], color[2], color[3], 1)
    r:SetSize(PEG_D, PEG_D)
    place(r, self.board, x, y)
    r:Show()
    return r
end

-- What the rules say happened since the last frame (Run.events), shown.
function Lode:ShowEvents()
    local run = self.run
    local events = run and run.events
    if not events or not events[1] then return end
    run.events = {}
    local chime = false
    for _, e in ipairs(events) do
        if e.kind == "mine" then
            local color = e.peg == "gold" and GOLD or e.lucky and { 0.45, 1, 0.45 } or { 1, 1, 1 }
            self:Float(e.x, e.y - 14, "+" .. commas(e.v) .. (e.lucky and " x2" or ""), e.peg == "gold" and 15 or 13, color)
            local art = self.artOf and self.artOf[e.ref]
            if art then art.pop = 0 end
            chime = true
        elseif e.kind == "hit" then
            local art = self.artOf and self.artOf[e.ref]
            if art then art.pop = 0 end
        elseif e.kind == "blast" then
            self:Burst(e.x, e.y, e.r, HOT)
            self:Flash(0.16)
        elseif e.kind == "land" then
            local p = self.pockets[e.pocket]
            p.flash:Show()
            UI.Fade(p.flash, 1, 0, 0.9)
            if e.gain > 0 then
                self:Float((e.pocket - 0.5) * Lode.W / #Lode.POCKETS, Lode.H - Lode.POCKET_H - 14,
                    ("x%d  +%s"):format(e.mult, commas(e.gain)), 17, GOLD, 1.3, 44)
                ns.Sound("LOOT_WINDOW_COIN_SOUND")
                if e.mult >= run:PocketMult(math.ceil(#Lode.POCKETS / 2)) then self:Flash(0.12) end
            end
        end
    end
    -- the pegs this bomb has hit so far, and a word as they add up
    local n = run.pegsHit or 0
    if n >= 2 and run.state == "flying" then
        self.combo:SetText(n .. " pegs")
        self.combo:Show()
    end
    if n ~= self.praised then
        local word = Lode.PRAISE[n]
        if word then self:Float(Lode.W / 2, Lode.H / 2 - 40, word, 24, GOLD, 1.2, 50) end
        self.praised = n
    end
    -- (one soft chink a frame at most, however many pegs went)
    if chime and GetTime() - (self.chimeAt or -1) > 0.06 then
        self.chimeAt = GetTime()
        ns.Sound("IG_BACKPACK_COIN_SELECT")
    end
end

function Lode:StepEffects(dt)
    for _, f in ipairs(self.floats) do
        if f.age then
            f.age = f.age + dt
            local k = f.age / f.life
            if k >= 1 then
                f.age = nil
                f:Hide()
            else
                place(f, self.board, f.x, f.y - f.rise * (1 - (1 - k) ^ 2))
                f:SetAlpha(k < 0.6 and 1 or 1 - (k - 0.6) / 0.4)
            end
        end
    end
    for _, r in ipairs(self.rings) do
        if r.age then
            r.age = r.age + dt
            local k = r.age / r.life
            if k >= 1 then
                r.age = nil
                r:Hide()
            else
                local d = PEG_D + (r.to - PEG_D) * (1 - (1 - k) ^ 2)
                r:SetSize(d, d)
                r:SetAlpha(1 - k)
            end
        end
    end
    if self.flash.age then
        self.flash.age = self.flash.age + dt
        local k = self.flash.age / 0.25
        if k >= 1 then
            self.flash.age = nil
            self.flash:Hide()
        else
            self.flash:SetAlpha(self.flash.strength * (1 - k))
        end
    end
    self.clock = (self.clock or 0) + dt
    for _, art in ipairs(self.pegArt) do
        if art.appear then
            -- a new floor's pegs fade in, the top rows first
            art.appear = art.appear + dt
            if art.appear >= APPEAR then
                art.appear = nil
                self:FadePeg(art, 1)
            else
                self:FadePeg(art, math.max(0, art.appear / APPEAR))
            end
        elseif art.pulse and not art.fading then
            -- gold, kegs and crystals breathe
            art.glow:SetAlpha(IDLE_GLOW * (0.55 + 0.45 * math.sin(self.clock * 2.2 + art.pulse)))
        end
        if art.pop then
            art.pop = art.pop + dt
            local k = art.pop / POP
            local grow = k >= 1 and 0 or 12 * math.sin(math.pi * k)
            art.ring:SetSize(PEG_D + 6 + grow, PEG_D + 6 + grow)
            if k >= 1 then art.pop = nil end
        end
        if art.fading then
            art.fading = art.fading + dt
            local k = art.fading / FADE
            if k >= 1 then
                art.fading = nil
                self:ShowPeg(art, false)
            else
                self:FadePeg(art, 1 - k)
            end
        end
    end
end

-- Every frame the page is up: the bombs in the air, or the aiming dots.
function Lode:Update(elapsed)
    local run = self.run
    if run then
        if run.state == "flying" then
            run:Step(elapsed)
            self:ShowEvents()
            if run.state ~= "flying" then self:ShotOver() end
            for i, b in ipairs(run.balls) do
                local art = self.ballArt[i]
                if art and not b.done then
                    table.insert(art.path, 1, { b.x, b.y })
                    art.path[TRAIL + 2] = nil
                end
            end
            self:Draw()
        elseif run.state == "aim" then
            self:DrawAim()
        end
        if run.dirty then self:Refresh() end
    end
    self:StepEffects(elapsed or 0)
end

function Lode:ShotOver()
    local run = self.run
    local last = run.last
    if last then
        local parts = {}
        for _, l in ipairs(last.landed) do parts[#parts + 1] = ("%s ore x%d"):format(commas(l.ore), l.mult) end
        self.message:SetText(last.gain > 0 and ("%s: +%s"):format(table.concat(parts, ", "), commas(last.gain)) or "Nothing hit.")
    end
    self.combo:Hide()
    self.praised = nil
    if run.state == "choose" then
        ns.Sound("IG_QUEST_LIST_COMPLETE")
    elseif run.state == "over" then
        self.newBest = self:Finish(run)
        run.dirty = true -- (sharing a new best redraws the page before we know it was one)
    end
end

-- The barrel points where the bomb will go (`angle` from straight down).
function Lode:AimBarrel(angle)
    self.barrelAngle = angle
    place(self.barrel, self.board, Lode.W / 2 + 15 * math.sin(angle), Lode.LAUNCH_Y + 15 * math.cos(angle))
    if self.barrel.SetRotation then self.barrel:SetRotation(angle) end
end

-- The whole board lights up for a moment (a keg, the best pocket).
function Lode:Flash(strength)
    self.flash.age, self.flash.strength = 0, strength
    self.flash:SetAlpha(strength)
    self.flash:Show()
end

function Lode:DrawAim()
    local run = self.run
    local angle = self:AimAngle()
    self:AimBarrel(angle)
    local dots = run:Preview(angle, DOTS, DOT_GAP)
    for i, d in ipairs(self.dots) do
        local p = dots[i]
        if p then
            place(d, self.board, p.x, p.y)
            d:Show()
        else
            d:Hide()
        end
    end
end

local function showBall(art, show)
    art:SetShown(show)
    art.glow:SetShown(show)
    art.hot:SetShown(show)
    if not show then
        for _, t in ipairs(art.trail) do t:Hide() end
    end
end

-- The bombs, where they are now, each with its sparks behind it. (The last
-- of ballArt is the one waiting in the mortar.)
function Lode:Draw()
    local balls = self.run and self.run.balls or {}
    for i = 1, Lode.MAX_BALLS do
        local art, b = self.ballArt[i], balls[i]
        local show = b ~= nil and not b.done
        showBall(art, show)
        if show then
            place(art, self.board, b.x, b.y)
            place(art.glow, self.board, b.x, b.y)
            place(art.hot, self.board, b.x - 1, b.y - 1)
            -- sparks where it was the last few frames (art.path, kept by Update)
            for k, t in ipairs(art.trail) do
                local at = art.path[k + 1]
                t:SetShown(at ~= nil)
                if at then place(t, self.board, at[1], at[2]) end
            end
        else
            wipe(art.path)
        end
    end
end

-- A peg's art, all of it shown or not; and all of it at one alpha (a mined peg fading away).
function Lode:ShowPeg(art, show)
    art.icon:SetShown(show)
    art.ring:SetShown(show)
    art.shadow:SetShown(show)
    if not show then
        art.glow:Hide()
        art.flash:Hide()
    end
end

function Lode:FadePeg(art, alpha)
    for _, t in ipairs({ art.icon, art.ring, art.shadow, art.flash }) do t:SetAlpha(alpha) end
    -- (the glow has a strength of its own: a halo when hit, fainter on gold, kegs and crystals at rest)
    art.glow:SetAlpha(alpha * (art.lit and LIT_GLOW or IDLE_GLOW))
end

function Lode:RefreshPegs()
    local run = self.run
    local pegs = run and run.pegs or {}
    self.artOf = {}
    for i, p in ipairs(pegs) do
        local art = self.pegArt[i]
        if not art then
            art = pegArt(self.board)
            self.pegArt[i] = art
        end
        self.artOf[p] = art
        if p.gone then
            -- mined: it fades out (once), unless it was never on show
            if art.peg == p and art.icon:IsShown() and not art.fading then art.fading = 0 end
            if art.peg ~= p then
                art.fading = nil
                self:ShowPeg(art, false)
            end
        else
            local c = Lode.KINDS[p.kind][4]
            local lit = p.lit == true
            art.fading, art.lit = nil, lit
            if art.peg ~= p then
                -- a peg we haven't drawn before: it fades in, the top rows first
                art.appear = -STAGGER * p.y / Lode.H
                art.pop = nil
                art.ring:SetSize(PEG_D + 6, PEG_D + 6)
            end
            if not art.appear then self:FadePeg(art, 1) else self:FadePeg(art, math.max(0, art.appear / APPEAR)) end
            self:ShowPeg(art, true)
            place(art.icon, self.board, p.x, p.y)
            place(art.ring, self.board, p.x, p.y)
            place(art.glow, self.board, p.x, p.y)
            place(art.flash, self.board, p.x, p.y)
            place(art.shadow, self.board, p.x + 1.5, p.y + 2.5)
            if art.icon.masked then
                art.icon:SetTexture(Lode.PegIcon(p.kind, run.floor))
                art.icon:SetVertexColor(1, 1, 1, 1)
            else
                art.icon:SetTexture(ns.MEDIA .. "disc")
                art.icon:SetVertexColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
            end
            art.pulse = not lit and p.kind ~= "ore" and (p.x * 0.07 + p.y * 0.05) or nil
            art.ring:SetVertexColor(lit and 1 or c[1], lit and 0.95 or c[2], lit and 0.75 or c[3], 1)
            art.glow:SetVertexColor(c[1], c[2], c[3], 1)
            art.glow:SetShown(lit or art.pulse ~= nil)
            art.flash:SetShown(lit)
        end
        art.peg = p
    end
    for i = #pegs + 1, #self.pegArt do
        self.pegArt[i].fading, self.pegArt[i].peg = nil, nil
        self:ShowPeg(self.pegArt[i], false)
    end
end

function Lode:RefreshSide()
    local s, run = self.side, self.run
    local g = G()
    s.best:SetText(g.runs > 0 and ("Best: floor %d, %s ore"):format(g.depth, commas(g.ore)) or "No runs yet")
    local floor = run and run.floor or 1
    s.seam:SetText(run and (Lode.Ore(floor)[2] .. " seam") or "")
    s.floor:SetText(run and tostring(floor) or "")
    s.floorLabel:SetShown(run ~= nil)
    s.seamIcon:SetShown(run ~= nil)
    s.seamIcon:SetTexture(Lode.PegIcon("ore", floor))
    s.ore:SetText(run and ("%s / %s"):format(commas(run.ore), commas(run.quota)) or "")
    s.bombs:SetText(run and tostring(run.bombs) or "")
    for i, pip in ipairs(s.pips) do pip:SetShown(run ~= nil and i <= run.bombs) end
    local share = math.min(1, run and run.ore / run.quota or 0)
    s.bar.fill:SetWidth(math.max(1, (SIDE_W - 24) * share))
    if share >= 1 then
        s.bar.fill:SetColorTexture(0.45, 0.9, 0.45, 0.9)
    else
        s.bar.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
    end
    s.togo:SetText(not run and "" or share >= 1 and "Quota hit!" or (commas(run.quota - run.ore) .. " to go"))
    local n = 0
    for _, u in ipairs(Lode.UPGRADES) do
        local have = run and run:Has(u[1]) or 0
        if have > 0 then
            n = n + 1
            local row = s.ups[n]
            row.key = u[1]
            row.icon:SetTexture(Lode.UpgradeIcon(u[1]))
            row.name:SetText(u[2])
            row.count:SetText(u[4] > 1 and ("x" .. have) or "")
            row:Show()
        end
    end
    for i = n + 1, #s.ups do
        s.ups[i].key = nil
        s.ups[i]:Hide()
    end
    s.noUps:SetShown(n == 0)
    -- what the pegs do, and are worth right now (hidden if the upgrades ever run down into it)
    local room = s.upsTop + n * LINE_H <= s:GetHeight() - FOOT_H - LEGEND_H - 6
    s.legendRule:SetShown(room)
    s.legendTitle:SetShown(room)
    local ore = Lode.Ore(floor)[2]
    local what = {
        ore = run and ("+" .. commas(run:OreValue())) or "+10",
        gold = run and ("+" .. commas(run:GoldValue())) or "+50",
        keg = "blows up nearby pegs",
        crystal = "splits your bomb",
    }
    for _, row in ipairs(s.legend) do
        row:SetShown(room)
        row.icon:SetTexture(Lode.PegIcon(row.kind, floor))
        row.name:SetText(row.kind == "ore" and (ore .. " ore") or Lode.KINDS[row.kind][2])
        row.what:SetText(what[row.kind])
    end
    s.newRun:SetLabel(run and "New run" or "Start run")
    s.scoresBtn:SetEnabledState(run ~= nil and run.state == "aim")
    s.scoresBtn:SetSelected(self.showScores == true)
end

-- The guild's hiscores for the overlay: the top rows, and ours on the last
-- one if we're further down than that. { rank, rec } each.
function Lode:ScoreRows()
    local board, me = self:Leaderboard(), ns.Sync:Me()
    local rows, mine = {}, nil
    for i, rec in ipairs(board) do
        if i <= SCORE_ROWS then rows[i] = { rank = i, rec = rec } end
        if rec.author == me then mine = i end
    end
    if mine and mine > SCORE_ROWS then rows[SCORE_ROWS] = { rank = mine, rec = board[mine] } end
    return rows
end

function Lode:RefreshOverlay()
    local o, run = self.overlay, self.run
    local state = run and run.state or "idle"
    local choosing = state == "choose"
    if state ~= "aim" then self.showScores = nil end
    local peek = self.showScores == true
    local scores = state == "idle" or state == "over" or peek
    o:SetShown(scores or choosing)
    o.start:SetShown(scores)
    -- the guild's hiscores
    local rows = scores and self:ScoreRows() or {}
    local me = ns.Sync:Me()
    o.scoreTitle:SetShown(scores)
    o.noScores:SetShown(scores and rows[1] == nil)
    for i, row in ipairs(o.scores) do
        local it = rows[i]
        row:SetShown(it ~= nil)
        if it then
            local rec = it.rec
            local p = ns.db.guild.players[rec.author]
            local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            row.rank:SetText(it.rank .. ".")
            row.name:SetText(Ambiguate(rec.author, "short"))
            row.name:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
            row.floor:SetText("floor " .. rec.depth)
            row.ore:SetText(commas(rec.ore) .. " ore")
            row.mine:SetShown(rec.author == me)
        end
    end
    for i, t in ipairs(o.tiles) do
        local key = choosing and run.offers[i]
        t:SetShown(key ~= nil and key ~= false)
        if key then
            local u = Lode.UPGRADE[key]
            t.icon:SetTexture(Lode.UpgradeIcon(key))
            t.name:SetText(u[2])
            t.desc:SetText(u[3])
            t.own:SetText(u[4] > 1 and run:Has(key) > 0 and ("You have %d"):format(run:Has(key)) or "")
        end
    end
    if state == "idle" then
        o.title:SetText("Motherlode")
        o.sub:SetText("Aim with your mouse and click to drop a bomb. Every peg it hits gets mined, and the pocket it lands in "
            .. "multiplies your haul. Hit the ore quota before you run out of bombs to go deeper.")
        o.start:SetLabel("Start run")
    elseif choosing then
        o.title:SetText(("Floor %d cleared"):format(run.cleared))
        o.sub:SetText("Pick an upgrade.")
    elseif peek then
        o.title:SetText("Hiscores")
        o.sub:SetText("Deepest floor cleared, then most ore.")
        o.start:SetLabel("Back")
    elseif state == "over" then
        o.title:SetText(self.newBest and "New best!" or "Out of bombs")
        o.sub:SetText(("Cleared %d floor%s, %s ore mined. Floor %d needed %s."):format(run.cleared,
            run.cleared == 1 and "" or "s", commas(run.total), run.floor, commas(run.quota)))
        o.start:SetLabel("New run")
    end
end

function Lode:Refresh()
    if not self.view then return end
    local run = self.run
    if run then run.dirty = nil end
    for i, p in ipairs(self.pockets) do
        p.text:SetText("x" .. (run and run:PocketMult(i) or Lode.POCKETS[i]))
    end
    local aiming = run ~= nil and run.state == "aim"
    self.catcher:SetShown(aiming)
    self.mortar:SetShown(run ~= nil)
    self.mortarRing:SetShown(run ~= nil)
    self.barrel:SetShown(run ~= nil)
    self.mortarGlow:SetShown(aiming)
    local share = math.min(1, run and run.ore / run.quota or 0)
    self.topBar:SetShown(run ~= nil)
    self.topBar.fill:SetWidth(math.max(1, (Lode.W - 2) * share))
    if share >= 1 then
        self.topBar.fill:SetColorTexture(0.45, 0.9, 0.45, 0.95)
    else
        self.topBar.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    end
    if not aiming then
        for _, d in ipairs(self.dots) do d:Hide() end
    end
    self:RefreshPegs()
    self:Draw()
    -- the bomb waiting in the mortar
    local waiting = self.ballArt[#self.ballArt]
    showBall(waiting, aiming)
    if aiming then
        place(waiting, self.board, Lode.W / 2, Lode.LAUNCH_Y)
        place(waiting.glow, self.board, Lode.W / 2, Lode.LAUNCH_Y)
        place(waiting.hot, self.board, Lode.W / 2 - 1, Lode.LAUNCH_Y - 1)
    end
    self:RefreshSide()
    self:RefreshOverlay()
end
