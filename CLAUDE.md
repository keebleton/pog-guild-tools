# Pog Guild Tools: notes for Claude

Jake's guild addon **Pog Guild Tools** (shown everywhere in game, docs and on CurseForge; the folder, SavedVariables
`PogRaidDB` and the addon message prefix stay `PogRaid`) for **WoW: Forever** (Blizzard's Classic+ third version; beta since 9/17/2026, launch 11/4/2026).
`/pog` opens it. Published on CurseForge (project **1712125**). Jake is not a terminal person: prefer double-click
launchers and plain-English steps. Read this whole file before changing anything.

## Layout
- `README.md` is for players: WowUp shows it as the addon's description (it lists the addon from the GitHub repo
  keebleton/pog-guild-tools), so keep it plain English and current when features change. Developer setup, testing and
  releasing live in `DEVELOPING.md`.
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
- Keep memory low (Jake checks it): no per-item tables for long lists, don't cache what only a menu needs, and
  measure with a realistic client (collectgarbage("count") in lupa) when adding anything list-shaped.
- Mutation-check new logic: copy `PogRaid/` somewhere, break the logic, run tests with `POGRAID_DIR=<copy>`, and make
  sure a test fails. Copy only the .lua/.toc files, never `Media/`: the project is in OneDrive, and deleting a temp copy
  that included Media once deleted the real `PogRaid/Media` files (restored from git). The stub has hidden real-client behaviour three times (see Gotchas), so make the stub match the game.
- Write multi-line edit scripts to a file with the Write tool; inline bash heredocs with quotes/backslashes break.
- Version lives in `PogRaid/Core.lua` (`ns.VERSION`) and `PogRaid.toc` (`## Version`); bump both. Releasing = push a
  `v<version>` tag: `.github/workflows/release.yml` checks the tag against both, runs the tests and the BigWigs packager
  (`.pkgmeta`: `PogRaid/` moved to the zip's top, the rest ignored; `CHANGELOG.md` = this version's player-facing notes,
  replaced each release), which uploads to CurseForge (secret `CF_API_KEY`)
  and makes the GitHub release with `release.json` for WowUp (DEVELOPING.md has the steps). CurseForge reviews every
  upload (moderators work 8 AM to 3 PM CET, overnight in the US), so bundle changes; send test zips directly.
- No em dashes in UI strings, docs or messages for Jake (they read as AI to him). Pixel-perfect alignment matters.
- Fewer numbers (Jake, Oct 2026: "we're displaying too many numbers of stuff that isn't really relevant"): no counts
  that just tally a list (items, members, recipes, comments, crafters, snapshots, slots). Kept because they help:
  roster group "2/5", bench, "18 / 20", "40 raiders, 12 online", profession skill "225 / 300", duel W/L, raid kills.
  Ask before adding a new count.

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
- WoW reads `.toc` files only when the game starts: a changed file list or load order needs a full restart, not
  `/reload`. Don't make code depend on a new load order; hook up across files on ADDON_LOADED instead.
- Item links from the client (GetItemInfo, bags) colour by quality code, `|cnIQ3:|Hitem:...`, not `|cffxxxxxx`:
  read quality with `ns.Loot.Quality` (handles both, else C_Item.GetItemQualityByID), never by matching a hex colour.
- Models: Forever can only draw a character with skin from a live unit (SetUnit/SetModelByUnit: you, target, group).
  There's no SetCustomRace; models by display ID (SetDisplayInfo, SetModelByCreatureDisplayID, even our own
  C_PlayerInfo.GetDisplayID) come out untextured white, with or without SetUseTransmogSkin. Tested with Jake, Oct 2026.
  NPC models are different: they carry a baked body texture, so SetDisplayInfo(an NPC display) draws with skin from
  anywhere (VanCleef 2029, model test 5); Undress only drops separate pieces (his mask) and TryOn adds separate pieces
  (shoulders), the baked clothes stay. Forever's data has bare NPC bodies, one per race and sex (`Gear.BODIES`, display
  IDs 139629-139654, not in regular Classic; their textures are skin and underwear). Tested with Jake (model tests 6
  and 7, Oct 2026): every body draws, but only separate pieces go on (shoulders, helms); painted gear (chest, legs,
  boots, gloves) never does, not with the transmog skin switch, transmog choices, TryOn by appearance source or
  SetItemTransmogInfo. Dropped: out of range we show gear icons. Don't retry unless the client changes.
- Forever's game data is on wago.tools as build 1.60.1.x (listed under "wow_cn_beta"): DB2 tables as CSV
  (`/db2/<Table>/csv?build=1.60.1.70245`), files by ID (`/api/casc/<fileID>`, BLP textures).
- A texture with a mask (SetMask, e.g. round portraits) errors on SetTexCoord: never crop a masked texture (the stub
  now errors too). Use a separate unmasked texture for icons that need cropping.
- Addon messages: 10 per prefix, then 1 per second (per sender). Anything sent during a loading screen is lost.
- Guild data is per guild (`PogRaidDB.guilds[name]`, sync stores `PogRaidDB.sync[name]`; `ns.db.guild` is a pointer,
  dropped at logout), keyed by the guild's NAME only (`ns.GuildKey`). Found live after launch (0.16.2): on connected
  realms `GetGuildInfo`'s 4th return (the guild's realm) comes and goes (Jake's characters on "CAMWOW US2 Realm 10",
  guild on "US1 Realm 9"), so a name-plus-realm key split one guild into two tables that took turns. And just after
  login `IsInGuild()` says false for a guilded character: only believed once the guild has loaded (`ns.guildKnown`:
  PLAYER_GUILD_UPDATE or 20 s after login); `Roster:ScanGuild` records nothing until the game names the guild. DB v4
  (`mergeSplitGuilds`) merges "Name-Realm" tables and stores into "Name" and empties guild rosters filed under
  "(no guild)". Checked against a copy of Jake's real saved data.
- Dev builds (0.16.5): `Core.lua` sets `ns.DEV = true` between `--@do-not-package@` lines, which the packager (and
  `tools/package.py`) delete, so only a copy run from the repo has it. A dev build sends `ns.WireVersion()`
  ("<version>-dev") wherever a version goes on the wire (V/W/R/Z!, the F fingerprint); no addon parses that as a version,
  so Jake testing an unreleased version no longer tells the guild "a newer version is out". The tests clear `ns.DEV`.
- 0.16.5, from Jake's live data and his calls: `drops` are one record per player and item (id "<author>:<itemID>",
  renewed at most hourly; one guildie farming Stockade was 176 of 231 shared drops) and Recent loot shows each
  player's item once, 8 lines a player at most. Late = more than 15 min after the raid gathered AND after the first
  boss attempt ended (`s.bosses`). Pugs met in a raid are `players[name].pug` (not `manual`), so only guild members and
  players added by hand are in the roster pool (DB v5 converts old ones: `manual` without `rev`). Group names are
  matched to roster names through `Attendance:Key` (Roster `who()`), and its name cache is cleared by whoever adds or
  removes a player. Wowdle doesn't focus on open: clicking the board or `/pog wowdle` does (`Wowdle:Focus`). Sync's
  index judges expiry at the turn of the minute (`expired(rec, now)`), so every addon drops an expired record from its
  fingerprint together.
