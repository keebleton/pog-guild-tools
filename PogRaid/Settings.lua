-- Pog Raid settings tab.
--
-- Layout (same grid as the other tabs):
--   [GENERAL              ]  [WHO HAS POG RAID                    ]
--   [ checkboxes          ]  [ name            version     seen   ]
--   [OFFICER RANKS        ]  [ ...                                ]
--   [ one checkbox a rank ]  [                                    ]
--
-- Officer ranks are shared guild-wide through Sync (one "officers" record)
-- so every addon agrees on who can post to the message board. Only current
-- officers can change it; the guild master's rank is always an officer rank.
local _, ns = ...
local UI = ns.UI

local Settings = {}
ns.Settings = Settings

local PAD, GAP, TITLE_H = 12, 8, 30
local FRAME_W, FRAME_H = 902, 608
local LEFT_W = 262
local RX = PAD + LEFT_W + PAD
local RW = FRAME_W - RX - PAD
local TOP = TITLE_H
local ROW_H = 22
local GENERAL_H = 202   -- six checks

local function S() return ns.db.settings end

------------------------------------------------------------------------
-- Officer ranks (shared)
------------------------------------------------------------------------
ns.Sync:Register({
    name = "config", code = "o", order = 1,
    fields = { "ranks" },
    valid = function(rec)
        return rec.id == "officers" and type(rec.ranks) == "string" and rec.ranks:match("^[%d,]+$") ~= nil
            and ns.Sync:IsOfficer(rec.by)
    end,
    onChange = function() Settings:Changed() end,
})

-- Set of officer rank indexes, or nil if the guild hasn't chosen (then the
-- default applies: guild master and the rank below).
function Settings:OfficerRanks()
    local rec = (ns.Sync:Store("config") or {}).officers
    if not rec or rec.deleted then return nil end
    local set = { [0] = true }
    for n in rec.ranks:gmatch("%d+") do set[tonumber(n)] = true end
    return set
end

function Settings:SetOfficerRank(index, on)
    if not ns.Sync:AmOfficer() or index == 0 then return end
    local set = self:OfficerRanks() or { [0] = true, [1] = true }
    set[index] = on or nil
    set[0] = true
    local list = {}
    for i in pairs(set) do list[#list + 1] = i end
    table.sort(list)
    ns.Sync:Write("config", { id = "officers", author = ns.Sync:Me(), t = ns.Now(), ranks = table.concat(list, ",") })
    self:Changed()
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
function Settings:Build(page)
    self.page = page
    local height = FRAME_H - PAD - TOP

    -- General
    local gen = CreateFrame("Frame", nil, page)
    gen:SetPoint("TOPLEFT", PAD, -TOP)
    gen:SetSize(LEFT_W, GENERAL_H)
    UI.Card(gen)
    local t = UI.SectionTitle(gen, "General")
    t:SetPoint("TOPLEFT", 12, -12)
    self.checks = {}
    local items = {
        { "Show minimap button", function() return not S().minimap.hide end,
            function(v) ns.MinimapButton:SetHidden(not v) end },
        { "Pop-up sounds", function() return S().sounds end, function(v) S().sounds = v end },
        { "Group join request pop-ups", function() return S().joinPopups end, function(v) S().joinPopups = v end },
        { "Ranked duel challenges", function() return S().duelChallenges end, function(v) S().duelChallenges = v end },
        { "Play profile songs", function() return S().profileSongs end, function(v)
            S().profileSongs = v
            if not v and ns.Profiles then ns.Profiles:StopSong() end
        end },
        { "New group pop-ups", function() return S().groupToasts end, function(v) S().groupToasts = v end },
    }
    for i, it in ipairs(items) do
        local c = UI.Check(gen, it[1], it[2], it[3])
        c:SetWidth(LEFT_W - 24)
        c:SetPoint("TOPLEFT", 12, -(32 + (i - 1) * 26))
        self.checks[i] = c
    end
    self.general = gen

    -- Officer ranks
    local off = CreateFrame("Frame", nil, page)
    off:SetPoint("TOPLEFT", PAD, -(TOP + GENERAL_H + GAP))
    off:SetSize(LEFT_W, height - GENERAL_H - GAP)
    UI.Card(off)
    local t2 = UI.SectionTitle(off, "Officer ranks")
    t2:SetPoint("TOPLEFT", 12, -12)
    off.ranks = {}
    for i = 1, 10 do
        local idx = i - 1
        local c = UI.Check(off, "", function() return self:IsOfficerRank(idx) end,
            function(v) self:SetOfficerRank(idx, v) end)
        c:SetWidth(LEFT_W - 24)
        c:SetPoint("TOPLEFT", 12, -(32 + (i - 1) * 26))
        off.ranks[i] = c
    end
    self.officers = off

    -- Who has Pog Raid
    local who = CreateFrame("Frame", nil, page)
    who:SetPoint("TOPLEFT", RX, -TOP)
    who:SetSize(RW, height)
    UI.Card(who)
    local t3 = UI.SectionTitle(who, "Who has Pog Guild Tools")
    t3:SetPoint("TOPLEFT", 12, -12)
    who.mine = UI.Text(who, 10)
    who.mine:SetPoint("TOPRIGHT", -12, -13)
    who.mine:SetTextColor(0.55, 0.55, 0.6)
    who.ask = UI.Button(who, "Ask again", 80, 18, function() ns.Version:Announce() end)
    who.ask:SetPoint("RIGHT", who.mine, "LEFT", -10, 0)
    local line = who:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -34)
    line:SetPoint("TOPRIGHT", -1, -34)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    who.rows = {}
    who.visible = math.floor((height - 42) / ROW_H)
    for i = 1, who.visible do
        local row = CreateFrame("Frame", nil, who)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -(38 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -2, -(38 + (i - 1) * ROW_H))
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetTexture(ns.MEDIA .. "disc")
        row.dot:SetVertexColor(0.4, 0.85, 0.45, 1)
        row.dot:SetSize(7, 7)
        row.dot:SetPoint("LEFT", 12, 0)
        row.name = UI.Text(row, 12)
        row.name:SetPoint("LEFT", 26, 0)
        row.seen = UI.Text(row, 10)
        row.seen:SetPoint("RIGHT", -10, 0)
        row.seen:SetTextColor(0.5, 0.5, 0.55)
        row.version = UI.Text(row, 12)
        row.version:SetPoint("RIGHT", -70, 0)
        who.rows[i] = row
    end
    who:EnableMouseWheel(true)
    who:SetScript("OnMouseWheel", function(_, d)
        self.offset = (self.offset or 0) - d * 3
        self:Refresh()
    end)
    who.hint = UI.ScrollHint(who, 38, 4)
    who.empty = UI.Text(who, 11)
    who.empty:SetPoint("TOP", 0, -60)
    who.empty:SetTextColor(0.5, 0.5, 0.55)
    who.empty:SetText("Nobody else seen yet.")
    self.who = who
