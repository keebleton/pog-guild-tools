-- Pog Raid social: the guild message board (officer posts, anyone comments)
-- and the group finder. Both are shared through Sync, so every guild member
-- running Pog Raid sees the same thing.
local _, ns = ...

local Social = {}
ns.Social = Social

Social.MAX_TITLE = 60
Social.MAX_BODY = 600
Social.MAX_COMMENT = 300
Social.MAX_LFG = 50
Social.MAX_LFG_DESC = 200
Social.POST_KEEP = 60 * 86400      -- unpinned posts (and their comments) drop after 60 days
Social.LFG_MINUTES = 45
Social.LFG_KEEP = 3600             -- expired listings are forgotten an hour later

local Sync = ns.Sync

local function clean(s, max)
    return ns.Codec.CleanText(s, max)
end

local function changed()
    if ns.Home then ns.Home:Changed() end
end

local function sane(rec, fields)
    for f, max in pairs(fields) do
        local v = rec[f]
        if v ~= nil and (type(v) ~= "string" or #v > max) then return false end
    end
    return true
end

------------------------------------------------------------------------
-- Collections
------------------------------------------------------------------------
Sync:Register({
    name = "posts", code = "p", order = 1,
    fields = { "title", "body", "pinned" },
    bool = { pinned = true },
    -- only officers post, pin or delete posts
    valid = function(rec)
        return sane(rec, { title = Social.MAX_TITLE, body = Social.MAX_BODY }) and Sync:IsOfficer(rec.by)
            and (rec.deleted or (rec.title and rec.title ~= ""))
    end,
    prune = function(store)
        local cutoff = ns.Now() - Social.POST_KEEP
        for id, rec in pairs(store) do
            if not rec.pinned and rec.t < cutoff then store[id] = nil end
        end
    end,
    expired = function(rec) return not rec.pinned and rec.t < ns.Now() - Social.POST_KEEP end,
    onChange = changed,
})

Sync:Register({
    name = "comments", code = "c", order = 2,
    fields = { "post", "body" },
    -- anyone comments; only the commenter or an officer changes it
    valid = function(rec)
        return sane(rec, { body = Social.MAX_COMMENT, post = 80 }) and rec.post ~= nil
            and (rec.by == rec.author or Sync:IsOfficer(rec.by)) and (rec.deleted or (rec.body and rec.body ~= ""))
    end,
    prune = function(store)
        local posts = Sync:Store("posts") or {}
        local cutoff = ns.Now() - Social.POST_KEEP
        for id, rec in pairs(store) do
            local post = posts[rec.post]
            if (not post and rec.t < cutoff) or (post and post.deleted and rec.t < cutoff) then store[id] = nil end
        end
    end,
    onChange = changed,
})

Sync:Register({
    name = "lfg", code = "g", order = 1,
    -- `roles`: one letter per member (T, H, D), tanks first, for the group
    -- finder's role icons (Jake); older versions ignore it
    fields = { "what", "need", "exp", "size", "max", "desc", "roles" },
    numeric = { exp = true, size = true, max = true },
    valid = function(rec)
        return sane(rec, { what = Social.MAX_LFG, need = Social.MAX_LFG, desc = Social.MAX_LFG_DESC }) and rec.exp ~= nil
            and (rec.roles == nil or (type(rec.roles) == "string" and #rec.roles <= 40 and rec.roles:match("^[THD]+$") ~= nil))
            and rec.exp - rec.t <= 3 * 3600 and (rec.by == rec.author or Sync:IsOfficer(rec.by))
            and (rec.deleted or (rec.what and rec.what ~= ""))
    end,
    prune = function(store)
        local cutoff = ns.Now() - Social.LFG_KEEP
        for id, rec in pairs(store) do
            if rec.exp < cutoff then store[id] = nil end
        end
    end,
    expired = function(rec) return rec.exp < ns.Now() end,
    perRecord = true,
    onChange = function(rec)
        changed()
        if ns.GroupToast then ns.GroupToast:Consider(rec) end
    end,
})

------------------------------------------------------------------------
-- Board
------------------------------------------------------------------------
local function list(name, keep)
    local out = {}
    for _, rec in pairs(Sync:Store(name) or {}) do
        if not rec.deleted and (not keep or keep(rec)) then out[#out + 1] = rec end
    end
    return out
end

function Social:Posts()
    local posts = list("posts")
    table.sort(posts, function(a, b)
        if (a.pinned or false) ~= (b.pinned or false) then return a.pinned == true end
        if a.t ~= b.t then return a.t > b.t end
        return a.id > b.id
    end)
    return posts
end

function Social:Comments(postId)
    local out = list("comments", function(c) return c.post == postId end)
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.id < b.id
    end)
    return out
end

function Social:CanPost()
    return Sync:GuildName() ~= nil and Sync:AmOfficer()
end

function Social:CanRemove(rec)
    return rec.author == Sync:Me() or Sync:AmOfficer()
end

function Social:NewPost(title, body)
    title, body = clean(title, Social.MAX_TITLE), clean(body, Social.MAX_BODY)
    if title == "" or not self:CanPost() then return nil end
    return Sync:Write("posts", { id = ns.NewId(), author = Sync:Me(), t = ns.Now(), title = title,
        body = body ~= "" and body or nil })
end

local function copy(rec)
    local c = {}
    for k, v in pairs(rec) do c[k] = v end
    return c
end

function Social:SetPinned(post, pinned)
    if not self:CanPost() then return end
    local c = copy(post)
    c.pinned = pinned or nil
    return Sync:Write("posts", c)
end

function Social:Remove(name, rec)
    if not self:CanRemove(rec) then return end
    local c = copy(rec)
    c.deleted = true
    if name == "posts" then c.body = nil end
    if name == "comments" then c.body = nil end
    return Sync:Write(name, c)
end

function Social:NewComment(post, body)
    body = clean(body, Social.MAX_COMMENT)
    if body == "" or not Sync:GuildName() then return nil end
    return Sync:Write("comments", { id = ns.NewId(), author = Sync:Me(), t = ns.Now(), post = post.id, body = body })
end

------------------------------------------------------------------------
-- Group finder
------------------------------------------------------------------------
function Social:Groups()
    local now = ns.Now()
    local out = list("lfg", function(g) return g.exp > now end)
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.id > b.id
    end)
    return out
end

function Social:MyGroup()
    local me = Sync:Me()
    for _, g in ipairs(self:Groups()) do
        if g.author == me then return g end
    end
end

-- How full the poster's group is: 1/5 solo or in a party, raids count
-- against 10, 20 or 40.
function Social:GroupSize()
    local n = math.max(1, GetNumGroupMembers())
    if IsInRaid() then
        return n, (n <= 10 and 10) or (n <= 20 and 20) or 40
    end
    return n, 5
end

-- Each member's role, tanks first ("THDD"): a guildie's profile role, else
-- what the game has them as, else DPS.
local ROLE_LETTER = { T = "T", H = "H", D = "D", M = "D", R = "D", TANK = "T", HEALER = "H", DAMAGER = "D" }
function Social:GroupRoles()
    local out = {}
    local function add(unit)
        local name = unit == "player" and Sync:Me() or (UnitName and UnitName(unit))
        if not name or (issecretvalue and issecretvalue(name)) then return end
        local key = unit == "player" and name or (ns.Attendance and ns.Attendance:Key(name)) or name
        local prof = ns.Profiles and ns.Profiles:Content(key).role
        local game = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
        if game and issecretvalue and issecretvalue(game) then game = nil end
        out[#out + 1] = ROLE_LETTER[prof or ""] or ROLE_LETTER[game or ""] or "D"
    end
    add("player")
    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then add(u) end
        end
    else
        for i = 1, 4 do if UnitExists and UnitExists("party" .. i) then add("party" .. i) end end
    end
    local rank = { T = 1, H = 2, D = 3 }
    table.sort(out, function(a, b) return rank[a] < rank[b] end)
    return table.concat(out)
end

-- One listing per person: posting again replaces your old one.
function Social:PostGroup(what, need, desc)
    what, need = clean(what, Social.MAX_LFG), clean(need, Social.MAX_LFG)
    desc = clean(desc, Social.MAX_LFG_DESC)
    if what == "" or not Sync:GuildName() then return nil end
    local old = self:MyGroup()
    if old then self:Remove("lfg", old) end
    local now = ns.Now()
    local size, max = self:GroupSize()
    wipe(self.requests)
    return Sync:Write("lfg", { id = ns.NewId(), author = Sync:Me(), t = now, what = what,
        need = need ~= "" and need or nil, desc = desc ~= "" and desc or nil,
        exp = now + Social.LFG_MINUTES * 60, size = size, max = max, roles = self:GroupRoles() })
end

-- Keep your listing's 2/5 current as people join or leave.
function Social:UpdateGroupSize()
    local mine = self:MyGroup()
    if not mine then return end
    local size, max = self:GroupSize()
    local roles = self:GroupRoles()
    if mine.size == size and mine.max == max and mine.roles == roles then return end
    local c = copy(mine)
    c.size, c.max, c.roles = size, max, roles
    Sync:Write("lfg", c)
end

function Social:IsFull(g)
    return g.size and g.max and g.size >= g.max
end

------------------------------------------------------------------------
-- Join requests: a whisper between the two addons ("J" to ask, "K" to
-- answer), nothing in chat. The poster gets a pop-up with Invite/No thanks.
------------------------------------------------------------------------
Social.requests = {}    -- poster side: requester key -> { t, id }
Social.requested = {}   -- requester side: listing id -> t

function Social:RequestJoin(g)
    if g.author == Sync:Me() or self:IsFull(g) then return false end
    ns.Comm.Send("J" .. g.id, "WHISPER", Ambiguate(g.author, "none"))
    self.requested[g.id] = ns.Now()
    changed()
    return true
end

function Social:OnJoinRequest(sender, id)
    local mine = self:MyGroup()
    if not mine or mine.id ~= id then return end
    local who = ns.Attendance:Key(sender)
    if self.requests[who] then return end
    self.requests[who] = { t = ns.Now(), id = id }
    if ns.JoinPopup and ns.db.settings.joinPopups ~= false then
        ns.JoinPopup:Add(who, mine)
    else
        ns.Print(("%s wants to join your group: click your listing on Home to answer"):format(Ambiguate(who, "short")))
    end
    changed()
end

function Social:Answer(who, invite)
    local req = self.requests[who]
    if not req then return end
    self.requests[who] = nil
    local target = Ambiguate(who, "none")
    if invite then
        local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        pcall(fn, target)
    end
    ns.Comm.Send("K" .. (invite and "1" or "0") .. req.id, "WHISPER", target)
    changed()
end

function Social:OnJoinReply(sender, ok, id)
    if not self.requested[id] then return end
    self.requested[id] = nil
    local name = Ambiguate(sender, "short")
    if ok then
        ns.Print(("%s is inviting you to their group"):format(name))
    else
        ns.Print(("%s can't take you right now"):format(name))
    end
    changed()
end

function Social:RequestCount()
    return ns.Count(self.requests)
end

ns.On("GROUP_ROSTER_UPDATE", function() Social:UpdateGroupSize() end)