- 0.16.5 group chat (`Chat.lua`, `ns.Chat`; Jake: "like aim/msn"): a window of its own (`PogRaidChat`, position key
  "chat"), not an Editor tab. A chat IS its set of people: key = the sorted full names joined by ","; kept per guild in
  `guild.chats[key] = { key, members, log = { { t, from, text, sys } }, last, unread, test }` (200 lines a chat, 30 chats,
  local only: chat is NOT a Sync collection, so old versions' fingerprints are untouched). Wire: Comm kind "C", chunked,
  WHISPER only, one whisper per other member who is online: `M<n:2><the others' names, comma separated><text>`, or `N`
  ("chat is off here", sent back at most once a minute per sender). A line is taken only from an in-guild sender, with
  our name in the list, at most 8 people, nobody twice; text has control characters removed, is cut at 200, and every
  "|" is escaped when shown (no colours, textures or links from a line, in the log or the pop-up). Buddies = online
  guildies whose known version is >= `Chat.MIN_VERSION`; a dev build is known by `Version.dev[name]` (its base version,
  this session only, never listed or warned about). `settings.chat == false` turns it all off (the Home button hides,
  the window closes, senders are told). `/pog chat test` makes a practice chat (`c.test`) that answers back and never
  whispers anyone; a real line from that person makes it a real chat. Entry points: Home's Chat button (left of Show
  offline, "Chat (n)" when unread), the Online now right-click menu, `/pog chat`, and the pop-up.
- 0.16.7 whispers in chat (Jake: "save in game whispers from guildmates"): `CHAT_MSG_WHISPER` / `_INFORM` with a guild
  member are logged into the 1:1 chat with them as lines with `w = true` (`Chat:OnWhisper`; the INFORM event is the ONLY
  place our own whispers are logged, so one typed in the window isn't added twice). No pop-up or sound for them (the
  game has shown it); incoming ones count as unread, our own reply marks the chat read. A `w` line is shown as the game
  sent it (links work, `OnHyperlinkClick` -> `SetItemRef`); addon lines stay escaped. `Chat:HasChat(name)` = the addon's
  own lines reach them (version >= MIN_VERSION, not off); `Chat:CanChat(name)` = online and HasChat, or any guild member
  when `Chat:Whispers()` (`settings.chatWhispers`, the "Guild whispers" check in the chat window's title bar: Settings'
  General card has no room left). A 1:1 line to someone online without HasChat goes out with
  `C_ChatInfo.SendChatMessage or SendChatMessage` (every "|" doubled), never in `Comm.IsRestricted()`; if no INFORM
  comes back within `Chat.WHISPER_WAIT` the chat says it didn't go. Groups of 3+ need HasChat for everyone (the list
  refuses the pick and says why). `GUILD_ROSTER_UPDATE` calls `Chat:RosterChanged` (list and heading only: redrawing
  the log lost its scroll position). Not yet proven on the live client: sending a real whisper from addon code.
- 0.16.8: the chat window's title bar has four checks before the X: In game chat (`settings.chatEcho`, the only one
  off by default), Sound (`settings.chatSound`), Pop-ups (`settings.chatToasts`) and Guild whispers, each as wide as
  its box and words (`14 + 8 + label width`) and 16px apart, with tooltips hooked on (`HookScript`: `SetScript` would
  replace UI.Check's own hover). `Chat:Notify` checks sound and pop-ups; the unread count doesn't depend on either.
  `Chat:Echo` writes an incoming addon line (never a whisper, never our own) to DEFAULT_CHAT_FRAME in whisper pink:
  "[Pog chat] Name: text", or "[group name or its people] Name: text". No volume slider: the game plays a sound kit at
  its channel's volume and gives addons no per-sound volume (Jake asked; a mute is what's possible). Settings' "Pop-up
  sounds" still mutes all.
