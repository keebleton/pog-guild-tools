-- Pog Guild Tools art gallery (/pog art): the game's own artwork we could use
-- as backgrounds, so Jake can pick what goes where.
--
-- Everything is drawn by the client (nothing is shipped). The client can say
-- whether a file exists (GetFileIDFromPath) or an atlas is defined
-- (C_Texture.GetAtlasInfo); only what this client has is shown. The catalog
-- is built when the gallery first opens.
--
-- Layout (760 x 566):
--   [Art gallery                         27 of 27 found     X]
--   [Talent trees     ]  [tile] [tile] [tile]
--   [Dressing rooms   ]  [tile] [tile] [tile]
--   [Dungeons         ]  [tile] [tile] [tile]
--   [...              ]                       [<]  1 / 3  [>]
local _, ns = ...
local UI = ns.UI

local Art = {}
ns.Art = Art

-- The classic talent pictures are painted on 296 x 332 of their 320 x 384
-- pieces; the rest is dark padding the old talent window hid behind its frame.
Art.TALENT_W, Art.TALENT_H = 296, 332

local W, BAND_H, PAD, GAP = 760, 36, 12, 10
local LIST_W, ROW_H = 170, 26
local GRID_X = PAD + LIST_W + PAD
local GRID_W = W - GRID_X - PAD
local COLS, ROWS = 3, 3
local TILE_W = math.floor((GRID_W - (COLS - 1) * GAP) / COLS)
local IMG_H = math.floor(TILE_W * 0.75)
local LABEL_H = 18
local PITCH = IMG_H + 4 + LABEL_H + GAP
local PAGER_H = 22
local GRID_H = ROWS * PITCH - GAP + 8 + PAGER_H
local BIG_IMG_H = GRID_H - PAGER_H - 8 - 18 - 6 -- the big view: picture, name, Use on
local H = BAND_H + PAD + GRID_H + PAD
local PER_PAGE = COLS * ROWS

Art.layout = { W = W, H = H, GRID_X = GRID_X, GRID_W = GRID_W, GRID_H = GRID_H, TILE_W = TILE_W, IMG_H = IMG_H,
    PITCH = PITCH, LIST_W = LIST_W }

------------------------------------------------------------------------
-- Catalog
------------------------------------------------------------------------
-- Kinds: "file" (one picture, 4:3), "quad" (the classic talent and dressing
-- room art: four pieces, 256+64 wide by 256+128 tall), "atlas".
local TALENTS = {
    { "Warrior", { "WarriorArms", "Arms" }, { "WarriorFury", "Fury" }, { "WarriorProtection", "Protection" } },
    { "Paladin", { "PaladinHoly", "Holy" }, { "PaladinProtection", "Protection" }, { "PaladinCombat", "Retribution" } },
    { "Hunter", { "HunterBeastMastery", "Beast Mastery" }, { "HunterMarksmanship", "Marksmanship" }, { "HunterSurvival", "Survival" } },
    { "Rogue", { "RogueAssassination", "Assassination" }, { "RogueCombat", "Combat" }, { "RogueSubtlety", "Subtlety" } },
    { "Priest", { "PriestDiscipline", "Discipline" }, { "PriestHoly", "Holy" }, { "PriestShadow", "Shadow" } },
    { "Shaman", { "ShamanElementalCombat", "Elemental" }, { "ShamanEnhancement", "Enhancement" }, { "ShamanRestoration", "Restoration" } },
    { "Mage", { "MageArcane", "Arcane" }, { "MageFire", "Fire" }, { "MageFrost", "Frost" } },
    { "Warlock", { "WarlockCurses", "Affliction" }, { "WarlockSummoning", "Demonology" }, { "WarlockDestruction", "Destruction" } },
    { "Druid", { "DruidBalance", "Balance" }, { "DruidFeralCombat", "Feral" }, { "DruidRestoration", "Restoration" } },
}
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local RACES = { { "Human", "Human" }, { "Dwarf", "Dwarf" }, { "NightElf", "Night Elf" }, { "Gnome", "Gnome" },
    { "Orc", "Orc" }, { "Scourge", "Undead" }, { "Tauren", "Tauren" }, { "Troll", "Troll" } }
