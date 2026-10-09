-- Pog Raid home: the dashboard /pog opens on. Useful to anyone in the guild.
--
-- Layout (902 x 642 page), three columns from the top:
--   [logo Guild name]  [Message board          ]  [Group finder       ]
--   [  message, 66  ]  [                       ]  [                   ]
--   [Activity       ]  [                       ]  [                   ]
--   [Online now     ]  [Guild chat             ]  [Recent loot        ]
local _, ns = ...
local UI = ns.UI

local Home = {}
ns.Home = Home

local PAD, GAP, TITLE_H = 12, 8, 30
local FRAME_W, FRAME_H = 902, ns.PAGE_H
local BODY_Y = TITLE_H
local BODY_H = FRAME_H - PAD - BODY_Y
local HALF_H = (BODY_H - GAP) / 2
-- the guild's own card tops the left column; Activity fills the rest of
-- that half, so Online now lines up with Guild chat and Recent loot
local HEADER_Y, HEADER_H = BODY_Y, 88
local FEED_Y, FEED_H = BODY_Y + HEADER_H + GAP, HALF_H - HEADER_H - GAP
local LEFT_W, MID_W = 262, 342
local LEFT_X = PAD
local MID_X = LEFT_X + LEFT_W + GAP
local RIGHT_X = MID_X + MID_W + GAP
local RIGHT_W = FRAME_W - PAD - RIGHT_X
local HEAD_H = 26
local LINE_H = 20
-- the guild card, like the game's guild window: the guild name, the message
-- of the day (up to two lines), "66 members, 4 online". No logo: it's in the
-- window's corner (Jake).
local TEXT_X = 14
-- the guild's banner hangs from the card's top-right edge, like the
-- Communities window's (its pennant, taller): background and border tinted
-- in the guild's colours, its emblem on it (the game fills these in: no
-- tabard gives the default horned helm). The text stops short of it.
local BANNER_W, BANNER_H, BANNER_R, BANNER_UP = 58, 76, 14, 4
local TEXT_W = LEFT_W - TEXT_X - BANNER_R - BANNER_W - 10

local BUCKETS = 12            -- members by level: 12 groups of 5 levels (1-5 ... 56-60)

Home.FEED_MAX = 60
Home.CHAT_MAX = 100
Home.LOOT_MAX = 100
Home.LOOT_MIN_QUALITY = 3   -- Recent loot shows blue (Rare) and up

