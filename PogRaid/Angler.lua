-- Pog Guild Tools games: Angler, an idle fishing game (Jake, 0.20.0: "let's do
-- the idle game", then "take a deep dive into ... successful idle games. I
-- like the Angler concept, let's flesh it out").
--
-- Your crew catches fish every second, whether the window is open or not and
-- while you're logged off (at half speed, eight hours at most, until tackle
-- makes that better). Fish buy more crew; every 10th, 25th, 50th and 100th of
-- one kind doubles what that kind catches. What the genre's hits have, in
-- our own clothes:
--   * a reason to keep the page open: every few minutes a SCHOOL of fish
--     shows for a few seconds; click it for a frenzy, a haul or a casting spree
--   * TACKLE: one-off upgrades (casting, all crew, the catch while away, schools)
--   * TROPHIES: goals that each add 1% for good
--   * buying one, ten or as many as you can afford
--   * prestige (Jake: "also a type of prestige system"): selling the catch
--     starts the voyage over (fish, crew, tackle) for PEARLS. Every pearl ever
--     earned is +10% for good, and pearls in hand are spent on PERKS that
--     outlast every voyage. Your rank grows with the pearls you've earned.
--
-- Nothing ticks in the background: the state is a number and the time it was
-- last counted to (Angler:Settle), so it costs nothing while the game is shut.
-- The rules know nothing of the screen. Local only: nothing is shared.
local _, ns = ...
local UI = ns.UI

local Angler = {}
ns.Angler = Angler

-- key, name, first one's price, fish a second from each, its picture (a game icon's name)
Angler.CREW = {
    { "rod", "Fishing Rod", 15, 0.2, "INV_Fishingpole_02" },
    { "net", "Cast Net", 120, 1.5, "INV_Misc_Net_01" },
    { "boat", "Rowboat", 1400, 10, "Trade_Fishing" },
    { "trawl", "Trawler", 16000, 70, "INV_Crate_01" },
    { "dock", "Fishery", 200000, 500, "INV_Cask_02" },
    { "rig", "Deep Sea Rig", 3000000, 4000, "Trade_Engineering" },
    { "fleet", "Fishing Fleet", 50000000, 35000, "INV_Misc_Spyglass_02" },
    { "hunter", "Leviathan Hunter", 900000000, 300000, "INV_Spear_06" },
    -- the long game (Jake: "make the game feel long and challenging to complete ... aim for longevity"):
    -- six more, each about fifteen times the price of the last for eight times the catch
    { "sub", "Goblin Submarine", 1.4e10, 2600000, "INV_Gizmo_02" },
    { "murloc", "Murloc Tribe", 2.2e11, 2.2e7, "INV_Misc_Head_Murloc_01" },
    { "tide", "Tidecaller", 3.6e12, 1.9e8, "Spell_Frost_SummonWaterElemental" },
    { "kraken", "Kraken", 6e13, 1.7e9, "Spell_Shadow_Possession" },
    { "storm", "Maelstrom", 1e15, 1.5e10, "Spell_Nature_Cyclone" },
    { "rift", "Abyssal Rift", 1.8e16, 1.4e11, "Spell_Shadow_ShadowWordPain" },
}
Angler.GROWTH = 1.15                    -- each one costs this much more than the last
Angler.MILESTONES = { 10, 25, 50, 100, 150, 200, 250, 300 } -- owning this many of a kind doubles what it catches
Angler.AWAY_AFTER = 60                  -- seconds uncounted before it's "while you were away"
Angler.AWAY_RATE = 0.5                  -- the crew works at half speed without you
Angler.AWAY_CAP = 8 * 3600              -- and for eight hours at most
Angler.CAST_SHARE = 0.05                -- a cast lands this share of a second's catch (1 fish at least)
Angler.PEARL_AT = 1000000               -- a voyage's fish for the first pearl (then 8 times that for two, 27 for three)
Angler.PEARL_BONUS = 0.10
Angler.TROPHY_BONUS = 0.01
Angler.QTYS = { 1, 10, "max" }