local DUNGEONS = {
    { "Deadmines", "The Deadmines" }, { "WailingCaverns", "Wailing Caverns" }, { "RagefireChasm", "Ragefire Chasm" },
    { "ShadowfangKeep", "Shadowfang Keep" }, { "BlackfathomDeeps", "Blackfathom Deeps" },
    { "StormwindStockade", "The Stockade" }, { "Stockades", "The Stockade (old name)" }, { "Gnomeregan", "Gnomeregan" },
    { "RazorfenKraul", "Razorfen Kraul" }, { "RazorfenDowns", "Razorfen Downs" }, { "ScarletMonastery", "Scarlet Monastery" },
    { "Uldaman", "Uldaman" }, { "ZulFarrak", "Zul'Farrak" }, { "Maraudon", "Maraudon" },
    { "SunkenTemple", "Sunken Temple" }, { "TempleOfAtalHakkar", "Sunken Temple (old name)" },
    { "BlackrockDepths", "Blackrock Depths" }, { "BlackrockSpire", "Blackrock Spire" }, { "DireMaul", "Dire Maul" },
    { "Scholomance", "Scholomance" }, { "Stratholme", "Stratholme" },
}
local RAIDS = {
    { "MoltenCore", "Molten Core" }, { "OnyxiasLair", "Onyxia's Lair" }, { "Onyxia", "Onyxia's Lair (other name)" },
    { "BlackwingLair", "Blackwing Lair" }, { "ZulGurub", "Zul'Gurub" }, { "AhnQiraj", "Ahn'Qiraj" },
    { "AhnQirajTemple", "Temple of Ahn'Qiraj" }, { "RuinsOfAhnQiraj", "Ruins of Ahn'Qiraj" }, { "Naxxramas", "Naxxramas" },
}
local WORLD = {
    { "EasternKingdom", "Eastern Kingdoms" }, { "Kalimdor", "Kalimdor" }, { "Stormwind", "Stormwind" },
    { "Orgrimmar", "Orgrimmar" }, { "Ironforge", "Ironforge" }, { "Undercity", "Undercity" }, { "Darnassus", "Darnassus" },
    { "ThunderBluff", "Thunder Bluff" }, { "WarsongGulch", "Warsong Gulch" }, { "ArathiBasin", "Arathi Basin" },
    { "AlteracValley", "Alterac Valley" }, { "PvPBattleground", "Battleground" },
}
local PVP = { { "AlteracValley", "Alterac Valley" }, { "WarsongGulch", "Warsong Gulch" }, { "ArathiBasin", "Arathi Basin" } }

