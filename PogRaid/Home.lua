-- Pog Raid home: the dashboard /pog opens on. Useful to anyone in the guild.
--
-- Layout (902 x 642 page), three columns from the top:
--   [logo Guild name]  [Message board          ]  [Group finder       ]
--   [  message, 66  ]  [                       ]  [                   ]
--   [Activity       ]  [Chats (0.16.8)         ]  [                   ]
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
-- the guild's own card tops the left column; Online now fills the rest of
-- that half (who's on is what Home is for: UI experiment), and Activity
-- lines up with Guild chat and Recent loot
local HEADER_Y, HEADER_H = BODY_Y, 74 -- just the name and two lines of message (Activity gets the rest)
local FEED_Y, FEED_H = BODY_Y + HEADER_H + GAP, HALF_H - HEADER_H - GAP
local LEFT_W, MID_W = 262, 342
local LEFT_X = PAD
local MID_X = LEFT_X + LEFT_W + GAP
local RIGHT_X = MID_X + MID_W + GAP
local RIGHT_W = FRAME_W - PAD - RIGHT_X
local HEAD_H = 26
local LINE_H = 20
-- Chats (Chat.lua) has the bottom third of what was all Message board (Jake):
-- three of our chats, the newest first, with what's unread. The board keeps
-- the rest; the two together end where the cards beside them do.
local CHATS_ROWS = 3
local CHATS_H = HEAD_H + 8 + CHATS_ROWS * LINE_H
local BOARD_H = HALF_H - GAP - CHATS_H
-- the guild card, like the game's guild window: the guild name and the
-- message of the day under it (up to two lines, starting "MOTD:" so
-- it reads as one, Jake), centred both ways (Jake). No
-- logo: it's in the window's corner (Jake); no banner, no member counts
-- (Jake didn't like them).
local TEXT_X = 14
local TEXT_W = LEFT_W - 2 * TEXT_X
local NAME_H, MOTD_GAP = 22, 6
Home.MOTD_LABEL = "MOTD: "


Home.FEED_MAX = 60
Home.CHAT_MAX = 100
Home.LOOT_MAX = 100
Home.LOOT_MIN_QUALITY = 3   -- Recent loot shows blue (Rare) and up
Home.FLASH_TIME = 1.2       -- a new chat line's glow

Home.layout = { HEADER_H = HEADER_H, FEED_H = FEED_H, BODY_Y = BODY_Y, BODY_H = BODY_H, HALF_H = HALF_H, LEFT_X = LEFT_X,
    BOARD_H = BOARD_H, CHATS_H = CHATS_H, CHATS_ROWS = CHATS_ROWS, GAP = GAP,
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
-- `away`: it happened while we weren't looking (found at login), so it has no time to show.
function Home:AddFeed(kind, name, value, away)
    local feed = G().feed
    table.insert(feed, 1, { t = ns.Now(), kind = kind, name = name, value = value, away = away or nil })
    for i = #feed, Home.FEED_MAX + 1, -1 do feed[i] = nil end
    self:Changed()
end

-- Called by the roster scan with what changed since the last scan.
function Home:OnGuildScan(levels, joined, left, catchUp)
    for _, x in ipairs(levels) do self:AddFeed("level", x.name, x.level, x.away) end
    for _, n in ipairs(joined) do self:AddFeed("join", n, nil, catchUp) end
    for _, n in ipairs(left) do self:AddFeed("leave", n, nil, catchUp) end
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
    self.chatFlash = true
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
    -- One record per item: getting it again (a dungeon farmed all night) renews
    -- that record, at most once an hour, instead of adding another. One player's
    -- farming was most of what the guild's addons had to pass around.
    if key == ns.Sync:Me() and ns.Sync:GuildName() then
        local id = key .. ":" .. itemID
        local cur = (ns.Sync:Store("drops") or {})[id]
        if not cur or cur.deleted or now - cur.t >= Home.DROP_RENEW then
            ns.Sync:Write("drops", { id = id, author = key, t = now, item = link, q = quality })
        end
    end
    self:Changed()
end

-- Guildies' own blue-and-better drops, shared for a day.
Home.DROPS_KEEP = 86400
Home.DROP_RENEW = 3600     -- the same item again renews its record this often at most
Home.LOOT_PER_PLAYER = 8   -- Recent loot shows this many of one player's drops

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
    expired = function(rec, now) return rec.t < (now or ns.Now()) - Home.DROPS_KEEP end,
    onChange = function() Home:Changed() end,
})

-- Recent loot: what we saw (us and our group) plus guildies' shared drops,
-- newest first, each drop once.
-- What we saw ourselves plus what guildies shared. Each player's item shows
-- once (the latest time they got it), and one player at most LOOT_PER_PLAYER
-- times, so someone farming a dungeon doesn't push everyone else off the card.
function Home:RecentLoot()
    local latest = {}
    local function add(e)
        local k = e.player .. ":" .. e.itemID
        if not latest[k] or e.t > latest[k].t then latest[k] = e end
    end
    for _, e in ipairs(G().seenLoot) do
        -- drops saved before pugs were skipped stay hidden too
        if e.demo or ns.Loot.FromGuild(e.player) then add(e) end
    end
    for _, rec in pairs(ns.Sync:Store("drops") or {}) do
        local itemID = not rec.deleted and ns.Loot.ItemID(rec.item)
        if itemID then add({ t = rec.t, player = rec.author, itemID = itemID, link = rec.item }) end
    end
    local all = {}
    for _, e in pairs(latest) do all[#all + 1] = e end
    table.sort(all, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        if a.player ~= b.player then return a.player < b.player end
        return a.itemID < b.itemID
    end)
    local out, shown = {}, {}
    for _, e in ipairs(all) do
        shown[e.player] = (shown[e.player] or 0) + 1
        if shown[e.player] <= Home.LOOT_PER_PLAYER and #out < Home.LOOT_MAX then out[#out + 1] = e end
    end
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

local function byLevel(a, b)
    local la, lb = G().players[a].level or 0, G().players[b].level or 0
    if la ~= lb then return la > lb end
    return a < b
end

function Home:OnlineList()
    local out = {}
    for name in pairs(ns.Roster.online) do
        if G().players[name] then out[#out + 1] = name end
    end
    table.sort(out, byLevel)
    return out
end

-- Show offline (Jake): everyone online as before, then the rest of the guild,
-- highest level first, at the level they were last seen at.
function Home:ShowingOffline() return ns.db.settings.homeOffline == true end

function Home:MemberList()
    local out = self:OnlineList()
    if not self:ShowingOffline() then return out end
    local offline = {}
    for name, p in pairs(G().players) do
        if p.inGuild and not ns.Roster.online[name] then offline[#offline + 1] = name end
    end
    table.sort(offline, byLevel)
    for _, name in ipairs(offline) do out[#out + 1] = name end
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


------------------------------------------------------------------------
-- UI building blocks
------------------------------------------------------------------------
local function card(page, title, x, y, w, h)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", x, -y)
    c:SetSize(w, h)
    UI.Card(c)
    UI.Parchment(c) -- every Home card on faint parchment, like the profile's About me (Jake)
    c.title = UI.SectionTitle(c, title)
    c.title:SetPoint("LEFT", c, "TOPLEFT", 10, -UI.HeadMid(HEAD_H))
    c.meta = UI.Text(c, 10)
    c.meta:SetPoint("RIGHT", c, "TOPRIGHT", -10, -UI.HeadMid(HEAD_H))
    c.meta:SetTextColor(0.5, 0.5, 0.55)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    UI.Line(line, 0.06)
    c.headLine = line
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
    b:SetPoint("RIGHT", c, "TOPRIGHT", -UI.HeadInset(), -UI.HeadMid(HEAD_H))
    return b
end

-- Scrolling rows inside a card. `two` adds a second, smaller line; `pic` a
-- small picture before the text (row.pic: a portrait or an item icon).
local PIC = 16
local function rowList(c, rowH, two, onEnter, onClick, pic)
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
        if pic then
            row.pic = row:CreateTexture(nil, "ARTWORK")
            row.pic:SetSize(PIC, PIC)
            row.pic:SetPoint("LEFT", 8, 0)
            row.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row.text = UI.Text(row, two and 12 or 11)
        row.text:SetPoint("TOPLEFT", pic and (8 + PIC + 6) or 8, two and -4 or -(rowH - 11) / 2)
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
    UI.Parchment(h)
    self.header = h

    -- the guild's name, big (gold in the classic look), placed by RefreshHeader
    h.name = UI.Text(h, NAME_H)
    h.name:SetHeight(NAME_H)
    h.name:SetWidth(TEXT_W)
    h.name:SetJustifyH("CENTER")
    h.name:SetWordWrap(false)
    if UI.classic then h.name:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3]) end
    -- the message across the card under it, two lines instead of being cut
    -- off, balanced so a last word never sits alone (RefreshHeader)
    h.motd = UI.Text(h, 12)
    h.motd:SetPoint("TOP", h.name, "BOTTOM", 0, -MOTD_GAP)
    h.motd:SetWidth(TEXT_W)
    h.motd:SetJustifyH("CENTER")
    h.motd:SetJustifyV("TOP")
    if h.motd.SetMaxLines then h.motd:SetMaxLines(2) end
    h.motd:SetTextColor(0.55, 0.9, 0.55)
    -- hovering the message shows it in full, with the guild info text
    local hover = CreateFrame("Frame", nil, h)
    hover:SetPoint("TOPLEFT", h.motd, "TOPLEFT", 0, 2)
    hover:SetPoint("BOTTOMRIGHT", h.motd, "BOTTOMRIGHT", 0, -2)
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
    -- a real message starts with its label in the title colour, like the game's chat line
    local t = UI.TITLE
    h.motd:SetText(motd ~= "" and (("|cff%02x%02x%02x%s|r"):format(t[1] * 255, t[2] * 255, t[3] * 255, Home.MOTD_LABEL) .. motd)
        or (inGuild and "No message of the day." or "You are not in a guild."))
    -- a real message is green; the placeholder stays quiet
    if motd ~= "" then h.motd:SetTextColor(0.55, 0.9, 0.55) else h.motd:SetTextColor(0.5, 0.5, 0.55) end
    -- two lines share the words evenly (Jake saw "Pog" alone on the second)
    h.motd:SetWidth(TEXT_W)
    local full = (h.motd.GetUnboundedStringWidth and h.motd:GetUnboundedStringWidth()) or h.motd:GetStringWidth()
    if full > TEXT_W then h.motd:SetWidth(math.min(TEXT_W, math.ceil(full / 2) + 24)) end
    -- the name and message centred top to bottom (one line of message or two)
    local block = NAME_H + MOTD_GAP + math.min(h.motd:GetStringHeight() or 12, 30)
    h.name:ClearAllPoints()
    h.name:SetPoint("TOPLEFT", TEXT_X, -math.floor((HEADER_H - block) / 2))
end

------------------------------------------------------------------------
-- Message board
------------------------------------------------------------------------
local POST_H = 58
local COMMENT_H = 46

function Home:BuildBoard(page)
    local c = card(page, "Message board", MID_X, BODY_Y, MID_W, BOARD_H)
    self.boardCard = c
    if c.parchment then c.parchment:Hide() end -- the art instead (they'd share a layer)
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
    c.visible = math.floor((BOARD_H - HEAD_H - 8) / POST_H)
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
    c.back:SetPoint("LEFT", c, "TOPLEFT", UI.HeadInset(), -UI.HeadMid(HEAD_H))
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

-- Chats: our chats (Chat.lua) under the message board. A row is a chat: its
-- picture, who or what it is, its last line, and how many lines are unread
-- (else when it last spoke). Click one to open it; New chat picks people.
-- With none yet, a button to start one (like LFM's).
function Home:BuildChats(page)
    local c = card(page, "Chats", MID_X, BODY_Y + BOARD_H + GAP, MID_W, CHATS_H)
    self.chatsCard = c
    c.new = headButton(c, "New chat", 70, function() ns.Chat:StartNew() end)
    rowList(c, LINE_H, false, nil, function(row)
        if row.item then ns.Chat:Open(row.item, true) end
    end, true)
    -- (the empty line and its button share the three rows' height evenly)
    c.empty:ClearAllPoints()
    c.empty:SetPoint("TOP", 0, -(HEAD_H + 12))
    c.cta = UI.Button(c, "Start a chat", 120, 24, function() ns.Chat:StartNew() end)
    c.cta:SetPoint("TOP", c.empty, "BOTTOM", 0, -8)
    c.cta:Hide()
end

function Home:RefreshChats()
    local c = self.chatsCard
    if not c then return end
    local Chat = ns.Chat
    local on = IsInGuild() and Chat:Enabled()
    local chats = on and Chat:List() or {}
    fillRows(c, chats, function(row, chat)
        local unread = chat.unread or 0
        row.pic:SetTexture(Chat:Picture(chat))
        local preview = Chat:Preview(chat)
        row.text:SetText(Chat:Title(chat) .. (preview and ("  |cff8a8a92" .. preview .. "|r") or ""))
        if unread > 0 then
            row.right:SetText(tostring(math.min(unread, 99)))
            row.right:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
        else
            row.right:SetText(Home.Ago(chat.last))
            row.right:SetTextColor(0.5, 0.5, 0.55)
        end
    end, not IsInGuild() and "" or on and "no chats atm" or "chat is turned off in Settings")
    c.new:SetShown(on and chats[1] ~= nil)
    c.cta:SetShown(on and chats[1] == nil)
end

-- A chat line came, went or was read (Chat.lua): just this card.
function Home:ChatsChanged()
    if self.page and self.page:IsShown() then self:RefreshChats() end
end

function Home:RefreshBoard()
    local c = self.boardCard
    local canPost = ns.Social:CanPost()
    local post = self:OpenPost()
    -- a post opens over Chats and guild chat, taking the whole column; the art fits again
    local h = post and BODY_H or BOARD_H
    if c:GetHeight() ~= h then
        c:SetHeight(h)
        if self.boardArt then
            self.boardArt.key = nil
            self:RefreshArt()
        end
    end
    self.chatCard:SetShown(post == nil)
    self.chatsCard:SetShown(post == nil)
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
    if self.boardArt then self.boardArt:SetSparse(#posts == 0) end -- an empty card shows its whole picture
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

-- LFM (groups forming) and LFG (players looking): two cards stacked in the
-- right column's top half, the same height (Jake). Either opens the LFG tab
-- when clicked outside a row; each scrolls on its own.
function Home:BuildGroups(page)
    local h = (HALF_H - GAP) / 2
    local function groupCard(title, y)
        local c = card(page, title, RIGHT_X, y, RIGHT_W, h)
        c:EnableMouse(true)
        c:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and ns.Editor.tabButtons.lfg then ns.Editor:ShowTab("lfg") end
        end)
        c:SetScript("OnEnter", function(f) f.bg:SetColorTexture(UI.CARD[1] + 0.03, UI.CARD[2] + 0.03, UI.CARD[3] + 0.03, UI.CARD[4] or 1) end)
        c:SetScript("OnLeave", function(f) f.bg:SetColorTexture(UI.CARD[1], UI.CARD[2], UI.CARD[3], UI.CARD[4] or 1) end)
        rowList(c, 40, true, function(row) self:GroupTooltip(row) end, function(row) self:GroupMenu(row) end)
        c:EnableMouseWheel(true)
        c:SetScript("OnMouseWheel", function(_, d)
            c.offset = c.offset - d
            self:RefreshGroups()
        end)
        return c
    end
    local c = groupCard("LFM", BODY_Y)
    self.groupCard = c
    c.lfm = c
    c.post = headButton(c, "Post group", 74, function() self:PostGroupDialog() end)
    c.lfg = groupCard("LFG", BODY_Y + h + GAP)
    self.lfgCard = c.lfg
    -- no groups: the next step, not just a grey line
    c.cta = UI.Button(c, "Post a group", 120, 24, function() self:PostGroupDialog() end)
    c.cta:SetPoint("TOP", c.empty, "BOTTOM", 0, -8)
    c.cta:Hide()
    -- nobody looking: list yourself (picking dungeons is on the LFG tab; Jake)
    c.listMe = UI.Button(c.lfg, "List yourself", 120, 24, function()
        if ns.Editor.tabButtons.lfg then ns.Editor:ShowTab("lfg") end
    end)
    c.listMe:SetPoint("TOP", c.lfg.empty, "BOTTOM", 0, -8)
    c.listMe:Hide()
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
    if g.looking then ns.Editor:ShowTab("lfg") return end
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
    if g.looking then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(colorName(g.name) .. " is looking for a group", 1, 1, 1)
        GameTooltip:AddLine(table.concat(g.list, ", "), 0.8, 0.8, 0.85, true)
        if g.note and g.note ~= "" then GameTooltip:AddLine(g.note, 0.7, 0.7, 0.75, true) end
        GameTooltip:AddLine("Click for the LFG tab", 0.5, 0.5, 0.55)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(g.what, 1, 1, 1)
    GameTooltip:AddLine("Posted by " .. colorName(g.author), 0.8, 0.8, 0.85)
    if g.need then GameTooltip:AddDoubleLine("Looking for", g.need, 0.6, 0.6, 0.65, 1, 1, 1) end
    if g.size then
        GameTooltip:AddDoubleLine("Group", g.size .. "/" .. (g.max or 5) .. (ns.Social:IsFull(g) and ", full" or ""),
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
    -- LFG: everyone saying they're up for a dungeon, ours first: name and
    -- level, their dungeons, online (no role icons here: Jake, too much)
    local lookers = {}
    for _, l in ipairs(ns.Dungeons and ns.Dungeons:Looking() or {}) do
        l.looking = true
        lookers[#lookers + 1] = l
    end
    fillRows(c.lfg, lookers, function(row, l)
        row.text:SetText(colorName(l.name) .. (l.level and ("  |cff8a8a92" .. l.level .. "|r") or ""))
        row.sub:SetText(table.concat(l.list, ", "))
        row.right:SetText(l.online and "online" or "offline")
        if l.online then row.right:SetTextColor(0.4, 0.85, 0.45) else row.right:SetTextColor(0.5, 0.5, 0.55) end
        row.right2:SetText("")
    end, IsInGuild() and "nobody looking atm" or "")
    -- LFM: the groups forming
    fillRows(c.lfm, groups, function(row, g)
        row.text:SetText(g.what)
        local full = ns.Social:IsFull(g)
        row.right:SetText(g.size and ((g.size .. "/" .. (g.max or 5)) .. (full and " full" or "")) or "")
        row.right:SetTextColor(full and 0.95 or 0.5, full and 0.45 or 0.85, full and 0.4 or 0.55)
        local left = math.max(0, math.ceil((g.exp - ns.Now()) / 60))
        local status = left .. "m left"
        if ns.Social.requested[g.id] then status = "requested" end
        if g.author == ns.Sync:Me() and ns.Social:RequestCount() > 0 then
            status = ns.Social:RequestCount() .. (ns.Social:RequestCount() == 1 and " request" or " requests")
        end
        row.right2:SetText(status)
        row.sub:SetText(colorName(g.author) .. (g.need and ("  |cff9a9aa2needs " .. g.need .. "|r") or ""))
    end, IsInGuild() and "no groups atm" or "") -- (all lowercase, Jake)
    c.cta:SetShown(IsInGuild() and #groups == 0)
    c.listMe:SetShown(IsInGuild() and #lookers == 0)
    c.post:SetShown(IsInGuild() and #groups > 0) -- (no groups: the red button says it, Jake)
end

------------------------------------------------------------------------
-- Build + refresh
------------------------------------------------------------------------
function Home:Build(page)
    self.page = page
    self:BuildHeader(page)

    self.feedCard = card(page, "Activity", LEFT_X, BODY_Y + HALF_H + GAP, LEFT_W, HALF_H)
    rowList(self.feedCard, LINE_H, false, function(row)
        local e = row.item
        if e and e.kind == "ach" and GameTooltip then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, e.value)
            GameTooltip:Show()
        end
    end, nil, true)

    self.onlineCard = card(page, "Online now", LEFT_X, FEED_Y, LEFT_W, FEED_H)
    self.onlineCard.toggle = headButton(self.onlineCard, "Show offline", 84, function()
        ns.db.settings.homeOffline = not self:ShowingOffline() or nil
        self.onlineCard.offset = 0
        self:Refresh()
    end)
    rowList(self.onlineCard, LINE_H, false, function(row)
        if row.item then ns.Roster:ShowTooltip(row.item, row) end
    end, function(row)
        local name = row.item
        -- someone offline can't be whispered or invited: just their profile
        if name and not ns.Roster.online[name] then
            if ns.Profiles:HasAddon(name) then
                UI.ShowMenu(row, { { text = display(name), header = true },
                    { text = "View profile", func = function() ns.Profiles:Open(name) end } })
            end
        elseif name and name ~= ns.Sync:Me() then
            local menu = {
                { text = display(name), header = true },
                { text = "Whisper", func = function() whisper(name) end },
                { text = "Invite to group", func = function() Home.Invite(name) end },
                { text = "Challenge to a ranked duel", func = function() ns.Duels:Challenge(name) end },
            }
            if ns.Chat:CanChat(name) then
                table.insert(menu, 3, { text = "Chat", func = function() ns.Chat:OpenWith({ name }) end })
            end
            if ns.Profiles:HasAddon(name) then
                table.insert(menu, 2, { text = "View profile", func = function() ns.Profiles:Open(name) end })
            end
            UI.ShowMenu(row, menu)
        end
    end, true)

    self:BuildBoard(page)
    self:BuildChats(page)
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
    end, nil, true)
end

-- The message board shows our current spec's remastered talent art (the
-- classic picture where there's no remastered one; our first tree before we
-- pick a spec).
function Home:RefreshArt()
    if not self.boardArt then return end
    local class = select(2, UnitClass("player"))
    self.boardArt:Show(ns.Art.ModernTreeArt(class, ns.Art.MySpec() or 1))
end

-- A member's picture for a row: their profile portrait, else their class's icon.
function Home.Portrait(name)
    return ns.Profiles and ns.Profiles.Portrait and ns.Profiles:Portrait(name) or 134400
end

function Home.ItemIcon(itemID)
    if itemID and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    return 134400 -- the question mark
end

function Home:Refresh()
    if not self.page then return end
    local inGuild = IsInGuild()
    self:RefreshHeader()

    fillRows(self.feedCard, G().feed, function(row, e)
        row.pic:SetTexture(Home.Portrait(e.name))
        row.text:SetText(self:FeedText(e))
        row.right:SetText(e.away and "" or Home.Ago(e.t))
    end, "Nothing yet.")
    fillRows(self.chatCard, G().chat, function(row, m)
        row.text:SetText(colorName(m.name) .. ": " .. m.text)
        row.right:SetText(Home.Ago(m.t))
    end, "No guild chat yet.", true)
    -- the newest line (at the bottom) glows for a moment when it arrives
    local newest = self.chatCard.rows[self.chatCard.visible]
    if self.chatFlash and newest and newest:IsShown() and self.chatCard.offset == 0 then
        if not newest.flash then
            newest.flash = newest:CreateTexture(nil, "BACKGROUND")
            newest.flash:SetAllPoints()
            UI.SelBar(newest.flash)
        end
        UI.Fade(newest.flash, 1, 0, Home.FLASH_TIME)
    end
    self.chatFlash = nil

    local offline = self:ShowingOffline()
    self.onlineCard.toggle:SetLabel(offline and "Hide offline" or "Show offline")
    self.onlineCard.toggle:SetShown(inGuild)
    self:RefreshChats()
    fillRows(self.onlineCard, self:MemberList(), function(row, name)
        local p = G().players[name]
        row.pic:SetTexture(Home.Portrait(name))
        if ns.Roster.online[name] then
            row.text:SetText(colorName(name))
            row.pic:SetDesaturated(false)
            row.pic:SetAlpha(1)
            row.right:SetText(((p.zone and p.zone ~= "") and (p.zone .. "  ") or "") .. (p.level or ""))
        else
            -- offline: greyed, with the level they were last seen at
            row.text:SetText(("|cff7a7a82%s|r"):format(display(name)))
            row.pic:SetDesaturated(true)
            row.pic:SetAlpha(0.6)
            row.right:SetText(p.level and tostring(p.level) or "")
        end
    end, inGuild and (offline and "Nobody in the guild yet." or "Nobody else online.") or "")

    self:RefreshBoard()
    self:RefreshGroups()

    self.lootCard.meta:SetText("")
    fillRows(self.lootCard, self:RecentLoot(), function(row, e)
        row.pic:SetTexture(Home.ItemIcon(e.itemID))
        row.text:SetText(("%s  %s"):format(colorName(e.player), e.link))
        row.right:SetText(Home.Ago(e.t))
    end, "No drops yet.")
end

------------------------------------------------------------------------
-- Events and tab
------------------------------------------------------------------------
ns.On("CHAT_MSG_GUILD", function(text, sender) Home:OnChat(text, sender) end)
ns.On("CHAT_MSG_GUILD_ACHIEVEMENT", function(text, sender) Home:OnAchievement(text, sender) end)
-- the guild's name can load late
ns.On("PLAYER_GUILD_UPDATE", function() if Home.header then Home:RefreshHeader() end end)
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
