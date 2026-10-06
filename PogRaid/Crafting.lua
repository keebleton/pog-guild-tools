-- Pog Raid crafting: the guild's profession directory.
--
--   * Each addon shares its player's professions and skill (collection
--     "profs": one record a player) and the recipes they know ("recipes":
--     one record per player and profession, recipe IDs packed four base64
--     digits each, so a big recipe book is under a kilobyte).
--   * Recipes are read from the player's own profession window whenever
--     they open it, never from a list someone linked. Names come from the
--     client's spell data, so searching finds offline crafters too.
--   * Pick a profession to see who has it, then click a member to scroll
--     (and filter) their recipe book.
--
-- Layout (same grid as the other tabs):
--   [PROFESSIONS     ]  [ search recipes ......................... ]
--   [ Alchemy      4 ]  [ recipe or member rows                    ]
--   [ Blacksmith.  3 ]  [ ...                                      ]
--   [ ...            ]  [ your sharing status                      ]
local _, ns = ...
local UI = ns.UI
local Sync = ns.Sync

local Crafting = {}
ns.Crafting = Crafting

Crafting.PUBLISH_DELAY = 120   -- skill-ups while crafting: share at most this often
Crafting.MAX_RECIPES = 1000
-- Gathering and fishing have no recipe book to share (English client names).
Crafting.NO_RECIPES = { Fishing = true, Herbalism = true, Skinning = true, Archaeology = true }
-- rogue skills the skill list files with professions: not shared or shown
Crafting.SKIP = { Poisons = true, Lockpicking = true }

local PAD, TITLE_H = 12, 30
local FRAME_W, FRAME_H = 902, 608
local LEFT_W = 262
local RX = PAD + LEFT_W + PAD
local RW = FRAME_W - RX - PAD
local TOP = TITLE_H
local BAR_H = 26
local ROW_H = 22

local function me() return Sync:Me() end
local function display(name) return name and Ambiguate(name, "short") end
local function online(name) return ns.Roster.online[name] == true end

local function classColor(name)
    local p = ns.db.guild.players[name]
    local cc = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if cc then return cc.r, cc.g, cc.b end
    return 0.9, 0.9, 0.93
end

