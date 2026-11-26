-- Care for the data file itself: it stays loadable, in the newest shape, honest about its gaps, and small enough.
--   Repair     a damaged file (a table that became a number, a loot row without its count, a number that is not
--              finite) is mended row by row instead of breaking the addon or the whole upload
--   Migrate    numbered steps, each run once per data file (data.schema); a file written by a newer version is
--              left as it is
--   Locale     names are kept in the game's language; when that changes, the old-language texts go (the game
--              gives them again in the new one) while every count and position stays
--   Gaps       how many NPCs have no name, no position, only a rough one, ... (health.gaps)
--   Size       the size the file will have on disk, and compaction of the least useful detail long before the
--              upload limit: nothing is ever cut off in the middle
local _, ns = ...

local Care = {}
ns.Care = Care

local TABLES = { "npc", "loot", "obj", "vendor", "quest", "trainer", "beast", "got" }

local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end

---------------------------------------------------------------------------------------------------
-- Repair

-- nil out numbers that are not finite and keys that can't be saved, at any depth; -> how many
local function scrub(t, depth, seen)
  local fixed = 0
  if depth > 8 or seen[t] then return 0 end
  seen[t] = true
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "number" then
      if not finite(v) then t[k] = nil; fixed = fixed + 1 end
    elseif tv == "table" then
      fixed = fixed + scrub(v, depth + 1, seen)
    elseif tv ~= "string" and tv ~= "boolean" then
      t[k] = nil; fixed = fixed + 1  -- a function or userdata can't be saved
    end
  end
  return fixed
end

-- Mend what would break the addon or the upload. -> rows or fields mended
function Care.Repair(data)
  local fixed = 0
  for _, name in ipairs(TABLES) do
    if data[name] ~= nil and type(data[name]) ~= "table" then data[name] = nil; fixed = fixed + 1 end
    data[name] = data[name] or {}
    for k, row in pairs(data[name]) do
      if type(row) ~= "table" then data[name][k] = nil; fixed = fixed + 1 end
    end
  end
  for _, name in ipairs({ "builds", "health", "inst" }) do
    if data[name] ~= nil and type(data[name]) ~= "table" then data[name] = nil; fixed = fixed + 1 end
  end
  fixed = fixed + scrub(data, 0, {})
  -- a loot row: n looted, i = { [item] = { times, quantity } }
  for key, rec in pairs(data.loot) do
    if type(rec.i) ~= "table" then rec.i = {}; fixed = fixed + 1 end
    local most = 0
    for item, it in pairs(rec.i) do
      if type(it) ~= "table" or type(it[1]) ~= "number" or it[1] < 1 then
        rec.i[item] = nil; fixed = fixed + 1
      else
        if type(it[2]) ~= "number" or it[2] < it[1] then it[2] = it[1]; fixed = fixed + 1 end
        if it[1] > most then most = it[1] end
      end
    end
    -- without its count the site would skip the whole row: it was looted at least as often as its commonest item
    if type(rec.n) ~= "number" or rec.n < most then
      rec.n = math.max(most, type(rec.n) == "number" and rec.n or 0)
      fixed = fixed + 1
    end
    if rec.n < 1 and next(rec.i) == nil then data.loot[key] = nil end
  end
  for _, rec in pairs(data.npc) do
    for _, f in ipairs({ "p", "pa", "z", "zi", "hp", "lvl", "xp", "svc", "react" }) do
      if rec[f] ~= nil and type(rec[f]) ~= "table" then rec[f] = nil; fixed = fixed + 1 end
    end
    for _, f in ipairs({ "name", "title", "type", "family", "class", "skin" }) do
      if rec[f] ~= nil and type(rec[f]) ~= "string" then rec[f] = nil; fixed = fixed + 1 end
    end
    if rec.lo and rec.hi and (type(rec.lo) ~= "number" or type(rec.hi) ~= "number" or rec.lo > rec.hi) then
      rec.lo, rec.hi = nil, nil; fixed = fixed + 1
    end
  end
  for _, v in pairs(data.vendor) do
    if type(v.i) ~= "table" then v.i = {}; fixed = fixed + 1 end
    for item, e in pairs(v.i) do
      if type(e) ~= "table" then v.i[item] = nil; fixed = fixed + 1 end
    end
  end
  -- where an item came from: got[item] = { [way] = times }
  for item, g in pairs(data.got) do
    for way, n in pairs(g) do
      if type(way) ~= "string" or type(n) ~= "number" or n < 1 then g[way] = nil; fixed = fixed + 1 end
    end
    if next(g) == nil then data.got[item] = nil end
  end
  for _, t in pairs(data.trainer) do
    if type(t.s) ~= "table" then t.s = {}; fixed = fixed + 1 end
    for spell, e in pairs(t.s) do
      if type(e) ~= "table" then t.s[spell] = nil; fixed = fixed + 1 end
    end
  end
  -- `since` names this data file over time; without a sane one every upload would count as a new player
  if type(data.since) ~= "number" or data.since < 1000000000 or data.since > 10000000000 then
    if data.since ~= nil then fixed = fixed + 1 end
    data.since = nil
  end
  return fixed
