-- EverlookDB: notes what you see while you play, for EverlookDB.com.
--   loot     what each mob, skinned mob, pickpocketed mob, herb, ore vein, chest and fishing spot gave
--   npcs     name, level, type, rare/elite, skinnable, max health, the zones they are in, where they stand (only
--            when you are next to them; within about 28 yards as approximate spots), the dungeon they are in, the XP a
--            solo kill gave, and services (flight master, banker, trainer, ...)
--   inst     each dungeon or raid entered: its name, kind and difficulties (EverlookDB.com's dungeon pages use its map ID)
--   trainers what each trainer teaches, for how much, from which level
--   vendors  what each vendor sells, for how much, and whether stock is limited
--   quests   who starts and ends each quest, where, the lowest level it was offered at, objectives, rewards
--            (items, choices, currencies), XP, and what turning it in actually gave (currencies, items)
--   beasts   (hunters, Beasts.lua) what a freshly tamed pet knows and what Beast Lore shows, by the beast's npc id
-- Nothing about you is saved: no character, realm or player names, no chat, no other players.
-- Everything goes into SavedVariables (EverlookDB.lua); upload that file on EverlookDB.com.
-- /edb opens the window (what's recorded, saving, privacy, options); /edb help lists the commands.
-- The player's own settings live in EverlookDBSettings, never in EverlookDBData (the site reads only that).

local ADDON, ns = ...
local VERSION = 1
local G, Care = ns.Guard, ns.Care  -- Guard.lua (errors, tally), Care.lua (repair, migrations, gaps, size)
if not G or not Care then
  -- The game only loads files it saw when it started. After an update that added Guard.lua, Care.lua and
  -- Report.lua, a /reload runs this file without them: recording goes on as before with these stand-ins, and
  -- /edb status says to restart the game.
  ns.NeedsRestart = true
  G = G or {
    note = function() end, sample = function() end, count = function() end, bind = function() end,
    run = function(_, f, ...) return pcall(f, ...) end,
    wrap = function(_, f) return function(...) pcall(f, ...) end end,
    session = { errors = 0, kinds = {} },
  }
  Care = Care or {
    Repair = function(d)
      for _, name in ipairs({ "npc", "loot", "obj", "vendor", "quest", "trainer", "beast" }) do
        if type(d[name]) ~= "table" then d[name] = {} end
      end
      return 0
    end,
    Migrate = function() return 0 end,
    LocaleChanged = function() return false end,
    Gaps = function() return {} end,
    Size = function() return 0 end,
    Compact = function() return 0, 0 end,
  }
  ns.Guard, ns.Care = G, Care
  local restart = "The addon was updated while the game was running. Restart the game to finish the update; it keeps recording meanwhile."
  ns.ReportLines = function() return { restart } end
  ns.Problems = function() return { restart } end
  ns.RecentLines = function() return {} end
  ns.CoverageLine = function() return nil end
  ns.ErrorLines = function() return { restart } end
end
ns.Tally = ns.Tally or function() end
ns.PlaceChanged = ns.PlaceChanged or function() end
local function tally(what, n, npc) ns.Tally(what, n, npc) end
-- These three shape the data every player uploads, so they are not options.
local SPAWN_GRID = 5        -- positions are kept on a 0.5% grid of the zone map
local SPAWNS_PER_MAP = 150  -- most grid cells kept per NPC or node per map
local NEAR = 3              -- CheckInteractDistance index: about 10 yards
local CLOSE = 4             -- CheckInteractDistance index: about 28 yards (approximate spots, rec.pa)

local db
local settings              -- EverlookDBSettings
local paused = false
local changes = 0               -- records touched since the last save (login or reload)

ns.SETTINGS_DEFAULTS = {
  version = 1,
  paused = false,
  savedMessage = true,      -- "data saved" in chat after a save
  problemMessage = true,    -- one chat line a session when something went wrong while recording
  questSparkles = true,     -- keep the glitter on lootable quest objects (Sparkles.lua)
}

-- Settings from the saved table, missing ones from the defaults; moves `paused` out of the data file.
function ns.InitSettings(data)
  local s = type(EverlookDBSettings) == "table" and EverlookDBSettings or {}
  EverlookDBSettings = s
  for k, v in pairs(ns.SETTINGS_DEFAULTS) do
    if s[k] == nil then s[k] = v end
  end
  -- options that no longer exist (the save pop-up after loading screens)
  s.saveReminder, s.reminderMinutes = nil, nil
  if data and data.paused ~= nil then
    if data.paused then s.paused = true end
    data.paused = nil
  end
  return s
end

-- Forever hides some values from addons ("secret values"). Treat any of them as unknown.
local isSecret = issecretvalue or function() return false end
local function ok(v)
  if v == nil or isSecret(v) then return nil end
  return v
end
-- a plain number, or nil (hidden values and anything else are unknown)
local function num(v)
  v = ok(v)
  return type(v) == "number" and v or nil
end
local function pack(...) return { n = select("#", ...), ... } end  -- WoW runs Lua 5.1: no table.pack

-- The API a function is, by name, for the self-test's error counts: only these words are ever saved.
local API_NAMES = {
  "CheckInteractDistance", "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "GetInstanceInfo",
  "C_TooltipInfo.GetUnit", "C_TooltipInfo.GetTrainerService", "GetLootSourceInfo", "IsFishingLoot",
  "UnitExists", "UnitGUID", "UnitName", "UnitLevel", "UnitIsDead", "UnitClassification",
  "C_CurrencyInfo.GetCurrencyListSize", "C_CurrencyInfo.GetCurrencyListInfo", "C_CurrencyInfo.GetCurrencyListLink",
  "GetQuestItemInfo", "GetQuestItemLink", "GetNumRewardCurrencies", "C_QuestOffer.GetQuestRewardCurrencyInfo",
  "GetQuestCurrencyID", "GetQuestCurrencyInfo", "GetNumQuestRewards", "GetNumQuestChoices", "GetRewardMoney",
  "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives", "GetNumQuestItems",
  "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceLevelReq",
  "C_Spell.GetSpellName", "GetSpellInfo", "GetBuildInfo", "GetRealmName", "C_Item.GetItemInfo", "GetItemInfo",
  "C_SpellBook.HasPetSpells", "C_PetInfo.GetPetTrainingPoints", "C_PetInfo.GetPetFoodTypes", "UnitAttackSpeed",
  "UnitCreatureFamily", "GameTooltip.GetOwner", "GameTooltip.GetUnit", "GameTooltip.GetItem",
}
local function apiName(f)
  for _, path in ipairs(API_NAMES) do
    local t = _G
    for part in path:gmatch("[^.]+") do t = type(t) == "table" and t[part] or nil end
    if t == f then return path end
  end
  return "other"
end
local MAX_ERROR_NAMES = 40
local function safe(f, ...)
  local r = pack(pcall(f, ...))
  if not r[1] then
    local h = ns.health  -- the self-test counts calls that threw (Health.lua), and which API threw
    if h then
      h.errors = math.min((h.errors or 0) + 1, 1000000)
      h.errs = type(h.errs) == "table" and h.errs or {}
      local name, n = apiName(f), 0
      if not h.errs[name] then for _ in pairs(h.errs) do n = n + 1 end end
      if h.errs[name] or n < MAX_ERROR_NAMES then h.errs[name] = math.min((h.errs[name] or 0) + 1, 1000000) end
    end
    G.sample(apiName(f), r[2])  -- what it said, kept as a short sample (Guard.lua)
    return nil
  end
  for i = 2, r.n do r[i] = ok(r[i]) end
  return unpack(r, 2, r.n)
end

-- Quest text the game shows can carry your character's name (it fills in $N), so text that holds it is
-- never saved, and the objective paragraph isn't saved at all (the site has the quest texts already).
local myName  -- read at login, in memory only: the check still works when the name is hidden later
local function noName(text)
  local me = ok(UnitName("player")) or myName
  if me then myName = me end
  if text and me and me ~= "" and text:find(me, 1, true) then return nil end
  return text
end

-- "Creature-0-server-instance-zone-NPCID-spawn": the type and the NPC id, nothing else. Any other shape (a game
-- update that changes GUIDs) gives nil, so a wrong id is never saved; the self-test counts it (Health.lua).
local GUID_FIELDS = 7
local function guidTypeID(guid)
  guid = ok(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  id = tonumber(id)
  if not id or id <= 0 or select(2, guid:gsub("-", "")) ~= GUID_FIELDS - 1 then return nil end
  return kind, id
end

-- -> "u", NPCID for creatures and vehicles, "o", id for game objects
local function parseGUID(guid)
  local kind, id = guidTypeID(guid)
  if kind == "Creature" or kind == "Vehicle" then return "u", id end
  if kind == "GameObject" then return "o", id end
  return nil
end

ns.ok, ns.safe, ns.parseGUID, ns.GuidTypeID = ok, safe, parseGUID, guidTypeID

local function itemID(link)
  link = ok(link)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

-- the player's zone map and position on it, as 0..1000 integers (nil inside most instances)
local function where()
  local map = safe(C_Map.GetBestMapForUnit, "player")
  if not map then return nil end
  local pos = safe(C_Map.GetPlayerMapPosition, map, "player")
  if pos then
    local x, y = safe(pos.GetXY, pos)
    if x and y and (x > 0 or y > 0) then
      return map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
    end
  end
  return map
end

-- Inside a dungeon or raid: its map ID (the one EverlookDB.com files dungeon pages under) and difficulty. The first
-- time a session, the instance's name and kind are noted in db.inst, so the site can tell which place it is.
local instNoted = {}
local function instanceMap()
  local name, itype, difficulty, _, _, _, _, mapID = safe(GetInstanceInfo)
  mapID = num(mapID)
  if not (itype and itype ~= "none" and mapID and mapID > 0) then return nil end
  difficulty = num(difficulty)
  local key = mapID .. ":" .. tostring(difficulty)
  if db and not instNoted[key] then
    instNoted[key] = true
    db.inst = db.inst or {}
    local i = db.inst[mapID] or {}
    db.inst[mapID] = i
    if type(name) == "string" and name ~= "" then i.name = name end
    if type(itype) == "string" then i.type = itype end           -- party, raid, pvp, arena, scenario
    if difficulty then i.d = i.d or {}; i.d[difficulty] = 1 end
  end
  return mapID, difficulty
end

-- seen in that instance: rec.zi = { [instance map ID] = 1 }
local function seenIn(rec, inst)
  if not inst then return end
  rec.zi = rec.zi or {}
  if not rec.zi[inst] then rec.zi[inst] = 1; changes = changes + 1 end
end

-- A unit token we may hand to the game. Inside dungeons, nameplate and world-cursor tokens can be secret values,
-- and the game throws when an addon passes one back to it.
local function usable(unit)
  return type(unit) == "string" and not isSecret(unit)
end

-- A set of keys seen this session that never grows past about 2 * limit: when the newest half fills up, the
-- older half is dropped. A key seen again is kept in the newest half.
local function seenSet(limit)
  local new, old, n = {}, {}, 0
  local set = {}
  function set.has(k) return new[k] or old[k] or false end
  function set.add(k)
    if new[k] then return end
    if n >= limit then old, new, n = new, {}, 0 end
    new[k], n = true, n + 1
  end
  return set
end
ns.SeenSet = seenSet

-- Keys seen within the last `seconds`. sliding: every sighting starts the window again (a creature you stand next
-- to stays one sighting); else the window runs from the first one. Holds about `limit` keys at most.
local function recentSet(limit, seconds, sliding)
  local at, n = {}, 0
  local set = {}
  -- true when k was seen within the window; notes this sighting either way
  function set.seen(k)
    local now = GetTime()
    local t = at[k]
    if t and now - t < seconds then
      if sliding then at[k] = now end
      return true
    end
    if not t then n = n + 1 end
    at[k] = now
    if n > limit then
      n = 0
      for key, v in pairs(at) do
        if now - v >= seconds then at[key] = nil else n = n + 1 end
      end
      if n > limit then at, n = { [k] = now }, 1 end
    end
    return false
  end
  return set
end
ns.RecentSet = recentSet

---------------------------------------------------------------------------------------------------
-- GUID trust. In memory, a unit's full GUID is only an opaque "is this the same spawn?" key. It is never parsed
-- past its type and ID, and never saved. Since build 71037 Blizzard scrambles the server, zone and spawn parts of
-- NPC GUIDs. If the same unit ever gives a different GUID (two reads in a row, or a target or nameplate that hasn't
-- changed), GUIDs can't tell spawns apart. Counting then falls back to NPC id + map cell + a time window, for the
-- rest of the session and for later sessions on this build (the counts live in the saved health). When we can't
-- tell two spawns apart, we count one.

local trust = { stable = true, counts = { checked = 0, badFormat = 0, changed = 0 } }
ns.GuidTrust = trust
local byToken = {}  -- "target" / "nameplateN" -> { guid, id } while that token still points at the same unit

local function countGUID(field)
  local c = trust.counts
  if (c[field] or 0) < 1000000 then c[field] = (c[field] or 0) + 1 end
end

-- Use these saved counts (the health of this build and addon version); GUIDs found unstable before stay distrusted.
function ns.TrustCounts(counts)
  trust.counts = counts
  if (counts.changed or 0) > 0 then trust.stable = false end
end

local function guidChanged()
  countGUID("changed")
  trust.stable = false
end

-- A creature's GUID, read once more straight away and, for a tracked token, compared with its last read
local function watchGUID(unit, guid, id)
  countGUID("checked")
  local again = ok(UnitGUID(unit))
  if type(again) == "string" and again ~= guid then return guidChanged() end
  if unit == "target" or unit:find("^nameplate") then
    local last = byToken[unit]
    if last and last.id == id and last.guid ~= guid then guidChanged() end
    byToken[unit] = { guid = guid, id = id }
  end
end
ns.ForgetToken = function(unit) if unit then byToken[unit] = nil end end

-- Two GUIDs name the same unit: equal while GUIDs are stable, else the same type and id.
function ns.SameUnit(a, b)
  a, b = ok(a), ok(b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  if trust.stable then return a == b end
  local ka, ia = guidTypeID(a)
  local kb, ib = guidTypeID(b)
  return ka ~= nil and ka == kb and ia == ib
end

-- A map cell of `grid` units (of 0..1000) as text, "?" without a position
local function cell(x, y, grid)
  if not x or not y then return "?" end
  return math.floor(x / grid) .. ":" .. math.floor(y / grid)
end

-- The first sighting of a spawn: by its GUID while GUIDs are stable, else by the fallback key within its window
local function firstSight(byGUID, byFallback, guid, fallback)
  if trust.stable then
    if byGUID.has(guid) then return false end
    byGUID.add(guid)
    return true
  end
  return not byFallback.seen(fallback)
end

-- Spawns whose position was counted this session: each spawn counts once, however long you stand next to it (the
-- nameplate scan sees it every second) and whether you then loot it or not. Without trusted GUIDs: once per NPC and
-- grid cell while it is still seen, until it has been out of sight for 5 minutes.
local spotCounted = seenSet(5000)
local spotRecent = recentSet(5000, 300, true)

-- add a position to rec.p[map] as a grid cell "x:y" -> times seen (each spawn once a session when guid is given)
-- field: "p" (default) or "pa", approximate spots (within about 28 yards), counted apart from the exact ones
local approxCounted = seenSet(5000)
local approxRecent = recentSet(5000, 300, true)
local function addSpot(rec, map, x, y, guid, id, field)
  if not map then return end
  field = field or "p"
  if guid then
    local fallback = (id or 0) .. "@" .. map .. ":" .. cell(x, y, SPAWN_GRID)
    if field == "pa" then
      if not firstSight(approxCounted, approxRecent, guid, fallback) then return end
    elseif not firstSight(spotCounted, spotRecent, guid, fallback) then return end
  end
  rec[field] = rec[field] or {}
  local cells = rec[field][map]
  if not cells then cells = { n = 0 }; rec[field][map] = cells end
  if not x then cells.n = cells.n + 1; changes = changes + 1; return end  -- seen on this map, position unknown (instance)
  local key = math.floor(x / SPAWN_GRID) * SPAWN_GRID .. ":" .. math.floor(y / SPAWN_GRID) * SPAWN_GRID
  if cells[key] then
    cells[key] = cells[key] + 1
    changes = changes + 1
  elseif cells.n < SPAWNS_PER_MAP then
    cells[key] = 1
    cells.n = cells.n + 1
    changes = changes + 1
  end
end

-- rec.p[map] holds at least one position (not just sightings without one)
local function hasCells(p, map)
  local cells = type(p) == "table" and p[map]
  if type(cells) ~= "table" then return false end
  for k in pairs(cells) do if k ~= "n" then return true end end
  return false
end

-- Versions before 0.4.2 added 1 to an NPC's spot every second you stood next to it (one cell reached 408),
-- so those counts are time spent nearby, not spawns. Once per data file each such count becomes 1 ("seen
-- here"), and sightings without a position (instances) at most 1 per map. Loot spots of herbs, veins and
-- chests were always counted once per node and are left alone.
local SPOT_FORMAT = 2
local function normalizeSpots(data)
  if data.spotFormat == SPOT_FORMAT then return 0 end
  local fixed = 0
  for _, rec in pairs(data.npc or {}) do
    if type(rec) == "table" and type(rec.p) == "table" then
      for _, cells in pairs(rec.p) do
        if type(cells) == "table" then
          local positions = 0
          for k, v in pairs(cells) do
            if k ~= "n" then
              positions = positions + 1
              if type(v) == "number" and v > 1 then cells[k] = 1; fixed = fixed + 1 end
            end
          end
          local unknown = (tonumber(cells.n) or positions) - positions
          if unknown > 1 then fixed = fixed + 1; unknown = 1 end
          cells.n = positions + math.max(unknown, 0)
        end
      end
    end
  end
  data.spotFormat = SPOT_FORMAT
  return fixed
end
ns.NormalizeSpots = normalizeSpots

---------------------------------------------------------------------------------------------------
-- NPCs

local scanned = {}  -- npc ids whose tooltip was read this session
local levelCounted = seenSet(5000)  -- beast spawns (GUIDs) whose level was counted this session
-- without trusted GUIDs: an NPC id at a level, near the same spot (a 5% cell), until out of sight for 5 minutes
local levelRecent = recentSet(5000, 300, true)
local recent = {}   -- name -> { id, level, at }: NPCs seen lately, to match "X dies, you gain N experience"
local SKINNABLE = {}
for _, g in ipairs({ "UNIT_SKINNABLE_LEATHER", "UNIT_SKINNABLE_HERB", "UNIT_SKINNABLE_ROCK", "UNIT_SKINNABLE_BOLTS" }) do
  if _G[g] then SKINNABLE[_G[g]] = g:sub(16):lower() end  -- leather, herb, rock, bolts
end

local function npcRecord(id)
  local rec = db.npc[id]
  if not rec then rec = {}; db.npc[id] = rec end
  return rec
end
ns.NpcRecord = npcRecord

-- "Bob's Companion", "Bob's Pet", ...: the tooltip line under a unit someone owns names its owner
local OWNER_TITLES = {}
for _, g in ipairs({ "UNITNAME_TITLE_COMPANION", "UNITNAME_TITLE_PET", "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_MINION",
    "UNITNAME_TITLE_CREATION", "UNITNAME_TITLE_CHARM", "UNITNAME_TITLE_SQUIRE" }) do
  local fmt = _G[g]
  if type(fmt) == "string" and fmt:find("%s", 1, true) then
    OWNER_TITLES[#OWNER_TITLES + 1] = "^" .. fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$%%])", "%%%1"):gsub("%%%%s", ".+") .. "$"
  end
end
local function ownerTitle(text)
  for _, p in ipairs(OWNER_TITLES) do if text:find(p) then return true end end
  return false
end
ns.OwnerTitle = ownerTitle

-- "Level ??" (a creature far above you) is the level line, not a title
local LEVEL_WORD = type(LEVEL) == "string" and LEVEL ~= "" and LEVEL or "Level"
local function isLevelLine(text) return text:sub(1, #LEVEL_WORD) == LEVEL_WORD end
ns.IsLevelLine = isLevelLine

-- here: { map, x, y } from where(), when the caller already has it (the nameplate scan reads it once a tick)
-- near: true within about 10 yards (an exact spot), "close" within about 28 (an approximate spot, rec.pa)
local idHidden = false  -- the last unit read had a hidden GUID (dungeons): read it again after combat
local function readUnit(unit, near, here)
  if paused or not usable(unit) then return end
  if not ok(UnitExists(unit)) or ok(UnitIsPlayer(unit)) then return end
  if ok(UnitPlayerControlled(unit)) then return end  -- pets and guardians
  -- companions and other players' pets carry a name and an owner line that a player chose or is
  if UnitIsBattlePetCompanion and ok(UnitIsBattlePetCompanion(unit)) then return end
  if UnitIsOtherPlayersPet and ok(UnitIsOtherPlayersPet(unit)) then return end
  local rawGUID = UnitGUID(unit)
  if isSecret(rawGUID) then idHidden = true; return end  -- which NPC it is stays hidden (dungeons): see readLoot
  local guid = ok(rawGUID)
  local kind, id = parseGUID(guid)
  if kind ~= "u" then
    -- a creature GUID of a shape we don't know: record nothing, but count it for the self-test
    if type(guid) == "string" and (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then countGUID("badFormat") end
    return
  end
  watchGUID(unit, guid, id)
  local rec = npcRecord(id)
  tally(nil, nil, id)
  rec.name = ok(UnitName(unit)) or rec.name
  local lvl = ok(UnitLevel(unit))
  if lvl then
    if lvl < 0 then rec.boss = 1
    else
      rec.lo = math.min(rec.lo or lvl, lvl)
      rec.hi = math.max(rec.hi or lvl, lvl)
    end
  end
  if rec.name then  -- updated in place: the nameplate scan passes here for every plate every second
    local r = recent[rec.name]
    if not r then r = {}; recent[rec.name] = r end
    -- a level the game hides right now (combat) keeps the one seen a moment ago for the same NPC
    if r.id ~= id then r.lvl = nil end
    r.id, r.lvl, r.at = id, lvl or r.lvl, GetTime()
  end
  local hp = ok(UnitHealthMax(unit))  -- hidden in some places; then unknown
  if lvl and lvl > 0 and hp and hp > 0 then
    rec.hp = rec.hp or {}
    rec.hp[lvl] = math.max(rec.hp[lvl] or 0, hp)
  end
  -- every zone it shows up in, even without a position (nameplates reach further than "near")
  here = here or { where() }
  local zone = here[1]
  if zone then
    rec.z = rec.z or {}
    if not rec.z[zone] then rec.z[zone] = 1; changes = changes + 1 end
  end
  local inst = instanceMap()
  seenIn(rec, inst)  -- inside a dungeon: the dungeon (most give no zone map)
  rec.class = ok(UnitClassification(unit)) or rec.class      -- normal, elite, rare, rareelite, worldboss
  rec.type = ok(UnitCreatureType(unit)) or rec.type          -- Beast, Humanoid, ... (client language)
  rec.family = ok(UnitCreatureFamily(unit)) or rec.family    -- Wolf, Spider, ...
  -- beasts: how many spawns were seen at each level (each spawn once a session), so a level spread shows
  if lvl and lvl > 0 and ok(UnitCreatureFamily(unit)) then
    local fallback = id .. ":" .. lvl .. "@" .. tostring(zone) .. ":" .. cell(here[2], here[3], 50)
    if firstSight(levelCounted, levelRecent, guid, fallback) then
      rec.lvl = rec.lvl or {}
      rec.lvl[lvl] = (rec.lvl[lvl] or 0) + 1
      changes = changes + 1
    end
  end
  local faction = ok(UnitFactionGroup("player"))
  local reaction = ok(UnitReaction(unit, "player"))
  if faction and reaction then
    rec.react = rec.react or {}
    rec.react[faction] = reaction  -- 1-3 hostile, 4 neutral, 5+ friendly, for that player faction
  end
  -- the tooltip (title, skinnable): read until the game gave it once; hidden in combat, so up to 5 tries a session
  if scanned[id] ~= true then
    scanned[id] = (scanned[id] or 0) + 1
    if scanned[id] >= 5 then scanned[id] = true end
    local data = safe(C_TooltipInfo.GetUnit, unit)
    if data and data.lines then
      scanned[id] = true
      for i, l in ipairs(data.lines) do
        local text = ok(l.leftText)
        if text then
          if SKINNABLE[text] then rec.skin = SKINNABLE[text] end
          -- line 2 is the title ("<Weapon Merchant>") when it isn't the level line
          if i == 2 and not text:find("%d") and not isLevelLine(text) and text ~= rec.name and not ownerTitle(text) and noName(text) then rec.title = text end
        end
      end
    end
  end
  if near == true and guid then
    local map, x, y = here[1], here[2], here[3]
    if not x then map = inst or map end
    addSpot(rec, map, x, y, guid, id)
  elseif near == "close" and guid and here[2] and not hasCells(rec.p, here[1]) then
    -- no exact spot on this map yet: the player's spot within about 28 yards, kept apart as approximate
    addSpot(rec, here[1], here[2], here[3], guid, id, "pa")
  end
  return rec, id
end

-- Is the unit close enough that the player's position is a good stand-in for its position? true within about
-- 10 yards, "close" within about 28, else false. Never in combat (the game restricts it there).
local function isNear(unit)
  if not usable(unit) or InCombatLockdown() then return false end
  if safe(CheckInteractDistance, unit, NEAR) == true then return true end
  if safe(CheckInteractDistance, unit, CLOSE) == true then return "close" end
  return false
end

local function scanNameplates()
  if paused then return end
  -- the target, once a second: a creature you keep targeted must keep its GUID
  if trust.stable then
    local guid = ok(UnitGUID("target"))
    local kind, id = parseGUID(guid)
    if kind == "u" and not ok(UnitIsPlayer("target")) then watchGUID("target", guid, id) end
  end
  local here  -- the player's position, read once a tick and only when there are plates
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken
    if not isSecret(unit) and unit == nil then unit = plate.UnitFrame and plate.UnitFrame.unit end
    if usable(unit) then  -- dungeon nameplates hand out secret tokens: those are skipped
      here = here or { where() }
      readUnit(unit, isNear(unit), here)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Loot

-- what the player cast just before the loot window opened tells skinning from corpse loot, etc.
local GATHER = {}  -- localized spell name -> loot kind
local GATHER_SPELLS = {
  s = { 8613, 8617, 8618, 10768 },   -- Skinning
  h = { 2366, 2368, 3570, 11993 },   -- Herb Gathering
  m = { 2575, 2576, 3564, 10248 },   -- Mining
  p = { 921 },                       -- Pick Pocket
}
local lastCast, lastCastAt = nil, 0
local lastObjectName, lastObjectAt = nil, 0
local looted = seenSet(2000)  -- "kind..guid" already counted this session (the latest few thousand)
-- without trusted GUIDs: the same kind of loot from the same NPC or object near the same spot (a 2% cell) within
-- 30 seconds is the same corpse or node opened again
local lootedRecent = recentSet(2000, 30, false)
local lootDone, lootSig, lootDoneAt = false, nil, 0
local pendingLoot  -- { read }: a window with something not readable yet; looked at again, counted when it closes
local moneyBefore, moneySources = nil, nil
local LOOT_ITEM = (Enum and Enum.LootSlotType and rawget(Enum.LootSlotType, "Item")) or 1

local function lootKind(sourceKind)
  if safe(IsFishingLoot) then return "f" end
  if lastCast and GetTime() - lastCastAt < 4 then
    local k = GATHER[lastCast]
    if k == "p" or k == "s" then return k end
    if (k == "h" or k == "m") and sourceKind == "o" then return k end
  end
  return sourceKind  -- "u" corpse, "o" other object (chest, crate, ...)
end

local function lootRecord(key)
  local rec = db.loot[key]
  if not rec then rec = { n = 0, i = {} }; db.loot[key] = rec end
  return rec
end

-- Inside dungeons the game hides which NPC a unit is (its GUID and often its name), but the loot window still
-- names the corpse. With one corpse in the window, the dead creature under the cursor (else the target) is that
-- corpse: its level and classification are noted for it. A readable name that differs from the one saved for
-- that NPC means it is another unit, and nothing is taken.
local function corpseUnit(guid)
  for _, u in ipairs({ "mouseover", "target" }) do
    if ok(UnitExists(u)) and ok(UnitIsDead(u)) and not ok(UnitIsPlayer(u)) and not ok(UnitPlayerControlled(u)) then
      local g = UnitGUID(u)
      if isSecret(g) or g == nil then return u, true end
      if ns.SameUnit(g, guid) then return u, false end
    end
  end
end

local function readCorpse(id, guid)
  local u, hidden = corpseUnit(guid)
  if not u then return end
  if not hidden then return readUnit(u, false) end  -- a unit we can tell: read it the usual way
  local rec = npcRecord(id)
  local name = ok(UnitName(u))
  if type(name) ~= "string" or name == "" then name = nil end
  if name and rec.name and rec.name ~= name then return end
  rec.name = rec.name or name
  local lvl = num(UnitLevel(u))
  if lvl then
    if lvl < 0 then rec.boss = 1
    elseif lvl > 0 then
      rec.lo = math.min(rec.lo or lvl, lvl)
      rec.hi = math.max(rec.hi or lvl, lvl)
    end
  end
  rec.class = ok(UnitClassification(u)) or rec.class
  rec.type = ok(UnitCreatureType(u)) or rec.type
  rec.family = ok(UnitCreatureFamily(u)) or rec.family
  changes = changes + 1
end

-- Read the open loot window, counting nothing yet. -> nil when it is empty, else
--   { sources, order, fished, fishing, bad, sig }
-- bad: item slots that can't be counted right now (the item is still loading, or the game hides what it came from).
local function scanLoot()
  local slots = num(safe(GetNumLootItems)) or 0
  if slots == 0 then return nil end
  -- per source: items it gave. A source is its GUID while GUIDs are stable, else its type and id (one corpse whose
  -- GUID reads differently per slot is still one corpse)
  local sources, order = {}, {}
  local fished = {}  -- every slot's items, for fishing (which has no mob or object)
  local fishing = safe(IsFishingLoot) and true or false
  local bad, sig = 0, { slots }
  local function src(guid)
    local sk, id = parseGUID(guid)
    if not sk then return nil end
    local key = trust.stable and guid or (sk .. ":" .. id)
    local s = sources[key]
    if not s then s = { items = {}, guid = guid, sk = sk, id = id }; sources[key] = s; order[#order + 1] = key end
    return s
  end
  for slot = 1, slots do
    local id = itemID(safe(GetLootSlotLink, slot))
    -- coins and currencies have no item link; an item slot without one is an item that hasn't loaded yet
    local isItem = id ~= nil or (GetLootSlotType ~= nil and num(safe(GetLootSlotType, slot)) == LOOT_ITEM)
    local info = pack(safe(GetLootSourceInfo, slot))
    -- ours: it comes from a creature or object (what we count); hidden: the game won't say what it comes from.
    -- Anything else (a clam or lockbox opened from your bags) is not ours to count and no reason to wait.
    local credited, ours, hidden = false, false, false
    for j = 1, info.n, 2 do
      local guid, qty = info[j], num(info[j + 1]) or 1
      if type(guid) == "string" then
        if id and fishing then fished[id] = (fished[id] or 0) + qty; credited = true end
        local s = src(guid)
        if s then
          ours = true
          if id then s.items[id] = (s.items[id] or 0) + qty; credited = true
          elseif isItem then s.bad = true end
          sig[#sig + 1] = s.sk .. s.id .. ":" .. (id or 0)
        end
      else
        hidden = true
      end
    end
    if fishing and id and not credited then
      -- a catch the game names no source for: its quantity from the slot itself
      local qty
      if GetLootSlotInfo then local _; _, _, qty = safe(GetLootSlotInfo, slot) end
      fished[id] = (fished[id] or 0) + (num(qty) or 1)
      credited = true
    end
    if isItem and not credited and (ours or hidden or fishing) then bad = bad + 1; sig[#sig + 1] = "?" .. (id or 0) end
  end
  return { sources = sources, order = order, fished = fished, fishing = fishing, bad = bad, sig = table.concat(sig, ",") }
end

local function countItems(items)
  local n = 0
  for _ in pairs(items) do n = n + 1 end
  return n
end

-- Count a loot window that was read. A window with an item that couldn't be read is left out of the drop counts
-- altogether: counting the corpse without that item would make the item look rarer than it is. Its place is kept.
local function countLoot(read)
  changes = changes + 1
  if read.fishing then
    lastCast = nil
    if read.bad > 0 then G.count("lootUnread"); tally("unread"); return end
    -- fishing has no mob or object: key it by zone map
    local map = where()
    local rec = lootRecord("f:" .. (map or 0))
    rec.n = rec.n + 1
    for id, qty in pairs(read.fished) do
      local it = rec.i[id] or { 0, 0 }
      it[1], it[2] = it[1] + 1, it[2] + qty
      rec.i[id] = it
    end
    tally("loot"); tally("items", countItems(read.fished))
    return
  end

  local map, x, y = where()
  local inst = instanceMap()
  local order, unread = read.order, false
  moneySources = {}
  for _, skey in ipairs(order) do
    local s = read.sources[skey]
    local sk, id, guid = s.sk, s.id, s.guid
    do
      local kind = lootKind(sk)
      local fallback = kind .. ":" .. id .. "@" .. tostring(map or inst) .. ":" .. cell(x, y, 20)
      if firstSight(looted, lootedRecent, kind .. guid, fallback) then
        local key = kind .. ":" .. id
        if read.bad > 0 or s.bad then
          unread = true
        else
          local rec = lootRecord(key)
          rec.n = rec.n + 1
          for item, qty in pairs(s.items) do
            local it = rec.i[item] or { 0, 0 }   -- { times it dropped, total quantity }
            it[1], it[2] = it[1] + 1, it[2] + qty
            rec.i[item] = it
          end
          moneySources[#moneySources + 1] = rec
          if inst then rec.zi = rec.zi or {}; rec.zi[inst] = (rec.zi[inst] or 0) + 1 end  -- looted in that dungeon
          tally("loot"); tally("items", countItems(s.items))
        end
        -- where it was: corpses mark NPC spawns, objects mark node spawns
        if sk == "u" then
          local npc = npcRecord(id)
          tally(nil, nil, id)
          seenIn(npc, inst)
          if inst and #order == 1 then readCorpse(id, guid) end
          addSpot(npc, x and map or inst or map, x, y, guid, id)  -- not again when it was counted alive
        else
          local obj = db.obj[id]
          if not obj then obj = {}; db.obj[id] = obj end
          -- the name is used once: a second object looted soon after must not take it too
          if lastObjectName and GetTime() - lastObjectAt < 15 then obj.name = lastObjectName end
          lastObjectName = nil
          obj.kind = kind
          seenIn(obj, inst)
          addSpot(obj, x and map or inst or map, x, y)
        end
      end
    end
  end
  -- (no source at all could be told: the game hid them all)
  if unread or (read.bad > 0 and #order == 0) then G.count("lootUnread"); tally("unread") end
  -- a skinning, gathering or pick pocket cast names one loot window only: the next corpse you loot within
  -- a few seconds is a plain corpse again
  lastCast = nil
  moneyBefore = num(safe(GetMoney))
end

local function finishLoot(read)
  pendingLoot = nil
  lootDone, lootSig, lootDoneAt = true, read.sig, GetTime()
  countLoot(read)
end

-- LOOT_READY and LOOT_OPENED both come for one window: it is read once. A window with something still loading is
-- looked at again (0.2 s, 0.6 s, and when it closes) and counted with what could be read by then.
-- last: count it now, whatever is still unreadable
local readLoot
readLoot = function(last)
  if paused then return end
  local read = scanLoot()
  if not read then return end
  -- the same window again; another one here means its LOOT_CLOSED never came
  if lootDone and read.sig == lootSig and GetTime() - lootDoneAt < 60 then return end
  if read.bad == 0 or last == true then return finishLoot(read) end
  if pendingLoot then pendingLoot.read = read; return end
  local p = { read = read }
  pendingLoot = p
  C_Timer.After(0.2, G.wrap("timer:loot", function() if pendingLoot == p then readLoot() end end))
  C_Timer.After(0.6, G.wrap("timer:loot", function() if pendingLoot == p then readLoot(true) end end))
end

local function lootClosed()
  -- state first: whatever fails below, the next loot window is read
  local p = pendingLoot
  pendingLoot = nil
  if p then G.run("loot:closing", finishLoot, p.read) end
  local sources, before = moneySources, moneyBefore
  moneySources, moneyBefore, lootDone, lootSig = nil, nil, false, nil
  -- money is credited only when one source was looted, so it can be attributed
  if sources and #sources == 1 and before and not p then
    local now = num(safe(GetMoney))
    if now and now > before then
      local rec = sources[1]
      rec.m = (rec.m or 0) + (now - before)
      rec.mn = (rec.mn or 0) + 1
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Vendors

local merchantOpen = false   -- (buying prints the same "You receive item" line as a quest reward)

-- A currency's id, from its link ("currency:3402") or, as the merchant cost gives only its name, from the
-- player's currency list. nil when unknown: the site takes only ids.
local function currencyID(link, name)
  link = ok(link)
  local id = type(link) == "string" and tonumber(link:match("currency:(%d+)"))
  if id then return id end
  name = ok(name)
  local C = C_CurrencyInfo
  if type(name) ~= "string" or name == "" or type(C) ~= "table" or not C.GetCurrencyListInfo then return nil end
  for i = 1, math.min(num(safe(C.GetCurrencyListSize)) or 0, 200) do
    local info = safe(C.GetCurrencyListInfo, i)
    if type(info) == "table" and ok(info.name) == name and not ok(info.isHeader) then
      id = num(ok(info.currencyID))
      if not id and C.GetCurrencyListLink then
        local l = safe(C.GetCurrencyListLink, i)
        id = type(l) == "string" and tonumber(l:match("currency:(%d+)"))
      end
      if id then return id end
    end
  end
end
ns.CurrencyID = currencyID

-- Costs saved by 0.5.0 and older named a currency instead of giving its id ("currency:Merchant's Favorx200"),
-- which the site can't read: put the id in when the player's currency list knows the name (else it stays as it
-- is until a later login or the next visit to that vendor; the site skips it meanwhile).
local function fixVendorCosts(data)
  local fixed = 0
  for _, v in pairs(data.vendor or {}) do
    for _, e in pairs(type(v) == "table" and v.i or {}) do
      if type(e) == "table" and type(e.cost) == "string" and e.cost:find("currency:%D") then
        local parts, bad = {}, false
        for part in e.cost:gmatch("[^,]+") do
          local name, n = part:match("^currency:(.-)x(%d+)$")
          if name and not tonumber(name) then
            local id = currencyID(nil, name)
            if id then part = "currency:" .. id .. "x" .. n else bad = true end
          end
          parts[#parts + 1] = part
        end
        if not bad then e.cost = table.concat(parts, ","); fixed = fixed + 1 end
      end
    end
  end
  return fixed
end
ns.FixVendorCosts = fixVendorCosts

-- -> items whose link the game hasn't loaded yet (read again a moment later)
local function readVendor()
  if paused then return end
  local kind, id = parseGUID(UnitGUID("npc"))
  if kind ~= "u" then return end
  local _ = readUnit("npc", true) or npcRecord(id)
  local v = db.vendor[id]
  if type(v) ~= "table" then v = {}; db.vendor[id] = v end
  if type(v.i) ~= "table" then v.i = {} end
  local reaction = num(UnitReaction("npc", "player"))
  local missing = 0
  for slot = 1, (num(safe(GetMerchantNumItems)) or 0) do
    local item = itemID(safe(GetMerchantItemLink, slot))
    if not item then
      missing = missing + 1
    else
      local price, stack, avail, extended
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = safe(C_MerchantFrame.GetItemInfo, slot)
        if type(info) == "table" then price, stack, avail, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
      else
        local _
        _, _, price, stack, avail, _, _, extended = safe(GetMerchantItemInfo, slot)
      end
      price, stack, avail, extended = num(price), num(stack), num(avail), ok(extended)
      -- What the game doesn't give this time keeps its saved value: a half-read line never wipes a full one.
      local e = type(v.i[item]) == "table" and v.i[item] or {}
      v.i[item] = e
      if price then e.price = price end
      if stack then e.stack = stack end
      if avail then e.limited = avail >= 0 and 1 or nil end
      if reaction then e.react = reaction end
      if extended then
        -- "item:123x2,currency:3402x60"; left as it was when any part is unknown (a partial cost would read as cheaper)
        local costs = {}
        for c = 1, (num(safe(GetMerchantItemCostInfo, slot)) or 0) do
          local _, amount, link, currency = safe(GetMerchantItemCostItem, slot, c)
          local cid, ckind = itemID(link), "item"
          if not cid then cid, ckind = currencyID(link, currency), "currency" end
          amount = num(amount)
          if not cid or not amount or amount <= 0 then costs = nil; break end
          costs[#costs + 1] = ckind .. ":" .. cid .. "x" .. amount
        end
        if costs and #costs > 0 then e.cost = table.concat(costs, ",") end
      elseif extended == false then
        e.cost = nil
      end
    end
  end
  v.t = time()
  changes = changes + 1
  return missing
end

-- The merchant window opened: read it now, and again while items are still loading (1.5 s, then 4 s later).
local function vendorOpened()
  if paused then return end
  tally("vendors")
  local waits, try = { 1.5, 4 }, 0
  local function again()
    if paused or not merchantOpen then return end
    local missing = readVendor()
    if not missing or missing == 0 then return end  -- (0 is true in Lua)
    try = try + 1
    if waits[try] then
      C_Timer.After(waits[try], G.wrap("timer:vendor", again))
    else
      G.count("vendorItemsUnread", missing)  -- still loading after 5 s: read at the next visit
    end
  end
  again()
end

---------------------------------------------------------------------------------------------------
-- Quests

-- a chat format of the game's ("You receive item: %s.") as a Lua pattern that captures its values
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  -- escape magic characters, then %s / %1$s -> (.-) and %d / %2$d -> (%d+)
  local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
  p = p:gsub("%%%d?%%?%$?s", "(.-)"):gsub("%%%d?%%?%$?d", "(%%d+)")
  return "^" .. p .. "$"
end

local function questRecord(qid)
  changes = changes + 1
  local q = db.quest[qid]
  if not q then q = {}; db.quest[qid] = q end
  return q
end

-- who is offering or taking the quest: an NPC, an object, or an item
local function questParty(startItem)
  if startItem and startItem ~= 0 then return "i:" .. startItem end
  local kind, id = parseGUID(UnitGUID("npc"))
  if kind then
    if kind == "u" then readUnit("npc", true) end
    return kind .. ":" .. id
  end
end

-- "id x count" of the items a quest window lists; the second result says some item was still loading
local function links(kind, count)
  local out, missing = {}, false
  count = num(count) or 0
  for i = 1, math.min(count, 12) do
    local _, _, n, _, _, infoID = safe(GetQuestItemInfo, kind, i)
    local id = itemID(safe(GetQuestItemLink, kind, i)) or num(infoID)  -- (retail's 6th value is the item id)
    if id and id > 0 then
      out[#out + 1] = id .. "x" .. (num(n) or 1)
    else
      missing = true
    end
  end
  return #out > 0 and table.concat(out, ",") or nil, missing
end

-- "id x amount" of the currencies the reward window lists (Merchant's Favor: "3402x10")
local MAX_LISTED_CURRENCIES = 8
local function rewardCurrencies()
  local out = {}
  for i = 1, math.min(num(safe(GetNumRewardCurrencies)) or 0, MAX_LISTED_CURRENCIES) do
    local id, amount
    if C_QuestOffer and C_QuestOffer.GetQuestRewardCurrencyInfo then
      local info = safe(C_QuestOffer.GetQuestRewardCurrencyInfo, "reward", i)
      if type(info) == "table" then
        id, amount = num(info.currencyID), num(info.totalRewardAmount) or num(info.baseRewardAmount)
      end
    end
    if not id and GetQuestCurrencyID then id = num(safe(GetQuestCurrencyID, "reward", i)) end
    if not amount and GetQuestCurrencyInfo then
      local _, _, n = safe(GetQuestCurrencyInfo, "reward", i)
      amount = num(n)
    end
    if id and amount and id > 0 and amount > 0 then out[#out + 1] = id .. "x" .. amount end
  end
  return #out > 0 and table.concat(out, ",") or nil
end

-- what the window lists; true when a reward item was still loading (read again a moment later)
local function readRewards(q)
  local reward, m1 = links("reward", safe(GetNumQuestRewards))
  local choice, m2 = links("choice", safe(GetNumQuestChoices))
  q.reward = reward or q.reward
  q.choice = choice or q.choice
  q.currency = rewardCurrencies() or q.currency
  local money = num(safe(GetRewardMoney))
  if money and money > 0 then q.money = money end
  return m1 or m2
end

local function questDetail(startItem)
  if paused then return end
  local qid = ok(GetQuestID())
  if not qid or qid == 0 then return end
  local q = questRecord(qid)
  q.title = noName(ok(GetTitleText())) or q.title
  q.from = questParty(startItem) or q.from
  local map, x, y = where()
  if map and x then q.fromAt = map .. ":" .. x .. ":" .. y end
  -- the lowest player level that was offered this quest approximates its required level
  local lvl = ok(UnitLevel("player"))
  if lvl then q.offeredAt = math.min(q.offeredAt or lvl, lvl) end
  readRewards(q)
end

-- objective lines that say what to do ("item|1|" with no text is one that never finished loading)
local function goodLines(list)
  local n = 0
  for _, line in ipairs(type(list) == "table" and list or {}) do
    if type(line) == "string" and line:match("^[^|]*|[^|]*|.*%S") then n = n + 1 end
  end
  return n
end
ns.GoodLines = goodLines

-- try: nil for the event itself; 1.. for the looks after it while an objective was still loading
local OBJECTIVE_WAITS = { 1, 3, 8 }
local function questAccepted(qid, try)
  qid = num(qid)
  if paused or not qid or qid <= 0 or type(C_QuestLog) ~= "table" then return end
  local q = questRecord(qid)
  local idx = safe(C_QuestLog.GetLogIndexForQuestID, qid)
  local info = idx and safe(C_QuestLog.GetInfo, idx)
  if type(info) == "table" then
    q.title = noName(ok(info.title)) or q.title
    q.level = num(info.level) or q.level
    q.group = num(info.suggestedGroup) or q.group
  end
  local objectives = safe(C_QuestLog.GetQuestObjectives, qid)
  if type(objectives) == "table" and #objectives > 0 then
    local out, loading = {}, false
    for _, o in ipairs(objectives) do
      local isTable = type(o) == "table"
      local text = isTable and noName(ok(o.text))
      -- drop the player's progress ("3/10 ") so every upload reads the same
      text = type(text) == "string" and text:gsub("^%d+/%d+%s*", "") or ""
      local otype, need = isTable and ok(o.type), isTable and num(o.numRequired)
      if text:find("%S") then
        out[#out + 1] = (type(otype) == "string" and otype or "") .. "|" .. (need or "") .. "|" .. text
      else
        loading = true  -- an item objective whose item isn't loaded yet reads "" for a moment
      end
    end
    -- a list with a line still loading replaces only a list that says less
    if #out > 0 and (not loading or #out > goodLines(q.objectives)) then q.objectives = out end
    try = try or 0
    if loading and OBJECTIVE_WAITS[try + 1] then
      C_Timer.After(OBJECTIVE_WAITS[try + 1], G.wrap("timer:quest", function() questAccepted(qid, try + 1) end))
    end
  end
end

-- Quests in the log whose objectives were never read in full (taken during a loading screen, before the addon was
-- installed, or with an item that hadn't loaded): read now. Each quest once a session.
local swept = {}
local function sweepQuestLog()
  if paused or not db or not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return end
  local n = num(safe(C_QuestLog.GetNumQuestLogEntries)) or 0
  for i = 1, math.min(n, 80) do
    local info = safe(C_QuestLog.GetInfo, i)
    local qid = type(info) == "table" and not ok(info.isHeader) and num(info.questID)
    if qid and qid > 0 and not swept[qid] then
      swept[qid] = true
      local q = db.quest[qid]
      local have = type(q) == "table" and type(q.objectives) == "table" and #q.objectives or 0
      if have == 0 or goodLines(q.objectives) < have then
        if type(q) ~= "table" then G.count("questFromLog") end
        questAccepted(qid)
      end
    end
  end
end
ns.SweepQuestLog = sweepQuestLog

local function questProgress()
  if paused then return end
  local qid = ok(GetQuestID())
  if not qid or qid == 0 then return end
  local q = questRecord(qid)
  -- repeatable hand-ins (bring 10 Linen Cloth) open here without a quest details window: the title too
  q.title = noName(ok(GetTitleText())) or q.title
  q.needs = links("required", safe(GetNumQuestItems)) or q.needs
end

local function questComplete()
  if paused then return end
  local qid = ok(GetQuestID())
  if not qid or qid == 0 then return end
  local q = questRecord(qid)
  q.title = noName(ok(GetTitleText())) or q.title
  q.to = questParty() or q.to
  local map, x, y = where()
  if map and x then q.toAt = map .. ":" .. x .. ":" .. y end
  if readRewards(q) then
    C_Timer.After(0.5, G.wrap("timer:quest", function()
      if not paused and ok(GetQuestID()) == qid then readRewards(q) end
    end))
  end
end

---------------------------------------------------------------------------------------------------
-- What a turn-in actually gave: for a few seconds after QUEST_TURNED_IN, currency gains (CURRENCY_DISPLAY_UPDATE,
-- or the chat line when that has no amount) and "You receive item" lines go to that quest. Bonus rewards (a
-- Performance Bonus on top of the Merchant's Favor) show up as a spread of amounts:
--   q.got = { n = turn-ins watched, c = { [currency] = { [amount] = times } }, i = { [item] = { [count] = times } } }
-- Gains a moment before the turn-in event (the game may send them first) count too. A second turn-in closes the
-- first one's window. No combat log: only these events and the player's own chat lines.

local GOT_WINDOW = 3        -- seconds after the turn-in
local GOT_BEFORE = 1        -- seconds before it
local GOT_CURRENCIES, GOT_ITEMS, GOT_AMOUNTS = 8, 16, 24
local watch                 -- { q = quest id, ends = time, c = {}, cc = {}, i = {} }
local early = {}            -- gains with no window yet: { at, kind, id, n }

local function addGain(w, kind, id, n)
  w[kind][id] = (w[kind][id] or 0) + n
end

local function gain(kind, id, n)
  if paused or not id or not n or id <= 0 or n <= 0 then return end
  local now = GetTime()
  if watch and now <= watch.ends then addGain(watch, kind, id, n); return end
  while early[1] and now - early[1].at > GOT_BEFORE do table.remove(early, 1) end
  if #early < 20 then early[#early + 1] = { at = now, kind = kind, id = id, n = n } end
end

local function spread(into, id, amount, maxIds)
  local d = into[id]
  if not d then
    local ids = 0
    for _ in pairs(into) do ids = ids + 1 end
    if ids >= maxIds then return end
    d = {}; into[id] = d
  end
  if d[amount] then d[amount] = d[amount] + 1
  else
    local amounts = 0
    for _ in pairs(d) do amounts = amounts + 1 end
    if amounts < GOT_AMOUNTS then d[amount] = 1 end
  end
end

local function closeWatch()
  local w = watch
  watch = nil
  if not w or not db then return end
  local q = db.quest[w.q]
  if not q then return end
  local got = q.got or {}
  q.got = got
  got.n = (got.n or 0) + 1
  for id, n in pairs(w.c) do got.c = got.c or {}; spread(got.c, id, n, GOT_CURRENCIES) end
  for id, n in pairs(w.cc) do  -- the chat line only for currencies the update event gave no amount for
    if not w.c[id] then got.c = got.c or {}; spread(got.c, id, n, GOT_CURRENCIES) end
  end
  for id, n in pairs(w.i) do got.i = got.i or {}; spread(got.i, id, n, GOT_ITEMS) end
  changes = changes + 1
end
ns.CloseRewardWatch = closeWatch

local function watchTurnIn(qid)
  closeWatch()
  local now = GetTime()
  local w = { q = qid, ends = now + GOT_WINDOW, c = {}, cc = {}, i = {} }
  for _, e in ipairs(early) do
    if now - e.at <= GOT_BEFORE then addGain(w, e.kind, e.id, e.n) end
  end
  early = {}
  watch = w
  C_Timer.After(GOT_WINDOW + 0.1, G.wrap("timer:handin", function() if watch == w then closeWatch() end end))
end

-- CURRENCY_DISPLAY_UPDATE: (currencyID, quantity, quantityChange, ...); only plain numbers are compared
local function currencyUpdate(id, _, change)
  gain("c", num(id), num(change))
end

-- the player's own chat lines: "You receive item: [x]x2." and "You receive currency: [Merchant's Favor] x10."
local ITEM_PUSHED = toPattern(_G.LOOT_ITEM_PUSHED_SELF)
local ITEM_PUSHED_N = toPattern(_G.LOOT_ITEM_PUSHED_SELF_MULTIPLE)
local CURRENCY_GOT = toPattern(_G.CURRENCY_GAINED)
local CURRENCY_GOT_N = toPattern(_G.CURRENCY_GAINED_MULTIPLE)
local CURRENCY_GOT_BONUS = toPattern(_G.CURRENCY_GAINED_MULTIPLE_BONUS)

local function chatGain(text, one, many, linkKind)
  local link, n
  if many then link, n = text:match(many) end
  if not link and one then link = text:match(one); n = link and 1 end
  if not link then return nil end
  return tonumber(link:match(linkKind .. ":(%d+)")), tonumber(n)
end

local function lootLine(text)
  text = ok(text)
  if paused or merchantOpen or type(text) ~= "string" then return end
  local id, n = chatGain(text, ITEM_PUSHED, ITEM_PUSHED_N, "item")
  if id then gain("i", id, n) end
end

local function currencyLine(text)
  text = ok(text)
  if paused or type(text) ~= "string" then return end
  local id, n = chatGain(text, CURRENCY_GOT, CURRENCY_GOT_N, "currency")
  if not id and CURRENCY_GOT_BONUS then id, n = chatGain(text, nil, CURRENCY_GOT_BONUS, "currency") end
  if id then gain("cc", id, n) end
end
ns.ChatGain = chatGain

---------------------------------------------------------------------------------------------------
-- Services and trainers: what an NPC does when you talk to it

local function service(name)
  if paused then return end
  local kind, id = parseGUID(UnitGUID("npc"))
  if kind ~= "u" then return end
  local rec = readUnit("npc", true) or npcRecord(id)
  rec.svc = rec.svc or {}
  if not rec.svc[name] then rec.svc[name] = 1; changes = changes + 1 end
  return id
end

local function readTrainer()
  local id = service("train")
  if not id then return end
  local t = type(db.trainer[id]) == "table" and db.trainer[id] or {}
  db.trainer[id] = t
  if type(t.s) ~= "table" then t.s = {} end
  for i = 1, (num(safe(GetNumTrainerServices)) or 0) do
    local name, sub, kind = safe(GetTrainerServiceInfo, i)
    if name and kind ~= "header" then
      local tip = C_TooltipInfo and C_TooltipInfo.GetTrainerService and safe(C_TooltipInfo.GetTrainerService, i)
      local spell = tip and ok(tip.id)
      local key = spell or (sub and sub ~= "" and (name .. " (" .. sub .. ")") or name)
      -- what the game doesn't give this time keeps its saved value
      local e = type(t.s[key]) == "table" and t.s[key] or {}
      t.s[key] = e
      e.c = num(safe(GetTrainerServiceCost, i)) or e.c
      e.l = num(safe(GetTrainerServiceLevelReq, i)) or e.l
    end
  end
  t.t = time()
  changes = changes + 1
  tally("trainers")
end

---------------------------------------------------------------------------------------------------
-- XP from kills: "Boar dies, you gain 85 experience." (solo only, so it is the mob's own XP)

local XP_PLAIN = toPattern(_G.COMBATLOG_XPGAIN_FIRSTPERSON)     -- %s dies, you gain %d experience.
local XP_RESTED = toPattern(_G.COMBATLOG_XPGAIN_EXHAUSTION1)    -- ... (%s exp %s bonus)

local function readKillXP(text)
  text = ok(text)
  if paused or type(text) ~= "string" or not XP_PLAIN then return end
  local name, xp = text:match(XP_PLAIN)
  local bonus
  if not name and XP_RESTED then
    local b
    name, xp, b = text:match(XP_RESTED)
    bonus = tonumber(b)
  end
  xp = tonumber(xp)
  local seen = name and recent[name]
  if not seen or GetTime() - seen.at > 60 then return end
  -- It died in a fight with you, so it was close by: a rough spot when no exact one is known on this map (creatures
  -- you fight but never loot, and range can't be checked in combat).
  local map, x, y = where()
  local npc = db.npc[seen.id]
  if map and x and npc and not hasCells(npc.p, map) and not hasCells(npc.pa, map) then
    addSpot(npc, map, x, y, nil, seen.id, "pa")
  end
  if not xp or IsInGroup() or not seen.lvl or seen.lvl < 1 then return end
  local pl = ok(UnitLevel("player"))
  if not pl then return end
  xp = xp - (bonus or 0)
  if xp <= 0 then return end
  local rec = npcRecord(seen.id)
  rec.xp = rec.xp or {}
  rec.xp[pl .. ":" .. seen.lvl] = xp   -- player level : mob level -> XP
  changes = changes + 1
  tally("kills", 1, seen.id)
end

---------------------------------------------------------------------------------------------------
-- Setup

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return safe(C_Spell.GetSpellName, id) end
  if GetSpellInfo then return (safe(GetSpellInfo, id)) end
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local noEvent = {}  -- events the game refused to register: what they bring is not recorded, and the health says so

local function init()
  if type(EverlookDBData) ~= "table" then
    if EverlookDBData ~= nil then G.note("repair", "the saved data was not a table") end
    EverlookDBData = {}
  end
  db = EverlookDBData
  G.bind(nil)  -- what goes wrong from here on is kept until this login's health exists
  -- first of all a file every later step can rely on: tables are tables, rows are rows (Care.lua)
  local okRepair, repaired = G.run("repair", Care.Repair, db)
  if not okRepair then
    for _, name in ipairs({ "npc", "loot", "obj", "vendor", "quest", "trainer", "beast" }) do
      if type(db[name]) ~= "table" then db[name] = {} end
    end
  end
  db.format = VERSION
  local version, build = safe(GetBuildInfo)
  local buildKey = (version and build) and (version .. "." .. build) or nil
  db.builds = db.builds or {}
  if buildKey then db.builds[buildKey] = true end
  -- the build and addon version this file is written by now: the site tags each upload with them
  db.build = buildKey or db.build
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  db.addon = meta and safe(meta, ADDON, "Version") or nil
  if ns.HealthCheck then
    local okHealth = G.run("init:health", function()
      ns.health = ns.HealthCheck(db, db.addon)
      ns.TrustCounts(ns.health.guid)
    end)
    if not okHealth or type(ns.health) ~= "table" then
      ns.health = { build = buildKey or "?", addon = db.addon, errors = 0, guid = { checked = 0, badFormat = 0, changed = 0 } }
      db.health = ns.health
      ns.TrustCounts(ns.health.guid)
    end
    G.bind(ns.health)
  end
  if okRepair and (repaired or 0) > 0 then G.count("repaired", repaired) end
  table.sort(noEvent)
  if ns.health then ns.health.noEvent = #noEvent > 0 and noEvent or nil end
  db.since = db.since or time()
  -- names are kept in the game's language: a new language starts them again, the counts stay
  local locale = GetLocale()
  local okLocale, changed = G.run("init:locale", Care.LocaleChanged, db, locale)
  if okLocale and changed then G.count("localeChanged") end
  db.locale = locale
  -- changes to the saved shape, each once per data file
  local _, why = Care.Migrate(db, G.run)
  ns.NewerData = (why == "newer") or nil
  G.run("init:vendorCosts", fixVendorCosts, db)
  settings = ns.InitSettings(db)
  paused = settings.paused and true or false

  for kind, ids in pairs(GATHER_SPELLS) do
    for _, id in ipairs(ids) do
      local name = spellName(id)
      if name then GATHER[name] = kind end
    end
  end
end

-- the world-object tooltip ("Peacebloom", "Copper Vein", "Battered Chest") names the next looted object;
-- a player's corpse ("Corpse of <name>", the game's CORPSE_TOOLTIP) is never taken as one, nor your own name
local corpseBefore, corpseAfter = (type(CORPSE_TOOLTIP) == "string" and CORPSE_TOOLTIP or ""):match("^(.-)%%s(.*)$")
local function isCorpse(text)
  return corpseBefore ~= nil and #text > #corpseBefore + #corpseAfter
    and text:sub(1, #corpseBefore) == corpseBefore and text:sub(#text - #corpseAfter + 1) == corpseAfter
end
GameTooltip:HookScript("OnShow", G.wrap("tooltip", function(tip)
  -- through safe(): in combat and instances these can be secret values, which can't be tested
  if safe(tip.GetOwner, tip) ~= UIParent then return end
  if tip.GetUnit and safe(tip.GetUnit, tip) then return end
  if tip.GetItem and safe(tip.GetItem, tip) then return end
  local line = _G.GameTooltipTextLeft1
  local text = noName(line and safe(line.GetText, line))
  if text and isCorpse(text) then text = nil end
  -- a world object whose name is hidden (instances) or not taken: forget the last one, or the chest you open
  -- next would get the name of the chair you hovered before it
  if text and text ~= "" then lastObjectName, lastObjectAt = text, GetTime() else lastObjectName = nil end
end))

---------------------------------------------------------------------------------------------------
-- Saving: the game writes SavedVariables only on logout or reload; /edb save (or the window's Save button)
-- reloads to write them now. No pop-up offers it: it can't be dismissed and sits in the middle of the screen.

-- Just before the game writes the file (logout, reload): finish what is half done, then note how complete and
-- how big the file is (health.gaps, health.rec, health.bytes) so the site can tell when something goes missing.
local function beforeSave()
  if not db then return end
  G.run("save:handin", ns.CloseRewardWatch)
  if pendingLoot then
    local p = pendingLoot
    pendingLoot = nil
    G.run("save:loot", finishLoot, p.read)
  end
  G.run("save:care", function()
    local h = ns.health
    if type(h) ~= "table" then return end
    local size, stages = Care.Compact(db)
    if stages > 0 then G.count("compacted", stages) end
    h.gaps = Care.Gaps(db)
    h.bytes = size
    -- what this file holds, by the addon's own count: the site compares it with what it could read
    local looted = 0
    for _, rec in pairs(db.loot) do looted = looted + (tonumber(rec.n) or 0) end
    local function n(t) local c = 0; for _ in pairs(t) do c = c + 1 end; return c end
    h.rec = { npc = n(db.npc), loot = n(db.loot), looted = looted, obj = n(db.obj), vendor = n(db.vendor),
      quest = n(db.quest), trainer = n(db.trainer) }
  end)
end
ns.BeforeSave = beforeSave

local function save()
  if settings then settings.savingAt = time() end  -- read back after the reload to confirm the save
  if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end
ns.Save = save

local f = CreateFrame("Frame")
local scanTicker
local handlers = {
  PLAYER_LOGIN = function()
    -- every step on its own: one that fails is counted and the rest still runs
    if not G.run("init", init) or not db or not settings then
      db = type(EverlookDBData) == "table" and EverlookDBData or {}
      EverlookDBData = db
      pcall(Care.Repair, db)
      db.format, db.locale, db.since = VERSION, db.locale or GetLocale(), db.since or time()
      settings = settings or ns.InitSettings(db)
      paused = settings.paused and true or false
    end
    noName(nil)  -- remember the player's name for the check (never saved)
    if ns.BeastsReady then G.run("init:beasts", ns.BeastsReady) end
    local savingAt = settings.savingAt or db.savingAt  -- older versions kept it in the data
    if savingAt and time() - savingAt < 120 then
      settings.lastSave = savingAt
      if settings.savedMessage then
        C_Timer.After(2, function()
          print("|cffffd200EverlookDB|r data saved. Thanks! /edb to see what's recorded so far.")
        end)
      end
    end
    db.savingAt, settings.savingAt = nil, nil
    scanTicker = scanTicker or C_Timer.NewTicker(1, G.wrap("tick", scanNameplates))
  end,
  -- after every loading screen: nothing half done from before it stays, and the quest log is looked through
  PLAYER_ENTERING_WORLD = function()
    pendingLoot, lootDone, lootSig, moneySources, moneyBefore = nil, false, nil, nil, nil
    merchantOpen, lastCast, lastObjectName = false, nil, nil
    ns.PlaceChanged()
    C_Timer.After(5, G.wrap("timer:questlog", sweepQuestLog))
  end,
  ZONE_CHANGED_NEW_AREA = function() ns.PlaceChanged() end,
  PLAYER_LOGOUT = function() beforeSave() end,
  UPDATE_MOUSEOVER_UNIT = function() readUnit("mouseover", isNear("mouseover")) end,
  -- a unit whose GUID was hidden in combat: try once more now that combat is over
  PLAYER_REGEN_ENABLED = function()
    if not idHidden then return end
    idHidden = false
    readUnit("target", isNear("target"))
    readUnit("mouseover", isNear("mouseover"))
  end,
  PLAYER_TARGET_CHANGED = function() ns.ForgetToken("target"); readUnit("target", isNear("target")) end,
  NAME_PLATE_UNIT_ADDED = ns.ForgetToken,
  NAME_PLATE_UNIT_REMOVED = ns.ForgetToken,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit ~= "player" then return end
    lastCast, lastCastAt = spellName(spellID), GetTime()
  end,
  LOOT_READY = function() readLoot() end,
  LOOT_OPENED = function() readLoot() end,
  LOOT_CLOSED = lootClosed,
  MERCHANT_SHOW = function()
    merchantOpen = true
    vendorOpened()
  end,
  GOSSIP_SHOW = function() readUnit("npc", true) end,
  TRAINER_SHOW = function() C_Timer.After(0.5, G.wrap("timer:trainer", readTrainer)) end,   -- the list fills in a moment later
  TAXIMAP_OPENED = function() service("taxi") end,
  BANKFRAME_OPENED = function() service("bank") end,
  AUCTION_HOUSE_SHOW = function() service("ah") end,
  PET_STABLE_SHOW = function() service("stable") end,
  CONFIRM_BINDER = function() service("inn") end,
  CHAT_MSG_COMBAT_XP_GAIN = readKillXP,
  QUEST_DETAIL = questDetail,
  QUEST_ACCEPTED = function(a, b)  -- (questID) or (logIndex, questID)
    local qid = num(b) or num(a)
    if qid then swept[qid] = true end
    if not paused then tally("quests") end
    questAccepted(qid)
  end,
  MERCHANT_CLOSED = function() merchantOpen = false end,
  QUEST_PROGRESS = questProgress,
  QUEST_COMPLETE = questComplete,
  QUEST_TURNED_IN = function(qid, xp, money)
    qid = num(qid)
    if paused or not qid or qid <= 0 then return end
    tally("handins")
    local q = questRecord(qid)
    q.done = (q.done or 0) + 1
    -- XP and money can be values the game hides from addons: compare them only when they are plain numbers
    xp, money = ok(xp), ok(money)
    xp = type(xp) == "number" and xp or nil
    money = type(money) == "number" and money or nil
    local pl = ok(UnitLevel("player"))
    if pl and xp and xp > 0 then
      q.xp = q.xp or {}
      q.xp[pl] = xp   -- player level -> XP (quests give less when you outlevel them)
    end
    if money and money > 0 then q.money = money end
    watchTurnIn(qid)
  end,
  CURRENCY_DISPLAY_UPDATE = currencyUpdate,
  CHAT_MSG_LOOT = lootLine,
  CHAT_MSG_CURRENCY = currencyLine,
}
for event in pairs(handlers) do
  if not pcall(f.RegisterEvent, f, event) then noEvent[#noEvent + 1] = event end
end
-- One handler that fails is counted by its event (health.errs, with a sample) and never stops the others.
f:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_LOGIN" and not db then return end
  local okRun, err = pcall(handlers[event], ...)
  if not okRun then G.note("event:" .. event, err) end
end)

---------------------------------------------------------------------------------------------------
-- What the window and chat commands need (Options.lua)

-- Recording on or off (saved in EverlookDBSettings).
function ns.SetPaused(on)
  paused = on and true or false
  if settings then settings.paused = paused end
end
function ns.IsPaused() return paused end

-- Totals of what's recorded, and how much is unsaved since the last save (login or reload).
-- Counted once per frame: the window shows a dozen of these numbers at once.
local statusCache, statusAt
function ns.Status()
  local now = GetTime()
  if statusCache and statusAt == now then return statusCache end
  local kills = 0
  for _, rec in pairs(db.loot) do kills = kills + (type(rec) == "table" and tonumber(rec.n) or 0) end
  local s = {
    npcs = count(db.npc), loot = count(db.loot), looted = kills, objects = count(db.obj),
    vendors = count(db.vendor), trainers = count(db.trainer), quests = count(db.quest),
    beasts = count(db.beast or {}),
    since = db.since, unsaved = changes, lastSave = settings and settings.lastSave,
  }
  statusCache, statusAt = s, now
  return s
end
function ns.Ready() return db ~= nil end
function ns.Data() return db end
function ns.Changed(n) changes = changes + (n or 1) end
ns.NoName = function(text) return noName(text) end