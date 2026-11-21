-- EverlookDB Collector: hunter pets. What a freshly tamed pet knows and what Beast Lore shows, so EverlookDB.com can
-- tell every hunter which beast teaches which ability rank.
--
--   Fresh tame   Tame Beast on a creature, then the new pet: its spellbook (spell ids, passive or not), its permanent
--                auras (Faster/Slower Attack), attack speed, level, family id, training points and the game's diet
--                words. The spellbook can fill in late, so it is read for 30 seconds before it is noted.
--   Beast Lore   the extra lines Beast Lore puts on the beast's tooltip, as the game gives them (abilities, diet,
--                tameable, ...), plus the ability lines turned into spell ids, the beast's level, the count of reads.
--
-- Saved in EverlookDBData.beast[npc id] as counts, never a list of events. The time is only a bucket: game build
-- plus ISO week ("1.60.1.70862:2026-W47"), never a day or time of day. Never the pet's name (the player chose it),
-- never a character name.

local ADDON, ns = ...

-- Spell ids from the client's Spell tables (ForeverMiner out/tables/SpellName.csv)
local TAME = { [1515] = true, [411624] = true, [469277] = true }  -- Tame Beast (not the quest tames, 1277794 ...)
local BEAST_LORE = 1462
local WATCH = 30      -- seconds the new pet's spellbook is read before the tame is noted
local READS = { 1, 3, 6, 10, 15, 20, WATCH }
local MAX_LINES = 6   -- distinct tooltip lines kept per beast and kind
local MAX_SETS = 5    -- distinct whole spell lists kept per beast

