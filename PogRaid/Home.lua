-- Pog Raid home: the dashboard /pog opens on. Useful to anyone in the guild.
--
-- Layout (902 x 608 window):
--   [logo  Guild name ................................  level spread ]
--   [      MOTD / stats                                              ]
--   [Activity|Chat ]  [Message board          ]  [Group finder       ]
--   [              ]  [                       ]  [                   ]
--   [Online now    ]  [                       ]  [Recent loot        ]
local _, ns = ...
local UI = ns.UI

local Home = {}
ns.Home = Home

local PAD, GAP, TITLE_H = 12, 8, 30
local FRAME_W, FRAME_H = 902, 608
local HEADER_Y, HEADER_H = TITLE_H, 80
local BODY_Y = HEADER_Y + HEADER_H + GAP
local BODY_H = FRAME_H - PAD - BODY_Y
local HALF_H = (BODY_H - GAP) / 2
local LEFT_W, MID_W = 262, 342
local LEFT_X = PAD
local MID_X = LEFT_X + LEFT_W + GAP
local RIGHT_X = MID_X + MID_W + GAP
local RIGHT_W = FRAME_W - PAD - RIGHT_X
local HEAD_H = 26
local LINE_H = 20
local CHART_W, CHART_H = 240, 64
-- banner: logo | name + message | stat tiles | level spread. Tiles are
-- right-aligned against the chart; the text gets whatever is left, so it
-- grows back when the launch countdown retires.
local TEXT_X = 88
local TILE_W = 92
local TILES_RIGHT = (FRAME_W - 2 * PAD) - 10 - CHART_W - 20

-- World of Warcraft: Forever launch (November 4, 2026). Counted to the start
-- of that day on the player's clock; the tile retires a week after.
Home.LAUNCH = { year = 2026, month = 11, day = 4 }
Home.LAUNCH_SHOW_AFTER = 7 * 86400

function Home:LaunchTime()
    return time({ year = self.LAUNCH.year, month = self.LAUNCH.month, day = self.LAUNCH.day, hour = 0 })
end

-- Tile text for the countdown, or nil once it should disappear.
function Home:Countdown()
    local left = self:LaunchTime() - ns.Now()
    if left <= -Home.LAUNCH_SHOW_AFTER then return nil end
    if left <= 0 then return "Live!" end
    if left < 86400 then return math.ceil(left / 3600) .. "h" end
    return math.ceil(left / 86400) .. "d"
end
local BUCKETS = 12            -- level spread: 12 bars of 5 levels (1-5 ... 56-60)

Home.FEED_MAX = 60
Home.CHAT_MAX = 100
Home.LOOT_MAX = 100
Home.LOOT_MIN_QUALITY = 3   -- Recent loot shows blue (Rare) and up

Home.layout = { HEADER_H = HEADER_H, BODY_Y = BODY_Y, BODY_H = BODY_H, HALF_H = HALF_H, LEFT_X = LEFT_X,
    LEFT_W = LEFT_W, MID_X = MID_X, MID_W = MID_W, RIGHT_X = RIGHT_X, RIGHT_W = RIGHT_W }

local function G() return ns.db.guild end
local function display(name) return name and Ambiguate(name, "short") end
local function secret(v) return issecretvalue and issecretvalue(v) or false end

local function classColor(name)
    local p = G().players[name]
    local c = p and p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
    if c then return c.r, c.g, c.b end
    return 0.75, 0.75, 0.78
end

local function colorName(name)
    local r, g, b = classColor(name)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, display(name))
end

-- "now", "5m", "3h", "2d"
function Home.Ago(t)
    local d = ns.Now() - (t or 0)
    if d < 60 then return "now" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    if d < 86400 then return math.floor(d / 3600) .. "h" end
    return math.floor(d / 86400) .. "d"
end

local function hideTip() if GameTooltip then GameTooltip:Hide() end end

------------------------------------------------------------------------
-- Data: activity feed, guild chat, recent loot
------------------------------------------------------------------------
function Home:AddFeed(kind, name, value)
    local feed = G().feed
    table.insert(feed, 1, { t = ns.Now(), kind = kind, name = name, value = value })
    for i = #feed, Home.FEED_MAX + 1, -1 do feed[i] = nil end
    self:Changed()
end

-- Called by the roster scan with what changed since the last scan.
function Home:OnGuildScan(levels, joined, left)
    for _, x in ipairs(levels) do self:AddFeed("level", x.name, x.level) end
    for _, n in ipairs(joined) do self:AddFeed("join", n) end
    for _, n in ipairs(left) do self:AddFeed("leave", n) end
end

-- "%s has earned the achievement %s!" in guild chat: keep the achievement link.
function Home:OnAchievement(text, sender)
    if type(text) ~= "string" or type(sender) ~= "string" or secret(text) or secret(sender) then return end
    local link = text:match("(|c%x+|Hachievement:.-|h.-|h|r)") or text:match("(|Hachievement:.-|h.-|h)")
    if not link then return end
    self:AddFeed("ach", ns.Attendance:Key(sender), link)
end

