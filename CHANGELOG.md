# EverlookDB Collector

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
