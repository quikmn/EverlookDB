A World of Warcraft: Forever addon that notes what you see while you play, so EverlookDB.com can show where things are and what drops from what. It runs quietly in the background, with nothing to set up. `/edb` opens its window: what's recorded so far, saving and uploading, privacy and a few options.

## Dungeon loot

`/edb loot` shows what drops where in every WoW Forever dungeon and raid. Pick a dungeon, then a boss or its trash mobs, and see each item with its icon, quality, slot, armor type, item level and how often it drops.

- Search all loot at once, for example `/edb loot vancleef`.
- Show only what your class can use, one armor type or one slot.
- A tick marks what you already have.
- Shift-click links an item in chat, Ctrl-click tries it on.
- Item tooltips say which bosses drop the item and how often.

Drop chances come from what players looted in WoW Forever, and every upload fills them in further. A `~` marks an estimate. Data from ForeverDB.net (https://foreverdb.net).

## What it records

- **Loot:** what each mob dropped (and in which dungeon), what skinning and pickpocketing gave, and what came from herbs, ore veins, chests and fishing. Each corpse or node is counted once, which is what gives drop rates.
- **NPCs:** name, level, type and family, whether they are rare or elite, whether they can be skinned, and where they stand.
- **Vendors and trainers:** what they sell or teach, the price, and whether stock is limited.
- **Quests:** who starts and ends each quest and where, the lowest level it was offered at, its objectives, required items and rewards.

## What it never records

Your character, realm or account name, other players, chat, your gear or bags. Your level is used only for the lowest level a quest was offered at and the XP a kill or quest gave.

## Commands

- `/edb`: the window
- `/edb loot`: dungeon loot; `/edb loot <words>` searches it
- `/edb off` / `/edb on`: pause and resume recording
- `/edb save`: write the data file now (reloads the UI)
- `/edb status`: what was recorded lately, place by place
- `/edb help`: every command

## Sharing what you recorded

The free EverlookDB App uploads your file by itself after you play. Or log out (or `/reload`) so the game writes the file, then upload it on EverlookDB.com:

`World of Warcraft\_forever_\WTF\Account\<your account>\SavedVariables\EverlookDB.lua`
