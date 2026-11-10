"""Several Pog Raid clients in one process: each is its own Lua state with the stub
client, and their guild addon messages are relayed to each other. Tests the
message board / group finder sync end to end, including people who log in late."""
import os
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.environ.get("POGRAID_DIR") or os.path.join(os.path.dirname(HERE), "PogRaid").replace("\\", "/")
STUB = open(os.path.join(HERE, "wowstub.lua"), encoding="utf-8").read()

GUILD = [("Jake-Realm", 1), ("Anna-Realm", 1), ("Mira-Realm", 3), ("Bob-Realm", 3)]

LOAD = """
local dir, player, guild, seed, guid = ...
STUB.player = player
STUB.guid = guid
STUB.guild = {}
for i = 1, #guild do
    local g = guild[i]
    STUB.guild[i] = { name = g[1], rankIndex = g[2], level = 60, online = g[3] ~= false, class = "MAGE", guid = g[4] }
end
local ns = {}
local toc = {}
for line in io.lines(dir .. "/PogRaid.toc") do
    if line:match("%.lua$") then toc[#toc + 1] = line end
end
for _, file in ipairs(toc) do assert(loadfile(dir .. "/" .. file))("PogRaid", ns) end
ns.DEV = nil
-- real clients have different random numbers; tests trigger summaries by hand
math.randomseed(player:byte(1) * 7919 + #player + seed * 104729)
ns.Sync.LOGIN_DELAY = 1e9
-- count every record that goes out in a sync page
SENT = { records = {} }
local orig = ns.Comm.SendChunked
ns.Comm.SendChunked = function(kind, payload, ...)
    if kind == "Y" and payload:sub(1, 1) == "E" then
        for rec in payload:sub(2):gmatch("[^;]+") do
            local key = rec:sub(1, 1) .. (rec:match("^.~([^~]*)") or "")
            SENT.records[key] = (SENT.records[key] or 0) + 1
        end
    end
    return orig(kind, payload, ...)
end
-- gear shares itself at login (tested in test_pograid and the stress test);
-- these counts are about the records each test makes
ns.Gear.Publish = function() end
STUB.Fire("ADDON_LOADED", "PogRaid")
STUB.Fire("PLAYER_LOGIN")
ns.Roster:ScanGuild()
return ns
"""


class Client:
    def __init__(self, name, guild_list=None, full=None, guid=None):
        """guild_list rows: (name, rankIndex[, online[, guid]]). `full` is the name the
        game shows everyone else (Forever: "First Surname"); `name` is UnitName("player")."""
        self.name = name
        self.full = full or (name + "-Realm")
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUB)
        rows = []
        for row in (guild_list or GUILD):
            rows.append(self.lua.table_from(list(row)))
        guild = self.lua.table_from(rows)
        self.ns = self.lua.execute(LOAD, ADDON, name, guild, int(os.environ.get("SYNC_SEED", "0")), guid)
        self.stub = self.lua.globals().STUB
        self.online = True

    def run(self, code, *args):
        return self.lua.execute(code, *args)


def reaches(target, d):
    """Whisper routing like the game: same-realm short names work, but a Forever
    character is only reachable by their full "First Surname"."""
    if d.full.endswith("-Realm"):
        return target in (d.name, d.full)
    return target == d.full


def pump(clients, seconds=20, step=0.1):
    """Relay guild addon messages between online clients while time passes."""
    sent_counts = {}
    t = 0.0
    while t < seconds:
        for c in clients:
            if not c.online:
                c.stub.sent = c.lua.table_from([])
                continue
            msgs = list(c.stub.sent.values())
            c.stub.sent = c.lua.table_from([])
            for m in msgs:
                if m.channel == "WHISPER":
                    for d in clients:
                        if d is not c and d.online and reaches(m.target, d):
                            d.stub.Fire("CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", c.full)
                    continue
                if m.channel != "GUILD":
                    continue
                if m.text[0] == "Y" and m.text[3] == "A":  # first chunk of a sync payload
                    op = m.text[5]
                    sent_counts[op] = sent_counts.get(op, 0) + 1
                for d in clients:
                    if d is not c and d.online:
                        d.stub.Fire("CHAT_MSG_ADDON", m.prefix, m.text, "GUILD", c.full)
        for c in clients:
            c.stub.Advance(step)
        t += step
    return sent_counts


results = {"pass": 0, "fail": 0, "failures": []}


def check(cond, name):
    if cond:
        results["pass"] += 1
    else:
        results["fail"] += 1
        results["failures"].append(name)


def posts(c):
    return c.run("local ns = ...; local out = {} for i, p in ipairs(ns.Social:Posts()) do out[i] = p.title end return table.concat(out, '|')", c.ns)


def comments(c, title):
    return c.run("""local ns, title = ...
        for _, p in ipairs(ns.Social:Posts()) do
            if p.title == title then
                local out = {}
                for i, x in ipairs(ns.Social:Comments(p.id)) do out[i] = x.author .. ':' .. x.body end
                return table.concat(out, '|')
            end
        end
        return nil""", c.ns, title)


