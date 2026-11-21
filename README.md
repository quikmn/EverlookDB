# EverlookDB

A World of Warcraft: Forever addon that notes what you see while you play, so EverlookDB.com can show where things are and what drops from what. It runs quietly in the background; there is nothing to set up. `/edb` opens its window: what's recorded so far, saving and uploading, privacy and a few options.

## What it records

- **Loot:** what each mob dropped, what skinning and pickpocketing gave, and what came from herbs, ore veins, chests and fishing. Each corpse or node is counted once, which is what gives drop rates. Money from a corpse when only one was looted.
- **NPCs:** name, title, level, type and family, whether they are rare or elite, whether they can be skinned, maximum health per level, how they react to your faction, every zone they are seen in, and where they stand. Positions are only taken when you are within about 10 yards of the NPC, so they are accurate. For beasts, how many spawns were seen at each level.
- **XP:** the XP a kill gave when you play solo (your level and the mob's level), and the XP a quest gave at your level.
- **Services and trainers:** flight masters, bankers, auctioneers, stable masters, innkeepers and trainers, and what each trainer teaches, for how much and from which level.
- **Vendors:** what they sell, the price, the stack size and whether stock is limited.
- **Quests:** who starts and ends each quest and where, the lowest level it was offered at, its objectives, required items and rewards (items, choices and currencies such as Merchant's Favor). For a few seconds after you hand a quest in, what you actually received: the currency amounts (so a bonus shows how often it comes) and the items the game's "You receive item" line names.
- **Hunters, when you tame a beast:** which beast it was (its NPC id) and its level, and what the new pet shows in its first 30 seconds: the spell ids in its spellbook and which are passive, its permanent auras (Faster or Slower Attack), its attack speed, level, family, training points, and the game's words for what it eats.
- **Hunters, when you cast Beast Lore:** the lines Beast Lore adds to the beast's tooltip, exactly as the game shows them (abilities, diet, tameable and the like), the ability lines turned into spell ids, the beast (its NPC id) and its level, and how many times you read it.
- With every file: the game's language, the game versions you played on, when the addon started recording, and when you last opened each vendor and trainer. Tames and Beast Lore reads are counted per game version and calendar week (for example `2026-W47`), never by day or time of day.

## Quest item sparkles
 Forever's graphics presets turn off the glitter on quest objects you can loot. The Collector keeps it on: at login and after any graphics change it sets `outlineModeShowLootEffectWhenDisabled` to 1 and the outline mode (`graphicsOutlineMode`, and the raid one) to off, since the game only shows the glitter without unit outlines. It's on by default. Untick **Show quest item sparkles** under Options, or `/edb sparkles off`, and it gives your outline mode back (High if it never saw another one); restart the game if the glitter stays. Written from the game's own settings, inspired by Forever Loot Sparkles.

## What it never records

Your character, realm or account name, other players, chat, your gear or bags, and your pets' names. Your level is used only for the lowest level a quest was offered at and the XP a kill or quest gave. Nothing leaves your computer until you upload the file yourself (on the site or with the EverlookDB App).

## Commands

`/edb` (also `/everlookdb`) follows the same pattern as every EverlookDB addon:

- `/edb`: the window (also under Settings > AddOns)
- `/edb off` / `/edb on` (or `toggle`): pause and resume recording (`/edb pause` and `/edb resume` still work)
- `/edb save`: write the data file now (reloads the UI)
- `/edb status`: version, recording or paused, and what has been recorded so far
- `/edb sparkles off` / `on`: quest item sparkles
- `/edb savedmessage off`, or `/edb set savedmessage off`: change a setting; `/edb get` lists them
- `/edb search <words>`: open the window with its search box filled
- `/edb feedback`: a link for reporting bugs and ideas
- `/edb help` (or `/edb ?`): every command; `/edb version`

A mistyped command suggests the nearest one.

The game only writes addon data when you log out or reload. To write it now, use Save now in `/edb` or `/edb save` (it reloads the UI).

## Sharing what you recorded

Log out (or `/reload`) so the game writes the file, then upload this file on EverlookDB.com:

`World of Warcraft\_forever_\WTF\Account\<your account>\SavedVariables\EverlookDB.lua`

## Install

With WowUp: *Get Addons* > *Install from URL* > paste this repository's GitHub URL. WowUp keeps it updated.

By hand: download the latest `EverlookDB-*.zip` from Releases and unzip it into `World of Warcraft\_forever_\Interface\AddOns\`.

## License

GPL-3.0-or-later (see LICENSE). Not affiliated with Blizzard Entertainment.
