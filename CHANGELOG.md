# EverlookDB Collector

## v0.8.0 (2026-11-24)

- `/edb status` now shows what was recorded lately in each zone or dungeon (NPCs, loot, quests, vendors), where your NPCs are known to be, and any problems in plain words. Check it right after a dungeon run. The window shows the same.
- Nothing is lost when the game is slow or hides something: a loot window with an item still loading is read again a moment later, vendor and trainer lists keep what was already known, and quest objectives that had not loaded are filled in from your quest log.
- One thing going wrong no longer stops the rest. The addon counts what went wrong and by which part (`/edb errors`), and says so once in chat.
- Creatures you fought but never stood next to get a rough spot on the map.
- Kill XP is noted even when the game hides the creature's level during the fight.
- A damaged data file is mended when you log in instead of breaking the addon.
- If you change the game's language, names are recorded again in the new language and your counts stay.
- Restart the game after this update (it adds files). Until you do, it keeps recording as before.

## v0.7.0 (2026-11-24)

- Dungeons: creatures and their loot now note which dungeon they are in, so EverlookDB.com can show them on the dungeon's page. When you loot a corpse, its level and whether it is elite or a boss are noted too.
- No more hidden errors inside dungeons from nameplates the game keeps private.
- Creatures you pass within about 28 yards get a rough spot on the map when no exact one is known yet.
- "Level ??" is no longer taken for a creature's title.

## v0.6.2 (2026-11-22)

- Quest item sparkles: the glitter on quest objects you can loot stays on, even after a graphics preset turns it off. On by default; untick it under Options or type /edb sparkles off.

## v0.6.1 (2026-11-21)

- Safer counting after the latest WoW Forever update: a creature, corpse or node is never counted twice.
- A small health check at login notes whether the game's info works, as yes/no answers only. It never saves a name or realm.

## v0.6.0 (2026-11-21)

- Quests: currency rewards such as Merchant's Favor are noted, and bonus rewards show how often each amount comes.
- Loot: fixes for skinning and pickpocketing counts, and chests or nodes no longer take the wrong name.
- Vendors: prices in currencies such as Merchant's Favor now show on the site.
- Quests: hand-ins note the quest's name, and a merchant purchase right after a hand-in is no longer counted as a reward.
- Privacy: NPC titles that name an owner, saved by versions before 0.2.0, are removed from your data file.

## v0.5.0 (2026-11-20)

- Spawn maps on the site are more accurate: standing next to a creature counts once, not every second.
- Lighter while you play, and vendor lists are read only once.
- Quest hand-ins no longer cause an error when the game hides their XP or money.
- Softer colours and cleaner edges in the settings window.
- Now listed as "EverlookDB Collector: loot, NPCs, quests" in the AddOns list.

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
