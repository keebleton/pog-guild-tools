# Pog Guild Tools

Raid leader and guild tools for World of Warcraft: Forever (interface 16001). Tabs include **Home** (the dashboard `/pog` opens on), **Raid Plans** (formerly Boards) (draw a boss diagram on the raid's own map art and pop it up on everyone's screen) **Roster** (build raid rosters from the guild) **Attendance** (logs who raided) and **Loot** (who got what). Officer sync is next.

- `PogRaid/` is the addon. It is linked (junction) into `_classic_beta_\Interface\AddOns\PogRaid`, so edits here are live after `/reload`.
- `tests/` runs the real addon files against a stubbed client: `python tests/run_tests.py` (needs `pip install lupa`).
- `tools/make_textures.py` regenerates `Media/disc.tga` and `Media/ring.tga`; `tools/make_logo.py` the gnome logo.
- `Package for CurseForge.bat` builds `dist/PogGuildTools-<version>.zip` (the folder inside stays `PogRaid`).
- `CLAUDE.md` has the project notes Claude reads on any computer.

## Working on another computer

1. Install World of Warcraft (Forever), [Git](https://git-scm.com/download/win), [GitHub Desktop](https://desktop.github.com/), [Python](https://www.python.org/downloads/) (tick "Add python.exe to PATH") and Claude Code.
2. In GitHub Desktop: File > Clone repository > `keebleton/pog-raid`.
3. Double-click `Set up this PC.bat` in the cloned folder. It links the addon into WoW, installs what the tests need and runs them.
4. Don't let the CurseForge app install or update Pog Guild Tools on a computer you develop on: it replaces the link with its own copy.
5. Every session: **Fetch origin** (and Pull) in GitHub Desktop before you start, **Commit** and **Push origin** when you're done.

## Commands

- `/pog` opens Home (again closes it); `/pog profile [name]` opens your profile or someone else's; `/pog home`, `/pog boards`, `/pog roster`, `/pog attendance`, `/pog loot`, `/pog games`, `/pog duels`, `/pog plans` and `/pog settings` open a tab; `/pog minimap` shows/hides the minimap button; `/pog late`, `/pog early` and `/pog ontime` tell the raid leaders about tonight
- `/pog probe` reports what this client supports (map art, messaging lockdown, events) and runs a self-whisper round trip
- `/pog test` sends the selected board to yourself, so you can see the viewer solo
- `/pog check` lists who in the group has PogRaid
- `/pog reset` recentres the windows

## Editor

Tools: Move, Marker, Player, Group (Tanks/Healers/Melee/Ranged), Arrow, Line, Pen, Rect, Circle, Text.

For drawing your own rooms: Line draws walls (Shift locks it to 45 degree steps, ends snap to nearby wall ends and rectangle corners), Rect drags corner to corner (Shift for a square), Pen draws freehand and is simplified to at most 60 points so boards stay small. Rect and Circle have three fills: Zone (see-through), Solid (pillars, pits), Outline (walls only). Gray is the wall colour.

Right-click deletes, the mouse wheel zooms, right-drag pans. Map picks your current map, a floor of the same instance, a blank grid, or a map ID. "Zoom to boss" uses the Encounter Journal's boss positions for the map.

"Show to raid" sends the board to the group. Only boards from the leader or assistants are shown. While addon messages are locked (boss fights on the 12.0 API), the board waits and sends when they unlock.

## Home

The dashboard `/pog` opens on. A header with the guild logo on a dark round plate (`Media/logo.tga`, made by `tools_make_logo.py <image>`), guild name, message of the day (hover for it in full plus the guild info; officers who can edit it get an Edit button), a stats line and a level spread chart (12 bars of 5 levels; hover a bar for the count). Below, three columns:

- **Activity / Chat** (toggle in the card header): level-ups, achievements, joins and leaves from guild roster updates and guild achievement messages; or the last 100 guild chat lines you saw. **Online now** underneath (click to whisper or invite).
- **Message board:** officers post (title + message), pin and delete; anyone with Pog Guild Tools comments in the thread and can delete their own comments. Officers are guild ranks at or above rank index 1 by default (`PogRaidDB.guild.officerRank`).
- **Group finder:** anyone posts what they are doing and who they need; one listing each, gone after 45 minutes. Listings show how full the group is (1/5, 3/5, 5/5 full; raids count against 10/20/40) and update as people join. Click a listing to **Request to join** (the poster gets a pop-up with Invite / No thanks, sent addon to addon by whisper) or whisper the poster; click your own listing to answer requests. When a guildie posts a new group, a small pop-up fades in above your chat box ("Flyne is forming a group for Deadmines"); click it to ask to join, right-click to dismiss (Settings: New group pop-ups). **Recent loot** (blue and up) underneath: what you and your group get, plus every guildie's own drops, shared for a day (the game only shows each player their own group's loot).

