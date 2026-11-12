-- Pog Raid sync: keeps small shared collections (message board, group
-- finder, leaderboards, duels, Wowdle results) the same on every guild
-- member's addon.
--
-- Each record has an id, a revision (rev, server time) and the editor (by);
-- the newest rev wins, deletes are tombstones. Changes are broadcast on the
-- guild addon channel as they happen.
--
-- Catching up people who were offline has to fit the client's allowance of
-- about one message a second, with a whole guild listening:
--   * Records hash into 32 buckets. An addon's fingerprint ("F") carries one
--     short sum per bucket, so two addons see exactly which buckets differ.
--   * For a bucket the fingerprint's sender has nothing in, records are
--     simply sent. For other differing buckets, listeners ask the sender to
--     list them ("L"; one ask covers everyone who needs the same buckets).
--     The sender lists those buckets' record tags ("H"); whoever holds
--     something missing from the list sends it, and whoever is missing a
--     listed tag asks for it ("N"). Only the sender ever lists, so a login
--     wave costs one listing per person, not one per pair.
--   * Records go out in small pages from an outbox, a page only when the
--     previous one has left. Before each page the addon drops anything it has
--     heard someone else send since it was asked for, so answers don't repeat.
--   * What people see first goes first (def.order: board and group finder
--     before games), in random order within that so answers spread out.
--   * Only a few addons answer at once (about PRIMARIES of those online);
--     the rest are a fallback that waits until the channel goes quiet.
--   * Sync goes out on Comm's background lane, behind raid plans and whispers.
--
-- Wire (inside chunked "Y" payloads; tags and sums are 5 base64 digits):
--   F<32 bucket sums><count>:<version>        fingerprint
--   L<buckets:6><name>                        please list these buckets (bit mask)
--   H(<bucket:1><sum:5><n:2><tag:5>*n)+       bucket listing
--   N<tag:5>...                               request
--   E<record>;<record>...                     records, compact (see EncodeRecord)
-- 0.11 and older sent S/G/R/P; their S still tells us their version and
-- their P records (fields ~ separated, percent-escaped, full) are still
-- accepted.
local _, ns = ...

local Sync = {}
ns.Sync = Sync

