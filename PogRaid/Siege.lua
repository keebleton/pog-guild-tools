-- Pog Guild Tools games: Siegebreaker, a brick-breaker roguelike (Jake, 0.17.0).
--
-- Knock down a fortress wall with a cannonball: slide your paddle with the
-- mouse to keep the ball in play, and click to fire it. Clear every brick of
-- a wall to move on, picking one of three upgrades on the way. Three lives;
-- lose them all and the run is over. Fifty walls in ten tiers of five: each
-- stage of a run draws one from its tier, so no two runs are the same.
--
-- The rules (Siege.Run) know nothing of the screen and take their dice from
-- a seeded generator (Lode.Rng), so a run can be replayed step for step in
-- the tests. Board space: Siege.W x Siege.H, x to the right, y DOWN.
local _, ns = ...
local UI = ns.UI
local Lode = ns.Lode

local Siege = {}
ns.Siege = Siege

Siege.W, Siege.H = 560, 566
Siege.COLS, Siege.ROWS = 13, 14          -- the wall's grid
Siege.BRICK_W, Siege.BRICK_H = 40, 18
Siege.GRID_X, Siege.GRID_Y = 20, 44      -- its top left corner on the board
Siege.BALL_R = 6
Siege.PADDLE_W, Siege.PADDLE_H, Siege.PADDLE_Y = 84, 10, 524 -- (PADDLE_Y is its top edge)
Siege.MAX_PADDLE = 260
Siege.SPEED = 320                        -- a ball's speed on stage 1, px/s
Siege.SPEED_UP, Siege.MAX_SPEED_UP = 0.04, 1.6 -- faster each stage, up to this many times
Siege.PACE_UP, Siege.MAX_PACE = 0.02, 1.5 -- and a little faster off every paddle hit, until a ball is lost
Siege.STEP = 1 / 240
Siege.LIVES = 3
Siege.MAX_BALLS = 8
Siege.MAX_ANGLE = math.rad(62)           -- off the paddle's ends, from straight up
Siege.MIN_RISE = 0.22                    -- a ball always keeps this share of its speed up or down (no endless sideways bouncing)
Siege.DROP = 0.08                        -- the chance a broken brick drops a pickup
Siege.PICKUP_SPEED = 130
Siege.WIDE_TIME, Siege.WIDE_MULT = 15, 1.4
Siege.IDLE = 12                          -- seconds without breaking anything before the paddle starts adding a twist
Siege.share = true                       -- our best run goes on the guild's hiscores

local W, H = Siege.W, Siege.H
local COLS, ROWS = Siege.COLS, Siege.ROWS
local BW, BH, GX, GY = Siege.BRICK_W, Siege.BRICK_H, Siege.GRID_X, Siege.GRID_Y

------------------------------------------------------------------------
-- Bricks. A wall is rows of 13 characters:
--   .          nothing
--   r o y g t b p m w n k   a brick of that colour, one hit (red, orange,
--              yellow, green, teal, blue, purple, pink, white, brown, grey)
--   R O Y ...  the same, two hits
--   %          stone, three hits
--   #          steel: never breaks, and doesn't have to
--   *          powder: blows up the bricks around it
--   $          gold: worth five bricks
------------------------------------------------------------------------
Siege.COLORS = {
    r = { 0.86, 0.24, 0.22 }, o = { 0.93, 0.52, 0.16 }, y = { 0.95, 0.80, 0.22 }, g = { 0.36, 0.74, 0.30 },
    t = { 0.20, 0.72, 0.70 }, b = { 0.26, 0.48, 0.90 }, p = { 0.58, 0.36, 0.86 }, m = { 0.92, 0.44, 0.70 },
    w = { 0.90, 0.90, 0.92 }, n = { 0.55, 0.38, 0.22 }, k = { 0.42, 0.44, 0.48 },
}
Siege.STEEL, Siege.STONE = { 0.56, 0.60, 0.66 }, { 0.50, 0.56, 0.66 }
Siege.POWDER, Siege.GOLD = { 0.95, 0.35, 0.15 }, { 1.00, 0.82, 0.20 }