def sent_records(clients):
    """key -> times sent, summed over clients; resets the counters."""
    out = {}
    for c in clients:
        g = c.lua.globals().SENT
        for k, v in g.records.items():
            out[k] = out.get(k, 0) + v
        g.records = c.lua.table_from({})
    return out


def hash_of(c):
    return c.run("local ns = ...; return (ns.Sync:Hash())", c.ns)


def post(c, title, body=""):
    return c.run("local ns, t, b = ...; local r = ns.Social:NewPost(t, b); return r and r.id", c.ns, title, body)


def comment(c, title, body):
    return c.run("""local ns, title, body = ...
        for _, p in ipairs(ns.Social:Posts()) do
            if p.title == title then local r = ns.Social:NewComment(p, body); return r and r.id end
        end""", c.ns, title, body)


jake, anna, mira, bob = Client("Jake"), Client("Anna"), Client("Mira"), Client("Bob")
everyone = [jake, anna, mira, bob]
bob.online = False  # Bob logs in later

# officers post, members can't
check(jake.run("local ns = ...; return ns.Social:CanPost()", jake.ns), "sync: officer can post")
check(not mira.run("local ns = ...; return ns.Social:CanPost()", mira.ns), "sync: member cannot post")
check(post(mira, "Mira's post") is None, "sync: member post refused locally")

post(jake, "Raid Thursday", "Skyreach Spire, 8pm server. Flasks please.")
pump(everyone, 3)
check(posts(anna) == "Raid Thursday" and posts(mira) == "Raid Thursday", "sync: post reaches everyone online")
check(posts(bob) == "", "sync: offline player has nothing yet")

comment(mira, "Raid Thursday", "I'll be there")
pump(everyone, 2)
comment(anna, "Raid Thursday", "Bringing extra flasks")
pump(everyone, 3)
check(comments(jake, "Raid Thursday") == "Mira-Realm:I'll be there|Anna-Realm:Bringing extra flasks", "sync: comments reach the poster")

# a forged post from a member is rejected everywhere
forged = mira.run("""local ns = ...
    local def = ns.Sync.collections.posts
    return ns.Sync:EncodeRecord(def, { id = 'Bob-1-1', rev = 10, by = 'Bob-Realm', author = 'Bob-Realm', t = ns.Now(), title = 'Free gold' })""", mira.ns)
for c in (jake, anna, mira):
    c.stub.Fire("CHAT_MSG_ADDON", "PogRaid", "Y" + "AAAA" + "E" + forged, "GUILD", "Bob-Realm")
check("Free gold" not in posts(jake) and "Free gold" not in posts(mira), "sync: member's forged post rejected")

# Bob logs in later and catches up through the fingerprint/digest exchange
post(anna, "Loot rules", "Council, see guild info.")
pump(everyone, 3)
bob.online = True
sent_records(everyone)
bob.run("local ns = ...; ns.Sync:SendSummary()", bob.ns)
counts = pump(everyone, 30)
check(posts(bob) == "Loot rules|Raid Thursday" or posts(bob) == "Raid Thursday|Loot rules", "sync: late login gets every post")
check(comments(bob, "Raid Thursday") == comments(jake, "Raid Thursday"), "sync: late login gets comments")
hashes = {hash_of(c) for c in everyone}
check(len(hashes) == 1, "sync: everyone ends with the same data")
check(counts.get("F", 0) == 1 and counts.get("H", 0) == 0 and counts.get("N", 0) == 0,
      "sync: a fresh install needs no listing, records just come (%s)" % counts)
sent = sent_records(everyone)
# answers wait a random moment and skip what they hear; two can still land
# within the same instant now and then, so allow one repeat
check(len(sent) == 4 and sum(sent.values()) <= 5, "sync: each missing record sent once, a repeat at most (%s)" % sent)

# officer pins and deletes; a member deletes their own comment; members can't delete others'
jake.run("""local ns = ...
    for _, p in ipairs(ns.Social:Posts()) do if p.title == 'Loot rules' then ns.Social:SetPinned(p, true) end end""", jake.ns)
pump(everyone, 3)
check(posts(mira).split("|")[0] == "Loot rules", "sync: pinned post first for everyone")
mira.run("""local ns = ...
    for _, p in ipairs(ns.Social:Posts()) do
        if p.title == 'Raid Thursday' then
            for _, c in ipairs(ns.Social:Comments(p.id)) do
                if c.author == 'Mira-Realm' then ns.Social:Remove('comments', c) end
                if c.author == 'Anna-Realm' then ns.Social:Remove('comments', c) end
            end
        end
    end""", mira.ns)
pump(everyone, 3)
check(comments(bob, "Raid Thursday") == "Anna-Realm:Bringing extra flasks", "sync: own comment deleted, others' kept")
jake.run("""local ns = ...
    for _, p in ipairs(ns.Social:Posts()) do if p.title == 'Raid Thursday' then ns.Social:Remove('posts', p) end end""", jake.ns)
