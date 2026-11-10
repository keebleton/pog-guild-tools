"""Launch-night stress test for Pog Raid's guild sync.

Many addon users (each its own Lua state) log in over a few minutes holding a
month's worth of shared data (board, comments, Wowdle results, leaderboards,
duels), some of them fresh installs, some a little behind. Guild addon
messages are relayed between them under the live client's throttle (10
messages per prefix, one more each second). Reports how long it takes until
everyone holds the same data, how many messages that cost, the longest
outgoing backlog, and how long a raid plan waits behind sync traffic.

    python tests/stress_sync.py [--clients 60] [--minutes 20] [--quick]
"""
import argparse
import json
import os
import random
import sys
import time

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.environ.get("POGRAID_DIR") or os.path.join(os.path.dirname(HERE), "PogRaid").replace("\\", "/")
STUB = open(os.path.join(HERE, "wowstub.lua"), encoding="utf-8").read()

REALM = "Forever"
FIRST = ["Jake", "Anna", "Mira", "Bob", "Thrain", "Kelda", "Orla", "Fizzle", "Gorn", "Tessa", "Brakk", "Nim",
         "Ysolde", "Varek", "Pip", "Hale", "Sorrel", "Durn", "Quill", "Ember"]


def guild_names(n):
    out = []
    for i in range(n):
        base = FIRST[i % len(FIRST)]
        out.append(base + ("" if i < len(FIRST) else "abcdefghijklmnopqrstuvwxyz"[(i // len(FIRST)) % 26] * 2))
    return out


LOAD = """
local dir, player, guild = ...
STUB.player = player
STUB.realThrottle = true
STUB.guild = {}
for i = 1, #guild do
    local g = guild[i]
    STUB.guild[i] = { name = g[1], rankIndex = g[2], level = 30, online = true, class = "MAGE" }
end
local ns = {}
local toc = {}
for line in io.lines(dir .. "/PogRaid.toc") do
    if line:match("%.lua$") then toc[#toc + 1] = line end
end
for _, file in ipairs(toc) do assert(loadfile(dir .. "/" .. file))("PogRaid", ns) end
ns.DEV = nil
math.randomseed(#player * 7919 + player:byte(1) * 31 + player:byte(#player))
STUB.Fire("ADDON_LOADED", "PogRaid")
ns.Roster:ScanGuild()

-- count what goes out (and anything too big to send at all)
STRESS = { payloads = {}, dropped = {}, maxQueue = 0 }
local orig = ns.Comm.SendChunked
ns.Comm.SendChunked = function(kind, payload, channel, target, background)
    local ok, total = orig(kind, payload, channel, target, background)
    local op = kind == "Y" and payload:sub(1, 1) or kind
    local p = STRESS.payloads[op] or { n = 0, bytes = 0, chunks = 0, biggest = 0 }
    STRESS.payloads[op] = p
    p.n, p.bytes, p.biggest = p.n + 1, p.bytes + #payload, math.max(p.biggest, #payload)
    p.chunks = p.chunks + math.ceil(#payload / 240)
    if not ok then STRESS.dropped[#STRESS.dropped + 1] = op .. ":" .. #payload end
    return ok, total
end
return ns
"""

# One month after launch, generated the same way on every client so each can
# keep its own subset. A tiny LCG keeps it independent of math.random.
SEED = """
local ns, users, officers = ...
local seed = 12345
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
local function pick(t) return t[rnd(#t)] end
local function text(n)
    local words = { "raid", "tonight", "flasks", "please", "bring", "healers", "loot", "rules", "gnomes", "bosses",
        "ready", "check", "sunday", "dungeon", "group", "need", "tank", "thanks", "everyone", "great" }
    local out = {}
    local len = 0
    while len < n do local w = pick(words); out[#out + 1] = w; len = len + #w + 1 end
    return table.concat(out, " "):sub(1, n)
end
local now, day = ns.Now(), ns.Wowdle:Day()
local recs = {}
local function add(coll, r) r.by = r.by or r.author; r.rev = r.rev or r.t; recs[#recs + 1] = { coll, r } end
local posts = {}
for k = 1, 25 do
    local a, t = pick(officers), now - k * 150000
    local r = { id = a .. "-" .. t .. "-" .. k, author = a, t = t, title = "Guild update " .. k, body = text(220),
        pinned = (k <= 2) or nil }
    posts[#posts + 1] = r.id
    add("posts", r)
end
for k = 1, 150 do
    local a, t = pick(users), now - rnd(3000000)
    add("comments", { id = a .. "-" .. t .. "-" .. k, author = a, t = t, post = pick(posts), body = text(60) })
end
local levels = {}
for _, lv in ipairs(ns.Games.LEVELS) do levels[#levels + 1] = lv.key end
for d = day - 13, day do
    local seen = {}
    for _ = 1, 35 do
        local a = pick(users)
        if not seen[a] then
            seen[a] = true
            local n, len = rnd(6), 4 + rnd(4)
            local rows = {}
            for i = 1, n do rows[i] = (i == n) and ("g"):rep(len) or ("xyg"):sub(rnd(3), rnd(3)):rep(len):sub(1, len) end
            for i = 1, n do if #rows[i] < len then rows[i] = rows[i] .. ("x"):rep(len - #rows[i]) end end
            add("wowdle", { id = a .. ":" .. d, author = a, t = now - (day - d) * 86400, day = d, n = n,
                pat = table.concat(rows, ",") })
        end
    end
end
for _, a in ipairs(users) do
    for _, lv in ipairs(levels) do
        if rnd(3) > 1 then add("scores", { id = a .. ":" .. lv, author = a, t = now - rnd(2000000), level = lv,
            best = 20 + rnd(400) + rnd(9) / 10 }) end
    end
    if rnd(4) > 1 then add("gems", { id = a, author = a, t = now - rnd(2000000), best = 200 + rnd(9000), tier = 3 + rnd(8) }) end
end
for k = 1, 150 do
    local a, b = pick(users), pick(users)
    if a ~= b then
        local t = now - rnd(2500000)
        local match = a .. "-" .. t .. "-" .. k
        local w = (rnd(2) == 1) and a or b
        for _, who in ipairs({ a, b }) do
            add("duels", { id = match .. ":" .. who, author = who, t = t, match = match, a = a, b = b, winner = w })
        end
    end
end
-- professions for everyone, recipe books for most (each 60-250 recipes)
local PROFS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Mining", "Herbalism", "Skinning" }
for _, a in ipairs(users) do
    local p1, p2 = pick(PROFS), pick(PROFS)
    local mine = { p1 }
    if p2 ~= p1 then mine[2] = p2 end
    local parts = {}
    for _, p in ipairs(mine) do parts[#parts + 1] = p .. ":" .. (100 + rnd(200)) .. ":300" end
    parts[#parts + 1] = "Cooking:" .. rnd(300) .. ":300"
    local t = now - rnd(600000)
    add("profs", { id = a, author = a, t = t, list = table.concat(parts, "|") })
    for _, p in ipairs(mine) do
        if rnd(10) <= 7 and p ~= "Mining" and p ~= "Herbalism" and p ~= "Skinning" then
            local ids, n = {}, 60 + rnd(190)
            for i = 1, n do ids[i] = 2000 + i * 7 + rnd(5) end
            add("recipes", { id = a .. ":" .. p, author = a, t = t, prof = p, ids = ns.Crafting.Pack(ids) })
        end
    end
end
for k = 1, 6 do
    local a = users[k + 4]
    add("lfg", { id = a .. "-" .. now .. "-lfg", author = a, t = now - 300, what = "Dungeon " .. k, need = "healer",
        exp = now + 2400, size = 3, max = 5, desc = text(80) })
end
return recs
"""

KEEP = """
local ns, recs, keep, seed, editsBy = ...
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local n = 0
for i = 1, #recs do
    local coll, src = recs[i][1], recs[i][2]
    if rnd() < keep then
        local r = {}
        for k, v in pairs(src) do r[k] = v end
        -- this player edited their own posts/comments since everyone else last saw them
        if editsBy and r.author == editsBy and (coll == "posts" or coll == "comments") then
            r.rev = r.rev + 5000
            r.body = (r.body or "") .. " (edited)"
        end
        if ns.Sync:Apply(ns.Sync.collections[coll], r) then n = n + 1 end
    end
end
return n
"""


class Client:
    def __init__(self, name, guild):
        self.name = name
        self.full = name + "-" + REALM
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUB)
        g = self.lua.table_from([self.lua.table_from([n + "-" + REALM, r]) for n, r in guild])
        self.ns = self.lua.execute(LOAD, ADDON, name, g)
        self.stub = self.lua.globals().STUB
        self.stress = self.lua.globals().STRESS
        self.online = False
        self.received = 0
        self.watch = self.lua.eval("""function(ns)
            local q = ns.Comm.QueueLength()
            if q > STRESS.maxQueue then STRESS.maxQueue = q end
        end""")

    def run(self, code, *args):
        return self.lua.execute(code, *args)

    def login(self):
        self.online = True
        self.stub.Fire("PLAYER_LOGIN")

    def revs(self):
        t = self.run("""local ns = ...
            local out = {}
            for _, k in ipairs(ns.Sync:Keys()) do out[k.key] = k.rev end
            return out""", self.ns)
        return dict(t.items())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clients", type=int, default=60)
    ap.add_argument("--guild", type=int, default=150)
    ap.add_argument("--minutes", type=float, default=None)
    ap.add_argument("--login-window", type=float, default=180, help="seconds over which everyone logs in")
    ap.add_argument("--fresh", type=int, default=10, help="clients with a brand-new install")
    ap.add_argument("--keep", type=float, default=0.97, help="share of the data the others already hold")
    ap.add_argument("--step", type=float, default=0.2)
    ap.add_argument("--loss", type=float, default=0.0,
                    help="chance each recipient misses a message (loading screens, disconnects)")
    ap.add_argument("--quick", action="store_true", help="small run for the regular test suite")
    ap.add_argument("--json", help="write the numbers here too")
    a = ap.parse_args()
    if a.quick:
        a.clients, a.guild, a.login_window, a.fresh = 16, 40, 60, 3
        a.minutes = a.minutes or 8
    a.minutes = a.minutes or 20
    rng = random.Random(7)
    wall = time.time()

    names = guild_names(a.guild)
    guild = [(n, 0 if i == 0 else 1 if i < 4 else 3) for i, n in enumerate(names)]
    users = names[:a.clients]
    clients = [Client(n, guild) for n in users]
    print(f"{len(clients)} clients loaded in {time.time() - wall:.1f}s", flush=True)

    # seed a month of shared data, each client holding its own subset
    seeder = clients[0]
    lu = lambda c, xs: c.lua.table_from([x + "-" + REALM for x in xs])
    recs = seeder.run(SEED, seeder.ns, lu(seeder, users), lu(seeder, names[:4]))
    total_recs = len(recs)
    fresh = set(rng.sample(range(1, len(clients)), min(a.fresh, len(clients) - 1)))
    editors = set(rng.sample(range(1, 4), 2))
    for i, c in enumerate(clients):
        r = c.run(SEED, c.ns, lu(c, users), lu(c, names[:4]))
        keep = 0.0 if i in fresh else (1.0 if i == 0 else a.keep)
        c.run(KEEP, c.ns, r, keep, 1000 + i * 17, (c.full if i in editors else None))
    held = [len(c.revs()) for c in clients]
    print(f"seeded {total_recs} records; holdings min {min(held)} max {max(held)}; fresh installs {len(fresh)}", flush=True)
    hash_cost = seeder.run("""local ns = ...
        local t = os.clock(); for _ = 1, 20 do ns.Sync:Hash() end; return (os.clock() - t) / 20""", seeder.ns)

    login_at = sorted(rng.uniform(0, a.login_window) for _ in clients)
    login_at[0] = 0.0
    order = list(range(len(clients)))
    rng.shuffle(order[1:])
    when = {order[i]: login_at[i] for i in range(len(clients))}

    counts, chunks_by_op, delivered = {}, {}, 0
    peak_rate, window = 0, []
    curve = []
    board = {"asked": None, "sent": None, "queue": None}
    board_at = min(a.login_window * 0.6, 120)
    converged_at = None
    fresh_board, fresh_all = {}, {}
    t = 0.0
    end = a.minutes * 60
    next_check = 10.0
    while t < end:
        for i, c in enumerate(clients):
            if not c.online and t >= when[i]:
                c.login()
        # the raid leader shows a plan while the catch-up is busy
        if board["asked"] is None and t >= board_at:
            leader = clients[0]
            board["queue"] = leader.run("local ns = ...; return ns.Comm.QueueLength()", leader.ns)
            leader.run("""local ns = ...
                local b = { name = 'Pull plan', map = 0, items = {} }
                ns.Comm.SendBoard(b, 'RAID')""", leader.ns)
            board["asked"] = t
        step_msgs = 0
        for c in clients:
            if not c.online:
                continue
            msgs = list(c.stub.sent.values())
            if not msgs:
                continue
            c.stub.sent = c.lua.table_from([])
            for m in msgs:
                text = m.text
                kind = text[0]
                if kind == "B" and board["sent"] is None and c is clients[0]:
                    board["sent"] = t
                if kind == "Y":
                    counts["Y"] = counts.get("Y", 0) + 1
                    if text[3] == "A":
                        op = text[5]
                        chunks_by_op[op] = chunks_by_op.get(op, 0) + 1
                else:
                    counts[kind] = counts.get(kind, 0) + 1
                if m.channel == "WHISPER":
                    for d in clients:
                        if d is not c and d.online and m.target in (d.name, d.full) and not (a.loss and rng.random() < a.loss):
                            d.stub.Fire("CHAT_MSG_ADDON", m.prefix, text, "WHISPER", c.full)
                            d.received += 1
                    continue
                if m.channel != "GUILD":
                    continue
                step_msgs += 1
                for d in clients:
                    if d is not c and d.online and not (a.loss and rng.random() < a.loss):
                        d.stub.Fire("CHAT_MSG_ADDON", m.prefix, text, "GUILD", c.full)
                        d.received += 1
                        delivered += 1
        window.append(step_msgs)
        if len(window) > int(10 / a.step):
            window.pop(0)
        peak_rate = max(peak_rate, sum(window) / 10)
        for c in clients:
            c.stub.Advance(a.step)
            if c.online:
                c.watch(c.ns)
        t = round(t + a.step, 6)
        if t >= next_check:
            next_check += 5
            online = [c for c in clients if c.online]
            revs = [c.revs() for c in online]
            best = {}
            for r in revs:
                for k, v in r.items():
                    if best.get(k, -1) < v:
                        best[k] = v
            behind = [sum(1 for k, v in best.items() if r.get(k, -1) < v) for r in revs]
            for c, r in zip(online, revs):
                i = clients.index(c)
                if i not in fresh:
                    continue
                gap = [k for k, v in best.items() if r.get(k, -1) < v]
                if i not in fresh_board and not any(k[0] in "pg" for k in gap):
                    fresh_board[i] = t - when[i]
                if os.environ.get("STRESS_DEBUG") and gap and t - when[i] > 60:
                    print("    fresh", c.name, round(t - when[i]), len(gap), sorted(gap)[:6], flush=True)
                if i not in fresh_all and not gap:
                    fresh_all[i] = t - when[i]
            curve.append((t, len(online), max(behind), sum(behind)))
            everyone_in = len(online) == len(clients)
            if everyone_in and max(behind) == 0 and converged_at is None:
                converged_at = t
            if everyone_in and max(behind) > 0:
                converged_at = None
            if os.environ.get("STRESS_GAPS") and int(t) % 60 == 0:
                w = max(range(len(revs)), key=lambda k: behind[k])
                gap = sorted(k for k, v in best.items() if revs[w].get(k, -1) < v)
                print("    gaps", online[w].name, len(gap), gap[:5], flush=True)
            if int(t) % 30 == 0:
                print(f"  t={t:6.0f}s online {len(online):3d}  worst behind {max(behind):5d}  total behind {sum(behind):6d}", flush=True)

    dropped = []
    payloads = {}
    max_queue = 0
    for c in clients:
        dropped += list(c.stress.dropped.values())
        max_queue = max(max_queue, c.stress.maxQueue)
        for op, p in c.stress.payloads.items():
            agg = payloads.setdefault(op, {"n": 0, "bytes": 0, "chunks": 0, "biggest": 0})
            agg["n"] += p.n
            agg["bytes"] += p.bytes
            agg["chunks"] += p.chunks
            agg["biggest"] = max(agg["biggest"], p.biggest)

    last_login = max(when.values())
    report = {
        "clients": len(clients), "guild": a.guild, "records": total_recs, "fresh": len(fresh),
        "converged_s_after_last_login": None if converged_at is None else round(converged_at - last_login),
        "guild_messages": sum(v for k, v in counts.items()), "messages_by_kind": counts,
        "sync_payloads": payloads, "dropped_payloads": len(dropped), "dropped_examples": dropped[:8],
        "peak_guild_msgs_per_s": round(peak_rate, 1), "received_per_client": round(delivered / len(clients)),
        "max_outgoing_backlog": max_queue,
        "fresh_install_board_s": sorted(round(v) for v in fresh_board.values()),
        "fresh_install_everything_s": sorted(round(v) for v in fresh_all.values()),
        "raid_plan_wait_s": None if board["sent"] is None else round(board["sent"] - board["asked"], 1),
        "raid_plan_queue_ahead": board["queue"],
        "hash_ms": round(hash_cost * 1000, 2), "wall_s": round(time.time() - wall),
    }
    print(json.dumps(report, indent=2))
    if a.json:
        with open(a.json, "w") as f:
            json.dump({"report": report, "curve": curve}, f, indent=1)
    ok = converged_at is not None and not dropped
    print("STRESS", "OK" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
