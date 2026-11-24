-- /edb status: what was recorded lately, place by place, how complete the file is, and any problems in plain
-- words. So right after a dungeon run you can see that it was captured. /edb errors lists what went wrong.
local _, ns = ...

local Care, Guard = ns.Care, ns.Guard

local SHOWN_PLACES = 4
local SHOWN_HOURS = 12

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

local function ago(t)
  local s = time() - (tonumber(t) or 0)
  if s < 120 then return "now" end
  if s < 5400 then return math.floor(s / 60 + 0.5) .. " min ago" end
  return math.floor(s / 3600 + 0.5) .. " h ago"
end

-- One visit to a zone or dungeon, as a line
local function placeLine(e, db)
  local c = type(e.c) == "table" and e.c or {}
  local n, named, exact, approx, inst, nowhere = 0, 0, 0, 0, 0, 0
  for id in pairs(type(e.ids) == "table" and e.ids or {}) do
    local rec = db.npc[id]
    if type(rec) == "table" then
      n = n + 1
      if rec.name then named = named + 1 end
      local l = Care.Located(rec)
      if l == "exact" then exact = exact + 1
      elseif l == "approx" then approx = approx + 1
      elseif l == "inst" then inst = inst + 1
      else nowhere = nowhere + 1 end
    end
  end
  local parts = {}
  if n > 0 then
    local s = plural(n, "NPC", "NPCs")
    local bits = {}
    if named < n then bits[#bits + 1] = (n - named) .. " without a name yet" end
    if e.inst then
      if nowhere > 0 then bits[#bits + 1] = nowhere .. " not placed" end
    else
      if exact > 0 then bits[#bits + 1] = exact .. " with a spot on the map" end
      if approx > 0 then bits[#bits + 1] = approx .. " with a rough spot" end
      if nowhere + inst > 0 then bits[#bits + 1] = (nowhere + inst) .. " with no spot yet" end
    end
    if #bits > 0 then s = s .. " (" .. table.concat(bits, ", ") .. ")" end
    parts[#parts + 1] = s
  end
  local function add(key, one, many)
    local v = tonumber(c[key]) or 0
    if v > 0 then parts[#parts + 1] = plural(v, one, many) end
  end
  local loot = tonumber(c.loot) or 0
  if loot > 0 then
    parts[#parts + 1] = plural(loot, "corpse or node", "corpses and nodes") .. " looted ("
      .. plural(tonumber(c.items) or 0, "item", "items") .. ")"
  end
  add("kills", "kill with XP", "kills with XP")
  add("quests", "quest taken", "quests taken")
  add("handins", "quest handed in", "quests handed in")
  add("vendors", "vendor", "vendors")
  add("trainers", "trainer", "trainers")
  add("unread", "loot window not readable (not counted)", "loot windows not readable (not counted)")
  add("errors", "error", "errors")
  if #parts == 0 then return nil end
  return ("|cffe6e8ee%s|r%s, %s: %s."):format(tostring(e.name or "?"), e.inst and " (dungeon)" or "", ago(e.to),
    table.concat(parts, ", "))
end

-- The places recorded in lately, newest first
function ns.RecentLines()
  local db, out = ns.Data(), {}
  local list = type(EverlookDBSettings) == "table" and EverlookDBSettings.recent
  if not db or type(list) ~= "table" then return out end
  for i = #list, 1, -1 do
    local e = list[i]
    if #out >= SHOWN_PLACES then break end
    if type(e) == "table" and time() - (tonumber(e.to) or 0) < SHOWN_HOURS * 3600 then
      local okRun, line = pcall(placeLine, e, db)
      if okRun and line then out[#out + 1] = line end
    end
  end
  return out
end

local function sortedCounts(t, limit)
  local keys = {}
  for k, v in pairs(t or {}) do if type(v) == "number" and v > 0 then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) if t[a] ~= t[b] then return t[a] > t[b] end return tostring(a) < tostring(b) end)
  local out = {}
  for i = 1, math.min(#keys, limit or #keys) do out[i] = keys[i] .. " x" .. t[keys[i]] end
  if limit and #keys > limit then out[#out + 1] = "..." end
  return out
end

-- Whole file: where its NPCs are
function ns.CoverageLine()
  local db = ns.Data()
  if not db then return nil end
  local g = Care.Gaps(db)
  if g.npcs == 0 then return nil end
  local s = ("Where the %d NPCs are: %d on the map, %d roughly, %d in dungeons, %d only by zone, %d nowhere yet."):format(
    g.npcs, g.exact, g.approx, g.inst, g.zoneOnly, g.noLoc)
  if g.noName > 0 then s = s .. " " .. g.noName .. (g.noName == 1 and " has" or " have") .. " no name yet." end
  return s, g
end

-- Everything that is not as it should be, in plain words; empty when all is well
function ns.Problems()
  local out = {}
  local db = ns.Data()
  if not db then return { "The data isn't loaded yet." } end
  local h = type(db.health) == "table" and db.health or {}
  if ns.IsPaused() then out[#out + 1] = "Recording is paused. /edb on records again." end
  if ns.NewerData then out[#out + 1] = "This data file was written by a newer version of the addon. Update the addon." end
  if type(h.missing) == "table" and #h.missing > 0 then
    out[#out + 1] = "The game doesn't offer " .. table.concat(h.missing, ", ") .. ": some things can't be recorded."
  end
  if h.item == "none" then out[#out + 1] = "The game gives no item info: loot can't be recorded." end
  if type(h.noEvent) == "table" and #h.noEvent > 0 then
    out[#out + 1] = "The game doesn't know these events, so what they bring isn't recorded: " .. table.concat(h.noEvent, ", ") .. "."
  end
  if ns.GuidTrust and not ns.GuidTrust.stable then
    out[#out + 1] = "The game gives changing creature IDs: counting carefully, by place and time."
  end
  local s = Guard.session
  if s.errors > 0 then
    out[#out + 1] = plural(s.errors, "error", "errors") .. " while recording since you logged in ("
      .. table.concat(sortedCounts(s.kinds, 4), ", ") .. "). The rest was recorded. /edb errors lists them."
  end
  local notes = type(h.notes) == "table" and h.notes or {}
  if (notes.lootUnread or 0) > 0 then
    out[#out + 1] = plural(notes.lootUnread, "loot window", "loot windows") .. " couldn't be read fully and "
      .. (notes.lootUnread == 1 and "was" or "were") .. " left out of the drop counts (the spot was kept)."
  end
  if (notes.repaired or 0) > 0 then
    out[#out + 1] = plural(notes.repaired, "damaged entry", "damaged entries") .. " in the data file " .. (notes.repaired == 1 and "was" or "were") .. " mended."
  end
  local size = Care.Size(db)
  if size >= Care.WARN then
    out[#out + 1] = ("The data file is about %.1f MB; uploads take up to %d MB. %s"):format(size / 1048576, Care.LIMIT / 1048576,
      (notes.compacted or 0) > 0 and "The finest position detail was thinned out to keep it small." or "It is thinned out by itself before it gets there.")
  end
  return out
end

-- /edb status, after the totals line
function ns.ReportLines()
  local out = {}
  local recent = ns.RecentLines()
  if #recent > 0 then
    out[#out + 1] = "Recorded lately:"
    for _, l in ipairs(recent) do out[#out + 1] = "  " .. l end
  else
    out[#out + 1] = "Nothing recorded since you logged in yet."
  end
  local cover = ns.CoverageLine()
  if cover then out[#out + 1] = cover end
  local st = ns.Status()
  if st.unsaved > 0 then
    out[#out + 1] = st.unsaved .. " changes are kept in memory; the game writes them when you log out or /reload (/edb save)."
  end
  local problems = ns.Problems()
  if #problems == 0 then
    out[#out + 1] = "|cff62cf88No problems.|r"
  else
    for _, p in ipairs(problems) do out[#out + 1] = "|cffef5d5dProblem:|r " .. p end
  end
  return out
end

-- /edb errors: every kind counted on this game version, and the kept samples
function ns.ErrorLines()
  local db = ns.Data()
  local h = db and type(db.health) == "table" and db.health or {}
  local out = {}
  local kinds = sortedCounts(type(h.errs) == "table" and h.errs or {})
  if #kinds == 0 and (tonumber(h.errors) or 0) == 0 then return { "No errors noted on this game version." } end
  out[#out + 1] = (tonumber(h.errors) or 0) .. " errors noted on this game version (" .. tostring(h.build or "?") .. "): " .. table.concat(kinds, ", ")
  for _, l in ipairs(type(h.log) == "table" and h.log or {}) do out[#out + 1] = "  " .. tostring(l) end
  return out
end