pump(everyone, 3)
check(posts(mira) == "Loot rules" and posts(bob) == "Loot rules", "sync: officer deletes a post for everyone")

# two officers edit the same post while apart: newest edit wins everywhere
anna.online = False
jake.run("""local ns = ...
    for _, p in ipairs(ns.Social:Posts()) do if p.title == 'Loot rules' then ns.Social:SetPinned(p, false) end end""", jake.ns)
pump(everyone, 3)
for c in everyone:
    c.stub.Advance(5)
anna.online = True
anna.run("""local ns = ...
    for _, p in ipairs(ns.Social:Posts()) do if p.title == 'Loot rules' then ns.Social:SetPinned(p, true) end end""", anna.ns)
pump(everyone, 3)
anna.run("local ns = ...; ns.Sync:SendSummary()", anna.ns)
pump(everyone, 30)
pinned = {c.run("""local ns = ...
    for _, p in ipairs(ns.Social:Posts()) do if p.title == 'Loot rules' then return p.pinned == true end end""", c.ns) for c in everyone}
check(pinned == {True} and len({hash_of(c) for c in everyone}) == 1, "sync: newest edit wins everywhere")

# an older copy of a post can never overwrite a newer one
stale = jake.run("""local ns = ...
    local def = ns.Sync.collections.posts
    for _, p in ipairs(ns.Social:Posts()) do
        if p.title == 'Loot rules' then
            local old = {}
            for k, v in pairs(p) do old[k] = v end
            old.rev = p.rev - 100
            old.pinned = not p.pinned or nil
            old.title = 'Old title'
            return ns.Sync:EncodeRecord(def, old)
        end
    end""", jake.ns)
jake.stub.Fire("CHAT_MSG_ADDON", "PogRaid", "Y" + "AB" + "AA" + "E" + stale, "GUILD", "Anna-Realm")
check("Old title" not in posts(jake), "sync: older version ignored")

# a 0.11 addon still sends the old full record format: it's read
oldfmt = jake.run("""local ns = ...
    local def = ns.Sync.collections.posts
    return ns.Sync:EncodeRecordFull(def, { id = 'Anna-7-7', rev = ns.Now(), by = 'Anna-Realm', author = 'Anna-Realm', t = ns.Now(),
        title = 'From an old addon', body = 'semi;colons~and^carets' })""", jake.ns)
jake.stub.Fire("CHAT_MSG_ADDON", "PogRaid", "Y" + "AC" + "AA" + "P" + oldfmt, "GUILD", "Anna-Realm")
check(jake.run("local ns = ...; local p = ns.Sync:Store('posts')['Anna-7-7']; return p and p.body", jake.ns) == "semi;colons~and^carets",
      "sync: old-format records from 0.11 still read")
jake.run("local ns = ...; local p = ns.Sync:Store('posts')['Anna-7-7']; ns.Sync:Store('posts')['Anna-7-7'] = nil; ns.Sync.index = nil", jake.ns)

# group finder: anyone posts, one listing each, expires
mira.run("local ns = ...; ns.Social:PostGroup('Deadmines', 'tank + healer', 'Chest piece run, bring water')", mira.ns)
pump(everyone, 3)
check(jake.run("local ns = ...; local g = ns.Social:Groups()[1]; return g and (g.what .. '/' .. g.need .. '/' .. g.author)", jake.ns)
      == "Deadmines/tank + healer/Mira-Realm", "lfg: listing reaches everyone")
check(bob.run("local ns = ...; return ns.Social:Groups()[1].desc", bob.ns) == "Chest piece run, bring water",
      "lfg: description reaches everyone")
mira.run("local ns = ...; ns.Social:PostGroup('Stockades', 'dps')", mira.ns)
pump(everyone, 3)
check(bob.run("local ns = ...; local g = ns.Social:Groups(); return #g .. ':' .. g[1].what", bob.ns) == "1:Stockades",
      "lfg: posting again replaces your listing")
for c in everyone:
    c.stub.Advance(46 * 60)
check(jake.run("local ns = ...; return #ns.Social:Groups()", jake.ns) == 0, "lfg: listings expire after 45 minutes")

# request to join, end to end: Mira asks, Jake's pop-up, Jake invites, Mira hears back
jake.run("local ns = ...; ns.Social:PostGroup('Gnomeregan', 'healer')", jake.ns)
pump(everyone, 3)
lid = mira.run("local ns = ...; return ns.Social:Groups()[1].id", mira.ns)
mira.run("local ns, id = ...; ns.Social:RequestJoin(ns.Sync:Store('lfg')[id])", mira.ns, lid)
pump(everyone, 2)
check(jake.run("local ns = ...; return ns.JoinPopup.frame and ns.JoinPopup.frame:IsShown() and ns.Social:RequestCount()", jake.ns) == 1,
      "join: poster gets the pop-up")