function Home:OnChat(text, sender)
    if type(text) ~= "string" or type(sender) ~= "string" or secret(text) or secret(sender) then return end
    local chat = G().chat
    table.insert(chat, 1, { t = ns.Now(), name = ns.Attendance:Key(sender), text = text })
    for i = #chat, Home.CHAT_MAX + 1, -1 do chat[i] = nil end
    self:Changed()
end

-- Recent loot on the home page: any drop of LOOT_MIN_QUALITY or better the
-- client reports (you and your group, anywhere), kept apart from the raid
-- loot log. The same item for the same player within two minutes is one entry.
function Home:OnLoot(player, link)
    if not player or not link or secret(player) or secret(link) then return end
    local itemID = ns.Loot.ItemID(link)
    if not itemID then return end
    local quality = ns.Loot.Quality(link)
    if not quality or quality < Home.LOOT_MIN_QUALITY then return end
    local key = ns.Attendance:Key(player)
    local now = ns.Now()
    local list = G().seenLoot
    for _, e in ipairs(list) do
        if now - e.t > ns.Loot.DEDUPE_SECONDS then break end
        if e.player == key and e.itemID == itemID then return end
    end
    table.insert(list, 1, { t = now, player = key, itemID = itemID, link = link })
    for i = #list, Home.LOOT_MAX + 1, -1 do list[i] = nil end
    self:Changed()
end

function Home:Changed()
    if self.page and self.page:IsShown() then self:Refresh() end
end

function Home:FeedText(e)
    if e.kind == "level" then
        return ("%s reached level %d"):format(colorName(e.name), e.value)
    elseif e.kind == "join" then
        return ("%s joined the guild"):format(colorName(e.name))
    elseif e.kind == "leave" then
        return ("%s left the guild"):format(colorName(e.name))
    elseif e.kind == "ach" then
        return ("%s earned %s"):format(colorName(e.name), e.value)
    end
    return ""
end

function Home:OnlineList()
    local out = {}
    for name in pairs(ns.Roster.online) do
        if G().players[name] then out[#out + 1] = name end
    end
    table.sort(out, function(a, b)
        local la, lb = G().players[a].level or 0, G().players[b].level or 0
        if la ~= lb then return la > lb end
        return a < b
    end)
    return out
end

function Home:MOTD()
    if C_GuildInfo and C_GuildInfo.GetMOTD then return C_GuildInfo.GetMOTD() end
    return GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
end

function Home:InfoText()
    if C_GuildInfo and C_GuildInfo.GetInfoText then return C_GuildInfo.GetInfoText() end
    return GetGuildInfoText and GetGuildInfoText() or ""
end

-- Guild members per level bucket, for the level spread chart.
function Home:LevelSpread()
    local counts = {}
    for i = 1, BUCKETS do counts[i] = 0 end
    local members = 0
    for _, p in pairs(G().players) do
        if p.inGuild and p.level and p.level > 0 then
            local b = math.min(BUCKETS, math.floor((p.level - 1) / 5) + 1)
            counts[b] = counts[b] + 1
            members = members + 1
        end
    end
    return counts, members
end

-- Numbers for the banner tiles: members, online, level-ups in the last day.
function Home:StatValues()
    local _, members = self:LevelSpread()
    local online = #self:OnlineList()
    local now = ns.Now()
    local dings = 0
    for _, e in ipairs(G().feed) do
        if e.kind == "level" and now - e.t < 86400 then dings = dings + 1 end
    end
    return members, online, dings
end

------------------------------------------------------------------------
-- UI building blocks
------------------------------------------------------------------------
local function card(page, title, x, y, w, h)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", x, -y)
    c:SetSize(w, h)
    UI.Card(c)
    c.title = UI.SectionTitle(c, title)
    c.title:SetPoint("LEFT", c, "TOPLEFT", 10, -HEAD_H / 2)
    c.meta = UI.Text(c, 10)
    c.meta:SetPoint("RIGHT", c, "TOPRIGHT", -10, -HEAD_H / 2)
    c.meta:SetTextColor(0.5, 0.5, 0.55)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    c.empty = UI.Text(c, 11)
    c.empty:SetPoint("TOP", 0, -HEAD_H - 18)
    c.empty:SetWidth(w - 24)
    c.empty:SetTextColor(0.5, 0.5, 0.55)
    c.empty:SetJustifyH("CENTER")
    c.empty:Hide()
    return c
end

-- A small button that sits in a card's header.
local function headButton(c, text, w, onClick)
    local b = UI.Button(c, text, w, 18, onClick)
    b:SetPoint("RIGHT", c, "TOPRIGHT", -5, -HEAD_H / 2)
    return b
end

-- Scrolling rows inside a card. `two` adds a second, smaller line.
local function rowList(c, rowH, two, onEnter, onClick)
    c.rows = {}
    c.offset = 0
    c.visible = math.floor((c:GetHeight() - HEAD_H - 8) / rowH)
    for i = 1, c.visible do
        local row = CreateFrame("Button", nil, c)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 2, -(HEAD_H + 4 + (i - 1) * rowH))
        row:SetPoint("TOPRIGHT", -2, -(HEAD_H + 4 + (i - 1) * rowH))
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        row.right = UI.Text(row, 10)
        row.right:SetPoint("TOPRIGHT", -8, two and -5 or -(rowH - 10) / 2)
        row.right:SetJustifyH("RIGHT")
        row.right:SetTextColor(0.5, 0.5, 0.55)
        row.text = UI.Text(row, two and 12 or 11)
        row.text:SetPoint("TOPLEFT", 8, two and -4 or -(rowH - 11) / 2)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        if two then
            row.right2 = UI.Text(row, 10)
            row.right2:SetPoint("TOPRIGHT", -8, -23)
            row.right2:SetJustifyH("RIGHT")
            row.right2:SetTextColor(0.5, 0.5, 0.55)
            row.sub = UI.Text(row, 10)
            row.sub:SetPoint("TOPLEFT", 8, -22)
            row.sub:SetPoint("RIGHT", row.right2, "LEFT", -8, 0)
            row.sub:SetJustifyH("LEFT")
            row.sub:SetWordWrap(false)
            row.sub:SetTextColor(0.6, 0.6, 0.65)
        end
        if onEnter then
            row:SetScript("OnEnter", onEnter)
            row:SetScript("OnLeave", hideTip)
        end
        if onClick then row:SetScript("OnClick", onClick) end
        c.rows[i] = row
    end
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, d)
        c.offset = c.offset - d * 2
        Home:Refresh()
    end)