-- What a character of a wall is, or nil for nothing (or a character we don't know).
function Siege.Brick(ch)
    if ch == "#" then return { kind = "steel", steel = true, hp = 1, max = 1, color = Siege.STEEL } end
    if ch == "*" then return { kind = "powder", boom = true, hp = 1, max = 1, color = Siege.POWDER } end
    if ch == "$" then return { kind = "gold", gold = true, hp = 1, max = 1, color = Siege.GOLD } end
    if ch == "%" then return { kind = "stone", hp = 3, max = 3, color = Siege.STONE } end
    local low = ch:lower()
    local color = Siege.COLORS[low]
    if not color then return nil end
    local hp = ch == low and 1 or 2
    return { kind = "brick", hp = hp, max = hp, color = color }
end

------------------------------------------------------------------------
-- The fifty walls: ten tiers of five, easiest first. Some are drawn by
-- hand (pic), the rest by a rule for each cell (gen).
------------------------------------------------------------------------
local LEVELS = {}
Siege.LEVELS = LEVELS
Siege.TIERS, Siege.PER_TIER = 10, 5

local function pic(name, ...)
    LEVELS[#LEVELS + 1] = { name = name, rows = { ... } }
end

local function gen(name, rows, cell)
    local out = {}
    for r = 1, rows do
        local t = {}
        for c = 1, COLS do t[c] = cell(c, r) or "." end
        out[r] = table.concat(t)
    end
    LEVELS[#LEVELS + 1] = { name = name, rows = out }
end

local RAINBOW = { "r", "o", "y", "g", "t", "b", "p", "m" }
local function rb(i) return RAINBOW[(i - 1) % #RAINBOW + 1] end
local abs, floor, max, min = math.abs, math.floor, math.max, math.min

-- Tier 1: say hello
gen("First Wall", 3, function(_, r) return rb(r) end)
gen("Garden Fence", 4, function(c) return c % 2 == 1 and rb(c) end)
gen("Pyramid", 6, function(c, r) return abs(c - 7) < r and rb(r) end)
gen("Checkerboard", 4, function(c, r) return (c + r) % 2 == 0 and "w" end)
pic("Heart",
    "..rrr...rrr..",
    ".rmmrr.rrrrr.",
    ".rrrrrrrrrrr.",
    ".rrrrrrrrrrr.",
    "..rrrrrrrrr..",
    "...rrrrrrr...",
    "....rrrrr....",
    ".....rrr.....",
    "......r......")

-- Tier 2: shapes
gen("Funnel", 6, function(c, r) return abs(c - 7) <= 6 - r and rb(r) end)
gen("Diamond", 7, function(c, r)
    local d = abs(c - 7) + abs(r - 4)
    return d == 0 and "$" or d <= 3 and rb(d)
end)
gen("Zigzag", 6, function(c, r) return (c + r) % 4 < 2 and rb(r) end)
pic("Smile",
    "....yyyyy....",
    "..yyyyyyyyy..",
    ".yyykyyykyyy.",
    ".yyykyyykyyy.",
    ".yyyyyyyyyyy.",
    ".yykyyyyykyy.",
    ".yyykkkkkyyy.",
    "..yyyyyyyyy..",
    "....yyyyy....")
pic("Old Oak",
    "......g......",
    ".....ggg.....",
    "....ggggg....",
    "...ggggggg...",
    "..ggggggggg..",
    ".ggggggggggg.",
    "......n......",
    "......n......",
    ".....nnn.....")

-- Tier 3: pictures
gen("Hourglass", 7, function(c, r) return abs(c - 7) <= abs(r - 4) * 2 and rb(r) end)
gen("Portcullis", 7, function(c, r) return r == 4 and "y" or c % 3 == 1 and "n" end)
pic("Longsword",
    "......w......",
    ".....www.....",
    ".....www.....",
    ".....www.....",
    ".....www.....",
    ".....www.....",
    ".....www.....",
    "...yyyyyyy...",
    "......n......",
    "......n......",
    ".....yyy.....")
pic("Shield",
    ".bbbbbbbbbbb.",
    ".bbbbbwbbbbb.",
    ".bbbbbwbbbbb.",
    ".bwwwwwwwwwb.",
    ".bbbbbwbbbbb.",
    ".bbbbbwbbbbb.",
    "..bbbbwbbbb..",
    "...bbbwbbb...",
    "....bbwbb....",
    "......b......")
pic("Gate Key",
    "..yyy........",
    ".y...y.......",
    ".y.$.yyyyyyy.",
    ".y...y...y.y.",
    "..yyy........")

-- Tier 4: thicker bricks
gen("Thick Wall", 5, function(_, r) return r <= 2 and "N" or rb(r) end)
gen("Crossroads", 9, function(c, r)
    return (c >= 6 and c <= 8 or r >= 4 and r <= 6) and (c == 7 and r == 5 and "$" or "r")
end)
pic("Crown",
    ".y...y.y...y.",
    ".yy.yy.yy.yy.",
    ".yyyyyyyyyyy.",
    ".yyryybyyryy.",
    ".yyyyyyyyyyy.",
    ".YYYYYYYYYYY.")
pic("Toadstool",
    "....rrrrr....",
    "..rrwrrrwrr..",
    ".rrrrrrrrrrr.",
    ".rwrrrwrrrwr.",
    ".rrrrrrrrrrr.",
    "....wwwww....",
    "....wwwww....",
    "....wwwww....",
    "...wwwwwww...")
gen("Waves", 7, function(c, r)
    local k = floor(3.5 + 2 * math.sin(c * 0.9) + 0.5)
    return r == k and "b" or r == k + 1 and "t"
end)

-- Tier 5: powder
gen("Powder Line", 5, function(c, r) return r == 3 and c % 3 == 1 and "*" or rb(r) end)
gen("X Marks the Spot", 9, function(c, r) return abs(c - 7) == abs(r - 5) and (c == 7 and "*" or "m") end)
pic("Skull",
    "...wwwwwww...",
    "..wwwwwwwww..",
    ".wwwwwwwwwww.",
    ".wwkkwwwkkww.",
    ".wwkkwwwkkww.",
    ".wwwwwkwwwww.",
    "..wwwwwwwww..",
    "...w.w.w.w...",
    "...w.w.w.w...")
pic("Castle",
    ".k.k.k.k.k.k.",
    ".kkkkkkkkkkk.",
    ".kkkkkkkkkkk.",
    ".kkwkkkkkwkk.",
    ".kkkkkkkkkkk.",
    ".kkkknnnkkkk.",
    ".kkkknnnkkkk.",
    ".kkkknnnkkkk.")
gen("Honeycomb", 8, function(c, r) return (c + r) % 2 == 0 and (floor((c - 1) / 2) % 2 == 0 and "y" or "o") end)

-- Tier 6: steel
gen("Bunker", 6, function(c, r) return r == 6 and (c % 2 == 0 and "#") or r < 6 and rb(r) end)
gen("Gatehouse", 8, function(c, r)
    return (c == 1 or c == 13) and "#" or r == 1 and "n" or (c >= 5 and c <= 9 and r >= 3) and "y"
end)
pic("Potion",
    ".....nnn.....",
    "......w......",
    "......w......",
    ".....bbb.....",
    "....brrrb....",
    "...brrrrrb...",
    "...brrrrrb...",
    "...brrrrrb...",
    "....bbbbb....")
pic("Big Fish",
    "....tttt....t",
    "..tttttttt.tt",
    ".ttwttttttttt",
    ".tttttttttttt",
    "..tttttttt.tt",
    "....tttt....t")
gen("Rings", 9, function(c, r)
    local d = max(abs(c - 7), abs(r - 5))
    return d % 2 == 0 and rb(d + 1)
end)

-- Tier 7
pic("Spiral",
    "ttttttttttttt",
    "............t",
    "ttttttttttt.t",
    "t.........t.t",
    "t.ttttttt.t.t",
    "t.t.$.....t.t",
    "t.ttttttttt.t",
    "t...........t",
    "ttttttttttttt")
gen("Minefield", 7, function(c, r) return (c + r * 2) % 5 == 0 and "*" or (c + r) % 2 == 0 and "g" end)
pic("Anchor",
    ".....kkk.....",
    ".....k.k.....",
    ".....kkk.....",
    "......k......",
    "...kkkkkkk...",
    "......k......",
    "......k......",
    ".k....k....k.",
    ".kk...k...kk.",
    "..kkkkkkkkk..")
pic("Star",
    "......y......",
    "......y......",
    ".....yyy.....",
    ".yyyyyyyyyyy.",
    "..yyyyyyyyy..",
    "...yyyyyyy...",
    "...yyy.yyy...",
    "..yyy...yyy..",
    "..y.......y..")
gen("Barricade", 7, function(c, r) return r % 2 == 1 and rb(r) or c % 6 == 1 and "#" end)

-- Tier 8: stone
pic("POG",
    ".PPP.OOO.GGG.",
    ".PPP.OOO.GGG.",
    ".P.P.O.O.G...",
    ".P.P.O.O.G...",
    ".PPP.O.O.G.GG",
    ".PPP.O.O.G.GG",
    ".P...O.O.G..G",
    ".P...O.O.G..G",
    ".P...OOO.GGGG",
    ".P...OOO.GGGG")
gen("Fortress", 7, function(c, r)
    if r == 1 then return c % 2 == 1 and "k" end
    if r == 2 then return "K" end
    return (c == 1 or c == 13) and "#" or (c == 7 and r >= 5) and "n" or "k"
end)
gen("Bullseye", 9, function(c, r)
    local d = floor(math.sqrt((c - 7) ^ 2 + ((r - 5) * 1.5) ^ 2) + 0.5)
    return d == 0 and "$" or d <= 5 and (d % 2 == 1 and "r" or "w")
end)
pic("Rocket",
    "......r......",
    ".....rrr.....",
    ".....www.....",
    ".....wbw.....",
    ".....www.....",
    ".....www.....",
    "....rwwwr....",
    "...rrwwwrr...",
    "...r.ooo.r...",
    "......o......")
gen("Stone Rows", 6, function(_, r) return r % 2 == 1 and "%" or rb(r) end)

-- Tier 9
gen("Vault", 7, function(c, r)
    if r == 7 then return (c <= 3 or c >= 11) and "#" end -- (the door: seven wide)
    if r == 1 or c == 1 or c == 13 then return "#" end
    return r >= 3 and r <= 4 and c >= 5 and c <= 9 and "$" or "Y"
end)
gen("Powder Web", 9, function(c, r)
    return (abs(c - 7) == abs(r - 5) or c == 7 or r == 5) and "*" or (c + r) % 2 == 0 and "p"
end)
pic("Butterfly",
    ".mm...k...mm.",
    ".mmm..k..mmm.",
    ".mmmm.k.mmmm.",
    "..mmmmkmmmm..",
    "..ppppkpppp..",
    ".pppp.k.pppp.",
    ".ppp..k..ppp.",
    ".pp...k...pp.")
pic("Maze",
    "ggggggggggggg",
    "g#.........#g",
    "g#.#######.#g",
    "g#.#$$$$$#.#g",
    "g#.#$$$$$#.#g",
    "g#.#.....#.#g",
    "g#.###.###.#g",
    "g#.........#g",
    "g#####.#####g")
gen("Cage", 8, function(c, r)
    return (c % 4 == 1 and r >= 2 and r <= 7) and "#" or r == 1 and "w" or (c % 4 ~= 1 and r >= 3 and r <= 6) and rb(r)
end)

-- Tier 10: the keep
gen("Bastion", 10, function(c, r)
    local d = max(abs(c - 7), abs(r - 5))
    return d == 0 and "$" or d == 1 and "*" or d <= 3 and "%" or d <= 5 and "K" or r % 2 == 1 and "o"
end)
gen("Powder Magazine", 9, function(c, r)
    if c < 2 or c > 12 or r > 8 then return false end
    if r == 1 or c == 2 or c == 12 then return "%" end
    return (c + r) % 2 == 0 and "*" or "K"
end)
pic("Wildfire",
    "......R......",
    ".....RR......",
    ".....RRR.....",
    "....RRoR.....",
    "...RRooRR....",
    "..RRooyoRR...",
    "..Rooyyoorr..",
    "..Roo$$$ooR..",
    "...Roo$ooR...",
    "....RRoRR....")
gen("The Wall", 12, function(c, r)
    if r <= 2 then return "%" end
    if r <= 5 then return "K" end
    if r == 6 then return c % 4 == 2 and "*" or "$" end
    if r <= 9 then return "B" end
    return rb(r)
end)
pic("The Throne",
    "#...........#",
    "#.YYYYYYYYY.#",
    "#.Y$$$$$$$Y.#",
    "#.Y$%%%%%$Y.#",
    "#.Y$%***%$Y.#",
    "#.Y$%%%%%$Y.#",
    "#.Y$$$$$$$Y.#",
    "#.YYYYYYYYY.#",
    "#...........#")

-- A wall's bricks: a list, and the same bricks by row and column. Each
-- brick knows its cell (c, r) and its top left corner on the board (x, y).
function Siege.Wall(index)
    local level = LEVELS[index]
    local bricks, grid, left = {}, {}, 0
    for r = 1, ROWS do grid[r] = {} end
    for r, row in ipairs(level.rows) do
        for c = 1, min(COLS, #row) do
            local k = Siege.Brick(row:sub(c, c))
            if k and r <= ROWS then
                k.c, k.r, k.x, k.y = c, r, GX + (c - 1) * BW, GY + (r - 1) * BH
                bricks[#bricks + 1] = k
                grid[r][c] = k
                if not k.steel then left = left + 1 end
            end
        end
    end
    return bricks, grid, left
end

-- key, name, what it does, how many times it can be taken
Siege.UPGRADES = {
    { "wide", "Longer Ram", "+15% paddle width.", 4 },
    { "life", "Field Medic", "+1 life, right now.", 9 },
    { "twin", "Second Shot", "Start every wall with an extra ball.", 2 },
    { "power", "Heavy Shot", "Balls hit for +1 damage.", 2 },
    { "slow", "Steady Hands", "Balls move 8% slower.", 3 },
    { "net", "Safety Net", "Saves a ball that gets past you, once a wall.", 2 },
    { "blast", "Bigger Booms", "Powder blows up a wider area.", 1 },
    { "gold", "War Chest", "+50% points.", 4 },
    { "lucky", "Scavenger", "Bricks drop pickups more often.", 3 },
}
Siege.UPGRADE = {}
for _, u in ipairs(Siege.UPGRADES) do Siege.UPGRADE[u[1]] = u end

-- what falls out of a broken brick now and then: kind, how likely next to the others
Siege.PICKUPS = { { "multi", 45 }, { "wide", 45 }, { "life", 10 } }

------------------------------------------------------------------------
-- Rules (no UI)
------------------------------------------------------------------------
local Run = {}
Run.__index = Run
Siege.Run = Run

function Run.New(seed)
    -- `events` is what has happened since someone last looked: the screen shows them and empties the list
    local run = setmetatable({ seed = seed, rand = Lode.Rng(seed), stage = 0, cleared = 0, score = 0, lives = Siege.LIVES,
        upgrades = {}, balls = {}, pickups = {}, events = {}, paddleX = W / 2, wide = 0, net = 0, idle = 0, side = 1,
        pace = 1, state = "serve" }, Run)
    run:NextStage()
    return run
end

function Run:Has(key) return self.upgrades[key] or 0 end

function Run:PaddleW()
    return min(Siege.MAX_PADDLE, Siege.PADDLE_W * (1 + 0.15 * self:Has("wide")) * (self.wide > 0 and Siege.WIDE_MULT or 1))
end

function Run:Note(e) self.events[#self.events + 1] = e end

-- Which wall a stage is: one of its tier's five; past the last tier, any from the harder half.
function Run:PickLevel(stage)
    local per = Siege.PER_TIER
    if stage <= Siege.TIERS then return (stage - 1) * per + floor(self.rand() * per) + 1 end
    local half = floor(#LEVELS / 2)
    return half + floor(self.rand() * (#LEVELS - half)) + 1
end

function Run:NextStage(level)
    self.stage = self.stage + 1
    self.level = level or self:PickLevel(self.stage)
    self.name = LEVELS[self.level].name
    self.bricks, self.grid, self.left = Siege.Wall(self.level)
    self.speed = Siege.SPEED * min(Siege.MAX_SPEED_UP, 1 + Siege.SPEED_UP * (self.stage - 1)) * 0.92 ^ self:Has("slow")
    self.net = self:Has("net")
    self.pickups, self.wide, self.offers, self.idle = {}, 0, nil, 0
    self:Serve()
    self.dirty = true
end

-- A ball (two or three with Second Shot) sits on the paddle until it's fired.
function Run:Serve()
    self.balls = { { stuck = 0 } }
    for i = 1, self:Has("twin") do
        self.balls[#self.balls + 1] = { stuck = (i % 2 == 1 and 1 or -1) * 18 * math.ceil(i / 2) }
    end
    self.state, self.pace = "serve", 1
    self:Follow()
end

-- Balls on the paddle go where it goes.
function Run:Follow()
    for _, b in ipairs(self.balls) do
        if b.stuck then b.x, b.y, b.vx, b.vy = self.paddleX + b.stuck, Siege.PADDLE_Y - Siege.BALL_R, 0, 0 end
    end
end

-- A ball leaves the paddle at an angle set by where on it the ball is.
function Run:Aim(b, rel)
    if abs(rel) < 0.12 then
        -- (dead centre would go straight up and down for ever: a little to one side, then the other)
        self.side = -self.side
        rel = 0.3 * self.side
    end
    local a = max(-1, min(1, rel)) * Siege.MAX_ANGLE
    local s = self.speed * self.pace
    b.vx, b.vy = s * math.sin(a), -s * math.cos(a)
end

-- Click: fire whatever is sitting on the paddle.
function Run:Launch()
    if self.state ~= "serve" and self.state ~= "play" then return false end
    local fired = false
    local half = self:PaddleW() / 2
    for _, b in ipairs(self.balls) do
        if b.stuck then
            self:Aim(b, b.stuck / half)
            b.stuck = nil
            fired = true
        end
    end
    if fired then
        self.state = "play"
        self.dirty = true
    end
    return fired
end

-- A ball never loses its up-and-down: it keeps at least MIN_RISE of its speed that way.
function Run:Steady(b)
    local s = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    local least = Siege.MIN_RISE * s
    if abs(b.vy) < least then
        b.vy = (b.vy > 0 and 1 or -1) * least
        b.vx = (b.vx >= 0 and 1 or -1) * math.sqrt(s * s - b.vy * b.vy)
    end
end

-- Turn a ball's path a little (off steel, and off the paddle when nothing has broken for a while).
function Run:Twist(b, most)
    local a = (self.rand() - 0.5) * 2 * most
    local cs, sn = math.cos(a), math.sin(a)
    b.vx, b.vy = b.vx * cs - b.vy * sn, b.vx * sn + b.vy * cs
    self:Steady(b)
end

function Run:Points(k)
    local base = k.gold and 50 or 10 * k.max
    return floor(base * (1 + 0.5 * self:Has("gold")) + 0.5)
end

-- A brick is gone: points, perhaps a pickup, and powder takes its neighbours with it.
function Run:Destroy(k)
    if k.gone or k.steel then return end
    k.gone, k.hp = true, 0
    self.grid[k.r][k.c] = nil
    self.left = self.left - 1
    self.idle = 0
    local points = self:Points(k)
    self.score = self.score + points
    self:Note({ kind = "break", brick = k, points = points })
    if self.rand() < Siege.DROP * (1 + 0.5 * self:Has("lucky")) then self:Drop(k) end
    if k.boom then
        local reach = 1 + self:Has("blast")
        self:Note({ kind = "boom", x = k.x + BW / 2, y = k.y + BH / 2, reach = reach })
        for r = max(1, k.r - reach), min(ROWS, k.r + reach) do
            for c = max(1, k.c - reach), min(COLS, k.c + reach) do
                local n = self.grid[r][c]
                if n then self:Destroy(n) end
            end
        end
    end
    self.dirty = true
end

function Run:Drop(k)
    local total = 0
    for _, p in ipairs(Siege.PICKUPS) do total = total + p[2] end
    local roll, kind = self.rand() * total, Siege.PICKUPS[1][1]
    for _, p in ipairs(Siege.PICKUPS) do
        roll = roll - p[2]
        if roll < 0 then
            kind = p[1]
            break
        end
    end
    self.pickups[#self.pickups + 1] = { kind = kind, x = k.x + BW / 2, y = k.y + BH / 2 }
end

function Run:Damage(k, b)
    if k.steel then
        self:Note({ kind = "clank", brick = k })
        self:Twist(b, 0.12)
        return
    end
    k.hp = k.hp - (1 + self:Has("power"))
    self.idle = 0
    if k.hp <= 0 then
        self:Destroy(k)
    else
        self:Note({ kind = "hit", brick = k })
        self.dirty = true
    end
end

-- The ball against the wall: the first brick it's touching turns it back and takes the hit.
function Run:HitBricks(b)
    local rad = Siege.BALL_R
    local c0, c1 = floor((b.x - rad - GX) / BW) + 1, floor((b.x + rad - GX) / BW) + 1
    local r0, r1 = floor((b.y - rad - GY) / BH) + 1, floor((b.y + rad - GY) / BH) + 1
    for r = max(1, r0), min(ROWS, r1) do
        for c = max(1, c0), min(COLS, c1) do
            local k = self.grid[r][c]
            if k then
                local left, top = k.x, k.y
                local nx, ny = max(left, min(b.x, left + BW)), max(top, min(b.y, top + BH))
                local dx, dy = b.x - nx, b.y - ny
                if dx * dx + dy * dy < rad * rad then
                    if dx == 0 and dy == 0 then
                        -- (its centre is inside the brick: out by the nearer side)
                        local px, py = min(b.x - left, left + BW - b.x), min(b.y - top, top + BH - b.y)
                        if px < py then
                            local toLeft = b.x - left < left + BW - b.x
                            b.vx = (toLeft and -1 or 1) * abs(b.vx)
                            b.x = toLeft and left - rad or left + BW + rad
                        else
                            local toTop = b.y - top < top + BH - b.y
                            b.vy = (toTop and -1 or 1) * abs(b.vy)
                            b.y = toTop and top - rad or top + BH + rad
                        end
                    elseif abs(dx) > abs(dy) then
                        b.vx = (dx > 0 and 1 or -1) * abs(b.vx)
                        b.x = nx + (dx > 0 and rad or -rad)
                    else
                        b.vy = (dy > 0 and 1 or -1) * abs(b.vy)
                        b.y = ny + (dy > 0 and rad or -rad)
                    end
                    self:Damage(k, b)
                    return true
                end
            end
        end
    end
    return false
end

-- A pickup is caught.
function Run:Catch(p)
    if p.kind == "multi" then
        local from
        for _, b in ipairs(self.balls) do
            if not b.stuck and not b.lost then
                from = b
                break
            end
        end
        if from then
            for _, turn in ipairs({ 0.4, -0.4 }) do
                if #self.balls < Siege.MAX_BALLS then
                    local cs, sn = math.cos(turn), math.sin(turn)
                    local nb = { x = from.x, y = from.y, vx = from.vx * cs - from.vy * sn, vy = from.vx * sn + from.vy * cs }
                    self:Steady(nb)
                    self.balls[#self.balls + 1] = nb
                end
            end
        end
    elseif p.kind == "wide" then
        self.wide = Siege.WIDE_TIME
    elseif p.kind == "life" then
        self.lives = self.lives + 1
    end
    self:Note({ kind = "catch", pickup = p.kind, x = p.x })
    self.dirty = true
end

function Run:Tick(h)
    local rad = Siege.BALL_R
    local half = self:PaddleW() / 2
    local top = Siege.PADDLE_Y
    self.idle = self.idle + h
    if self.wide > 0 then
        self.wide = max(0, self.wide - h)
        if self.wide == 0 then self.dirty = true end
    end
    -- pickups fall; the paddle catches them
    for i = #self.pickups, 1, -1 do
        local p = self.pickups[i]
        p.y = p.y + Siege.PICKUP_SPEED * h
        if p.y >= top - 8 and p.y <= top + Siege.PADDLE_H + 8 and abs(p.x - self.paddleX) <= half + 8 then
            table.remove(self.pickups, i)
            self:Catch(p)
        elseif p.y > H + 20 then
            table.remove(self.pickups, i)
        end
    end
    for i = 1, #self.balls do
        local b = self.balls[i]
        if b.stuck then
            b.x, b.y = self.paddleX + b.stuck, top - rad
        elseif not b.lost then
            b.x, b.y = b.x + b.vx * h, b.y + b.vy * h
            if b.x < rad then
                b.x, b.vx = rad, abs(b.vx)
            elseif b.x > W - rad then
                b.x, b.vx = W - rad, -abs(b.vx)
            end
            if b.y < rad then b.y, b.vy = rad, abs(b.vy) end
            self:HitBricks(b)
            -- the paddle: where the ball lands on it sets the angle it leaves at
            if b.vy > 0 and b.y + rad >= top and b.y - rad <= top + Siege.PADDLE_H and abs(b.x - self.paddleX) <= half + rad then
                local rel = max(-1, min(1, (b.x - self.paddleX) / half))
                b.y = top - rad
                self.pace = min(Siege.MAX_PACE, self.pace + Siege.PACE_UP)
                -- (0.19.0: Tar Paddle, which held the ball here until a click, is gone: Jake's call)
                if self.idle > Siege.IDLE then rel = max(-1, min(1, rel + (self.rand() - 0.5) * 0.8)) end
                self:Aim(b, rel)
                self:Note({ kind = "paddle" })
            elseif b.vy > 0 and self.net > 0 and b.y + rad >= H - 6 then
                -- the safety net, once
                b.y, b.vy = H - 6 - rad, -abs(b.vy)
                self.net = self.net - 1
                self:Note({ kind = "net" })
                self.dirty = true
            elseif b.y - rad > H then
                b.lost = true
            end
        end
    end
    for i = #self.balls, 1, -1 do
        if self.balls[i].lost then table.remove(self.balls, i) end
    end
    if self.left <= 0 then
        self:Cleared()
    elseif #self.balls == 0 then
        self:LoseLife()
    end
end

function Run:LoseLife()
    self.lives = self.lives - 1
    self.pickups, self.wide = {}, 0
    self:Note({ kind = "lost" })
    if self.lives <= 0 then
        self.balls = {}
        self.state = "over"
    else
        self:Serve()
    end
    self.dirty = true
end

-- The wall is down: a bonus, and three upgrades to pick from.
function Run:Cleared()
    self.cleared = self.stage
    self.score = self.score + floor(100 * self.stage * (1 + 0.5 * self:Has("gold")) + 0.5)
    self.balls, self.pickups = {}, {}
    self.offers = self:Offers()
    self:Note({ kind = "cleared" })
    if self.offers[1] then self.state = "choose" else self:NextStage() end
    self.dirty = true
end

function Run:Offers()
    local pool = {}
    for _, u in ipairs(Siege.UPGRADES) do
        if self:Has(u[1]) < u[4] then pool[#pool + 1] = u[1] end
    end
    local out = {}
    for _ = 1, min(3, #pool) do
        out[#out + 1] = table.remove(pool, floor(self.rand() * #pool) + 1)
    end
    return out
end

function Run:Choose(i)
    local key = self.state == "choose" and self.offers and self.offers[i]
    if not key then return false end
    self.upgrades[key] = self:Has(key) + 1
    if key == "life" then self.lives = self.lives + 1 end
    self:NextStage()
    return true
end

-- Advance by `dt` seconds of real time with the paddle under `mouseX` (board
-- space; nil leaves it where it is).
function Run:Step(dt, mouseX)
    if self.state ~= "serve" and self.state ~= "play" then return end
    if mouseX then
        local half = self:PaddleW() / 2
        self.paddleX = max(half, min(W - half, mouseX))
    end
    if self.state == "serve" then
        self:Follow()
        return
    end
    self.acc = (self.acc or 0) + min(dt or 0, 0.05)
    while self.acc >= Siege.STEP and self.state == "play" do
        self.acc = self.acc - Siege.STEP
        self:Tick(Siege.STEP)
    end
    if self.state ~= "play" then self.acc = 0 end
end

------------------------------------------------------------------------
-- Bests, and the guild's hiscores (like Motherlode's: one record a player)
------------------------------------------------------------------------
local function G()
    ns.db.games = ns.db.games or { best = {} }
    ns.db.games.siege = ns.db.games.siege or { stage = 0, score = 0, runs = 0 }
    return ns.db.games.siege
end
Siege.Saved = G

-- A run is over: counted, and kept if it got furthest (most points breaks a tie).
function Siege:Finish(run)
    local g = G()
    g.runs = g.runs + 1
    if run.cleared > g.stage or (run.cleared == g.stage and run.score > g.score) then
        g.stage, g.score = run.cleared, run.score
        self:Publish()
        return true
    end
    return false
end

ns.Sync:Register({
    name = "siege", code = "b", order = 4,
    fields = { "stage", "score" },
    numeric = { stage = true, score = true },
    valid = function(rec)
        return rec.by == rec.author and rec.id == rec.author and rec.stage ~= nil and rec.stage >= 0 and rec.stage <= 9999
            and rec.stage == floor(rec.stage) and rec.score ~= nil and rec.score >= 0 and rec.score < 1e9
    end,
    onChange = function() Siege:Refresh() end,
})

function Siege:Publish()
    if not Siege.share or not ns.Sync:GuildName() then return false end
    local g, me = G(), ns.Sync:Me()
    local cur = (ns.Sync:Store("siege") or {})[me]
    if cur and not cur.deleted and (cur.stage > g.stage or (cur.stage == g.stage and cur.score >= g.score)) then return false end
    ns.Sync:Write("siege", { id = me, author = me, t = ns.Now(), stage = g.stage, score = floor(g.score) })
    return true
end

-- Furthest first, then most points.
function Siege:Leaderboard()
    local out = {}
    for _, rec in pairs(ns.Sync:Store("siege") or {}) do
        if not rec.deleted then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b)
        if a.stage ~= b.stage then return a.stage > b.stage end
        if a.score ~= b.score then return a.score > b.score end
        return a.author < b.author
    end)
    return out
end

------------------------------------------------------------------------
-- UI: the wall on the left, the run beside it (laid out like Motherlode,
-- with its drawing pieces: Lode.util)
------------------------------------------------------------------------
local U = Lode.util
local commas, disc, additive, place = U.commas, U.disc, U.additive, U.place
local PAD, GAP = 12, 8
local SIDE_X = PAD + W + GAP
local SIDE_W = 902 - PAD - SIDE_X
local HEAD_H = 32
local LINE_H = 20
local BALL_D = 2 * Siege.BALL_R
local TILE_W, TILE_H, TILE_GAP = 164, 118, 10
local TRAIL = 6
local FLOATS = 16
local PIPS = 8
local FOOT_H, LEGEND_H = 70, 120
local SCORE_ROWS, SCORE_W, SCORE_TOP = 8, 340, 322
local BREAK = 0.16              -- seconds a broken brick takes to flash and go
-- While a ball sits on the paddle, a click this far off the board still fires it (the mouse is the paddle,
-- so it's often out there).
local CATCH = { side = 320, bottom = 170 }
local GOLD = Siege.GOLD
local HOT = { 1.00, 0.60, 0.15 }
Siege.ART = { "Talent trees", "Warrior: Protection" } -- the board's backdrop
Siege.ART_ALPHA = 0.4
-- a pickup: its colour and the mark on it
Siege.PICKUP_LOOK = {
    multi = { { 0.95, 0.55, 0.15 }, "x3", "More balls" },
    wide = { { 0.30, 0.60, 0.95 }, "<>", "Wide paddle" },
    life = { { 0.40, 0.80, 0.40 }, "+1", "Extra life" },
}
Siege.layout = { SIDE_X = SIDE_X, SIDE_W = SIDE_W, HEAD_H = HEAD_H, TILE_W = TILE_W, TILE_H = TILE_H, TILE_GAP = TILE_GAP,
    CATCH = CATCH, FOOT_H = FOOT_H, LEGEND_H = LEGEND_H, SCORE_ROWS = SCORE_ROWS, SCORE_W = SCORE_W, SCORE_TOP = SCORE_TOP,
    BREAK = BREAK, TRAIL = TRAIL }

-- an upgrade's picture, from an item everyone knows
Siege.UPGRADE_ITEMS = { wide = 2901, life = 118, twin = 4394, power = 4390, slow = 4496, net = 2776,
    blast = 10646, gold = 3858, lucky = 19972 }
function Siege.UpgradeIcon(key) return U.itemIcon(Siege.UPGRADE_ITEMS[key]) end

-- A brick: its face, a darker frame behind for the ones that take more than
-- one hit, a light top edge and a dark bottom one, and a glow for powder and gold.
local function brickArt(parent)
    local a = {}
    a.glow = additive(parent:CreateTexture(nil, "ARTWORK", nil, 1))
    a.glow:SetTexture(ns.MEDIA .. "glow")
    a.glow:SetSize(BW + 26, BH + 30)
    a.glow:Hide()
    a.frame = parent:CreateTexture(nil, "ARTWORK", nil, 2)
    a.frame:SetSize(BW - 2, BH - 2)
    a.face = parent:CreateTexture(nil, "ARTWORK", nil, 3)
    a.top = parent:CreateTexture(nil, "ARTWORK", nil, 4)
    a.top:SetSize(BW - 2, 1)
    a.top:SetColorTexture(1, 1, 1, 0.28)
    a.bottom = parent:CreateTexture(nil, "ARTWORK", nil, 4)
    a.bottom:SetSize(BW - 2, 1)
    a.bottom:SetColorTexture(0, 0, 0, 0.4)
    a.flash = additive(parent:CreateTexture(nil, "ARTWORK", nil, 5))
    a.flash:SetSize(BW - 2, BH - 2)
    a.flash:SetColorTexture(1, 1, 1, 1)
    a.flash:Hide()
    return a
end

local function showBrick(a, show)
    a.frame:SetShown(show)
    a.face:SetShown(show)
    a.top:SetShown(show)
    a.bottom:SetShown(show)
    if not show then
        a.glow:Hide()
        a.flash:Hide()
    end
end

function Siege:Build(view, top, height)
    self.view = view
    local board = CreateFrame("Button", nil, view)
    board:SetPoint("TOPLEFT", PAD, -top)
    board:SetSize(W, H)
    UI.Card(board, { 0.035, 0.035, 0.04, 1 })
    board:RegisterForClicks("LeftButtonUp")
    board:SetScript("OnClick", function() self:Click() end)
    board:SetScript("OnUpdate", function(_, elapsed) self:Update(elapsed) end)
    self.board = board

    if ns.Art then
        local ctl = ns.Art.CardArt(board)
        board.artAlpha = Siege.ART_ALPHA
        ctl:SetSparse(true)
        ctl:Show(ns.Art.Find(Siege.ART[1], Siege.ART[2]))
        self.boardArt = ctl
    end
    local depth = board:CreateTexture(nil, "BACKGROUND", nil, 3)
    depth:SetPoint("TOPLEFT", 1, -1)
    depth:SetPoint("BOTTOMRIGHT", -1, 1)
    depth:SetColorTexture(1, 1, 1, 1)
    local shaded = CreateColor and depth.SetGradient
        and pcall(depth.SetGradient, depth, "VERTICAL", CreateColor(0, 0, 0, 0.7), CreateColor(0, 0, 0, 0.2))
    if not shaded then depth:SetColorTexture(0, 0, 0, 0.45) end
    self.depth = depth

    -- clicks that miss the board while a ball waits on the paddle
    local catcher = CreateFrame("Button", nil, view)
    catcher:SetPoint("TOPLEFT", board, "TOPLEFT", -CATCH.side, 0)
    catcher:SetSize(CATCH.side + W + GAP + SIDE_W + CATCH.side, H + CATCH.bottom)
    catcher:SetFrameLevel(view:GetFrameLevel())
    catcher:RegisterForClicks("LeftButtonUp")
    catcher:SetScript("OnClick", function() self:Click() end)
    catcher:Hide()
    self.catcher = catcher

    self.brickArt = {}

    -- the safety net along the bottom, while there's one
    self.netLine = additive(board:CreateTexture(nil, "ARTWORK", nil, 2))
    self.netLine:SetPoint("BOTTOMLEFT", 2, 4)
    self.netLine:SetPoint("BOTTOMRIGHT", -2, 4)
    self.netLine:SetHeight(2)
    self.netLine:SetColorTexture(0.3, 0.9, 0.9, 0.8)
    self.netLine:Hide()

    -- the paddle: a bronze ram with round ends, in a soft glow
    local p = {}
    p.glow = additive(board:CreateTexture(nil, "ARTWORK", nil, 1))
    p.glow:SetTexture(ns.MEDIA .. "glow")
    p.glow:SetVertexColor(HOT[1], HOT[2], HOT[3], 0.35)
    p.bar = board:CreateTexture(nil, "ARTWORK", nil, 3)
    p.shine = board:CreateTexture(nil, "ARTWORK", nil, 4)
    p.shine:SetColorTexture(1, 1, 1, 0.3)
    p.left = disc(board, "ARTWORK", 3, Siege.PADDLE_H, 1, 1, 1, 1)
    p.right = disc(board, "ARTWORK", 3, Siege.PADDLE_H, 1, 1, 1, 1)
    self.paddle = p

    -- the balls: a white-hot core in a glow, sparks behind
    self.ballArt = {}
    for i = 1, Siege.MAX_BALLS do
        local b = disc(board, "OVERLAY", 3, BALL_D, 1, 0.80, 0.32, 1)
        b.glow = additive(board:CreateTexture(nil, "OVERLAY", nil, 1))
        b.glow:SetTexture(ns.MEDIA .. "glow")
        b.glow:SetSize(BALL_D + 30, BALL_D + 30)
        b.glow:SetVertexColor(HOT[1], HOT[2], HOT[3], 0.95)
        b.hot = additive(disc(board, "OVERLAY", 4, BALL_D - 4, 1, 1, 0.85, 0.95))
        b.trail = {}
        for k = 1, TRAIL do
            b.trail[k] = additive(disc(board, "OVERLAY", 2, BALL_D * (1 - k / (TRAIL + 2)), HOT[1], HOT[2], HOT[3], 0.55 * (1 - k / (TRAIL + 1))))
            b.trail[k]:Hide()
        end
        b.path = {}
        b:Hide()
        b.glow:Hide()
        b.hot:Hide()
        self.ballArt[i] = b
    end

    -- over the wall: pickups falling, numbers and words floating up, the flash
    local fx = CreateFrame("Frame", nil, board)
    fx:SetAllPoints()
    fx:SetFrameLevel(board:GetFrameLevel() + 3)
    self.fx = fx
    self.pickupArt = {}
    for i = 1, 12 do
        local a = disc(fx, "ARTWORK", 2, 22, 1, 1, 1, 1)
        a.ring = fx:CreateTexture(nil, "ARTWORK", nil, 3)
        a.ring:SetTexture(ns.MEDIA .. "ring")
        a.ring:SetSize(26, 26)
        a.mark = UI.Text(fx, 10)
        a.mark:SetFont(UI.FONT, 10, "OUTLINE")
        a:Hide()
        a.ring:Hide()
        a.mark:Hide()
        self.pickupArt[i] = a
    end
    self.floats, self.floatAt = {}, 1
    for i = 1, FLOATS do
        local f = UI.Text(fx, 13)
        f:SetFont(UI.FONT, 13, "OUTLINE")
        f:Hide()
        self.floats[i] = f
    end
    self.flash = additive(fx:CreateTexture(nil, "BACKGROUND"))
    self.flash:SetAllPoints()
    self.flash:SetColorTexture(1, 0.9, 0.7, 1)
    self.flash:Hide()
    -- the wall's name and what to do, over the paddle while a ball waits
    self.banner = UI.Text(fx, 16)
    self.banner:SetFont(UI.FONT, 16, "OUTLINE")
    self.banner:SetPoint("CENTER", board, "TOPLEFT", W / 2, -(Siege.PADDLE_Y - 110))
    self.banner:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    self.hint = UI.Text(fx, 11)
    self.hint:SetPoint("TOP", self.banner, "BOTTOM", 0, -6)
    self.hint:SetTextColor(0.8, 0.8, 0.85)

    self:BuildSide(view, top, height)
    self:BuildOverlays(board)
    if G().stage > 0 or G().score > 0 then self:Publish() end
end

-- The run, beside the wall: which wall (big) and its name, lives, points,
-- how much of the wall is left, the upgrades taken, what the bricks and
-- pickups are, and at the foot our best, Hiscores and New run.
function Siege:BuildSide(view, top, height)
    local s = CreateFrame("Frame", nil, view)
    s:SetPoint("TOPLEFT", SIDE_X, -top)
    s:SetSize(SIDE_W, height)
    UI.Card(s)
    self.side = s
    s.title = UI.SectionTitle(s, "Siegebreaker")
    s.title:SetPoint("LEFT", s, "TOPLEFT", 10, -UI.HeadMid(HEAD_H))
    s.wallName = UI.Text(s, 11)
    s.wallName:SetPoint("RIGHT", s, "TOPRIGHT", -10, -UI.HeadMid(HEAD_H))
    s.wallName:SetTextColor(0.6, 0.6, 0.65)
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
    local function value(y)
        local v = UI.Text(s, 13)
        v:SetPoint("TOPRIGHT", -12, -y)
        v:SetJustifyH("RIGHT")
        return v
    end
    rule(HEAD_H, 1)

    local y = HEAD_H + 12
    s.wallLabel = UI.Text(s, 10)
    s.wallLabel:SetPoint("TOPLEFT", 12, -y)
    s.wallLabel:SetText("WALL")
    s.wallLabel:SetTextColor(0.6, 0.6, 0.65)
    s.stage = UI.Text(s, 30)
    s.stage:SetPoint("TOPLEFT", 12, -(y + 13))
    s.stage:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    -- lives: a pip each, top right
    s.livesLabel = UI.Text(s, 10)
    s.livesLabel:SetPoint("TOPRIGHT", -12, -y)
    s.livesLabel:SetText("LIVES")
    s.livesLabel:SetTextColor(0.6, 0.6, 0.65)
    s.lives = UI.Text(s, 13)
    s.lives:SetPoint("TOPRIGHT", -12, -(y + 20))
    s.lives:SetJustifyH("RIGHT")
    s.pips = {}
    for i = 1, PIPS do
        local pip = disc(s, "ARTWORK", 1, 10, 0.90, 0.30, 0.30, 1)
        pip:SetPoint("RIGHT", s, "TOPRIGHT", -(40 + (i - 1) * 14), -(y + 27))
        s.pips[i] = pip
    end

    y = y + 56
    label(y, "Points")
    s.score = value(y)
    y = y + 24
    label(y, "Wall")
    s.left = value(y)
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

    y = y + 44
    rule(y, 8)
    s.upTitle = label(y + 10, "Upgrades")
    s.ups = {}
    for i = 1, #Siege.UPGRADES do
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
            GameTooltip:AddLine(Siege.UPGRADE[r.key][2], 1, 1, 1)
            GameTooltip:AddLine(Siege.UPGRADE[r.key][3], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        s.ups[i] = row
    end
    s.upsTop = y + 30
    s.noUps = UI.Text(s, 11)
    s.noUps:SetPoint("TOPLEFT", 12, -(y + 32))
    s.noUps:SetTextColor(0.5, 0.5, 0.55)
    s.noUps:SetText("Break a wall to get one.")

    -- what the bricks and pickups are
    local ly = height - FOOT_H - LEGEND_H
    s.legendRule = rule(ly - 6, 8)
    s.legendTitle = label(ly + 2, "Bricks and pickups")
    s.legend = {}
    local rows = {
        { "frame", "Framed", "2 or 3 hits" },
        { "steel", "Steel", "never breaks" },
        { "powder", "Powder", "blows up its neighbours" },
        { "gold", "Gold", "5x points" },
        { "pickups", "Catch", "x3 balls, <> wide, +1 life" },
    }
    for i, def in ipairs(rows) do
        local row = CreateFrame("Frame", nil, s)
        row:SetHeight(LINE_H)
        row:SetPoint("TOPLEFT", 12, -(ly + 20 + (i - 1) * LINE_H))
        row:SetPoint("TOPRIGHT", -12, -(ly + 20 + (i - 1) * LINE_H))
        row.kind = def[1]
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(16, 10)
        row.swatch:SetPoint("LEFT")
        local c = def[1] == "steel" and Siege.STEEL or def[1] == "powder" and Siege.POWDER or def[1] == "gold" and GOLD
            or def[1] == "frame" and Siege.STONE or Siege.PICKUP_LOOK.wide[1]
        row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 22, 0)
        row.name:SetText(def[2])
        row.what = UI.Text(row, 11)
        row.what:SetPoint("RIGHT")
        row.what:SetTextColor(0.6, 0.6, 0.65)
        row.what:SetText(def[3])
        s.legend[i] = row
    end

    rule(height - FOOT_H, 8)
    s.newRun = UI.Button(s, "New run", 96, 24, function(b)
        local run = self.run
        if run and run.state ~= "over" and (run.score > 0 or run.stage > 1) then
            UI.ConfirmClick(b, function() self:NewRun() end)
        else
            self:NewRun()
        end
    end)
    s.newRun:SetPoint("BOTTOM", 52, 12)
    s.scoresBtn = UI.Button(s, "Hiscores", 96, 24, function()
        local run = self.run
        if not run or run.state ~= "serve" then return end
        self.showScores = not self.showScores or nil
        self:Refresh()
    end)
    s.scoresBtn:SetPoint("BOTTOM", -52, 12)
    UI.Unred(s.scoresBtn)
    s.best = UI.Text(s, 11)
    s.best:SetPoint("BOTTOM", s, "BOTTOM", 0, 46)
    s.best:SetTextColor(0.6, 0.6, 0.65)
end

-- Over the wall: how to play (before a run), three upgrades to pick from
-- (a wall down), how it went (the run over), and the guild's hiscores.
function Siege:BuildOverlays(board)
    local o = CreateFrame("Frame", nil, board)
    o:SetAllPoints()
    o:SetFrameLevel(board:GetFrameLevel() + 5)
    o:EnableMouse(true)
    o.shade = o:CreateTexture(nil, "BACKGROUND")
    o.shade:SetAllPoints()
    o.shade:SetColorTexture(0, 0, 0, 0.7)
    o.title = UI.Text(o, 22)
    o.title:SetPoint("TOP", 0, -140)
    o.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    o.sub = UI.Text(o, 12)
    o.sub:SetPoint("TOP", o.title, "BOTTOM", 0, -10)
    o.sub:SetWidth(W - 120)
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
    o.tiles = {}
    local total = 3 * TILE_W + 2 * TILE_GAP
    for i = 1, 3 do
        local t = CreateFrame("Button", nil, o)
        t:SetSize(TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", (W - total) / 2 + (i - 1) * (TILE_W + TILE_GAP), -224)
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
        row.score = UI.Text(row, 11)
        row.score:SetPoint("RIGHT", -6, 0)
        row.score:SetJustifyH("RIGHT")
        row.score:SetTextColor(0.6, 0.6, 0.65)
        row.stage = UI.Text(row, 12)
        row.stage:SetPoint("RIGHT", -110, 0)
        row.stage:SetJustifyH("RIGHT")
        o.scores[i] = row
    end
    o.noScores = UI.Text(o, 11)
    o.noScores:SetPoint("TOP", 0, -(SCORE_TOP + 4))
    o.noScores:SetTextColor(0.5, 0.5, 0.55)
    o.noScores:SetText("No scores yet. Be the first.")
    o:Hide()
    self.overlay = o
end

------------------------------------------------------------------------
-- Playing
------------------------------------------------------------------------
function Siege:NewRun(seed)
    self.run = Run.New(seed or (math.floor(GetTime() * 1000) % 2147483646 + math.random(1, 100000)))
    self.newBest, self.showScores = nil, nil
    self:Refresh()
end

-- Where the mouse is across the board.
function Siege:MouseX()
    local x = GetCursorPosition()
    local s = self.board:GetEffectiveScale()
    local left = self.board:GetLeft()
    if not left then return W / 2 end
    return x / s - left
end

function Siege:Click()
    local run = self.run
    if not run or self.showScores then return end
    if run:Launch() then
        for _, art in ipairs(self.ballArt) do wipe(art.path) end
        self:Refresh()
    end
end

function Siege:Pick(i)
    local run = self.run
    if run and run:Choose(i) then
        ns.Sound("IG_CHARACTER_INFO_TAB")
        self:Refresh()
    end
end

-- `text` rising from (x, y) on the board and fading.
function Siege:Float(x, y, text, size, color, life, rise)
    local f = self.floats[self.floatAt]
    self.floatAt = self.floatAt % FLOATS + 1
    f:SetFont(UI.FONT, size or 13, "OUTLINE")
    f:SetText(text)
    f:SetTextColor(color[1], color[2], color[3])
    f.x, f.y, f.age, f.life, f.rise = x, y, 0, life or 0.8, rise or 24
    f:SetAlpha(1)
    place(f, self.board, x, y)
    f:Show()
    return f
end

function Siege:Flash(strength)
    self.flash.age, self.flash.strength = 0, strength
    self.flash:SetAlpha(strength)
    self.flash:Show()
end

-- What the rules say happened since the last frame (Run.events), shown.
function Siege:ShowEvents()
    local run = self.run
    local events = run and run.events
    if not events or not events[1] then return end
    run.events = {}
    local chink = false
    for _, e in ipairs(events) do
        if e.kind == "break" then
            local a = self.artOf and self.artOf[e.brick]
            if a then a.breaking = 0 end
            if e.brick.gold or e.brick.boom then
                self:Float(e.brick.x + BW / 2, e.brick.y, "+" .. commas(e.points), 14, e.brick.gold and GOLD or HOT)
            end
            chink = true
        elseif e.kind == "hit" or e.kind == "clank" then
            local a = self.artOf and self.artOf[e.brick]
            if a then a.knock = 0 end
        elseif e.kind == "boom" then
            self:Flash(0.16)
        elseif e.kind == "catch" then
            local look = Siege.PICKUP_LOOK[e.pickup]
            self:Float(run.paddleX, Siege.PADDLE_Y - 16, look[3] .. "!", 15, look[1], 1.1, 34)
            ns.Sound("LOOT_WINDOW_COIN_SOUND")
        elseif e.kind == "net" then
            self:Float(W / 2, H - 30, "Saved!", 15, { 0.3, 0.9, 0.9 }, 1.1, 30)
        elseif e.kind == "lost" then
            self:Flash(0.1)
        elseif e.kind == "cleared" then
            ns.Sound("IG_QUEST_LIST_COMPLETE")
        end
    end
    if chink and GetTime() - (self.chinkAt or -1) > 0.06 then
        self.chinkAt = GetTime()
        ns.Sound("IG_BACKPACK_COIN_SELECT")
    end
end

function Siege:StepEffects(dt)
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
    for _, a in ipairs(self.brickArt) do
        if a.breaking then
            -- a broken brick flashes white and is gone
            a.breaking = a.breaking + dt
            local k = a.breaking / BREAK
            if k >= 1 then
                a.breaking = nil
                showBrick(a, false)
            else
                a.flash:Show()
                a.flash:SetAlpha(1 - k)
                for _, t in ipairs({ a.frame, a.face, a.top, a.bottom }) do t:SetAlpha(1 - k) end
            end
        elseif a.knock then
            -- a brick that took a hit and held blinks
            a.knock = a.knock + dt
            local k = a.knock / 0.14
            a.flash:SetShown(k < 1)
            a.flash:SetAlpha(0.6 * (1 - k))
            if k >= 1 then a.knock = nil end
        elseif a.pulse then
            a.glow:SetAlpha(0.3 + 0.2 * math.sin(self.clock * 3 + a.pulse))
        end
    end
end

-- Every frame the page is up.
function Siege:Update(elapsed)
    local run = self.run
    if run then
        if (run.state == "serve" or run.state == "play") and not self.showScores then
            local was = run.state
            run:Step(elapsed, self:MouseX())
            self:ShowEvents()
            if run.state == "over" and was ~= "over" then
                self.newBest = self:Finish(run)
                run.dirty = true
            end
            for i, b in ipairs(run.balls) do
                local art = self.ballArt[i]
                if art and not b.stuck then
                    table.insert(art.path, 1, { b.x, b.y })
                    art.path[TRAIL + 2] = nil
                end
            end
            self:Draw()
        end
        if run.dirty then self:Refresh() end
    end
    self:StepEffects(elapsed or 0)
end

local function showBall(art, show)
    art:SetShown(show)
    art.glow:SetShown(show)
    art.hot:SetShown(show)
    if not show then
        for _, t in ipairs(art.trail) do t:Hide() end
    end
end

-- The paddle, the balls and the pickups, where they are now.
function Siege:Draw()
    local run = self.run
    local p = self.paddle
    local playing = run ~= nil and (run.state == "serve" or run.state == "play")
    for _, t in ipairs({ p.glow, p.bar, p.shine, p.left, p.right }) do t:SetShown(playing) end
    if playing then
        local w = run:PaddleW()
        local x, y = run.paddleX, Siege.PADDLE_Y + Siege.PADDLE_H / 2
        local wide = run.wide > 0
        local r, g, b = wide and 0.45 or 0.78, wide and 0.70 or 0.56, wide and 1 or 0.26
        p.bar:SetSize(w - Siege.PADDLE_H, Siege.PADDLE_H)
        p.bar:SetColorTexture(r, g, b, 1)
        p.shine:SetSize(w - Siege.PADDLE_H, 2)
        p.left:SetVertexColor(r, g, b, 1)
        p.right:SetVertexColor(r, g, b, 1)
        p.glow:SetSize(w + 50, 46)
        place(p.bar, self.board, x, y)
        place(p.shine, self.board, x, y - Siege.PADDLE_H / 2 + 2)
        place(p.left, self.board, x - (w - Siege.PADDLE_H) / 2, y)
        place(p.right, self.board, x + (w - Siege.PADDLE_H) / 2, y)
        place(p.glow, self.board, x, y)
    end
    local balls = playing and run.balls or {}
    for i = 1, Siege.MAX_BALLS do
        local art, b = self.ballArt[i], balls[i]
        local show = b ~= nil and b.x ~= nil
        showBall(art, show)
        if show then
            place(art, self.board, b.x, b.y)
            place(art.glow, self.board, b.x, b.y)
            place(art.hot, self.board, b.x - 1, b.y - 1)
            for k, t in ipairs(art.trail) do
                local at = not b.stuck and art.path[k + 1]
                t:SetShown(at ~= nil and at ~= false)
                if at then place(t, self.board, at[1], at[2]) end
            end
            if b.stuck then wipe(art.path) end
        else
            wipe(art.path)
        end
    end
    local pickups = playing and run.pickups or {}
    for i, a in ipairs(self.pickupArt) do
        local pk = pickups[i]
        a:SetShown(pk ~= nil)
        a.ring:SetShown(pk ~= nil)
        a.mark:SetShown(pk ~= nil)
        if pk then
            local look = Siege.PICKUP_LOOK[pk.kind]
            a:SetVertexColor(look[1][1] * 0.55, look[1][2] * 0.55, look[1][3] * 0.55, 1)
            a.ring:SetVertexColor(look[1][1], look[1][2], look[1][3], 1)
            a.mark:SetText(look[2])
            place(a, self.board, pk.x, pk.y)
            place(a.ring, self.board, pk.x, pk.y)
            place(a.mark, self.board, pk.x, pk.y)
        end
    end
end

-- A brick's look for the hits it has left: plain at one, a darker frame
-- round a smaller face for more; steel, powder and gold their own.
function Siege:PaintBrick(a, k)
    local c = k.color
    local cx, cy = k.x + BW / 2, k.y + BH / 2
    place(a.frame, self.board, cx, cy)
    place(a.face, self.board, cx, cy)
    place(a.top, self.board, cx, k.y + 1.5)
    place(a.bottom, self.board, cx, k.y + BH - 1.5)
    place(a.flash, self.board, cx, cy)
    place(a.glow, self.board, cx, cy)
    local inset = k.steel and 3 or (k.hp >= 3 and 4 or k.hp == 2 and 3 or 0)
    a.face:SetSize(BW - 2 - 2 * inset, BH - 2 - 2 * inset)
    if k.steel then
        a.frame:SetColorTexture(c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1)
        a.face:SetColorTexture(c[1], c[2], c[3], 1)
    else
        local dark = inset > 0 and (k.hp >= 3 and 0.38 or 0.55) or 1
        a.frame:SetColorTexture(c[1] * dark, c[2] * dark, c[3] * dark, 1)
        a.face:SetColorTexture(c[1], c[2], c[3], 1)
    end
    a.pulse = (k.boom or k.gold) and (k.c * 0.9 + k.r * 0.6) or nil
    a.glow:SetShown(a.pulse ~= nil)
    if a.pulse then a.glow:SetVertexColor(c[1], c[2], c[3], 1) end
end

function Siege:RefreshBricks()
    local run = self.run
    local bricks = run and run.state ~= "over" and run.bricks or {}
    self.artOf = {}
    for i, k in ipairs(bricks) do
        local a = self.brickArt[i]
        if not a then
            a = brickArt(self.board)
            self.brickArt[i] = a
        end
        self.artOf[k] = a
        if k.gone then
            -- (broken: it flashes out in StepEffects, unless it was never drawn)
            if a.brick ~= k then
                a.breaking = nil
                showBrick(a, false)
            end
        else
            if a.brick ~= k then a.breaking, a.knock = nil, nil end
            for _, t in ipairs({ a.frame, a.face, a.top, a.bottom }) do t:SetAlpha(1) end
            showBrick(a, true)
            self:PaintBrick(a, k)
        end
        a.brick = k
    end
    for i = #bricks + 1, #self.brickArt do
        local a = self.brickArt[i]
        a.brick, a.breaking, a.knock, a.pulse = nil, nil, nil, nil
        showBrick(a, false)
    end
end

function Siege:RefreshSide()
    local s, run = self.side, self.run
    local g = G()
    s.best:SetText(g.runs > 0 and ("Best: wall %d, %s pts"):format(g.stage, commas(g.score)) or "No runs yet")
    s.wallName:SetText(run and run.name or "")
    s.stage:SetText(run and tostring(run.stage) or "")
    s.wallLabel:SetShown(run ~= nil)
    s.livesLabel:SetShown(run ~= nil)
    s.lives:SetText(run and run.lives > PIPS and ("x" .. run.lives) or "")
    for i, pip in ipairs(s.pips) do pip:SetShown(run ~= nil and run.lives <= PIPS and i <= run.lives) end
    s.score:SetText(run and commas(run.score) or "")
    local total = 0
    for _, k in ipairs(run and run.bricks or {}) do
        if not k.steel then total = total + 1 end
    end
    local done = total > 0 and (total - run.left) / total or 0
    s.left:SetText(run and (run.left .. " left") or "")
    s.bar.fill:SetWidth(math.max(1, (SIDE_W - 24) * done))
    local n = 0
    for _, u in ipairs(Siege.UPGRADES) do
        local have = run and run:Has(u[1]) or 0
        if have > 0 then
            n = n + 1
            local row = s.ups[n]
            row.key = u[1]
            row.icon:SetTexture(Siege.UpgradeIcon(u[1]))
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
    local room = s.upsTop + n * LINE_H <= s:GetHeight() - FOOT_H - LEGEND_H - 6
    s.legendRule:SetShown(room)
    s.legendTitle:SetShown(room)
    for _, row in ipairs(s.legend) do row:SetShown(room) end
    s.newRun:SetLabel(run and "New run" or "Start run")
    s.scoresBtn:SetEnabledState(run ~= nil and run.state == "serve")
    s.scoresBtn:SetSelected(self.showScores == true)
end

-- The guild's hiscores for the overlay: the top rows, and ours on the last
-- one if we're further down. { rank, rec } each.
function Siege:ScoreRows()
    local board, me = self:Leaderboard(), ns.Sync:Me()
    local rows, mine = {}, nil
    for i, rec in ipairs(board) do
        if i <= SCORE_ROWS then rows[i] = { rank = i, rec = rec } end
        if rec.author == me then mine = i end
    end
    if mine and mine > SCORE_ROWS then rows[SCORE_ROWS] = { rank = mine, rec = board[mine] } end
    return rows
end

function Siege:RefreshOverlay()
    local o, run = self.overlay, self.run
    local state = run and run.state or "idle"
    local choosing = state == "choose"
    if state ~= "serve" then self.showScores = nil end
    local peek = self.showScores == true
    local scores = state == "idle" or state == "over" or peek
    o:SetShown(scores or choosing)
    o.start:SetShown(scores)
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
            row.stage:SetText("wall " .. rec.stage)
            row.score:SetText(commas(rec.score) .. " pts")
            row.mine:SetShown(rec.author == me)
        end
    end
    for i, t in ipairs(o.tiles) do
        local key = choosing and run.offers[i]
        t:SetShown(key ~= nil and key ~= false)
        if key then
            local u = Siege.UPGRADE[key]
            t.icon:SetTexture(Siege.UpgradeIcon(key))
            t.name:SetText(u[2])
            t.desc:SetText(u[3])
            t.own:SetText(u[4] > 1 and run:Has(key) > 0 and ("You have %d"):format(run:Has(key)) or "")
        end
    end
    if state == "idle" then
        o.title:SetText("Siegebreaker")
        o.sub:SetText("Knock the wall down. Move your mouse to slide the paddle and click to fire the ball. "
            .. "Keep it in play, break every brick, and pick an upgrade for the next wall. You get three lives.")
        o.start:SetLabel("Start run")
    elseif choosing then
        o.title:SetText(("Wall %d is down"):format(run.cleared))
        o.sub:SetText("Pick an upgrade.")
    elseif peek then
        o.title:SetText("Hiscores")
        o.sub:SetText("Most walls broken, then most points.")
        o.start:SetLabel("Back")
    elseif state == "over" then
        o.title:SetText(self.newBest and "New best!" or "Out of lives")
        o.sub:SetText(("Broke %d wall%s for %s points. %s held."):format(run.cleared, run.cleared == 1 and "" or "s",
            commas(run.score), run.name))
        o.start:SetLabel("New run")
    end
end

function Siege:Refresh()
    if not self.view then return end
    local run = self.run
    if run then run.dirty = nil end
    local serving = run ~= nil and run.state == "serve" and not self.showScores
    local waiting = serving
    for _, b in ipairs(run and run.state == "play" and run.balls or {}) do
        if b.stuck then waiting = true end
    end
    self.catcher:SetShown(waiting)
    self.netLine:SetShown(run ~= nil and run.net > 0 and (run.state == "serve" or run.state == "play"))
    self.banner:SetShown(serving)
    self.hint:SetShown(serving)
    if serving then
        self.banner:SetText(("Wall %d: %s"):format(run.stage, run.name))
        self.hint:SetText("Click to fire")
    end
    self:RefreshBricks()
    self:Draw()
    self:RefreshSide()
    self:RefreshOverlay()
end