jake.run("local ns = ...; ns.JoinPopup:Answer(true)", jake.ns)
pump(everyone, 2)
check(jake.run("return STUB.invites[#STUB.invites]") == "Mira", "join: poster's Invite invites the requester")
check(mira.run("local ns = ...; for _, m in ipairs(STUB.printed) do if m:find('is inviting you', 1, true) then return true end end", mira.ns),
      "join: requester told they're being invited")

# leaderboard times reach everyone and only improve
mira.run("local ns = ...; ns.Games:Publish('expert', 250)", mira.ns)
jake.run("local ns = ...; ns.Games:Publish('expert', 199.9)", jake.ns)
pump(everyone, 3)
check(bob.run("local ns = ...; local b = ns.Games:Leaderboard('expert'); return b[1].author .. '/' .. b[1].best .. '/' .. b[2].author", bob.ns)
      == "Jake-Realm/199.9/Mira-Realm", "leaderboard: guild times ranked on every client")
mira.run("local ns = ...; ns.Games:Publish('expert', 300)", mira.ns)
pump(everyone, 3)
check(bob.run("local ns = ...; return ns.Sync:Store('scores')['Mira-Realm:expert'].best", bob.ns) == 250,
      "leaderboard: a slower time doesn't replace a best")

# ranked duel end to end: Jake challenges Mira, she accepts, Jake wins, Bob sees the ratings
jake.run("local ns = ...; ns.Duels:Challenge('Mira')", jake.ns)
pump(everyone, 2)
check(mira.run("local ns = ...; return ns.DuelPopup.frame and ns.DuelPopup.frame:IsShown()", mira.ns), "duel: Mira gets the challenge")
mira.run("local ns = ...; ns.DuelPopup:Answer(true)", mira.ns)
pump(everyone, 2)
check(jake.run("local ns = ...; return ns.Duels.agreed and ns.Duels.agreed.opp", jake.ns) == "Mira-Realm", "duel: agreed on both sides")
for c in (jake, mira):
    c.stub.Fire("CHAT_MSG_SYSTEM", "Jake has defeated Mira in a duel")
pump(everyone, 3)
ratings = bob.run("""local ns = ...
    local t = ns.Duels:Table()
    return math.floor(t.players['Jake-Realm'].rating + 0.5) .. '/' .. math.floor(t.players['Mira-Realm'].rating + 0.5)""", bob.ns)
check(ratings == "1216/1184", "duel: every client agrees on the new ratings (%s)" % ratings)

# profiles and kudos: shared with everyone; an alt on the same account shows
# the same profile and shares its kudos; a late login catches up
mira.run("local ns = ...; ns.Profiles:Save({ status = 'Leveling my alt', icon = 134169, song = 2 })", mira.ns)
anna.run("local ns = ...; ns.Profiles:GiveKudos('Mira-Realm', 1, 'Saved the wipe')", anna.ns)
bob.run("local ns = ...; ns.Profiles:GiveKudos('Mira-Realm', 1, 'Clutch!')", bob.ns)
pump(everyone, 3)
check(jake.run("local ns = ...; local c = ns.Profiles:Content('Mira-Realm'); return c.status .. '/' .. c.icon .. '/' .. c.song", jake.ns)
      == "Leveling my alt/134169/2", "profiles: a profile reaches everyone")
check(jake.run("local ns = ...; local k, _, total, givers = ns.Profiles:Kudos('Mira-Realm'); return k[1].n .. '/' .. total .. '/' .. givers", jake.ns)
      == "2/2/2", "kudos: kudos reach everyone")
check(jake.run("local ns = ...; local _, recent = ns.Profiles:Kudos('Mira-Realm'); local m = {} for i, r in ipairs(recent) do m[i] = r.msg end table.sort(m) return table.concat(m, '|')", jake.ns)
      == "Clutch!|Saved the wipe", "kudos: with their messages")
# Mira logs in on her alt: same account (the saved data is shared), its own record
miraalt = Client("Miraalt", GUILD + [("Miraalt-Realm", 3)])
miraalt.stub.now = mira.stub.now  # everyone reads the same server clock
mira.run("local ns = ...; ns.Profiles:Mine().chars[ns.Sync:GuildName()]['Miraalt-Realm'] = ns.Now() - 5; ns.Profiles:Publish()", mira.ns)
account = mira.run("""local ns = ...
    local a = ns.Profiles:Mine()
    return a.content.status .. '|' .. a.content.icon .. '|' .. a.content.song .. '|' .. a.ed""", mira.ns)
miraalt.run("""local ns, acct = ...
    local status, icon, song, ed = acct:match('^(.-)|(%d+)|(%d+)|(%d+)$')
    local g = ns.Sync:GuildName()
    ns.db.account = { content = { status = status, icon = tonumber(icon), song = tonumber(song) }, ed = tonumber(ed),
        chars = { [g] = { ['Mira-Realm'] = ns.Now() - 5, ['Miraalt-Realm'] = ns.Now() } }, together = {}, pins = {}, hidden = {} }
    ns.Profiles:Publish()""", miraalt.ns, account)
