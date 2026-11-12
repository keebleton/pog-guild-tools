-- Pog Guild Tools: the guild's kill on sight list (0.18.0, asked for by guildies).
--
-- A shared list of enemy players. Anyone in the guild adds a name (with a few
-- words saying why) from the list's window or with "/pog kos Name Surname
-- reason"; everyone gets a pop-up when a name goes on, and a pop-up, a sound
-- and a chat line when they come across someone on the list (as a target,
-- under the mouse, or by nameplate).
--
-- The list is the `kos` Sync collection: id = the name in lower case, `name`
-- as it was typed, `note`. Whoever marked a player (or an officer) takes them
-- off again. Like the hiscores, an addon older than 0.18 can't file these
-- records and asks for them again at every check-in until it updates.
local _, ns = ...
local UI, Sync = ns.UI, ns.Sync

local Kos = {}
ns.Kos = Kos

Kos.MAX_NAME, Kos.MAX_NOTE = 40, 60
Kos.MAX = 100            -- names on the list
Kos.FRESH = 600          -- a name marked longer ago than this (seconds) arrives without a pop-up
Kos.SPOT_EVERY = 300     -- seconds before the same player is called out again
Kos.ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" -- the skull
Kos.RED = "|cffff4040"
Kos.spotted = {}         -- [id] = GetTime() of the last call-out
Kos.told = {}            -- [id .. t] = true: marks we've shown a pop-up for

-- The window (Jake: "a bulletin board of targets"): a board of wanted posters,
-- three across and two down, with the guild's hunters listed beside it.
local PAD, TITLE_H, BOX_H = 12, 30, 24
local COLS, LINES = 3, 2
local ROWS = COLS * LINES                 -- posters on the board at once
local POSTER_W, POSTER_H, POSTER_GAP, BOARD_PAD = 132, 150, 10, 12
local BOARD_W = COLS * POSTER_W + (COLS - 1) * POSTER_GAP + 2 * BOARD_PAD
local BOARD_H = LINES * POSTER_H + (LINES - 1) * POSTER_GAP + 2 * BOARD_PAD
local HUNT_W, HUNT_ROW, HUNT_HEAD = 176, 20, 30
local HUNTERS = math.floor((BOARD_H - HUNT_HEAD - 6) / HUNT_ROW)
local W = PAD + BOARD_W + 8 + HUNT_W + PAD
local INNER = W - 2 * PAD
local ADD_W, NAME_W = 60, 160
local NOTE_W = INNER - NAME_W - ADD_W - 12
local LIST_Y = TITLE_H + BOX_H + 8
local FOOT_Y = LIST_Y + BOARD_H + 8
local H = FOOT_Y + BOX_H + PAD
Kos.layout = { W = W, H = H, ROWS = ROWS, COLS = COLS, HUNTERS = HUNTERS }
Kos.PAPER = { 0.80, 0.70, 0.50 }      -- a poster
Kos.INK = { 0.22, 0.12, 0.05 }        -- its writing
Kos.BLOOD = { 0.55, 0.06, 0.04 }      -- the name on it
Kos.WOOD = { 0.16, 0.10, 0.06, 1 }    -- the board behind
Kos.KILL_EVERY = 300     -- seconds before the same player counts as a kill again
Kos.guids = {}           -- [GUID] = id: marked players we've come across this session
Kos.killed = {}          -- [id] = GetTime() of our last kill of them
Kos.seenKills = {}       -- [hunter] = the count we last saw, for the pop-up

local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function display(name) return name and Ambiguate(name, "short") end

local function colorName(name)
    local p = ns.db.guild and ns.db.guild.players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if not c then return display(name) or "?" end
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, display(name))
end

