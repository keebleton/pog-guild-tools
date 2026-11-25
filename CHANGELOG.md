# Pog Guild Tools 0.20.10

- **Profiles:** scrolling the list of members no longer stutters. It was redoing a slow lookup for every member on every notch of the wheel.
- **Kill on sight:** players on your own side are no longer called out, even if their name is on the list. You can't attack them anyway.
- **Officers:** a guild rank with "officer" in its name now counts as an officer rank, wherever it sits in the guild's rank list. Before, only the guild master and the rank right under them counted, so officers in a guild with its ranks in another order couldn't do officer things. Ranks picked in Settings still win.

New in 0.20.9:

- **Pop-ups: up to three at once.** Level-ups, new groups, chat lines and kudos now stack one above the other instead of queueing up one at a time. When one goes, the rest drop down.

New in 0.20.8:

- **Congrats:** clicking a level-up pop-up now says your congrats in guild chat. It used to whisper them. Clicking a level-up in Activity is still a whisper, since that line can be hours old.

New in 0.20.7:

- **Pop-ups now show in combat.** New groups, chat lines, kudos and the level 60 banner used to wait until the fight was over, which in a battleground meant almost never. A new group that turned up mid-fight was never shown at all.

New in 0.20.6:

- **Whisper:** picking Whisper on someone (Online now, profiles, group finder, crafters) now opens a whisper to them. It could open whatever chat you last used instead.

New in 0.20.5:

- **Siege:** in a run picked up after logging back in, bricks stayed on screen after the ball broke them. Fixed.

New in 0.20.4:

- **Poggle and Siege: your run is saved.** Log out, `/reload` or get disconnected, and the run is waiting where you left it when you open the game again.
  - In Siege the ball goes back on the paddle, so you never come back to a ball already falling.
  - A run is dropped if the addon updates in between, because the rules may have changed.
  - If the game itself crashes, the run can still be lost. WoW only saves addon data on the way out.

New in 0.20.3:

- **Poggle: every class has its own hiscores.** The board has a tab for Warrior, Mage, Rogue and Hunter, and it opens on the class you're playing. Your best is kept per class too.
- **Poggle: the hiscores have been reset.** Everyone's best run is cleared and the boards start empty, so we all start level with the new classes.
- **Profiles:** gear icons now get their rarity colour even for items your game hasn't seen before. They could stay white (a purple weapon with a white outline).

New in 0.20.2:

- **Angler: pearls were far too strong, so they've been reworked.** It was possible to snowball to the end in a few hours.
  - Pearls now come from the fish you've caught in all, not from each voyage on its own, so selling again only pays for new ground.
  - They're much harder to earn: 1 at a million fish, 2 at 32 million, 3 at 243 million, 10 at 100 billion.
  - Each pearl is worth 5% more fish (was 10%). Pearl Lustre makes that 8%.
  - Casting no longer counts your bonuses twice, and Golden Hooks is 3x (was 10x).
  - **Everyone's Angler progress has been reset,** and the guild board with it, so we all start level under the new rules.

New in 0.20.1:

- **Angler:** the pop-out can buy crew ten at a time, or as many as you can afford. Its x1 button, at the end of the tab row, switches between x1, x10 and max.
- **Angler:** the pop-out's fish count now steps once a second, like the page. It was changing too fast to read.

New in 0.20.0:

- **New game: Angler.** An idle fishing game on the Games tab (or /pog angler). Restart the game after updating to see its tab. It's built to last: expect weeks, not an evening.
  - **Crew** catch fish every second, even with the window closed and while you're logged off (at half speed, up to eight hours). Fourteen kinds, from a Fishing Rod to an Abyssal Rift. Owning 10, 25, 50, 100 and every 50th after that of one kind doubles what that kind catches. Buy one, ten or as many as you can afford.
  - **Cast** for a few fish by hand.
  - **Schools of fish** show up every few minutes for a few seconds. Click one for a feeding frenzy, a lucky haul or a casting spree.
  - **Tackle:** 46 one-off upgrades, including a Better and a Master upgrade for every kind of crew.
  - **Trophies:** 34 goals, each worth 1% more fish for good. The last ones take a long time.
  - **Pop-out:** /pog fish (or Pop out on the page) opens a small card you can leave up with the addon shut: cast, catch schools, and buy crew, tackle and perks from a little shop you can fold away. Every cast pops a "+" off the icon.
  - **Guild board:** the Guild tab ranks everyone by the most fish ever caught, with their rank and pearls.
  - **Pearls and perks:** sell the catch to start the voyage over for pearls. Every pearl you've ever earned is 5% more fish for good, and you spend pearls on twelve perks that last through every voyage, from 2 pearls to 1,000. Your rank climbs from Deckhand to Tide King.
- **Poggle, from your feedback:**
  - **The mine cart is now a bucket.** It slides back and forth along the bottom all the time, so you can time your shot. Land a bomb in it and you get the bomb back, every time, with no limit a floor.
  - **Every upgrade is a class spell.** Each class has seven or eight spells and talents of its own, with the spell's icon, and no two classes share one. Warriors get Cleave, Execute, Thunder Clap and Last Stand. Mages get Arcane Explosion, Polymorph and Arcane Missiles. Rogues get Ambush, Vanish and Seal Fate. Hunters get Multi-Shot, Freezing Trap and Call Pet.
  - **Your bomb is your class colour.**
  - Hunters now drop two bombs every shot and get a longer aim line. The Lodestone is gone.
- **Sapper Sweeper:** the three difficulty buttons are now one drop-down, so they no longer sit on top of the game tabs.
- **Poggle:** New run works at one click, even with a bomb in the air.
- **Congrats:** click a level-up in Activity, or on the level pop-up, to whisper that guildie your congrats. The first click asks for your message with "gz" typed in. Change it any time with the Congrats button on Activity.
- **Games:** tidier wording across the games.

New in 0.19.0:

Motherlode is now called **Poggle**, and it got a big update from your feedback:

- **Classes.** Pick Warrior, Mage, Rogue or Hunter when you start a run. Each has a perk for the whole run and two upgrades only it is offered.
- **The mine cart replaces the x1 x2 x5 pockets.** Ore now counts exactly as you mine it, with no luck at the bottom. A cart rides along the bottom instead: land your bomb in it and you get the bomb back, up to three times a floor.
- **No more dead ends.** When the pegs left on the board can't make the quota and half the board is mined, fresh rock caves in. You only lose by running out of bombs.
- **The top corners can be hit.** The mortar now swings almost flat, and no peg sits where a shot can't reach it.
- **Twice the upgrades.** 23 in all, with new ones like Powder Store, Geodes, Hot Streak, Lodestone, Last Gasp and Wide Cart.

Also:

- **Siegebreaker:** the Tar Paddle upgrade is gone.
- **Kill on sight:** a name typed with angle brackets, like <Kraken Skulls>, now shows without them.
- **Guildies on the map:** the dots are now the same size and style as OneForAll's, for those who use both.
- **Kill on sight:** you can mark a whole guild. Type the guild's name, and anyone in that guild is called out when you come across them.
