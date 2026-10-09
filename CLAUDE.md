# Pog Guild Tools: notes for Claude

Jake's guild addon **Pog Guild Tools** (shown everywhere in game, docs and on CurseForge; the folder, SavedVariables
`PogRaidDB` and the addon message prefix stay `PogRaid`) for **WoW: Forever** (Blizzard's Classic+ third version; beta since 9/17/2026, launch 11/4/2026).
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
- Keep memory low (Jake checks it): no per-item tables for long lists, don't cache what only a menu needs, and
  measure with a realistic client (collectgarbage("count") in lupa) when adding anything list-shaped.
- Mutation-check new logic: copy `PogRaid/` somewhere, break the logic, run tests with `POGRAID_DIR=<copy>`, and make
  sure a test fails. Copy only the .lua/.toc files, never `Media/`: the project is in OneDrive, and deleting a temp copy
  that included Media once deleted the real `PogRaid/Media` files (restored from git). The stub has hidden real-client behaviour three times (see Gotchas), so make the stub match the game.
- Write multi-line edit scripts to a file with the Write tool; inline bash heredocs with quotes/backslashes break.
- Version lives in `PogRaid/Core.lua` (`ns.VERSION`) and `PogRaid.toc` (`## Version`); bump both. CurseForge reviews
  every upload (moderators work 8 AM to 3 PM CET, overnight in the US), so bundle changes; send test zips directly.
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
- Addons can't call ReloadUI ("Interface action failed because of an AddOn"; Jake hit it, Oct 2026; the stub errors
  too): `UI.ReloadButton` is a SecureActionButtonTemplate running the /reload macro on the player's click.
- Addons cannot set the guild MOTD. Blizzard's guild professions API exists in the client but may not be fed.

## Architecture
- Comm prefix `PogRaid`, messages chunked at 240 bytes (max 64 chunks). Kinds: B raid plan, X close plan, Q/R raid
  check, P self ping, Y guild sync, J/K join request/answer, D duels, V/W version, Z sync ping. Two send lanes: fast
  (plans, whispers, sync asks) and background (sync listings and records) keeping 3 sends in reserve.
- Sync.lua: shared collections per guild in `PogRaidDB.sync[guild]` (posts, comments, lfg, scores, gems, wowdle, duels,
  config, profs, recipes, profile, kudos, nights, notice, drops, wish, gear, lfd). Records have id/rev/by, newest wins, deletes are tombstones. Records hash into 32 buckets;
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
more than 15 min after the start or leaving more than 15 min before the end, unless they said so ahead (`notice`
records from "Late / early..." or /pog late, early, ontime: full credit); bench counts as there. Officers share nights
(`nights` records, officer-only); two recordings of one raid show once (time and player overlap). Nights recorded
before 0.13.1 (no first/last times) keep the old share-of-snapshots credit and aren't shared.
Crafting: professions + recipe IDs shared per player; recipes read only from your own open profession window.
Poisons and Lockpicking (rogue skills in the skill list) are never read, shared or shown. First Aid, Fishing,
Herbalism, Mining and Skinning are shared but not listed in the directory (`Crafting.HIDDEN`). The results card's art
follows the picked profession (`Crafting.ART`: Alchemy Elemental Shaman, Blacksmithing Arms Warrior, Cooking Resto
Druid, Enchanting Disc Priest, Engineering Arcane Mage, Leatherworking Feral Druid, Tailoring Frost Mage; others the
page's own).
Home: three columns from the top: the guild card and Activity over Online now (Online now lines up with the other
columns' lower cards); Message board over Guild chat (Jake, Oct 2026: chat got its own card;
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
