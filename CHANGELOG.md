# EverlookDB Collector

## Unreleased
- Settings window: switches, buttons and sliders use a softer shade of the accent colour, an on switch has a dark knob so it stands out, and boxes have cleaner rounded edges.

- NPC spawn spots: a creature you stand next to now counts once per play session, not once every second you stay near it, so the site's spawn maps show where creatures really stand instead of where you waited longest. Spots counted the old way in your data file are set to "seen here" once, the next time you log in.
- Lighter while you play: your position is read once a second for all nameplates together, not once per nameplate.
- Vendors: a vendor's list is read once when you open it, and a second time only when some items were still loading.
- Quests: handing in a quest no longer runs into an error when the game hides the quest's XP or money from addons; the hand-in is still counted.
- Long play sessions: the list of corpses and nodes already looted no longer grows all session; it keeps the latest few thousand.
- In the AddOns list it is now "EverlookDB Collector: loot, NPCs, quests", so it isn't mixed up with the EverlookDB Tooltip Collector.

## v0.4.1 (2026-11-18)

- Settings: an AI help button copies a description of every setting for an AI assistant, and `/edb apply` runs the commands it gives back.

## v0.4.0 (2026-11-18)

- Hunters: records what a freshly tamed pet knows and what Beast Lore shows, so EverlookDB can tell every hunter which beast teaches which rank.

## v0.3.0 (2026-11-18)

- Chat commands now follow one pattern across all EverlookDB addons: `/edb help` (or `?`) lists them; `/edb on`, `off` and `toggle` resume and pause recording; `/edb get` and `/edb set <setting> <value>`; `/edb search <words>`; `/edb status` and `/edb version`; a mistyped command suggests the nearest one. `/edb pause`, `/edb resume` and `/everlookdb` still work.
- The settings window has a search box at the top: type to find any setting.

## v0.2.0 (2026-11-17)

- Privacy: a creature's title line that names its owner ("Bob's Companion") is never saved, and companions and other players' pets are not recorded at all. A quest title holding your character's name is not saved when you hand the quest in either (it already wasn't when you took it).
- Settings left from the removed save pop-up are cleared from your settings.
- World-object names: reading the tooltip no longer trips over values the game hides in combat and instances.
- The "Save EverlookDB data" button no longer pops up in the middle of the screen after a loading screen (it couldn't be dismissed). Save whenever you like with Save now in /edb or `/edb save`; logging out saves too.

- `/edb` opens a window: recording or paused (with a Pause button), everything recorded so far, how much is unsaved and when you last saved, a Save now button, where the data file is and where to upload it, what it records, its privacy rules and options. Also under Settings > AddOns. The old chat summary is `/edb status`. New option: the "data saved" chat line. Your own settings (pause included) are now kept apart from the recorded data. `/edb feedback` opens in the addon's own small window instead of a game pop-up.
- Quest text that holds your character's name (the game fills it in for some quests) is no longer saved, and neither is a quest's objective paragraph; what older versions saved of it is removed from your data file. The site shows the quest texts from the game data instead. A player's corpse is never taken as the name of an object you loot next.
- `/edb feedback` shows a link for reporting bugs and ideas.
- The window counts your totals once instead of once per line, so it opens faster with a big data file.
- The "Save EverlookDB data" button after a loading screen always stays its full 30 seconds.
- Settings window: Escape closes an open dropdown list first, then the window; Escape in a text box puts the old text back; a number typed next to a slider snaps to the slider's steps; a Delete or Reset that asks for a second click no longer forgets it early.

## v0.1.3 (2026-11-14)

- Notes more for EverlookDB.com: the XP from kills (when you play solo) and from quests, which NPCs are flight masters, bankers, auctioneers, stable masters, innkeepers or trainers, which spells each trainer teaches, every zone an NPC is seen in, and NPC health per level.

## v0.1.2 (2026-11-14)

- Its own icon in the addon list: the EverlookDB mark.

## v0.1.1 (2026-11-14)

- Now shown as EverlookDB Collector. The folder and your saved data are unchanged.
- Licensed GPL-3.0-or-later.

## v0.1.0 (2026-11-13)

- First release. Notes loot, vendors, quests and where NPCs and nodes are while you play, for EverlookDB.com. It saves nothing about you or your character.
- `/edb save` saves what's been noted so far. After a loading screen, if more than 20 minutes are unsaved, a button offers to save in one click.
