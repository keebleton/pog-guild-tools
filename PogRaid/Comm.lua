-- PogRaid comms: send boards to the group in chunks, reassemble them on
-- the other end, and hold outgoing messages while the client restricts
-- addon chat (boss fights on the 12.0 API).
--
-- Messages (prefix "PogRaid"):
--   B<id:2><index:1><total:1><payload>   board chunk (base64 digits)
--   X                                    close the board this sender showed
--   Q                                    "who has PogRaid?"
--   R<version>                           reply to Q, whispered back
--   P                                    probe ping to self
local _, ns = ...

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "PogRaid"
local CHUNK = 240
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:sub(i, i)] = i - 1 end
local function b64(n) return B64:sub(n + 1, n + 1) end

-- What went out and came in this session, for /pog sync.
Comm.stats = { sent = {}, failed = {}, recv = {}, from = {} }

-- "Y" chunks count under their sync op (first chunk) or "Y+" (the rest).
local function statKey(text)
    local k = text:sub(1, 1)
    if k == "Y" then return text:sub(4, 4) == "A" and ("Y" .. text:sub(6, 6)) or "Y+" end
    return k
end
local function bump(t, k) t[k] = (t[k] or 0) + 1 end

local queue = {}          -- outgoing { text, channel, target }: raid plans, whispers, checks
local bulk = {}           -- background guild sync; only sends while allowance is to spare
local pumping = false
local warnedRestricted = false
local inbox = {}          -- key -> { parts = {}, got = n, total = n, time = t }
local nextId = math.random(0, 4095)
local check                -- active raid check, if any

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function shortName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:match("^[^-]+"))
end

-- The encounter lockdown on addon messages (12.0 rules). Only a plain
-- true counts. Not C_ChatInfo.AreOutgoingAddonChatMessagesRestricted: that
-- is about addons posting ordinary chat, which normal realms always
-- restrict, and on Forever it's always true (it held every message 0.12.0
-- tried to send).
function Comm.IsRestricted()
    local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not fn then return false end
    local ok, restricted = pcall(fn)
    return ok and restricted == true
end

-- Where a board should go right now. Solo: whisper ourselves, so the whole
-- send/receive path can be tested without a group.
function Comm.GroupChannel()
    local instanceCat = LE_PARTY_CATEGORY_INSTANCE
    local homeCat = LE_PARTY_CATEGORY_HOME
    if instanceCat and IsInGroup(instanceCat) and not (homeCat and IsInGroup(homeCat)) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return "WHISPER", ns.PlayerName()
end

local function resultName(r)
    if type(Enum) == "table" and Enum.SendAddonMessageResult then
        for k, v in pairs(Enum.SendAddonMessageResult) do
            if v == r then return k end
        end
    end
    return tostring(r)
end

local function isSuccess(r)
    if r == nil or r == true or r == 0 then return true end
    local E = type(Enum) == "table" and Enum.SendAddonMessageResult
    return E and r == E.Success or false
end

local function isThrottle(r)
    local E = type(Enum) == "table" and Enum.SendAddonMessageResult
    return E and (r == E.AddonMessageThrottle or r == E.ChannelThrottle) or false
end

------------------------------------------------------------------------
-- Outgoing queue
------------------------------------------------------------------------
-- The client lets each prefix send 10 messages, then one more per second.
-- We keep our own estimate so background sync always leaves a few for
-- things people are waiting on (a raid plan, a duel challenge).
Comm.ALLOWANCE, Comm.RESERVE = 10, 3
local allowance, allowanceAt = Comm.ALLOWANCE, nil

local function refill()
    local now = GetTime()
    if allowanceAt then allowance = math.min(Comm.ALLOWANCE, allowance + (now - allowanceAt)) end
    allowanceAt = now
end

local Pump

local function schedule(delay)
    if pumping then return end
    pumping = true
    C_Timer.After(delay, function()
        pumping = false
        Pump()
    end)
end

-- Messages are always tried; one only waits when the client turns it down
-- during a lockdown, so a wrong "locked" answer can never hold everything.
local function hold()
    if not warnedRestricted then
        warnedRestricted = true
        ns.Print("addon messages are locked right now (boss fight?). Pog Guild Tools will send as soon as they unlock.")
    end
    schedule(1)
end

Pump = function()
    while queue[1] or bulk[1] do
        refill()
        local list = queue[1] and queue or bulk
        if list == bulk and allowance < 1 + Comm.RESERVE then
            schedule(1)
            return
        end
        local m = list[1]
        local ok, r = pcall(C_ChatInfo.SendAddonMessage, Comm.PREFIX, m.text, m.channel, m.target)
        local st = Comm.stats
        if (not ok or not (isSuccess(r) or isThrottle(r))) and Comm.IsRestricted() then
            return hold()
        end
        if not ok then
            ns.Print("send failed: " .. tostring(r))
            bump(st.failed, "error")
            st.lastFail = { what = statKey(m.text) .. " " .. m.channel, why = tostring(r), at = GetTime() }
            table.remove(list, 1)
        elseif isSuccess(r) then
            table.remove(list, 1)
            allowance = allowance - 1
            bump(st.sent, statKey(m.text))
        elseif isThrottle(r) then
            allowance = 0
            bump(st.failed, "throttled (retried)")
            schedule(1)
            return
        else
            if list == queue then ns.Print("send failed: " .. resultName(r)) end
            bump(st.failed, resultName(r))
            st.lastFail = { what = statKey(m.text) .. " " .. m.channel, why = resultName(r), at = GetTime() }
            table.remove(list, 1)
        end
    end
    if warnedRestricted then
        warnedRestricted = false
        ns.Print("addon messages unlocked, sent.")
    end