clients = everyone + [miraalt]
miraalt.run("local ns = ...; ns.Sync:SendSummary()", miraalt.ns)  # its login fingerprint: catches up on the rest
pump(clients, 30)
check(jake.run("local ns = ...; local l = ns.Profiles:Linked('Miraalt-Realm'); return #l .. ':' .. ns.Profiles:Content('Miraalt-Realm').status", jake.ns)
      == "2:Leveling my alt", "accounts: an alt that logged in joins its account, with the same profile")
jake.run("local ns = ...; ns.Profiles:GiveKudos('Miraalt-Realm', 2, 'Held aggro on everything')", jake.ns)
pump(clients, 3)
check(bob.run("local ns = ...; local _, _, total = ns.Profiles:Kudos('Mira-Realm'); return total", bob.ns) == 3,
      "kudos: kudos to an alt count on the account")
# an edit on the alt shows on every character of the account, for everyone
anna.online = False
miraalt.run("local ns = ...; ns.Profiles:Save({ status = 'Alt life' })", miraalt.ns)
pump(clients, 3)
check(jake.run("local ns = ...; return ns.Profiles:Content('Mira-Realm').status", jake.ns) == "Alt life",
      "accounts: the newest edit wins across the account")
miraalt.run("local ns = ...; ns.Profiles:Save({ nick = 'Mimi' })", miraalt.ns)
pump(clients, 3)
check(bob.run("local ns = ...; return ns.Profiles:Name('Miraalt-Realm', true)", bob.ns) == "Mimi (Mira)",
      "accounts: a nickname reaches everyone, with the main's name")
anna.online = True
anna.run("local ns = ...; ns.Sync:SendSummary()", anna.ns)
pump(clients, 30)
check(anna.run("local ns = ...; return ns.Profiles:Content('Mira-Realm').status", anna.ns) == "Alt life",
      "profiles: a late login gets the newest profile")
def profile_keys(c):
    """Profile and kudos records with their revisions. (Whole hashes can differ for a
    while here: an expired group listing isn't handed to the newcomer, by design.)"""
    keys = c.run("local ns = ...; local out = {} for i, k in ipairs(ns.Sync:Keys()) do out[i] = k.key .. '@' .. k.rev end return table.concat(out, '|')", c.ns)
    return sorted(k for k in keys.split("|") if k[:1] in ("u", "q"))
check(len({tuple(profile_keys(c)) for c in clients}) == 1 and len(profile_keys(jake)) == 5,
      "profiles: everyone ends with the same profiles and kudos")

# attendance: an officer's raid night reaches the other officers; a raider's
# "I'll be late" reaches the raid leader
anna.run("""local ns = ...
    STUB.roster = { { name = "Anna" }, { name = "Mira" }, { name = "Bob" } }
    STUB.instance = { "Skyreach Spire", "raid" }
    STUB.isLeader = true
    ns.Attendance:Check()""", anna.ns)
# an hour of raid passes for everyone (one server clock: records from the future are refused)
pump(clients, 3600, step=5)
# the night is shared as it goes: another officer already has it, still open
check(jake.run("""local ns = ...
    for _, s in ipairs(ns.Attendance:Sessions()) do
        if s.rec == 'Anna-Realm' and not s.stop then return s.live and s.present['Mira-Realm'] ~= nil end
    end
    return false""", jake.ns) is True, "attendance: an officer's night reaches the other officers while it's still going")
anna.run("""local ns = ...
    ns.Attendance:End()
    STUB.roster, STUB.isLeader = nil, false
    STUB.instance = { "Stormwind", "none" }""", anna.ns)
pump(clients, 5)
check(jake.run("""local ns = ...
    for _, s in ipairs(ns.Attendance:Sessions()) do
        if s.rec == 'Anna-Realm' then return s.present['Mira-Realm'] .. '/' .. ns.Attendance:Credit(s, 'Bob-Realm') end
    end""", jake.ns) == "13/1", "attendance: an officer's raid night reaches the other officers")
check(jake.run("local ns = ...; local r = ns.Attendance:Summary().byName['Mira-Realm']; return r and r.last8", jake.ns) == 1,
      "attendance: and counts in their weekly numbers")
jake.run("local ns = ...; STUB.printed = {}; STUB.isLeader = true", jake.ns)
mira.run("local ns = ...; ns.Attendance:SetNotice(true, false)", mira.ns)
pump(clients, 3)
check(jake.run("local ns = ...; for _, m in ipairs(STUB.printed) do if m:find('Mira will be late tonight', 1, true) then return true end end", jake.ns),
      "attendance: a raider's I'll be late reaches the raid leader")
jake.run("local ns = ...; STUB.isLeader = false", jake.ns)

