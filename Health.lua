-- Health self-test: what the game gives this addon right now, saved with the data (EverlookDBData.health) so the
-- site can tell a game update that broke something apart from real data, and hold uploads back until it is checked.
-- Only words, true/false and counts are kept: never a GUID, a name or a realm.
--   build, addon    the client build and this addon's version (the counts start again when either changes)
--   day             the date of the last check
--   realm           "ok" or "empty": whether the realm API answers (Forever answers "" since build 71037)
--   guid            { checked, badFormat, changed }: creature GUIDs read, ones of a shape we don't know, and times
--                   the same unit gave a different GUID (EverlookDB.lua then counts without GUIDs)
--   item            "ok", "slow" (not loaded within a few seconds) or "none" (no item API)
--   missing         core APIs that are not there
--   errors          API calls that threw an error
--   errs            the same, per API by name ("CheckInteractDistance" = 12), and errors in the addon's own
--                   handlers by event or timer ("event:LOOT_READY"), at most 40 names (Guard.lua)
--   log             the last 20 distinct error messages as short samples: no GUID, no quoted text, never your name
--   notes           counts of things worth seeing that are not errors: lootUnread (loot windows left out of the
--                   drop counts because an item could not be read), vendorItemsUnread, repaired (damaged entries
--                   mended at login), localeChanged, compacted, questFromLog
--   noEvent         game events the client refused to register
--   Written just before the game saves the file (logout or reload, EverlookDB.lua beforeSave):
--   gaps            how complete the file is: npcs, noName, noLevel, exact / approx / inst / zoneOnly / noLoc (where
--                   each NPC is known to be), loot, lootNoName, objs, objNoName, quests, questNoGiver, ... (Care.lua)
--   rec             the addon's own row counts (npc, loot, looted, obj, vendor, quest, trainer): the site compares
--                   them with what it could read, so rows lost on the way are noticed
--   bytes           about the size of the file on disk
local _, ns = ...

-- APIs the Collector can't do its job without
local CORE = {
  "GetBuildInfo", "UnitGUID", "UnitName", "UnitLevel", "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition",
  "C_NamePlate.GetNamePlates", "C_TooltipInfo.GetUnit", "GetLootSourceInfo", "GetLootSlotLink", "GetNumLootItems",
  "GetMerchantItemLink", "GetMerchantNumItems", "C_QuestLog.GetQuestObjectives", "GetQuestID",
}
local PROBE_ITEM = 2589  -- Linen Cloth: in every client

local function lookup(path)
  local t = _G
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

local function itemName(id)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if type(get) ~= "function" then return nil, false end
  local name = ns.safe(get, id)
  return type(name) == "string" and name ~= "" and name or nil, true
end

-- Run the test and return the health table (in `db`); counts carry on while the build and version stay the same.
function ns.HealthCheck(db, version)
  local v, b = ns.safe(GetBuildInfo)
  local build = (v and b) and (v .. "." .. b) or "?"
  local h = type(db.health) == "table" and db.health or {}
  if h.build ~= build or h.addon ~= version then h = { build = build, addon = version } end
  db.health = h
  h.day = date("%Y-%m-%d")
  local missing = {}
  for _, name in ipairs(CORE) do
    if type(lookup(name)) ~= "function" then missing[#missing + 1] = name end
  end
  h.missing = #missing > 0 and missing or nil
  local realm = ns.safe(GetRealmName)
  h.realm = (type(realm) == "string" and realm ~= "") and "ok" or "empty"
  h.guid = type(h.guid) == "table" and h.guid or { checked = 0, badFormat = 0, changed = 0 }
  h.errors = h.errors or 0
  local name, api = itemName(PROBE_ITEM)
  if not api then
    h.item = "none"
  elseif name then
    h.item = "ok"
  else
    h.item = "slow"
    if C_Item and C_Item.RequestLoadItemDataByID then ns.safe(C_Item.RequestLoadItemDataByID, PROBE_ITEM) end
    C_Timer.After(10, function() if itemName(PROBE_ITEM) then h.item = "ok" end end)
  end
  return h
end