- 0.16.9 Motherlode (`Lode.lua`, `ns.Lode`; Jake asked for "a peggle roguelike": ours is its own game in that genre,
  never Peggle's name, levels or look). Games tab mode "lode" (`/pog lode` or `/pog motherlode`). Rules in `Lode.Run`
  (no UI, dice from `Lode.Rng(seed)` so a run replays exactly): board space 560 x 566, y DOWN; a bomb drops from the
  mortar at an angle from straight down (max 80 degrees), gravity and bounces in fixed 1/240 s ticks (`Run:Step` takes
  real elapsed time). A peg is mined once (`Mine`), stays to bounce on until the shot ends, crumbles at once after 3
  bounces; kegs blow up their neighbours (chaining), crystals split the bomb; the pocket a bomb lands in (x1 x2 x5 x2
  x1) multiplies what THAT bomb mined. Floor quota `Lode.Quota` = 450 x 1.5 per floor, 5 bombs; reach it for a pick
  of 3 upgrades (`Lode.UPGRADES`, each with a cap) and the next floor, else the run is over. Tuned by simulation
  (scratch script: random clicking clears ~2 floors, best of 4 aims ~7, best of 10 ~9); retune `QUOTA` /
  `QUOTA_GROWTH` from Jake's playtesting. UI: board card left (pegs are round-masked ore icons from item IDs, a tinted
  disc where masks aren't available), run card right (floor, ore / quota bar, bombs, upgrades, best, New run with a
  confirm click mid-run), overlays on the board (how to play, the 3 upgrade tiles, run over). Best run in
  `db.games.lode = { depth, ore, runs }`. Guild hiscores (Jake: "add a hiscore", after being told the cost): the `lode`
  Sync collection (code "m", id = author, fields depth and ore), written by `Lode:Publish` when a run is a new best
  (and once when the game is first opened, for a best made earlier). `Lode.share = true`; false stops the writing.
  The cost, accepted: an addon older than 0.16.9 can't file a record of a collection it doesn't know and asks for it
  again at every check-in, a few small messages every ten minutes while old and new are online together, until it
  updates. The list (`Lode:ScoreRows`: top 8, ours on the last row with its real rank if we're lower) is on the
  board's overlay before and after a run, and mid-run from the Hiscores button at the card's foot (`showScores`,
  only while aiming; no bomb drops while it's up; Back returns to the same run).
  Naming trap: the rules constructor is `Run.New(seed)`; `Lode:NewRun()` is the button's handler.
  Looks (Jake: "more visually appealing", "the ball could be brighter or more dopamine enhancing"): a faint talent
  picture behind the board (`Lode.ART`, not a gallery page: its "Use on" row is full) under a top-to-bottom shade; pegs
  have a shadow, a ring in their colour, a glow and flash when lit, a ring that jumps when hit (`POP`) and they fade
  out when mined (`FADE`) instead of vanishing; the bomb is a bright core in an additive glow with `TRAIL` sparks
  behind it; "+10" floats off every peg mined (bigger and gold for gold, green "x2" for a lucky one), a keg's blast is
  a spreading ring, the pocket pays out in a big "x5  +500" with a coin sound, a "6 pegs" count runs top right and
  `Lode.PRAISE` words pop at 6 / 10 / 14 / 18 pegs in one shot. All of it is driven by `Run.events` (mine / hit / blast
  / land, emptied by `Lode:ShowEvents` each frame; `Fire` starts the list afresh) and `Lode:StepEffects(dt)`; the
  rules never wait on an effect. A bomb's spark path is noted once a frame in `Update` (not in `Draw`, which also runs
  inside `Refresh`). `Lode.catcher`: an invisible button under the board and run card, 320px past either side and
  170px below (never above the board), shown only while a bomb is waiting, so a click that slips off the board or the
  window while aiming still drops it (Jake); it sits at the view's own frame level, below the cards.
- 0.16.9 Motherlode polish (Jake, from his screenshot: "go a little deeper on the design"): the mortar is a dark bowl in
  a gold ring with a barrel that turns to the aim (`Lode:AimBarrel`; the Goblin Mortar icon read as a black crescent);
  a hit peg keeps its picture under a halo (`LIT_GLOW` 0.5, a faint wash) instead of blowing out to a white disc
  (`FadePeg` gives the glow its own strength); gold, kegs and crystals pulse faintly at rest (`IDLE_GLOW`); a new
  floor's pegs fade in top rows first (`APPEAR`, `STAGGER`); the walls fall into shadow; the quota also fills a 3px bar
  along the top of the board (`Lode.topBar`); a keg and the best pocket flash the whole board (`Lode:Flash`). The run
  card: FLOOR in 30pt gold with the seam's ore icon, a 12px quota bar with "225 to go" / "Quota reached", bomb pips,
  upgrades (icon, name, count), a "Pegs" legend (what each kind does and is worth on this floor with these upgrades;
  it hides if more than 8 upgrades reach down to it) and the foot (best, New run).
- 0.18.0 kill on sight (`Kos.lua`, `ns.Kos`; asked for by guildies: "a KOS list for horde", a pop-up when someone is
  marked, "/pog kos [NAME]"). Sync collection `kos` (code "t"): id = `Kos.Key(name)` (lower case, single spaces), `name`
  as typed, `note` (60). Anyone marks; only the marker (`by == author`) or an officer changes or deletes. `perRecord`:
  `Kos:OnRecord` pops up once per mark (`Kos.told`, only one marked in the last `FRESH` 10 min, never our own). The
  spotter: PLAYER_TARGET_CHANGED, UPDATE_MOUSEOVER_UNIT and NAME_PLATE_UNIT_ADDED -> `Kos:Check(unit)`: a player whose
  `UnitName` (first, surname; secret values skipped) is on the list is called out (chat line, RAID_WARNING sound, pop-up
  note; the note waits out combat like all notes, the chat line and sound don't), each player once per `SPOT_EVERY`
  5 min. `Kos:Find` matches a whole name, or by first name when the mark or the sighting has only that. `/pog kos`
  opens the window (`PogRaidKos`, DIALOG strata like chat: two boxes and Add, the list, Add target, an Alerts check =
  `settings.kosAlerts`); `/pog kos Name Surname reason` (`Kos.Parse`: up to a comma, else the first two words are the
  name); `/pog kos remove Name`. Guild members can't be marked; 100 marks at most. Same cost with older addons as the
  hiscore collections. Seen in game by Jake (Nov 2026): targeting a marked Horde player gave the chat line with level,
  race and class, so enemy names do come through `UnitName`.
  The window (Jake, from his screenshot of the plain list: "a bulletin board of targets"): a wood-coloured board of
  wanted posters, 3 across and 2 down (`poster()`: tan paper with the game's parchment over it, a pin, "Wanted", the
  skull, the name in dark red, why, "by X"; dark ink with no text shadow), the wheel moves a row of posters at a time;
  beside it the Hunters card. Kills (Jake: "people who have killed the most people marked as KoS by other people"):
  Forever closes COMBAT_LOG_EVENT_* to addons (registering it gets the addon blocked), so kills come from PARTY_KILL
  (killer GUID, victim GUID; ours and our group's). `Kos:Check` notes the GUID of every marked player we come across
  (`Kos.guids`, alerts on or off), else `GetPlayerInfoByGUID` names the victim. A kill counts for a mark someone else
  made, once per `KILL_EVERY` 5 min per target; `koskills` collection (code "j", id = author, `n`, `last` = the latest
  victim's name, `perRecord`): `Kos:OnKills` pops up "X got Y" once per new count, fresh ones only. `Kos:Hunters`.
  Not proven in game yet: that PARTY_KILL fires for player kills in the open world.
- 0.19.0: Motherlode is called **Poggle** wherever a player sees it (the guild's name for it; Jake: "let's change the
  name to Poggle"): the Games tab, the card title, the start screen, `/pog poggle`, README, CHANGELOG. Everything
  inside keeps "lode" (`Lode.lua`, `ns.Lode`, the tab key, `db.games.lode`, the `lode` collection), and
  `/pog motherlode` and `/pog lode` still work. These notes say Motherlode for the same reason.
- 0.19.0 Motherlode 2 (Jake: "people are really loving motherlode ... make it a really good game", with the guild's
  feedback). What changed in `Lode.Run`, and why:
  * Pockets are gone (guildies: "too much RNG", missing the x5 "can feel pretty bad"). Ore banks as mined
    (`Run:Land`). A mine cart (`run.cart`, `Lode.CART_W` 80, `CART_SPEED` 150, moved by `Run:MoveCart` only while a
    bomb flies) gives the bomb back when it lands in it: `Lode.CATCHES` 3 a floor (`Run:CatchesLeft`, shown on the cart).
  * No dead ends ("you will never be able to go to the next stage even if you have pegs left"): after a shot,
    `Run:Spent()` (ore + `Potential()` < quota AND half the pegs or fewer left, `CAVE_AT`) brings `Run:CaveIn()`, a
    fresh board with ore and bombs kept. Deep floors need several boards by design. The run ends only on 0 bombs.
  * Aim ("I cannot aim at the pegs in the top right / left corner"): `MAX_AIM` 88 degrees, and `Lode.Board` never
    puts a peg above `Lode.Ceiling(x)`, the flattest shot's path.
  * Classes (`Lode.CLASSES`, `Run.New(seed, class)`): Warrior +2 bombs a floor; Mage Twin Fuse built in; Rogue gold x2
    and 10% luck; Hunter cart 1.5x wide with Lodestone built in. `Lode.UPGRADES[i][5]` = the class an upgrade belongs
    to; `Run:Offers` gives a class its own, never another's, never what it has `built` in. A run without a class is
    still legal (the old tests use it). The screen asks for the class: `Lode:NewRun()` with no seed opens the picker
    (`Lode.picking`, four tiles, the last class marked from `db.games.lode.class`); `NewRun(seed)` or
    `NewRun(nil, false)` starts without one.
  * 23 upgrades. Anything that gives a bomb back goes through `Run:GiveBomb`: ONE a shot whatever the source
    (`run.given`), upgrades' ones `Lode.GIFTS` 2 a floor. Keep it that way: the balance script found three ways to
    play for ever before those limits (two halves of a split bomb both caught; Bloodthirst refunding every Cleave
    shot, so it now pays +50% instead; Lodestone catching every shot).
  * Balance (scratch script `lode_sim3.py`: per class, a random clicker and one that tries 4 aims): random clears 0-3
    floors, careful play 9-10, every class ends. `QUOTA` 450 x 1.5 unchanged. Rogue looks strongest. Retune from play.
  * Tests: the 0.16.9 block switches the cart and cave-ins off (`Lode.CART_W = -1`, `Lode.CAVE_IN = false`) because it
    watches one peg at a time; the 0.19.0 block covers the new rules and the picker.
  Not seen in game yet: the cart's look, the class tiles (class pictures come from the character-creation sheet with
  `CLASS_ICON_TCOORDS`), the upgrade icons' item IDs (`Lode.UPGRADE_ITEMS`), and how the cave-in reads on screen.
- 0.18.1 (Jake, from a poster a guildie made reading "<Kraken Skulls>"): `Kos.Show(name)` drops angle brackets wherever
  a mark is shown; `Kos:Add` stores new marks without them; old ones keep them in the record (the id must equal
  `Kos.Key(name)`), so `Find`, `Add` and the spotter also look under "<key>". A mark can be a guild: `Kos:Check` falls
  back to `GetGuildInfo(unit)` (whole name only) and the call-out then leads with the player's first name.
- 0.18.1 map dots match OneForAll's (Jake saw two sizes side by side): the "PlayerPartyBlip" atlas tinted to the
  class, 14px on a zone and 10px on a continent or the world (`mapType <= Continent`), scale = 1 / the scroll
  container's `GetCanvasScale()`. Our disc with a dark edge is only the fallback.
- 0.18.0 guildies on the world map (`GuildMap.lua`, `ns.GuildMap`; asked for by guildies). An addon can't read where
  anyone else is, so each one says where its own player is: Comm kind "G" on GUILD, one unchunked message in the
  background lane, `G1:<map>:<x>:<y>:<continent>:<wx>:<wy>` (x, y in 1/10000 of the zone map; world yards from
  `C_Map.GetWorldPosFromMapPos`) or `G0` (no position: an instance, or switched off). `GuildMap:Tick` every 5 s: sends
  when moved (`MOVE`) at most every `MIN_GAP` 20 s, every `BEAT` 120 s standing still, and never while the sync queue
  is busy (`Comm.BulkIdle`). Dots (`GuildMap:Refresh`) are frames on `WorldMapFrame:GetCanvas()`: class colour from the
  guild roster, the sender's own x, y on their zone's map, `C_Map.GetMapPosFromWorldPos` on any other map, scaled by
  map scale / canvas scale so zooming doesn't grow them; group members are skipped (the game draws them); a dot goes
  `STALE` 300 s after its last message, or 45 s after the roster says they're offline. Hooks: the map's OnShow,
  OnMapChanged, OnCanvasScaleChanged (all three exist on this client: another addon on Jake's PC uses them).
  `settings.guildMap` (on by default) is one switch for sending and seeing; `/pog map` and the minimap button's menu
  flip it, and so does Settings' "Share location on the guild map" (Jake asked for a tick there, default on).
  Old versions ignore kind "G". Not seen in game yet.
  OneForAll (another addon on Jake's PC, by Smoergi) draws guildies too, from its own prefix "OFAGuildPos" ("P<tab>..."
  a place, "X" gone, "I..." in a dungeon). Different prefix, own frames: neither breaks the other. To avoid two dots on
  one guildie who runs both, `GuildMap:OnOther` listens to that prefix (never sends on it) and `GuildMap:Doubled` skips
  our dot while OneForAll is loaded here, its `OneForAllDB.qol.guildMap` isn't false, and it had a place for them in
  the last 180 s (its own forget time).
- 0.18.0 added two files to the .toc. A player who updates and only does /reload doesn't have them until the game
  restarts, so everything outside them that touches `ns.Kos` or `ns.GuildMap` checks it exists first (the minimap
  menu, /pog kos, /pog map, /pog reset, Comm's "G"). Do the same for any file added later.
- 0.17.0 Siegebreaker (`Siege.lua`, `ns.Siege`; Jake: "roguelike BrickBreaker like the OG game", then "make it like 50"
  levels). Our own game in that genre: never the BlackBerry game's name or its levels. Games tab mode "siege" (tab
  label "Siege", `/pog siege`). Rules in `Siege.Run` (no UI, dice from `Lode.Rng`): the paddle is the mouse
  (`Run:Step(dt, mouseX)`), a click fires what's on the paddle (`Run:Launch`); fixed 1/240 s ticks; a ball leaves the
  paddle at an angle set by where it landed (62 degrees at the ends, never dead straight), keeps at least `MIN_RISE`
  of its speed vertical, and quickens 2% a paddle hit up to 1.5x until one is lost (`pace`: at a flat speed a bot took
  three minutes over the first wall). Three lives; a wall is down when everything but steel is. Walls are rows of 13
  characters (`Siege.LEVELS`, 50 = 10 tiers x 5; `pic` drawn by hand, `gen` by a rule per cell): lowercase colour
  letters 1 hit, uppercase 2, `%` stone 3, `#` steel, `*` powder (destroys the 8 round it, chaining), `$` gold. Stage
  n draws one of tier n's five (past tier 10, any of the harder half), 4% faster a stage up to 1.6x. Pickups drop
  from 8% of broken bricks (multi, wide for 15 s, life); nine upgrades (`Siege.UPGRADES`; Tar Paddle was
  removed in 0.19.0, Jake's call). `Run.events` drives the
  effects, as in Motherlode, whose drawing helpers it shares (`Lode.util`). A scratch script had a bot (paddle
  follows the lowest ball) clear all 50; every wall is also checked for reachability (no brick walled in by steel):
  keep both true when adding walls. Hiscores: Sync collection `siege` (code "b", id = author, stage and score), same
  cost with pre-0.17 addons as Motherlode's. Six game tabs now, so Sapper Sweeper's difficulty buttons are 78 wide
  (`LEVEL_W`). The catcher (clicks off the board) is up while a ball waits on the paddle, including a Tar Paddle catch.
- 0.17.0: Home's Activity rows show the whole line (and how long ago) in a tooltip when the row's text is cut off
  (`row.text:IsTruncated()`; an achievement row keeps its achievement tooltip, with the line added under it).
- 0.16.10: `Roster:Poll` asks the game for the guild roster every `Roster.POLL` (30) seconds from login (not in combat).
  Before, it was only asked for when the Home or Roster tab showed, so level-ups (and their pop-ups) were noticed only
  when the window opened (Jake). The milestone pop-ups no longer play the game's level-up sound (it read as our own
  level-up): the small ones are silent, the 60 banner keeps IG_QUEST_LIST_COMPLETE.
- 0.16.9 level milestones (`ns.Milestone`, in JoinPopup.lua): `Roster:ScanGuild` passes each level-up's old level
  (`from`); `Home:OnGuildScan` hands live ones (not `away`) to `Milestone:OnLevel`. `Milestone.Crossed(from, to)` is
  the highest of 20/30/40/50/60 passed. Below 60: a note in the new-group pop-up with their portrait (click opens a
  chat to say grats). 60: `PogRaidLevelBanner`, no box, a dark cloud and gold light, their portrait in a gold ring,
  the name in class colour, "LEVEL 60" in 36pt, rules that open out, sparks drifting up; it lands at scale 1.18 and
  settles, holds 7s, fades; banners queue and wait out combat. Sound: the game's level-up (SOUNDKIT.LEVELUP or 888).
  `settings.levelToasts`; `/pog ding` previews the banner, `/pog ding 40` the small one.
- 0.16.9 `settings.gamesOnFlight` (off by default): PLAYER_CONTROL_LOST, then a second later `UnitOnTaxi("player")`,
  opens the Games tab if the window is closed (`Games:OnControlLost`). Nothing closes on landing.
- Settings' General card has eleven checks at `CHECK_PITCH` 21 (both cards; each row is exactly that tall), `GENERAL_H`
  323: ten officer ranks fit under it with room to spare. A check's 4th entry is a tooltip. 21 is as tight as rows of
  12pt text should go: a twelfth check needs a second column or a rethink.
- 0.16.9 pages refresh only when really on screen: every `X:Changed()` guard is `page:IsVisible()`, not `IsShown()`. A
  page of the closed window is still flagged shown, so background sync kept redrawing whichever tab was last open; on
  Profiles that restarted the profile song with the addon closed (Jake). `Profiles:Open` uses it too, so asking for a
  profile with the window closed opens the window. The test stub's `IsVisible` walks the parents, and the tests' copy
  of `Editor:ShowTab` opens the window (as /pog and the tabs always do in the game).
- 0.16.9: the "[label]" of an echoed line is a link, `|Haddon:PogRaid:chat:<n>|h[label]|h` (`Chat:Link`; n is a
  session number for the chat, `Chat.links` / `Chat.linkOf`). Clicking it runs the game's `SetItemRef`, which leaves
  "addon" links alone, then our `hooksecurefunc("SetItemRef")` -> `Chat:OnLink` opens that chat with the keyboard in
  its box. Same mechanism as Questie's links on this client (a post-hook, so nothing is tainted).
- 0.16.8 group name and picture (Jake: "like imessage"): `c.name` (cleaned by Codec.CleanText, 24 chars), `c.icon` (a
  file ID from `Profiles:IconChoices()`), `c.metaAt` (when set; the newest wins). Groups only (`Chat:IsGroup`, 3+).
  Set from Edit in the chat's heading or its right-click menu (`Chat:Menu` -> `UI.Prompt` / `UI.Picker`); `SetMeta`
  whispers `R<n:2><names><at>~<icon>~<name>` to everyone online with HasChat. `OnMeta` takes a newer one, ignores one
  with our stamp, and answers an older one with ours. `Chat.told[key .. "\n" .. name]` (session) is the stamp each
  member has from us: someone who writes a line without it is sent it once, so people who were offline catch up.
  0.16.5 to 0.16.7 ignore "R" (unknown op), so they just don't see names. `Chat:Title` = the name, else
  `Chat:Members`; `Chat:Picture` = the group's icon (or `Chat.GROUP_ICON`), or the other person's portrait. The chat
  list rows and the heading show the picture.
- 0.16.8 Home: a Chats card (`Home.chatsCard`, `BuildChats` / `RefreshChats`) has the bottom third of what was all
  Message board: `CHATS_H = HEAD_H + 8 + 3 rows`, `BOARD_H = HALF_H - GAP - CHATS_H` (the board now shows two posts and
  scrolls). Rows: picture, title, a grey preview of the last line (`Chat:Preview`: "You: ", or the speaker in a
  group), and on the right the unread count in the accent colour, else how long ago. Click opens the chat; "New chat"
  in the heading and the "Start a chat" button (when there are none, like LFM's) call `Chat:StartNew` (the window on
  its picker). An open post still takes the whole column and hides it. `Chat:Badge` / `Chat:Changed` call
  `Home:ChatsChanged` (just this card). The Chat button beside Show offline is gone.
- 0.16.7 chat window layout (Jake, from his screenshot: chats and the whole guild in one column "looks a little
  confusing"): the left list is ONLY our chats (`Chat:Items`, "No chats yet" when empty) with a New chat button under
  it. New chat (`Chat.picking`) shows the picker in the right card in place of the open chat: a search box (any part
  of the short name, case-blind; Enter with exactly one name left opens that chat), everyone from `Chat:Buddies()`
  (those without HasChat tagged "whisper"), a two-line hint bottom left, Cancel and Start chat (n). `Chat:Pickable`:
  the first pick is anyone; after that a name is greyed out (`row.dim`, alpha 0.35, disabled) when the chat is full
  ("full") or when it or a pick lacks HasChat ("addon"), and the hint says which. Nothing is printed to the chat box
  for a refused pick any more (it spammed). While picking, the chat underneath isn't being watched (`Chat:Watching`), so
  its new lines count as unread until Cancel. Opening any chat (list, pop-up, Home menu) closes the picker.
- 0.16.6: the chat window is on the DIALOG strata, toplevel, and `Raise()`d on every `Chat:Open`. On HIGH (the main
  window's strata, which is toplevel) it opened behind the main window, so Home's Chat button seemed dead. Any new
  window that can be opened from inside the main window needs the same.
- 0.16.5 pop-up notes: `ns.GroupToast:Note({ icon, text, sub, onClick })` shows other news in the new-group pop-up, one
  at a time (`Toast.notes`, at most 5 waiting, held back in combat until PLAYER_REGEN_ENABLED; a new group listing takes
  the pop-up over). Chat lines use it, and so do kudos: the `kudos` collection is `perRecord`, and `Profiles:OnKudos`
  pops up for a record to one of our characters from someone else's, in the current week, of a kind that isn't retired,
  whose count is above `guild.kudosSeen[id]` (so each kudos shows once; a take-back lowers it). `settings.kudosToasts`.
  Settings' General card is 300 tall now (eight checks); ten officer ranks still fit in the card under it.
- 0.16.5 design, from Jake's screenshots (Nov 2026): the Wishlist sheet is 7 armour slots a side (Hands on the left) with
  the weapons in a row on the sheet's ninth row (`side = 3`: Main Hand under the left column, Off Hand centred, Ranged
  mirrored under the right); Activity lines found at login or for an offline member carry `away` and show no time;
  Most played with tiles show the first name (a nickname whole); Wowdle's stats bars are `UI.ACCENT` at `BAR_ALPHA`;
  LFG skips the journal's `questChainPage` entries (Cozy Sleeping Bag). Jake's own wording, leave it: "no groups atm",
  "nobody looking atm". Still open (his call): nine red buttons on Raid Plans, "> " marks in menus, log-style chat lines,
  one cool grey for dim text on the warm themes.
- Addons can't call ReloadUI ("Interface action failed because of an AddOn"; Jake hit it, Oct 2026; the stub errors
  too): `UI.ReloadButton` is a SecureActionButtonTemplate running the /reload macro on the player's click.
- Addons cannot set the guild MOTD. Blizzard's guild professions API exists in the client but may not be fed.

## Architecture
- Comm prefix `PogRaid`, messages chunked at 240 bytes (max 64 chunks). Kinds: B raid plan, X close plan, Q/R raid
  check, P self ping, Y guild sync, J/K join request/answer, D duels, V/W version, Z sync ping, C chat,
  G where a guildie is (GuildMap). Two send lanes: fast
  (plans, whispers, sync asks) and background (sync listings and records) keeping 3 sends in reserve.
- Sync.lua: shared collections per guild in `PogRaidDB.sync[guild]` (posts, comments, lfg, scores, gems, wowdle, duels,
  config, profs, recipes, profile, kudos, nights, notice, drops, wish, gear, lfd, lode, siege, kos, koskills). Records have id/rev/by, newest wins, deletes are tombstones. Records hash into 32 buckets;
  a fingerprint "F" (bucket sums + version) goes out 15 s after login, every 10 min, after loading screens and when a
  multi-part message arrives incomplete (at most once a minute). Receivers ask the sender to list differing buckets
  ("L"), only the sender lists ("H"), others send what's missing ("E" pages, compact format; old "P" still read) or
  request what they lack ("N"). About 5 addons answer at once, the rest wait as fallbacks; anything heard from someone
  else is not re-sent. Launch-night stress result: 60 clients converge ~40 s after the last login, 0 dropped.
- Version check is deliberately light: one "V" at login, ~5 random replies ("W"); versions also ride on "F".
- Diagnostics in game: `/pog probe` (client support, lockdown values, CPU/memory), `/pog sync ping`, `/pog sync`
  (copy box: sent/failed/received, peers, fingerprint match), `/pog bug` (last 25 Pog Raid errors, `/pog bug clear`).
- Game art: Jake loves using the client's own art as subtle backgrounds (nothing shipped, no addon memory). `/pog art`
  (Art.lua) is a gallery of candidates (classic talent trees and dressing rooms as 4-piece quads, modern talent and
  dressing room atlases, dungeon/raid/world loading screens, PvP window art), showing only what this client has
  (GetFileIDFromPath, C_Texture.GetAtlasInfo). Pick from it with Jake before wiring art into a page.
  Also: "Dungeon journal" (EJ_GetInstanceInfo's background and lore files, every tier, the selected tier put back),
  faction crests, stationery and parchment, and "Try your own" (a file path, file ID or atlas name; `Art.Custom`; picks
  kept as { "Custom", text } and found again by `Art.Find`). Files cover an area at 4:3 (`item.aspect`), cropped.
  Jake can browse every client texture on wago.tools (Files).
  Talent tree helpers: `Art.Trees(class)`, `Art.TreeArt(class, i)` (classic quad, else the modern atlas),
  `Art.Cover` (crop to fill). Classic talent pictures are painted on 296x332 of their 320x384 pieces (dark padding
  beyond, once hidden by the talent window's frame): `Art.TALENT_W/H`, always size by that. Jake tried them as a profile page background and didn't like it there (it clashes
  with the Character card's dressing room art): keep them off the profile page.
  Page art (Oct 2026): one picture per page, the same for everyone (not by class), strong (70%, Jake, Oct 2026; was a faint 30% that let the theme's surface through) inside one solid card
  in its BACKGROUND layer above the fill: `Art.PAGES` (roster pool, attendance and loot tables, crafting results,
  wowdle guild card, settings "Who has"). Jake chose Settings "Mage: Fire", Wowdle "Mage: Arcane", Loot "Druid: Restoration", Roster "Priest: Holy", Duels
  leaderboard "Rogue: Subtlety"
  (Attendance and Crafting are still placeholders). Home's Message board shows the player's current spec's
  remastered talent art (`Art.MySpec`: GetSpecialization, matched by name; `Art.ModernTreeArt`: the atlas, else the
  classic picture; tree 1 before a spec), updated on PLAYER_SPECIALIZATION_CHANGED.
  No icons on Home's card titles and no art behind the Home banner (Jake tried both and didn't like them). Home has
  no banner across the top (Jake, Oct 2026: the stat tiles, level chart and launch countdown read as a dashboard and
  took too much space): the guild has its own card (`Home.header`, 262 x 88) heading the left column, like the game's
  guild window: no logo (it's in the window's corner portrait, Jake), guild name big (22) and gold in angle brackets
  ("<pog>", Jake), the MOTD (12, two lines), the guild's banner hanging from the card's top-right edge (Jake: the
  Communities pennant, "communities-guildbanner-background/border", 58x76, 4px over the edge, painted by the game's
  SetLargeGuildTabardTextures: guild colours and emblem, or the default horned helm; repainted on PLAYER_GUILD_UPDATE;
  the text stops short of it), "66 members, 4 online" under it. The gallery's big view has
  "Use on <page>" so Jake can try pictures in place (saved in `PogRaidDB.art`, local); once he's happy, read his picks
  from his SavedVariables (WTF\Account\*\SavedVariables\PogRaid.lua, `art`) and make them the defaults.

## Tabs
Home, Profiles, LFG, Wishlist, Raid, Crafting, Games, Settings. Raid is a tab group (`Editor:RegisterGroup`): Roster, Attendance, Loot
and Raid Plans sit under a row of sub-tabs; the Raid button opens the last used one (default Attendance). Tabs are
spaced by label width so every gap is equal (`Editor:LayoutTabs`). Games: Wowdle (append-only word lists; list size must not be a multiple of 53; keyboard: letters not tried stand
out, ruled-out ones dark and faint, `Wowdle.KEY_OPEN/KEY_OUT`), Sapper Sweeper (tiles act on the press, LeftButtonDown:
fast clicks drifting onto the next tile were lost), Gem Cutter (real 2048 rules), Ranked Duels (Elo 1200, K 32, both players' reports must agree).
Attendance: weekly (a raid week, Tuesday reset, counts as a player's best night). A night is 100%, or 50% for arriving
more than 15 min after the raid gathered or leaving more than 15 min before it broke up, unless they said so ahead
(`notice` records from "Late / early..." or /pog late, early, ontime: full credit); bench counts as there. Since
0.16.2 "gathered" = when half the night's players had arrived and "broke up" = when half had left (`Att:Times`), so
when the recorder zoned in or stayed behind doesn't matter. Officers share nights (`nights` records, officer-only);
two recordings of one raid show once (time and player overlap). Since 0.16.2 a night is shared as it goes (after each
boss and every 15 min, `Att:Checkpoint`), shows as "live" to other officers, and a recorder who crashed (addon data
is only saved at logout or /reload) carries on with the copy that comes back (`Att:Resumable`). Nights recorded
before 0.13.1 (no first/last times) keep the old share-of-snapshots credit and aren't shared. Loot ignores
"You receive item:" lines (quest rewards, vendor buys).
Crafting: professions + recipe IDs shared per player; recipes read only from your own open profession window.
Poisons and Lockpicking (rogue skills in the skill list) are never read, shared or shown. First Aid, Fishing,
Herbalism, Mining and Skinning are shared but not listed in the directory (`Crafting.HIDDEN`). The results card's art
follows the picked profession (`Crafting.ART`: Alchemy Elemental Shaman, Blacksmithing Arms Warrior, Cooking Resto
Druid, Enchanting Disc Priest, Engineering Arcane Mage, Leatherworking Feral Druid, Tailoring Frost Mage; others the
page's own).
Home: three columns from the top: the guild card and Online now over Activity (Activity lines up with the other
columns' lower cards). Online now's "Show offline" header button (Jake, Nov 2026; `settings.homeOffline`, per
account) lists the rest of the guild under who's online, highest level first, greyed, with the level they were last
seen at (offline rows: profile menu only, no whisper/invite); Message board over Guild chat (Jake, Oct 2026: chat got its own card;
newest line at the bottom like the chat window, `fillRows(..., bottomUp)`; an open post grows the board over the chat,
the art re-cropped); Group finder over Recent loot. The MOTD comes from GUILD_MOTD's text when heard (Home.heardMOTD;
asking right after a change can give the old one), else C_GuildInfo.GetMOTD (also when the event brought a blank: at
login it can). LFG's dungeon ranges: `Dungeons.LEVEL_FIX` overrides the journal (Blackfathom Deeps "22+" -> 22-32, Jake). Recent loot = what we saw plus `drops` records (each player shares only their own blue+ drops, kept 24h). A
guildie's new lfg listing (posted < 2 min ago, once per listing) shows a toast above the chat box (JoinPopup.lua).
Profiles (MySpace style), one per account, named after the account's Main (highest level) or its nickname (the Main's
name always shows beside a nickname); opening any character shows the account page (`viewing` = Main, `profChar` =
the character opened, for the Professions card). Content (status, about, favorites, nick, role, icon file ID, color/song indexes
into lists in Profiles.lua: only ever append) lives in `PogRaidDB.account`; each character publishes it in its own
`profile` record with `ed` (edit time, newest wins) and `chars` (the account's characters; linked when both records
list each other, or one lists the other and the other has no list yet with the same `ed`: a character last shared
before its alt was played). Only accounts confirmed to run Pog Raid (versions heard, or a profile/profs record) are
listed or openable. `kudos` records: one per giver, kind and receiver, `n` counts up once a week (Tuesday reset), a
message is required (latest kept); retired kinds (Funny) stay in the list as `retired`. The card lists the latest
kudos only, never counts for others (Jake: nobody should see how many, or zero, someone has); your own page's Kudos header
shows your total ("12 received", only you see it). Roles: DPS, Tank, Heals; plus an Off spec (profile field `off`,
appended to FIELDS), shown beside the main role in the banner.
Character card (Gear.lua): each character shares a `gear` record (id = author; `items` = item IDs of inventory slots
1-19, 4 base64 chars each, 0 = empty; `race`, `sex`), at login (+20 s, +90 s) and 30 s after its gear stops changing.
The card shows the account's current character (the one we're playing, else the newest gear record): their gear
icons like the character pane (`Profiles.MINI`: left head..wrists incl. shirt and tabard, right hands..trinkets, weapons
along the bottom between them, Inspect above the weapons, using the art's full height; ours read live from what we
wear, refreshed on PLAYER_EQUIPMENT_CHANGED; hover for the item, click for Inspect), and in the middle the live model
(SetUnit, for ourselves, target or group: the only way Forever draws a character; sized to fit between the columns,
down to Inspect), else their class icon (not their profile portrait, Jake: it threw him); their portrait and an
Inspect button at the bottom only if nothing's shared, nothing else; the dressing room art fills the card 8px in on every side,
behind the button too (Jake: no title, no level/race text, the banner says it).
Behind every model (`Dungeons.Backdrop`): the client's "dressingroom-background-<class>" atlas if C_Texture has it
(cropped, at 70%: `Wishlist.BACKDROP_ALPHA`; in Inspect it fills the whole window under the band), else Media/glow.tga in the class colour, plus a shadow at the feet. Profile body: About me 166
(about 4 lines; hover shows a cut-off one), Professions, Most played with on the left; Character 248 and Kudos on the
right. Inspect is a pop-up (PogRaidInspect) with the wishlist's
sheet (`Wishlist.Sheet`, `Wishlist.FillSlot`, `Wishlist.Model`); clicking an item offers "Add to my wishlist".
`/pog probe` says whether the client has DressUpModel and SetCustomRace. Item IDs only (no enchants or suffixes).
Professions card: the 2 main professions from Crafting's shared data, with a recipe book (built on first use). Most
played with: automatic, the 5 accounts with the most time grouped (other accounts' alts summed); on your own page
"See all" lists everyone grouped with for a minute or more, with the time (`Profiles:Together`; times are local only). Portrait picker: our 48, then
the client's macro icons below file ID 140000 (classic art), kept as plain numbers. Songs: PlayMusic/StopMusic.

LFG (Dungeons.lua, `ns.Dungeons`, tab key "lfg"): Jake scrapped the per-dungeon quests/bosses/loot page (keep it out).
Left: "You" (Tank/Heals/DPS toggle buttons, any of them, at least one (`role` = letters "TH"; default the profile's main
role + off spec), with the game's role icons: the large "groupfinder-icon-role-large-*" atlases, else
the classic UI-LFG-ICON-PORTRAITROLES; never GetIconForRole's tiny ones, they blur; a
note, saved on Enter/focus lost; Stop looking) and the dungeons by level (DungeonJournal's list, else `Dungeons.KNOWN`),
each with a tick box: ticked = looking for it; dungeons in your level range (min-2 to max) bright; level ranges in one
right-aligned column, no counts (Jake); Beast Mastery Hunter talent art behind the list (`Dungeons.ART`); clicking a row ticks
it (Jake: no per-dungeon filter, there won't be enough groups for one). No title bar (Jake: no "Groups and looking, 0 groups up"): both columns start at the top; "Post group" sits in the
Groups card's header, as on Home. Right: Groups as tiles (Social's lfg listings: what, leader + need, 5 size pips or 12/20, time left, Join /
Requested / Full, ours: Manage = Home:GroupMenu), then Looking for group (role icon, name, level, dungeons with ours marked, note; ours first,
then those sharing a dungeon with us, online; no time left shown for signups, Jake). `lfd` record: `list` (dungeons,
comma separated), `role` (1-3 of T/H/D), `note` (<= 40), `exp` <= 4 h after `t`; any change renews it; deleted on Stop.
Home's Group finder card opens the LFG tab when clicked outside a listing.
Wishlist (Wishlist.lua; also defines `ns.Journal`): a character sheet (Sixty Upgrades style): `Wishlist.SLOTS` (17 inventory
slots, 9 left, 8 right, no shirt/tabard), one item per slot, a DressUpModel behind the slots spanning between the icons (narrower clips shoulders; SetUnit("player") +
TryOn each item, redressed only when the list changes; drag turns it). Per character in `PogRaidDB.wishlist[GUID]` = { sets = 1-3 x { name, items = {id, link, t, slot,
got} }, cur } (`Wishlist:Data`; an older plain list becomes set 1); lists exist only once made (Jake: don't list ones
that don't exist): the side panel's first row is the current list, and the "Wishlists" button (title row, right)
opens a menu to switch, New (up to 3), Rename, Delete (asks first; never the last one); each its own sheet; `wish` shares what's wanted on any of them (once each, MAX 60); getting an item ticks it
on every list. Slot from C_Item.GetItemInfoInstant's equip loc, else the journal's slot text; non-gear is
refused; rings/trinkets take the free one of the pair, otherwise the slot's item is replaced. Shift-click into the add
box (hooked ChatEdit_InsertLink while it has focus). Drop sources come from DungeonJournal
(`_G.ForeverDungeonJournal_NS.DB[dungeon]`: level string, bosses {name, trash, loot = {{id, name, slot, quality}}}, quests
{name, rewardItems = {{id, name, quality}}}), read fresh each refresh, never indexed. Owned = C_Item.GetItemCount (bank
included) or worn (slots 1-19); checked 1 s after BAG_UPDATE_DELAYED / PLAYER_EQUIPMENT_CHANGED. `wish` records: id =
author, `ids` = still-wanted item IDs packed 4 base64 chars each (Crafting.Pack). Next phases: dungeon board (merging
Jake's PogDungeonFinder: dungeon list, interest signups, quest checklist), pre-BiS tracker, buddy matching from `wish`.
The top-left box is "Search..." (2+ letters: journal gear by name, best item level first; a shift-clicked item link
still goes straight on the wishlist). The side panel lists slots (`Wishlist.LISTS`: rings share one, trinkets too); a slot shows every journal item that
fits, best item level first (C_Item.GetItemInfo; unknown last, loaded on demand, refresh debounced on
ITEM_DATA_LOAD_RESULT). No counts anywhere on the page (Jake: too many numbers that don't matter): not per slot, not
"16 of 17 slots", not "N items". Clicking an empty sheet slot opens its list. The
dressing room art fills the whole wishlist card (`Backdrop(card, model, card)`), hidden while a list shows.

## UI style (UI.lua)
Themes (Jake, Oct 2026; Settings > Theme, `settings.theme`, default `UI.DEFAULT_THEME` = "night", Jake's favourite; an old `classic = false` became "plain"):
`UI.THEMES` = Stone (grey marble, Jake's favourite), Ember (marble over red-brown, one he liked), Sandstone
(UI-Background-Rock, soft warm stone, tint 0.5), Leather (Interface\Collections\CollectionsBackgroundTile, tint 0.55),
Night (UIFrameOribosBackground, smooth mottled blue; the default) and Plain (the original modern look). Each classic theme sets its
`surface` tile and `tint` (strength: brighter tiles turned down), laid additively over the backing, card and band
colours, plus its soft edge and body text; `UI.Surface()` falls back to marble if a tile is missing. Jake liked smooth,
mottled surfaces like marble; he tried the frame tiles with planks (Neutral, Horde), bricks (Alliance) and quilting
(Venthyr) and didn't like them. `UI.SetTheme` at ADDON_LOADED runs `UI.SetClassic` (gold ACCENT 1/0.82/0,
warm borders, gold tab text with white selected, SEL_FILL) and the theme's colours, changing tokens in place before
anything is built; picking a theme saves it and shows "Reload to apply" (UI.ReloadButton) under the Theme button. Body text is `UI.TEXT`, never pure white in the classic themes
(Jake liked the pale yellow of the game's "Apprentice" text: Stone 0.88/0.82/0.64); set text colours from it, not
from white literals. A page's own tabs (Raid's Roster/Attendance/Loot/Raid Plans, Games' Wowdle/Sapper Sweeper/...) are `UI.SubTab` in the
classic themes: the talent window's Primary/Secondary look (Jake), drawn (dark tab, thin muted edge; the open one warm gold
with a gold sheen, bright gold edge, light text), width from the label, side by side from the page margin, 6 apart; the
Plain theme keeps underlined text tabs. No instruction lines under the game boards (Jake: flavor text). The title band (`UI.Band`) is the theme's solid BAND with the marble over it and a top-lit
falloff, so it doesn't read flat next to the cards. All from the client's files (`UI.FILES`):
`UI.Window(f, "dialog"|"tooltip")` puts the dialog/tooltip border just outside a window (nothing inside moves; level
+30) and dimmed stone behind (UI-Background-Rock, else the dark dialog background); `SetPrimary` = the red panel button
(`UI.RedButton`, 3 slices, Up/Down/Disabled); `UI.Check` = the game's check box with its click sounds; `UI.CloseButton` = the game's red X: the square
"RedButton-Exit" atlas Forever's windows use (22px), else the round UI-Panel-MinimizeButton (32px art); `visualW` for
spacing. The main window wears the game's metal frame (`UI.PortraitFrame`: NineSliceUtil "PortraitFrameTemplate", as on
Professions/Spellbook; Jake, Oct 2026): our logo in the corner's round portrait, "Pog Guild Tools" centred in a 21px
strip just above the window (nothing inside moves; it's the drag handle), the X at the strip's right; the band keeps
the tabs, centred in the window with the spacing that fills from the right column to the margin (Jake). Inspect (their name in the strip, their class's round icon in the ring:
`Gear.SetClassPortrait`, UI-Classes-Circles + CLASS_ICON_TCOORDS), the art gallery, the raid plan viewer and the copy
box wear it too (band content starts at `UI.PORTRAIT_CLEAR`, 66, clear of the portrait); small prompts (Compose,
duel/join pop-ups) keep the dialog border. Without the layout it falls back to the dialog border (UI.Window); list rows use
`UI.Hover` (gold glow), `UI.Line` (gold dividers) and `UI.SelBar` (the quest log's highlight bar); `UI.Parchment`
(faint, 20%) on reading cards without picked art (About me, Kudos). Gentle section breaks (Jake's model: his
Dungeon Journal addon, panels on a content panel a shade apart; he called our dark gutters severe, and 30% parchment
and the game's inset bevel "too harsh"): windows sit on a mid grey (UI.BACKING 0.135) with the game's marble
(UI-Background-Marble) laid over it additively; `UI.Card` in the classic look is a shade darker (CARD 0.085) with the
marble over it additively, a soft vertical falloff (6% lighter at the top, 30% darker at the bottom; SetGradient +
CreateColor), all below sublevel 1 where card art draws, and the game's tooltip edge toned down nearly to its colour
(UI.CARD_EDGE, edgeSize 12; set it nil for no edges, the other option Jake saw). A card given its own colour (game
boards) stays flat. The "-c60" atlases on wago.tools
(Forever's Classic-styled UI, e.g. "profession-overview-card-c60") are NOT in Jake's client yet (Oct 2026: they fell
back silently); check a texture exists in his build before designing around it; `UI.Sound` (character window open/close/tab)
only in the classic look. Page art Jake picked stays as it is. No in-world "voice" wording (Jake said no).
Cards are a fill (UI.Card), no outline. Buttons are outlines; fill only when selected or the one primary action.
Section titles in the title colour, size 12 (11 for table columns), never in capitals (Jake: the game's UI never
uses them; `UI.SectionTitle` keeps the text as written), UI.ScrollHint on long lists, UI.ConfirmClick ("Sure?") for destructive actions.
Item hovers use `UI.ItemTip(owner, link)`: the game's "Currently equipped" comparison shows only while Shift is held
(Jake). It hides ShoppingTooltip1/2 as they show for our owners and redraws on MODIFIER_STATE_CHANGED; never write
fields on GameTooltip (taint, secret values).
Window 902x658 with a 36 px title band; pages are 902 x `ns.PAGE_H` (642); the Raid group's pages are 902 x
`ns.RAID_H` (608) under their sub-tab row (`ns.SUB_H` = 34).

## Handover (Nov 14, 2026): where things stand, for whoever picks this up
Jake is switching models, so this is the state of play and what to do next.
- Released: 0.18.0 (kill on sight board, hunters, guildies on the map). Pushed to main but NOT released: 0.18.1 (no
  angle brackets on marks, guild marks, map dots matching OneForAll). In the working tree, NOT committed: 0.19.0
  (Motherlode 2, above). "push" means commit and push to main; a release (pushing the `v<version>` tag) is a
  separate ask, and Jake answers "Release 0.x.y".
- Jake tests by playing and sends screenshots (they land in the game's `Screenshots` folder, newest first; read the
  image, don't ask him to describe it). Expect a round of look-and-feel fixes on Motherlode 2 first: the cart is drawn
  from flat colours and may want real art; the class tiles and the upgrade icons have never been seen.
- Motherlode ideas not built, in the order I'd offer them (ask before building, one at a time):
  1. Feedback on the classes once guildies have played them: each has only two upgrades of its own. More per class
     (a third and fourth), and the missing classes (Priest, Paladin, Warlock, Druid, Shaman) are the obvious growth.
  2. Hiscores per class, or the class shown beside a score (needs a field on the `lode` record: old addons ignore
     unknown fields, but check `Sync:DecodeRecord` before adding one).
  3. Floor variety: a boss floor every fifth (one big multi-hit peg), moving pegs, a different layout per seam.
  4. A daily seed everyone plays (like Wowdle), with its own board.
- Things only the game can prove, still open from 0.18: that PARTY_KILL fires for player kills in the open world (the
  hunters list depends on it), that an enemy's guild name comes through `GetGuildInfo(unit)` (guild marks), and the
  map dots with a second guildie on 0.18+.
- Working habits that kept this codebase healthy (all above in more detail): write edit scripts as files, never as
  shell heredocs with quotes; run `python tests/run_tests.py` after every change; mutation-check new logic on a copy
  of the .lua files; simulate game balance headless before trusting it (every runaway in Motherlode 2 was found that
  way, not by reading the code); guard anything that touches a file added in the same release (`ns.X and ...`),
  because players update and /reload without restarting.
- With Jake: short, plain English, recommendation first, no em dashes, never suggest stopping. He decides scope with
  one-line asks; when a request has a hidden cost (a new shared list, a default-on setting) say so in a sentence and
  go with the sensible default rather than asking.

## How Jake likes to work
- Plain English, short, recommendation first. He isn't a terminal person: give him buttons, double-click files and
  in-game steps, and do the command-line parts yourself.
- Never suggest stopping, pausing or "a good place to wrap up". When something lands, say what's done and move to the
  next step; he decides when to stop.
- He iterates by screenshot and notices small misalignments: measure, don't eyeball.
- Keep it lean: single-agent work unless he asks for more horsepower.
- When he asks, commit and push for him (GitHub Desktop is his tool for Fetch/Pull/Push).

## Jake's decisions
- Don't change the top band without asking (Jake asked for the metal frame and its strip, Oct 2026). No leveling race. Signups/Discord integration parked. No "what's new"
  pop-up (no extra things to click). Officer sync: attendance is shared between officers (Jake, Oct 2026: two raid
  teams); rosters and loot sharing still on hold until a second officer can test. Mid-raid tools (boss-aware plans, soft reserves, pull timers) pinned until they can be tested in
  a raid. Remaining idea list (main/alt linking is done: account profiles): next-raid countdown, weekly recap, Wowdle stats chart, duel seasons,
  Murloc Memory / Connect Four.