-- Pet abilities, ranks in order (Quarry web/data/guides.json "pets", from the client's SkillLineAbility), and the
-- Forever attack-speed passives. Only used to turn Beast Lore's ability lines into spell ids: the names come from
-- the game in the player's language (C_Spell.GetSpellName), so this works in every client language.
local ABILITIES = {
  { 24493, 24497, 24500, 24501 }, -- Arcane Resistance
  { 17253, 17255, 17256, 17257, 17258, 17259, 17260, 17261 }, -- Bite
  { 7371, 26177, 26178, 26179, 26201, 27685 }, -- Charge
  { 16827, 16828, 16829, 16830, 16831, 16832, 3010, 3009 }, -- Claw
  { 1742, 1753, 1754, 1755, 1756, 16697 }, -- Cower
  { 23099, 23109, 23110 }, -- Dash
  { 24423, 24577, 24578, 24579 }, -- Demoralizing Screech
  { 1264758, 1264927, 1264929, 1264930, 1264933 }, -- Dismember
  { 23145, 23147, 23148 }, -- Dive
  { 1265899, 1265901, 1265902, 1265903, 1265904 }, -- Dust Cloud
  { 23992, 24439, 24444, 24445 }, -- Fire Resistance
  { 24446, 24447, 24448, 24449 }, -- Frost Resistance
  { 24604, 24605, 24603, 24597 }, -- Furious Howl
  { 4187, 4188, 4189, 4190, 4191, 4192, 4193, 4194, 5041, 5042 }, -- Great Stamina
  { 2649, 14916, 14917, 14918, 14919, 14920, 14921 }, -- Growl
  { 24844, 25008, 25009, 25010, 25011, 25012 }, -- Lightning Breath
  { 1265054, 1265055, 1265056, 1265057, 1265058 }, -- Mine!
  { 24545, 24549, 24550, 24551, 24552, 24553, 24554, 24555, 24629, 24630 }, -- Natural Armor
  { 24492, 24502, 24503, 24504 }, -- Nature Resistance
  { 1264735, 1264736, 1264739, 1264741, 1264742 }, -- Pinch
  { 24450, 24452, 24453 }, -- Prowl
  { 1265065, 1265066, 1265067, 1265068, 1265069 }, -- Savage Rend
  { 24640, 24583, 24586, 24587 }, -- Scorpid Poison
  { 24488, 24505, 24506, 24507 }, -- Shadow Resistance
  { 26064 }, -- Shell Shield
  { 1264478, 1264479, 1264480, 1264481, 1264482 }, -- Sonic Blast
  { 1264494, 1264497, 1264498, 1264501, 1264502 }, -- Swipe
  { 1265038, 1265039, 1265040, 1265041, 1265042 }, -- Tendon Rip
  { 26090, 26187, 26188, 1264455 }, -- Thunderstomp
  { 1265843, 1265878, 1265880, 1265881, 1265883 }, -- Web
  -- Faster Attack I-VII, Slower Attack I-III: one spell each, the numeral is part of the name
  { 1263099 }, { 1263100 }, { 1263102 }, { 1263104 }, { 1263107 }, { 1263109 }, { 1263110 },
  { 1263111 }, { 1263113 }, { 1263114 },
}

local ok, safe = ns.ok, ns.safe
local function num(v) v = ok(v); return type(v) == "number" and v == v and v or nil end
local function str(v) v = ok(v); return type(v) == "string" and v ~= "" and v or nil end
local function api(space, name) local t = _G[space]; return type(t) == "table" and t[name] or nil end
local function call(f, ...) if type(f) == "function" then return safe(f, ...) end end

local function bump(t, k, by) t[k] = (t[k] or 0) + (by or 1) end
local function size(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
-- count a text key, but keep at most `max` distinct keys
local function bumpCapped(t, k, max)
  if t[k] or size(t) < max then bump(t, k) end
end

-- "Creature-0-server-instance-zone-NPCID-spawn" or "Pet-0-...-NPCID-..." -> kind, NPCID
local function guidId(guid)
  return ns.GuidTypeID(str(guid))
end

------------------------------------------------------------------------------------------------------------------
-- Time bucket: game build plus ISO week, from the calendar date only (no time of day is kept anywhere)

local function isoWeek(t)
  local d = date("*t", t)
  local wday = (d.wday + 5) % 7 + 1                -- Monday 1 .. Sunday 7
  local week = math.floor((d.yday - wday + 10) / 7)
  local year = d.year
  local function weeks(y)
    -- a year has 53 ISO weeks when it starts on a Thursday, or on a Wednesday in a leap year
    local jan1 = date("*t", time({ year = y, month = 1, day = 1, hour = 12 }))
    local w = (jan1.wday + 5) % 7 + 1
    local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
    return (w == 4 or (leap and w == 3)) and 53 or 52
  end
  if week < 1 then year = year - 1; week = weeks(year)
  elseif week > weeks(year) then year = year + 1; week = 1 end
  return ("%04d-W%02d"):format(year, week)
end
ns.IsoWeek = isoWeek

local function bucket()
  local version, build = call(GetBuildInfo)
  local okWeek, week = pcall(isoWeek, time())
  if not (version and build and okWeek) then return nil end
  return version .. "." .. build .. ":" .. week
end

local function beastRecord(npc)
  local db = ns.Data()
  db.beast = db.beast or {}
  local rec = db.beast[npc]
  if not rec then rec = {}; db.beast[npc] = rec end
  local b = bucket()
  if b then rec.wk = rec.wk or {}; bump(rec.wk, b) end
  ns.Changed()
  return rec
end

------------------------------------------------------------------------------------------------------------------
-- Ability names in the client's language -> spell id per rank (built once, at login)

local byName           -- localized name -> { rank -> spell id }
local names            -- the names, longest first ("Faster Attack II" before "Faster Attack I")
local function buildNames()
  byName, names = {}, {}
  for _, ranks in ipairs(ABILITIES) do
    for rank, id in ipairs(ranks) do
      local name = str(call(api("C_Spell", "GetSpellName"), id))
      if name then
        if not byName[name] then byName[name] = {}; names[#names + 1] = name end
        byName[name][rank] = id
      end
    end
  end
  table.sort(names, function(a, b) return #a > #b end)
end

-- The spell ids an ability line names: "Bite (Rank 3), Dash (Rank 1)" -> { 17256, 23099 }. The rank is the first
-- number after the name; an ability with one rank needs none. A name it can't place is left out.
local function spellsIn(text)
  if not byName then buildNames() end
  local out, taken = {}, {}
  for _, name in ipairs(names) do
    local from = 1
    while true do
      local s, e = text:find(name, from, true)
      if not s then break end
      local overlaps = false
      for _, r in ipairs(taken) do if s <= r[2] and e >= r[1] then overlaps = true end end
      if not overlaps then
        taken[#taken + 1] = { s, e }
        local ranks = byName[name]
        local rest = text:sub(e + 1):match("^[^,;\n]*") or ""
        local rank = tonumber(rest:match("(%d+)"))
        local id = rank and ranks[rank] or (not rank and ranks[1] and not ranks[2] and ranks[1]) or nil
        if id then out[#out + 1] = id end
      end
      from = e + 1
    end
  end
  return out
end
ns.SpellsIn = spellsIn

------------------------------------------------------------------------------------------------------------------
-- Fresh tames

local pendingTame      -- { npc, lvl, at, stop, failed }: a Tame Beast cast on a creature
local watching         -- { guid, npc, lvl, best, info, reads }: the new pet being read
local recordedPets = {}  -- pet GUIDs already noted this session

local function petBank()
  local e = Enum and Enum.SpellBookSpellBank
  local v = e and e.Pet
  if v == nil then return 1 end
  return v
end

-- Everything the new pet shows right now. Nothing here reads its name.
local function readPet()
  local p = { spells = {}, n = 0, auras = {} }
  local count = num(call(api("C_SpellBook", "HasPetSpells")))
  local get, passive = api("C_SpellBook", "GetSpellBookItemInfo"), api("C_SpellBook", "IsSpellBookItemPassive")
  for i = 1, math.min(count or 0, 40) do
    local info = call(get, i, petBank())
    local id = type(info) == "table" and (num(info.spellID) or num(info.actionID))
    if id and id > 0 and not p.spells[id] then
      local pas = type(info) == "table" and ok(info.isPassive)
      if pas == nil then pas = call(passive, i, petBank()) end
      p.spells[id] = pas == true
      p.n = p.n + 1
    end
  end
  -- permanent auras: Forever's Faster/Slower Attack passives (duration 0 = no end)
  local byIndex = api("C_UnitAuras", "GetAuraDataByIndex")
  for i = 1, 40 do
    local a = call(byIndex, "pet", i, "HELPFUL")
    if type(a) ~= "table" then break end
    local id, dur = num(a.spellId), num(a.duration)
    if id and dur == 0 then p.auras[id] = true end
  end
  local speed = num((call(UnitAttackSpeed, "pet")))
  if speed and speed > 0 and speed < 10 then p.speed = ("%.2f"):format(speed) end
  p.level = num((call(UnitLevel, "pet")))
  local _, fam = call(UnitCreatureFamily, "pet")
  p.family = num(fam)
  local total, used = call(api("C_PetInfo", "GetPetTrainingPoints"))
  total, used = num(total), num(used)
  if total and p.level then p.tp = p.level .. ":" .. total .. ":" .. (used or 0) end
  local foods = call(api("C_PetInfo", "GetPetFoodTypes"))
  if type(foods) == "table" then
    p.diet = {}
    for _, f in ipairs(foods) do
      f = str(f)
      if f and #f <= 40 then p.diet[#p.diet + 1] = f end
    end
  end
  return p
end

local function noteTame(w)
  watching = nil
  if ns.IsPaused() or not ns.Ready() then return end
  if w.key then recordedPets[w.key] = true end
  local p = w.best or w.last
  if not p then return end
  local rec = beastRecord(w.npc)
  local t = rec.tame or {}
  rec.tame = t
  bump(t, "n")
  local function add(field, key) if key ~= nil then t[field] = t[field] or {}; bump(t[field], key) end end
  add("lvl", w.lvl)
  local last = w.last or p
  add("plvl", last.level)
  add("fam", last.family)
  add("spd", last.speed)
  add("tp", last.tp)
  if p.n == 0 then
    bump(t, "none")
  else
    local ids = {}
    for id, pas in pairs(p.spells) do
      add("s", id)
      if pas then t.pas = t.pas or {}; t.pas[id] = true end
      ids[#ids + 1] = id
    end
    table.sort(ids)
    t.set = t.set or {}
    bumpCapped(t.set, table.concat(ids, ","), MAX_SETS)
  end
  for id in pairs(last.auras) do add("aura", id) end
  if last.diet then
    t.diet = t.diet or {}
    for _, f in ipairs(last.diet) do bumpCapped(t.diet, f, 8) end
  end
end

local function readWatched(step)
  local w = watching
  if not w then return end
  if not ns.SameUnit(str(call(UnitGUID, "pet")), w.guid) then return noteTame(w) end  -- dismissed or died: note what was seen
  local p = readPet()
  w.last = p
  if not w.best or p.n >= w.best.n then w.best = p end
  if READS[step + 1] then
    C_Timer.After(READS[step + 1] - READS[step], function() if watching == w then readWatched(step + 1) end end)
  else
    noteTame(w)
  end
end

local function tameStarted(spellID)
  if not TAME[spellID] then return end
  local kind, npc = guidId(call(UnitGUID, "target"))
  if kind ~= "Creature" or not npc then pendingTame = nil; return end
  pendingTame = { npc = npc, lvl = num((call(UnitLevel, "target"))), at = GetTime() }
end

local function petChanged()
  local t = pendingTame
  if not t or GetTime() - t.at > 60 then return end
  local guid = str(call(UnitGUID, "pet"))
  -- a pet already noted: by its GUID while GUIDs are stable (else the pending tame above is the only guard)
  local key = ns.GuidTrust.stable and guid or nil
  if not guid or (key and recordedPets[key]) then return end
  -- the new pet's GUID carries the creature id it was tamed from: it must be the beast we cast on. Without one,
  -- only a pet that arrives as the channel ends counts, so calling an old pet after a failed tame never does.
  local kind, id = guidId(guid)
  if id and (kind == "Pet" or kind == "Creature") then
    if id ~= t.npc then return end
  elseif t.failed or not t.stop or GetTime() - t.stop > 3 then
    return
  end
  pendingTame = nil
  watching = { guid = guid, key = key, npc = t.npc, lvl = t.lvl }
  local w = watching
  C_Timer.After(READS[1], function() if watching == w then readWatched(1) end end)
end

------------------------------------------------------------------------------------------------------------------
-- Beast Lore: the lines it adds to the beast's tooltip

local pendingLore      -- { guid, base, at, done }
local SKIP_TYPES = {}  -- tooltip line types that are never Beast Lore's
do
  local T = Enum and Enum.TooltipDataLineType
  if T then
    for _, k in ipairs({ "UnitName", "UnitOwner", "UnitThreat", "QuestObjective", "QuestTitle", "QuestPlayer",
        "Blank", "Separator", "UnitDead", "UnitCriteriaProgress", "UnitLevel", "UnitType" }) do
      if T[k] ~= nil then SKIP_TYPES[T[k]] = true end
    end
  end
end

-- The tooltip lines of a unit as the game gives them, or nil if any is hidden from addons (combat): then a read
-- would be partial, and is skipped.
local function unitLines(unit)
  local data = call(api("C_TooltipInfo", "GetUnit"), unit)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local out = {}
  for i, l in ipairs(data.lines) do
    if type(l) ~= "table" then return nil end
    local raw = l.leftText
    if raw ~= nil and ok(raw) == nil then return nil end
    local text = str(raw)
    if text then out[#out + 1] = { i = i, text = text, kind = ok(l.type) } end
  end
  return out
end

local function dietPattern()
  local fmt = str(_G.PET_DIET_TEMPLATE)        -- "Diet: %s"
  if not fmt then return nil end
  return "^" .. fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1"):gsub("%%%d?%$?s", ".+") .. "$"
end

local function unitFor(guid)
  for _, u in ipairs({ "target", "mouseover" }) do
    if ns.SameUnit(str(call(UnitGUID, u)), guid) then return u end
  end
end

-- What a line is: "a" names an ability, "d" the diet, "t" tameable or not, "o" anything else Beast Lore shows
local TAME_WORDS
local function kindOf(text, ids)
  if #ids > 0 then return "a" end
  local diet = dietPattern()
  if diet and text:find(diet) then return "d" end
  if not TAME_WORDS then
    TAME_WORDS = {}
    for _, g in ipairs({ "TAMEABLE", "NOT_TAMEABLE", "UNIT_TAMEABLE", "UNIT_NOT_TAMEABLE", "PET_TAMEABLE", "PET_NOT_TAMEABLE" }) do
      local w = str(_G[g])
      if w then TAME_WORDS[w] = true end
    end
  end
  if TAME_WORDS[text] then return "t" end
  return "o"
end

local function readLore(step)
  local L = pendingLore
  if not L or L.done then return end
  local unit = unitFor(L.guid)
  local lines = unit and unitLines(unit)
  local fresh = {}
  if lines then
    local name = str(call(UnitName, unit))
    local level = num((call(UnitLevel, unit)))
    for _, l in ipairs(lines) do
      local t = l.text
      local keep = l.i > 1 and not SKIP_TYPES[l.kind] and t ~= name and #t <= 120 and not ns.OwnerTitle(t) and ns.NoName(t)
      if keep and L.base then
        keep = not L.base[t]
      elseif keep then
        -- no "before" to compare with: leave out the usual lines (title, level line)
        local rec = ns.Data().npc[L.npc]
        keep = not (rec and t == rec.title) and not (l.i == 2 and level and t:find(tostring(level), 1, true))
      end
      if keep then fresh[#fresh + 1] = t end
    end
    if #fresh > 0 then
      L.done = true
      if ns.IsPaused() then return end
      local rec = beastRecord(L.npc)
      local lore = rec.lore or {}
      rec.lore = lore
      bump(lore, "n")
      if level and level > 0 then lore.lvl = lore.lvl or {}; bump(lore.lvl, level) end
      local seenIds = {}
      for _, t in ipairs(fresh) do
        local ids = spellsIn(t)
        local k = kindOf(t, ids)
        lore[k] = lore[k] or {}
        bumpCapped(lore[k], t, MAX_LINES)
        for _, id in ipairs(ids) do
          if not seenIds[id] then seenIds[id] = true; lore.s = lore.s or {}; bump(lore.s, id) end
        end
      end
      return
    end
  end
  local waits = { 0.3, 1, 2.5 }
  if waits[step + 1] then
    C_Timer.After(waits[step + 1] - waits[step], function() if pendingLore == L then readLore(step + 1) end end)
  end
end

local function loreSent()
  local guid = str(call(UnitGUID, "target"))
  local kind, npc = guidId(guid)
  if kind ~= "Creature" or not npc then pendingLore = nil; return end
  local base
  local lines = unitLines("target")
  if lines then
    base = {}
    for _, l in ipairs(lines) do base[l.text] = true end
  end
  pendingLore = { guid = guid, npc = npc, base = base, at = GetTime() }
end

local function loreCast()
  if not pendingLore or GetTime() - pendingLore.at > 5 or pendingLore.done then
    loreSent()          -- the "sent" event was missed: no "before" lines then
    if pendingLore then pendingLore.base = nil end
  end
  local L = pendingLore
  if not L then return end
  C_Timer.After(0.3, function() if pendingLore == L then readLore(1) end end)
end

------------------------------------------------------------------------------------------------------------------
-- Events

local f = CreateFrame("Frame")
local handlers = {
  UNIT_SPELLCAST_SENT = function(unit, _, _, spellID)
    if unit ~= "player" then return end
    if TAME[spellID] then tameStarted(spellID) elseif spellID == BEAST_LORE then loreSent() end
  end,
  UNIT_SPELLCAST_CHANNEL_START = function(unit, _, spellID)
    if unit == "player" and TAME[spellID] and not (pendingTame and GetTime() - pendingTame.at < 2) then tameStarted(spellID) end
  end,
  UNIT_SPELLCAST_CHANNEL_STOP = function(unit, _, spellID)
    if unit == "player" and TAME[spellID] and pendingTame then pendingTame.stop = GetTime() end
  end,
  UNIT_SPELLCAST_INTERRUPTED = function(unit, _, spellID)
    if unit == "player" and TAME[spellID] and pendingTame then pendingTame.failed = true end
  end,
  UNIT_SPELLCAST_FAILED = function(unit, _, spellID)
    if unit == "player" and TAME[spellID] and pendingTame then pendingTame.failed = true end
  end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit ~= "player" then return end
    if TAME[spellID] and not pendingTame then tameStarted(spellID)
    elseif spellID == BEAST_LORE then loreCast() end
  end,
  UNIT_PET = function(unit)
    if unit == "player" then petChanged() end
  end,
}
for event in pairs(handlers) do pcall(f.RegisterEvent, f, event) end
f:SetScript("OnEvent", function(_, event, ...)
  if not ns.Ready() or ns.IsPaused() then return end
  local okRun, err = pcall(handlers[event], ...)
  if not okRun then local h = geterrorhandler and geterrorhandler(); if h then h(err) end end
end)

-- after login: the ability names in this client's language
function ns.BeastsReady() byName = nil end

-- Totals for the window and /edb status
function ns.BeastStatus()
  local tames, lore, beasts = 0, 0, 0
  for _, rec in pairs(ns.Data().beast or {}) do
    beasts = beasts + 1
    tames = tames + (rec.tame and rec.tame.n or 0)
    lore = lore + (rec.lore and rec.lore.n or 0)
  end
  return beasts, tames, lore
end
