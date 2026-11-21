-- EverlookDB: notes what you see while you play, for EverlookDB.com.
--   loot     what each mob, skinned mob, pickpocketed mob, herb, ore vein, chest and fishing spot gave
--   npcs     name, level, type, rare/elite, skinnable, max health, the zones they are in, where they stand (only
--            when you are next to them), the XP a solo kill gave, and services (flight master, banker, trainer, ...)
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
-- These three shape the data every player uploads, so they are not options.
local SPAWN_GRID = 5        -- positions are kept on a 0.5% grid of the zone map
local SPAWNS_PER_MAP = 150  -- most grid cells kept per NPC or node per map
local NEAR = 3              -- CheckInteractDistance index: about 10 yards

local db
local settings              -- EverlookDBSettings
local paused = false
local changes = 0               -- records touched since the last save (login or reload)

ns.SETTINGS_DEFAULTS = {
  version = 1,
  paused = false,
  savedMessage = true,      -- "data saved" in chat after a save
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
local function safe(f, ...)
  local r = pack(pcall(f, ...))
  if not r[1] then
    local h = ns.health  -- the self-test counts calls that threw (Health.lua)
    if h then h.errors = math.min((h.errors or 0) + 1, 1000000) end
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

local function instanceMap()
  local _, itype, difficulty, _, _, _, _, mapID = safe(GetInstanceInfo)
  if itype and itype ~= "none" then return mapID, difficulty end
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
local function addSpot(rec, map, x, y, guid, id)
  if not map then return end
  if guid then
    local fallback = (id or 0) .. "@" .. map .. ":" .. cell(x, y, SPAWN_GRID)
    if not firstSight(spotCounted, spotRecent, guid, fallback) then return end
  end
  rec.p = rec.p or {}
  local cells = rec.p[map]
  if not cells then cells = { n = 0 }; rec.p[map] = cells end
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

-- here: { map, x, y } from where(), when the caller already has it (the nameplate scan reads it once a tick)
local function readUnit(unit, near, here)
  if paused or not ok(UnitExists(unit)) or ok(UnitIsPlayer(unit)) then return end
  if ok(UnitPlayerControlled(unit)) then return end  -- pets and guardians
  -- companions and other players' pets carry a name and an owner line that a player chose or is
  if UnitIsBattlePetCompanion and ok(UnitIsBattlePetCompanion(unit)) then return end
  if UnitIsOtherPlayersPet and ok(UnitIsOtherPlayersPet(unit)) then return end
  local guid = ok(UnitGUID(unit))
  local kind, id = parseGUID(guid)
  if kind ~= "u" then
    -- a creature GUID of a shape we don't know: record nothing, but count it for the self-test
    if type(guid) == "string" and (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then countGUID("badFormat") end
    return
  end
  watchGUID(unit, guid, id)
  local rec = npcRecord(id)
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
    r.id, r.lvl, r.at = id, lvl, GetTime()
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
  if not scanned[id] then
    scanned[id] = true
    local data = safe(C_TooltipInfo.GetUnit, unit)
    if data and data.lines then
      for i, l in ipairs(data.lines) do
        local text = ok(l.leftText)
        if text then
          if SKINNABLE[text] then rec.skin = SKINNABLE[text] end
          -- line 2 is the title ("<Weapon Merchant>") when it isn't the level line
          if i == 2 and not text:find("%d") and text ~= rec.name and not ownerTitle(text) and noName(text) then rec.title = text end
        end
      end
    end
  end
  if near and guid then
    local map, x, y = here[1], here[2], here[3]
    if not x then map = instanceMap() or map end
    addSpot(rec, map, x, y, guid, id)
  end
  return rec, id
end

-- Is the unit close enough that the player's position is a good stand-in for its position?
local function isNear(unit)
  if InCombatLockdown() then return false end
  return safe(CheckInteractDistance, unit, NEAR) == true
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
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then
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
local lootDone = false
local moneyBefore, moneySources = 0, nil

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

local function readLoot()
  if paused or lootDone then return end
  local slots = GetNumLootItems() or 0
  if slots == 0 then return end
  lootDone = true
  changes = changes + 1

  -- per source: items it gave. A source is its GUID while GUIDs are stable, else its type and id (one corpse whose
  -- GUID reads differently per slot is still one corpse)
  local sources, order = {}, {}
  local fished = {}  -- every slot's items, for fishing (which has no mob or object)
  local function src(guid)
    local sk, id = parseGUID(guid)
    if not sk then return nil end
    local key = trust.stable and guid or (sk .. ":" .. id)
    local s = sources[key]
    if not s then s = { items = {}, guid = guid, sk = sk, id = id }; sources[key] = s; order[#order + 1] = key end
    return s
  end
  for slot = 1, slots do
    local link = ok(GetLootSlotLink(slot))
    local id = itemID(link)
    local info = { safe(GetLootSourceInfo, slot) }
    for j = 1, #info, 2 do
      local guid, qty = ok(info[j]), info[j + 1]
      if guid and id then fished[id] = (fished[id] or 0) + (qty or 1) end
      local s = guid and src(guid)
      if s and id then s.items[id] = (s.items[id] or 0) + (qty or 1) end
    end
  end

  local fishing = safe(IsFishingLoot)
  if fishing then
    lastCast = nil
    -- fishing has no mob or object: key it by zone map
    local map = where()
    local rec = lootRecord("f:" .. (map or 0))
    rec.n = rec.n + 1
    for id, qty in pairs(fished) do
      local it = rec.i[id] or { 0, 0 }
      it[1], it[2] = it[1] + 1, it[2] + qty
      rec.i[id] = it
    end
    return
  end

  local map, x, y = where()
  local inst = instanceMap()
  moneySources = {}
  for _, skey in ipairs(order) do
    local s = sources[skey]
    local sk, id, guid = s.sk, s.id, s.guid
    do
      local kind = lootKind(sk)
      local fallback = kind .. ":" .. id .. "@" .. tostring(map or inst) .. ":" .. cell(x, y, 20)
      if firstSight(looted, lootedRecent, kind .. guid, fallback) then
        local key = kind .. ":" .. id
        local rec = lootRecord(key)
        rec.n = rec.n + 1
        for item, qty in pairs(s.items) do
          local it = rec.i[item] or { 0, 0 }   -- { times it dropped, total quantity }
          it[1], it[2] = it[1] + 1, it[2] + qty
          rec.i[item] = it
        end
        moneySources[#moneySources + 1] = rec
        -- where it was: corpses mark NPC spawns, objects mark node spawns
        if sk == "u" then
          addSpot(npcRecord(id), x and map or inst or map, x, y, guid, id)  -- not again when it was counted alive
        else
          local obj = db.obj[id]
          if not obj then obj = {}; db.obj[id] = obj end
          -- the name is used once: a second object looted soon after must not take it too
          if lastObjectName and GetTime() - lastObjectAt < 15 then obj.name = lastObjectName end
          lastObjectName = nil
          obj.kind = kind
          addSpot(obj, x and map or inst or map, x, y)
        end
      end
    end
  end
  -- a skinning, gathering or pick pocket cast names one loot window only: the next corpse you loot within
  -- a few seconds is a plain corpse again
  lastCast = nil
  moneyBefore = GetMoney()
end

local function lootClosed()
  -- money is credited only when one source was looted, so it can be attributed
  if moneySources and #moneySources == 1 then
    local gained = GetMoney() - moneyBefore
    if gained > 0 then
      local rec = moneySources[1]
      rec.m = (rec.m or 0) + gained
      rec.mn = (rec.mn or 0) + 1
    end
  end
  moneySources = nil
  lootDone = false
end

---------------------------------------------------------------------------------------------------
-- Vendors

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

local function readVendor()
  if paused then return end
  local kind, id = parseGUID(UnitGUID("npc"))
  if kind ~= "u" then return end
  local rec = readUnit("npc", true) or npcRecord(id)
  local v = db.vendor[id] or {}
  db.vendor[id] = v
  v.i = v.i or {}
  local reaction = ok(UnitReaction("npc", "player"))
  local missing = 0
  for slot = 1, (GetMerchantNumItems() or 0) do
    local item = itemID(GetMerchantItemLink(slot))
    if not item then
      missing = missing + 1
    else
      local price, stack, avail, extended
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = safe(C_MerchantFrame.GetItemInfo, slot)
        if info then price, stack, avail, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
      else
        local _
        _, _, price, stack, avail, _, _, extended = safe(GetMerchantItemInfo, slot)
      end
      local e = { price = price, stack = stack, limited = (avail and avail >= 0) and 1 or nil, react = reaction }
      if extended then
        -- "item:123x2,currency:3402x60"; left out when any part is unknown (a partial cost would read as cheaper)
        local costs = {}
        for c = 1, (num(safe(GetMerchantItemCostInfo, slot)) or 0) do
          local _, amount, link, currency = safe(GetMerchantItemCostItem, slot, c)
          local cid, kind = itemID(link), "item"
          if not cid then cid, kind = currencyID(link, currency), "currency" end
          amount = num(amount)
          if not cid or not amount or amount <= 0 then costs = nil; break end
          costs[#costs + 1] = kind .. ":" .. cid .. "x" .. amount
        end
        e.cost = costs and #costs > 0 and table.concat(costs, ",") or nil
      end
      v.i[item] = e
    end
  end
  v.t = time()
  changes = changes + 1
  return missing
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

local function questAccepted(qid, retried)
  qid = num(qid)
  if paused or not qid or qid <= 0 then return end
  local q = questRecord(qid)
  local idx = safe(C_QuestLog.GetLogIndexForQuestID, qid)
  local info = idx and safe(C_QuestLog.GetInfo, idx)
  if info then
    q.title = noName(ok(info.title)) or q.title
    q.level = ok(info.level) or q.level
    q.group = ok(info.suggestedGroup) or q.group
  end
  local objectives = safe(C_QuestLog.GetQuestObjectives, qid)
  if type(objectives) == "table" and #objectives > 0 then
    local out, loading = {}, false
    for _, o in ipairs(objectives) do
      local text = type(o) == "table" and noName(ok(o.text))
      -- drop the player's progress ("3/10 ") so every upload reads the same
      text = type(text) == "string" and text:gsub("^%d+/%d+%s*", "") or ""
      local otype, need = ok(o.type), num(o.numRequired)
      if text ~= "" then
        out[#out + 1] = (type(otype) == "string" and otype or "") .. "|" .. (need or "") .. "|" .. text
      else
        loading = true  -- an item objective whose item isn't loaded yet reads "" for a moment
      end
    end
    -- a list with a line still loading doesn't replace a complete one
    if #out > 0 and (not loading or not q.objectives) then q.objectives = out end
    if loading and not retried then
      C_Timer.After(1, function() if not paused then questAccepted(qid, true) end end)
    end
  end
end

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
    C_Timer.After(0.5, function()
      if not paused and ok(GetQuestID()) == qid then readRewards(q) end
    end)
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
  C_Timer.After(GOT_WINDOW + 0.1, function() if watch == w then closeWatch() end end)
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

local merchantOpen = false   -- buying prints the same "You receive item" line: not a quest reward
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
  local t = db.trainer[id] or {}
  db.trainer[id] = t
  t.s = t.s or {}
  for i = 1, (safe(GetNumTrainerServices) or 0) do
    local name, sub, kind = safe(GetTrainerServiceInfo, i)
    if name and kind ~= "header" then
      local tip = C_TooltipInfo and C_TooltipInfo.GetTrainerService and safe(C_TooltipInfo.GetTrainerService, i)
      local spell = tip and ok(tip.id)
      local key = spell or (sub and sub ~= "" and (name .. " (" .. sub .. ")") or name)
      t.s[key] = { c = safe(GetTrainerServiceCost, i), l = safe(GetTrainerServiceLevelReq, i) }
    end
  end
  t.t = time()
  changes = changes + 1
end

---------------------------------------------------------------------------------------------------
-- XP from kills: "Boar dies, you gain 85 experience." (solo only, so it is the mob's own XP)

local XP_PLAIN = toPattern(_G.COMBATLOG_XPGAIN_FIRSTPERSON)     -- %s dies, you gain %d experience.
local XP_RESTED = toPattern(_G.COMBATLOG_XPGAIN_EXHAUSTION1)    -- ... (%s exp %s bonus)

local function readKillXP(text)
  text = ok(text)
  if paused or not text or not XP_PLAIN or IsInGroup() then return end
  local name, xp = text:match(XP_PLAIN)
  local bonus
  if not name and XP_RESTED then
    local b
    name, xp, b = text:match(XP_RESTED)
    bonus = tonumber(b)
  end
  xp = tonumber(xp)
  local seen = name and recent[name]
  if not xp or not seen or GetTime() - seen.at > 60 or not seen.lvl or seen.lvl < 1 then return end
  local pl = ok(UnitLevel("player"))
  if not pl then return end
  xp = xp - (bonus or 0)
  if xp <= 0 then return end
  local rec = npcRecord(seen.id)
  rec.xp = rec.xp or {}
  rec.xp[pl .. ":" .. seen.lvl] = xp   -- player level : mob level -> XP
  changes = changes + 1
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

local function init()
  EverlookDBData = EverlookDBData or {}
  db = EverlookDBData
  db.format = VERSION
  db.locale = GetLocale()
  local version, build = GetBuildInfo()
  db.builds = db.builds or {}
  db.builds[version .. "." .. build] = true
  -- the build and addon version this file is written by now: the site tags each upload with them
  db.build = version .. "." .. build
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  db.addon = meta and safe(meta, ADDON, "Version") or nil
  if ns.HealthCheck then ns.health = ns.HealthCheck(db, db.addon); ns.TrustCounts(ns.health.guid) end
  db.since = db.since or time()
  db.npc, db.loot, db.obj = db.npc or {}, db.loot or {}, db.obj or {}
  db.vendor, db.quest = db.vendor or {}, db.quest or {}
  -- older versions saved each quest's objective paragraph, which can hold your character's name: drop it
  for _, q in pairs(db.quest) do q.objective = nil end
  db.trainer = db.trainer or {}
  db.beast = db.beast or {}
  normalizeSpots(db)
  -- titles that name an owner ("Nimsy's Guardian") saved before 0.2.0 could name a player: drop them
  for _, rec in pairs(db.npc) do
    if type(rec) == "table" and type(rec.title) == "string" and ownerTitle(rec.title) then rec.title = nil end
  end
  fixVendorCosts(db)
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
GameTooltip:HookScript("OnShow", function(tip)
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
end)

---------------------------------------------------------------------------------------------------
-- Saving: the game writes SavedVariables only on logout or reload; /edb save (or the window's Save button)
-- reloads to write them now. No pop-up offers it: it can't be dismissed and sits in the middle of the screen.

local function save()
  if settings then settings.savingAt = time() end  -- read back after the reload to confirm the save
  if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end
ns.Save = save

local f = CreateFrame("Frame")
local handlers = {
  PLAYER_LOGIN = function()
    init()
    noName(nil)  -- remember the player's name for the check (never saved)
    if ns.BeastsReady then ns.BeastsReady() end
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
    C_Timer.NewTicker(1, scanNameplates)
  end,
  UPDATE_MOUSEOVER_UNIT = function() readUnit("mouseover", isNear("mouseover")) end,
  PLAYER_TARGET_CHANGED = function() ns.ForgetToken("target"); readUnit("target", isNear("target")) end,
  NAME_PLATE_UNIT_ADDED = ns.ForgetToken,
  NAME_PLATE_UNIT_REMOVED = ns.ForgetToken,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit ~= "player" then return end
    lastCast, lastCastAt = spellName(spellID), GetTime()
  end,
  LOOT_READY = readLoot,
  LOOT_OPENED = readLoot,
  LOOT_CLOSED = lootClosed,
  MERCHANT_SHOW = function()
    merchantOpen = true
    -- uncached items arrive later: read again only when some were missing (0 is true in Lua)
    local missing = readVendor()
    if missing and missing > 0 and not paused then C_Timer.After(1.5, readVendor) end
  end,
  GOSSIP_SHOW = function() readUnit("npc", true) end,
  TRAINER_SHOW = function() C_Timer.After(0.5, readTrainer) end,   -- the list fills in a moment later
  TAXIMAP_OPENED = function() service("taxi") end,
  BANKFRAME_OPENED = function() service("bank") end,
  AUCTION_HOUSE_SHOW = function() service("ah") end,
  PET_STABLE_SHOW = function() service("stable") end,
  CONFIRM_BINDER = function() service("inn") end,
  CHAT_MSG_COMBAT_XP_GAIN = readKillXP,
  QUEST_DETAIL = questDetail,
  QUEST_ACCEPTED = function(a, b) questAccepted(b or a) end,  -- (questID) or (logIndex, questID)
  MERCHANT_CLOSED = function() merchantOpen = false end,
  QUEST_PROGRESS = questProgress,
  QUEST_COMPLETE = questComplete,
  QUEST_TURNED_IN = function(qid, xp, money)
    if paused or not qid then return end
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
for event in pairs(handlers) do pcall(f.RegisterEvent, f, event) end
f:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_LOGIN" and not db then return end
  handlers[event](...)
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
  for _, rec in pairs(db.loot) do kills = kills + rec.n end
  local s = {
    npcs = count(db.npc), loot = count(db.loot), looted = kills, objects = count(db.obj),
    vendors = count(db.vendor), trainers = count(db.trainer), quests = count(db.quest),
    beasts = count(db.beast or {}),
    since = db.since, unsaved = changes, lastSave = settings.lastSave,
  }
  statusCache, statusAt = s, now
  return s
end
function ns.Ready() return db ~= nil end
function ns.Data() return db end
function ns.Changed(n) changes = changes + (n or 1) end
ns.NoName = function(text) return noName(text) end