# version check: one guild message, one whisper back from each addon, nothing more
for c in everyone:
    c.stub.sent = c.lua.table_from([])
    c.stub.Advance(601)  # everyone already announced at login; wait out the 10-minute reply window
    c.stub.sent = c.lua.table_from([])
jake.run("local ns = ...; ns.Version:Announce()", jake.ns)
counts = {"V": 0, "W": 0}
for _ in range(20):
    for c in everyone:
        msgs = list(c.stub.sent.values())
        c.stub.sent = c.lua.table_from([])
        for m in msgs:
            if m.text[0] in "VW":
                counts[m.text[0]] += 1
            for d in everyone:
                if d is c:
                    continue
                if m.channel == "GUILD" or (m.channel == "WHISPER" and reaches(m.target, d)):
                    d.stub.Fire("CHAT_MSG_ADDON", m.prefix, m.text, m.channel, c.full)
    for c in everyone:
        c.stub.Advance(0.2)
check(counts == {"V": 1, "W": 3}, "version: 1 announcement + 1 reply per addon (%s)" % counts)
check(jake.run("local ns = ...; return ns.Version.seen['Mira-Realm'] and ns.Version.seen['Bob-Realm']", jake.ns) is not None,
      "version: the announcer learns everyone's version")

# officer ranks are shared: Jake makes Mira's rank an officer rank, she can post and everyone accepts it
jake.run("local ns = ...; ns.Settings:SetOfficerRank(3, true)", jake.ns)
pump(everyone, 3)
check(mira.run("local ns = ...; return ns.Social:CanPost()", mira.ns), "officers: rank change reaches everyone")
mira.run("local ns = ...; ns.Social:NewPost('Mira can post now')", mira.ns)
pump(everyone, 3)
check("Mira can post now" in posts(bob), "officers: other addons accept the new officer's post")

# small games: a Wowdle result and a Gem Cutter best reach everyone
mira.run("local ns = ...; local w = ns.Wowdle:Word(ns.Wowdle:Day()); ns.Wowdle:Guess(w)", mira.ns)
anna.run("local ns = ...; ns.db.games = ns.db.games or {best = {}}; ns.db.games.gems = {best = 5120, bestTier = 12}; ns.Gems:Publish()", anna.ns)
pump(everyone, 3)
check(bob.run("local ns = ...; local t = ns.Wowdle:Today(); return t[1] and (t[1].author .. '/' .. t[1].n)", bob.ns) == "Mira-Realm/1",
      "wowdle: today's results reach everyone")
check(bob.run("local ns = ...; local b = ns.Gems:Leaderboard(); return b[1] and (b[1].author .. '/' .. b[1].best)", bob.ns) == "Anna-Realm/5120",
      "gems: best scores reach everyone")

# someone a little behind (and holding one thing nobody else has) catches up both ways
bob.online = False
post(jake, "Consumables", "Flask list in the guild bank.")
comment(mira, "Loot rules", "Bob, bring bandages")
pump(everyone, 3)
secret = bob.run("""local ns = ...
    local def = ns.Sync.collections.comments
    local p
    for _, x in ipairs(ns.Social:Posts()) do if x.title == 'Loot rules' then p = x end end
    local r = { id = 'Bob-9-9', rev = ns.Now(), by = 'Bob-Realm', author = 'Bob-Realm', t = ns.Now(), post = p.id, body = 'written offline' }
    return ns.Sync:Apply(def, r)""", bob.ns)
bob.online = True
sent_records(everyone)
# Bob would otherwise be a slow fallback answerer: only having just listed
# makes him answer at once (he's the only one holding his comment)
bob.run("local ns = ...; ns.Sync.PRIMARIES = 0", bob.ns)
bob.run("local ns = ...; ns.Sync:SendSummary()", bob.ns)
counts = pump(everyone, 30)
bob.run("local ns = ...; ns.Sync.PRIMARIES = 5", bob.ns)
check(len({hash_of(c) for c in everyone}) == 1 and "Consumables" in posts(bob) and "written offline" in comments(jake, "Loot rules"),
      "sync: behind in both directions, everyone ends the same")
check(1 <= counts.get("L", 0) <= 2, "sync: one ask for a listing (%s)" % counts)
check(counts.get("H", 0) == 1, "sync: only the newcomer lists what they hold (%s)" % counts)
check(1 <= counts.get("N", 0) <= 2, "sync: the others ask once for what the newcomer has (%s)" % counts)
sent = sent_records(everyone)
check(len(sent) == 3 and sum(sent.values()) <= 4, "sync: exactly the missing records, a repeat at most (%s)" % sent)

