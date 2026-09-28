# Pog Raid: notes for Claude

Jake's guild addon for **WoW: Forever** (Blizzard's Classic+ third version; beta since 9/17/2026, launch 11/4/2026).
`/pog` opens it. Published on CurseForge (project **1712125**). Jake is not a terminal person: prefer double-click
launchers and plain-English steps. Read this whole file before changing anything.

## Layout
- `PogRaid/`: the addon (Lua + `Media/*.tga`). Load order is `PogRaid.toc`. The folder name must stay `PogRaid`
  (SavedVariables `PogRaidDB` and the code are tied to it), whatever the zip is called.
- `tests/`: headless tests running the real addon files against a stub client (lupa, Lua 5.1).
- `tools/`: `package.py` (zip for CurseForge), `setup_pc.py` (new-computer setup), `make_logo.py`, `make_textures.py`.
- `Set up this PC.bat`: links the addon into the WoW AddOns folder (a junction, so edits are live after `/reload`),
  installs lupa, runs the tests. `Package for CurseForge.bat`: builds `dist/PogGuildTools-<version>.zip`.
- `dist/curseforge-description.md`: the CurseForge page text. Zips in `dist/` are not committed.

## Working rules
- Run `python tests/run_tests.py` after every change: main suite (`test_pograid.lua`), 4-client sync suite
  (`test_sync.py`), and the launch-night stress test (`stress_sync.py --quick`, plain and with 10% message loss).
  After sync changes also run `test_sync.py` with `SYNC_SEED=1..10` and a full `stress_sync.py` (60 clients).
- Mutation-check new logic: copy `PogRaid/` somewhere, break the logic, run tests with `POGRAID_DIR=<copy>`, and make
  sure a test fails. The stub has hidden real-client behaviour twice (see Gotchas), so make the stub match the game.
- Write multi-line edit scripts to a file with the Write tool; inline bash heredocs with quotes/backslashes break.
- Version lives in `PogRaid/Core.lua` (`ns.VERSION`) and `PogRaid.toc` (`## Version`); bump both. CurseForge reviews
  every upload (moderators work 8 AM to 3 PM CET, overnight in the US), so bundle changes; send test zips directly.
- No em dashes in UI strings, docs or messages for Jake (they read as AI to him). Pixel-perfect alignment matters.

## Forever client facts and gotchas
- Interface 16001, modern retail 12.0 API rules (secret values, `issecretvalue`). Function list:
  Thunderz96/forever-addon-kit `data/forever_api.json` (a real dump; check it before relying on an API).
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` is ALWAYS true on Forever. It is about addons posting
  ordinary chat, not addon messages. Only `InChatMessagingLockdown() == true` means locked, and Comm always tries the
  send and holds a message only if the client refuses it during that lockdown. (0.12.0 sent nothing because of this.)
- Characters have **surnames**: `UnitName("player")` is "Flyne" but the guild roster, whisper targets and addon
  message senders are "Flyne Lee" (no realm). `ns.PlayerName()` returns the full name found in the guild roster
  (GUID match, else the one online roster name starting with the first name; saved per character).
  `Attendance:Key` maps a bare first name from game text (loot lines, duel results) to the guild member;
  `ns.SameName` compares names allowing for this. Whispering a first name fails.
- Addon messages: 10 per prefix, then 1 per second (per sender). Anything sent during a loading screen is lost.
- Addons cannot set the guild MOTD. Blizzard's guild professions API exists in the client but may not be fed.

## Architecture
- Comm prefix `PogRaid`, messages chunked at 240 bytes (max 64 chunks). Kinds: B raid plan, X close plan, Q/R raid
  check, P self ping, Y guild sync, J/K join request/answer, D duels, V/W version, Z sync ping. Two send lanes: fast
  (plans, whispers, sync asks) and background (sync listings and records) keeping 3 sends in reserve.
- Sync.lua: shared collections per guild in `PogRaidDB.sync[guild]` (posts, comments, lfg, scores, gems, wowdle, duels,
  config, profs, recipes). Records have id/rev/by, newest wins, deletes are tombstones. Records hash into 32 buckets;
  a fingerprint "F" (bucket sums + version) goes out 15 s after login, every 10 min, after loading screens and when a
  multi-part message arrives incomplete (at most once a minute). Receivers ask the sender to list differing buckets
  ("L"), only the sender lists ("H"), others send what's missing ("E" pages, compact format; old "P" still read) or
  request what they lack ("N"). About 5 addons answer at once, the rest wait as fallbacks; anything heard from someone
  else is not re-sent. Launch-night stress result: 60 clients converge ~40 s after the last login, 0 dropped.
- Version check is deliberately light: one "V" at login, ~5 random replies ("W"); versions also ride on "F".
- Diagnostics in game: `/pog probe` (client support, lockdown values, CPU/memory), `/pog sync ping`, `/pog sync`
  (copy box: sent/failed/received, peers, fingerprint match), `/pog bug` (last 25 Pog Raid errors, `/pog bug clear`).

## Tabs
Home, Roster, Attendance, Loot, Crafting, Games, Raid Plans, Settings. Tabs are spaced by label width so every gap is
equal (`Editor:LayoutTabs`). Games: Wowdle (append-only word lists; list size must not be a multiple of 53), Sapper
Sweeper, Gem Cutter (real 2048 rules), Ranked Duels (Elo 1200, K 32, both players' reports must agree).
Crafting: professions + recipe IDs shared per player; recipes read only from your own open profession window.

## UI style (UI.lua)
Cards are a fill (UI.Card), no outline. Buttons are outlines; fill only when selected or the one primary action.
Small dim caps section titles, UI.ScrollHint on long lists, UI.ConfirmClick ("Sure?") for destructive actions.
Window 902x624 with a 36 px title band; pages use a 902x608 grid.

## How Jake likes to work
- Plain English, short, recommendation first. He isn't a terminal person: give him buttons, double-click files and
  in-game steps, and do the command-line parts yourself.
- Never suggest stopping, pausing or "a good place to wrap up". When something lands, say what's done and move to the
  next step; he decides when to stop.
- He iterates by screenshot and notices small misalignments: measure, don't eyeball.
- Keep it lean: single-agent work unless he asks for more horsepower.
- When he asks, commit and push for him (GitHub Desktop is his tool for Fetch/Pull/Push).

## Jake's decisions
- Don't change the top band without asking. No leveling race. Signups/Discord integration parked. No "what's new"
  pop-up (no extra things to click). Officer sync (rosters/attendance/loot between officers) on hold until a second
  officer can test. Mid-raid tools (boss-aware plans, soft reserves, pull timers) pinned until they can be tested in
  a raid. Remaining idea list: main/alt linking, next-raid countdown, weekly recap, Wowdle stats chart, duel seasons,
  Murloc Memory / Connect Four.
