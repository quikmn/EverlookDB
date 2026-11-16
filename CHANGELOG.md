# EverlookDB Collector

## Unreleased

- `/edb` opens a window: recording or paused (with a Pause button), everything recorded so far, how much is unsaved and when you last saved, a Save now button, where the data file is and where to upload it, what it records, its privacy rules and options. Also under Settings > AddOns. The old chat summary is `/edb status`. New options: the save button after a loading screen on or off and after how many minutes (20, as before), and the "data saved" chat line. Your own settings (pause included) are now kept apart from the recorded data. `/edb feedback` opens in the addon's own small window instead of a game pop-up.
- Quest text that holds your character's name (the game fills it in for some quests) is no longer saved, and neither is a quest's objective paragraph; what older versions saved of it is removed from your data file. The site shows the quest texts from the game data instead. A player's corpse is never taken as the name of an object you loot next.
- `/edb feedback` shows a link for reporting bugs and ideas.

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