The board and group finder are shared between everyone in the guild running Pog Guild Tools (Sync.lua): changes go out on the guild addon channel as they happen, and people who log in later catch up by comparing a fingerprint of what each addon holds and trading only the differences. Data is kept per guild. `tests/test_sync.py` runs four clients side by side to test this.

## LFG

Everything about getting a group together. On the left, **You**: your role (Tank, Heals or DPS, with the game's role icons; your profile's main role until you pick) and an optional note, then every dungeon by level, the ones in your level range standing out. Click the dungeons you want (each gets a tick) and you're looking (four hours, or until **Stop looking**; changing anything renews it). **Post a group** sits at the top left.

On the right, **Groups**: the guild's group listings (the same ones as Home's group finder) as tiles, with what it is, who leads it and what they need, how full it is and the time left. **Join** asks to join; your own has **Manage** (answer requests, close it). Below, **Looking for group**: everyone looking, with their role, level, dungeons and note; the ones after the same dungeons as you come first, those dungeons marked. Click someone to whisper or invite them. Who's looking is shared with the guild (collection `lfd`, one record per player).

## Wishlist

A character sheet of the gear you're after, one item per slot (17 slots: no shirt or tabard), with your character in the middle wearing it (drag to turn), on your class's dressing room art. One list per character. The **Search...** box at the top left finds gear by name (best item level first); shift-click an item from bags, chat or a loot window into it to add it straight away: it goes into its slot (a second ring or trinket takes the other slot; otherwise it replaces what's there). Only gear can be added.

The left side lists each kind of slot (rings together, trinkets together). Pick one, or click an empty slot on the sheet, to see every item for it from DungeonJournal, best item level first, with where it drops (boss and dungeon, or the quest); click an item to add it or take it off. Items in your bags or equipped get a green tick (also when you add something you already have). Click an item on the sheet to mark it got or not yet, browse its slot, or remove it; shift-click links it in chat. What you still want is shared with the guild (collection `wish`, one record of item IDs per player) for dungeon buddy matching later.

## Profiles

A page for every guild member running Pog Guild Tools, MySpace style, one per account. The list on the left shows guild accounts confirmed to have Pog Guild Tools (their addon has been heard, or they've shared a profile or professions), one row each, online first, with a search box that finds any of their characters. Click anyone, or pick View profile from a name's menu on Home, Roster or Crafting.

- **One profile per account.** Status, About me, favorites, main role, portrait, color and song are kept for your whole account and every character you play shares them. Opening any of someone's characters shows their account's page, named after their highest level character or the nickname they set (the character's name always shows beside a nickname, so nobody can pass as someone else). The Professions card starts on the character you opened and can switch between their characters. Two characters count as one account only when each lists the other, so nobody can attach themselves to your page; a character joins once it logs in with Pog Guild Tools. You can let a character go from the Characters line.
- **Banner:** portrait, name, level, class, rank, main role (DPS, Tank or Heals), status line, online (or online on another of their characters), and their profile song (Play / Stop).
- **About me**, their characters and two favorites (raid, dungeon).
- **Professions:** their two main professions (no Cooking, First Aid or Fishing) with skill and recipe count. Click one to browse their recipes, with a search box.
- **Character:** their current character (the one they last played with Pog Guild Tools) as a 3D model, on their class's dressing room backdrop (or a glow in their class color). **Inspect** (or click the model) opens their character sheet: what they were most recently wearing, slot by slot, with where each item drops; click an item to add it to your wishlist, shift-click to link it. Everyone's addon shares their own character's gear (collection `gear`: item IDs, race and sex), at login and shortly after their gear changes, since the game only lets you inspect people standing next to you. The model is drawn live for you and anyone you target or group with; for others it's built from their race and gear where the client allows (`/pog probe` says), otherwise their portrait shows.
- **Most played with:** the five guild accounts you group with most (counted every minute across all your characters, guild members only, at least 10 minutes together). Automatic.
- **Kudos:** the latest kudos someone was given, each with its kind, who gave it and their message (hover for the whole message). No counts are shown, so nobody sees how many anyone has; you see your own total on your page. Give kudos on someone's page picks a kind (Clutch heals, Great tank, Big damage, Carried me, Helpful, Generous, Great leader, GGWP) and asks for a few words (required); each kind once a week per person (the week turns over at the Tuesday reset), and one given this week can be taken back from the same menu. Your own characters can't give each other kudos.

On your own page, Edit sets the status, About me, nickname, favorites and main role; Portrait picks from about 4,000 classic-art icons (48 favorites first, then pages of the classic icons the client offers for macros); Color picks the theme color (or your class color); Song picks one of 21 classic music tracks. Someone else's song plays when you open their page (Settings: Play profile songs), stops when you leave, and never plays on your own page by itself. Profiles and kudos are shared through Sync (collections `profile` and `kudos`); Most played with times stay on your computer.

## Roster

The pool on the left is the guild, filtered by the ranks you tick under Ranks (max level only unless you untick it), plus pugs added by name. Click a raider to drop them in the first open slot, or drag them into a group, onto the bench, or back to the pool; dragging between slots swaps. Right-click a raider in the pool to mark them available, tentative or out (from Discord signups) or to mark them Tank or Healer (roles are only what you set, never guessed from class; marked players get a thin blue or green stripe and count in the composition panel); right-click a slot to remove. 10/20/40 sets the raid size (shrinking benches the extra groups). Rosters are saved per raid night under Rosters, where you can duplicate or delete them.

Invite roster invites everyone on the groups who is not in your group and not marked out (4 first when solo, then converts to a raid and invites the rest). Arrange groups moves raid members into their planned groups, one move per roster update. Copy for Discord gives a paste-ready text version.

Every roster and player record carries an id, revision time and author so officer sync can merge them later.

## Attendance

Records itself while you are in a raid group inside a raid instance and you are leader, assistant or a guild officer (Options turns that off; Start raid / End raid work by hand). A snapshot every 5 minutes and after every boss notes who is in the raid and online, and when each player was first and last seen; a night ends 10 minutes after you leave the raid group.

- **A night counts 100%**, or **50%** for arriving more than 15 minutes after it started or leaving more than 15 minutes before it ended. Anyone who said so ahead of time gets full credit: **Late / early...** in the Attendance tab (or `/pog late`, `/pog early`, `/pog ontime`) shares "I'll be late" or "I'll leave early" for tonight, and raid leaders and officers get a chat note. The night shows "late", "left early" or "late (said so)".
- **Bench** players on that night's roster count as there (Options turns this off), and being called in from the bench isn't late. Right-click a player on a night to set present / half / absent, or Add player for a sub the snapshots missed.
- **Weekly:** a raid week (from the Tuesday reset) counts as a player's best night that week, so with two raid teams raiding with either one counts, and never twice. Summary shows each raider's attendance over the last 4 and 8 raid weeks and all weeks (click a column header to sort); hovering a raider in the Roster tab shows it too. Copy as CSV for a spreadsheet, Copy for Discord for a post.
- **Shared between officers:** nights recorded by officers (guild ranks ticked in Settings) reach every other addon, so both teams' nights add up in everyone's weekly numbers. Two officers recording the same raid show as one night. Raiders see the attendance too.

## Loot

Logs loot while an attendance night is recording, from every source the client reports (boss loot event, loot roll history, chat loot messages); the same item for the same player within 2 minutes is one entry. Rare quality and up by default (Options). Loot within 10 minutes of a kill is credited to that boss. Right-click an entry to tag it (Main spec, Off spec, Alt, Disenchanted, Guild bank), give it to someone else after a trade, or delete it. Add loot: shift-click the item into the box, then type who got it. Filter by night, by player (left list) or search. Hovering a raider in the Roster tab shows their attendance, main-spec loot over the last 8 nights and their last item.

## Games: Sapper Sweeper

Minesweeper with Goblin Sapper Charges. Apprentice (9x9, 10 sappers), Journeyman (16x16, 40), Expert (30x16, 99); tiles size themselves to fit the window. Left-click reveals, right-click marks a tile with a skull, clicking a revealed number whose skulls are all placed opens the tiles around it. The first click is always safe. The gnome button starts a new game; best times are kept per difficulty (`PogRaidDB.games`). **Leaderboard** swaps the board for the guild's top 20 per difficulty (tenths of a second, your row highlighted, your rank underneath if you are outside the top 20). New bests are shared through the same sync as the message board, one record per player per difficulty.

## Games: Gem Cutter

2048 with gems (same rules as 2048: checked against a separate reference 2048 over 300 spam games, same average score and tiles). Slide with the arrow keys or WASD while the mouse is over the board (keys are only captured while hovering), drag with the mouse, or use the on-screen arrows. Two of the same gem merge into the next: Rough Stone, Malachite, Tigerseye ... Star Ruby, **Large Opal** (the 2048 tile), Huge Emerald, Azerothian Diamond, Arcane Crystal, Black Diamond (real item icons, border climbs the rarity colours). Best score and biggest gem are shared on a guild leaderboard; a game in progress survives a reload. `/pog gems`.

## Games: Wowdle

A daily WoW word of 5 to 8 letters (singular words and names, no plurals; six tries, green / gold / grey). The page says how long today's word is and the grid resizes to fit. The whole guild gets the same word, which changes at the daily reset. Type straight away or use the on-screen keyboard. Today in the guild lists who solved it and in how many (hover for their colour squares, never the letters); your stats show games played, win %, streak, best streak and guess distribution; Copy result gives Discord squares; Post to guild puts just the score ("Wowdle #12  4/6") in the chat box after /g, ready to send with Enter (addons can't post chat themselves on Forever). Any letters of the right length count as a guess (no dictionary is bundled). `/pog wowdle`.

## Games: Ranked Duels

Chess-style ratings for duels between guildies. Challenge someone from the Ranked Duels page (your target, or anyone online) or from Home's Online now menu; they get a pop-up and must accept before the duel is ranked. The challenger then presses Send duel (a normal WoW duel). Both addons read the game's result ("X has defeated Y in a duel"; fleeing is a loss) and share a report; a match counts only when both reports agree. Every addon replays confirmed matches in order (start 1200, K = 32), so the guild leaderboard (rank, rating, W-L, win %) is the same for everyone. `/pog duels` opens the page.

## Settings, minimap button, versions

**Settings** tab: show/hide the minimap button, pop-up sounds, group join pop-ups, ranked duel challenges (off = declined automatically); **officer ranks** (shared guild-wide through sync, changeable by officers only, guild master always included); and **who has Pog Guild Tools** with versions (old ones flagged). The **minimap button** (gnome) opens Pog Guild Tools on left-click, offers Settings / Hide on right-click, and drags around the ring; `/pog minimap` brings a hidden one back, and Pog Guild Tools is also in Blizzard's AddOns menu. The **version check** is one tiny guild message at login, one whispered reply per addon (at most every 10 minutes per person), and after that the version rides on the sync check-in; a newer version gives one chat note.

## First in-game checks (beta)

1. `/pog probe` in town: map art found, self whisper test replies.
2. `/pog`, draw a few items on each tool, `/pog test`: viewer pops up and matches.
3. Inside a Forever raid: `/pog probe` again (map art for the new raid, bosses on map, messaging restricted during a pull?).
4. With a second player: leader shows a board, the other player sees it; "Close on raid" closes it.
5. Roster tab: guild raiders show up, rank filter works, Invite roster actually sends invites (the call may need a click per invite on this client), Arrange groups moves people.
6. Attendance: lead or assist a raid group inside a raid instance, check the tab shows Recording and a snapshot count; boss kills appear on the night.
7. Loot: with attendance recording, loot a boss; check the Loot tab logs it once, with the boss name.