end

---------------------------------------------------------------------------------------------------
-- Migrations: each step runs once per data file, in order. Never renumber; add at the end.

local STEPS = {
  -- 1: older versions saved each quest's objective paragraph, which can hold your character's name
  function(d) for _, q in pairs(d.quest) do q.objective = nil end end,
  -- 2: titles that name an owner ("Nimsy's Guardian") saved before 0.2.0 could name a player
  function(d)
    for _, rec in pairs(d.npc) do
      if type(rec.title) == "string" and ns.OwnerTitle(rec.title) then rec.title = nil end
    end
  end,
  -- 3: spot counts of versions before 0.4.2 were seconds spent nearby (it keeps its own mark, spotFormat)
  function(d) ns.NormalizeSpots(d) end,
  -- 4: "Level ??" was taken for a title before 0.7.0
  function(d)
    for _, rec in pairs(d.npc) do
      if type(rec.title) == "string" and ns.IsLevelLine(rec.title) then rec.title = nil end
    end
  end,
}
Care.SCHEMA = #STEPS

-- -> steps run, or nil and why when the file is from a newer version (then nothing is touched)
function Care.Migrate(data, run)
  local at = tonumber(data.schema) or 0
  if at > #STEPS then return nil, "newer" end
  local done = 0
  for i = at + 1, #STEPS do
    -- a step that fails is tried again at the next login; the later ones wait for it
    local okRun = run("migrate:" .. i, STEPS[i], data)
    if not okRun then break end
    data.schema = i
    done = done + 1
  end
  return done
end

---------------------------------------------------------------------------------------------------
-- The game's language changed: texts in the old language would be filed under the new one on the site.

function Care.LocaleChanged(data, locale)
  local was = data.locale
  if type(was) ~= "string" or was == locale then return false end
  for _, rec in pairs(data.npc) do rec.name, rec.title, rec.type, rec.family = nil, nil, nil, nil end
  for _, rec in pairs(data.obj) do rec.name = nil end
  for _, q in pairs(data.quest) do q.title, q.objectives = nil, nil end
  for _, t in pairs(data.trainer) do
    for key in pairs(t.s) do
      if type(key) == "string" then t.s[key] = nil end  -- spells kept by name, when the game gave no id
    end
  end
  return true
end

---------------------------------------------------------------------------------------------------
-- Gaps

-- Where an NPC is known to be: "exact" (a spot on a zone map), "approx" (a rough spot), "inst" (a dungeon),
-- "zone" (only which zone), or nil
local function hasCell(p)
  if type(p) ~= "table" then return false end
  for _, cells in pairs(p) do
    if type(cells) == "table" then
      for k in pairs(cells) do if k ~= "n" then return true end end
    end
  end
  return false
end
function Care.Located(rec)
  if hasCell(rec.p) then return "exact" end
  if hasCell(rec.pa) then return "approx" end
  if (type(rec.zi) == "table" and next(rec.zi)) or (type(rec.p) == "table" and next(rec.p)) then return "inst" end
  if type(rec.z) == "table" and next(rec.z) then return "zone" end
  return nil
end

-- Counts only: how complete the file is. Saved as health.gaps.
function Care.Gaps(data)
  local g = { npcs = 0, noName = 0, noLevel = 0, exact = 0, approx = 0, inst = 0, zoneOnly = 0, noLoc = 0,
    loot = 0, lootNoName = 0, objs = 0, objNoName = 0, quests = 0, questNoGiver = 0, questNoTitle = 0,
    vendors = 0, vendorNoSpot = 0 }
  for _, rec in pairs(data.npc or {}) do
    g.npcs = g.npcs + 1
    if not rec.name then g.noName = g.noName + 1 end
    if not rec.lo and not rec.boss then g.noLevel = g.noLevel + 1 end
    local l = Care.Located(rec)
    if l == "exact" then g.exact = g.exact + 1
    elseif l == "approx" then g.approx = g.approx + 1
    elseif l == "inst" then g.inst = g.inst + 1
    elseif l == "zone" then g.zoneOnly = g.zoneOnly + 1
    else g.noLoc = g.noLoc + 1 end
  end
  for key in pairs(data.loot or {}) do
    g.loot = g.loot + 1
    local kind, id = tostring(key):match("^([usp]):(%d+)$")
    if kind then
      local rec = data.npc and data.npc[tonumber(id)]
      if not rec or not rec.name then g.lootNoName = g.lootNoName + 1 end
    end
  end
  for _, rec in pairs(data.obj or {}) do
    g.objs = g.objs + 1
    if not rec.name then g.objNoName = g.objNoName + 1 end
  end
  for _, q in pairs(data.quest or {}) do
    g.quests = g.quests + 1
    if not q.from then g.questNoGiver = g.questNoGiver + 1 end
    if not q.title then g.questNoTitle = g.questNoTitle + 1 end
  end
  for id in pairs(data.vendor or {}) do
    g.vendors = g.vendors + 1
    local rec = data.npc and data.npc[id]
    if not rec or Care.Located(rec) ~= "exact" then g.vendorNoSpot = g.vendorNoSpot + 1 end
  end
  return g