end

local function Send(text, channel, target, background)
    local list = background and bulk or queue
    list[#list + 1] = { text = text, channel = channel, target = target }
    -- something people wait on goes out now, even while sync waits its turn
    if not pumping or not background then Pump() end
end
Comm.Send = Send

function Comm.QueueLength() return #queue + #bulk end
function Comm.BulkIdle() return bulk[1] == nil end
function Comm.QueueLengths() return #queue, #bulk end

------------------------------------------------------------------------
-- Boards
------------------------------------------------------------------------
-- Any payload, split into numbered chunks: <kind><id:2><index:1><total:1>.
-- `background` puts it behind everything else (guild sync).
function Comm.SendChunked(kind, payload, channel, target, background)
    local total = math.max(1, math.ceil(#payload / CHUNK))
    if total > 64 then return false end
    nextId = (nextId + 1) % 4096
    local id = b64(math.floor(nextId / 64)) .. b64(nextId % 64)
    for i = 0, total - 1 do
        Send(kind .. id .. b64(i) .. b64(total - 1) .. payload:sub(i * CHUNK + 1, (i + 1) * CHUNK), channel, target, background)
    end
    return true, total
end

function Comm.SendBoard(board, channel, target)
    if not channel then channel, target = Comm.GroupChannel() end
    local ok, total = Comm.SendChunked("B", ns.Codec.Encode(board), channel, target)
    if not ok then
        ns.Print("raid plan is too large to send")
        return false
    end
    return true, channel, total
end

function Comm.SendClose()
    Send("X", Comm.GroupChannel())
end

-- Leader or assistant in our group, or ourselves. Boards from anyone else
-- are ignored so one person cannot spam everyone's screen.
function Comm.IsTrusted(sender)
    local name = shortName(sender)
    if name == ns.PlayerName() then return true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local rosterName, rank = GetRaidRosterInfo(i)
            if rosterName and shortName(rosterName) == name then
                return (rank or 0) >= 1
            end
        end
        return false
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if shortName(GetUnitName(unit, true)) == name then
                return UnitIsGroupLeader(unit) and true or false
            end
        end
    end
    return false
end

-- Reassembles chunks; returns the whole payload once the last one lands.
-- A multi-part message that will never finish: a part went missing (say,
-- during a loading screen). Guild sync can recover what it carried.
local function lost(entry)
    Comm.stats.lost = (Comm.stats.lost or 0) + 1
    if entry.kind == "Y" and ns.Sync then ns.Sync:Missed() end
end

local function receiveChunk(text, sender)
    local id = text:sub(2, 3)
    local idx, last = DEC[text:sub(4, 4)], DEC[text:sub(5, 5)]
    if not idx or not last or idx > last then return end
    local key = sender .. "/" .. text:sub(1, 1) .. id
    local now = GetTime()
    for k, entry in pairs(inbox) do
        if now - entry.time > 30 then
            inbox[k] = nil
            lost(entry)
        end
    end
    local entry = inbox[key]
    if not entry then
        entry = { parts = {}, got = 0, total = last + 1, time = now, kind = text:sub(1, 1) }
        inbox[key] = entry
        -- notice even if nothing else arrives to trigger the sweep above
        if last > 0 then
            C_Timer.After(31, function()
                if inbox[key] == entry and GetTime() - entry.time > 30 then
                    inbox[key] = nil
                    lost(entry)
                end
            end)
        end
    end
    if entry.total ~= last + 1 or entry.parts[idx] then return end
    entry.parts[idx] = text:sub(6)
    entry.got = entry.got + 1
    entry.time = now
    if entry.got < entry.total then return end
    inbox[key] = nil
    return table.concat(entry.parts, "", 0, entry.total - 1)
end

local function receiveBoard(text, sender)
    local payload = receiveChunk(text, sender)
    if not payload then return end
    local board, err = ns.Codec.Decode(payload)
    if board then
        ns.Viewer:ShowBoard(board, shortName(sender))
    else
        ns.Print(("could not read raid plan from %s: %s"):format(shortName(sender), err))
    end
end

------------------------------------------------------------------------
-- Raid check: who has the addon?
------------------------------------------------------------------------
local function groupNames()
    local names = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = GetRaidRosterInfo(i)
            if n then names[#names + 1] = shortName(n) end
        end
    else
        names[1] = ns.PlayerName()
        for i = 1, GetNumSubgroupMembers() do
            local n = GetUnitName("party" .. i, true)
            if n then names[#names + 1] = shortName(n) end
        end
    end
    return names
end

function Comm.CheckRaid()
    if not IsInGroup() then
        ns.Print("check: you are not in a group")
        return
    end
    check = { replies = {} }
    Send("Q", Comm.GroupChannel())
    ns.Print("checking who has Pog Guild Tools...")
    C_Timer.After(3, function()
        local have, missing = {}, {}
        for _, n in ipairs(groupNames()) do
            if check.replies[n] or n == ns.PlayerName() then
                have[#have + 1] = n
            else
                missing[#missing + 1] = n
            end
        end
        ns.Print(("has it (%d): %s"):format(#have, table.concat(have, ", ")))
        if #missing > 0 then
            ns.Print(("|cffff8040missing (%d): %s|r"):format(#missing, table.concat(missing, ", ")))
        else
            ns.Print("everyone has it")
        end
        check = nil
    end)
end

-- Ask every Pog Raid in the guild to answer; reports who did.
function Comm.GuildPing()
    if not IsInGuild() then
        ns.Print("sync ping: you're not in a guild")
        return
    end
    Comm.guildPingAt, Comm.guildPongs = GetTime(), 0
    Send("Z?", "GUILD")
    ns.Print("sync ping: asking the guild...")
    C_Timer.After(5, function()
        if (Comm.guildPongs or 0) == 0 then
            ns.Print("sync ping: |cffff8040no answer in 5s|r. Either nobody else online runs Pog Guild Tools, or guild addon messages aren't getting through.")
        end
        Comm.guildPingAt = nil
    end)
end

function Comm.Ping()
    Comm.pingSent = GetTime()
    Send("P", "WHISPER", ns.PlayerName())
    C_Timer.After(3, function()
        if Comm.pingSent then
            Comm.pingSent = nil
            ns.Print("self whisper test: |cffff4040no reply in 3s|r")
        end
    end)
end

------------------------------------------------------------------------
-- Incoming
------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
    if name ~= "PogRaid" then return end
    C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
end)

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= Comm.PREFIX or type(text) ~= "string" or not sender then return end
    local kind = text:sub(1, 1)
    local fromSelf = shortName(sender) == ns.PlayerName()
    local st = Comm.stats
    bump(st.recv, statKey(text) .. (fromSelf and " (own echo)" or ""))
    if not fromSelf then st.from[shortName(sender)] = { at = GetTime(), what = statKey(text), channel = channel } end
    if kind == "B" or kind == "X" then
        -- Our own group messages echo back to us; the editor already shows
        -- the board, so only self whispers (the solo test) open the viewer.
        if fromSelf and channel ~= "WHISPER" then return end
        if not Comm.IsTrusted(sender) then return end
        if kind == "B" then
            receiveBoard(text, sender)
        else
            ns.Viewer:CloseFrom(shortName(sender))
        end
    elseif kind == "Y" then
        -- shared guild data (message board, group finder); our own echo is ignored
        if fromSelf or channel ~= "GUILD" then return end
        local payload = receiveChunk(text, sender)
        if payload and ns.Sync then ns.Sync:OnPayload(payload, sender) end
    elseif kind == "V" or kind == "W" then
        -- version check: one tiny message at login, one whispered reply
        if fromSelf or not ns.Version then return end
        ns.Version:OnMessage(kind, text, channel, sender)
    elseif kind == "D" then
        -- ranked duel challenges, addon to addon over whisper
        if fromSelf or channel ~= "WHISPER" or not ns.Duels then return end
        ns.Duels:OnMessage(sender, text)
    elseif kind == "J" or kind == "K" then
        -- group finder join requests, addon to addon over whisper
        if fromSelf or channel ~= "WHISPER" or not ns.Social then return end
        if kind == "J" then
            ns.Social:OnJoinRequest(sender, text:sub(2))
        else
            ns.Social:OnJoinReply(sender, text:sub(2, 2) == "1", text:sub(3))
        end
    elseif kind == "Q" then
        if not fromSelf then Send("R" .. ns.VERSION, "WHISPER", sender) end
    elseif kind == "R" then
        if check then check.replies[shortName(sender)] = text:sub(2) end
    elseif kind == "Z" then
        -- /pog sync ping: a guild-wide "who hears me?", answered by whisper
        if fromSelf then return end
        if text:sub(2, 2) == "?" and channel == "GUILD" then
            Comm.pongedAt = Comm.pongedAt or {}
            local last = Comm.pongedAt[sender]
            if not last or GetTime() - last > 10 then
                Comm.pongedAt[sender] = GetTime()
                Send("Z!" .. ns.VERSION, "WHISPER", Ambiguate(sender, "none"))
            end
        elseif text:sub(2, 2) == "!" and Comm.guildPingAt then
            ns.Print(("sync ping: %s answered (Pog Guild Tools %s) in %.1fs"):format(shortName(sender), text:sub(3),
                GetTime() - Comm.guildPingAt))
            Comm.guildPongs = (Comm.guildPongs or 0) + 1
        end
    elseif kind == "P" then
        if fromSelf and Comm.pingSent then
            ns.Print(("self whisper test: |cff40ff40reply in %.2fs|r"):format(GetTime() - Comm.pingSent))
            Comm.pingSent = nil
        end
    end
end)
