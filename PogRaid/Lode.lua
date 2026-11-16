-- Pog Guild Tools games: Poggle, a peg-drop roguelike (Jake, 0.16.9). It was
-- "Motherlode" until 0.19.0: the guild called it Poggle, so Jake renamed it.
-- Only the name players see changed: the file, `ns.Lode`, the "lode" tab key,
-- the saved bests and the `lode` hiscores keep theirs.
--
-- You bomb your way down a mine. Each floor is a board of ore pegs: aim with
-- the mouse, click to drop a bomb from the top, and every peg it bounces off
-- is mined. A bucket slides back and forth along the bottom, all the time:
-- land in it and the bomb comes back (0.20.0: it was a cart that only moved
-- during a shot and paid three times a floor; the guild didn't take to it). Reach the floor's ore quota before the bombs run out and you go down
-- a floor, picking one of three upgrades on the way; miss it and the run is
-- over. You pick a class for the run: a perk, and upgrades of its own.
--
-- 0.19.0, from the guild's feedback (Jake: "make it a really good game"):
--   * the x1 x2 x5 pockets are gone ("too much RNG"): the cart is something
--     you can aim for and time, and ore counts as mined
--   * no dead ends ("you will never be able to go to the next stage even if
--     you have pegs left"): when what's left on the board can't make the
--     quota and half of it is mined, fresh rock caves in (Run:CaveIn)
--   * the top corners can be hit: the mortar swings to 88 degrees and no peg
--     sits above the flattest shot's path (Lode.Ceiling)
--   * classes, and twice the upgrades
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
Lode.MAX_AIM = math.rad(88) -- either side of straight down
Lode.LAUNCH_Y = 26
Lode.POCKET_H = 34          -- the strip along the bottom the bucket slides in
Lode.CART_W = 80            -- the bucket ("cart" in the code): land a bomb in it and it comes back (one bomb a shot at most)
Lode.CART_SPEED = 150       -- px/s, side to side, whether a bomb is in the air or not
Lode.BOMBS = 5              -- per floor
Lode.GIFTS = 2              -- bombs an upgrade can give back on one floor (the bucket's don't count)
Lode.CAVE_IN = true         -- fresh rock when the board can't make the quota (the tests switch it off to watch one peg)
Lode.CAVE_AT = 0.5          -- ...once this share of the pegs or fewer are left (deep floors need more than one board)
Lode.MAX_HITS = 3           -- a peg bounced on this often crumbles at once (so nothing rests on it)
Lode.SHOT_CAP = 12          -- seconds: a bomb still in the air then just lands
Lode.MAX_BALLS = 8
Lode.KEG_R = 62
Lode.PEGS, Lode.GOLD, Lode.KEGS, Lode.CRYSTALS = 46, 5, 3, 2
-- The first floor's quota and how it grows. Tuned by playing a few hundred runs headless (a scratch script: one
-- that clicks at random, one that tries a few aims and takes the best). Retune from Jake's playtesting.
Lode.QUOTA, Lode.QUOTA_GROWTH = 450, 1.5
Lode.WIPE = 1               -- (which wipe a save has had: see G)
Lode.share = true           -- our best run is shared with the guild (the "lodes" collection below)

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

-- Every upgrade is a spell or talent of the run's class (Jake, 0.20.0: "the upgrades you get offered are
-- all talents/spells from the classes", with the spell's own icon). A row: what it does (a key the rules
-- ask Run:Has about; two classes may share one under different names), the spell, its line, how many
-- times it can be taken, and its icon. No two classes have the same upgrade (Jake, the day after: "let's get
-- rid of the abilities that are the same across classes"), so a key belongs to one class.
Lode.SPELLS = {
    warrior = {
        { "cleave", "Cleave", "Mining a peg also mines the one next to it.", 2, "Ability_Warrior_Cleave" },
        { "blood", "Bloodthirst", "Mine 10 pegs in one shot and it pays 50% more.", 1, "Spell_Nature_BloodLust" },
        { "spare", "Battle Shout", "+1 bomb every floor.", 5, "Ability_Warrior_BattleShout" },
        { "last", "Execute", "Your last bomb of a floor mines triple.", 1, "INV_Sword_48" },
        { "big", "Whirlwind", "Kegs blow up a bigger area.", 3, "Ability_Whirlwind" },
        { "heroic", "Heroic Strike", "Your first bomb of a floor mines double.", 1, "Ability_Rogue_Ambush" },
        { "clap", "Thunder Clap", "Your bomb mines the pegs near where it lands.", 1, "Spell_Nature_ThunderClap" },
        { "stand", "Last Stand", "Once a run, running out of bombs gives you 3 more.", 1, "Spell_Holy_AshesToAshes" },
    },
    mage = {
        { "nova", "Arcane Explosion", "Crystals blow up as big as a keg.", 1, "Spell_Nature_WispSplode" },
        { "evoc", "Evocation", "Hit a crystal and you get the bomb back, twice a floor.", 1, "Spell_Nature_Purge" },
        { "geode", "Mana Gem", "1 extra crystal every floor.", 3, "INV_Misc_Gem_Emerald_01" },
        { "kegs", "Pyroblast", "1 extra keg every floor.", 3, "Spell_Fire_Fireball02" },
        { "streak", "Combustion", "From the 8th peg of a shot on, ore counts double.", 1, "Spell_Fire_SealOfFire" },
        { "rubber", "Blink", "Bouncier bombs.", 3, "Spell_Arcane_Blink" },
        { "sheep", "Polymorph", "The first ore peg of every shot pays like gold.", 1, "Spell_Nature_Polymorph" },
        { "missiles", "Arcane Missiles", "Crystals split your bomb in three, not two.", 1, "Spell_Nature_StarFall" },
    },
    rogue = {
        { "ambush", "Ambush", "The first peg of every shot pays 5x.", 2, "Ability_Rogue_Ambush" },
        { "pick", "Pick Pocket", "Gold can hand the bomb back (1 in 3), twice a floor.", 1, "INV_Misc_Bag_11" },
        { "prospector", "Pick Lock", "2 extra gold veins every floor.", 4, "INV_Misc_Key_03" },
        { "fever", "Backstab", "Gold veins pay double.", 5, "Ability_BackStab" },
        { "lucky", "Malice", "+10% chance for ore to count double.", 5, "Ability_Racial_BloodRage" },
        { "deep", "Preparation", "Leftover bombs carry over to the next floor.", 1, "Spell_Shadow_AntiShadow" },
        { "vanish", "Vanish", "Once a floor, a shot that mines nothing comes back.", 1, "Ability_Vanish" },
        { "seal", "Seal Fate", "Lucky ore pays triple, not double.", 1, "Spell_Shadow_ChillTouch" },
    },
    hunter = {
        { "multi", "Multi-Shot", "Every shot drops one more bomb.", 1, "Ability_UpgradeMoonGlaive" },
        { "twin", "Scatter Shot", "Your bomb splits in two on its first hit.", 1, "Ability_GolemStormBolt" },
        { "cart", "Entrapment", "A wider bucket.", 3, "Spell_Nature_StrangleVines" },
        { "rich", "Hunter's Mark", "+3 ore from every peg.", 9, "Ability_Hunter_SniperShot" },
        { "freeze", "Freezing Trap", "The bucket holds still while your bomb is in the air.", 1, "Spell_Frost_ChainsOfIce" },
        { "sting", "Serpent Sting", "Bouncing on a peg you already hit pays half again.", 1, "Ability_Hunter_Quickshot" },
        { "pet", "Call Pet", "Your pet digs up 3 ore pegs at the start of every floor.", 3, "Ability_Hunter_BeastCall" },
    },
}
-- A class's spell for what an upgrade does (nil: not one of its own). A run without a class has
-- none: nobody plays one, but the tests do, and give it a list of its own (SPELLS.none).
function Lode.Spells(class) return Lode.SPELLS[class or "none"] or {} end
function Lode.Spell(class, key)
    for _, u in ipairs(Lode.Spells(class)) do
        if u[1] == key then return u end
    end
end
function Lode.UpgradeIcon(key, class)
    local u = Lode.Spell(class, key)
    return u and ("Interface\\Icons\\" .. u[5]) or 134400
end

-- A class for the run (asked for by guildies: "mage would have its own set of powerups"): key, name,
-- its perk, and the bomb's colour (the class's own).
Lode.CLASSES = {
    { "warrior", "Warrior", "2 extra bombs every floor, and pegs pay 50% more.", color = { 0.78, 0.61, 0.43 } },
    -- (it was "your bomb splits in two on its first hit", much the same as the Hunter's two bombs: Jake had
    --  crystals made the Mage's own thing instead)
    { "mage", "Mage", "3 extra crystals every floor, and crystals blow up.", color = { 0.41, 0.80, 0.94 } },
    { "rogue", "Rogue", "Gold pays double, and ore has a 10% chance to.", color = { 1.00, 0.96, 0.41 } },
    -- (it was a wider bucket and the long aim line. Jake: "hunter's perk in poggle seems very very weak")
    { "hunter", "Hunter", "Every shot drops two bombs, with an aim line twice as long.", color = { 0.67, 0.83, 0.45 } },
}
Lode.CLASS = {}
for _, c in ipairs(Lode.CLASSES) do Lode.CLASS[c[1]] = c end
Lode.CLEAVE_R = 40          -- how far Cleave reaches (plus half again a second time)
Lode.CLAP_R = 100           -- how far Thunder Clap reaches from where the bomb lands
Lode.STAND = 3              -- the bombs Last Stand gives, once a run
Lode.PET = 3                -- the ore pegs Call Pet digs up as a floor starts (each time it's taken)
Lode.NOVA = 0.7             -- a Mage's crystal blast, as a share of a keg's
Lode.MAGE_CRYSTALS = 3      -- extra crystals on every floor for a Mage
Lode.WARRIOR_ORE = 1.5      -- what a peg is worth to a Warrior
Lode.WARRIOR_BOMBS = 2      -- and the extra bombs on every floor
Lode.SPREAD = math.rad(5)   -- a Hunter's two bombs, this far either side of the aim

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

-- How high a peg at `x` may sit and still be hit straight from the mortar: the path of the
-- flattest shot there, less a little (guildies: "I cannot aim at the pegs in the top right / left
-- corner so I just have to shoot the ball down the hole 14 times").
function Lode.Ceiling(x)
    local vx, vy = Lode.SPEED * math.sin(Lode.MAX_AIM), Lode.SPEED * math.cos(Lode.MAX_AIM)
    local t = math.abs(x - Lode.W / 2) / vx
    return Lode.LAUNCH_Y + vy * t + Lode.GRAVITY * t * t / 2 - (Lode.BALL_R + Lode.PEG_R) / 2
end

-- A floor's pegs: a staggered grid of spots, jittered, a random lot of them
-- filled. `gold` veins, the kegs and crystals, the rest ore. None higher than
-- a bomb can be aimed.
function Lode.Board(rand, gold, kegs, crystals)
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
    kegs, crystals = kegs or Lode.KEGS, crystals or Lode.CRYSTALS
    gold = math.min(gold or Lode.GOLD, n - kegs - crystals)
    for i = 1, n do
        local kind = i <= kegs and "keg" or i <= kegs + crystals and "crystal" or i <= kegs + crystals + gold and "gold" or "ore"
        local x, y = spots[i].x + (rand() - 0.5) * 10, spots[i].y + (rand() - 0.5) * 10
        pegs[i] = { x = x, y = math.max(y, Lode.Ceiling(x)), kind = kind, hits = 0 }
    end
    return pegs
end

local Run = {}
Run.__index = Run
Lode.Run = Run

function Run.New(seed, class)
    -- `events` is what has happened since someone last looked (a peg mined, a keg gone up, a bomb landed):
    -- the screen shows them and empties the list; the rules never read it
    local run = setmetatable({ seed = seed, rand = Lode.Rng(seed), floor = 0, total = 0, cleared = 0, shots = 0,
        class = Lode.CLASS[class] and class or nil,
        upgrades = {}, carried = 0, balls = {}, events = {}, state = "aim" }, Run)
    run:NextFloor()
    return run
end

function Run:Has(key) return self.upgrades[key] or 0 end
function Run:Is(class) return self.class == class end
-- (a Warrior's pegs are worth more: two extra bombs alone fell behind as the quota grew, the balance script)
function Run:OreValue()
    local v = 10 + 2 * (self.floor - 1) + 3 * self:Has("rich")
    return self:Is("warrior") and math.floor(v * Lode.WARRIOR_ORE + 0.5) or v
end
function Run:GoldValue() return self:OreValue() * 5 * (1 + self:Has("fever") + (self:Is("rogue") and 1 or 0)) end
function Run:KegRadius() return Lode.KEG_R * (1 + 0.3 * self:Has("big")) end
function Run:Luck() return 0.1 * (self:Has("lucky") + (self:Is("rogue") and 1 or 0)) end
function Run:Twin() return self:Has("twin") > 0 end
-- How big a crystal's blast is, as a share of a keg's (nil: it just splits the bomb). A Mage's crystals blow
-- up small; Arcane Explosion makes that a keg's size (or a small one for anyone else who has it).
function Run:Nova()
    local mage, spell = self:Is("mage"), self:Has("nova") > 0
    if mage and spell then return 1 end
    if mage or spell then return Lode.NOVA end
end
function Run:LongAim() return self:Is("hunter") end
function Run:CartWidth() return Lode.CART_W * (1 + 0.25 * self:Has("cart")) end
-- Bombs a shot: a Hunter's two, and one more with Multi-Shot.
function Run:Volley() return 1 + (self:Is("hunter") and 1 or 0) + self:Has("multi") end
function Run:BombsAFloor() return Lode.BOMBS + self:Has("spare") + (self:Is("warrior") and Lode.WARRIOR_BOMBS or 0) end

function Run:NewBoard()
    return Lode.Board(self.rand, Lode.GOLD + 2 * self:Has("prospector"), Lode.KEGS + self:Has("kegs"), Lode.CRYSTALS + self:Has("geode") + (self:Is("mage") and Lode.MAGE_CRYSTALS or 0))
end

function Run:NextFloor()
    self.floor = self.floor + 1
    self.ore, self.quota = 0, Lode.Quota(self.floor)
    self.bombs = self:BombsAFloor() + self.carried
    self.carried = 0
    self.pegs = self:NewBoard()
    self.cart = self.cart or { x = Lode.W / 2, dir = 1 }
    self.gifts, self.floorShots, self.vanished = 0, 0, nil
    -- Call Pet: a few ore pegs are dug up before the first shot
    for _ = 1, Lode.PET * self:Has("pet") do
        local ores = {}
        for _, p in ipairs(self.pegs) do
            if p.kind == "ore" and not p.gone then ores[#ores + 1] = p end
        end
        if not ores[1] then break end
        local p = ores[math.floor(self.rand() * #ores) + 1]
        p.gone = true
        self.ore, self.total = self.ore + self:OreValue(), self.total + self:OreValue()
    end
    self.balls, self.offers, self.last = {}, nil, nil
    self.state = "aim"
    self.dirty = true
end

-- What the pegs still standing are worth: can the quota still be made?
function Run:Potential()
    local sum, ore, gold = 0, self:OreValue(), self:GoldValue()
    for _, p in ipairs(self.pegs) do
        if not p.gone then sum = sum + (p.kind == "gold" and gold or ore) end
    end
    return sum
end

-- How many pegs are still standing.
function Run:PegsLeft()
    local n = 0
    for _, p in ipairs(self.pegs) do
        if not p.gone then n = n + 1 end
    end
    return n
end

-- Is the board spent? What's left can't make the quota, and half of it or
-- more has been mined. (Deep down a whole board is worth less than the
-- quota: it's mined half away, then fresh rock comes, as often as it takes.)
function Run:Spent()
    return self.ore + self:Potential() < self.quota and self:PegsLeft() <= Lode.PEGS * Lode.CAVE_AT
end

-- The board is spent: fresh rock comes down. The ore mined so far and the
-- bombs stay as they are.
function Run:CaveIn()
    self.pegs = self:NewBoard()
    self.caveins = (self.caveins or 0) + 1
    self.events[#self.events + 1] = { kind = "cavein" }
    self.dirty = true
end

-- Drop a bomb. `angle` is from straight down, in radians, right positive.
function Run:Fire(angle)
    if self.state ~= "aim" or self.bombs <= 0 then return false end
    angle = math.max(-Lode.MAX_AIM, math.min(Lode.MAX_AIM, tonumber(angle) or 0))
    self.bombs = self.bombs - 1
    self.shots = self.shots + 1
    self.floorShots = (self.floorShots or 0) + 1
    self.balls = {}
    -- (two go either side of the aim, three with one down the middle)
    local n, angles = self:Volley(), {}
    for i = 1, n do angles[i] = angle + (i - (n + 1) / 2) * 2 * Lode.SPREAD end
    for i, a in ipairs(angles) do
        self.balls[i] = { x = Lode.W / 2, y = Lode.LAUNCH_Y, vx = Lode.SPEED * math.sin(a), vy = Lode.SPEED * math.cos(a),
            ore = 0, first = true }
    end
    self.landed, self.events, self.pegsHit, self.given, self.sheeped = {}, {}, 0, nil, nil
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
        if self:Has("pick") > 0 and self.rand() < 1 / 3 then self:GiveBomb("pick", peg.x, peg.y) end
    elseif peg.kind == "ore" and self.rand() < self:Luck() then
        v = v * (self:Has("seal") > 0 and 3 or 2)
        peg.lucky = true
    end
    local nth = (self.pegsHit or 0) + 1
    -- Polymorph: the first ore peg of a shot is worth what gold is
    if peg.kind == "ore" and not self.sheeped and self:Has("sheep") > 0 then
        self.sheeped = true
        v = math.max(v, self:GoldValue())
    end
    if self.floorShots == 1 and self:Has("heroic") > 0 then v = v * 2 end
    if nth == 1 and self:Has("ambush") > 0 then v = v * 5 * self:Has("ambush") end
    if nth >= 8 and self:Has("streak") > 0 then v = v * 2 end
    if self.bombs == 0 and self:Has("last") > 0 then v = v * 3 end
    ball.ore = ball.ore + v
    self.pegsHit = nth
    self.events[#self.events + 1] = { kind = "mine", x = peg.x, y = peg.y, v = v, peg = peg.kind, lucky = peg.lucky, ref = peg }
    self.dirty = true
end

-- A bomb comes back (the bucket, an upgrade): `why` is for the screen. One a
-- shot at most, whatever gives it: with two (a split bomb, both halves in
-- the cart) a careful player made more bombs than they spent and never ran
-- out (found by the balance script, 0.19.0). Returns whether it was given.
function Run:GiveBomb(why, x, y)
    if self.given then return false end
    if why ~= "cart" then
        -- an upgrade's: only so many a floor (a Mage hitting a crystal every shot never ran out either)
        if (self.gifts or 0) >= Lode.GIFTS then return false end
        self.gifts = (self.gifts or 0) + 1
    end
    self.given = true
    self.bombs = self.bombs + 1
    self.events[#self.events + 1] = { kind = "bomb", why = why, x = x, y = y }
    self.dirty = true
    return true
end

-- A keg goes up: everything near it is mined and gone, other kegs in turn.
-- (`radius`: a crystal's Arcane Explosion is a smaller one.)
function Run:Explode(keg, ball, radius)
    keg.gone = true
    local r2 = (radius or self:KegRadius()) ^ 2
    for _, p in ipairs(self.pegs) do
        if not p.gone and (p.x - keg.x) ^ 2 + (p.y - keg.y) ^ 2 <= r2 then
            self:Mine(p, ball)
            if p.kind == "keg" then self:Explode(p, ball) else p.gone = true end
        end
    end
    self.blasts = self.blasts or {}
    self.blasts[#self.blasts + 1] = { x = keg.x, y = keg.y, r = radius or self:KegRadius() }
    self.events[#self.events + 1] = { kind = "blast", x = keg.x, y = keg.y, r = radius or self:KegRadius() }
end

-- Cleave: the nearest peg within reach of this one is mined with it.
function Run:Cleave(peg, ball)
    local reach = (Lode.CLEAVE_R * (1 + 0.5 * (self:Has("cleave") - 1))) ^ 2
    local best, bestD
    for _, p in ipairs(self.pegs) do
        if p ~= peg and not p.gone and not p.lit then
            local d = (p.x - peg.x) ^ 2 + (p.y - peg.y) ^ 2
            if d <= reach and (not bestD or d < bestD) then best, bestD = p, d end
        end
    end
    if best then self:Mine(best, ball) end
end

-- A second bomb from where this one is, going the other way.
function Run:Split(ball, third)
    if #self.balls >= Lode.MAX_BALLS then return end
    local vx = -ball.vx
    if math.abs(vx) < 60 then vx = (ball.vx >= 0 and -1 or 1) * 120 end
    if third then vx = vx / 4 end -- (Arcane Missiles: one more, nearly straight down)
    self.balls[#self.balls + 1] = { x = ball.x, y = ball.y, vx = vx, vy = ball.vy, ore = 0 }
end

function Run:Hit(peg, ball)
    peg.hits = peg.hits + 1
    local fresh = not peg.lit
    if peg.lit then
        self.events[#self.events + 1] = { kind = "hit", ref = peg }
        -- Serpent Sting: a peg already hit pays again, half as much
        if self:Has("sting") > 0 then ball.ore = ball.ore + math.floor(self:OreValue() / 2) end
    end
    self:Mine(peg, ball)
    if fresh and self:Has("cleave") > 0 then self:Cleave(peg, ball) end
    if peg.kind == "keg" then
        self:Explode(peg, ball)
    elseif peg.kind == "crystal" then
        if self:Has("evoc") > 0 then self:GiveBomb("evoc", peg.x, peg.y) end
        local nova = self:Nova()
        if nova then self:Explode(peg, ball, Lode.KEG_R * nova) else peg.gone = true end
        self:Split(ball)
        if self:Has("missiles") > 0 then self:Split(ball, true) end
    elseif peg.hits >= Lode.MAX_HITS then
        peg.gone = true
    end
    if ball.first then
        ball.first = nil
        if self:Twin() then self:Split(ball) end
    end
    self.dirty = true
end

-- A bomb reaches the bottom: what it mined is banked, and if the bucket was
-- under it the bomb comes back. (`timeout`: it never got there.)
function Run:Land(ball, timeout)
    ball.done = true
    if not timeout and self:Has("clap") > 0 then
        local y, r2 = Lode.H - Lode.POCKET_H / 2, Lode.CLAP_R ^ 2
        for _, p in ipairs(self.pegs) do
            if not p.gone and not p.lit and (p.x - ball.x) ^ 2 + (p.y - y) ^ 2 <= r2 then self:Mine(p, ball) end
        end
    end
    local gain = ball.ore
    local inCart = not timeout and math.abs(ball.x - self.cart.x) <= self:CartWidth() / 2
    self.ore, self.total = self.ore + gain, self.total + gain
    local event = { kind = "land", x = ball.x, gain = gain }
    self.events[#self.events + 1] = event
    -- (caught = it gave the bomb back: only the first of a shot does)
    local caught = inCart and self:GiveBomb("cart", ball.x, Lode.H - Lode.POCKET_H) or false
    event.caught = caught
    self.landed[#self.landed + 1] = { ore = ball.ore, gain = gain, caught = caught }
    self.dirty = true
end

-- The bucket: back and forth, at one speed, for ever.
function Run:MoveCart(h)
    local cart, half = self.cart, self:CartWidth() / 2
    cart.x = cart.x + cart.dir * Lode.CART_SPEED * h
    if cart.x < half then
        cart.x, cart.dir = half, 1
    elseif cart.x > Lode.W - half then
        cart.x, cart.dir = Lode.W - half, -1
    end
end

-- It keeps moving while you aim, so a shot can be timed (the screen calls this).
function Run:Idle(dt)
    if self.state == "aim" then self:MoveCart(math.max(0, math.min(dt or 0, 0.05))) end
end

function Run:Tick(h)
    local W, r, R = Lode.W, Lode.BALL_R, Lode.PEG_R
    local reach = (r + R) ^ 2
    local e = Lode.BOUNCE + 0.06 * self:Has("rubber")
    self.shotTime = self.shotTime + h
    if self:Has("freeze") == 0 then self:MoveCart(h) end
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
            if b.y >= Lode.H - Lode.POCKET_H / 2 then
                self:Land(b)
            elseif self.shotTime > Lode.SHOT_CAP then
                self:Land(b, true)
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
    if self:Has("blood") > 0 and (self.pegsHit or 0) >= 10 and gain > 0 then
        local bonus = math.floor(gain / 2)
        self.ore, self.total, self.last.gain = self.ore + bonus, self.total + bonus, gain + bonus
        self.events[#self.events + 1] = { kind = "bonus", why = "blood", gain = bonus }
    end
    if (self.pegsHit or 0) == 0 and self:Has("vanish") > 0 and not self.vanished and self:GiveBomb("vanish") then
        self.vanished = true
    end
    if self.ore < self.quota and self.bombs <= 0 and self:Has("stand") > 0 and not self.stood then
        self.stood = true
        self.bombs = Lode.STAND
        self.events[#self.events + 1] = { kind = "bomb", why = "stand" }
    end
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
        -- never a floor that can't be finished with bombs still in hand
        if Lode.CAVE_IN and self:Spent() then self:CaveIn() end
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

-- Three of the class's spells to pick from (fewer once most are taken as often as they can be;
-- none without a class).
function Run:Offers()
    local pool = {}
    for _, u in ipairs(Lode.Spells(self.class)) do
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
    ns.db.games.lode = ns.db.games.lode or { bests = {}, runs = 0, wipe = Lode.WIPE }
    local g = ns.db.games.lode
    -- The wipe (Jake, for 0.20.3: "lets reset the poggle hiscores in next version"): a best from before it is
    -- forgotten, and the runs counted with it, so the board starts level after the class rework. The class last
    -- picked is kept. Lode.WIPE says which wipe a save has had; raise it to do it again.
    if g.wipe ~= Lode.WIPE then g.bests, g.runs, g.wipe = {}, 0, Lode.WIPE end
    -- (a best is kept for each class since 0.20.3: the one best of a save from before that isn't any class's)
    g.bests = g.bests or {}
    g.depth, g.ore = nil, nil
    return g
end
Lode.Saved = G

-- Our best with a class: { depth, ore } (Jake, 0.20.3: "let's make the poggle leaderboard class specific". The
-- classes play too differently to share a board: a Rogue's ore isn't a Warrior's.) A run without a class, which
-- only the tests make, has a best of its own that's never shared.
function Lode:Best(class)
    local g = G()
    local key = Lode.CLASS[class or ""] and class or "none"
    g.bests[key] = g.bests[key] or { depth = 0, ore = 0 }
    return g.bests[key]
end

-- A run is over: counted, and kept if it's our deepest with its class (most ore breaks a tie).
function Lode:Finish(run)
    local g = G()
    g.runs = g.runs + 1
    local b = self:Best(run.class)
    if run.cleared > b.depth or (run.cleared == b.depth and run.total > b.ore) then
        b.depth, b.ore = run.cleared, run.total
        self:Publish(run.class)
        return true
    end
    return false
end

-- The guild's hiscores: one record a player and class, their deepest run with it (Jake: "add a
-- hiscore"). A new kind of record costs something while the guild is on
-- mixed versions: an addon older than 0.16.9 can't file it and asks for it
-- again at every check-in (a few small messages every ten minutes while old
-- and new are online together), until it updates. Jake's call to have the
-- board now; Lode.share = false turns the writing off again.
-- ("lodes", code y: it was "lode", code m, until the wipe. A new collection is the only way to empty the board
--  for everyone at once: nobody can delete someone else's record. As with Angler's "anglers", code x.)
ns.Sync:Register({
    name = "lodes", code = "y", order = 4,
    fields = { "class", "depth", "ore" },
    numeric = { depth = true, ore = true },
    valid = function(rec)
        return rec.by == rec.author and Lode.CLASS[rec.class or ""] ~= nil and rec.id == rec.author .. ":" .. rec.class
            and rec.depth ~= nil and rec.depth >= 0 and rec.depth <= 999
            and rec.depth == math.floor(rec.depth) and rec.ore ~= nil and rec.ore >= 0 and rec.ore < 1e9
    end,
    onChange = function() Lode:Refresh() end,
})

function Lode:Publish(class)
    if not Lode.share or not Lode.CLASS[class or ""] or not ns.Sync:GuildName() then return false end
    local g, me = self:Best(class), ns.Sync:Me()
    local id = me .. ":" .. class
    local cur = (ns.Sync:Store("lodes") or {})[id]
    if cur and not cur.deleted and (cur.depth > g.depth or (cur.depth == g.depth and cur.ore >= g.ore)) then return false end
    ns.Sync:Write("lodes", { id = id, author = me, t = ns.Now(), class = class, depth = g.depth, ore = math.floor(g.ore) })
    return true
end

-- A class's board: deepest first, then most ore.
function Lode:Leaderboard(class)
    local out = {}
    for _, rec in pairs(ns.Sync:Store("lodes") or {}) do
        if not rec.deleted and rec.class == class then out[#out + 1] = rec end
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
local CART_H = 24
local GREEN = { 0.45, 1, 0.45 }
local CLASS_W, CLASS_H, CLASS_GAP = 126, 168, 8 -- the four class tiles
local TILE_W, TILE_H, TILE_GAP = 164, 138, 10
local TRAIL = 7                 -- sparks behind a bomb
local FLOATS, RINGS = 30, 6     -- "+10"s in the air at once, keg blasts
local PIPS = 10                 -- bombs shown as pips on the run card
local UPS = 12                  -- rows for the spells taken (a class has eleven at most)
local POP, FADE = 0.2, 0.28     -- seconds: a peg's ring jumps when hit; a mined peg fades away
local APPEAR, STAGGER = 0.25, 0.4 -- a new floor's pegs fade in, the top rows first
local LIT_GLOW, IDLE_GLOW = 0.5, 0.22 -- a hit peg's halo; the slow pulse of gold, kegs and crystals
local FOOT_H = 70               -- the run card's foot: our best, Hiscores and New run
local SCORE_ROWS, SCORE_W, SCORE_TOP = 8, 340, 322 -- the guild's hiscores on the board's overlay
local SCORE_TAB_W, SCORE_TAB_H, SCORE_TAB_GAP = 82, 22, 4 -- a tab a class over them (4 x 82 + 3 x 4 = SCORE_W)
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
    IDLE_GLOW = IDLE_GLOW, FOOT_H = FOOT_H, LEGEND_H = LEGEND_H, SCORE_ROWS = SCORE_ROWS, SCORE_W = SCORE_W, SCORE_TOP = SCORE_TOP,
    SCORE_TAB_W = SCORE_TAB_W, SCORE_TAB_H = SCORE_TAB_H, SCORE_TAB_GAP = SCORE_TAB_GAP }

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

-- a class's picture: its square from the character-creation sheet (never a masked texture: those can't be cropped)
Lode.CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
function Lode.ClassIcon(tex, class)
    local token = class and class:upper()
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    tex:SetTexture(Lode.CLASS_SHEET)
    if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
end

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

    -- the bucket along the bottom: land a bomb in it and it comes back
    local cart = CreateFrame("Frame", nil, board)
    cart:SetSize(Lode.CART_W, CART_H)
    cart:SetPoint("BOTTOM", board, "BOTTOMLEFT", Lode.W / 2, 5)
    cart.body = cart:CreateTexture(nil, "BORDER")
    cart.body:SetPoint("TOPLEFT", 0, 0)
    cart.body:SetPoint("BOTTOMRIGHT", 0, 5)
    cart.body:SetColorTexture(0.20, 0.15, 0.10, 1)
    cart.rim = cart:CreateTexture(nil, "ARTWORK")
    cart.rim:SetPoint("TOPLEFT", 0, 0)
    cart.rim:SetPoint("TOPRIGHT", 0, 0)
    cart.rim:SetHeight(3)
    cart.rim:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    cart.ore = cart:CreateTexture(nil, "ARTWORK", nil, 1)
    cart.ore:SetPoint("TOPLEFT", 4, -3)
    cart.ore:SetPoint("TOPRIGHT", -4, -3)
    cart.ore:SetHeight(5)
    cart.ore:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.30)
    cart.wheels = {}
    for i, x in ipairs({ 0.22, 0.78 }) do
        cart.wheels[i] = disc(cart, "OVERLAY", 0, 10, 0.55, 0.50, 0.45, 1)
        cart.wheels[i].at = x
    end
    cart.flash = cart:CreateTexture(nil, "OVERLAY", nil, 1)
    cart.flash:SetAllPoints(cart.body)
    cart.flash:SetColorTexture(0.6, 1, 0.6, 0.7)
    cart.flash:Hide()
    cart:Hide()
    self.cart = cart
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
    for i = 1, 2 * DOTS do -- (twice as many with Aimed Shot)
        local d = disc(board, "ARTWORK", 6, math.max(3, 6 - i * 0.2), 1, 0.92, 0.62, 0.75 * (1 - (i - 1) / (2 * DOTS)) + 0.15)
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
    for _, c in ipairs(Lode.CLASSES) do
        if G().bests[c[1]] then self:Publish(c[1]) end -- (a best made while sharing was off, or out of a guild)
    end
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
    s.title = UI.SectionTitle(s, "Poggle")
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
    for i = 1, UPS do
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
            local u = Lode.Spell(Lode.run and Lode.run.class, r.key)
            if not u then return end
            GameTooltip:AddLine(u[2], 1, 1, 1)
            GameTooltip:AddLine(u[3], nil, nil, nil, true)
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
    -- (no "Sure?", and it works with a bomb in the air: Jake, 0.20.0. It opens the class picker, the shot
    --  waits behind it, and Back there goes on with the run, so nothing is lost by a stray click.)
    s.newRun = UI.Button(s, "New run", 120, 24, function() self:NewRun() end)
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
        if self.picking then
            self.picking = nil
            self:Refresh()
        elseif self.showScores then
            self.showScores = nil
            self:Refresh()
        else
            self:NewRun()
        end
    end)
    o.start:SetPoint("TOP", o.sub, "BOTTOM", 0, -18)
    -- the guild's hiscores: deepest run first. Up before a run, after one, and when asked for.
    o.scoreTitle = UI.Text(o, 13)
    o.scoreTitle:SetPoint("TOP", 0, -(SCORE_TOP - 6 - SCORE_TAB_H - 24))
    o.scoreTitle:SetText("Guild hiscores")
    o.scoreTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    -- a board a class: the tabs pick whose (the class being played, until one is clicked)
    o.scoreTabs = {}
    for i, c in ipairs(Lode.CLASSES) do
        local t = UI.Button(o, c[2], SCORE_TAB_W, SCORE_TAB_H, function()
            self.scoreClass = c[1]
            self:Refresh()
        end)
        t:SetPoint("TOPLEFT", (Lode.W - SCORE_W) / 2 + (i - 1) * (SCORE_TAB_W + SCORE_TAB_GAP), -(SCORE_TOP - 6 - SCORE_TAB_H))
        UI.Unred(t)
        t.key = c[1]
        o.scoreTabs[i] = t
    end
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
    -- the classes, picked before a run
    o.classes = {}
    local across = #Lode.CLASSES * CLASS_W + (#Lode.CLASSES - 1) * CLASS_GAP
    for i, c in ipairs(Lode.CLASSES) do
        local t = CreateFrame("Button", nil, o)
        t:SetSize(CLASS_W, CLASS_H)
        t:SetPoint("TOPLEFT", (Lode.W - across) / 2 + (i - 1) * (CLASS_W + CLASS_GAP), -250)
        UI.Card(t)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.09)
        t.last = t:CreateTexture(nil, "BORDER")
        t.last:SetPoint("BOTTOMLEFT", 6, 4)
        t.last:SetPoint("BOTTOMRIGHT", -6, 4)
        t.last:SetHeight(2)
        t.last:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(36, 36)
        t.icon:SetPoint("TOP", 0, -12)
        Lode.ClassIcon(t.icon, c[1])
        t.name = UI.Text(t, 13)
        t.name:SetPoint("TOP", 0, -54)
        t.name:SetText(c[2])
        local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c[1]:upper()]
        if col then t.name:SetTextColor(col.r, col.g, col.b) end
        t.desc = UI.Text(t, 11)
        t.desc:SetPoint("TOP", t.name, "BOTTOM", 0, -6)
        t.desc:SetWidth(CLASS_W - 16)
        t.desc:SetJustifyH("CENTER")
        t.desc:SetText(c[3])
        t.own = UI.Text(t, 10)
        t.own:SetPoint("BOTTOM", 0, 12)
        t.own:SetWidth(CLASS_W - 12)
        t.own:SetJustifyH("CENTER")
        t.own:SetTextColor(0.6, 0.6, 0.65)
        t.own:SetText(("%d %s spells to learn"):format(#Lode.SPELLS[c[1]], c[2]))
        t.key = c[1]
        t:SetScript("OnClick", function() self:NewRun(nil, c[1]) end)
        o.classes[i] = t
    end
    o:Hide()
    self.overlay = o
end

-- The bombs in the class's colour (the plain fiery one without a class).
function Lode:Tint()
    local class = self.run and self.run.class or false
    if self.tint == class then return end
    self.tint = class
    local c = class and Lode.CLASS[class].color
    local core, glow = c or { 1, 0.80, 0.32 }, c or HOT
    for _, b in ipairs(self.ballArt) do
        b:SetVertexColor(core[1], core[2], core[3], 1)
        b.glow:SetVertexColor(glow[1], glow[2], glow[3], 0.95)
        for k, t in ipairs(b.trail) do t:SetVertexColor(glow[1], glow[2], glow[3], 0.6 * (1 - k / (TRAIL + 1))) end
    end
    self.mortarGlow:SetVertexColor(glow[1], glow[2], glow[3], 0.5)
end

-- The bucket where the rules have it, as wide as it is this run.
function Lode:PlaceCart()
    local run, cart = self.run, self.cart
    cart:SetShown(run ~= nil)
    if not run then return end
    local w = run:CartWidth()
    cart:SetWidth(w)
    cart:ClearAllPoints()
    cart:SetPoint("BOTTOM", self.board, "BOTTOMLEFT", run.cart.x, 5)
    for _, wheel in ipairs(cart.wheels) do
        wheel:ClearAllPoints()
        wheel:SetPoint("CENTER", cart, "BOTTOMLEFT", w * wheel.at, 4)
    end
end

------------------------------------------------------------------------
-- Playing
------------------------------------------------------------------------
-- A new run starts with a class: asked for here unless one is given.
function Lode:NewRun(seed, class)
    if seed == nil and class == nil then
        self.picking, self.showScores = true, nil
        self:Refresh()
        return
    end
    G().class = Lode.CLASS[class] and class or nil
    self.scoreClass = nil -- (the board goes back to the class being played)
    self.run = Run.New(seed or (math.floor(GetTime() * 1000) % 2147483646 + math.random(1, 100000)), class)
    self.newBest, self.showScores, self.picking = nil, nil, nil
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
    if not run or run.state ~= "aim" or self.showScores or self.picking then return end
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
            if e.gain > 0 then
                self:Float(e.x, Lode.H - Lode.POCKET_H - 14, "+" .. commas(e.gain), 17, GOLD, 1.3, 44)
                ns.Sound("LOOT_WINDOW_COIN_SOUND")
            end
        elseif e.kind == "bomb" then
            if e.why == "cart" then
                self.cart.flash:Show()
                UI.Fade(self.cart.flash, 1, 0, 0.9)
                self:Float(run.cart.x, Lode.H - Lode.POCKET_H - 34, "Free bomb!", 16, GREEN, 1.3, 40)
                self:Flash(0.12)
                ns.Sound("IG_QUEST_LIST_COMPLETE")
            else
                local say = e.why == "stand" and ("Last Stand! +%d bombs"):format(Lode.STAND) or e.why == "vanish" and "Vanish! +1 bomb" or "+1 bomb"
                self:Float(e.x or Lode.W / 2, (e.y or Lode.H / 2) - 26, say, e.why == "stand" and 18 or 14, GREEN, 1.1, 34)
            end
        elseif e.kind == "bonus" then
            self:Float(Lode.W / 2, Lode.H / 2 - 10, "Bloodthirst +" .. commas(e.gain), 18, HOT, 1.4, 44)
        elseif e.kind == "cavein" then
            self:Float(Lode.W / 2, Lode.H / 2 - 70, "Cave-in! Fresh rock", 20, GOLD, 1.6, 40)
            self:Flash(0.2)
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
        if run.state == "flying" and self.picking then
            -- (a bomb in the air waits while a class is being picked)
        elseif run.state == "flying" then
            run:Step(elapsed)
            self:ShowEvents()
            if run.state ~= "flying" then self:ShotOver() end
            self:PlaceCart()
            for i, b in ipairs(run.balls) do
                local art = self.ballArt[i]
                if art and not b.done then
                    table.insert(art.path, 1, { b.x, b.y })
                    art.path[TRAIL + 2] = nil
                end
            end
            self:Draw()
        elseif run.state == "aim" then
            if not self.picking then
                run:Idle(elapsed)
                self:PlaceCart()
            end
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
        local caught = 0
        for _, l in ipairs(last.landed) do
            if l.caught then caught = caught + 1 end
        end
        local parts = { last.gain > 0 and ("+%s ore"):format(commas(last.gain)) or "Nothing hit" }
        if caught > 0 then parts[#parts + 1] = caught == 1 and "bomb caught" or (caught .. " bombs caught") end
        self.message:SetText(table.concat(parts, ", ") .. ".")
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
    local dots = run:Preview(angle, DOTS * (run:LongAim() and 2 or 1), DOT_GAP)
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
    -- our best with the class being played (the last one played, between runs)
    local class = run and run.class or (not run and g.class) or nil
    local b, cname = self:Best(class), Lode.CLASS[class or ""] and Lode.CLASS[class][2]
    if g.runs == 0 then
        s.best:SetText("No runs yet")
    elseif cname and b.depth == 0 and b.ore == 0 then
        s.best:SetText(("No %s best yet"):format(cname))
    else
        s.best:SetText(("%s: floor %d, %s ore"):format(cname and (cname .. " best") or "Best", b.depth, commas(b.ore)))
    end
    local floor = run and run.floor or 1
    s.seam:SetText(run and (Lode.Ore(floor)[2] .. " seam" .. (run.class and (", " .. Lode.CLASS[run.class][2]) or "")) or "")
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
    for _, u in ipairs(run and Lode.Spells(run.class) or {}) do
        local have = run:Has(u[1])
        if have > 0 and s.ups[n + 1] then
            n = n + 1
            local row = s.ups[n]
            row.key = u[1]
            row.icon:SetTexture(Lode.UpgradeIcon(u[1], run.class))
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

-- Whose board is up: the tab clicked, else the class being played or last played (NewRun saves it), else the first.
function Lode:ScoreClass()
    local c = self.scoreClass or G().class
    return Lode.CLASS[c or ""] and c or Lode.CLASSES[1][1]
end

-- The guild's hiscores for the overlay: the top rows, and ours on the last
-- one if we're further down than that. { rank, rec } each.
function Lode:ScoreRows()
    local board, me = self:Leaderboard(self:ScoreClass()), ns.Sync:Me()
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
    local choosing = state == "choose" and self.picking ~= true
    if state ~= "aim" then self.showScores = nil end
    local picking = self.picking == true -- (over a bomb in the air or the upgrade tiles too: New run works at any time)
    local peek = self.showScores == true and not picking
    local scores = (state == "idle" or state == "over" or peek) and not picking
    o:SetShown(scores or choosing or picking)
    o.start:SetShown(scores or picking)
    local lastClass = G().class
    for _, t in ipairs(o.classes) do
        t:SetShown(picking)
        t.last:SetShown(t.key == lastClass)
    end
    -- the guild's hiscores
    local rows = scores and self:ScoreRows() or {}
    local me = ns.Sync:Me()
    o.scoreTitle:SetShown(scores)
    local shown = self:ScoreClass()
    for _, t in ipairs(o.scoreTabs) do
        t:SetShown(scores)
        t:SetSelected(t.key == shown)
    end
    o.noScores:SetShown(scores and rows[1] == nil)
    o.noScores:SetText(("No %s scores yet. Be the first."):format(Lode.CLASS[shown][2]))
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
            local u = Lode.Spell(run.class, key)
            t.icon:SetTexture(Lode.UpgradeIcon(key, run.class))
            t.name:SetText(u[2])
            t.desc:SetText(u[3])
            t.own:SetText(u[4] > 1 and run:Has(key) > 0 and ("You have %d"):format(run:Has(key)) or "")
        end
    end
    if picking then
        o.title:SetText("Pick a class")
        o.sub:SetText("You get its perk for the whole run, and every upgrade is one of its spells.")
        o.start:SetLabel("Back")
    elseif state == "idle" then
        o.title:SetText("Poggle")
        o.sub:SetText("Aim with your mouse and click to drop a bomb. Every peg it hits gets mined. Land it in the bucket "
            .. "and you get the bomb back. Hit the ore quota before you run out of bombs to go deeper.")
        o.start:SetLabel("Start run")
    elseif choosing then
        o.title:SetText(("Floor %d cleared"):format(run.cleared))
        o.sub:SetText("Pick an upgrade.")
    elseif peek then
        o.title:SetText("Hiscores")
        o.sub:SetText("Deepest floor cleared, then most ore. Each class has its own board.")
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
    self:Tint()
    self:PlaceCart()
    local aiming = run ~= nil and run.state == "aim" and not self.picking
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