end

---------------------------------------------------------------------------------------------------
-- Size. The game writes one line per value: ["key"] = value, and the site and the app take files up to 5 MB.

Care.LIMIT = 5 * 1024 * 1024
Care.WARN = 3.5 * 1024 * 1024     -- /edb status and the site say so
Care.COMPACT = 4.2 * 1024 * 1024  -- compaction starts
Care.TARGET = 3.8 * 1024 * 1024   -- and stops below this

local function sizeOf(v, depth)
  local tv = type(v)
  if tv == "string" then return #v + 2 end
  if tv == "number" then return #tostring(v) end
  if tv == "boolean" then return v and 4 or 5 end
  if tv ~= "table" or depth > 12 then return 3 end
  local n = 4  -- {, }, line ends
  for k, x in pairs(v) do
    -- ["key"] = value,\r\n  or  [12] = value,\r\n
    n = n + (type(k) == "string" and #k + 4 or #tostring(k) + 2) + 3 + sizeOf(x, depth + 1) + 3
  end
  return n
end

-- About the bytes the data file will have on disk
function Care.Size(data) return sizeOf(data, 0) + 20 end

-- Merge a map's spot cells onto a grid twice as coarse (the counts add up): half the detail, nothing forgotten
local function coarsen(cells, grid)
  local out, n = { n = 0 }, 0
  local unknown = tonumber(cells.n) or 0
  for k, v in pairs(cells) do
    if k ~= "n" then
      unknown = unknown - 1
      local x, y = tostring(k):match("^(%d+):(%d+)$")
      if x then
        local key = math.floor(x / grid) * grid .. ":" .. math.floor(y / grid) * grid
        if not out[key] then n = n + 1 end
        out[key] = (out[key] or 0) + (tonumber(v) or 1)
      end
    end
  end
  out.n = n + math.max(unknown, 0)
  return out, n
end

-- Each stage gives up the least useful detail left. -> true when something changed
local STAGES = {
  -- 1: a zone listed under z that also has spots under p says nothing new
  function(d)
    local did = false
    for _, rec in pairs(d.npc) do
      if type(rec.z) == "table" and type(rec.p) == "table" then
        for map in pairs(rec.z) do
          if rec.p[map] then rec.z[map] = nil; did = true end
        end
        if next(rec.z) == nil then rec.z = nil end
      end
    end
    return did
  end,
  -- 2: NPCs and nodes with many spots on one map: a 1% grid instead of 0.5%
  function(d)
    local did = false
    for _, name in ipairs({ "npc", "obj" }) do
      for _, rec in pairs(d[name]) do
        for _, f in ipairs({ "p", "pa" }) do
          for map, cells in pairs(type(rec[f]) == "table" and rec[f] or {}) do
            local count = 0
            if type(cells) == "table" then for _ in pairs(cells) do count = count + 1 end end
            if count > 25 then rec[f][map] = coarsen(cells, 10); did = true end
          end
        end
      end
    end
    return did
  end,
  -- 3: health per level: the lowest and highest level seen are kept
  function(d)
    local did = false
    for _, rec in pairs(d.npc) do
      if type(rec.hp) == "table" then
        for lvl in pairs(rec.hp) do
          if lvl ~= rec.lo and lvl ~= rec.hi then rec.hp[lvl] = nil; did = true end
        end
      end
    end
    return did
  end,
  -- 4: every map with more than a dozen spots: a 2% grid
  function(d)
    local did = false
    for _, name in ipairs({ "npc", "obj" }) do
      for _, rec in pairs(d[name]) do
        for map, cells in pairs(type(rec.p) == "table" and rec.p or {}) do
          local count = 0
          if type(cells) == "table" then for _ in pairs(cells) do count = count + 1 end end
          if count > 12 then rec.p[map] = coarsen(cells, 20); did = true end
        end
      end
    end
    return did
  end,
  -- 5: items that arrived with nothing to explain them: the zone they arrived in goes
  function(d)
    local did = false
    for _, g in pairs(type(d.got) == "table" and d.got or {}) do
      for way in pairs(g) do
        if tostring(way):find("^%?:") then g[way] = nil; did = true end
      end
    end
    return did
  end,
}

-- Keep the file under the upload limit. -> size now, stages run (0 when it was small enough)
function Care.Compact(data, compactAt, target)
  local size = Care.Size(data)
  if size < (compactAt or Care.COMPACT) then return size, 0 end
  local ran = 0
  for _, stage in ipairs(STAGES) do
    if stage(data) then ran = ran + 1 end
    size = Care.Size(data)
    if size < (target or Care.TARGET) then break end
  end
  return size, ran
end