# crafting: Mira opens her profession window; everyone can search her recipes
mira.run("""
    GetProfessions = function() return 1 end
    GetProfessionInfo = function() return "Alchemy", 1, 250, 300, 0, 0, 171 end
    local names = { [17635] = "Flask of the Titans", [11451] = "Major Healing Potion" }
    C_Spell = { GetSpellName = function(id) return names[id] end }
    C_TradeSkillUI = {
        GetBaseProfessionInfo = function() return { professionName = "Alchemy" } end,
        GetAllRecipeIDs = function() return { 17635, 11451 } end,
        GetRecipeInfo = function(id) return { name = names[id], learned = true } end,
    }
    STUB.Fire("TRADE_SKILL_SHOW")""")
for c in everyone:
    c.run("C_Spell = { GetSpellName = function(id) return ({ [17635] = 'Flask of the Titans', [11451] = 'Major Healing Potion' })[id] end }")
pump(everyone, 6)
found = bob.run("""local ns = ...
    local h = ns.Crafting:Search("flask")
    return h[1] and (h[1].name .. '/' .. h[1].crafters[1].name .. '/' .. h[1].crafters[1].prof)""", bob.ns)
check(found == "Flask of the Titans/Mira-Realm/Alchemy", "crafting: a guildie's recipes are searchable everywhere (%s)" % found)
check(jake.run("local ns = ...; local d = ns.Crafting:Directory(); return d.Alchemy and d.Alchemy[1].rank", jake.ns) == 250,
      "crafting: professions and skill reach everyone")

# a record the others won't take (say, from an addon on another version)
# is refused once, not asked for again at every listing
mira.run("""local ns = ...
    ns.Sync:Store('posts')['Mira-5-5'] = { id = 'Mira-5-5', rev = ns.Now(), by = 'Mira-Realm', author = 'Mira-Realm', t = ns.Now(), title = 'Not an officer post' }
    ns.Sync.index = nil
    ns.Settings:SetOfficerRank(3, false)""", mira.ns)
jake.run("local ns = ...; ns.Settings:SetOfficerRank(3, false)", jake.ns)
pump(everyone, 3)
for c in everyone:
    c.stub.Advance(20)
mira.run("local ns = ...; ns.Sync:SendSummary()", mira.ns)
first = pump(everyone, 20)
for c in everyone:
    c.stub.Advance(20)
mira.run("local ns = ...; ns.Sync:SendSummary()", mira.ns)
second = pump(everyone, 20)
check("Not an officer post" not in posts(bob), "sync: others turn down a record they don't accept")
check(first.get("N", 0) >= 1 and second.get("N", 0) == 0, "sync: and don't keep asking for it (%s then %s)" % (first, second))

# diagnostics: /pog sync ping gets answers, /pog sync shows who was heard and whether data matches
jake.run("local ns = ...; STUB.printed = {}; ns.Comm.GuildPing()", jake.ns)
pump(everyone, 3)
answered = jake.run("local ns = ...; local n = 0; for _, m in ipairs(STUB.printed) do if m:find('answered', 1, true) then n = n + 1 end end; return n", jake.ns)
check(answered == 3, "diag: sync ping answered by every other addon (%s)" % answered)
for c in everyone:
    c.stub.Advance(20)
jake.run("local ns = ...; ns.Sync:SendSummary()", jake.ns)
pump(everyone, 20)
report = bob.run("local ns = ...; return ns.Bug:SyncReport()", bob.ns)
check("Jake: " in report and "same as yours" in report and "Send problems: none" in report,
      "diag: report shows peers, matching data and no send problems: " + report)

# Forever surnames: UnitName("player") is only the first name, while the guild roster,
# whispers and addon messages use "First Surname". Keeb has a second (offline) Keeb.
FOREVER = [("Keeb Sixseven", 0, True), ("Keeb Pog", 0, False), ("Flyne Lee", 2, True, "Player-1-FLYNE"), ("Mira Stone", 3, True)]
keeb = Client("Keeb", FOREVER, "Keeb Sixseven")
flyne = Client("Flyne", FOREVER, "Flyne Lee", "Player-1-FLYNE")
stone = Client("Mira", FOREVER, "Mira Stone")
forever = [keeb, flyne, stone]
check(keeb.run("local ns = ...; return ns.PlayerName() .. '|' .. ns.Sync:Me()", keeb.ns) == "Keeb Sixseven|Keeb Sixseven",
      "surname: the one online Keeb in the roster is us")
check(flyne.run("local ns = ...; return ns.Sync:Me()", flyne.ns) == "Flyne Lee", "surname: found by character ID too")
# records Flyne shared before his full name was known move to it
flyne.run("""local ns = ...
    -- as 0.12.2 left it: shared under the bare first name
    ns.selfName = nil
    local def = ns.Sync.collections.gems
    local rec = { id = 'Flyne', author = 'Flyne', by = 'Flyne', t = ns.Now(), rev = ns.Now(), best = 900, tier = 5 }
    ns.Sync:Apply(def, rec)
    ns.Sync:Broadcast({ { def = def, rec = rec } })""", flyne.ns)
pump(forever, 3)
check(keeb.run("local ns = ...; local r = ns.Sync:Store('gems')['Flyne']; return r and not r.deleted", keeb.ns),
      "surname: (a short-name record went out first)")
