# EverlookDB

A World of Warcraft: Forever addon that notes what you see while you play, so EverlookDB.com can show where things are and what drops from what. It runs quietly in the background. There are no windows and nothing to set up.

## What it records

- **Loot:** what each mob dropped, what skinning and pickpocketing gave, and what came from herbs, ore veins, chests and fishing. Each corpse or node is counted once, which is what gives drop rates.
- **NPCs:** name, level, type and family, whether they are rare or elite, whether they can be skinned, and where they stand. Positions are only taken when you are within about 10 yards of the NPC, so they are accurate.
- **Vendors:** what they sell, the price, the stack size and whether stock is limited.
- **Quests:** who starts and ends each quest and where, the lowest level it was offered at, its objectives, required items and rewards.

## What it never records

Your character, realm or account name, other players, chat, your gear or bags. Your level is used only to note the lowest level a quest was offered at.

## Commands

- `/edb`: what has been recorded so far
- `/edb save`: write the data file now (reloads the UI)
- `/edb pause` / `/edb resume`: stop and restart recording

The game only writes addon data when you log out or reload. After a loading screen, if 20 minutes or more are unsaved, a small "Save EverlookDB data" button shows for 30 seconds.

## Sharing what you recorded

Log out (or `/reload`) so the game writes the file, then upload this file on EverlookDB.com:

`World of Warcraft\_forever_\WTF\Account\<your account>\SavedVariables\EverlookDB.lua`

## Install

With WowUp: *Get Addons* > *Install from URL* > paste this repository's GitHub URL. WowUp keeps it updated.

By hand: download the latest `EverlookDB-*.zip` from Releases and unzip it into `World of Warcraft\_forever_\Interface\AddOns\`.
