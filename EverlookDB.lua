-- EverlookDB: notes what you see while you play, for EverlookDB.com.
--   loot     what each mob, skinned mob, pickpocketed mob, herb, ore vein, chest and fishing spot gave
--   npcs     name, level, type, rare/elite, skinnable, and where they stand (only when you are next to them)
--   vendors  what each vendor sells, for how much, and whether stock is limited
--   quests   who starts and ends each quest, where, the lowest level it was offered at, objectives, rewards
-- Nothing about you is saved: no character, realm or player names, no chat, no other players.
-- Everything goes into SavedVariables (EverlookDB.lua); upload that file on EverlookDB.com.
-- /edb for a summary, /edb save to write the file now (reloads the UI), /edb pause and /edb resume.

local ADDON = ...
local VERSION = 1
local SPAWN_GRID = 5        -- positions are kept on a 0.5% grid of the zone map
local SPAWNS_PER_MAP = 150  -- most grid cells kept per NPC or node per map
local NEAR = 3              -- CheckInteractDistance index: about 10 yards

local db
local paused = false
local SAVE_REMINDER = 20 * 60   -- offer a save after a loading screen once this much play is unsaved
local changes = 0               -- records touched since the last save (login or reload)

-- Forever hides some values from addons ("secret values"). Treat any of them as unknown.
local isSecret = issecretvalue or function() return false end
local function ok(v)
  if v == nil or isSecret(v) then return nil end
  return v
end
local function pack(...) return { n = select("#", ...), ... } end  -- WoW runs Lua 5.1: no table.pack
local function safe(f, ...)
  local r = pack(pcall(f, ...))
  if not r[1] then return nil end
  for i = 2, r.n do r[i] = ok(r[i]) end
  return unpack(r, 2, r.n)
end