flyne.run("local ns = ...; ns.Roster:ScanGuild()", flyne.ns)
pump(forever, 3)
board = keeb.run("""local ns = ...
    local out = {}
    for _, r in ipairs(ns.Gems:Leaderboard()) do out[#out + 1] = r.author end
    return table.concat(out, ',')""", keeb.ns)
check(board == "Flyne Lee", "surname: old short-name records move to the full name, no duplicates (%s)" % board)
# Flyne's professions reach Keeb (the listing ask now names the right person)
keeb.online = False
flyne.run("""local ns = ...
    ns.Sync:Write('profs', { id = ns.Sync:Me(), author = ns.Sync:Me(), t = ns.Now(), list = 'Tailoring:40:75' })""", flyne.ns)
pump(forever, 2)
keeb.online = True
for c in forever:
    c.stub.Advance(20)
keeb.run("local ns = ...; ns.Sync:SendSummary()", keeb.ns)
pump(forever, 30)
check(keeb.run("local ns = ...; local d = ns.Crafting:Directory(); return d.Tailoring and d.Tailoring[1].name", keeb.ns) == "Flyne Lee",
      "surname: a guildie's professions catch up to someone who was offline")
# own echoes are recognised: Keeb doesn't list himself as another Pog Raid user
keeb.run("local ns = ...; ns.Version:Announce()", keeb.ns)
pump(forever, 3)
check(keeb.run("local ns = ...; return ns.db.versions['Keeb Sixseven'] == nil and ns.Version.seen['Flyne Lee'] ~= nil", keeb.ns),
      "surname: our own messages aren't mistaken for someone else's")
# join request goes to the full name
flyne.run("local ns = ...; ns.Social:PostGroup('Deadmines', 'healer')", flyne.ns)
pump(forever, 3)
keeb.run("local ns = ...; ns.Social:RequestJoin(ns.Social:Groups()[1])", keeb.ns)
pump(forever, 2)
check(flyne.run("local ns = ...; return ns.JoinPopup.frame and ns.JoinPopup.frame:IsShown() and ns.Social:RequestCount()", flyne.ns) == 1,
      "surname: request to join reaches the poster by their full name")
flyne.run("local ns = ...; ns.JoinPopup:Answer(true)", flyne.ns)
check(flyne.run("return STUB.invites[#STUB.invites]") == "Keeb Sixseven", "surname: and the invite goes to the full name")

# a ranked duel counts even when the game's duel text uses first names only
keeb.run("local ns = ...; ns.Duels:Challenge('Flyne Lee')", keeb.ns)
pump(forever, 2)
flyne.run("local ns = ...; ns.DuelPopup:Answer(true)", flyne.ns)
pump(forever, 2)
for c in (keeb, flyne):
    c.stub.Fire("CHAT_MSG_SYSTEM", "Flyne has defeated Keeb in a duel")
pump(forever, 3)
ratings = stone.run("""local ns = ...
    local t = ns.Duels:Table()
    local f, k = t.players['Flyne Lee'], t.players['Keeb Sixseven']
    return f and k and (math.floor(f.rating + 0.5) .. '/' .. math.floor(k.rating + 0.5))""", stone.ns)
check(ratings == "1216/1184", "surname: a duel announced with first names still counts (%s)" % ratings)

# a guildie's new group pops up for the others; a guildie's drop shows in everyone's recent loot
for c in clients:
    c.run("local ns = ...; if ns.GroupToast.frame then ns.GroupToast.frame:Hide() end", c.ns)
bob.run("local ns = ...; ns.Social:PostGroup('Wailing Caverns', 'tank')", bob.ns)
pump(clients, 3)
check(jake.run("local ns = ...; local f = ns.GroupToast.frame; return f and f:IsShown() and f.text:GetText()", jake.ns)
      and "is forming a group for Wailing Caverns" in jake.run("local ns = ...; return ns.GroupToast.frame.text:GetText()", jake.ns),
      "toast: a guildie's new group pops up for the others")
check(not bob.run("local ns = ...; local f = ns.GroupToast.frame; return f and f:IsShown()", bob.ns), "toast: but not for the poster")
mira.run("local ns = ...; ns.Home:OnLoot('Mira', STUB.Link(23001, 'Mira Blue', '0070dd'))", mira.ns)
pump(clients, 3)
check(jake.run("local ns = ...; for _, e in ipairs(ns.Home:RecentLoot()) do if e.itemID == 23001 then return e.player end end", jake.ns)
      == "Mira-Realm", "drops: a guildie's drop shows in everyone's recent loot")

# another guild's data stays separate
bob.stub.guildName = "Other Guild"
check(posts(bob) == "", "sync: data is kept per guild")
bob.stub.guildName = None

print(f"{results['pass']} passed, {results['fail']} failed")
for f in results["failures"]:
    print("  FAIL:", f)