Sync.SUMMARY_EVERY = 600
Sync.LOGIN_DELAY = 15
Sync.BUCKETS = 32
Sync.PAGE = 900           -- bytes of records per page (4 chunks)
Sync.PRIMARIES = 5        -- about this many addons answer right away
Sync.FAST = { 0.3, 2.5 }  -- seconds before a primary answers
Sync.SLOW = { 45, 90 }    -- the fallback, and only once the channel is quiet
Sync.QUIET = 8
Sync.FUTURE = 600         -- seconds a record's times may run ahead of the server's clock
Sync.collections = {}
Sync.byCode = {}
Sync.heard = {}          -- key -> { rev, at }: last copy heard on the channel
Sync.asked = {}          -- tag -> GetTime() someone requested it
Sync.outbox = {}         -- records waiting to go out, in random order
Sync.queued = {}         -- key -> outbox item
Sync.pendingDigest = {}  -- bucket -> GetTime() we planned to list it
Sync.sentDigest = {}     -- bucket -> GetTime() we last listed it
Sync.heardDigest = {}    -- bucket -> { sum, at }
Sync.asks = {}           -- name -> { mask, at }: listing asks we plan or heard
Sync.listMask = 0        -- buckets people asked us to list
Sync.lastPageAt = -1e9
Sync.refused = {}        -- tag -> GetTime() we turned that record down (don't ask again for a while)
Sync.peers = {}          -- name -> { at, differ, count, version }: their last fingerprint vs ours
Sync.stats = { taken = 0, refused = 0, noGuild = 0 }

------------------------------------------------------------------------
-- Encoding
------------------------------------------------------------------------
local function esc(v)
    return (tostring(v):gsub("[%%;~,|\n\r%^]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function unesc(v)
    return (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
Sync.Escape, Sync.Unescape = esc, unesc

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end
local TAG_MOD = 1073741824 -- 2^30, five base64 digits

local function enc(n, digits)
    local out = {}
    for i = digits, 1, -1 do
        local d = n % 64
        out[i] = B64:sub(d + 1, d + 1)
        n = (n - d) / 64
    end
    return table.concat(out)
end
local function dec(s, from, digits)
    local n = 0
    for i = from, from + digits - 1 do
        local d = DEC[s:byte(i) or 0]
        if not d then return nil end
        n = n * 64 + d
    end
    return n
end

Sync.Enc, Sync.Dec = enc, dec

local function djb(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % TAG_MOD end
    return h
end
local function bucketOf(key) return math.floor(djb(key) / 32768) % Sync.BUCKETS end
local function tagOf(key, rev) return djb(key .. ":" .. rev) end
Sync.Tag = tagOf

-- Bucket masks as plain numbers (no bit library needed).
local function hasBit(mask, b) return math.floor(mask / 2 ^ b) % 2 == 1 end
local function union(a, b)
    local out = a
    for i = 0, Sync.BUCKETS - 1 do
        if hasBit(b, i) and not hasBit(a, i) then out = out + 2 ^ i end
    end
    return out
end
local function covers(a, b) return union(a, b) == a end
local function bits(mask)
    local n = 0
    for i = 0, Sync.BUCKETS - 1 do
        if hasBit(mask, i) then n = n + 1 end
    end
    return n
end
-- A broad ask gets every bucket listed, so it answers anyone's ask.
local function answers(heard, mask) return bits(heard) >= Sync.BUCKETS / 2 or covers(heard, mask) end
Sync.HasBit, Sync.Union = hasBit, union

local function split(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            return out
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
end

-- Common fields come first in every collection.
local BASE = { "id", "rev", "by", "author", "t", "deleted" }

function Sync:Register(def)
    local fields = {}
    for _, f in ipairs(BASE) do fields[#fields + 1] = f end
    for _, f in ipairs(def.fields) do fields[#fields + 1] = f end
    def.all = fields
    def.numeric = def.numeric or {}
    def.numeric.rev, def.numeric.t = true, true
    def.bool = def.bool or {}
    def.bool.deleted = true
    self.collections[def.name] = def
    self.byCode[def.code] = def
end

-- Old full format (0.11 and older send it; kept for reading).
function Sync:EncodeRecordFull(def, rec)
    local parts = { def.code }
    for _, f in ipairs(def.all) do
        local v = rec[f]
        if def.bool[f] then v = v and "1" or "" end
        parts[#parts + 1] = v == nil and "" or esc(v)
    end
    return table.concat(parts, "~")
end

local function decodeFull(def, vals)
    local rec = {}
    for i, f in ipairs(def.all) do
        local v = unesc(vals[i])
        if def.bool[f] then
            rec[f] = (v == "1") or nil
        elseif def.numeric[f] then
            rec[f] = tonumber(v)
        elseif v ~= "" then
            rec[f] = v
        end
    end
    return rec
end

-- Compact format: same fields, but times in base 64, rev left empty when
-- it equals t, by left empty when it's the author, and the author's name
-- inside any other field written as "^". About a third smaller.
local function encTime(v)
    if v == math.floor(v) and v >= 0 and v < 2 ^ 36 then return enc(v, 6) end
    return "=" .. esc(v)
end
local function decTime(s)
    if s:sub(1, 1) == "=" then return tonumber(unesc(s:sub(2))) end
    return #s == 6 and dec(s, 1, 6) or nil
end

function Sync:EncodeRecord(def, rec)
    local author = rec.author or ""
    local ea = esc(author)
    local parts = { def.code }
    for _, f in ipairs(def.all) do
        local v = rec[f]
        if f == "rev" then
            v = (v == rec.t) and "" or encTime(v)
        elseif f == "t" then
            v = encTime(v)
        elseif f == "by" then
            v = (v == author) and "" or esc(v)
        elseif f == "author" then
            v = ea
        elseif def.bool[f] then
            v = v and "1" or ""
        elseif v == nil then
            v = ""
        else
            v = esc(v)
            if ea ~= "" then
                local i = v:find(ea, 1, true)
                while i do
                    v = v:sub(1, i - 1) .. "^" .. v:sub(i + #ea)
                    i = v:find(ea, i + 1, true)
                end
            end
        end
        parts[#parts + 1] = v
    end
    return table.concat(parts, "~")
end

local function decodeCompact(def, vals)
    local rec = {}
    local ea = vals[4] -- author, still escaped
    local author = unesc(ea)
    for i, f in ipairs(def.all) do
        local v = vals[i]
        if f == "rev" then
            rec.rev = v ~= "" and decTime(v) or nil
        elseif f == "t" then
            rec.t = decTime(v)
        elseif f == "by" then
            rec.by = v == "" and author or unesc(v)
        elseif f == "author" then
            rec.author = author ~= "" and author or nil
        elseif def.bool[f] then
            rec[f] = (v == "1") or nil
        else
            v = unesc((v:gsub("%^", function() return ea end)))
            if def.numeric[f] then
                rec[f] = tonumber(v)
            elseif v ~= "" then
                rec[f] = v
            end
        end
    end
    rec.rev = rec.rev or rec.t
    return rec
end

-- `full` reads the old format.
function Sync:DecodeRecord(s, full)
    local def = self.byCode[s:sub(1, 1)]
    if not def then return nil end
    local vals = split(s:sub(3), "~")
    if s:sub(2, 2) ~= "~" or #vals ~= #def.all then return nil end
    local rec = full and decodeFull(def, vals) or decodeCompact(def, vals)
    if not rec.id or not rec.rev or not rec.by or not rec.author or not rec.t then return nil end
    return def, rec
end

------------------------------------------------------------------------
-- Storage (per guild, so alts in another guild keep their own board)
------------------------------------------------------------------------
function Sync:GuildName()
    if not IsInGuild() then return nil end
    return (GetGuildInfo("player"))
end

function Sync:Store(name)
    local guild = self:GuildName()
    if not guild then return nil end
    ns.db.sync = ns.db.sync or {}
    local g = ns.db.sync[guild]
    if not g then
        g = {}
        ns.db.sync[guild] = g
    end
    g[name] = g[name] or {}
    return g[name]
end

function Sync:Me()
    return ns.Attendance:Key(ns.PlayerName())
end

-- Officer = guild rank index at or above the officer rank setting (0 is
-- guild master). Unknown players get the benefit of the doubt only until
-- we've read the whole guild roster once: after that a name that isn't in
-- it (made up, or someone who left) is no officer, so a forged "by" can't
-- post as one or hand out officer ranks.
function Sync:OfficerRank()
    return ns.db.guild.officerRank or 1
end

-- The guild's chosen officer ranks (Settings) win over the default.
function Sync:RankIsOfficer(rankIndex)
    local set = ns.Settings and ns.Settings:OfficerRanks()
    if set then return set[rankIndex] == true end
    return rankIndex <= self:OfficerRank()
end

function Sync:IsOfficer(name)
    local p = ns.db.guild.players[ns.Attendance:Key(name)]
    local known = ns.db.guild.fullScan
    if not p or p.rankIndex == nil then return not known end
    if known and p.inGuild == false then return false end
    return self:RankIsOfficer(p.rankIndex)
end

function Sync:AmOfficer()
    local p = ns.db.guild.players[self:Me()]
    if p and p.rankIndex ~= nil then return self:RankIsOfficer(p.rankIndex) end
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end

-- Stores a record if it is valid and newer than ours. Returns true if kept.
-- `quiet` leaves the change callback to the caller (a page of records
-- refreshes the screen once, not once per record).
function Sync:Apply(def, rec, quiet)
    local store = self:Store(def.name)
    if not store then return false end
    -- newest rev wins, so one stamped in the future could never be replaced
    -- or deleted again (and every addon would keep passing it on)
    local latest = ns.Now() + Sync.FUTURE
    if (rec.rev or 0) > latest or (rec.t or 0) > latest then return false end
    if def.valid and not def.valid(rec) then return false end
    if def.expired and not rec.deleted and def.expired(rec) then return false end
    local cur = store[rec.id]
    if cur then
        if cur.rev > rec.rev then return false end
        if cur.rev == rec.rev and (cur.by or "") >= (rec.by or "") then return false end
    end
    store[rec.id] = rec
    self.index = nil
    if def.onChange and (not quiet or def.perRecord) then def.onChange(rec) end
    return true
end

-- Our records shared under an earlier name of ours (the short name, before
-- the guild roster told us the full one) move to the new name; the old
-- copies are withdrawn as they were written, so nobody sees us twice.
Sync.OWN = { "profs", "recipes", "gems", "scores", "wowdle", "profile", "kudos", "wish", "gear", "lode", "siege" }

function Sync:MoveAuthor(old, new)
    if not old or not new or old == new or not self:GuildName() then return end
    for _, name in ipairs(Sync.OWN) do
        local def, store = self.collections[name], self:Store(name)
        if def and store then
            local moves = {}
            for id, rec in pairs(store) do
                if rec.author == old and not rec.deleted and (id == old or id:sub(1, #old + 1) == old .. ":") then
                    moves[#moves + 1] = rec
                end
            end
            for _, rec in ipairs(moves) do
                local copy = {}
                for k, v in pairs(rec) do copy[k] = v end
                copy.id, copy.author, copy.by, copy.rev = new .. rec.id:sub(#old + 1), new, nil, nil
                local cur = store[copy.id]
                if not cur or cur.deleted then self:Write(name, copy) end
                local gone = {}
                for k, v in pairs(rec) do gone[k] = v end
                gone.deleted, gone.rev = true, math.max(ns.Now(), rec.rev + 1)
                if self:Apply(def, gone) then self:Broadcast({ { def = def, rec = gone } }) end
            end
        end
    end
end

-- A local change: bump the revision, store, broadcast.
function Sync:Write(name, rec)
    local def = self.collections[name]
    local store = self:Store(name)
    if not def or not store then return nil end
    local cur = store[rec.id]
    rec.rev = math.max(ns.Now(), cur and (cur.rev + 1) or 0)
    rec.by = self:Me()
    if not self:Apply(def, rec) then return nil end
    self:Broadcast({ { def = def, rec = rec } })
    return rec
end

------------------------------------------------------------------------
-- Fingerprint: records by bucket, with a tag per record
------------------------------------------------------------------------
function Sync:Pruned()
    for name, def in pairs(self.collections) do
        local store = self:Store(name)
        if store and def.prune then def.prune(store) end
    end
    self.index = nil
end

-- Past its time (an old listing or night, deleted or not): it waits for the
-- next prune, and nobody takes it, so it isn't offered or counted. Players
-- who have pruned would otherwise never match those who haven't yet. (A
-- deletion can go too: the record it deleted is just as expired.)
local function stale(def, rec, now)
    if not def.expired then return false end
    local ok, gone = pcall(def.expired, rec, now)
    return ok and gone == true
end

-- Cached until something changes: { sums, members, tags, count }.
function Sync:Index()
    local guild = self:GuildName()
    -- Expiry is judged at the turn of the minute (server time), so every addon
    -- drops an expired record from its fingerprint at the same moment. Judged
    -- whenever each one happened to rebuild, they disagreed about it, and
    -- traded listings and records nobody would take, until their next prune.
    local minute = math.floor(ns.Now() / 60)
    if self.index and self.index.guild == guild and self.index.minute == minute then return self.index end
    local idx = { guild = guild, minute = minute, sums = {}, members = {}, tags = {}, count = 0 }
    for b = 0, Sync.BUCKETS - 1 do
        idx.sums[b], idx.members[b] = 0, {}
    end
    for name, def in pairs(self.collections) do
        local store = guild and self:Store(name)
        if store then
            for id, rec in pairs(store) do
                if not stale(def, rec, minute * 60) then
                    local key = def.code .. id
                    local tag = tagOf(key, rec.rev)
                    local b = bucketOf(key)
                    local m = { tag = tag, key = key, def = def, id = id }
                    idx.sums[b] = (idx.sums[b] + tag) % TAG_MOD
                    idx.members[b][#idx.members[b] + 1] = m
                    idx.tags[tag] = m
                    idx.count = idx.count + 1
                end
            end
        end
    end
    self.index = idx
    return idx
end

-- Every record's key and rev, sorted (tests and diagnostics).
function Sync:Keys()
    local keys = {}
    for name, def in pairs(self.collections) do
        local store = self:Store(name)
        if store then
            for id, rec in pairs(store) do keys[#keys + 1] = { key = def.code .. id, rev = rec.rev, def = def, rec = rec } end
        end
    end
    table.sort(keys, function(a, b) return a.key < b.key end)
    return keys
end

-- The bucket sums as one string, and the record count.
function Sync:Hash()
    local idx = self:Index()
    local parts = {}
    for b = 0, Sync.BUCKETS - 1 do parts[#parts + 1] = enc(idx.sums[b], 5) end
    return table.concat(parts), idx.count
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
-- Records and listings go on the background lane; the short asks
-- (fingerprint, list-ask, request) go straight out, so others hear them in
-- time to hold their own.
local function send(payload, urgent)
    if not IsInGuild() then return end
    ns.Comm.SendChunked("Y", payload, "GUILD", nil, not urgent)
end

function Sync:Broadcast(items)
    if #items == 0 then return end
    local parts = {}
    local now = GetTime()
    for _, it in ipairs(items) do
        parts[#parts + 1] = self:EncodeRecord(it.def, it.rec)
        self.heard[it.def.code .. it.rec.id] = { rev = it.rec.rev, at = now }
    end
    send("E" .. table.concat(parts, ";"))
end

function Sync:SendSummary()
    if not self:GuildName() then return end
    self:Pruned()
    local sums, n = self:Hash()
    self.summaryAt = GetTime()
    send(("F%s%d:%s"):format(sums, n, ns.WireVersion()), true)
    -- forget old bookkeeping
    local now = GetTime()
    for tag, at in pairs(self.asked) do
        if now - at > 600 then self.asked[tag] = nil end
    end
    for key, h in pairs(self.heard) do
        if now - h.at > 600 then self.heard[key] = nil end
    end
end

-- Addons online that we know run Pog Raid (at least us).
function Sync:Peers()
    local n = 1
    for name in pairs(ns.Version and ns.Version.seen or {}) do
        if ns.Roster.online[name] then n = n + 1 end
    end
    return n
end

-- Whether we answer this ask right away, or hold back as the fallback.
function Sync:Primary()
    return math.random() * self:Peers() < Sync.PRIMARIES
end

-- Put a record in the outbox. Asked again, it counts from the new ask.
function Sync:Queue(def, id, primary)
    local key = def.code .. id
    local now = GetTime()
    local d = primary and Sync.FAST or Sync.SLOW
    local notBefore = now + d[1] + math.random() * (d[2] - d[1])
    local it = self.queued[key]
    if it then
        it.at = now
        if notBefore < it.notBefore then it.notBefore, it.slow = notBefore, not primary end
        return
    end
    it = { key = key, def = def, id = id, at = now, notBefore = notBefore, slow = not primary,
        order = (def.order or 5) + math.random() }
    self.queued[key] = it
    self.outbox[#self.outbox + 1] = it
    self.unsorted = true
    self:Kick(notBefore - now)
end

-- Look at the outbox after `delay` (sooner wins). Waking exactly when a
-- record is due, rather than on a shared tick, keeps two answerers from
-- sending the same record in the same instant.
function Sync:Kick(delay)
    local now = GetTime()
    local at = now + math.max(delay or 0.5, 0.05)
    if self.kickAt and self.kickAt > now and self.kickAt <= at then return end
    self.kickAt = at
    C_Timer.After(at - now, function()
        if self.kickAt ~= at then return end
        self.kickAt = nil
        self:PumpOutbox()
    end)
end

-- Send one page from the outbox once the last one has left, skipping
-- anything someone else has sent since it was asked for.
function Sync:PumpOutbox()
    if not self.outbox[1] then return end
    if not ns.Comm.BulkIdle() then return self:Kick() end
    if self.unsorted then
        table.sort(self.outbox, function(a, b) return a.order < b.order end)
        self.unsorted = nil
    end
    local now = GetTime()
    local quiet = now - self.lastPageAt >= Sync.QUIET
    local parts, size, left = {}, 0, {}
    for _, it in ipairs(self.outbox) do
        local store = self:Store(it.def.name)
        local rec = store and store[it.id]
        local h = self.heard[it.key]
        if not rec or (h and h.at >= it.at and h.rev >= rec.rev) then
            self.queued[it.key] = nil
        elseif size < Sync.PAGE and now >= it.notBefore and (quiet or not it.slow) then
            local s = self:EncodeRecord(it.def, rec)
            if size > 0 and size + #s + 1 > Sync.PAGE then
                left[#left + 1] = it
            else
                parts[#parts + 1] = s
                size = size + #s + 1
                self.queued[it.key] = nil
                self.heard[it.key] = { rev = rec.rev, at = now }
            end
        else
            left[#left + 1] = it
        end
    end
    self.outbox = left
    if parts[1] then send("E" .. table.concat(parts, ";")) end
    if not left[1] then return end
    if parts[1] then return self:Kick(0.5) end -- next page once this one has left
    local due = math.huge
    for _, it in ipairs(left) do
        local t = it.slow and math.max(it.notBefore, self.lastPageAt + Sync.QUIET) or it.notBefore
        if t < due then due = t end
    end
    self:Kick(due - now)
end

-- List these buckets (after `delay`, default a random moment).
function Sync:PlanDigest(buckets, delay)
    local now = GetTime()
    for _, b in ipairs(buckets) do
        if not self.pendingDigest[b] and now - (self.sentDigest[b] or -1e9) > 10 then self.pendingDigest[b] = now end
    end
    if self.digestTimer or not next(self.pendingDigest) then return end
    self.digestTimer = true
    C_Timer.After(delay or (1 + math.random() * 3), function()
        self.digestTimer = nil
        self:SendDigest()
    end)
end

function Sync:SendDigest()
    local idx = self:Index()
    local pages, cur, size = {}, {}, 0
    local now = GetTime()
    for b, since in pairs(self.pendingDigest) do
        local hd = self.heardDigest[b]
        if not (hd and hd.at >= since and hd.sum == idx.sums[b]) then
            local m = idx.members[b]
            local tags = {}
            for i, x in ipairs(m) do tags[i] = enc(x.tag, 5) end
            local s = enc(b, 1) .. enc(idx.sums[b], 5) .. enc(math.min(#m, 4095), 2) .. table.concat(tags, "", 1, math.min(#m, 4095))
            if size > 0 and size + #s > Sync.PAGE then
                pages[#pages + 1] = table.concat(cur)
                cur, size = {}, 0
            end
            cur[#cur + 1] = s
            size = size + #s
            self.sentDigest[b] = now
        end
    end
    if size > 0 then pages[#pages + 1] = table.concat(cur) end
    self.pendingDigest = {}
    if pages[1] then self.listedAt = now end
    for _, p in ipairs(pages) do send("H" .. p) end
end

-- Ask for these tags soon, unless someone else asks or they turn up.
-- While records are still pouring in, wait: most of them are on the way.
function Sync:PlanRequest(want)
    local asked = GetTime()
    local tries = 0
    local function attempt()
        tries = tries + 1
        if GetTime() - (self.gainAt or -1e9) < 5 and tries < 20 then
            C_Timer.After(3, attempt)
            return
        end
        local idx = self:Index()
        local out = {}
        for _, tag in ipairs(want) do
            local r = self.asked[tag]
            if (not r or r < asked) and not idx.tags[tag] then
                out[#out + 1] = enc(tag, 5)
                self.asked[tag] = GetTime()
            end
        end
        local per = math.floor(Sync.PAGE / 5)
        for i = 1, #out, per do send("N" .. table.concat(out, "", i, math.min(i + per - 1, #out)), true) end
    end
    C_Timer.After(0.2 + math.random() * 1.3, attempt)
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
function Sync:OnPayload(payload, sender)
    if not self:GuildName() then
        self.stats.noGuild = self.stats.noGuild + 1
        return
    end
    local op, body = payload:sub(1, 1), payload:sub(2)
    if op == "F" then
        self:OnFingerprint(body, sender)
    elseif op == "H" then
        self:OnDigest(body)
    elseif op == "N" then
        self:OnRequest(body)
    elseif op == "L" then
        self:OnAsk(body)
    elseif op == "E" then
        self:OnRecords(body)
    elseif op == "P" then
        self:OnRecords(body, true)
    elseif op == "S" then
        -- 0.11 and older: only their version is still of use
        local v = body:match("^%x+:%d+:(.+)$")
        if v and ns.Version then ns.Version:Note(sender, v) end
    end
end

function Sync:OnFingerprint(body, sender)
    local n = Sync.BUCKETS * 5
    local v = body:sub(n + 1):match("^%d+:(.+)$")
    if not v then return end
    if ns.Version then ns.Version:Note(sender, v) end
    local idx = self:Index()
    local primary = self:Primary()
    local mask, empty, emptyMask = 0, 0, 0
    local differ = 0
    for b = 0, Sync.BUCKETS - 1 do
        if dec(body, b * 5 + 1, 5) ~= idx.sums[b] then differ = differ + 1 end
    end
    self.peers[Ambiguate(sender, "none")] = { at = GetTime(), differ = differ, version = v,
        count = tonumber(body:sub(n + 1):match("^(%d+):")) }
    for b = 0, Sync.BUCKETS - 1 do
        local theirs = dec(body, b * 5 + 1, 5)
        if not theirs then return end
        if theirs ~= idx.sums[b] then
            if theirs == 0 then
                -- they hold nothing here: no need to list, just send
                for _, m in ipairs(idx.members[b]) do self:Queue(m.def, m.id, primary) end
            elseif idx.sums[b] == 0 then
                empty, emptyMask = empty + 1, emptyMask + 2 ^ b
            else
                mask = mask + 2 ^ b
            end
        end
    end
    -- mostly empty where they aren't (a new install): our own fingerprint
    -- gets all of it sent, cheaper than a listing we'd ask every tag of
    local fresh = empty >= Sync.BUCKETS / 4
    if not fresh then mask = union(mask, emptyMask) end
    if mask > 0 then self:PlanAsk(ns.Attendance:Key(sender), mask) end
    if fresh and GetTime() - (self.summaryAt or -1e9) > 60 then
        self.summaryAt = GetTime()
        C_Timer.After(1 + math.random() * 4, function() self:SendSummary() end)
    end
end

-- Ask `who` to list these buckets, unless someone asks for them first.
function Sync:PlanAsk(who, mask)
    local now = GetTime()
    local heard = self.asks[who]
    if heard and now - heard.at < 10 and answers(heard.mask, mask) then return end
    local since = now
    C_Timer.After(0.3 + math.random() * 1.5, function()
        local h = self.asks[who]
        if h and h.at >= since and answers(h.mask, mask) then return end
        local m = union(h and h.at >= since and h.mask or 0, mask)
        self.asks[who] = { mask = m, at = GetTime() }
        send("L" .. enc(mask, 6) .. who, true)
    end)
end

function Sync:OnAsk(body)
    local mask, who = dec(body, 1, 6), body:sub(7)
    if not mask or who == "" then return end
    if who == self:Me() then
        self.listMask = union(self.listMask, mask)
        if self.listTimer then return end
        -- gather everyone's asks for a moment, then list once
        self.listTimer = true
        C_Timer.After(1.5, function()
            self.listTimer = nil
            local b = {}
            local all = bits(self.listMask) >= Sync.BUCKETS / 2
            for i = 0, Sync.BUCKETS - 1 do
                if all or hasBit(self.listMask, i) then b[#b + 1] = i end
            end
            self.listMask = 0
            self:PlanDigest(b, 0)
        end)
    else
        local h = self.asks[who]
        local now = GetTime()
        if h and now - h.at < 10 then
            self.asks[who] = { mask = union(h.mask, mask), at = now }
        else
            self.asks[who] = { mask = mask, at = now }
        end
    end
end

function Sync:OnDigest(body)
    local idx = self:Index()
    local primary = self:Primary()
    local want = {}
    local pos, now = 1, GetTime()
    while pos <= #body do
        local b, sum, n = dec(body, pos, 1), dec(body, pos + 1, 5), dec(body, pos + 6, 2)
        pos = pos + 8
        if not b or not sum or not n or b >= Sync.BUCKETS or pos + n * 5 - 1 > #body then return end
        self.heardDigest[b] = { sum = sum, at = now }
        if sum ~= idx.sums[b] then
            local theirs = {}
            for i = 0, n - 1 do
                local tag = dec(body, pos + i * 5, 5)
                if tag then theirs[tag] = true end
            end
            for _, m in ipairs(idx.members[b]) do
                if not theirs[m.tag] then self:Queue(m.def, m.id, primary) end
            end
            for tag in pairs(theirs) do
                if not idx.tags[tag] and now - (self.refused[tag] or -1e9) > 600 then want[#want + 1] = tag end
            end
        end
        pos = pos + n * 5
    end
    if want[1] then self:PlanRequest(want) end
end

function Sync:OnRequest(body)
    local idx = self:Index()
    -- asks that follow our own listing are ours to answer: we may be the
    -- only one holding those records
    local primary = (self.listedAt and GetTime() - self.listedAt < 60) or self:Primary()
    local now = GetTime()
    for i = 1, #body - 4, 5 do
        local tag = dec(body, i, 5)
        if tag then
            self.asked[tag] = now
            local m = idx.tags[tag]
            if m then self:Queue(m.def, m.id, primary) end
        end
    end
end

function Sync:OnRecords(body, full)
    local now = GetTime()
    self.lastPageAt = now
    local changed = {}
    for _, s in ipairs(split(body, ";")) do
        local def, rec = self:DecodeRecord(s, full)
        if def then
            local key = def.code .. rec.id
            local h = self.heard[key]
            if not h or rec.rev >= h.rev then self.heard[key] = { rev = rec.rev, at = now } end
            if self:Apply(def, rec, true) then
                changed[def] = rec
                self.gainAt = now
                self.stats.taken = self.stats.taken + 1
            else
                local cur = (self:Store(def.name) or {})[rec.id]
                if not (cur and cur.rev >= rec.rev) then
                    -- not just an older copy: we turned it down
                    self.stats.refused = self.stats.refused + 1
                    self.stats.lastRefused = def.name .. " " .. tostring(rec.id) .. " by " .. tostring(rec.by)
                end
                -- older than ours, or a record we won't take (an addon on
                -- another version may judge it differently): stop asking
                self.refused[tagOf(key, rec.rev)] = now
            end
        end
    end
    for def, rec in pairs(changed) do
        if def.onChange and not def.perRecord then def.onChange(rec) end
    end
end

------------------------------------------------------------------------
-- Timers
------------------------------------------------------------------------
local function periodic()
    Sync:SendSummary()
    C_Timer.After(Sync.SUMMARY_EVERY, periodic)
end

-- We probably missed something: a message arrived incomplete, or we were on
-- a loading screen (anything sent meanwhile never reaches us). Show our
-- fingerprint again shortly, so whatever we lack comes back instead of
-- waiting for the ten-minute one. At most once a minute.
Sync.MISSED_EVERY = 60
function Sync:Missed()
    local now = GetTime()
    if self.missedAt and now - self.missedAt < Sync.MISSED_EVERY then return end
    self.missedAt = now
    C_Timer.After(5 + math.random() * 10, function() self:SendSummary() end)
end

ns.OnGuildChanged(function() Sync.index = nil end)

ns.On("PLAYER_ENTERING_WORLD", function(initial, reload)
    if not initial and not reload then Sync:Missed() end
end)

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(Sync.LOGIN_DELAY, periodic)
end)
