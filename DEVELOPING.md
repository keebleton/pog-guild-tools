# Developing Pog Guild Tools

Notes for working on the addon. The player-facing description is [README.md](README.md); the detailed project notes
(architecture, Forever client gotchas, every tab's behaviour and Jake's decisions) are in [CLAUDE.md](CLAUDE.md).

## What's where

- `PogRaid/` is the addon. The folder name must stay `PogRaid`: the saved data (`PogRaidDB`) and the code depend on it,
  whatever the zip is called.
- `tests/` runs the real addon files against a stand-in game client, headless (Lua 5.1 through `lupa`):
  - `python tests/run_tests.py` runs everything: the main suite (`test_pograid.lua`), the multi-player sync suite
    (`test_sync.py`) and a quick launch-night stress test (`stress_sync.py --quick`, plain and with 10% of messages lost).
  - After sync changes, also run `test_sync.py` with `SYNC_SEED=1` to `10`, and the full `stress_sync.py` (60 clients).
  - `POGRAID_DIR=<folder>` points the tests at a copy of the addon (to check a test fails when the code is broken).
- `tools/`: `package.py` (the CurseForge zip), `setup_pc.py` (new computer setup), `make_logo.py`, `make_textures.py`.
- `Set up this PC.bat`: links the addon into WoW, installs what the tests need and runs them.
- `Package for CurseForge.bat`: builds `dist/PogGuildTools-<version>.zip`. Zips in `dist/` aren't committed.
- `dist/curseforge-description.md`: the CurseForge page text.

## Working on another computer

1. Install World of Warcraft (Forever), [Git](https://git-scm.com/download/win),
   [GitHub Desktop](https://desktop.github.com/), [Python](https://www.python.org/downloads/) (tick
   "Add python.exe to PATH") and Claude Code.
2. In GitHub Desktop: File > Clone repository > `keebleton/pog-guild-tools`.
3. Double-click `Set up this PC.bat` in the cloned folder. Point it at the `_forever_` client folder when it asks. It
   links the addon into `_forever_\Interface\AddOns\PogRaid` (so edits show after `/reload`), moves any copy that was
   there into `Interface\PogRaid-backups`, installs what the tests need and runs them.
4. Don't let the CurseForge app (or WowUp) install or update Pog Guild Tools on a computer you develop on: it replaces
   the link with its own copy.
5. Every session: **Fetch origin** (and Pull) in GitHub Desktop before you start, **Commit** and **Push origin** when
   you're done. Push the whole repo, not just the addon folder, so the tests and notes stay in step.

## Releasing

1. Bump the version in both `PogRaid/Core.lua` (`ns.VERSION`) and `PogRaid/PogRaid.toc` (`## Version`).
2. Run the tests.
3. Double-click `Package for CurseForge.bat`, then upload the zip to CurseForge (project 1712125) for the Forever game
   version. CurseForge reviews every upload, and its moderators work 8 AM to 3 PM CET (overnight in the US), so bundle
   changes and allow a day.
4. WowUp lists the addon from this GitHub repo.

## Commands for testing

- `/pog probe` reports what this client supports (map art, the messaging lockdown, professions, CPU and memory) and runs
  a self-whisper round trip.
- `/pog sync ping` asks every Pog Guild Tools in the guild to answer; `/pog sync` opens a copy box with what was sent and
  received, who was heard and whether your shared data matches theirs.
- `/pog bug` opens the last 25 Pog Guild Tools errors in a copy box (`/pog bug clear` empties it).
- `/pog test` sends the selected raid plan to yourself, so the viewer can be seen solo.
- `/pog check` lists who in your group has Pog Guild Tools.
- `/pog demo` fills Attendance and the loot log with made-up nights (`/pog demo clear` removes them). Never shared.

## First checks in a new client

1. `/pog probe` in town: map art found, the self whisper test replies.
2. `/pog`, draw a few things on a raid plan, `/pog test`: the viewer pops up and matches.
3. Inside a raid: `/pog probe` again (map art for the raid, bosses on the map, messaging locked during a pull?).
4. With a second player: the leader shows a plan, the other player sees it.
5. Roster tab: guild raiders show up, the rank filter works, Invite roster sends invites, Arrange groups moves people.
6. Attendance: lead or assist a raid group inside a raid instance; the night shows as "live" and boss kills appear.
7. Loot: with attendance recording, loot a boss; the Loot tab logs it once, with the boss name.