Home.layout = { HEADER_H = HEADER_H, FEED_H = FEED_H, BODY_Y = BODY_Y, BODY_H = BODY_H, HALF_H = HALF_H, LEFT_X = LEFT_X,
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
-- client reports for a guild member (you and guildies in your group, anywhere;
-- pugs are skipped), kept apart from the raid loot log. The same item for the
-- same player within two minutes is one entry.
function Home:OnLoot(player, link)
    if not player or not link or secret(player) or secret(link) then return end
    local itemID = ns.Loot.ItemID(link)
    if not itemID then return end
    local quality = ns.Loot.Quality(link)
    if not quality or quality < Home.LOOT_MIN_QUALITY then return end
    local key = ns.Attendance:Key(player)
    if not ns.Loot.FromGuild(key) then return end
    local now = ns.Now()
    local list = G().seenLoot
    for _, e in ipairs(list) do
        if now - e.t > ns.Loot.DEDUPE_SECONDS then break end
        if e.player == key and e.itemID == itemID then return end
    end
    table.insert(list, 1, { t = now, player = key, itemID = itemID, link = link })
    for i = #list, Home.LOOT_MAX + 1, -1 do list[i] = nil end
    -- our own drops go to the whole guild (the game only shows each of us
    -- the loot of people in our group)
    if key == ns.Sync:Me() and ns.Sync:GuildName() then
        ns.Sync:Write("drops", { id = ns.NewId(), author = key, t = now, item = link, q = quality })
    end
    self:Changed()
end

-- Guildies' own blue-and-better drops, shared for a day.
Home.DROPS_KEEP = 86400

ns.Sync:Register({
    name = "drops", code = "l", order = 5,
    fields = { "item", "q" },
    numeric = { q = true },
    valid = function(rec)
        return rec.by == rec.author and type(rec.item) == "string" and #rec.item <= 250
            and rec.item:find("item:%d+") ~= nil and rec.q ~= nil and rec.q >= Home.LOOT_MIN_QUALITY and rec.q <= 7
    end,
    prune = function(store)
        local cutoff = ns.Now() - Home.DROPS_KEEP
        for id, rec in pairs(store) do
            if rec.t < cutoff then store[id] = nil end
        end
    end,
    expired = function(rec) return rec.t < ns.Now() - Home.DROPS_KEEP end,
    onChange = function() Home:Changed() end,
})

-- Recent loot: what we saw (us and our group) plus guildies' shared drops,
-- newest first, each drop once.
function Home:RecentLoot()
    local out, seen = {}, {}
    for _, e in ipairs(G().seenLoot) do
        -- drops saved before pugs were skipped stay hidden too
        if e.demo or ns.Loot.FromGuild(e.player) then
            out[#out + 1] = e
            local k = e.player .. ":" .. e.itemID
            seen[k] = seen[k] or {}
            table.insert(seen[k], e.t)
        end
    end
    for _, rec in pairs(ns.Sync:Store("drops") or {}) do
        local itemID = not rec.deleted and ns.Loot.ItemID(rec.item)
        if itemID then
            local dup = false
            for _, t in ipairs(seen[rec.author .. ":" .. itemID] or {}) do
                if math.abs(t - rec.t) <= ns.Loot.DEDUPE_SECONDS then dup = true end
            end
            if not dup then out[#out + 1] = { t = rec.t, player = rec.author, itemID = itemID, link = rec.item } end
        end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    for i = #out, Home.LOOT_MAX + 1, -1 do out[i] = nil end
    return out
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

-- The message of the day: the text GUILD_MOTD last brought (the game sends it
-- at login and on every change; asking right after a change can still give
-- the old one), else what the game has (also when the event brought a blank:
-- at login it can, before the message is in).
function Home:MOTD()
    if self.heardMOTD and self.heardMOTD ~= "" then return self.heardMOTD end
    local motd
    if C_GuildInfo and C_GuildInfo.GetMOTD then
        motd = C_GuildInfo.GetMOTD()
    elseif GetGuildRosterMOTD then
        motd = GetGuildRosterMOTD()
    end
    if type(motd) ~= "string" or secret(motd) then return "" end
    return motd
end

function Home:InfoText()
    if C_GuildInfo and C_GuildInfo.GetInfoText then return C_GuildInfo.GetInfoText() end
    return GetGuildInfoText and GetGuildInfoText() or ""
end

-- Guild members per level bucket (5 levels each), and how many there are.
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

-- The banner's counts: members, online.
function Home:StatValues()
    local _, members = self:LevelSpread()
    return members, #self:OnlineList()
end

-- "66 members, 4 online"
function Home:CountsText()
    local members, online = self:StatValues()
    return ("%d member%s, %d online"):format(members, members == 1 and "" or "s", online)
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
    UI.Line(line, 0.06)
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
        UI.Hover(hl, 0.05)
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

-- items are newest first. `bottomUp`: the newest on the bottom row, like the
-- game's chat window (a short list sits at the bottom; the wheel goes back).
local function fillRows(c, items, fill, emptyText, bottomUp)
    c.offset = math.max(0, math.min(c.offset, #items - c.visible))
    c.hint = c.hint or UI.ScrollHint(c, HEAD_H + 4, 4)
    c.hint:Set(bottomUp and math.max(0, #items - c.visible) - c.offset or c.offset, c.visible, #items)
    for i, row in ipairs(c.rows) do
        local item = items[bottomUp and (c.offset + c.visible - i + 1) or (i + c.offset)]
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
-- The guild card: logo, guild name, message of the day, counts
------------------------------------------------------------------------
function Home:BuildHeader(page)
    local h = CreateFrame("Frame", nil, page)
    h:SetPoint("TOPLEFT", LEFT_X, -HEADER_Y)
    h:SetSize(LEFT_W, HEADER_H)
    UI.Card(h)
    self.header = h

    -- the banner, drawn above the card's edge (its own frame level)
    local b = CreateFrame("Frame", nil, h)
    b:SetSize(BANNER_W, BANNER_H)
    b:SetPoint("TOPRIGHT", h, "TOPRIGHT", -BANNER_R, BANNER_UP)
    b:SetFrameLevel(h:GetFrameLevel() + 5)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetAllPoints()
    b.emblem = b:CreateTexture(nil, "ARTWORK")
    b.emblem:SetSize(BANNER_W - 14, BANNER_W - 14)
    b.emblem:SetPoint("TOP", 0, -10)
    local shown = UI.HasAtlas("communities-guildbanner-background")
    if shown then
        b.bg:SetAtlas("communities-guildbanner-background")
        b.border:SetAtlas("communities-guildbanner-border")
    end
    b:SetShown(shown)
    h.banner = b

    -- the guild's name, big (gold in the classic look), its message, its counts
    h.name = UI.Text(h, 22)
    h.name:SetPoint("TOPLEFT", TEXT_X, -11)
    h.name:SetWidth(TEXT_W)
    h.name:SetJustifyH("LEFT")
    h.name:SetWordWrap(false)
    if UI.classic then h.name:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) end
    -- the message gets two lines instead of being cut off; the counts follow it
    h.motd = UI.Text(h, 12)
    h.motd:SetPoint("TOPLEFT", TEXT_X, -39)
    h.motd:SetWidth(TEXT_W)
    h.motd:SetJustifyH("LEFT")
    h.motd:SetJustifyV("TOP")
    if h.motd.SetMaxLines then h.motd:SetMaxLines(2) end
    h.motd:SetTextColor(0.55, 0.9, 0.55)
    h.counts = UI.Text(h, 11)
    h.counts:SetPoint("TOPLEFT", h.motd, "BOTTOMLEFT", 0, -5)
    h.counts:SetJustifyH("LEFT")
    h.counts:SetTextColor(0.72, 0.72, 0.76)
    -- hovering the message shows it in full, with the guild info text
    local hover = CreateFrame("Frame", nil, h)
    hover:SetPoint("TOPLEFT", h.motd, "TOPLEFT", 0, 2)
    hover:SetSize(TEXT_W, 30)
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
    h.hover = hover

end

function Home:RefreshHeader()
    local h = self.header
    local inGuild = IsInGuild()
    -- the guild's name in angle brackets, as the game writes it under names
    h.name:SetText(inGuild and ("<" .. (GetGuildInfo("player") or "Your guild") .. ">") or "Pog Guild Tools")
    local motd = inGuild and self:MOTD() or ""
    h.motd:SetText(motd ~= "" and motd or (inGuild and "No message of the day." or "You are not in a guild."))
    -- a real message is green; the placeholder stays quiet
    if motd ~= "" then h.motd:SetTextColor(0.55, 0.9, 0.55) else h.motd:SetTextColor(0.5, 0.5, 0.55) end
    h.counts:SetText(inGuild and self:CountsText() or "")
    self:RefreshBanner()
end

-- The banner in the guild's colours and emblem (the game's own helper; it
-- shows the default horned helm when the guild has no tabard yet).
function Home:RefreshBanner()
    local b = self.header and self.header.banner
    if not b or not b:IsShown() then return end
    if SetLargeGuildTabardTextures and IsInGuild() then
        pcall(SetLargeGuildTabardTextures, "player", b.emblem, b.bg, b.border)
    end
    b.emblem:SetShown(IsInGuild() and true or false)
end

------------------------------------------------------------------------
-- Message board
------------------------------------------------------------------------
local POST_H = 58
local COMMENT_H = 46

function Home:BuildBoard(page)
    local c = card(page, "Message board", MID_X, BODY_Y, MID_W, HALF_H)
    self.boardCard = c
    self.boardArt = ns.Art and ns.Art.CardArt(c) -- our spec's remastered talent art, faint
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
    c.visible = math.floor((HALF_H - HEAD_H - 8) / POST_H)
    for i = 1, c.visible do
        local b = CreateFrame("Button", nil, c)
        b:SetHeight(POST_H)
        b:SetPoint("TOPLEFT", 2, -(HEAD_H + 4 + (i - 1) * POST_H))
        b:SetPoint("TOPRIGHT", -2, -(HEAD_H + 4 + (i - 1) * POST_H))
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        UI.Hover(hl, 0.05)
        local sep = b:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT", 8, 0)
        sep:SetPoint("BOTTOMRIGHT", -8, 0)
        sep:SetHeight(1)
        UI.Line(sep, 0.06)
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
    t.body:SetTextColor(UI.TEXT[1], UI.TEXT[2], UI.TEXT[3])
    local div = t:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", 8, -166)
    div:SetPoint("TOPRIGHT", -8, -166)
    div:SetHeight(1)
    UI.Line(div, 0.08)
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
    -- a post opens over guild chat, taking the whole column; the art fits again
    local h = post and BODY_H or HALF_H
    if c:GetHeight() ~= h then
        c:SetHeight(h)
        if self.boardArt then
            self.boardArt.key = nil
            self:RefreshArt()
        end
    end
    self.chatCard:SetShown(post == nil)
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
        t.count:SetText(#comments > 0 and "Comments" or "No comments yet")
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
            b.pin:SetText(p.pinned and "Pinned" or "")
            b.meta:SetText(("%s, %s ago"):format(colorName(p.author), Home.Ago(p.t)))
            b.snippet:SetText(p.body or "")
            b:Show()
        else
            b:Hide()
        end
    end
    if not IsInGuild() then
        c.empty:SetText("Join a guild to see its message board.")
    elseif canPost then
        c.empty:SetText("No posts yet.")
    else
        c.empty:SetText("No posts yet.")
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
    -- the card opens the LFG tab (a listing still opens its own menu)
    c:EnableMouse(true)
    c:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and ns.Editor.tabButtons.lfg then ns.Editor:ShowTab("lfg") end
    end)
    c:SetScript("OnEnter", function(f) f.bg:SetColorTexture(UI.CARD[1] + 0.03, UI.CARD[2] + 0.03, UI.CARD[3] + 0.03, UI.CARD[4] or 1) end)
    c:SetScript("OnLeave", function(f) f.bg:SetColorTexture(UI.CARD[1], UI.CARD[2], UI.CARD[3], UI.CARD[4] or 1) end)
    c.post = headButton(c, "Post group", 74, function() self:PostGroupDialog() end)
    rowList(c, 40, true, function(row) self:GroupTooltip(row) end, function(row) self:GroupMenu(row) end)
end

-- Post (or update) our group listing. `what` fills in "Doing what?" for a
-- new one (the Dungeons tab passes the dungeon). Also used by the Dungeons tab.
function Home:PostGroupDialog(what)
    local mine = ns.Social:MyGroup()
    UI.Compose({ heading = mine and "Update your group" or "Post a group", label1 = "Doing what?",
        labelMid = "Looking for", label2 = "Description (optional)",
        max1 = ns.Social.MAX_LFG, maxMid = ns.Social.MAX_LFG, max2 = ns.Social.MAX_LFG_DESC,
        text1 = mine and mine.what or what or "", textMid = mine and mine.need or "", text2 = mine and mine.desc or "",
        button = "Post" }, function(text, desc, need)
        ns.Social:PostGroup(text, need, desc)
        self:Refresh()
        if ns.Dungeons then ns.Dungeons:Changed() end
    end)
end

-- Clicking a listing (row.item): join, whisper, answer requests, close.
function Home:GroupMenu(row)
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
            color = { 0.95, 0.4, 0.4 }, func = function()
                ns.Social:Remove("lfg", g)
                self:Refresh()
                if ns.Dungeons then ns.Dungeons:Changed() end
            end }
    end
    UI.ShowMenu(row, menu)
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
    end, IsInGuild() and "No groups up." or "")
end

------------------------------------------------------------------------
-- Build + refresh
------------------------------------------------------------------------
function Home:Build(page)
    self.page = page
    self:BuildHeader(page)

    self.feedCard = card(page, "Activity", LEFT_X, FEED_Y, LEFT_W, FEED_H)
    rowList(self.feedCard, LINE_H, false, function(row)
        local e = row.item
        if e and e.kind == "ach" and GameTooltip then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, e.value)
            GameTooltip:Show()
        end
    end)

    self.onlineCard = card(page, "Online now", LEFT_X, BODY_Y + HALF_H + GAP, LEFT_W, HALF_H)
    rowList(self.onlineCard, LINE_H, false, function(row)
        if row.item then ns.Roster:ShowTooltip(row.item, row) end
    end, function(row)
        local name = row.item
        if name and name ~= ns.Sync:Me() then
            local menu = {
                { text = display(name), header = true },
                { text = "Whisper", func = function() whisper(name) end },
                { text = "Invite to group", func = function() Home.Invite(name) end },
                { text = "Challenge to a ranked duel", func = function() ns.Duels:Challenge(name) end },
            }
            if ns.Profiles:HasAddon(name) then
                table.insert(menu, 2, { text = "View profile", func = function() ns.Profiles:Open(name) end })
            end
            UI.ShowMenu(row, menu)
        end
    end)

    self:BuildBoard(page)
    -- guild chat under the message board, newest at the bottom; the wheel goes back
    self.chatCard = card(page, "Guild chat", MID_X, BODY_Y + HALF_H + GAP, MID_W, HALF_H)
    rowList(self.chatCard, LINE_H, false, function(row)
        if not row.item or not GameTooltip then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(display(row.item.name), classColor(row.item.name))
        GameTooltip:AddLine(row.item.text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.chatCard:SetScript("OnMouseWheel", function(c, d)
        c.offset = c.offset + d * 2
        Home:Refresh()
    end)
    self:BuildGroups(page)

    self.lootCard = card(page, "Recent loot", RIGHT_X, BODY_Y + HALF_H + GAP, RIGHT_W, HALF_H)
    rowList(self.lootCard, LINE_H, false, function(row)
        if not row.item or not GameTooltip then return end
        UI.ItemTip(row, row.item.link)
        GameTooltip:Show()
    end)
end

-- The message board shows our current spec's remastered talent art (the
-- classic picture where there's no remastered one; our first tree before we
-- pick a spec).
function Home:RefreshArt()
    if not self.boardArt then return end
    local class = select(2, UnitClass("player"))
    self.boardArt:Show(ns.Art.ModernTreeArt(class, ns.Art.MySpec() or 1))
end

function Home:Refresh()
    if not self.page then return end
    local inGuild = IsInGuild()
    self:RefreshHeader()

    fillRows(self.feedCard, G().feed, function(row, e)
        row.text:SetText(self:FeedText(e))
        row.right:SetText(Home.Ago(e.t))
    end, "Nothing yet.")
    fillRows(self.chatCard, G().chat, function(row, m)
        row.text:SetText(colorName(m.name) .. ": " .. m.text)
        row.right:SetText(Home.Ago(m.t))
    end, "No guild chat yet.", true)

    local online = self:OnlineList()
    fillRows(self.onlineCard, online, function(row, name)
        local p = G().players[name]
        row.text:SetText(colorName(name))
        row.right:SetText(((p.zone and p.zone ~= "") and (p.zone .. "  ") or "") .. (p.level or ""))
    end, inGuild and "Nobody else online." or "")

    self:RefreshBoard()
    self:RefreshGroups()

    self.lootCard.meta:SetText("")
    fillRows(self.lootCard, self:RecentLoot(), function(row, e)
        row.text:SetText(("%s  %s"):format(colorName(e.player), e.link))
        row.right:SetText(Home.Ago(e.t))
    end, "No drops yet.")
end

------------------------------------------------------------------------
-- Events and tab
------------------------------------------------------------------------
ns.On("CHAT_MSG_GUILD", function(text, sender) Home:OnChat(text, sender) end)
ns.On("CHAT_MSG_GUILD_ACHIEVEMENT", function(text, sender) Home:OnAchievement(text, sender) end)
-- the tabard can change (or load late): repaint the banner
ns.On("PLAYER_GUILD_UPDATE", function() Home:RefreshBanner() end)
ns.On("GUILD_MOTD", function(motd)
    if type(motd) == "string" and not secret(motd) then Home.heardMOTD = motd end
    Home:Changed()
end)
ns.On("CHAT_MSG_LOOT", function(msg) Home:OnLoot(ns.Loot:ParseChat(msg)) end)
ns.On("ENCOUNTER_LOOT_RECEIVED", function(_, _, itemLink, _, playerName) Home:OnLoot(playerName, itemLink) end)

-- Group finder times tick down while the page is open.
local function tick()
    if Home.page and Home.page:IsShown() then Home:RefreshGroups() end
    C_Timer.After(30, tick)
end
ns.On("PLAYER_LOGIN", function() C_Timer.After(30, tick) end)

ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if (unit == nil or unit == "player") and Home.page and Home.page:IsShown() then Home:RefreshArt() end
end)

ns.Editor:RegisterTab("home", "Home", 0,
    function(page) Home:Build(page) end,
    function()
        ns.Roster:RequestGuild()
        Home:RefreshArt()
        Home:Refresh()
    end)