-- How a name is filed: lower case, single spaces.
function Kos.Key(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if key == "" then return nil end
    return key
end

Sync:Register({
    name = "kos", code = "t", order = 3,
    fields = { "name", "note" },
    -- anyone marks a player; whoever marked them, or an officer, changes it
    valid = function(rec)
        if type(rec.id) ~= "string" or rec.id == "" or #rec.id > Kos.MAX_NAME then return false end
        for f, max in pairs({ name = Kos.MAX_NAME, note = Kos.MAX_NOTE }) do
            local v = rec[f]
            if v ~= nil and (type(v) ~= "string" or #v > max) then return false end
        end
        if not (rec.by == rec.author or Sync:IsOfficer(rec.by)) then return false end
        return rec.deleted == true or (rec.name ~= nil and Kos.Key(rec.name) == rec.id)
    end,
    perRecord = true,
    onChange = function(rec) Kos:OnRecord(rec) end,
})

------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------
-- Everyone marked, by name.
function Kos:List()
    local out = {}
    for _, rec in pairs(Sync:Store("kos") or {}) do
        if not rec.deleted then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Lookups for the spotter: by whole name, and by first name for a mark (or
-- a sighting) that has only that.
function Kos:Index()
    if self.index then return self.index end
    local idx = { full = {}, first = {}, any = false }
    for _, rec in ipairs(self:List()) do
        idx.any = true
        idx.full[rec.id] = rec
        local first = rec.id:match("^(%S+)")
        if not idx.first[first] or rec.id == first then idx.first[first] = rec end
    end
    self.index = idx
    return idx
end

-- The mark for a name, or nil. A first name alone matches a mark with a
-- surname, and a mark of a first name alone matches anyone with it.
function Kos:Find(name)
    local key = Kos.Key(name)
    if not key then return nil end
    local idx = self:Index()
    local rec = idx.full[key]
    if rec then return rec end
    local first = key:match("^(%S+)")
    if first == key then return idx.first[first] end
    return idx.full[first]
end

function Kos:CanRemove(rec)
    return rec ~= nil and (rec.author == Sync:Me() or Sync:AmOfficer())
end

-- Marks a player. Returns the record, or nil and why not.
function Kos:Add(name, note)
    if not Sync:GuildName() then return nil, "You need to be in a guild." end
    name = ns.Codec.CleanText(name, 200):gsub("%s+", " ")
    if name == "" then return nil, "Whose name?" end
    if #name > Kos.MAX_NAME then return nil, "That name is too long." end
    local id = Kos.Key(name)
    local store = Sync:Store("kos")
    if store[id] and not store[id].deleted then return nil, name .. " is already on the list." end
    if ns.SameName(name, ns.PlayerName()) or (ns.db.guild.players[ns.Attendance:Key(name)] or {}).inGuild then
        return nil, name .. " is in the guild."
    end
    if #self:List() >= Kos.MAX then return nil, "The list is full. Take someone off first." end
    note = ns.Codec.CleanText(note, Kos.MAX_NOTE)
    local rec = Sync:Write("kos", { id = id, author = Sync:Me(), t = ns.Now(), name = name, note = note ~= "" and note or nil })
    if not rec then return nil, "That didn't save." end
    return rec
end

function Kos:Remove(rec)
    if not self:CanRemove(rec) then return false end
    return Sync:Write("kos", { id = rec.id, author = rec.author, t = rec.t, name = rec.name, deleted = true }) ~= nil
end

-- "/pog kos Name Surname reason", "/pog kos Name, reason", "/pog kos remove Name".
-- Returns the name and the reason: up to a comma when there is one, else the
-- first two words (everyone on Forever has a surname).
function Kos.Parse(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local name, note = text:match("^([^,]+),%s*(.*)$")
    if name then return name:gsub("%s+$", ""), note end
    local a, b, rest = text:match("^(%S+)%s+(%S+)%s+(.+)$")
    if a then return a .. " " .. b, rest end
    return text, ""
end

function Kos:Slash(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        self:Toggle()
        return
    end
    local gone = text:match("^[Rr][Ee][Mm][Oo][Vv][Ee]%s+(.+)$")
    if gone then
        local rec = self:Find(gone)
        if not rec then
            ns.Print(gone .. " isn't on the kill on sight list.")
        elseif not self:Remove(rec) then
            ns.Print(("Only %s or an officer can take %s off the list."):format(display(rec.author), rec.name))
        else
            ns.Print(rec.name .. " is off the kill on sight list.")
        end
        return
    end
    local name, note = Kos.Parse(text)
    local rec, why = self:Add(name, note)
    ns.Print(rec and (Kos.RED .. "Kill on sight:|r " .. rec.name .. (rec.note and (" (" .. rec.note .. ")") or "")) or why)
end

------------------------------------------------------------------------
-- Pop-ups
------------------------------------------------------------------------
function Kos:Alerts()
    return ns.db.settings.kosAlerts ~= false
end

-- A record arrived or changed (ours included).
function Kos:OnRecord(rec)
    self.index = nil
    self:Changed()
    if not rec or rec.deleted or rec.author == Sync:Me() or not self:Alerts() then return end
    local stamp = rec.id .. (rec.t or 0)
    if self.told[stamp] or (rec.t or 0) < ns.Now() - Kos.FRESH then return end
    self.told[stamp] = true
    if not (ns.GroupToast and ns.GroupToast.Note) then return end
    ns.GroupToast:Note({
        icon = Kos.ICON,
        text = ("%s marked %s%s|r kill on sight"):format(colorName(rec.author), Kos.RED, rec.name),
        sub = rec.note or "",
        onClick = function() self:Open() end,
    })
end

-- "Level 34 Orc Rogue", as much of it as the game tells us.
local function describe(unit)
    local parts = {}
    local level = UnitLevel and UnitLevel(unit)
    if level and not secret(level) then parts[#parts + 1] = "Level " .. (level > 0 and level or "??") end
    local race = UnitRace and UnitRace(unit)
    if race and not secret(race) then parts[#parts + 1] = race end
    local class = UnitClass and UnitClass(unit)
    if class and not secret(class) then parts[#parts + 1] = class end
    return table.concat(parts, " ")
end

-- Is this unit (target, mouseover, a nameplate) someone on the list?
function Kos:Check(unit)
    if not self:Index().any then return end
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local first, last = UnitName(unit)
    if not first or secret(first) or secret(last) then return end
    local rec = (last and last ~= "" and self:Find(first .. " " .. last)) or self:Find(first)
    if not rec then return end
    -- who they are, for when they die (the kill event names nobody, only a GUID)
    local guid = UnitGUID and UnitGUID(unit)
    if guid and not secret(guid) then self.guids[guid] = rec.id end
    if not self:Alerts() then return end
    local now = GetTime()
    if self.spotted[rec.id] and now - self.spotted[rec.id] < Kos.SPOT_EVERY then return end
    self.spotted[rec.id] = now
    self:Spot(rec, describe(unit))
    return rec
end

function Kos:Spot(rec, what)
    local sub = what or ""
    if rec.note then sub = sub ~= "" and (sub .. ": " .. rec.note) or rec.note end
    ns.Print(Kos.RED .. "Kill on sight:|r " .. rec.name .. (sub ~= "" and (" (" .. sub .. ")") or ""))
    ns.Sound("RAID_WARNING")
    if ns.GroupToast and ns.GroupToast.Note then
        ns.GroupToast:Note({
            icon = Kos.ICON,
            text = Kos.RED .. "Kill on sight:|r " .. rec.name,
            sub = sub,
            onClick = function() self:Open() end,
        })
    end
end

ns.On("PLAYER_TARGET_CHANGED", function() Kos:Check("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() Kos:Check("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) Kos:Check(unit) end)

------------------------------------------------------------------------
-- Kills (Jake: "a KoS leaderboard, people who have killed the most people
-- marked as KoS by other people")
--
-- Forever closes the combat log to addons; what it does send is PARTY_KILL
-- (killer's GUID, victim's GUID) when we or our group kill something. The
-- victim's GUID is one we noted when we came across them (Kos:Check), or the
-- game tells us whose it is. A kill counts for a player someone ELSE marked,
-- once per KILL_EVERY per target. Each hunter shares their own count: the
-- `koskills` collection, id = author, `n` kills, `last` = who they got last.
------------------------------------------------------------------------
Sync:Register({
    name = "koskills", code = "j", order = 4,
    fields = { "n", "last" },
    numeric = { n = true },
    valid = function(rec)
        if rec.by ~= rec.author or rec.id ~= rec.author then return false end
        if rec.last ~= nil and (type(rec.last) ~= "string" or #rec.last > Kos.MAX_NAME) then return false end
        return rec.deleted == true or (type(rec.n) == "number" and rec.n >= 0 and rec.n < 1e6 and rec.n == math.floor(rec.n))
    end,
    perRecord = true,
    onChange = function(rec) Kos:OnKills(rec) end,
})

-- Our own tally.
function Kos:Kills(name)
    local rec = (Sync:Store("koskills") or {})[name or Sync:Me()]
    return rec and not rec.deleted and rec.n or 0
end

-- The guild's hunters, most kills first: { name, n }.
function Kos:Hunters()
    local out = {}
    for name, rec in pairs(Sync:Store("koskills") or {}) do
        if not rec.deleted and (rec.n or 0) > 0 then out[#out + 1] = { name = name, n = rec.n } end
    end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return out
end

-- PARTY_KILL: we (or our group) killed `victim`.
function Kos:OnKill(_, victim)
    if not victim or secret(victim) or not self:Index().any then return end
    local id = self.guids[victim]
    if not id and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, victim)
        local rec = ok and name and not secret(name) and self:Find(name)
        id = rec and rec.id
    end
    local rec = id and (Sync:Store("kos") or {})[id]
    if not rec or rec.deleted or rec.author == Sync:Me() then return end
    local now = GetTime()
    if self.killed[id] and now - self.killed[id] < Kos.KILL_EVERY then return end
    self.killed[id] = now
    local n = self:Kills() + 1
    if not Sync:Write("koskills", { id = Sync:Me(), author = Sync:Me(), t = ns.Now(), n = n, last = rec.name }) then return end
    ns.Print(("%sKill on sight:|r you got %s. That's %d."):format(Kos.RED, rec.name, n))
    ns.Sound("IG_QUEST_LIST_COMPLETE")
    return n
end

ns.On("PARTY_KILL", function(killer, victim) Kos:OnKill(killer, victim) end)

-- A hunter's tally arrived: a pop-up for a fresh kill by someone else.
function Kos:OnKills(rec)
    self:Changed()
    if not rec or not rec.author then return end
    local n = rec.deleted and 0 or rec.n or 0
    local seen = self.seenKills[rec.author]
    self.seenKills[rec.author] = n
    if rec.author == Sync:Me() or not self:Alerts() or not rec.last then return end
    if (seen and n <= seen) or (rec.t or 0) < ns.Now() - Kos.FRESH then return end
    if not (ns.GroupToast and ns.GroupToast.Note) then return end
    ns.GroupToast:Note({
        icon = Kos.ICON,
        text = ("%s got %s%s|r"):format(colorName(rec.author), Kos.RED, rec.last),
        sub = "Kill on sight",
        onClick = function() self:Open() end,
    })
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
-- A box with grey words in it while it's empty.
local function hintBox(parent, w, hint, maxLetters)
    local e = UI.EditBox(parent, w, BOX_H)
    e:SetMaxLetters(maxLetters)
    e.hint = UI.Text(e, 12)
    e.hint:SetPoint("LEFT", 8, 0)
    e.hint:SetTextColor(0.5, 0.5, 0.55)
    e.hint:SetText(hint)
    e:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
    return e
end

-- One wanted poster: paper pinned to the board, "Wanted", the name, why, and
-- who put it up.
local function poster(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(POSTER_W, POSTER_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.shade = b:CreateTexture(nil, "BACKGROUND")
    b.shade:SetPoint("TOPLEFT", 3, -3)
    b.shade:SetPoint("BOTTOMRIGHT", 3, -3)
    b.shade:SetColorTexture(0, 0, 0, 0.45)
    b.paper = b:CreateTexture(nil, "BORDER")
    b.paper:SetAllPoints()
    b.paper:SetColorTexture(Kos.PAPER[1], Kos.PAPER[2], Kos.PAPER[3], 1)
    -- the game's own parchment over the flat colour, where the client has it
    local file = UI.FILES and UI.FILES.parchment
    if file and UI.HasFile(file) then
        b.grain = b:CreateTexture(nil, "ARTWORK")
        b.grain:SetAllPoints()
        b.grain:SetTexture(file)
        b.grain:SetAlpha(0.55)
    end
    b.hover = b:CreateTexture(nil, "HIGHLIGHT")
    b.hover:SetAllPoints()
    b.hover:SetColorTexture(1, 1, 1, 0.10)
    b.pin = b:CreateTexture(nil, "OVERLAY")
    b.pin:SetSize(8, 8)
    b.pin:SetPoint("TOP", 0, -4)
    b.pin:SetTexture("Interface\\AddOns\\PogRaid\\Media\\disc")
    b.pin:SetVertexColor(0.45, 0.08, 0.06)
    b.head = UI.Text(b, 15, "OVERLAY")
    b.head:SetPoint("TOP", 0, -16)
    b.head:SetText("Wanted")
    b.head:SetTextColor(Kos.INK[1], Kos.INK[2], Kos.INK[3])
    b.rule = b:CreateTexture(nil, "OVERLAY")
    b.rule:SetHeight(1)
    b.rule:SetPoint("TOPLEFT", 12, -36)
    b.rule:SetPoint("TOPRIGHT", -12, -36)
    b.rule:SetColorTexture(Kos.INK[1], Kos.INK[2], Kos.INK[3], 0.6)
    b.skull = b:CreateTexture(nil, "OVERLAY")
    b.skull:SetSize(26, 26)
    b.skull:SetPoint("TOP", 0, -42)
    b.skull:SetTexture(Kos.ICON)
    b.name = UI.Text(b, 13, "OVERLAY")
    b.name:SetPoint("TOP", 0, -72)
    b.name:SetSize(POSTER_W - 16, 30)
    b.name:SetJustifyH("CENTER")
    b.name:SetJustifyV("TOP")
    b.name:SetWordWrap(true)
    if b.name.SetMaxLines then b.name:SetMaxLines(2) end
    b.name:SetTextColor(Kos.BLOOD[1], Kos.BLOOD[2], Kos.BLOOD[3])
    b.note = UI.Text(b, 11, "OVERLAY")
    b.note:SetPoint("TOP", 0, -104)
    b.note:SetSize(POSTER_W - 16, 24)
    b.note:SetJustifyH("CENTER")
    b.note:SetJustifyV("TOP")
    b.note:SetWordWrap(true)
    if b.note.SetMaxLines then b.note:SetMaxLines(2) end
    b.note:SetTextColor(Kos.INK[1], Kos.INK[2], Kos.INK[3])
    b.by = UI.Text(b, 10, "OVERLAY")
    b.by:SetPoint("BOTTOM", 0, 7)
    b.by:SetWidth(POSTER_W - 16)
    b.by:SetJustifyH("CENTER")
    b.by:SetWordWrap(false)
    b.by:SetTextColor(Kos.INK[1], Kos.INK[2], Kos.INK[3], 0.8)
    for _, fs in ipairs({ b.head, b.name, b.note, b.by }) do fs:SetShadowColor(0, 0, 0, 0) end
    return b
end

function Kos:Build()
    local f = CreateFrame("Frame", "PogRaidKos", UIParent)
    f:SetSize(W, H)
    -- above the main window, as the chat window is
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    UI.Panel(f)
    UI.Window(f)
    f:Hide()
    tinsert(UISpecialFrames, "PogRaidKos")
    self.frame = f

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetSize(W, TITLE_H)
    UI.MakeMovable(f, bar, function() UI.SavePosition(f, "kos") end)
    local title = UI.Text(bar, 13)
    if UI.classic then title:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) end
    title:SetPoint("LEFT", PAD + 2, 0)
    title:SetText("Kill on sight")
    local close = UI.CloseButton(bar, 28, TITLE_H, function() f:Hide() end)
    close:SetPoint("RIGHT", -PAD + 7, 0)
    local alerts = UI.Check(bar, "Alerts", function() return self:Alerts() end, function(v)
        ns.db.settings.kosAlerts = v and true or false
    end)
    alerts:SetWidth(14 + 8 + math.ceil(alerts.label:GetStringWidth()))
    alerts:SetPoint("RIGHT", close, "LEFT", -6, 0)
    alerts:HookScript("OnEnter", function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Alerts", 1, 1, 1)
        GameTooltip:AddLine("A pop-up when a guildie marks or kills someone, and a pop-up, a sound and a chat line when you come across someone on the list.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    alerts:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.alertsCheck = alerts

    -- who, why, Add
    self.nameBox = hintBox(f, NAME_W, "Name Surname", Kos.MAX_NAME)
    self.nameBox:SetPoint("TOPLEFT", PAD, -TITLE_H)
    self.noteBox = hintBox(f, NOTE_W, "Why (optional)", Kos.MAX_NOTE)
    self.noteBox:SetPoint("TOPLEFT", PAD + NAME_W + 6, -TITLE_H)
    self.addButton = UI.Button(f, "Add", ADD_W, BOX_H, function() self:AddFromBoxes() end)
    self.addButton:SetPoint("TOPLEFT", PAD + NAME_W + 6 + NOTE_W + 6, -TITLE_H)
    self.nameBox:SetScript("OnEnterPressed", function() self:AddFromBoxes() end)
    self.noteBox:SetScript("OnEnterPressed", function() self:AddFromBoxes() end)
    self.nameBox:SetScript("OnTabPressed", function() self.noteBox:SetFocus() end)
    self.noteBox:SetScript("OnTabPressed", function() self.nameBox:SetFocus() end)

    -- the board
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", PAD, -LIST_Y)
    list:SetSize(BOARD_W, BOARD_H)
    UI.Card(list, Kos.WOOD)
    list.rows, list.offset = {}, 0
    self.list = list
    for i = 1, ROWS do
        local col, line = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local row = poster(list)
        row:SetPoint("TOPLEFT", BOARD_PAD + col * (POSTER_W + POSTER_GAP), -(BOARD_PAD + line * (POSTER_H + POSTER_GAP)))
        row:SetScript("OnClick", function(r) self:Menu(r) end)
        row:SetScript("OnEnter", function(r) self:Tip(r) end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        list.rows[i] = row
    end
    list.empty = UI.Text(list, 12)
    list.empty:SetPoint("CENTER")
    list.empty:SetTextColor(0.62, 0.55, 0.45)
    list.empty:SetText("Nobody marked yet")
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = list.offset - delta * COLS
        self:Refresh()
    end)
    list.hint = UI.ScrollHint(list, 4, 4)

    -- the hunters
    local hunt = CreateFrame("Frame", nil, f)
    hunt:SetPoint("TOPLEFT", PAD + BOARD_W + 8, -LIST_Y)
    hunt:SetSize(HUNT_W, BOARD_H)
    UI.Card(hunt)
    hunt.title = UI.SectionTitle(hunt, "Hunters", 12)
    hunt.title:SetPoint("TOPLEFT", 10, -9)
    hunt.rows = {}
    for i = 1, HUNTERS do
        local row = CreateFrame("Frame", nil, hunt)
        row:SetHeight(HUNT_ROW)
        row:SetPoint("TOPLEFT", 10, -(HUNT_HEAD + (i - 1) * HUNT_ROW))
        row:SetPoint("TOPRIGHT", -10, -(HUNT_HEAD + (i - 1) * HUNT_ROW))
        row.n = UI.Text(row, 12)
        row.n:SetPoint("RIGHT")
        row.n:SetJustifyH("RIGHT")
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT")
        row.name:SetPoint("RIGHT", row.n, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        hunt.rows[i] = row
    end
    hunt.empty = UI.Text(hunt, 11)
    hunt.empty:SetPoint("TOPLEFT", 10, -HUNT_HEAD)
    hunt.empty:SetPoint("TOPRIGHT", -10, -HUNT_HEAD)
    hunt.empty:SetJustifyH("LEFT")
    hunt.empty:SetWordWrap(true)
    hunt.empty:SetTextColor(0.55, 0.55, 0.6)
    hunt.empty:SetText("No kills yet. Kill someone a guildie marked to get on the board.")
    self.hunt = hunt

    self.status = UI.Text(f, 11)
    self.status:SetPoint("TOPLEFT", PAD + 2, -FOOT_Y)
    self.status:SetSize(INNER - 110, BOX_H)
    self.status:SetJustifyH("LEFT")
    self.status:SetTextColor(0.62, 0.62, 0.66)
    self.targetButton = UI.Button(f, "Add target", 100, BOX_H, function() self:AddTarget() end)
    self.targetButton:SetPoint("TOPRIGHT", -PAD, -FOOT_Y)

    f:SetScript("OnShow", function() self:Refresh() end)
    UI.RestorePosition(f, "kos", 40)
end

function Kos:Say(text)
    if self.status then self.status:SetText(text or "") end
end

function Kos:AddFromBoxes()
    local rec, why = self:Add(self.nameBox:GetText(), self.noteBox:GetText())
    if not rec then
        self:Say(why)
        return
    end
    self.nameBox:SetText("")
    self.noteBox:SetText("")
    self.nameBox:ClearFocus()
    self.noteBox:ClearFocus()
    self:Say(rec.name .. " is on the list.")
end

-- The player we have targeted goes on the list (with whatever's in the Why box).
function Kos:AddTarget()
    local first, last
    if UnitExists("target") and UnitIsPlayer("target") then first, last = UnitName("target") end
    if not first or secret(first) or secret(last) then
        self:Say("Target a player first.")
        return
    end
    local rec, why = self:Add((last and last ~= "") and (first .. " " .. last) or first, self.noteBox:GetText())
    if rec then self.noteBox:SetText("") end
    self:Say(rec and (rec.name .. " is on the list.") or why)
end

function Kos:Menu(row)
    local rec = row.item
    if not rec then return end
    local entries = { { text = rec.name, header = true } }
    if self:CanRemove(rec) then
        entries[#entries + 1] = { text = "Take off the list", func = function()
            if self:Remove(rec) then self:Say(rec.name .. " is off the list.") end
        end }
    else
        entries[#entries + 1] = { text = ("Only %s or an officer can take them off"):format(display(rec.author)), header = true }
    end
    UI.ShowMenu(row, entries)
end

function Kos:Tip(row)
    local rec = row.item
    if not rec or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(rec.name, 1, 0.35, 0.3)
    if rec.note then GameTooltip:AddLine(rec.note, 1, 1, 1, true) end
    local ago = ns.Home.Ago(rec.t)
    GameTooltip:AddLine(("Marked by %s %s"):format(display(rec.author), ago == "now" and "just now" or ago .. " ago"), 0.6, 0.6, 0.65)
    GameTooltip:Show()
end

function Kos:Refresh()
    if not self.frame then return end
    local list, items = self.list, self:List()
    -- whole rows of posters: the last row may be part full
    local last = math.max(0, math.ceil((#items - ROWS) / COLS) * COLS)
    list.offset = math.max(0, math.min(list.offset, last))
    for i, row in ipairs(list.rows) do
        local rec = items[list.offset + i]
        row.item = rec
        row:SetShown(rec ~= nil)
        if rec then
            row.name:SetText(rec.name)
            row.note:SetText(rec.note or "")
            row.by:SetText("by " .. (display(rec.author) or "?"))
        end
    end
    list.empty:SetShown(#items == 0)
    list.hint:Set(list.offset, ROWS, #items)
    local hunters = self:Hunters()
    for i, row in ipairs(self.hunt.rows) do
        local h = hunters[i]
        row:SetShown(h ~= nil)
        if h then
            row.name:SetText(i .. ". " .. colorName(h.name))
            row.n:SetText(tostring(h.n))
        end
    end
    self.hunt.empty:SetShown(#hunters == 0)
end

function Kos:Changed()
    if self.frame and self.frame:IsVisible() then self:Refresh() end
end

function Kos:Open()
    if not self.frame then self:Build() end
    self.frame:Show()
    self.frame:Raise()
    self:Say("")
    self:Refresh()
end

function Kos:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end