-- Tackle: key, name, what it does, price, picture. Bought once a voyage.
-- What each does is read where it matters (Has).
Angler.TACKLE = {
    { "hooks", "Sharp Hooks", "Casts catch 2x.", 100, "INV_Misc_Hook_01" },
    { "charts", "Tide Charts", "Crew catches 25% more.", 10000, "INV_Misc_Map_01" },
    { "barbs", "Barbed Hooks", "Casts catch 2x again.", 5000, "INV_Misc_MonsterClaw_03" },
    { "hold", "Bigger Hold", "Crew keeps fishing for 16 hours while you're offline.", 25000, "INV_Box_01" },
    { "lanterns", "Night Lanterns", "Crew fishes at 75% speed while you're offline.", 50000, "INV_Misc_Lantern_01" },
    { "lure", "Enchanted Lure", "Casts catch 2x. Yes, again.", 250000, "INV_Misc_Orb_03" },
    { "spotter", "Spotter", "Schools show up twice as often.", 500000, "Ability_Hunter_EagleEye" },
    { "sonar", "Sonar", "Crew catches another 25%.", 1000000, "INV_Gizmo_01" },
    { "cold", "Cold Storage", "Crew keeps fishing for a full 24 hours while you're offline.", 2500000, "Spell_Frost_FrostArmor02" },
    { "shift", "Night Shift", "Crew fishes at full speed while you're offline.", 5000000, "Spell_Nature_StarFall" },
    { "chum", "Chum", "Feeding frenzies last twice as long.", 20000000, "Spell_Shadow_BloodBoil" },
    { "shanties", "Sea Shanties", "Crew catches 25% more. Morale is up.", 100000000, "INV_Misc_Horn_01" },
    -- the long game: something to save for past the first evening
    { "nets", "Bigger Nets", "Lucky hauls are twice as big.", 5e9, "INV_Misc_Net_01" },
    { "deep", "Deep Charts", "Crew catches 25% more.", 1e10, "INV_Misc_Map_01" },
    { "golden", "Golden Lure", "Casts catch 2x. One more time.", 1e11, "INV_Misc_Orb_05" },
    { "light", "Lighthouse", "Crew catches 25% more.", 1e13, "INV_Misc_Lantern_01" },
    { "siren", "Siren Song", "Feeding frenzies are twice as strong.", 1e14, "INV_Misc_Horn_02" },
    { "ancient", "Charts of the Ancients", "Crew catches 50% more.", 1e16, "INV_Misc_Book_09" },
}
-- ...and two for every kind of crew, each doubling what that kind catches (Cookie Clicker's building
-- upgrades): "Better" at 40 times the kind's first price, "Master" at 2,000 times. Keys: rod2, rod3, net2...
Angler.MARKS = { { "2", "Better", 40 }, { "3", "Master", 2000 } }
for _, c in ipairs(Angler.CREW) do
    for _, m in ipairs(Angler.MARKS) do
        Angler.TACKLE[#Angler.TACKLE + 1] = { c[1] .. m[1], m[2] .. " " .. c[2], ("Each %s catches twice as much."):format(c[2]), c[3] * m[3], c[5] }
    end
end
Angler.GEAR = {}
for _, t in ipairs(Angler.TACKLE) do Angler.GEAR[t[1]] = t end

-- Schools of fish: one shows every SCHOOL_GAP seconds (somewhere in that
-- range) while the page is open, for SCHOOL_SHOWS seconds.
Angler.SCHOOL_GAP = { 120, 300 }
Angler.SCHOOL_SHOWS = 15
Angler.SCHOOLS = {
    { "frenzy", "Feeding frenzy! 7x fish for %d seconds." },
    { "haul", "Lucky haul! %s fish, just like that." },
    { "spree", "Casting spree! Casts hit 20x for %d seconds." },
}
Angler.FRENZY, Angler.FRENZY_FOR = 7, 30
Angler.SPREE, Angler.SPREE_FOR = 20, 20
Angler.HAUL = 600                       -- a haul is this many seconds of catch (and 25 casts at least)
Angler.Random = math.random             -- (the tests put their own dice here)

-- Perks: bought with pearls, kept for good. key, name, what it does, pearls.
Angler.PERKS = {
    { "start", "Head Start", "Start every voyage with 25 Fishing Rods and 10 Cast Nets.", 2, "INV_Fishingpole_01" },
    { "legs", "Sea Legs", "Start with 3 tackle upgrades, and all tackle costs half.", 5, "INV_Boots_05" },
    { "lookout", "Keen Lookout", "Schools come 50% more often and stay twice as long.", 8, "INV_Misc_Spyglass_03" },
    { "tireless", "Tireless Crew", "Offline, crew fishes 25% faster and for twice as long.", 12, "Ability_Rogue_Sprint" },
    { "twin", "Blood in the Water", "Feeding frenzies are 15x, not 7x.", 15, "Ability_Racial_BloodRage" },
    { "bulk", "Bulk Deals", "Crew costs 25% less.", 20, "INV_Misc_Coin_02" },
    { "lustre", "Pearl Lustre", "Each pearl is worth 15%, not 10%.", 30, "INV_Misc_Gem_Pearl_01" },
    -- the long game: these take many voyages to afford
    { "friends", "Old Friends", "Also start every voyage with 10 Rowboats and 10 Trawlers.", 50, "INV_Misc_Spyglass_02" },
    { "ghooks", "Golden Hooks", "Casts catch 10x.", 100, "INV_Misc_Hook_01" },
    { "room", "Trophy Room", "Trophies are worth 2% each, not 1%.", 250, "INV_Misc_Fish_13" },
    { "wright", "Shipwright", "Each crew costs 13% more than the last, not 15%.", 500, "Trade_Engineering" },
    { "call", "Call of the Deep", "All crew catch twice as much.", 1000, "Spell_Shadow_Possession" },
}
-- What the perks are worth (0.20.0, the day they shipped to Jake: "make sure they're all strong. head start
-- seems a little lack luster"). Each was a few percent; a pearl alone is 10%, so nobody would have bought one.
Angler.START = { rod = 25, net = 10 }           -- Head Start: about five minutes of a fresh voyage
Angler.FRIENDS = { boat = 10, trawl = 10 }      -- Old Friends
Angler.WRIGHT = 1.13                            -- Shipwright's growth
Angler.LEGS = { "hooks", "barbs", "charts" }    -- Sea Legs' tackle
Angler.LEGS_PRICE = 0.5                         -- ...and what tackle then costs
Angler.LOOKOUT_OFTEN = 1.5
Angler.TIRELESS_LONG = 2
Angler.BULK_PRICE = 0.75
Angler.LUSTRE = 0.15
Angler.BLOOD = 15
Angler.PERK = {}
for _, k in ipairs(Angler.PERKS) do Angler.PERK[k[1]] = k end
-- pearls ever earned -> what you're called
Angler.RANKS = { { 0, "Deckhand" }, { 1, "Mate" }, { 10, "Skipper" }, { 50, "Captain" }, { 200, "Admiral" },
    { 1000, "Sea Lord" }, { 10000, "Tide King" } }

local function G()
    ns.db.games = ns.db.games or { best = {} }
    local g = ns.db.games.angler
    if not g then
        g = { fish = 0, total = 0, life = 0, own = {}, pearls = 0, t = ns.Now() }
        ns.db.games.angler = g
    end
    g.tackle, g.trophies, g.perks = g.tackle or {}, g.trophies or {}, g.perks or {}
    g.earned = g.earned or g.pearls -- pearls ever earned (pearls = the ones still in hand)
    g.casts, g.schools, g.voyages = g.casts or 0, g.schools or 0, g.voyages or 0
    return g
end
Angler.Saved = G

-- Trophies: key, name, how it's earned, and the test. Each is +1% for good.
local function life(n) return function(g) return g.life >= n end end
local function owns(n, key)
    return function(g)
        if key then return (g.own[key] or 0) >= n end
        for _, c in ipairs(Angler.CREW) do
            if (g.own[c[1]] or 0) >= n then return true end
        end
        return false
    end
end
Angler.TROPHIES = {
    { "life3", "First Catch", "Catch 1,000 fish.", life(1e3), "INV_Misc_Fish_01" },
    { "life5", "Full Nets", "Catch 100,000 fish.", life(1e5), "INV_Misc_Fish_03" },
    { "life7", "Fishmonger", "Catch 10 million fish.", life(1e7), "INV_Misc_Fish_06" },
    { "life9", "Master Angler", "Catch a billion fish.", life(1e9), "INV_Misc_Fish_08" },
    { "life11", "Lord of the Tides", "Catch 100 billion fish.", life(1e11), "INV_Misc_Fish_13" },
    { "rods10", "Tackle Box", "Own 10 Fishing Rods.", owns(10, "rod"), "INV_Misc_Bag_10" },
    { "any50", "Crewed Up", "Own 50 of the same crew.", owns(50), "INV_Misc_Net_01" },
    { "any100", "Armada", "Own 100 of the same crew.", owns(100), "INV_Misc_Spyglass_02" },
    { "hunter1", "Here Be Monsters", "Own a Leviathan Hunter.", owns(1, "hunter"), "INV_Spear_06" },
    { "cast100", "Sore Arm", "Cast 100 times.", function(g) return g.casts >= 100 end, "INV_Fishingpole_01" },
    { "cast1000", "Old Salt", "Cast 1,000 times.", function(g) return g.casts >= 1000 end, "INV_Fishingpole_02" },
    { "cast10000", "Iron Wrist", "Cast 10,000 times.", function(g) return g.casts >= 10000 end, "INV_Fishingpole_03" },
    { "school1", "Lookout", "Catch a school.", function(g) return g.schools >= 1 end, "Ability_Hunter_EagleEye" },
    { "school25", "Sharp Eyes", "Catch 25 schools.", function(g) return g.schools >= 25 end, "INV_Misc_Fish_09" },
    { "school100", "Never Blinks", "Catch 100 schools.", function(g) return g.schools >= 100 end, "INV_Misc_Fish_11" },
    { "pearl1", "Pearl Diver", "Earn your first pearl.", function(g) return g.earned >= 1 end, "INV_Misc_Gem_Pearl_01" },
    { "pearl10", "String of Pearls", "Earn 10 pearls.", function(g) return g.earned >= 10 end, "INV_Misc_Gem_Pearl_03" },
    { "perk1", "Investor", "Buy a perk.", function(g) return next(g.perks) ~= nil end, "INV_Misc_Coin_01" },
    { "voyage5", "Seasoned", "Sell the catch 5 times.", function(g) return g.voyages >= 5 end, "INV_Misc_Map_01" },
    -- the long game
    { "life13", "Emptied the Sea", "Catch 10 trillion fish.", life(1e13), "INV_Misc_Fish_14" },
    { "life15", "Emptied It Twice", "Catch a quadrillion fish.", life(1e15), "INV_Misc_Fish_10" },
    { "life18", "There Are No More Fish", "Catch a quintillion fish.", life(1e18), "INV_Misc_Fish_12" },
    { "any150", "Standing Room Only", "Own 150 of the same crew.", owns(150), "INV_Crate_01" },
    { "any200", "Too Many Cooks", "Own 200 of the same crew.", owns(200), "INV_Cask_02" },
    { "kraken1", "Release It", "Own a Kraken.", owns(1, "kraken"), "Spell_Shadow_Possession" },
    { "rift1", "Staring Back", "Own an Abyssal Rift.", owns(1, "rift"), "Spell_Shadow_ShadowWordPain" },
    { "cast100000", "Wrist of Legend", "Cast 100,000 times.", function(g) return g.casts >= 100000 end, "INV_Fishingpole_03" },
    { "school500", "Fish Whisperer", "Catch 500 schools.", function(g) return g.schools >= 500 end, "INV_Misc_Fish_07" },
    { "pearl100", "Pearl Hoard", "Earn 100 pearls.", function(g) return g.earned >= 100 end, "INV_Misc_Gem_Pearl_02" },
    { "pearl1000", "Sea Lord's Ransom", "Earn 1,000 pearls.", function(g) return g.earned >= 1000 end, "INV_Misc_Gem_Pearl_04" },
    { "voyage25", "Well Travelled", "Sell the catch 25 times.", function(g) return g.voyages >= 25 end, "INV_Misc_Map_01" },
    { "voyage100", "Never Home", "Sell the catch 100 times.", function(g) return g.voyages >= 100 end, "INV_Misc_Spyglass_03" },
    { "tackleall", "Fully Kitted", "Have every piece of tackle aboard at once.", function(g)
        for _, t in ipairs(Angler.TACKLE) do
            if not g.tackle[t[1]] then return false end
        end
        return true
    end, "INV_Box_01" },
    { "perkall", "Nothing Left to Buy", "Own every perk.", function(g)
        for _, k in ipairs(Angler.PERKS) do
            if not g.perks[k[1]] then return false end
        end
        return true
    end, "INV_Misc_Coin_02" },
}

-- 1234 -> "1,234"; a million and up -> "1.23M".
function Angler.Short(n)
    n = math.floor(n or 0)
    if n < 1000000 then return ns.Lode.util.commas(n) end
    for _, unit in ipairs({ { 1e33, "Dc" }, { 1e30, "No" }, { 1e27, "Oc" }, { 1e24, "Sp" }, { 1e21, "Sx" }, { 1e18, "Qi" }, { 1e15, "Q" }, { 1e12, "T" },
        { 1e9, "B" }, { 1e6, "M" } }) do
        if n >= unit[1] then return ("%.2f%s"):format(n / unit[1], unit[2]) end
    end
end

function Angler:Owned(i) return G().own[Angler.CREW[i][1]] or 0 end
function Angler:Has(key) return G().tackle[key] == true end
function Angler:Perk(key) return G().perks[key] == true end

-- What the `n`th of a kind costs (n = how many are owned before it).
function Angler:Price(i, n)
    local growth = self:Perk("wright") and Angler.WRIGHT or Angler.GROWTH
    return math.floor(Angler.CREW[i][3] * growth ^ n * (self:Perk("bulk") and Angler.BULK_PRICE or 1) + 0.5)
end

function Angler.RankOf(earned)
    local name = Angler.RANKS[1][2]
    for _, r in ipairs(Angler.RANKS) do
        if (earned or 0) >= r[1] then name = r[2] end
    end
    return name
end
function Angler:Rank() return Angler.RankOf(G().earned) end

-- What `n` more of a kind cost, each dearer than the last.
function Angler:Cost(i, n)
    local owned, sum = self:Owned(i), 0
    for k = 0, (n or 1) - 1 do
        sum = sum + self:Price(i, owned + k)
    end
    return sum
end

-- How many of a kind the fish in hand will buy.
function Angler:Affordable(i)
    local fish, owned, n = G().fish, self:Owned(i), 0
    while n < 1000 do
        local cost = self:Price(i, owned + n)
        if cost > fish then break end
        fish, n = fish - cost, n + 1
    end
    return n
end

-- How many times over a kind's catch has doubled.
function Angler.Doubles(owned)
    local n = 0
    for _, at in ipairs(Angler.MILESTONES) do
        if owned >= at then n = n + 1 end
    end
    return n
end

-- The next count of a kind that doubles it, or nil past the last.
function Angler.NextMilestone(owned)
    for _, at in ipairs(Angler.MILESTONES) do
        if owned < at then return at end
    end
end

function Angler:TrophyCount()
    local n = 0
    for _ in pairs(G().trophies) do n = n + 1 end
    return n
end

function Angler:PearlBonus() return self:Perk("lustre") and Angler.LUSTRE or Angler.PEARL_BONUS end
function Angler:FrenzyMult() return (self:Perk("twin") and Angler.BLOOD or Angler.FRENZY) * (self:Has("siren") and 2 or 1) end

-- Everything that multiplies every catch: pearls, trophies, tackle.
function Angler:Bonus()
    local tackle = 1
    for _, key in ipairs({ "charts", "sonar", "shanties", "deep", "light" }) do
        if self:Has(key) then tackle = tackle * 1.25 end
    end
    if self:Has("ancient") then tackle = tackle * 1.5 end
    if self:Perk("call") then tackle = tackle * 2 end
    local trophy = self:Perk("room") and 2 * Angler.TROPHY_BONUS or Angler.TROPHY_BONUS
    return (1 + self:PearlBonus() * G().earned) * (1 + trophy * self:TrophyCount()) * tackle
end

-- Fish a second from one of a kind, from a kind, and from all of them.
function Angler:Each(i)
    local key, marks = Angler.CREW[i][1], 0
    for _, m in ipairs(Angler.MARKS) do
        if self:Has(key .. m[1]) then marks = marks + 1 end
    end
    return Angler.CREW[i][4] * 2 ^ (Angler.Doubles(self:Owned(i)) + marks) * self:Bonus()
end
function Angler:RateOf(i) return self:Owned(i) * self:Each(i) end

function Angler:Rate()
    local sum = 0
    for i = 1, #Angler.CREW do sum = sum + self:RateOf(i) end
    return sum
end

function Angler:AwayRate()
    local rate = self:Has("shift") and 1 or self:Has("lanterns") and 0.75 or Angler.AWAY_RATE
    return math.min(1, rate + (self:Perk("tireless") and 0.25 or 0))
end
function Angler:AwayCap()
    local cap = self:Has("cold") and 24 * 3600 or self:Has("hold") and 16 * 3600 or Angler.AWAY_CAP
    return cap * (self:Perk("tireless") and Angler.TIRELESS_LONG or 1)
end

function Angler:Add(fish)
    local g = G()
    g.fish, g.total, g.life = g.fish + fish, g.total + fish, g.life + fish
end

-- A school's effect still running: { kind, from, till } (this session only).
function Angler:Buff(kind, now)
    local b = self.buff
    if b and b.kind == kind and (now or ns.Now()) < b.till then return b end
end

-- Count the catch up to `now`. Returns what came in, and whether we were away
-- for it (slower, capped).
function Angler:Settle(now)
    local g = G()
    now = now or ns.Now()
    local from = g.t or now
    local gap = now - from
    g.t = now
    if gap <= 0 then return 0, false end
    local away = gap > Angler.AWAY_AFTER
    local seconds = away and math.min(gap, self:AwayCap()) * self:AwayRate() or gap
    -- a frenzy counts for the part of this stretch it covered
    local b = self.buff
    if not away and b and b.kind == "frenzy" then
        local overlap = math.min(now, b.till) - math.max(from, b.from)
        if overlap > 0 then seconds = seconds + overlap * (self:FrenzyMult() - 1) end
    end
    local gain = self:Rate() * seconds
    self:Add(gain)
    return gain, away
end

function Angler:CastValue()
    local v = math.max(1, math.floor(self:Rate() * Angler.CAST_SHARE + 0.5)) * self:Bonus()
    for _, key in ipairs({ "hooks", "barbs", "lure", "golden" }) do
        if self:Has(key) then v = v * 2 end
    end
    if self:Perk("ghooks") then v = v * 10 end
    if self:Buff("spree") then v = v * Angler.SPREE end
    return v
end

function Angler:Cast()
    self:Settle()
    local v = self:CastValue()
    self:Add(v)
    G().casts = G().casts + 1
    return v
end

-- Buy `n` of a kind (1 unless said; "max" = as many as the fish will buy).
function Angler:Buy(i, n)
    if not Angler.CREW[i] then return false end
    self:Settle()
    if n == "max" then n = self:Affordable(i) end
    n = n or 1
    if n < 1 then return false end
    local g, cost = G(), self:Cost(i, n)
    if g.fish < cost then return false end
    g.fish = g.fish - cost
    g.own[Angler.CREW[i][1]] = self:Owned(i) + n
    return n
end

-- What a piece of tackle costs us (half with Sea Legs).
function Angler:TackleCost(key)
    local t = Angler.GEAR[key]
    return t and math.floor(t[4] * (self:Perk("legs") and Angler.LEGS_PRICE or 1) + 0.5)
end

function Angler:BuyTackle(key)
    local t = Angler.GEAR[key]
    if not t or self:Has(key) then return false end
    self:Settle()
    local g = G()
    local cost = self:TackleCost(key)
    if g.fish < cost then return false end
    g.fish = g.fish - cost
    g.tackle[key] = true
    return true
end

-- Pearls a voyage of `total` fish is worth: 1 at a million, 2 at eight, 3 at
-- twenty-seven (the cube root). A square root gave a three-hour first voyage
-- some 500 pearls, the whole prestige ladder in one go (the pacing script).
function Angler.Pearls(total)
    return math.floor((math.max(0, total or 0) / Angler.PEARL_AT) ^ (1 / 3) + 1e-9)
end

-- The fish a voyage needs for its `n`th pearl.
function Angler.PearlAt(n) return Angler.PEARL_AT * n ^ 3 end

function Angler:PearlsNow() return Angler.Pearls(G().total) end

-- Sell the catch: the voyage starts over (fish, crew, tackle); pearls and
-- trophies stay for good.
function Angler:Sell()
    self:Settle()
    local g = G()
    local pearls = Angler.Pearls(g.total)
    if pearls < 1 then return false end
    g.pearls, g.earned = g.pearls + pearls, g.earned + pearls
    g.fish, g.total, g.own, g.tackle = 0, 0, {}, {}
    g.voyages = g.voyages + 1
    self.buff = nil
    self:Outfit()
    return pearls
end

-- What a new voyage starts with, from the perks.
function Angler:Outfit()
    local g = G()
    if self:Perk("start") then
        for key, n in pairs(Angler.START) do g.own[key] = math.max(g.own[key] or 0, n) end
    end
    if self:Perk("friends") then
        for key, n in pairs(Angler.FRIENDS) do g.own[key] = math.max(g.own[key] or 0, n) end
    end
    if self:Perk("legs") then
        for _, key in ipairs(Angler.LEGS) do g.tackle[key] = true end
    end
end

-- A perk, for pearls in hand. It's ours for good (and works from now on).
function Angler:BuyPerk(key)
    local k = Angler.PERK[key]
    local g = G()
    if not k or g.perks[key] or g.pearls < k[4] then return false end
    self:Settle()
    g.pearls = g.pearls - k[4]
    g.perks[key] = true
    self:Outfit()
    return true
end

-- Trophies newly earned: marked, and returned (their names).
function Angler:Award()
    local g, new = G(), {}
    for _, t in ipairs(Angler.TROPHIES) do
        if not g.trophies[t[1]] and t[4](g) then
            g.trophies[t[1]] = true
            new[#new + 1] = t[2]
        end
    end
    return new
end

-- Schools. When the next one shows is drawn once and kept; it shows only
-- while someone is looking (Angler:Watch, from the page's update).
function Angler:NextSchoolIn()
    local lo, hi = Angler.SCHOOL_GAP[1], Angler.SCHOOL_GAP[2]
    local wait = lo + (hi - lo) * Angler.Random()
    if self:Perk("lookout") then wait = wait / Angler.LOOKOUT_OFTEN end
    return self:Has("spotter") and wait / 2 or wait
end

function Angler:Watch(now)
    now = now or ns.Now()
    if self.school then
        if now >= self.school.till then
            self.school = nil
            self.schoolAt = now + self:NextSchoolIn()
        end
        return self.school
    end
    if not self.schoolAt then self.schoolAt = now + self:NextSchoolIn() end
    -- (nothing to multiply before there's a crew)
    if now >= self.schoolAt and self:Rate() > 0 then
        local kind = Angler.SCHOOLS[math.min(#Angler.SCHOOLS, math.floor(Angler.Random() * #Angler.SCHOOLS) + 1)][1]
        self.school = { kind = kind, till = now + Angler.SCHOOL_SHOWS * (self:Perk("lookout") and 2 or 1) }
    end
    return self.school
end

-- The school is clicked: what it gave, in words.
function Angler:CatchSchool(now)
    now = now or ns.Now()
    local s = self.school
    if not s or now >= s.till then return nil end
    self:Settle(now)
    self.school = nil
    self.schoolAt = now + self:NextSchoolIn()
    G().schools = G().schools + 1
    if s.kind == "frenzy" then
        local secs = Angler.FRENZY_FOR * (self:Has("chum") and 2 or 1)
        self.buff = { kind = "frenzy", from = now, till = now + secs }
        return (Angler.SCHOOLS[1][2]:gsub("7x", self:FrenzyMult() .. "x")):format(secs)
    elseif s.kind == "haul" then
        local gain = math.max(self:Rate() * Angler.HAUL, self:CastValue() * 25) * (self:Has("nets") and 2 or 1)
        self:Add(gain)
        return Angler.SCHOOLS[2][2]:format(Angler.Short(gain))
    end
    self.buff = { kind = "spree", from = now, till = now + Angler.SPREE_FOR }
    return Angler.SCHOOLS[3][2]:format(Angler.SPREE_FOR)
end

------------------------------------------------------------------------
-- The guild's anglers (Jake: "also a leaderboard"): one record a player,
-- the fish they've caught in all (never reset) and the pearls they've earned.
-- A new kind of record: addons older than 0.20.0 can't file it and ask for
-- it again at every check-in until they update (as with every board so far).
------------------------------------------------------------------------
Angler.share = true
Angler.PUBLISH_EVERY = 900      -- seconds between our own updates (the number climbs every second; the guild needn't hear each one)
Angler.BOARD_MIN = 1000         -- fish before you're on the board
Angler.BOARD_MAX = 1e60         -- (far past anything the game reaches; the last digits of a big one are rounded on the way)

ns.Sync:Register({
    name = "angler", code = "v", order = 4,
    fields = { "life", "earned" },
    numeric = { life = true, earned = true },
    valid = function(rec)
        return rec.by == rec.author and rec.id == rec.author and rec.life ~= nil and rec.life >= 0 and rec.life < Angler.BOARD_MAX
            and rec.life == math.floor(rec.life) and rec.earned ~= nil and rec.earned >= 0 and rec.earned < 1e6 and rec.earned == math.floor(rec.earned)
    end,
    onChange = function() Angler:Refresh() end,
})

-- Tell the guild where we stand: when it has changed, and not more often
-- than every quarter of an hour unless `now` (a voyage just sold).
function Angler:Publish(now)
    if not Angler.share or not ns.Sync:GuildName() then return false end
    local g, me = G(), ns.Sync:Me()
    -- (twelve figures of it: a big number goes over the wire as "1.23456789012e+20", and what we keep must
    --  be exactly what the others will read back, or our record and theirs would never agree)
    local life = tonumber(("%.12g"):format(math.min(math.floor(g.life), Angler.BOARD_MAX / 10)))
    if life < Angler.BOARD_MIN then return false end
    local cur = (ns.Sync:Store("angler") or {})[me]
    if cur and not cur.deleted then
        if cur.life == life and cur.earned == g.earned then return false end
        if not now and ns.Now() - (cur.t or 0) < Angler.PUBLISH_EVERY then return false end
    end
    ns.Sync:Write("angler", { id = me, author = me, t = ns.Now(), life = life, earned = g.earned })
    return true
end

-- Most fish ever caught first.
function Angler:Leaderboard()
    local out = {}
    for _, rec in pairs(ns.Sync:Store("angler") or {}) do
        if not rec.deleted then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b)
        if a.life ~= b.life then return a.life > b.life end
        return a.author < b.author
    end)
    return out
end

------------------------------------------------------------------------
-- UI: a list on the left (crew, tackle or trophies), the catch beside it
------------------------------------------------------------------------
local PAD, GAP = 12, 8
local W, H = 560, 566
local SIDE_X = PAD + W + GAP
local SIDE_W = 902 - PAD - SIDE_X
local HEAD_H, ROW_H, ROW_GAP, ROWS = 34, 80, 8, 6
local ICON, BUY_W, BUY_H = 44, 118, 26
local TAB_W, TAB_H, TAB_GAP = 78, 22, 6
local POP_W, POP_HEAD, POP_ROWS, POP_ROW_H, POP_ROW_GAP, POP_LIST = 220, 64, 5, 26, 3, 94 -- the pop-out
local POP_TAB_Y, POP_TAB_W, POP_TAB_H, POP_TAB_GAP = 70, 50, 18, 6
local POP_QTY_W = POP_W - 16 - 3 * (POP_TAB_W + POP_TAB_GAP) -- x1 / x10 / max, at the end of the tab row -- Crew / Tackle / Perks over its shop
Angler.POP_TABS = { { "crew", "Crew" }, { "tackle", "Tackle" }, { "perks", "Perks" } }
local POP_CAST, POP_MINI, POP_BUY_W, POP_TEXT_X = 48, 16, 66, 66 -- Cast is a square fishing icon at the left, the count beside it
local POP_EDGE = 1 -- the frame round Cast
Angler.CAST_EDGE = { 0.80, 0.66, 0.30 } -- soft gold under the mouse; a muted bronze (60% of it) at rest
local POP_FLOATS, POP_FLOAT_LIFE, POP_FLOAT_RISE, POP_PRESS = 6, 0.8, 30, 0.14 -- the "+12"s off a cast; how long the icon stays squashed
local GOLD = { 1.00, 0.82, 0.20 }
local DIM = { 0.6, 0.6, 0.65 }
local GREEN = { 0.45, 1, 0.45 }
Angler.TABS = { { "crew", "Crew" }, { "tackle", "Tackle" }, { "perks", "Perks" }, { "trophies", "Trophies" }, { "guild", "Guild" } }
Angler.layout = { W = W, H = H, SIDE_X = SIDE_X, SIDE_W = SIDE_W, ROW_H = ROW_H, ROW_GAP = ROW_GAP, HEAD_H = HEAD_H, BUY_W = BUY_W,
    ROWS = ROWS, TAB_W = TAB_W, TAB_GAP = TAB_GAP, POP_W = POP_W, POP_LIST = POP_LIST, POP_ROWS = POP_ROWS,
    POP_ROW_H = POP_ROW_H, POP_ROW_GAP = POP_ROW_GAP, POP_HEAD = POP_HEAD, POP_TAB_Y = POP_TAB_Y, POP_MINI = POP_MINI,
    POP_TAB_W = POP_TAB_W, POP_TAB_GAP = POP_TAB_GAP, POP_QTY_W = POP_QTY_W, POP_CAST = POP_CAST, POP_TEXT_X = POP_TEXT_X, POP_FLOATS = POP_FLOATS,
    POP_FLOAT_LIFE = POP_FLOAT_LIFE, POP_PRESS = POP_PRESS, POP_EDGE = POP_EDGE }

local function per(n) return n < 10 and ("%.1f"):format(n) or Angler.Short(n) end

function Angler:Build(view, top)
    self.view = view
    self.tab, self.qty, self.offset = "crew", self.qty or 1, 0
    local crew = CreateFrame("Frame", nil, view)
    crew:SetPoint("TOPLEFT", PAD, -top)
    crew:SetSize(W, H)
    UI.Card(crew)
    -- the catch is counted on once a second while the page is up
    crew:SetScript("OnUpdate", function(_, elapsed) self:Update(elapsed) end)
    crew:EnableMouseWheel(true)
    crew:SetScript("OnMouseWheel", function(_, delta)
        self.offset = self.offset - delta
        self:Refresh()
    end)
    self.crew = crew
    -- Crew / Tackle / Trophies, and how many to buy at a time
    self.tabs = {}
    for i, t in ipairs(Angler.TABS) do
        local b = UI.Button(crew, t[2], TAB_W, TAB_H, function()
            self.tab, self.offset = t[1], 0
            self:Refresh()
        end)
        b:SetPoint("LEFT", crew, "TOPLEFT", 12 + (i - 1) * (TAB_W + TAB_GAP), -UI.HeadMid(HEAD_H))
        b.key = t[1]
        self.tabs[i] = b
    end
    self.qtyBtn = UI.Button(crew, "Buy 1", TAB_W, TAB_H, function()
        self:NextQty()
        self:Refresh()
    end)
    self.qtyBtn:SetPoint("RIGHT", crew, "TOPRIGHT", -12, -UI.HeadMid(HEAD_H))
    self.summary = UI.Text(crew, 11)
    self.summary:SetPoint("RIGHT", crew, "TOPRIGHT", -12, -UI.HeadMid(HEAD_H))
    self.summary:SetTextColor(DIM[1], DIM[2], DIM[3])
    self.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, crew)
        row:SetPoint("TOPLEFT", 10, -(HEAD_H + (i - 1) * (ROW_H + ROW_GAP)))
        row:SetSize(W - 20, ROW_H)
        UI.Card(row, { 0.05, 0.05, 0.06, 1 })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("LEFT", 12, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.name = UI.Text(row, 14)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, -1)
        row.owned = UI.Text(row, 12)
        row.owned:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.rate = UI.Text(row, 12)
        row.rate:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -6)
        row.rate:SetWidth(W - 20 - ICON - BUY_W - 60)
        row.rate:SetJustifyH("LEFT")
        -- (a long line wraps onto a second: Jake's screenshot had two perks cut off with "...")
        row.rate:SetWordWrap(true)
        if row.rate.SetMaxLines then row.rate:SetMaxLines(2) end
        row.rate:SetJustifyV("TOP")
        row.rate:SetTextColor(DIM[1], DIM[2], DIM[3])
        row.next = UI.Text(row, 11)
        row.next:SetPoint("TOPLEFT", row.rate, "BOTTOMLEFT", 0, -4)
        row.next:SetTextColor(DIM[1], DIM[2], DIM[3])
        row.buy = UI.Button(row, "", BUY_W, BUY_H, function() self:RowClick(row) end)
        row.buy:SetPoint("RIGHT", -12, 0)
        row.tag = UI.Text(row, 12)
        row.tag:SetPoint("RIGHT", -16, 0)
        row.tag:SetJustifyH("RIGHT")
        self.rows[i] = row
    end
    self.hint = UI.ScrollHint(crew, HEAD_H, 4)
    self.empty = UI.Text(crew, 12)
    self.empty:SetPoint("TOP", 0, -(HEAD_H + 40))
    self.empty:SetTextColor(DIM[1], DIM[2], DIM[3])
    self.empty:SetText(("Nobody's on the board yet. Catch %s fish to get on it."):format(Angler.Short(Angler.BOARD_MIN)))
    self.empty:Hide()

    local s = CreateFrame("Frame", nil, view)
    s:SetPoint("TOPLEFT", SIDE_X, -top)
    s:SetSize(SIDE_W, H)
    UI.Card(s)
    s.title = UI.SectionTitle(s, "Angler")
    s.title:SetPoint("LEFT", s, "TOPLEFT", 12, -UI.HeadMid(HEAD_H))
    s.rank = UI.Text(s, 11)
    s.rank:SetPoint("LEFT", s.title, "RIGHT", 10, 0)
    s.rank:SetTextColor(DIM[1], DIM[2], DIM[3])
    -- a small window of its own that stays up with this one shut
    s.pop = UI.Button(s, "Pop out", 70, TAB_H, function() self:TogglePop() end)
    s.pop:SetPoint("RIGHT", s, "TOPRIGHT", -12, -UI.HeadMid(HEAD_H))
    s.fish = UI.Text(s, 30)
    s.fish:SetPoint("TOP", 0, -(HEAD_H + 18))
    s.fish:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    s.fishLabel = UI.Text(s, 11)
    s.fishLabel:SetPoint("TOP", s.fish, "BOTTOM", 0, -4)
    s.fishLabel:SetTextColor(DIM[1], DIM[2], DIM[3])
    s.fishLabel:SetText("fish")
    s.rate = UI.Text(s, 13)
    s.rate:SetPoint("TOP", s.fishLabel, "BOTTOM", 0, -12)
    s.cast = UI.Button(s, "Cast", SIDE_W - 48, 44, function()
        local v = self:Cast()
        ns.Sound("IG_BACKPACK_COIN_SELECT")
        self.note = "+" .. Angler.Short(v)
        self:Refresh()
    end)
    s.cast:SetPrimary(true)
    s.cast:SetPoint("TOP", s.rate, "BOTTOM", 0, -18)
    -- a school of fish: here for a few seconds, every few minutes
    s.school = UI.Button(s, "School of fish! Grab it", SIDE_W - 48, 30, function()
        local what = self:CatchSchool()
        if what then
            ns.Sound("IG_QUEST_LIST_COMPLETE")
            self.note = what
            self:Refresh()
        end
    end)
    s.school:SetPoint("TOP", s.cast, "BOTTOM", 0, -10)
    s.school.label:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    s.school:Hide()
    s.buff = UI.Text(s, 12)
    s.buff:SetPoint("TOP", s.cast, "BOTTOM", 0, -18)
    s.buff:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    s.note = UI.Text(s, 12)
    s.note:SetPoint("TOP", s.cast, "BOTTOM", 0, -52)
    s.note:SetWidth(SIDE_W - 24)
    s.note:SetJustifyH("CENTER")
    s.note:SetWordWrap(true)
    s.note:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    -- pearls, along the foot
    s.rule = s:CreateTexture(nil, "ARTWORK")
    s.rule:SetPoint("BOTTOMLEFT", 12, 150)
    s.rule:SetPoint("BOTTOMRIGHT", -12, 150)
    s.rule:SetHeight(1)
    UI.Line(s.rule)
    s.pearlTitle = UI.SectionTitle(s, "Pearls", 12)
    s.pearlTitle:SetPoint("BOTTOMLEFT", 12, 124)
    s.pearls = UI.Text(s, 12)
    s.pearls:SetPoint("BOTTOMRIGHT", -12, 124)
    s.pearls:SetJustifyH("RIGHT")
    s.pearlHint = UI.Text(s, 11)
    s.pearlHint:SetPoint("BOTTOMLEFT", 12, 62)
    s.pearlHint:SetPoint("BOTTOMRIGHT", -12, 62)
    s.pearlHint:SetHeight(52)
    s.pearlHint:SetJustifyH("LEFT")
    s.pearlHint:SetJustifyV("TOP")
    s.pearlHint:SetWordWrap(true)
    s.pearlHint:SetTextColor(DIM[1], DIM[2], DIM[3])
    -- (it asks "Sure?" first: selling empties the boat)
    s.sell = UI.Button(s, "Sell the catch", SIDE_W - 24, 26, function(btn)
        UI.ConfirmClick(btn, function()
            local pearls = self:Sell()
            if pearls then
                self:Publish(true)
                ns.Sound("IG_QUEST_LIST_COMPLETE")
                self.note = ("Sold for %d pearl%s. Back out you go."):format(pearls, pearls == 1 and "" or "s")
                self:Refresh()
            end
        end)
    end)
    s.sell:SetPoint("BOTTOM", 0, 12)
    self.side = s
end

-- One, ten, as many as you can afford, and round again.
function Angler:NextQty()
    local at = 1
    for i, q in ipairs(Angler.QTYS) do if q == (self.qty or 1) then at = i end end
    self.qty = Angler.QTYS[at % #Angler.QTYS + 1]
    return self.qty
end

-- A row's button: buy crew (one, ten or the lot) or a piece of tackle.
function Angler:RowClick(row)
    local ok
    if self.tab == "crew" and row.index then
        ok = self:Buy(row.index, self.qty)
    elseif self.tab == "tackle" and row.key then
        ok = self:BuyTackle(row.key)
    elseif self.tab == "perks" and row.key then
        ok = self:BuyPerk(row.key)
    end
    if ok then
        ns.Sound("IG_BACKPACK_COIN_SELECT")
        self.note = nil
        self:Refresh()
    end
end

-- Once a second while the page or the pop-out is up.
function Angler:Update(elapsed)
    self.wait = (self.wait or 0) + (elapsed or 0)
    if self.wait < 1 then return end
    self.wait = 0
    local had = self.school
    self:Watch()
    -- a school is worth a sound: the pop-out is there to be half watched
    if self.school and self.school ~= had then ns.Sound("TELL_MESSAGE") end
    self:Publish()
    self:Refresh()
end

------------------------------------------------------------------------
-- The pop-out (Jake: "a pop out menu that we can click to get fish without
-- the addon open, maybe with a small, scrollable menu to buy stuff")
------------------------------------------------------------------------
-- What its shop sells, a tab at a time (Jake: "add the tabs for crew, tackle, and perks"): the crew;
-- the tackle not aboard yet, cheapest first; the perks.
function Angler:PopItems(tab)
    tab = tab or (self.pop and self.pop.tab) or "crew"
    local g, out = G(), {}
    if tab == "tackle" then
        local left = {}
        for _, t in ipairs(Angler.TACKLE) do
            if not g.tackle[t[1]] then left[#left + 1] = t end
        end
        table.sort(left, function(a, b) return a[4] < b[4] end)
        for _, t in ipairs(left) do out[#out + 1] = { tackle = t } end
    elseif tab == "perks" then
        for _, k in ipairs(Angler.PERKS) do out[#out + 1] = { perk = k } end
    else
        for i in ipairs(Angler.CREW) do out[#out + 1] = { crew = i } end
    end
    return out
end

-- The pop-out, second go (Jake: "it looks clunky ... as clean and satisfying as possible ... smooth, polished
-- and dopamine inducing"). No title bar and no stone frame: a slim dark card, the Cast icon, the count beside
-- it, and three small controls in the corner that stay faint until the mouse is over the card. What makes a
-- clicker feel good is that every click answers: the icon dips and flashes and a "+12" floats up off it
-- (Angler:PopFrame, every frame).
local function mini(parent, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(POP_MINI, POP_MINI)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.glow = b:CreateTexture(nil, "HIGHLIGHT")
    b.glow:SetAllPoints()
    b.glow:SetColorTexture(1, 1, 1, 0.25)
    b.tip = tip
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(type(self.tip) == "function" and self.tip() or self.tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end
-- (the red X and arrow are this client's own, seen in Jake's screenshots; the files are the classic ones)
local function art(tex, atlas, file)
    if UI.HasAtlas and UI.HasAtlas(atlas) then tex:SetAtlas(atlas) else tex:SetTexture(file) end
end
Angler.SHOP_ART = { open = "Interface\\Buttons\\UI-MinusButton-Up", shut = "Interface\\Buttons\\UI-PlusButton-Up" }

function Angler:BuildPop()
    local f = CreateFrame("Frame", "PogRaidAnglerPop", UIParent)
    f:SetSize(POP_W, Angler.PopHeight(true))
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    UI.Panel(f, { 0.05, 0.05, 0.07, 0.94 })
    UI.Window(f, "tooltip")
    f:Hide()
    self.pop = f
    -- the whole card drags
    UI.MakeMovable(f, f, function() UI.SavePosition(f, "anglerPop") end)
    -- the corner: shop, maximize, shut
    f.close = mini(f, "Close", function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -6, -6)
    art(f.close.tex, UI.CLOSE_ATLAS.Up, "Interface\\Buttons\\UI-StopButton")
    f.big = mini(f, "Open the full Angler page", function() self:Maximize() end)
    f.big:SetPoint("RIGHT", f.close, "LEFT", -3, 0)
    art(f.big.tex, Angler.MAX_ATLAS.Up, Angler.MAX_FILE .. "Up")
    f.shop = mini(f, function() return self:ShopOpen() and "Hide the shop" or "Open the shop" end, function()
        ns.db.games.anglerShopShut = not ns.db.games.anglerShopShut or nil
        self:FitPop()
        self:Refresh()
    end)
    f.shop:SetPoint("RIGHT", f.big, "LEFT", -3, 0)
    f.controls = { f.shop, f.big, f.close }
    -- Cast: a fishing icon that says so. It dips and flashes when clicked.
    local cast = CreateFrame("Button", nil, f)
    cast:SetSize(POP_CAST, POP_CAST)
    cast:SetPoint("TOPLEFT", 8, -8)
    cast.icon = cast:CreateTexture(nil, "ARTWORK")
    cast.icon:SetAllPoints()
    cast.icon:SetTexture(Angler.CAST_ICON)
    cast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- "Cast", small and quiet along the bottom (Jake had it taken off with its dark strip, then asked for "a
    -- very subtle and clean" one back): soft white, outlined so it needs no strip behind it
    cast.label = UI.Text(cast, 10)
    cast.label:SetFont(UI.FONT, 10, "OUTLINE")
    cast.label:SetPoint("BOTTOM", 0, 3)
    cast.label:SetText("Cast")
    cast.label:SetTextColor(1, 1, 1, 0.85)
    cast.label:SetShadowOffset(0, 0)
    cast.flash = cast:CreateTexture(nil, "OVERLAY")
    cast.flash:SetAllPoints(cast.icon)
    cast.flash:SetColorTexture(1, 1, 1, 1)
    if cast.flash.SetBlendMode then cast.flash:SetBlendMode("ADD") end
    cast.flash:SetAlpha(0)
    cast.glow = cast:CreateTexture(nil, "HIGHLIGHT")
    cast.glow:SetAllPoints()
    cast.glow:SetColorTexture(1, 1, 1, 0.12)
    -- no word on it (Jake: "take away the cast text ... a stronger border to indicate its a button"; then, of
    -- the solid bright gold one two pixels thick, "lose the bright yellow and make it more subtle"): a thin
    -- bronze line with a dark one inside it, warming to soft gold under the mouse
    cast.edges = {}
    local function edge(a, b, horizontal, inset, color)
        local e = cast:CreateTexture(nil, "OVERLAY", nil, inset > 0 and 1 or 2)
        e:SetColorTexture(color[1], color[2], color[3], color[4])
        e:SetPoint(a, a:find("LEFT") and inset or -inset, a:find("TOP") and -inset or inset)
        e:SetPoint(b, b:find("LEFT") and inset or -inset, b:find("TOP") and -inset or inset)
        if horizontal then e:SetHeight(inset > 0 and 1 or POP_EDGE) else e:SetWidth(inset > 0 and 1 or POP_EDGE) end
        return e
    end
    for _, d in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        edge(d[1], d[2], d[3], POP_EDGE, { 0, 0, 0, 0.8 })
        cast.edges[#cast.edges + 1] = edge(d[1], d[2], d[3], 0, { Angler.CAST_EDGE[1], Angler.CAST_EDGE[2], Angler.CAST_EDGE[3], 1 })
    end
    local function lit(on)
        local k = on and 1 or 0.6
        for _, e in ipairs(cast.edges) do e:SetVertexColor(k, k, k) end
    end
    lit(false)
    -- (no tooltip: it says Cast on it; Jake)
    cast:SetScript("OnEnter", function() lit(true) end)
    cast:SetScript("OnLeave", function() lit(false) end)
    cast:SetScript("OnClick", function()
        local v = self:Cast()
        ns.Sound("IG_BACKPACK_COIN_SELECT")
        self:PopPress(v)
        self:Refresh()
    end)
    f.cast = cast
    f.press = 0
    -- "+12" off the icon, a few at once
    -- (on a layer of their own ABOVE the Cast button: text on the card itself is drawn under the button, a
    --  child frame, so the first ones went behind the icon; Jake's screenshot. Outlined, to read on any picture.)
    f.floatLayer = CreateFrame("Frame", nil, f)
    f.floatLayer:SetAllPoints()
    f.floatLayer:SetFrameLevel((cast:GetFrameLevel() or 0) + 5)
    f.floats = {}
    for i = 1, POP_FLOATS do
        local fl = UI.Text(f.floatLayer, 15)
        fl:SetFont(UI.FONT, 15, "OUTLINE")
        fl:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        fl:Hide()
        f.floats[i] = fl
    end
    -- the count, and what it's growing by
    f.fish = UI.Text(f, 20)
    f.fish:SetPoint("TOPLEFT", POP_TEXT_X, -9)
    f.fish:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.rate = UI.Text(f, 11)
    f.rate:SetPoint("TOPLEFT", POP_TEXT_X + 1, -33)
    f.rate:SetTextColor(DIM[1], DIM[2], DIM[3])
    f.buff = UI.Text(f, 11)
    f.buff:SetPoint("TOPLEFT", POP_TEXT_X + 1, -46)
    f.buff:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    -- a school: over the rate while it lasts, breathing so it catches the eye
    f.school = UI.Button(f, "School! Grab it", POP_W - POP_TEXT_X - 8, 24, function()
        local what = self:CatchSchool()
        if what then
            ns.Sound("IG_QUEST_LIST_COMPLETE")
            self.note = what
            self:Refresh()
        end
    end)
    f.school:SetPoint("TOPLEFT", POP_TEXT_X, -32)
    f.school.label:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    f.school:Hide()
    -- the shop, under a hairline
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetPoint("TOPLEFT", 8, -POP_HEAD)
    f.rule:SetPoint("TOPRIGHT", -8, -POP_HEAD)
    f.rule:SetHeight(1)
    f.rule:SetColorTexture(1, 1, 1, 0.08)
    f.tab, f.tabs = "crew", {}
    for i, t in ipairs(Angler.POP_TABS) do
        local b = UI.Button(f, t[2], POP_TAB_W, POP_TAB_H, function()
            f.tab, f.offset = t[1], 0
            self:RefreshPop()
        end)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * (POP_TAB_W + POP_TAB_GAP), -POP_TAB_Y)
        b.key = t[1]
        if UI.Unred then UI.Unred(b) end
        f.tabs[i] = b
    end
    -- how many crew a click buys: one, ten or all you can afford (Jake, the day 0.20.0 went out: "we might
    -- need to implement a buy 10 button"; the page had one, the pop-out bought one at a time). It's the
    -- page's setting too: change it in either.
    f.qty = UI.Button(f, "x1", POP_QTY_W, POP_TAB_H, function()
        self:NextQty()
        self:Refresh()
    end)
    f.qty:SetPoint("TOPRIGHT", -8, -POP_TAB_Y)
    f.empty = UI.Text(f, 11)
    f.empty:SetPoint("TOP", 0, -(POP_LIST + 10))
    f.empty:SetTextColor(DIM[1], DIM[2], DIM[3])
    f.empty:SetText("All the tackle is aboard.")
    f.empty:Hide()
    f.rows = {}
    for i = 1, POP_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 8, -(POP_LIST + (i - 1) * (POP_ROW_H + POP_ROW_GAP)))
        row:SetSize(POP_W - 16, POP_ROW_H)
        UI.Card(row, { 0.05, 0.05, 0.06, 1 })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 5, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        -- how many you have: a number on the icon, as a stack of items has (beside the name it was cut off
        -- for the longer crew, "Deep Sea Rig x..."; Jake's screenshot)
        row.count = UI.Text(row, 10)
        row.count:SetFont(UI.FONT, 10, "OUTLINE")
        row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 3, -2)
        row.count:SetJustifyH("RIGHT")
        row.name = UI.Text(row, 11)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.name:SetWidth(POP_W - 16 - 5 - 20 - 7 - POP_BUY_W - 5 - 4)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.buy = UI.Button(row, "", POP_BUY_W, 20, function()
            local it = row.it
            local ok = it and (it.crew and self:Buy(it.crew, self.qty or 1) or it.tackle and self:BuyTackle(it.tackle[1]) or it.perk and self:BuyPerk(it.perk[1]))
            if ok then
                ns.Sound("IG_BACKPACK_COIN_SELECT")
                self:Refresh()
            end
        end)
        row.buy:SetPoint("RIGHT", -5, 0)
        row.tag = UI.Text(row, 11)
        row.tag:SetPoint("RIGHT", -10, 0)
        row.tag:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(r)
            if not r.it or not GameTooltip then return end
            GameTooltip:SetOwner(r, "ANCHOR_LEFT")
            if r.it.crew then
                GameTooltip:AddLine(Angler.CREW[r.it.crew][2], 1, 1, 1)
                GameTooltip:AddLine(("%s fish/sec each"):format(per(self:Each(r.it.crew))), nil, nil, nil, true)
            else
                local what = r.it.tackle or r.it.perk
                GameTooltip:AddLine(what[2], 1, 1, 1)
                GameTooltip:AddLine(what[3], nil, nil, nil, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = row
    end
    f.offset = 0
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        f.offset = f.offset - delta
        self:RefreshPop()
    end)
    f:SetScript("OnUpdate", function(_, elapsed)
        -- (the page keeps the time itself while it is up)
        if not (self.crew and self.crew:IsVisible()) then self:Update(elapsed) end
        self:PopFrame(elapsed or 0)
    end)
end

-- A cast from the pop-out: the icon dips, and "+v" floats up off it.
function Angler:PopPress(v)
    local f = self.pop
    f.press = 1
    local fl
    for _, x in ipairs(f.floats) do
        if not x:IsShown() then fl = x break end
    end
    -- (all six in the air: the oldest starts again)
    if not fl then
        for _, x in ipairs(f.floats) do
            if not fl or x.t > fl.t then fl = x end
        end
    end
    fl.t, fl.dx = 0, (Angler.Random() - 0.5) * 24
    fl:SetText("+" .. Angler.Short(v))
    fl:SetAlpha(1)
    fl:ClearAllPoints()
    fl:SetPoint("BOTTOM", f.cast, "TOP", fl.dx, -16)
    fl:Show()
end

-- Every frame the pop-out is up: the motion.
function Angler:PopFrame(elapsed)
    local f = self.pop
    if not f or not f:IsShown() then return end
    f.clock = (f.clock or 0) + elapsed
    -- (the count steps once a second, as the page's does. It ran up every frame here for a day: the last
    --  digits were a blur. Jake: "the decimal on the popout ends up going way too fast. looks better in the
    --  non popout menu")
    -- the icon springs back
    if f.press > 0 then
        f.press = math.max(0, f.press - elapsed / POP_PRESS)
        local inset = 5 * f.press
        f.cast.icon:ClearAllPoints()
        f.cast.icon:SetPoint("TOPLEFT", inset, -inset)
        f.cast.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        f.cast.flash:SetAlpha(0.45 * f.press)
    end
    for _, fl in ipairs(f.floats) do
        if fl:IsShown() then
            fl.t = fl.t + elapsed
            local k = fl.t / POP_FLOAT_LIFE
            if k >= 1 then
                fl:Hide()
            else
                fl:ClearAllPoints()
                fl:SetPoint("BOTTOM", f.cast, "TOP", fl.dx, -16 + POP_FLOAT_RISE * k)
                fl:SetAlpha(1 - k * k)
            end
        end
    end
    -- a school breathes; so does the shop button when there's something you can afford behind it
    local breath = 0.5 + 0.5 * math.sin(f.clock * 6)
    if f.school:IsShown() then f.school:SetAlpha(0.7 + 0.3 * breath) end
    -- the corner controls come up when the mouse is over the card
    local over = f.IsMouseOver and f:IsMouseOver() == true
    f.reveal = math.max(0, math.min(1, (f.reveal or 0) + (over and 1 or -1) * elapsed / 0.15))
    for _, b in ipairs(f.controls) do b:SetAlpha(0.35 + 0.65 * f.reveal) end
    if f.canBuy and not self:ShopOpen() then
        f.shop:SetAlpha(math.max(f.shop:GetAlpha(), 0.6 + 0.4 * breath))
        f.shop.tex:SetVertexColor(1, 0.82, 0.2)
    else
        f.shop.tex:SetVertexColor(1, 1, 1)
    end
end

Angler.CAST_ICON = "Interface\\Icons\\Trade_Fishing"
-- How tall the pop-out is with its shop open or folded away.
function Angler.PopHeight(open)
    return open and (POP_LIST + POP_ROWS * (POP_ROW_H + POP_ROW_GAP) + 5) or POP_HEAD
end
function Angler:ShopOpen() return not (ns.db.games and ns.db.games.anglerShopShut) end

-- Size the pop-out to its shop. Its top-left corner stays where it is (it is
-- placed by its centre, which would move the card under the mouse).
function Angler:FitPop()
    local f = self.pop
    if not f then return end
    local h = Angler.PopHeight(self:ShopOpen())
    local left, top = f:GetLeft(), f:GetTop()
    local moved = left and top and f:GetHeight() ~= h
    f:SetHeight(h)
    if moved then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        UI.SavePosition(f, "anglerPop")
    end
end

-- The pop-out's maximize button: the main window on Angler's page, the pop-out put away.
Angler.MAX_ATLAS = { Up = "RedButton-Expand", Down = "RedButton-Expand-Pressed" }
Angler.MAX_FILE = "Interface\\Buttons\\UI-Panel-BiggerButton-"
function Angler:Maximize()
    local ed = ns.Editor
    if not (ed.frame and ed.frame:IsShown() and ed.currentTab == "games") then ed:Toggle("games") end
    if ns.Games.page then ns.Games:SetMode("angler") end
    if self.pop then self.pop:Hide() end
end

-- Open or shut it (/pog fish, or Pop out on the page).
function Angler:TogglePop()
    if not self.pop then self:BuildPop() end
    if self.pop:IsShown() then
        self.pop:Hide()
        return false
    end
    self.pop:SetHeight(Angler.PopHeight(self:ShopOpen()))
    UI.RestorePosition(self.pop, "anglerPop", 0)
    self.pop:Show()
    self:Refresh()
    return true
end

function Angler:RefreshPop()
    local f = self.pop
    if not f or not f:IsShown() then return end
    local g, now = G(), ns.Now()
    f.fish:SetText(Angler.Short(g.fish))
    local frenzy, spree = self:Buff("frenzy", now), self:Buff("spree", now)
    f.rate:SetText(("%s/sec"):format(per(self:Rate() * (frenzy and self:FrenzyMult() or 1))))
    local school = self.school and now < self.school.till
    f.school:SetShown(school == true)
    f.rate:SetShown(not school)
    f.buff:SetShown(not school and (frenzy or spree) ~= nil)
    if frenzy then
        f.buff:SetText(("Feeding frenzy: %ds"):format(frenzy.till - now))
    elseif spree then
        f.buff:SetText(("Casting spree: %ds"):format(spree.till - now))
    end
    local open = self:ShopOpen()
    f.shop.tex:SetTexture(open and Angler.SHOP_ART.open or Angler.SHOP_ART.shut)
    f.rule:SetShown(open)
    -- is there anything in the shop the fish in hand would buy? (its button glows while it's folded away)
    f.canBuy = false
    for i in ipairs(Angler.CREW) do
        if g.fish >= self:Cost(i, 1) then f.canBuy = true end
    end
    for _, t in ipairs(Angler.TACKLE) do
        if not g.tackle[t[1]] and g.fish >= self:TackleCost(t[1]) then f.canBuy = true end
    end
    for _, b in ipairs(f.tabs) do
        b:SetShown(open)
        b:SetSelected(b.key == f.tab)
    end
    f.qty:SetShown(open and f.tab == "crew")
    f.qty:SetLabel(self.qty == "max" and "max" or ("x" .. (self.qty or 1)))
    local items = open and self:PopItems() or {}
    f.empty:SetShown(open and f.tab == "tackle" and items[1] == nil)
    f.offset = math.max(0, math.min(f.offset or 0, #items - POP_ROWS))
    for i, row in ipairs(f.rows) do
        local it = items[f.offset + i]
        row.it = it
        row:SetShown(it ~= nil)
        row.buy:Show()
        row.tag:SetText("")
        row.count:SetText("")
        if it and it.perk then
            local k = it.perk
            row.icon:SetTexture("Interface\\Icons\\" .. k[5])
            row.name:SetText(k[2])
            if g.perks[k[1]] then
                row.buy:Hide()
                row.tag:SetText("Owned")
            else
                row.buy:SetLabel(k[4] .. (k[4] == 1 and " pearl" or " pearls"))
                row.buy:SetEnabledState(g.pearls >= k[4])
            end
        elseif it and it.crew then
            local qty = self.qty or 1
            local c, owned = Angler.CREW[it.crew], self:Owned(it.crew)
            local cost = self:Cost(it.crew, qty == "max" and math.max(1, self:Affordable(it.crew)) or qty)
            row.icon:SetTexture("Interface\\Icons\\" .. c[5])
            row.name:SetText(c[2])
            row.count:SetText(owned > 0 and tostring(owned) or "")
            row.buy:SetLabel(Angler.Short(cost))
            row.buy:SetEnabledState(g.fish >= cost)
        elseif it then
            row.icon:SetTexture("Interface\\Icons\\" .. it.tackle[5])
            row.name:SetText(it.tackle[2])
            row.buy:SetLabel(Angler.Short(self:TackleCost(it.tackle[1])))
            row.buy:SetEnabledState(g.fish >= self:TackleCost(it.tackle[1]))
        end
    end
end

-- What the list shows: the tab's entries, in order.
function Angler:Items()
    local g, out = G(), {}
    if self.tab == "tackle" then
        -- what's left to buy, cheapest first; then what's aboard
        local left, got = {}, {}
        for _, t in ipairs(Angler.TACKLE) do
            if g.tackle[t[1]] then got[#got + 1] = t else left[#left + 1] = t end
        end
        table.sort(left, function(a, b) return a[4] < b[4] end)
        for _, t in ipairs(left) do out[#out + 1] = t end
        for _, t in ipairs(got) do out[#out + 1] = t end
    elseif self.tab == "trophies" then
        for _, t in ipairs(Angler.TROPHIES) do out[#out + 1] = t end
    elseif self.tab == "perks" then
        for _, k in ipairs(Angler.PERKS) do out[#out + 1] = k end
    elseif self.tab == "guild" then
        for i, rec in ipairs(self:Leaderboard()) do out[#out + 1] = { place = i, rec = rec } end
    else
        for i in ipairs(Angler.CREW) do out[#out + 1] = i end
    end
    return out
end

local ICONS = "Interface\\Icons\\"

function Angler:FillRow(row, it)
    local g = G()
    row.index, row.key = nil, nil
    row.buy:Hide()
    row.tag:SetText("")
    row.owned:SetText("")
    row.next:SetText("")
    row.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    row.icon:SetDesaturated(false)
    row:SetAlpha(1)
    if self.tab == "crew" then
        local c, owned = Angler.CREW[it], self:Owned(it)
        local n = self.qty == "max" and math.max(1, self:Affordable(it)) or self.qty
        local cost = self:Cost(it, n)
        row.index = it
        row.icon:SetTexture(ICONS .. c[5])
        row.name:SetText(c[2])
        row.owned:SetText(owned > 0 and ("x" .. owned) or "")
        row.rate:SetText(("%s fish/sec each"):format(per(self:Each(it))))
        local at = Angler.NextMilestone(owned)
        row.next:SetText(at and ("Doubles at %d"):format(at) or "")
        row.buy:SetLabel((n > 1 and (n .. " for ") or "") .. Angler.Short(cost))
        row.buy:SetEnabledState(g.fish >= cost)
        row.buy:Show()
    elseif self.tab == "tackle" then
        local have = g.tackle[it[1]] == true
        row.key = it[1]
        row.icon:SetTexture(ICONS .. it[5])
        row.name:SetText(it[2])
        row.rate:SetText(it[3])
        if have then
            row.tag:SetText("Owned")
            row.tag:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
            row:SetAlpha(0.6)
        else
            row.buy:SetLabel(Angler.Short(self:TackleCost(it[1])))
            row.buy:SetEnabledState(g.fish >= self:TackleCost(it[1]))
            row.buy:Show()
        end
    elseif self.tab == "perks" then
        local have = g.perks[it[1]] == true
        row.key = it[1]
        row.icon:SetTexture(ICONS .. it[5])
        row.name:SetText(it[2])
        row.rate:SetText(it[3])
        if have then
            row.tag:SetText("Yours forever")
            row.tag:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        else
            row.buy:SetLabel(it[4] .. (it[4] == 1 and " pearl" or " pearls"))
            row.buy:SetEnabledState(g.pearls >= it[4])
            row.buy:Show()
        end
    elseif self.tab == "guild" then
        local rec = it.rec
        local p = ns.db.guild and ns.db.guild.players and ns.db.guild.players[rec.author]
        local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
        row.icon:SetTexture(ICONS .. (it.place == 1 and "INV_Misc_Gem_Pearl_04" or "Trade_Fishing"))
        row.name:SetText(("%d. %s"):format(it.place, Ambiguate and Ambiguate(rec.author, "short") or rec.author))
        row.name:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        row.owned:SetText(rec.author == ns.Sync:Me() and "you" or "")
        row.rate:SetText(("%s, %d pearl%s"):format(Angler.RankOf(rec.earned), rec.earned, rec.earned == 1 and "" or "s"))
        row.tag:SetText(Angler.Short(rec.life) .. " fish")
        row.tag:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    else
        local have = g.trophies[it[1]] == true
        row.icon:SetTexture(ICONS .. it[5])
        row.icon:SetDesaturated(not have)
        row.name:SetText(it[2])
        row.rate:SetText(it[3])
        row.tag:SetText(have and "+1%" or "")
        row.tag:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        if not have then
            row.name:SetTextColor(DIM[1], DIM[2], DIM[3])
            row:SetAlpha(0.6)
        end
    end
end

function Angler:Refresh()
    if not self.view and not (self.pop and self.pop:IsShown()) then return end
    local gain, away = self:Settle()
    if away and gain >= 1 then self.note = ("Your crew caught %s fish while you were gone."):format(Angler.Short(gain)) end
    local won = self:Award()
    if won[1] then
        ns.Sound("IG_QUEST_LIST_COMPLETE")
        self.note = "Trophy: " .. table.concat(won, ", ") .. "!"
    end
    self:RefreshPop()
    if not self.view then return end
    local g, s = G(), self.side
    -- the list
    local items = self:Items()
    self.offset = math.max(0, math.min(self.offset or 0, #items - ROWS))
    for i, row in ipairs(self.rows) do
        local it = items[self.offset + i]
        row:SetShown(it ~= nil)
        if it then self:FillRow(row, it) end
    end
    self.hint:Set(self.offset, ROWS, #items)
    for _, b in ipairs(self.tabs) do b:SetSelected(b.key == self.tab) end
    self.qtyBtn:SetShown(self.tab == "crew")
    self.qtyBtn:SetLabel(self.qty == "max" and "Buy max" or ("Buy " .. self.qty))
    self.summary:SetShown(self.tab ~= "crew")
    if self.tab == "trophies" then
        local n = self:TrophyCount()
        self.summary:SetText(("%d of %d, +%d%% fish"):format(n, #Angler.TROPHIES, n))
    elseif self.tab == "tackle" then
        self.summary:SetText("Resets when you sell")
    elseif self.tab == "perks" then
        self.summary:SetText(g.pearls == 1 and "1 pearl to spend" or (g.pearls .. " pearls to spend"))
    elseif self.tab == "guild" then
        self.summary:SetText("Most fish ever")
    end
    self.empty:SetShown(self.tab == "guild" and items[1] == nil)
    s.rank:SetText(self:Rank())
    -- the catch
    s.fish:SetText(Angler.Short(g.fish))
    local now = ns.Now()
    local frenzy, spree = self:Buff("frenzy", now), self:Buff("spree", now)
    local rate = self:Rate() * (frenzy and self:FrenzyMult() or 1)
    s.rate:SetText(("%s/sec"):format(per(rate)))
    local school = self.school and now < self.school.till
    s.school:SetShown(school == true)
    s.buff:SetShown(not school and (frenzy or spree) ~= nil)
    if frenzy then
        s.buff:SetText(("Feeding frenzy: %ds"):format(frenzy.till - now))
    elseif spree then
        s.buff:SetText(("Casting spree: %ds"):format(spree.till - now))
    end
    s.note:SetText(self.note or "")
    local pearls = self:PearlsNow()
    s.pearls:SetText(g.earned > 0 and ("%d earned  (+%d%%)"):format(g.earned, math.floor(g.earned * self:PearlBonus() * 100 + 0.5)) or "none yet")
    if pearls >= 1 then
        s.pearlHint:SetText(("Sell now for %d pearl%s (next one at %s fish). Crew and tackle reset, but pearls boost your fish forever and buy perks.")
            :format(pearls, pearls == 1 and "" or "s", Angler.Short(Angler.PearlAt(pearls + 1))))
    else
        s.pearlHint:SetText(("Catch %s fish this voyage for your first pearl. You're at %s.")
            :format(Angler.Short(Angler.PearlAt(1)), Angler.Short(g.total)))
    end
    s.sell:SetEnabledState(pearls >= 1)
end