------------------------------------------------------------------------
-- Shared records
------------------------------------------------------------------------
-- "Alchemy:285:300|Mining:300:300"
local function parseList(list)
    local out = {}
    for name, rank, max in tostring(list or ""):gmatch("([^:|]+):(%d+):(%d+)") do
        if not Crafting.SKIP[name] then out[#out + 1] = { name = name, rank = tonumber(rank), max = tonumber(max) } end
    end
    return out
end
Crafting.ParseList = parseList

local function changed()
    Crafting.index = nil
    Crafting:Changed()
end

Sync:Register({
    name = "profs", code = "k", order = 3,
    fields = { "list" },
    valid = function(rec)
        if rec.by ~= rec.author or rec.id ~= rec.author then return false end
        if rec.deleted or rec.list == nil then return true end -- no professions (an empty list travels as nothing)
        return type(rec.list) == "string" and #rec.list <= 200 and rec.list:match("^[^:|]+:%d+:%d+") ~= nil
    end,
    onChange = changed,
})

Sync:Register({
    name = "recipes", code = "r", order = 5,
    fields = { "prof", "ids" },
    valid = function(rec)
        if rec.by ~= rec.author or type(rec.prof) ~= "string" or rec.id ~= rec.author .. ":" .. rec.prof then return false end
        if rec.deleted then return true end
        return type(rec.ids) == "string" and #rec.ids % 4 == 0 and #rec.ids <= 4 * Crafting.MAX_RECIPES
            and rec.ids:match("^[A-Za-z0-9+/]*$") ~= nil
    end,
    onChange = changed,
})

function Crafting.Pack(ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = Sync.Enc(id, 4) end
    return table.concat(out)
end

function Crafting.Unpack(s)
    local out = {}
    for i = 1, #(s or "") - 3, 4 do
        local id = Sync.Dec(s, i, 4)
        if id then out[#out + 1] = id end
    end
    return out
end

------------------------------------------------------------------------
-- Reading our own professions and recipes
------------------------------------------------------------------------
-- { { name, rank, max } }, from the profession slots (or the classic
-- skill list under the profession headers, if that's what the client has).
-- Second result: false when the client couldn't tell us at all.
function Crafting:ReadProfessions()
    local out = {}
    local known = (GetProfessions and GetProfessionInfo) or (C_SkillInfo and C_SkillInfo.GetNumSkillLines)
    if not known then return out, false end
    if GetProfessions and GetProfessionInfo then
        local slots = { GetProfessions() }
        for i = 1, select("#", GetProfessions()) do
            local idx = slots[i]
            if idx then
                local ok, name, _, rank, max = pcall(GetProfessionInfo, idx)
                if ok and type(name) == "string" and name ~= "" then
                    out[#out + 1] = { name = name, rank = tonumber(rank) or 0, max = tonumber(max) or 0 }
                end
            end
        end
    end
    if not out[1] and C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        local wanted = { [PROFESSIONS or "Professions"] = true, [SECONDARY_SKILLS or "Secondary Skills"] = true,
            ["Professions"] = true, ["Secondary Skills"] = true }
        local under = false
        local ok, n = pcall(C_SkillInfo.GetNumSkillLines)
        for i = 1, (ok and tonumber(n)) or 0 do
            local r = { pcall(C_SkillInfo.GetSkillLineInfo, i) }
            if r[1] then
                local name, header, rank, max
                if type(r[2]) == "table" then
                    local t = r[2]
                    name, header, rank, max = t.skillName or t.name, t.isHeader, t.skillRank, t.skillMaxRank
                else
                    name, header, rank, max = r[2], r[3], r[5], r[8]
                end
                if header then
                    under = wanted[(tostring(name or ""):gsub(":$", ""))] == true
                elseif under and type(name) == "string" and name ~= "" then
                    out[#out + 1] = { name = name, rank = tonumber(rank) or 0, max = tonumber(max) or 0 }
                end
            end
        end
    end
    for i = #out, 1, -1 do
        if Crafting.SKIP[out[i].name] then table.remove(out, i) end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out, true
end

local function listString(profs)
    local parts = {}
    for _, p in ipairs(profs) do
        parts[#parts + 1] = ("%s:%d:%d"):format(p.name:gsub("[:|]", ""), p.rank, p.max)
    end
    return table.concat(parts, "|")
end

-- Share our professions if they changed. Recipes of a profession we've
-- dropped are withdrawn.
function Crafting:PublishProfessions()
    if not Sync:GuildName() then return end
    local profs, readable = self:ReadProfessions()
    if not readable then return end
    local cur = (Sync:Store("profs") or {})[me()]
    if not profs[1] and not cur then return end
    local list = listString(profs)
    if list == "" then list = nil end
    if not cur or cur.deleted or cur.list ~= list then
        Sync:Write("profs", { id = me(), author = me(), t = ns.Now(), list = list })
    end
    if not profs[1] then return end -- the skill list may not be loaded yet; keep recipes
    local have = {}
    for _, p in ipairs(profs) do have[p.name] = true end
    for id, rec in pairs(Sync:Store("recipes") or {}) do
        if rec.author == me() and not rec.deleted and not have[rec.prof] then
            Sync:Write("recipes", { id = id, author = me(), t = ns.Now(), prof = rec.prof, deleted = true })
        end
    end
end

-- Our own open profession window: remember and share what we know.
function Crafting:ScanRecipes()
    local T = C_TradeSkillUI
    if not T or not T.GetAllRecipeIDs or not T.GetRecipeInfo or not Sync:GuildName() then return end
    for _, fn in ipairs({ T.IsTradeSkillLinked, T.IsTradeSkillGuild, T.IsNPCCrafting, T.IsTradeSkillGuildMember }) do
        local ok, yes = pcall(fn or function() end)
        if ok and yes then return end
    end
    if T.IsTradeSkillReady then
        local ok, ready = pcall(T.IsTradeSkillReady)
        if ok and ready == false then return end
    end
    local ok, base = pcall(T.GetBaseProfessionInfo or function() end)
    local prof = ok and type(base) == "table" and base.professionName
    if type(prof) ~= "string" or prof == "" then return end
    prof = prof:gsub("[:|]", "")
    if Crafting.SKIP[prof] then return end
    local ids, names = {}, self:NameCache()
    local okIds, all = pcall(T.GetAllRecipeIDs)
    for _, id in ipairs(okIds and all or {}) do
        local okInfo, info = pcall(T.GetRecipeInfo, id)
        if okInfo and type(info) == "table" and info.learned and type(id) == "number" and id > 0 and id < 2 ^ 24 then
            ids[#ids + 1] = id
            if type(info.name) == "string" then names[id] = info.name end
        end
    end
    if not ids[1] then return end
    table.sort(ids)
    while #ids > Crafting.MAX_RECIPES do table.remove(ids) end
    local packed = Crafting.Pack(ids)
    local key = me() .. ":" .. prof
    local cur = (Sync:Store("recipes") or {})[key]
    if not cur or cur.deleted or cur.ids ~= packed then
        Sync:Write("recipes", { id = key, author = me(), t = ns.Now(), prof = prof, ids = packed })
    end
end

-- Recipe names we've seen, so offline crafters stay searchable.
function Crafting:NameCache()
    ns.db.crafting = ns.db.crafting or {}
    ns.db.crafting.names = ns.db.crafting.names or {}
    return ns.db.crafting.names
end

function Crafting:RecipeName(id)
    local names = self:NameCache()
    if names[id] then return names[id] end
    local name
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
        name = ok and type(info) == "table" and info.name or nil
    end
    if not name and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        name = ok and n or nil
    end
    if type(name) == "string" and name ~= "" then
        names[id] = name
        return name
    end
end

------------------------------------------------------------------------
-- Directory and search
------------------------------------------------------------------------
-- { [profession] = { { name, rank, max, recipes } } }, members best first.
function Crafting:Directory()
    local out = {}
    local counts = {}
    for _, rec in pairs(Sync:Store("recipes") or {}) do
        if not rec.deleted then counts[rec.author .. ":" .. rec.prof] = #rec.ids / 4 end
    end
    for _, rec in pairs(Sync:Store("profs") or {}) do
        if not rec.deleted then
            for _, p in ipairs(parseList(rec.list)) do
                out[p.name] = out[p.name] or {}
                table.insert(out[p.name], { name = rec.author, rank = p.rank, max = p.max,
                    recipes = counts[rec.author .. ":" .. p.name] })
            end
        end
    end
    for _, list in pairs(out) do
        table.sort(list, function(a, b)
            if online(a.name) ~= online(b.name) then return online(a.name) end
            if a.rank ~= b.rank then return a.rank > b.rank end
            return a.name < b.name
        end)
    end
    return out
end

-- Every known recipe with its crafters: { name, lower, id, crafters }.
function Crafting:Index()
    if self.index and (not self.index.retryAt or GetTime() < self.index.retryAt) then return self.index end
    local byId = {}
    local list = {}
    local unnamed = 0
    for _, rec in pairs(Sync:Store("recipes") or {}) do
        if not rec.deleted and not Crafting.SKIP[rec.prof] then
            for _, id in ipairs(Crafting.Unpack(rec.ids)) do
                local e = byId[id]
                if not e then
                    local name = self:RecipeName(id)
                    if name then
                        e = { id = id, name = name, lower = name:lower(), crafters = {} }
                        byId[id] = e
                        list[#list + 1] = e
                    else
                        unnamed = unnamed + 1
                    end
                end
                if e then table.insert(e.crafters, { name = rec.author, prof = rec.prof }) end
            end
        end
    end
    table.sort(list, function(a, b) return a.lower < b.lower end)
    -- names the client didn't know yet may load later: look again in a minute
    list.retryAt = unnamed > 0 and GetTime() + 60 or nil
    self.index = list
    return list
end

-- One member's recipes for a profession, by name, optionally filtered.
-- Second result: false if they haven't shared that profession's recipes.
function Crafting:MemberRecipes(author, prof, text)
    local rec = (Sync:Store("recipes") or {})[author .. ":" .. prof]
    if not rec or rec.deleted then return {}, false end
    text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local out = {}
    for _, id in ipairs(Crafting.Unpack(rec.ids)) do
        local name = self:RecipeName(id)
        local e = { id = id, name = name or ("Recipe " .. id), unknown = name == nil,
            crafters = { { name = author, prof = prof } } }
        e.lower = e.name:lower()
        if text == "" or e.lower:find(text, 1, true) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b)
        if a.unknown ~= b.unknown then return b.unknown end
        return a.lower < b.lower
    end)
    return out, true
end

-- Recipes matching `text`: names starting with it first, then the rest.
function Crafting:Search(text)
    text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return {} end
    local starts, contains = {}, {}
    for _, e in ipairs(self:Index()) do
        local at = e.lower:find(text, 1, true)
        if at == 1 then
            starts[#starts + 1] = e
        elseif at then
            contains[#contains + 1] = e
        end
    end
    for _, e in ipairs(contains) do starts[#starts + 1] = e end
    for _, e in ipairs(starts) do
        table.sort(e.crafters, function(a, b)
            if online(a.name) ~= online(b.name) then return online(a.name) end
            return a.name < b.name
        end)
    end
    return starts
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
function Crafting:Changed()
    if self.page and self.page:IsShown() then self:Refresh() end
end

Crafting.PLACEHOLDER = "Who can make... (search recipes)"

local function rowList(parent, top, count)
    local rows = {}
    for i = 1, count do
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(top + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(top + (i - 1) * ROW_H))
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetTexture(ns.MEDIA .. "disc")
        row.dot:SetVertexColor(0.4, 0.85, 0.45, 1)
        row.dot:SetSize(7, 7)
        row.dot:SetPoint("LEFT", 12, 0)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 26, 0)
        row.name:SetJustifyH("LEFT")
        row.right = UI.Text(row, 11)
        row.right:SetPoint("RIGHT", -12, 0)
        row.right:SetJustifyH("RIGHT")
        row.right:SetTextColor(0.6, 0.6, 0.65)
        rows[i] = row
    end
    return rows
end

function Crafting:Build(page)
    self.page = page
    local height = FRAME_H - TOP - PAD

    -- Professions, left
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", PAD, -TOP)
    left:SetSize(LEFT_W, height)
    UI.Card(left)
    local t1 = UI.SectionTitle(left, "Professions")
    t1:SetPoint("TOPLEFT", 12, -12)
    left.visible = math.floor((height - 42) / ROW_H)
    left.rows = rowList(left, 38, left.visible)
    for _, row in ipairs(left.rows) do
        row.dot:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 12, 0)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.12)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT", 0, 0)
        row.bar:SetPoint("BOTTOMLEFT", 0, 0)
        row.bar:SetWidth(2)
        row.bar:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
        row:SetScript("OnClick", function(r)
            if not r.item then return end
            self.selected = (self.selected == r.item and not self.member) and nil or r.item
            self.member = nil
            self.offset = 0
            if self.searchBox then self.searchBox:SetText("") self.searchBox:ClearFocus() end
            self:Refresh()
        end)
    end
    left:EnableMouseWheel(true)
    left:SetScript("OnMouseWheel", function(_, d)
        self.leftOffset = (self.leftOffset or 0) - d * 3
        self:Refresh()
    end)
    left.hint = UI.ScrollHint(left, 38, 4)
    left.empty = UI.Text(left, 11)
    left.empty:SetPoint("TOP", 0, -60)
    left.empty:SetWidth(LEFT_W - 24)
    left.empty:SetTextColor(0.5, 0.5, 0.55)
    left.empty:SetText("No professions shared yet.")
    self.left = left

    -- Search and results, right
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", RX, -TOP)
    right:SetSize(RW, height)
    UI.Card(right)
    local search = UI.EditBox(right, RW - 24, BAR_H)
    search:SetPoint("TOPLEFT", 12, -12)
    search.placeholder = UI.Text(search, 11)
    search.placeholder:SetPoint("LEFT", 8, 0)
    search.placeholder:SetTextColor(0.45, 0.45, 0.5)
    search.placeholder:SetText(Crafting.PLACEHOLDER)
    search:SetScript("OnTextChanged", function(box)
        self.search = box:GetText()
        search.placeholder:SetShown(self.search == "")
        self.offset = 0
        self:Refresh()
    end)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    self.searchBox = search
    right.title = UI.SectionTitle(right, "")
    right.title:SetPoint("TOPLEFT", 12, -(12 + BAR_H + 12))
    right.count = UI.Text(right, 10)
    right.count:SetTextColor(0.55, 0.55, 0.6)
    right.back = UI.Button(right, "Back", 56, 18, function() self:ShowMember(nil) end)
    right.back:SetPoint("TOPRIGHT", -12, -(12 + BAR_H + 9))
    local line = right:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -(12 + BAR_H + 34))
    line:SetPoint("TOPRIGHT", -1, -(12 + BAR_H + 34))
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    local listTop = 12 + BAR_H + 38
    local statusH = 34
    right.visible = math.floor((height - listTop - statusH) / ROW_H)
    right.rows = rowList(right, listTop, right.visible)
    for _, row in ipairs(right.rows) do
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", function(r) self:RowTooltip(r) end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:SetScript("OnClick", function(r, button)
            -- a member opens their recipe book; right-click still whispers
            if r.kind == "member" and r.item and button ~= "RightButton" then
                self:ShowMember(r.item.name)
            else
                self:RowMenu(r)
            end
        end)
    end
    right:EnableMouseWheel(true)
    right:SetScript("OnMouseWheel", function(_, d)
        self.offset = (self.offset or 0) - d * 3
        self:Refresh()
    end)
    right.hint = UI.ScrollHint(right, listTop, statusH)
    right.empty = UI.Text(right, 11)
    right.empty:SetPoint("TOP", 0, -(listTop + 30))
    right.empty:SetWidth(RW - 60)
    right.empty:SetTextColor(0.5, 0.5, 0.55)
    right.status = UI.Text(right, 10)
    right.status:SetPoint("BOTTOMLEFT", 12, 12)
    right.status:SetPoint("BOTTOMRIGHT", -12, 12)
    right.status:SetJustifyH("LEFT")
    right.status:SetTextColor(0.55, 0.55, 0.6)
    self.right = right
end

-- Open (or, with nil, close) a member's recipe book for the picked profession.
function Crafting:ShowMember(name)
    self.member = name
    self.offset = 0
    if self.searchBox then
        self.searchBox:SetText("")
        self.searchBox:ClearFocus()
    end
    self.search = ""
    self:Refresh()
end

function Crafting:RowTooltip(row)
    local e = row.item
    if not e or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.kind == "recipe" then
        local ok = GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, e.id)
        if not ok then GameTooltip:AddLine(e.name, 1, 0.82, 0) end
        GameTooltip:AddLine(" ")
        for _, c in ipairs(e.crafters) do
            local r, g, b = classColor(c.name)
            GameTooltip:AddDoubleLine(display(c.name) .. (online(c.name) and "  |cff66dd77online|r" or ""), c.prof, r, g, b, 0.6, 0.6, 0.65)
        end
    else
        ns.Roster:ShowTooltip(e.name, row)
        return
    end
    GameTooltip:Show()
end

function Crafting:RowMenu(row)
    local e = row.item
    if not e then return end
    local entries = {}
    local people = row.kind == "recipe" and e.crafters or { e }
    for _, c in ipairs(people) do
        if c.name ~= me() then
            entries[#entries + 1] = { text = "Whisper " .. display(c.name) .. (online(c.name) and "" or " (offline)"),
                func = function() ns.Home.Whisper(c.name) end }
        end
    end
    if row.kind ~= "recipe" then
        entries[#entries + 1] = { text = "View profile", func = function() ns.Profiles:Open(e.name) end }
    end
    if entries[1] then
        table.insert(entries, 1, { text = row.kind == "recipe" and e.name or display(e.name), header = true })
        UI.ShowMenu(row, entries)
    end
end

function Crafting:Refresh()
    if not self.page then return end
    local dir = self:Directory()

    -- professions list
    local profs = {}
    for name, members in pairs(dir) do
        profs[#profs + 1] = { name = name, count = #members }
    end
    table.sort(profs, function(a, b) return a.name < b.name end)
    if self.selected and not dir[self.selected] then self.selected = nil end
    local left = self.left
    self.leftOffset = math.max(0, math.min(self.leftOffset or 0, #profs - left.visible))
    left.hint:Set(self.leftOffset, left.visible, #profs)
    for i, row in ipairs(left.rows) do
        local p = profs[i + self.leftOffset]
        row.item = p and p.name
        if p then
            local sel = self.selected == p.name
            row.name:SetText(p.name)
            row.name:SetTextColor(sel and 1 or 0.9, sel and 1 or 0.9, sel and 1 or 0.93)
            row.right:SetText(tostring(p.count))
            row.sel:SetShown(sel)
            row.bar:SetShown(sel)
            row:Show()
        else
            row:Hide()
        end
    end
    left.empty:SetShown(#profs == 0)

    -- right side: search results, a profession's members, or a hint
    local right = self.right
    local items, kind = {}, nil
    local searching = self.search and self.search:match("%S")
    if self.member and not (self.selected and dir[self.selected]) then self.member = nil end
    right.back:SetShown(self.member ~= nil)
    right.count:ClearAllPoints()
    if self.member then
        right.count:SetPoint("RIGHT", right.back, "LEFT", -10, 0)
    else
        right.count:SetPoint("TOPRIGHT", -12, -(12 + BAR_H + 13))
    end
    self.searchBox.placeholder:SetText(self.member and ("Search %s's %s recipes"):format(display(self.member), self.selected)
        or Crafting.PLACEHOLDER)
    if self.member then
        local shared
        items, shared = self:MemberRecipes(self.member, self.selected, self.search)
        kind = "recipe"
        right.title:SetText(("%s  |cff5a5a64/|r  %s"):format(self.selected:upper(), display(self.member):upper()))
        right.count:SetText(#items == 1 and "1 recipe" or (#items .. " recipes"))
        if Crafting.NO_RECIPES[self.selected] then
            right.empty:SetText(self.selected .. " has no recipes.")
        elseif not shared then
            right.empty:SetText(("%s hasn't shared their %s recipes yet."):format(
                display(self.member), self.selected, display(self.member)))
        else
            right.empty:SetText("No recipe like that.")
        end
    elseif searching then
        items, kind = self:Search(self.search), "recipe"
        right.title:SetText("RECIPES")
        right.count:SetText(#items == 1 and "1 recipe" or (#items .. " recipes"))
        right.empty:SetText("No guildie has shared a recipe like that yet.")
    elseif self.selected then
        items, kind = dir[self.selected], "member"
        right.title:SetText(self.selected:upper())
        right.count:SetText(#items == 1 and "1 member" or (#items .. " members"))
        right.empty:SetText("")
    else
        right.title:SetText("RECIPES")
        right.count:SetText("")
        right.empty:SetText("Search for something to craft, or pick a profession\nto see who has it.")
    end
    self.offset = math.max(0, math.min(self.offset or 0, #items - right.visible))
    right.hint:Set(self.offset, right.visible, #items)
    for i, row in ipairs(right.rows) do
        local e = items[i + self.offset]
        row.item, row.kind = e, kind
        if e and kind == "recipe" and self.member then
            row.dot:Hide()
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 12, 0)
            row.name:SetText(e.name)
            if e.unknown then row.name:SetTextColor(0.5, 0.5, 0.55) else row.name:SetTextColor(1, 0.82, 0) end
            row.right:SetText("")
            row:Show()
        elseif e and kind == "recipe" then
            row.dot:Hide()
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 12, 0)
            row.name:SetText(e.name)
            row.name:SetTextColor(1, 0.82, 0)
            local names = {}
            for _, c in ipairs(e.crafters) do
                if #names < 3 then names[#names + 1] = display(c.name) end
            end
            local more = #e.crafters - #names
            row.right:SetText(table.concat(names, ", ") .. (more > 0 and ("  +" .. more) or ""))
            row:Show()
        elseif e then
            row.dot:SetShown(online(e.name))
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 26, 0)
            row.name:SetText(display(e.name))
            row.name:SetTextColor(classColor(e.name))
            row.right:SetText(("%s%d / %d"):format(e.recipes and (e.recipes .. " recipes     ") or "", e.rank, e.max))
            row:Show()
        else
            row:Hide()
        end
    end
    right.empty:SetShown(#items == 0)
    right.status:SetText(self:StatusText())
end

-- What we share, or a nudge to open a profession window we haven't read.
function Crafting:StatusText()
    local mine = self:ReadProfessions()
    if not mine[1] then return "No professions yet." end
    local shared, missing = {}, {}
    local store = Sync:Store("recipes") or {}
    for _, p in ipairs(mine) do
        local rec = store[me() .. ":" .. p.name]
        if rec and not rec.deleted then
            shared[#shared + 1] = ("%s (%d)"):format(p.name, #rec.ids / 4)
        elseif not Crafting.NO_RECIPES[p.name] then
            missing[#missing + 1] = p.name
        end
    end
    if missing[1] then
        return ("open your %s %s once to share recipes!"):format(table.concat(missing, " and "):lower(),
            #missing == 1 and "window" or "windows")
    end
    if shared[1] then return "Recipes shared: " .. table.concat(shared, ", ") end
    return "No recipes to share."
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local pending = {}
local function soon(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        fn()
    end)
end

local function tradeSkill()
    soon("scan", 2, function()
        Crafting:ScanRecipes()
        Crafting:PublishProfessions()
    end)
end
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do
    ns.On(event, tradeSkill)
end
ns.On("SKILL_LINES_CHANGED", function()
    soon("profs", Crafting.PUBLISH_DELAY, function() Crafting:PublishProfessions() end)
end)
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(35, function() Crafting:PublishProfessions() end)
end)

ns.Editor:RegisterTab("crafting", "Crafting", 4,
    function(page) Crafting:Build(page) end,
    function() Crafting:Refresh() end)
