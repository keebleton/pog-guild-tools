-- Pog Raid demo data: /pog demo fills Attendance, the loot log and Recent
-- loot with eight made-up Molten Core nights so the tabs can be seen full.
-- Every record is marked demo = true; /pog demo clear removes exactly those.
-- Nothing here is shared with other players.
local _, ns = ...

local Demo = {}
ns.Demo = Demo

local NIGHTS = 8
local SNAPS = 30
local BOSSES = { "Lucifron", "Magmadar", "Gehennas", "Garr", "Baron Geddon", "Shazzrah", "Sulfuron Harbinger",
    "Golemagg the Incinerator", "Majordomo Executus", "Ragnaros" }
local ITEMS = {
    { 17076, "Bonereaver's Edge" }, { 18814, "Choker of the Fire Lord" }, { 17063, "Band of Accuria" },
    { 18822, "Obsidian Edged Blade" }, { 16921, "Halo of Transcendence" }, { 16866, "Helm of Might" },
    { 16808, "Felheart Horns" }, { 16834, "Cenarion Helm" }, { 18203, "Eskhandar's Right Claw" },
    { 17069, "Striker's Mark" }, { 18842, "Staff of Dominance" }, { 17077, "Crimson Shocker" },
    { 18821, "Quick Strike Ring" }, { 16800, "Arcanist Boots" }, { 17105, "Aurastone Hammer" },
    { 16847, "Earthfury Helmet" }, { 18829, "Deep Earth Spaulders" }, { 19137, "Onslaught Girdle" },
}
local TAGS = { "ms", "ms", "ms", "ms", "ms", "os", "os", "de", "alt", "bank" }
local FAKE = { { "Brambleworth", "DRUID" }, { "Kazzik", "ROGUE" }, { "Thessaly", "PRIEST" }, { "Grimtooth", "WARRIOR" },
    { "Velinde", "MAGE" }, { "Ashbourne", "WARLOCK" }, { "Rukka", "HUNTER" }, { "Seraphel", "PALADIN" },
    { "Thundra", "SHAMAN" }, { "Pipwhistle", "MAGE" }, { "Oswin", "PRIEST" }, { "Durnak", "WARRIOR" } }

local function link(id, name)
    return ("|cffa335ee|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(id, name)
end

function Demo:Has()
    for _, s in pairs(ns.db.guild.sessions) do
        if s.demo then return true end
    end
    return false
end

-- Up to 25 guild members (highest level first); made-up raiders fill the rest.
function Demo:Raiders()
    local players = ns.db.guild.players
    local list = {}
    for name, p in pairs(players) do
        if p.inGuild then list[#list + 1] = name end
    end
    table.sort(list, function(a, b)
        local la, lb = players[a].level or 0, players[b].level or 0
        if la ~= lb then return la > lb end
        return a < b
    end)
    local out = {}
    for i = 1, math.min(25, #list) do out[#out + 1] = list[i] end
    local i = 1
    while #out < 20 and FAKE[i] do
        local name = FAKE[i][1]
        if not players[name] then
            players[name] = { manual = true, class = FAKE[i][2], demo = true }
            ns.Attendance.keyCache = nil
        end
        out[#out + 1] = name
        i = i + 1
    end
    return out
end

function Demo:Add()
    if self:Has() then
        ns.Print("demo data is already in. /pog demo clear removes it.")
        return
    end
    local g = ns.db.guild
    local raiders = self:Raiders()
    -- each raider gets a steady attendance habit so the summary has a spread
    local habit = {}
    for i, name in ipairs(raiders) do habit[name] = 0.45 + ((i * 37) % 55) / 100 end
    local now = ns.Now()
    local itemIndex = 0
    for night = NIGHTS, 1, -1 do
        -- Tuesdays and Thursdays going back four weeks, 8pm, about three hours
        local start = now - night * 3.5 * 86400 - 3 * 3600
        local s = { id = ("demo-%d"):format(night), name = "Molten Core", demo = true, start = start,
            stop = start + 3 * 3600, lastSnap = start + 3 * 3600, lastSeen = start + 3 * 3600, snaps = SNAPS,
            present = {}, benchSnaps = {}, bosses = {}, overrides = {} }
        local attended = {}
        for i, name in ipairs(raiders) do
            local roll = ((i * 7 + night * 13) % 100) / 100
            if roll < habit[name] then
                s.present[name] = (roll < habit[name] - 0.2) and SNAPS or math.floor(SNAPS * 0.6)
                attended[#attended + 1] = name
            elseif i % 9 == night % 9 then
                s.benchSnaps[name] = SNAPS
            end
        end
        for b, boss in ipairs(BOSSES) do
            local t = start + b * 1000
            if night % 3 == 0 and b == #BOSSES then
                table.insert(s.bosses, { id = 600 + b, name = boss, success = false, t = t })
            else
                table.insert(s.bosses, { id = 600 + b, name = boss, success = true, t = t })
                -- one or two drops per boss, to people who were there
                for k = 1, (b % 3 == 0) and 2 or 1 do
                    itemIndex = itemIndex + 1
                    local item = ITEMS[(itemIndex % #ITEMS) + 1]
                    local who = attended[((itemIndex * 5 + k) % math.max(1, #attended)) + 1]
                    if who then
                        local e = { id = ("demo-loot-%d"):format(itemIndex), demo = true, t = t + 60 * k, player = who,
                            itemID = item[1], link = link(item[1], item[2]), quality = 4, boss = boss, sessionId = s.id,
                            tag = TAGS[(itemIndex % #TAGS) + 1], source = "demo" }
                        g.loot[e.id] = e
                    end
                end
            end
        end
        ns.Touch(s)
        g.sessions[s.id] = s
    end
    -- a few blue and purple drops for the home page
    for i = 1, 12 do
        local item = ITEMS[((i * 3) % #ITEMS) + 1]
        table.insert(g.seenLoot, i, { t = now - i * 1500, player = raiders[(i % #raiders) + 1], itemID = item[1],
            link = (i % 3 == 0) and ("|cff0070dd|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(item[1], item[2])
                or link(item[1], item[2]), demo = true })
    end
    self:Refresh()
    ns.Print(("demo data added: %d raid nights and their loot. /pog demo clear removes it."):format(NIGHTS))
end

function Demo:Clear()
    local g = ns.db.guild
    local n = 0
    for id, s in pairs(g.sessions) do
        if s.demo then g.sessions[id] = nil; n = n + 1 end
    end
    for id, e in pairs(g.loot) do
        if e.demo then g.loot[id] = nil end
    end
    for i = #g.seenLoot, 1, -1 do
        if g.seenLoot[i].demo then table.remove(g.seenLoot, i) end
    end
    for name, p in pairs(g.players) do
        if p.demo then
            g.players[name] = nil
            ns.Attendance.keyCache = nil
        end
    end
    self:Refresh()
    ns.Print(n > 0 and "demo data removed." or "no demo data to remove.")
end

function Demo:Refresh()
    ns.Attendance.cache, ns.Attendance.sessionsCache = nil, nil
    ns.Attendance.viewing = nil
    ns.Loot.counts = nil
    for _, m in ipairs({ ns.Attendance, ns.Loot, ns.Home }) do
        if m.page and m.page:IsShown() then m:Refresh() end
    end
    if ns.Roster.page and ns.Roster.page:IsShown() then ns.Roster:Refresh() end
end