end

function Settings:IsOfficerRank(index)
    local set = self:OfficerRanks()
    if set then return set[index] == true end
    return index <= ns.Sync:OfficerRank()
end

function Settings:Changed()
    if self.page and self.page:IsShown() then self:Refresh() end
end

function Settings:Refresh()
    if not self.page then return end
    for _, c in ipairs(self.checks) do c:Update() end

    -- officer ranks
    local off = self.officers
    local canEdit = ns.Sync:AmOfficer()
    local myRank = (ns.db.guild.players[ns.Sync:Me()] or {}).rankIndex
    local numRanks = IsInGuild() and GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i, c in ipairs(off.ranks) do
        local name = i <= numRanks and GuildControlGetRankName(i) or nil
        if name and name ~= "" then
            c.label:SetText(name)
            c:Update()
            -- the guild master is always an officer, and you can't remove your own rank
            c:SetEnabledState(canEdit and i - 1 ~= 0 and i - 1 ~= myRank)
            c:Show()
        else
            c:Hide()
        end
    end

    -- who has it
    local who = self.who
    local list = ns.Version:List()
    local newest = ns.Version:Newest()
    who.mine:SetText("You: " .. ns.VERSION)
    self.offset = math.max(0, math.min(self.offset or 0, #list - who.visible))
    who.hint:Set(self.offset, who.visible, #list)
    for i, row in ipairs(who.rows) do
        local e = list[i + self.offset]
        if e then
            local p = ns.db.guild.players[e.name]
            local cc = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            row.name:SetText(Ambiguate(e.name, "short"))
            if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(0.9, 0.9, 0.93) end
            row.dot:SetShown(e.online)
            local old = ns.Version.Compare(e.version, newest) == -1
            row.version:SetText(e.version .. (old and "  (update)" or ""))
            if old then row.version:SetTextColor(0.95, 0.45, 0.4) else row.version:SetTextColor(0.4, 0.85, 0.45) end
            row.seen:SetText(e.online and "online" or (ns.Home and ns.Home.Ago(e.t) or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    who.empty:SetShown(#list == 0)
end

ns.Editor:RegisterTab("settings", "Settings", 10,
    function(page) Settings:Build(page) end,
    function() Settings:Refresh() end)