local function build()
    local cats = {}
    local function cat(name)
        local c = { name = name, items = {} }
        cats[#cats + 1] = c
        return c
    end
    local function add(c, item)
        item.cat = c.name
        c.items[#c.items + 1] = item
    end

    local c = cat("Talent trees")
    for _, cls in ipairs(TALENTS) do
        for i = 2, 4 do
            local file, spec = cls[i][1], cls[i][2]
            add(c, { kind = "quad", base = "Interface\\TalentFrame\\" .. file .. "-", parts = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
                cw = Art.TALENT_W, ch = Art.TALENT_H, name = cls[1] .. ": " .. spec })
        end
    end
    c = cat("Talents (modern)")
    for _, cls in ipairs(TALENTS) do
        for i = 2, 4 do
            local spec = cls[i][2]:lower():gsub(" ", "")
            add(c, { kind = "atlas", atlas = ("talents-background-%s-%s"):format(cls[1]:lower(), spec), name = cls[1] .. ": " .. cls[i][2] })
        end
    end
    c = cat("Dressing rooms")
    for _, cls in ipairs(CLASSES) do
        add(c, { kind = "atlas", atlas = "dressingroom-background-" .. cls:lower(), name = cls .. " (class)" })
    end
    for _, r in ipairs(RACES) do
        add(c, { kind = "quad", base = "Interface\\DressUpFrame\\DressUpBackground-" .. r[1], parts = { "1", "2", "3", "4" },
            name = r[2] .. " (race)" })
    end
    for _, group in ipairs({ { "Dungeons", DUNGEONS }, { "Raids", RAIDS }, { "World and PvP", WORLD } }) do
        c = cat(group[1])
        for _, d in ipairs(group[2]) do
            add(c, { kind = "file", path = "Interface\\Glues\\LoadingScreens\\LoadScreen" .. d[1], name = d[2] })
        end
    end
    for _, p in ipairs(PVP) do
        add(c, { kind = "file", path = "Interface\\PVPFrame\\PvpBg-" .. p[1], name = p[2] .. " (PvP window)" })
    end
    -- the dungeon journal's own pictures: the client says which files they are
    c = cat("Dungeon journal")
    if EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetInstanceInfo then
        local okT, tiers = pcall(EJ_GetNumTiers)
        local okC, current = pcall(EJ_GetCurrentTier or function() end)
        local seen = {}
        for t = 1, (okT and tonumber(tiers) or 0) do
            if pcall(EJ_SelectTier, t) then
                for _, raid in ipairs({ false, true }) do
                    for i = 1, 200 do
                        local ok, id = pcall(EJ_GetInstanceByIndex, i, raid)
                        if not ok or not id then break end
                        local ok2, name, _, bg, _, lore = pcall(EJ_GetInstanceInfo, id)
                        if ok2 and name and not seen[name] then
                            seen[name] = true
                            if bg and bg ~= 0 and bg ~= "" then add(c, { kind = "file", path = bg, name = name }) end
                            if lore and lore ~= 0 and lore ~= "" then add(c, { kind = "file", path = lore, name = name .. " (lore)" }) end
                        end
                    end
                end
            end
        end
        if okC and current then pcall(EJ_SelectTier, current) end
    end
    c = cat("Faction crests")
    for _, f in ipairs({ { "Interface\\Timer\\Alliance-Logo", "Alliance (battleground)" }, { "Interface\\Timer\\Horde-Logo", "Horde (battleground)" },
        { "Interface\\TargetingFrame\\UI-PVP-Alliance", "Alliance (PvP flag)" }, { "Interface\\TargetingFrame\\UI-PVP-Horde", "Horde (PvP flag)" },
        { "Interface\\FriendsFrame\\PlusManz-Alliance", "Alliance (small)" }, { "Interface\\FriendsFrame\\PlusManz-Horde", "Horde (small)" } }) do
        add(c, { kind = "file", path = f[1], name = f[2] })
    end
    for _, a in ipairs({ { "AllianceEmblem", "Alliance emblem" }, { "HordeEmblem", "Horde emblem" } }) do
        add(c, { kind = "atlas", atlas = a[1], name = a[2] })
    end
    c = cat("Stationery and parchment")
    for _, f in ipairs({ { "StationeryTest1", "Plain letter" }, { "Stationery_ill1", "Illidari letter" },
        { "Stationery_Chr1", "Winter Veil letter" }, { "Stationery_OG1", "Orgrimmar letter" }, { "Stationery_TB1", "Thunder Bluff letter" },
        { "Stationery_UC1", "Undercity letter" }, { "Stationery_Val1", "Love letter" } }) do
        add(c, { kind = "file", path = "Interface\\Stationery\\" .. f[1], name = f[2] })
    end
    for _, f in ipairs({ { "Interface\\ACHIEVEMENTFRAME\\UI-Achievement-Parchment-Horizontal", "Achievement parchment" },
        { "Interface\\ACHIEVEMENTFRAME\\UI-Achievement-Parchment", "Achievement parchment (tall)" },
        { "Interface\\Spellbook\\Spellbook-Page-1", "Spellbook page" }, { "Interface\\QuestFrame\\QuestBG", "Quest parchment" } }) do
        add(c, { kind = "file", path = f[1], name = f[2] })
    end
    return cats
end

-- An item typed into "Try your own": a file ID, an atlas name, or a file
-- path (slashes either way).
function Art.Custom(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local item = { cat = "Custom", name = text }
    local n = tonumber(text)
    if n then
        item.kind, item.path = "file", n
    elseif C_Texture and C_Texture.GetAtlasInfo and select(2, pcall(C_Texture.GetAtlasInfo, text)) then
        item.kind, item.atlas = "atlas", text
    else
        item.kind, item.path = "file", (text:gsub("/", "\\"))
    end
    return item
end

-- Does this client have it? true, false, or nil when it can't say.
function Art.Has(item)
    if item.kind == "atlas" then
        if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
        local ok, info = pcall(C_Texture.GetAtlasInfo, item.atlas)
        return ok and type(info) == "table"
    end
    if type(item.path) == "number" then return true end -- a file ID the client gave us (or someone typed)
    if not GetFileIDFromPath then return nil end
    local path = item.kind == "quad" and (item.base .. item.parts[1]) or item.path
    for _, p in ipairs({ path, path .. ".blp" }) do
        local ok, id = pcall(GetFileIDFromPath, p)
        if ok and id then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Talent trees, for the rest of the addon
------------------------------------------------------------------------
-- A class's three talent trees, { { file, spec name } }, by class file ("MAGE").
function Art.Trees(class)
    for _, cls in ipairs(TALENTS) do
        if class and cls[1]:upper() == class then return { cls[2], cls[3], cls[4] } end
    end
end

-- Our current spec as a tree of our class (1-3), or nil before we have one.
-- Matched by name where we can (the client's spec order may differ).
local SPEC_ALIAS = { outlaw = "combat", guardian = "feral" }
function Art.MySpec()
    local trees = Art.Trees(select(2, UnitClass("player")))
    if not trees or not GetSpecialization then return nil end
    local ok, idx = pcall(GetSpecialization)
    if not ok or type(idx) ~= "number" or idx < 1 then return nil end
    if GetSpecializationInfo then
        local ok2, _, name = pcall(GetSpecializationInfo, idx)
        if ok2 and type(name) == "string" then
            name = name:lower()
            name = SPEC_ALIAS[name] or name
            for i, t in ipairs(trees) do
                local mine = t[2]:lower()
                if mine == name or mine:find(name, 1, true) or name:find(mine, 1, true) then return i end
            end
        end
    end
    return idx <= #trees and idx or nil
end

local function modernTree(class, t)
    return { kind = "atlas", atlas = ("talents-background-%s-%s"):format(class:lower(), (t[2]:lower():gsub(" ", ""))) }
end

-- One tree's remastered art if this client has it, else the classic picture.
function Art.ModernTreeArt(class, i)
    local trees = Art.Trees(class)
    local t = trees and trees[i]
    if not t then return nil end
    local modern = modernTree(class, t)
    if Art.Has(modern) then return modern end
    return Art.TreeArt(class, i)
end

-- One tree's art: the classic picture if this client has it, else the modern
-- one, else nil. Remembered per class and tree.
local treeArt = {}
Art.treeCache = treeArt
function Art.TreeArt(class, i)
    local key = tostring(class) .. i
    if treeArt[key] ~= nil then return treeArt[key] or nil end
    local trees = Art.Trees(class)
    local t = trees and trees[i]
    local art = false
    if t then
        local classic = { kind = "quad", base = "Interface\\TalentFrame\\" .. t[1] .. "-", parts = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
            cw = Art.TALENT_W, ch = Art.TALENT_H }
        local modern = modernTree(class, t)
        if Art.Has(classic) ~= false then art = classic elseif Art.Has(modern) then art = modern end
    end
    treeArt[key] = art
    return art or nil
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
-- The classic quads: pieces 256x256, 64x256 / 256x128, 64x128 (320 x 384),
-- of which item.cw x item.ch (from the top left) is picture.
local SPOTS = { { 0, 0, 256, 256 }, { 256, 0, 64, 256 }, { 0, 256, 256, 128 }, { 256, 256, 64, 128 } }

-- (f.artLayer / artSub / artAlpha: where and how strongly a card draws it)
local function texOf(f, i)
    f.tex = f.tex or {}
    local t = f.tex[i]
    if not t then
        t = f:CreateTexture(nil, f.artLayer or "ARTWORK", nil, f.artSub)
        f.tex[i] = t
    end
    t:ClearAllPoints()
    t:SetTexCoord(0, 1, 0, 1)
    t:SetAlpha(f.artAlpha or 1)
    t:Show()
    return t
end

local function hideAll(f)
    for _, t in ipairs(f.tex or {}) do t:Hide() end
end

-- Draw the part (ox, oy, vw, vh) of a quad's picture at scale s, its top left
-- at (dx, dy) on f: each piece cropped to what falls inside.
local function quad(f, item, s, ox, oy, vw, vh, dx, dy)
    for i, part in ipairs(item.parts) do
        local px, py, pw, ph = SPOTS[i][1], SPOTS[i][2], SPOTS[i][3], SPOTS[i][4]
        local x0, x1 = math.max(px, ox), math.min(px + pw, ox + vw)
        local y0, y1 = math.max(py, oy), math.min(py + ph, oy + vh)
        if x1 > x0 and y1 > y0 then
            local t = texOf(f, i)
            t:SetTexture(item.base .. part)
            t:SetTexCoord((x0 - px) / pw, (x1 - px) / pw, (y0 - py) / ph, (y1 - py) / ph)
            t:SetSize((x1 - x0) * s, (y1 - y0) * s)
            t:SetPoint("TOPLEFT", dx + (x0 - ox) * s, -(dy + (y0 - oy) * s))
        end
    end
end

-- Fill w x h on `f` with an item, cropped to keep its shape (a background).
function Art.Cover(f, item, w, h)
    hideAll(f)
    if item.kind == "quad" then
        local cw, ch = item.cw or 320, item.ch or 384
        local s = math.max(w / cw, h / ch)
        local vw, vh = w / s, h / s
        quad(f, item, s, (cw - vw) / 2, (ch - vh) / 2, vw, vh, 0, 0)
    elseif item.kind == "atlas" then
        local ok, info = pcall(C_Texture.GetAtlasInfo, item.atlas)
        if not ok or type(info) ~= "table" or (info.width or 0) <= 0 then return end
        local l, r, t_, b = info.leftTexCoord or 0, info.rightTexCoord or 1, info.topTexCoord or 0, info.bottomTexCoord or 1
        local want, have = w / h, info.width / info.height
        if want > have then
            local cut = (b - t_) * (1 - have / want) / 2
            t_, b = t_ + cut, b - cut
        else
            local cut = (r - l) * (1 - want / have) / 2
            l, r = l + cut, r - cut
        end
        local t = texOf(f, 1)
        t:SetTexture(info.file)
        t:SetTexCoord(l, r, t_, b)
        t:SetSize(w, h)
        t:SetPoint("TOPLEFT", 0, 0)
    else
        -- a picture: taken as 4:3 unless it says, cropped to fit
        local have, want = item.aspect or 4 / 3, w / h
        local l, r, t_, b = 0, 1, 0, 1
        if want > have then
            local cut = (1 - have / want) / 2
            t_, b = cut, 1 - cut
        else
            local cut = (1 - want / have) / 2
            l, r = cut, 1 - cut
        end
        local t = texOf(f, 1)
        t:SetTexture(item.path)
        t:SetTexCoord(l, r, t_, b)
        t:SetSize(w, h)
        t:SetPoint("TOPLEFT", 0, 0)
    end
end

-- Talent tree art inside a card, faint: drawn in the card's own background
-- layer just above its fill, so the card's text and rows stay on top.
-- art:Set(classFile, tree) or art:Random() (any class's tree).
Art.CARD_ALPHA = 0.7 -- page art, strong (Jake: was 0.3, which let the theme's surface through; full was too bright behind text)

function Art.CardArt(card)
    card.artLayer, card.artSub, card.artAlpha = "BACKGROUND", 1, Art.CARD_ALPHA
    local ctl = { card = card }
    function ctl:Show(item)
        local art = item and Art.Has(item) ~= false and item or nil
        local key = art and (art.base or art.atlas or art.path)
        if art and key ~= self.key then Art.Cover(card, art, card:GetWidth(), card:GetHeight()) end
        if not art then hideAll(card) end
        self.key = key
        self.item = art
    end
    function ctl:Set(class, i) self:Show(class and Art.TreeArt(class, i)) end
    return ctl
end

------------------------------------------------------------------------
-- Pages: one picture each, the same for everyone. "Use on" in the gallery
-- tries another in place (kept in PogRaidDB.art, this computer only).
------------------------------------------------------------------------
Art.PAGES = {
    { key = "roster", label = "Roster", default = { "Talent trees", "Priest: Holy" } },
    { key = "attendance", label = "Attendance", default = { "Talent trees", "Paladin: Holy" } },
    { key = "loot", label = "Loot", default = { "Talent trees", "Druid: Restoration" } },
    { key = "crafting", label = "Crafting", default = { "Talent trees", "Shaman: Elemental" } },
    { key = "wowdle", label = "Wowdle", default = { "Talent trees", "Mage: Arcane" } },
    { key = "duels", label = "Duels", default = { "Talent trees", "Rogue: Subtlety" } },
    { key = "settings", label = "Settings", default = { "Talent trees", "Mage: Fire" } },
}
Art.pageArt = {} -- page key -> its card's art

function Art.Catalog()
    if not Art.cats then Art.cats = build() end
    return Art.cats
end

function Art.Find(catName, name)
    if catName == "Custom" then
        local item = Art.Custom(name)
        return item and Art.Has(item) ~= false and item or nil
    end
    for _, c in ipairs(Art.Catalog()) do
        if c.name == catName then
            for _, item in ipairs(c.items) do
                if item.name == name then return item end
            end
        end
    end
end

local function pageDef(key)
    for _, p in ipairs(Art.PAGES) do
        if p.key == key then return p end
    end
end

-- The picture a page shows: our pick if we made one, else the default.
function Art.PickFor(key)
    local pick = ns.db and ns.db.art and ns.db.art[key]
    local item = pick and Art.Find(pick[1], pick[2])
    if item then return item end
    local p = pageDef(key)
    return p and Art.Find(p.default[1], p.default[2])
end

function Art.Page(key, card)
    local ctl = Art.CardArt(card)
    Art.pageArt[key] = ctl
    ctl:Show(Art.PickFor(key))
    return ctl
end

function Art.Use(key, item)
    ns.db.art = ns.db.art or {}
    ns.db.art[key] = { item.cat, item.name }
    local ctl = Art.pageArt[key]
    if ctl then ctl:Show(item) end
end

-- Up to four textures on `f` showing an item fitted into w x h, centred.
local function draw(f, item, w, h)
    hideAll(f)
    local function tex(i) return texOf(f, i) end
    if item.kind == "quad" then
        local cw, ch = item.cw or 320, item.ch or 384
        local s = math.min(w / cw, h / ch)
        quad(f, item, s, 0, 0, cw, ch, (w - cw * s) / 2, (h - ch * s) / 2)
    elseif item.kind == "atlas" then
        local t = tex(1)
        local aw, ah = 4, 3
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, item.atlas)
            if ok and type(info) == "table" and (info.width or 0) > 0 then aw, ah = info.width, info.height end
        end
        local s = math.min(w / aw, h / ah)
        if t.SetAtlas then pcall(t.SetAtlas, t, item.atlas) end
        t:SetSize(aw * s, ah * s)
        t:SetPoint("TOPLEFT", (w - aw * s) / 2, -(h - ah * s) / 2)
    else
        local t = tex(1)
        t:SetTexture(item.path)
        t:SetSize(w, h)
        t:SetPoint("TOPLEFT", 0, 0)
    end
end
Art.Draw = draw

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function Art:Build()
    local f = CreateFrame("Frame", "PogRaidArt", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    UI.Panel(f)
    f.metal = UI.PortraitFrame(f, "Art gallery", ns.MEDIA .. "logo", function() f:Hide() end)
    if not f.metal then UI.Window(f) end
    f:Hide()
    tinsert(UISpecialFrames, "PogRaidArt")
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAND_H)
    UI.MakeMovable(f, bar, function() UI.SavePosition(f, "art") end)
    local band = bar:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("BOTTOMRIGHT", -1, 0)
    local divider = bar:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", 1, 0)
    divider:SetPoint("BOTTOMRIGHT", -1, 0)
    divider:SetHeight(1)
    f.meta = UI.Text(bar, 11)
    f.meta:SetTextColor(0.55, 0.55, 0.6)
    if f.metal then
        f.title, f.close = f.metal.title, f.metal.close
        UI.Band(band, divider)
        f.meta:SetPoint("RIGHT", -PAD, 0)
        UI.MakeMovable(f, f.metal.strip, function() UI.SavePosition(f, "art") end)
    else
        f.title = UI.Text(bar, 14)
        f.title:SetPoint("LEFT", PAD, 0)
        f.title:SetText("Art gallery")
        UI.Band(band, divider, f.title)
        f.close = UI.CloseButton(bar, 28, BAND_H, function() f:Hide() end)
        f.close:SetPoint("RIGHT", -PAD + 7, 0)
        f.meta:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
    end

    -- categories
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", PAD, -(BAND_H + PAD))
    list:SetSize(LIST_W, GRID_H)
    UI.Card(list)
    list.rows = {}
    for i, c in ipairs(self.cats) do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(4 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(4 + (i - 1) * ROW_H))
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        UI.SelBar(row.sel, 0.12)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        row.name = UI.Text(row, 11)
        row.name:SetPoint("LEFT", 10, 0)
        row.count = UI.Text(row, 10)
        row.count:SetPoint("RIGHT", -10, 0)
        row.count:SetTextColor(0.5, 0.5, 0.55)
        row:SetScript("OnClick", function()
            self.cat, self.page, self.preview = i, 1, nil
            self:Refresh()
        end)
        list.rows[i] = row
    end
    -- try your own: a file path, file ID or atlas name (from wago.tools, say)
    list.ownTitle = UI.SectionTitle(list, "Try your own")
    list.ownTitle:SetPoint("TOPLEFT", 12, -(GRID_H - 74))
    local own = UI.EditBox(list, LIST_W - 20, 24)
    own:SetPoint("TOPLEFT", 10, -(GRID_H - 58))
    own.placeholder = UI.Text(own, 10)
    own.placeholder:SetPoint("LEFT", 8, 0)
    own.placeholder:SetTextColor(0.45, 0.45, 0.5)
    own.placeholder:SetText("File path or ID")
    own:SetScript("OnTextChanged", function(b) b.placeholder:SetShown(b:GetText() == "") end)
    own:SetScript("OnEnterPressed", function(b)
        b:ClearFocus()
        self:TryOwn(b:GetText())
    end)
    list.own = own
    list.ownNote = UI.Text(list, 10)
    list.ownNote:SetPoint("TOPLEFT", 12, -(GRID_H - 28))
    list.ownNote:SetWidth(LIST_W - 24)
    list.ownNote:SetJustifyH("LEFT")
    list.ownNote:SetTextColor(0.95, 0.45, 0.4)
    f.list = list

    -- tiles
    local grid = CreateFrame("Frame", nil, f)
    grid:SetPoint("TOPLEFT", GRID_X, -(BAND_H + PAD))
    grid:SetSize(GRID_W, GRID_H)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, d)
        if self.preview then return end
        self.page = (self.page or 1) - d
        self:Refresh()
    end)
    grid.tiles = {}
    for i = 1, PER_PAGE do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local t = CreateFrame("Button", nil, grid)
        t:SetSize(TILE_W, IMG_H + 4 + LABEL_H)
        t:SetPoint("TOPLEFT", col * (TILE_W + GAP), -(row * PITCH))
        t.img = CreateFrame("Frame", nil, t)
        t.img:SetPoint("TOPLEFT", 0, 0)
        t.img:SetSize(TILE_W, IMG_H)
        UI.Card(t.img)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 0, 0)
        hl:SetSize(TILE_W, IMG_H)
        UI.Hover(hl, 0.08)
        t.label = UI.Text(t, 11)
        t.label:SetPoint("TOPLEFT", 0, -(IMG_H + 4))
        t.label:SetWidth(TILE_W)
        t.label:SetJustifyH("LEFT")
        t.label:SetWordWrap(false)
        t:SetScript("OnClick", function(b)
            self.preview = b.item
            self:Refresh()
        end)
        grid.tiles[i] = t
    end
    grid.empty = UI.Text(grid, 12)
    grid.empty:SetPoint("TOP", 0, -80)
    grid.empty:SetTextColor(0.55, 0.55, 0.6)
    grid.empty:SetText("None of these are in this client.")
    -- pager
    grid.next = UI.Button(grid, ">", 24, PAGER_H, function() self.page = self.page + 1; self:Refresh() end)
    grid.next:SetPoint("BOTTOMRIGHT", 0, 0)
    grid.pageText = UI.Text(grid, 11)
    grid.pageText:SetPoint("RIGHT", grid.next, "LEFT", -10, 0)
    grid.pageText:SetTextColor(0.7, 0.7, 0.75)
    grid.prev = UI.Button(grid, "<", 24, PAGER_H, function() self.page = self.page - 1; self:Refresh() end)
    grid.prev:SetPoint("RIGHT", grid.pageText, "LEFT", -10, 0)
    f.grid = grid

    -- one picture, big: click anywhere (or Back) to return
    local big = CreateFrame("Button", nil, f)
    big:SetPoint("TOPLEFT", GRID_X, -(BAND_H + PAD))
    big:SetSize(GRID_W, GRID_H)
    big:SetFrameLevel(grid:GetFrameLevel() + 5)
    UI.Card(big)
    big.img = CreateFrame("Frame", nil, big)
    big.img:SetPoint("TOPLEFT", 0, 0)
    big.img:SetSize(GRID_W, BIG_IMG_H)
    big.name = UI.Text(big, 12)
    big.name:SetPoint("BOTTOMLEFT", 2, PAGER_H + 8)
    big.back = UI.Button(big, "Back", 60, PAGER_H, function() self.preview = nil; self:Refresh() end)
    big.back:SetPoint("BOTTOMRIGHT", 0, 0)
    -- try it on a page: Use on [Roster] [Attendance] ...
    big.useLabel = UI.Text(big, 11)
    big.useLabel:SetPoint("BOTTOMLEFT", 2, (PAGER_H - 11) / 2)
    big.useLabel:SetTextColor(0.6, 0.6, 0.65)
    big.useLabel:SetText("Use on")
    big.uses = {}
    local x = 2 + math.floor(big.useLabel:GetStringWidth() + 0.5) + 8
    for i, p in ipairs(Art.PAGES) do
        local b = UI.Button(big, p.label, 60, PAGER_H, function()
            if self.preview then
                Art.Use(p.key, self.preview)
                self:Refresh()
            end
        end)
        local w = math.floor(b.label:GetStringWidth() + 0.5) + 14
        b:SetWidth(w)
        b:SetPoint("BOTTOMLEFT", x, 0)
        b.key = p.key
        x = x + w + 4
        big.uses[i] = b
    end
    big:SetScript("OnClick", function() self.preview = nil; self:Refresh() end)
    big:Hide()
    f.big = big

    UI.RestorePosition(f, "art", 0)
    self.frame = f
end

-- Show something typed into "Try your own" big, ready for Use on.
function Art:TryOwn(text)
    local note = self.frame.list.ownNote
    local item = Art.Custom(text)
    note:SetText("")
    if not item then return end
    if Art.Has(item) == false then
        note:SetText("Not in this client.")
        return
    end
    self.preview = item
    self:Refresh()
end

function Art:Toggle()
    for _, c in ipairs(Art.Catalog()) do
        if not c.found then
            c.found = {}
            for _, item in ipairs(c.items) do
                if Art.Has(item) ~= false then c.found[#c.found + 1] = item end
            end
        end
    end
    if not self.frame then self:Build() end
    if self.frame:IsShown() then
        self.frame:Hide()
        return
    end
    self.cat, self.page, self.preview = self.cat or 1, self.page or 1, nil
    self.frame:Show()
    self:Refresh()
end

function Art:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    for i, row in ipairs(f.list.rows) do
        local c = self.cats[i]
        row.name:SetText(c.name)
        row.count:SetText(tostring(#c.found))
        row.sel:SetShown(i == self.cat)
        if #c.found == 0 then row.name:SetTextColor(0.45, 0.45, 0.5) else row.name:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3]) end
    end
    local c = self.cats[self.cat]
    f.meta:SetText(("%d of %d in this client"):format(#c.found, #c.items))
    local pages = math.max(1, math.ceil(#c.found / PER_PAGE))
    self.page = math.max(1, math.min(self.page or 1, pages))
    local grid = f.grid
    for i, t in ipairs(grid.tiles) do
        local item = c.found[(self.page - 1) * PER_PAGE + i]
        t.item = item
        if item then
            draw(t.img, item, TILE_W, IMG_H)
            t.label:SetText(item.name)
            t:Show()
        else
            t:Hide()
        end
    end
    grid.empty:SetShown(#c.found == 0)
    grid.pageText:SetText(("%d / %d"):format(self.page, pages))
    grid.prev:SetEnabledState(self.page > 1)
    grid.next:SetEnabledState(self.page < pages)
    local p = self.preview
    f.big:SetShown(p ~= nil)
    if p then
        draw(f.big.img, p, GRID_W, BIG_IMG_H)
        f.big.name:SetText(p.name)
        for _, b in ipairs(f.big.uses) do
            local cur = Art.PickFor(b.key)
            b:SetSelected(cur ~= nil and cur.cat == p.cat and cur.name == p.name)
        end
    end
end