-- "Creature-0-server-instance-zone-NPCID-spawn" -> "u", NPCID ; GameObject likewise -> "o", id
local function parseGUID(guid)
  guid = ok(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  id = tonumber(id)
  if not id then return nil end
  if kind == "Creature" or kind == "Vehicle" then return "u", id end
  if kind == "GameObject" then return "o", id end
  return nil
end

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

-- add a position to rec.p[map] as a grid cell "x:y" -> times seen
local function addSpot(rec, map, x, y)
  if not map then return end
  changes = changes + 1
  rec.p = rec.p or {}
  local cells = rec.p[map]
  if not cells then cells = { n = 0 }; rec.p[map] = cells end
  if not x then cells.n = cells.n + 1; return end  -- seen on this map, position unknown (instance)
  local key = math.floor(x / SPAWN_GRID) * SPAWN_GRID .. ":" .. math.floor(y / SPAWN_GRID) * SPAWN_GRID
  if cells[key] then
    cells[key] = cells[key] + 1
  elseif cells.n < SPAWNS_PER_MAP then
    cells[key] = 1
    cells.n = cells.n + 1
  end
end

---------------------------------------------------------------------------------------------------
-- NPCs

local scanned = {}  -- npc ids whose tooltip was read this session
local SKINNABLE = {}
for _, g in ipairs({ "UNIT_SKINNABLE_LEATHER", "UNIT_SKINNABLE_HERB", "UNIT_SKINNABLE_ROCK", "UNIT_SKINNABLE_BOLTS" }) do
  if _G[g] then SKINNABLE[_G[g]] = g:sub(16):lower() end  -- leather, herb, rock, bolts
end

local function npcRecord(id)
  local rec = db.npc[id]
  if not rec then rec = {}; db.npc[id] = rec end
  return rec
end

local function readUnit(unit, near)
  if paused or not ok(UnitExists(unit)) or ok(UnitIsPlayer(unit)) then return end
  if ok(UnitPlayerControlled(unit)) then return end  -- pets and guardians
  local kind, id = parseGUID(UnitGUID(unit))
  if kind ~= "u" then return end
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
  rec.class = ok(UnitClassification(unit)) or rec.class      -- normal, elite, rare, rareelite, worldboss
  rec.type = ok(UnitCreatureType(unit)) or rec.type          -- Beast, Humanoid, ... (client language)
  rec.family = ok(UnitCreatureFamily(unit)) or rec.family    -- Wolf, Spider, ...
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
          if i == 2 and not text:find("%d") and text ~= rec.name then rec.title = text end
        end
      end
    end
  end
  if near then
    local map, x, y = where()
    if not x then map = instanceMap() or map end
    addSpot(rec, map, x, y)
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
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then readUnit(unit, isNear(unit)) end
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
local looted = {}       -- "kind:guid" already counted this session
local lootDone = false
local moneyBefore, moneySources = 0, nil

local function lootKind(sourceKind)
  if ok(IsFishingLoot()) then return "f" end
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

  -- per source guid: items it gave
  local sources, order = {}, {}
  local function src(guid)
    local s = sources[guid]
    if not s then s = { items = {} }; sources[guid] = s; order[#order + 1] = guid end
    return s
  end
  for slot = 1, slots do
    local link = ok(GetLootSlotLink(slot))
    local id = itemID(link)
    local info = { safe(GetLootSourceInfo, slot) }
    for j = 1, #info, 2 do
      local guid, qty = info[j], info[j + 1]
      if guid then
        local s = src(guid)
        if id then s.items[id] = (s.items[id] or 0) + (qty or 1) end
      end
    end
  end

  local fishing = ok(IsFishingLoot())
  if fishing then
    -- fishing has no mob or object: key it by zone map
    local map = where()
    local rec = lootRecord("f:" .. (map or 0))
    rec.n = rec.n + 1
    for _, s in pairs(sources) do
      for id, qty in pairs(s.items) do
        local it = rec.i[id] or { 0, 0 }
        it[1], it[2] = it[1] + 1, it[2] + qty
        rec.i[id] = it
      end
    end
    return
  end

  local map, x, y = where()
  local inst = instanceMap()
  moneySources = {}
  for _, guid in ipairs(order) do
    local sk, id = parseGUID(guid)
    if sk then
      local kind = lootKind(sk)
      local seenKey = kind .. guid
      if not looted[seenKey] then
        looted[seenKey] = true
        local key = kind .. ":" .. id
        local rec = lootRecord(key)
        rec.n = rec.n + 1
        for item, qty in pairs(sources[guid].items) do
          local it = rec.i[item] or { 0, 0 }   -- { times it dropped, total quantity }
          it[1], it[2] = it[1] + 1, it[2] + qty
          rec.i[item] = it
        end
        moneySources[#moneySources + 1] = rec
        -- where it was: corpses mark NPC spawns, objects mark node spawns
        if sk == "u" then
          addSpot(npcRecord(id), x and map or inst or map, x, y)
        else
          local obj = db.obj[id]
          if not obj then obj = {}; db.obj[id] = obj end
          if lastObjectName and GetTime() - lastObjectAt < 15 then obj.name = lastObjectName end
          obj.kind = kind
          addSpot(obj, x and map or inst or map, x, y)
        end
      end
    end
  end
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
        local costs = {}
        for c = 1, (safe(GetMerchantItemCostInfo, slot) or 0) do
          local _, amount, link, currency = safe(GetMerchantItemCostItem, slot, c)
          local cid = itemID(link)
          costs[#costs + 1] = (cid and ("item:" .. cid) or ("currency:" .. tostring(currency))) .. "x" .. tostring(amount)
        end
        e.cost = table.concat(costs, ",")
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

local function links(kind, count)
  local out = {}
  for i = 1, count or 0 do
    local id = itemID(GetQuestItemLink(kind, i))
    if id then
      local _, _, n = safe(GetQuestItemInfo, kind, i)
      out[#out + 1] = id .. "x" .. (n or 1)
    end
  end
  return #out > 0 and table.concat(out, ",") or nil
end

local function readRewards(q)
  q.reward = links("reward", GetNumQuestRewards()) or q.reward
  q.choice = links("choice", GetNumQuestChoices()) or q.choice
  local money = ok(GetRewardMoney())
  if money and money > 0 then q.money = money end
end

local function questDetail(startItem)
  if paused then return end
  local qid = ok(GetQuestID())
  if not qid or qid == 0 then return end
  local q = questRecord(qid)
  q.title = ok(GetTitleText()) or q.title
  q.objective = ok(GetObjectiveText()) or q.objective
  q.from = questParty(startItem) or q.from
  local map, x, y = where()
  if map and x then q.fromAt = map .. ":" .. x .. ":" .. y end
  -- the lowest player level that was offered this quest approximates its required level
  local lvl = ok(UnitLevel("player"))
  if lvl then q.offeredAt = math.min(q.offeredAt or lvl, lvl) end
  readRewards(q)
end

local function questAccepted(qid)
  if paused or not qid then return end
  local q = questRecord(qid)
  local idx = safe(C_QuestLog.GetLogIndexForQuestID, qid)
  local info = idx and safe(C_QuestLog.GetInfo, idx)
  if info then
    q.title = ok(info.title) or q.title
    q.level = ok(info.level) or q.level
    q.group = ok(info.suggestedGroup) or q.group
  end
  local objectives = safe(C_QuestLog.GetQuestObjectives, qid)
  if objectives and #objectives > 0 then
    local out = {}
    for _, o in ipairs(objectives) do
      local text = ok(o.text)
      -- drop the player's progress ("3/10 ") so every upload reads the same
      if text then out[#out + 1] = (o.type or "") .. "|" .. (o.numRequired or "") .. "|" .. text:gsub("^%d+/%d+%s*", "") end
    end
    q.objectives = out
  end
end

local function questProgress()
  if paused then return end
  local qid = ok(GetQuestID())
  if not qid or qid == 0 then return end
  local q = questRecord(qid)
  q.needs = links("required", GetNumQuestItems()) or q.needs
end

local function questComplete()
  if paused then return end
  local qid = ok(GetQuestID())
  if not qid or qid == 0 then return end
  local q = questRecord(qid)
  q.title = ok(GetTitleText()) or q.title
  q.to = questParty() or q.to
  local map, x, y = where()
  if map and x then q.toAt = map .. ":" .. x .. ":" .. y end
  readRewards(q)
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
  db.since = db.since or time()
  db.npc, db.loot, db.obj = db.npc or {}, db.loot or {}, db.obj or {}
  db.vendor, db.quest = db.vendor or {}, db.quest or {}
  paused = db.paused or false

  for kind, ids in pairs(GATHER_SPELLS) do
    for _, id in ipairs(ids) do
      local name = spellName(id)
      if name then GATHER[name] = kind end
    end
  end
end

-- the world-object tooltip ("Peacebloom", "Copper Vein", "Battered Chest") names the next looted object
GameTooltip:HookScript("OnShow", function(tip)
  if tip:GetOwner() ~= UIParent then return end
  if tip.GetUnit and tip:GetUnit() then return end
  if tip.GetItem and tip:GetItem() then return end
  local line = _G.GameTooltipTextLeft1
  local text = line and ok(line:GetText())
  if text and text ~= "" then lastObjectName, lastObjectAt = text, GetTime() end
end)

---------------------------------------------------------------------------------------------------
-- Saving: the game writes SavedVariables only on logout or reload, so after a loading screen
-- (when the player is waiting anyway) offer a one-click save if a lot is unsaved.

local function save()
  if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end

local saveButton
local function offerSave()
  if not saveButton then
    saveButton = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    saveButton:SetSize(220, 28)
    saveButton:SetPoint("TOP", UIParent, "TOP", 0, -150)
    saveButton:SetText("Save EverlookDB data")
    saveButton:SetScript("OnClick", save)
    saveButton:Hide()
  end
  saveButton:Show()
  C_Timer.After(30, function() if saveButton then saveButton:Hide() end end)
end

local loginAt = 0
local function afterLoadingScreen()
  if paused or changes == 0 or InCombatLockdown() then return end
  if GetTime() - loginAt < SAVE_REMINDER then return end
  offerSave()
end

local f = CreateFrame("Frame")
local handlers = {
  PLAYER_LOGIN = function()
    init()
    loginAt = GetTime()
    C_Timer.NewTicker(1, scanNameplates)
  end,
  UPDATE_MOUSEOVER_UNIT = function() readUnit("mouseover", isNear("mouseover")) end,
  PLAYER_TARGET_CHANGED = function() readUnit("target", isNear("target")) end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit ~= "player" then return end
    lastCast, lastCastAt = spellName(spellID), GetTime()
  end,
  LOADING_SCREEN_DISABLED = function() C_Timer.After(1, afterLoadingScreen) end,
  LOOT_READY = readLoot,
  LOOT_OPENED = readLoot,
  LOOT_CLOSED = lootClosed,
  MERCHANT_SHOW = function()
    if readVendor() and not paused then C_Timer.After(1.5, readVendor) end  -- uncached items arrive later
  end,
  GOSSIP_SHOW = function() readUnit("npc", true) end,
  QUEST_DETAIL = questDetail,
  QUEST_ACCEPTED = function(a, b) questAccepted(b or a) end,  -- (questID) or (logIndex, questID)
  QUEST_PROGRESS = questProgress,
  QUEST_COMPLETE = questComplete,
  QUEST_TURNED_IN = function(qid, xp, money)
    if paused or not qid then return end
    local q = questRecord(qid)
    q.done = (q.done or 0) + 1
    if money and money > 0 then q.money = money end
  end,
}
for event in pairs(handlers) do pcall(f.RegisterEvent, f, event) end
f:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_LOGIN" and not db then return end
  handlers[event](...)
end)

SLASH_EVERLOOKDB1 = "/edb"
SLASH_EVERLOOKDB2 = "/everlookdb"
SlashCmdList.EVERLOOKDB = function(msg)
  msg = (msg or ""):lower()
  if msg == "save" then
    save()
  elseif msg == "pause" then
    paused, db.paused = true, true
    print("|cffffd200EverlookDB|r paused. /edb resume to record again.")
  elseif msg == "resume" then
    paused, db.paused = false, false
    print("|cffffd200EverlookDB|r recording.")
  else
    local kills = 0
    for _, rec in pairs(db.loot) do kills = kills + rec.n end
    print(string.format("|cffffd200EverlookDB|r %s. %d NPCs, %d loot sources (%d looted), %d objects, %d vendors, %d quests.",
      paused and "paused" or "recording", count(db.npc), count(db.loot), kills, count(db.obj), count(db.vendor), count(db.quest)))
    print("Upload WTF\\Account\\<account>\\SavedVariables\\EverlookDB.lua on EverlookDB.com. /edb save, /edb pause, /edb resume.")
  end
end