end

local function fillRows(c, items, fill, emptyText)
    c.offset = math.max(0, math.min(c.offset, #items - c.visible))
    c.hint = c.hint or UI.ScrollHint(c, HEAD_H + 4, 4)
    c.hint:Set(c.offset, c.visible, #items)
    for i, row in ipairs(c.rows) do
        local item = items[i + c.offset]
        row.item = item
        if item then
            fill(row, item)
            row:Show()
        else
            row:Hide()
        end
    end
    c.empty:SetText(emptyText or "")
    c.empty:SetShown(#items == 0)
end

------------------------------------------------------------------------
-- Header: logo, guild name, MOTD, stats, level spread
------------------------------------------------------------------------
function Home:BuildHeader(page)
    local h = CreateFrame("Frame", nil, page)
    h:SetPoint("TOPLEFT", PAD, -HEADER_Y)
    h:SetSize(FRAME_W - 2 * PAD, HEADER_H)
    UI.Card(h)
    self.header = h

    -- logo on a dark round plate
    local plate = h:CreateTexture(nil, "ARTWORK", nil, 1)
    plate:SetTexture(ns.MEDIA .. "disc")
    plate:SetVertexColor(0.13, 0.14, 0.17, 1)
    plate:SetSize(62, 62)
    plate:SetPoint("LEFT", 12, 0)
    local logo = h:CreateTexture(nil, "ARTWORK", nil, 2)
    logo:SetTexture(ns.MEDIA .. "logo")
    logo:SetSize(58, 58)
    logo:SetPoint("CENTER", plate, "CENTER", 0, 1)
    h.plate, h.logo = plate, logo

    h.name = UI.Text(h, 18)
    h.name:SetPoint("TOPLEFT", TEXT_X, -13)
    h.name:SetWidth(200)
    h.name:SetJustifyH("LEFT")
    h.name:SetWordWrap(false)
    -- the message gets two lines instead of being cut off
    h.motd = UI.Text(h, 11)
    h.motd:SetPoint("TOPLEFT", TEXT_X, -38)
    h.motd:SetSize(200, 28)
    h.motd:SetJustifyH("LEFT")
    h.motd:SetJustifyV("TOP")
    if h.motd.SetMaxLines then h.motd:SetMaxLines(2) end
    h.motd:SetTextColor(0.55, 0.9, 0.55)
    -- hovering the message shows it in full, with the guild info text
    local hover = CreateFrame("Frame", nil, h)
    hover:SetPoint("TOPLEFT", h.motd, "TOPLEFT", 0, 2)
    hover:SetSize(200, 30)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(f)
        if not GameTooltip then return end
        GameTooltip:SetOwner(f, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Message of the day", UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
        GameTooltip:AddLine(self:MOTD(), 1, 1, 1, true)
        local info = self:InfoText()
        if info ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Guild info", UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
            GameTooltip:AddLine(info, 0.85, 0.85, 0.9, true)
        end
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", hideTip)

    -- stat tiles: small label over a big number, thin dividers between
    h.tiles = {}
    for i, label in ipairs({ "Members", "Online", "Dings today", "Launch in" }) do
        local tile = CreateFrame("Frame", nil, h)
        tile:SetSize(TILE_W, HEADER_H)
        local div = tile:CreateTexture(nil, "ARTWORK")
        div:SetPoint("TOPLEFT", 0, -16)
        div:SetPoint("BOTTOMLEFT", 0, 16)
        div:SetWidth(1)
        div:SetColorTexture(1, 1, 1, 0.07)
        tile.label = UI.SectionTitle(tile, label)
        tile.label:SetPoint("TOP", 0, -21)
        tile.value = UI.Text(tile, 22)
        tile.value:SetPoint("TOP", tile.label, "BOTTOM", 0, -5)
        h.tiles[i] = tile
    end
    local launch = h.tiles[4]
    launch.value:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
    launch:EnableMouse(true)
    launch:SetScript("OnEnter", function(f)
        if not GameTooltip then return end
        GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("World of Warcraft: Forever", 1, 1, 1)
        GameTooltip:AddLine("Launches November 4, 2026", 0.8, 0.8, 0.85)
        GameTooltip:Show()
    end)
    launch:SetScript("OnLeave", hideTip)
    h.hover = hover

    -- level spread chart
    local chart = CreateFrame("Frame", nil, h)
    chart:SetSize(CHART_W, CHART_H)
    chart:SetPoint("RIGHT", -10, 0)
    self.chart = chart
    chart.label = UI.SectionTitle(chart, "Level spread")
    chart.label:SetPoint("TOPLEFT", 0, 0)
    local barW = math.floor((CHART_W - (BUCKETS - 1) * 3) / BUCKETS)
    local chartX = (CHART_W - (BUCKETS * barW + (BUCKETS - 1) * 3)) / 2
    chart.bars = {}
    for i = 1, BUCKETS do
        local b = CreateFrame("Frame", nil, chart)
        b:SetSize(barW, 38)
        b:SetPoint("BOTTOMLEFT", chartX + (i - 1) * (barW + 3), 12)
        b.track = b:CreateTexture(nil, "BACKGROUND")
        b.track:SetAllPoints()
        b.track:SetColorTexture(1, 1, 1, 0.02)
        b.fill = b:CreateTexture(nil, "ARTWORK")
        b.fill:SetPoint("BOTTOMLEFT")
        b.fill:SetPoint("BOTTOMRIGHT")
        b.fill:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.85)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(f)
            if not GameTooltip then return end
            GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(("Levels %d-%d"):format((i - 1) * 5 + 1, i * 5), 1, 1, 1)
            GameTooltip:AddLine(("%d member%s"):format(f.count or 0, f.count == 1 and "" or "s"), 0.8, 0.8, 0.85)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", hideTip)
        chart.bars[i] = b
    end
    local base = chart:CreateTexture(nil, "BORDER")
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT", chartX, 12)
    base:SetPoint("BOTTOMRIGHT", -chartX, 12)
    base:SetColorTexture(1, 1, 1, 0.12)
    local low = UI.Text(chart, 9)
    low:SetPoint("BOTTOMLEFT", chartX, 0)
    low:SetTextColor(0.5, 0.5, 0.55)
    low:SetText("1")
    local high = UI.Text(chart, 9)
    high:SetPoint("BOTTOMRIGHT", -chartX, 0)
    high:SetTextColor(0.5, 0.5, 0.55)
    high:SetText("60")
end

function Home:RefreshHeader()
    local h = self.header
    local inGuild = IsInGuild()
    h.name:SetText(inGuild and (GetGuildInfo("player") or "Your guild") or "Pog Raid")
    local motd = inGuild and self:MOTD() or ""
    h.motd:SetText(motd ~= "" and motd or (inGuild and "No message of the day." or "You are not in a guild."))
    -- a real message is green; the placeholder stays quiet
    if motd ~= "" then h.motd:SetTextColor(0.55, 0.9, 0.55) else h.motd:SetTextColor(0.5, 0.5, 0.55) end
    local members, online, dings = self:StatValues()
    local values = { inGuild and members, inGuild and online, inGuild and dings, self:Countdown() }
    -- lay out the tiles that have something to show, right-aligned
    local shown = {}
    for i, tile in ipairs(h.tiles) do
        local v = values[i]
        tile:SetShown(v ~= nil and v ~= false)
        if tile:IsShown() then
            tile.value:SetText(tostring(v))
            shown[#shown + 1] = tile
        end
    end
    local x = TILES_RIGHT - #shown * TILE_W
    for i, tile in ipairs(shown) do
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", x + (i - 1) * TILE_W, 0)
    end
    local textW = x - 16 - TEXT_X
    h.name:SetWidth(textW)
    h.motd:SetWidth(textW)
    h.hover:SetWidth(textW)
    h.textW = textW
    local counts = self:LevelSpread()
    local most = 1
    for _, n in ipairs(counts) do most = math.max(most, n) end
    for i, b in ipairs(self.chart.bars) do
        b.count = counts[i]
        b.fill:SetHeight(math.max(counts[i] > 0 and 2 or 0, 38 * counts[i] / most))
        b.fill:SetShown(counts[i] > 0)
    end
end

------------------------------------------------------------------------
-- Message board
------------------------------------------------------------------------
local POST_H = 58
local COMMENT_H = 46

function Home:BuildBoard(page)
    local c = card(page, "Message board", MID_X, BODY_Y, MID_W, BODY_H)
    self.boardCard = c
    c.newPost = headButton(c, "New post", 70, function()
        UI.Compose({ heading = "New post", label1 = "Title", label2 = "Message", max1 = ns.Social.MAX_TITLE,
            max2 = ns.Social.MAX_BODY }, function(title, body)
            ns.Social:NewPost(title, body)
            self:Refresh()
        end)
    end)

    -- list of posts
    c.posts = {}
    c.offset = 0
    c.visible = math.floor((BODY_H - HEAD_H - 8) / POST_H)
    for i = 1, c.visible do
        local b = CreateFrame("Button", nil, c)
        b:SetHeight(POST_H)
        b:SetPoint("TOPLEFT", 2, -(HEAD_H + 4 + (i - 1) * POST_H))
        b:SetPoint("TOPRIGHT", -2, -(HEAD_H + 4 + (i - 1) * POST_H))
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        local sep = b:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT", 8, 0)
        sep:SetPoint("BOTTOMRIGHT", -8, 0)
        sep:SetHeight(1)
        sep:SetColorTexture(1, 1, 1, 0.06)
        b.pin = UI.Text(b, 9)
        b.pin:SetPoint("TOPRIGHT", -8, -8)
        b.pin:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
        b.title = UI.Text(b, 13)
        b.title:SetPoint("TOPLEFT", 8, -6)
        b.title:SetPoint("RIGHT", b.pin, "LEFT", -8, 0)
        b.title:SetJustifyH("LEFT")
        b.title:SetWordWrap(false)
        b.meta = UI.Text(b, 10)
        b.meta:SetPoint("TOPLEFT", 8, -24)
        b.meta:SetTextColor(0.55, 0.55, 0.6)
        b.snippet = UI.Text(b, 11)
        b.snippet:SetPoint("TOPLEFT", 8, -39)
        b.snippet:SetPoint("TOPRIGHT", -8, -39)
        b.snippet:SetJustifyH("LEFT")
        b.snippet:SetWordWrap(false)
        b.snippet:SetTextColor(0.72, 0.72, 0.76)
        b:SetScript("OnClick", function(btn)
            if btn.post then
                self.openPost = btn.post.id
                c.threadOffset = 0
                self:Refresh()
            end
        end)
        c.posts[i] = b
    end
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, d)
        if self.openPost then
            c.threadOffset = (c.threadOffset or 0) - d
        else
            c.offset = c.offset - d
        end
        self:Refresh()
    end)

    -- thread view
    local t = CreateFrame("Frame", nil, c)
    t:SetPoint("TOPLEFT", 0, -HEAD_H)
    t:SetPoint("BOTTOMRIGHT")
    t:Hide()
    c.thread = t
    c.back = UI.Button(c, "< Back", 60, 18, function()
        self.openPost = nil
        self:Refresh()
    end)
    c.back:SetPoint("LEFT", c, "TOPLEFT", 5, -HEAD_H / 2)
    c.delete = headButton(c, "Delete", 56)
    c.delete:SetScript("OnClick", function(btn)
        local post = self:OpenPost()
        if post then UI.ConfirmClick(btn, function() ns.Social:Remove("posts", post); self.openPost = nil; self:Refresh() end) end
    end)
    c.pinBtn = UI.Button(c, "Pin", 50, 18, function()
        local post = self:OpenPost()
        if post then ns.Social:SetPinned(post, not post.pinned); self:Refresh() end
    end)
    c.pinBtn:SetPoint("RIGHT", c.delete, "LEFT", -4, 0)

    t.title = UI.Text(t, 14)
    t.title:SetPoint("TOPLEFT", 10, -10)
    t.title:SetPoint("TOPRIGHT", -10, -10)
    t.title:SetJustifyH("LEFT")
    t.meta = UI.Text(t, 10)
    t.meta:SetPoint("TOPLEFT", 10, -30)
    t.meta:SetTextColor(0.55, 0.55, 0.6)
    t.body = UI.Text(t, 12)
    t.body:SetPoint("TOPLEFT", 10, -48)
    t.body:SetPoint("TOPRIGHT", -10, -48)
    t.body:SetHeight(112)
    t.body:SetJustifyH("LEFT")
    t.body:SetJustifyV("TOP")
    if t.body.SetMaxLines then t.body:SetMaxLines(7) end
    t.body:SetTextColor(0.9, 0.9, 0.93)
    local div = t:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", 8, -166)
    div:SetPoint("TOPRIGHT", -8, -166)
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.08)
    t.count = UI.Text(t, 10)
    t.count:SetPoint("TOPLEFT", 10, -172)
    t.count:SetTextColor(0.6, 0.6, 0.65)
    t.comments = {}
    local listTop = 190
    local bottomBar = 34
    t.visible = math.floor((BODY_H - HEAD_H - listTop - bottomBar) / COMMENT_H)
    for i = 1, t.visible do
        local r = CreateFrame("Button", nil, t)
        r:SetHeight(COMMENT_H)
        r:SetPoint("TOPLEFT", 2, -(listTop + (i - 1) * COMMENT_H))
        r:SetPoint("TOPRIGHT", -2, -(listTop + (i - 1) * COMMENT_H))
        r:RegisterForClicks("RightButtonUp")
        r.who = UI.Text(r, 11)
        r.who:SetPoint("TOPLEFT", 8, -2)
        r.age = UI.Text(r, 10)
        r.age:SetPoint("TOPRIGHT", -8, -3)
        r.age:SetTextColor(0.5, 0.5, 0.55)
        r.text = UI.Text(r, 11)
        r.text:SetPoint("TOPLEFT", 8, -17)
        r.text:SetPoint("TOPRIGHT", -8, -17)
        r.text:SetHeight(26)
        r.text:SetJustifyH("LEFT")
        r.text:SetJustifyV("TOP")
        if r.text.SetMaxLines then r.text:SetMaxLines(2) end
        r.text:SetTextColor(0.85, 0.85, 0.88)
        r:SetScript("OnClick", function(row)
            if row.comment and ns.Social:CanRemove(row.comment) then
                UI.ShowMenu(row, { { text = "Delete comment", color = { 0.95, 0.4, 0.4 },
                    func = function() ns.Social:Remove("comments", row.comment); self:Refresh() end } })
            end
        end)
        r:SetScript("OnEnter", function(row)
            if not row.comment or not GameTooltip then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(display(row.comment.author), classColor(row.comment.author))
            GameTooltip:AddLine(row.comment.body, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", hideTip)
        t.comments[i] = r
    end
    t.add = UI.Button(t, "Add a comment", MID_W - 16, 24, function()
        local post = self:OpenPost()
        if not post then return end
        UI.Compose({ heading = "Comment on: " .. post.title, label2 = "Comment", max2 = ns.Social.MAX_COMMENT,
            button = "Comment" }, function(_, body)
            ns.Social:NewComment(post, body)
            self:Refresh()
        end)
    end)
    t.add:SetPoint("BOTTOMLEFT", 8, 8)
end

function Home:OpenPost()
    if not self.openPost then return nil end
    for _, p in ipairs(ns.Social:Posts()) do
        if p.id == self.openPost then return p end
    end
    self.openPost = nil
end

function Home:RefreshBoard()
    local c = self.boardCard
    local canPost = ns.Social:CanPost()
    local post = self:OpenPost()
    c.title:SetShown(post == nil)
    c.back:SetShown(post ~= nil)
    c.newPost:SetShown(post == nil and canPost)
    c.pinBtn:SetShown(post ~= nil and canPost)
    c.delete:SetShown(post ~= nil and ns.Social:CanRemove(post))
    c.thread:SetShown(post ~= nil)
    if post then
        for _, b in ipairs(c.posts) do b:Hide() end
        c.empty:Hide()
        local t = c.thread
        c.pinBtn:SetLabel(post.pinned and "Unpin" or "Pin")
        t.title:SetText(post.title)
        t.meta:SetText(("%s, %s ago"):format(colorName(post.author), Home.Ago(post.t)))
        t.body:SetText(post.body or "")
        local comments = ns.Social:Comments(post.id)
        t.count:SetText(#comments == 1 and "1 comment" or (#comments .. " comments"))
        c.threadOffset = math.max(0, math.min(c.threadOffset or 0, #comments - t.visible))
        if c.postHint then c.postHint:Set(0, 1, 0) end
        c.threadHint = c.threadHint or UI.ScrollHint(t, 190, 40)
        c.threadHint:Set(c.threadOffset, t.visible, #comments)
        for i, r in ipairs(t.comments) do
            local cm = comments[i + c.threadOffset]
            r.comment = cm
            if cm then
                r.who:SetText(colorName(cm.author))
                r.age:SetText(Home.Ago(cm.t))
                r.text:SetText(cm.body)
                r:Show()
            else
                r:Hide()
            end
        end
        return
    end
    local posts = ns.Social:Posts()
    c.offset = math.max(0, math.min(c.offset, #posts - c.visible))
    c.postHint = c.postHint or UI.ScrollHint(c, HEAD_H + 4, 4)
    c.postHint:Set(c.offset, c.visible, #posts)
    if c.threadHint then c.threadHint:Set(0, 1, 0) end
    for i, b in ipairs(c.posts) do
        local p = posts[i + c.offset]
        b.post = p
        if p then
            b.title:SetText(p.title)
            b.title:SetTextColor(p.pinned and UI.ACCENT[1] or 1, p.pinned and UI.ACCENT[2] or 1, p.pinned and UI.ACCENT[3] or 1)
            b.pin:SetText(p.pinned and "PINNED" or "")
            local n = #ns.Social:Comments(p.id)
            b.meta:SetText(("%s, %s ago, %s"):format(colorName(p.author), Home.Ago(p.t),
                n == 1 and "1 comment" or (n .. " comments")))
            b.snippet:SetText(p.body or "")
            b:Show()
        else
            b:Hide()
        end
    end
    if not IsInGuild() then
        c.empty:SetText("Join a guild to see its message board.")
    elseif canPost then
        c.empty:SetText("No posts yet. Use New post to write the first one.")
    else
        c.empty:SetText("No posts yet. Officers can post here, and\neveryone with Pog Raid can comment.")
    end
    c.empty:SetShown(#posts == 0)
end

------------------------------------------------------------------------
-- Group finder
------------------------------------------------------------------------
local function whisper(name)
    local target = Ambiguate(name, "none")
    if ChatFrame_SendTell then
        ChatFrame_SendTell(target)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(target)
    end
end
Home.Whisper = whisper

function Home.Invite(name)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    pcall(fn, Ambiguate(name, "none"))
end

function Home:BuildGroups(page)
    local c = card(page, "Group finder", RIGHT_X, BODY_Y, RIGHT_W, HALF_H)
    self.groupCard = c
    c.post = headButton(c, "Post group", 74, function()
        local mine = ns.Social:MyGroup()
        UI.Compose({ heading = mine and "Update your group" or "Post a group", label1 = "Doing what?",
            labelMid = "Looking for", label2 = "Description (optional, shown when people hover your group)",
            max1 = ns.Social.MAX_LFG, maxMid = ns.Social.MAX_LFG, max2 = ns.Social.MAX_LFG_DESC,
            text1 = mine and mine.what or "", textMid = mine and mine.need or "", text2 = mine and mine.desc or "",
            button = "Post" }, function(what, desc, need)
            ns.Social:PostGroup(what, need, desc)
            self:Refresh()
        end)
    end)
    rowList(c, 40, true, function(row) self:GroupTooltip(row) end, function(row)
        local g = row.item
        if not g then return end
        local mine = g.author == ns.Sync:Me()
        local menu = { { text = display(g.author) .. ", " .. g.what, header = true } }
        if not mine then
            if ns.Social.requested[g.id] then
                menu[#menu + 1] = { text = "Request sent", disabled = true }
            elseif ns.Social:IsFull(g) then
                menu[#menu + 1] = { text = "Group is full", disabled = true }
            else
                menu[#menu + 1] = { text = "Request to join", color = { 0.5, 0.9, 0.55 },
                    func = function() ns.Social:RequestJoin(g) end }
            end
            menu[#menu + 1] = { text = "Whisper " .. display(g.author), func = function() whisper(g.author) end }
        else
            for who in pairs(ns.Social.requests) do
                menu[#menu + 1] = { text = "Invite " .. display(who), color = { 0.5, 0.9, 0.55 },
                    func = function() ns.Social:Answer(who, true) end }
                menu[#menu + 1] = { text = "   No thanks, " .. display(who), func = function() ns.Social:Answer(who, false) end }
            end
        end
        if ns.Social:CanRemove(g) then
            menu[#menu + 1] = { text = g.author == ns.Sync:Me() and "Close my group" or "Remove listing",
                color = { 0.95, 0.4, 0.4 }, func = function() ns.Social:Remove("lfg", g); self:Refresh() end }
        end
        UI.ShowMenu(row, menu)
    end)
end

-- Hovering a listing: everything about it, description last.
function Home:GroupTooltip(row)
    local g = row.item
    if not g or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(g.what, 1, 1, 1)
    GameTooltip:AddLine("Posted by " .. colorName(g.author), 0.8, 0.8, 0.85)
    if g.need then GameTooltip:AddDoubleLine("Looking for", g.need, 0.6, 0.6, 0.65, 1, 1, 1) end
    if g.size then
        GameTooltip:AddDoubleLine("Group", g.size .. "/" .. g.max .. (ns.Social:IsFull(g) and ", full" or ""),
            0.6, 0.6, 0.65, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Time left", math.max(0, math.ceil((g.exp - ns.Now()) / 60)) .. "m", 0.6, 0.6, 0.65, 1, 1, 1)
    if g.desc then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(g.desc, 0.9, 0.9, 0.93, true)
    end
    GameTooltip:Show()
end

function Home:RefreshGroups()
    local c = self.groupCard
    local groups = ns.Social:Groups()
    c.post:SetShown(IsInGuild())
    c.post:SetLabel(ns.Social:MyGroup() and "Update" or "Post group")
    fillRows(c, groups, function(row, g)
        row.text:SetText(g.what)
        local full = ns.Social:IsFull(g)
        row.right:SetText(g.size and ((g.size .. "/" .. g.max) .. (full and " full" or "")) or "")
        row.right:SetTextColor(full and 0.95 or 0.5, full and 0.45 or 0.85, full and 0.4 or 0.55)
        local left = math.max(0, math.ceil((g.exp - ns.Now()) / 60))
        local status = left .. "m left"
        if ns.Social.requested[g.id] then status = "requested" end
        if g.author == ns.Sync:Me() and ns.Social:RequestCount() > 0 then
            status = ns.Social:RequestCount() .. (ns.Social:RequestCount() == 1 and " request" or " requests")
        end
        row.right2:SetText(status)
        row.sub:SetText(colorName(g.author) .. (g.need and ("  |cff9a9aa2needs " .. g.need .. "|r") or ""))
    end, IsInGuild() and "No groups up. Post one and guildies\nwith Pog Raid will see it." or "")
end

------------------------------------------------------------------------
-- Build + refresh
------------------------------------------------------------------------
function Home:Build(page)
    self.page = page
    self:BuildHeader(page)

    -- Activity and Chat share the top-left slot; the header toggles them.
    self.feedCard = card(page, "", LEFT_X, BODY_Y, LEFT_W, HALF_H)
    self.chatCard = card(page, "", LEFT_X, BODY_Y, LEFT_W, HALF_H)
    for _, c in ipairs({ self.feedCard, self.chatCard }) do
        c.title:Hide()
        c.modeFeed = UI.Tab(c, "ACTIVITY", 72, HEAD_H, function() self.leftMode = "feed"; self:Refresh() end, 10)
        c.modeFeed:SetPoint("TOPLEFT", 2, 0)
        c.modeChat = UI.Tab(c, "CHAT", 48, HEAD_H, function() self.leftMode = "chat"; self:Refresh() end, 10)
        c.modeChat:SetPoint("LEFT", c.modeFeed, "RIGHT", 0, 0)
    end
    rowList(self.feedCard, LINE_H, false, function(row)
        local e = row.item
        if e and e.kind == "ach" and GameTooltip then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, e.value)
            GameTooltip:Show()
        end
    end)
    rowList(self.chatCard, LINE_H, false, function(row)
        if not row.item or not GameTooltip then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(display(row.item.name), classColor(row.item.name))
        GameTooltip:AddLine(row.item.text, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    self.onlineCard = card(page, "Online now", LEFT_X, BODY_Y + HALF_H + GAP, LEFT_W, HALF_H)
    rowList(self.onlineCard, LINE_H, false, function(row)
        if row.item then ns.Roster:ShowTooltip(row.item, row) end
    end, function(row)
        local name = row.item
        if name and name ~= ns.Sync:Me() then
            UI.ShowMenu(row, {
                { text = display(name), header = true },
                { text = "Whisper", func = function() whisper(name) end },
                { text = "Invite to group", func = function() Home.Invite(name) end },
                { text = "Challenge to a ranked duel", func = function() ns.Duels:Challenge(name) end },
            })
        end
    end)

    self:BuildBoard(page)
    self:BuildGroups(page)

    self.lootCard = card(page, "Recent loot", RIGHT_X, BODY_Y + HALF_H + GAP, RIGHT_W, HALF_H)
    rowList(self.lootCard, LINE_H, false, function(row)
        if not row.item or not GameTooltip then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, row.item.link)
        GameTooltip:Show()
    end)
end

function Home:Refresh()
    if not self.page then return end
    local inGuild = IsInGuild()
    self:RefreshHeader()

    local chatMode = self.leftMode == "chat"
    self.feedCard:SetShown(not chatMode)
    self.chatCard:SetShown(chatMode)
    for _, c in ipairs({ self.feedCard, self.chatCard }) do
        c.modeFeed:SetSelected(not chatMode)
        c.modeChat:SetSelected(chatMode)
    end
    fillRows(self.feedCard, G().feed, function(row, e)
        row.text:SetText(self:FeedText(e))
        row.right:SetText(Home.Ago(e.t))
    end, "Level-ups, achievements and new\nmembers show up here.")
    fillRows(self.chatCard, G().chat, function(row, m)
        row.text:SetText(colorName(m.name) .. ": " .. m.text)
        row.right:SetText(Home.Ago(m.t))
    end, "Guild chat you see is kept here.")

    local online = self:OnlineList()
    self.onlineCard.meta:SetText(inGuild and tostring(#online) or "")
    fillRows(self.onlineCard, online, function(row, name)
        local p = G().players[name]
        row.text:SetText(colorName(name))
        row.right:SetText(((p.zone and p.zone ~= "") and (p.zone .. "  ") or "") .. (p.level or ""))
    end, inGuild and "Nobody else online." or "")

    self:RefreshBoard()
    self:RefreshGroups()

    self.lootCard.meta:SetText("blue and up")
    fillRows(self.lootCard, G().seenLoot, function(row, e)
        row.text:SetText(("%s  %s"):format(colorName(e.player), e.link))
        row.right:SetText(Home.Ago(e.t))
    end, "Blue and better drops you or\nyour group get show up here.")
end

------------------------------------------------------------------------
-- Events and tab
------------------------------------------------------------------------
ns.On("CHAT_MSG_GUILD", function(text, sender) Home:OnChat(text, sender) end)
ns.On("CHAT_MSG_GUILD_ACHIEVEMENT", function(text, sender) Home:OnAchievement(text, sender) end)
ns.On("GUILD_MOTD", function() Home:Changed() end)
ns.On("CHAT_MSG_LOOT", function(msg) Home:OnLoot(ns.Loot:ParseChat(msg)) end)
ns.On("ENCOUNTER_LOOT_RECEIVED", function(_, _, itemLink, _, playerName) Home:OnLoot(playerName, itemLink) end)

-- Group finder times tick down while the page is open.
local function tick()
    if Home.page and Home.page:IsShown() then Home:RefreshGroups() end
    C_Timer.After(30, tick)
end
ns.On("PLAYER_LOGIN", function() C_Timer.After(30, tick) end)

ns.Editor:RegisterTab("home", "Home", 0,
    function(page) Home:Build(page) end,
    function()
        ns.Roster:RequestGuild()
        Home:Refresh()
    end)
