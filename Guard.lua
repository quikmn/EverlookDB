-- Guard: nothing fails quietly, and you can see what was recorded where.
--   errors   every caught error is counted by kind (which API, which event, which timer) in the saved health
--            (health.errs) with a short sample of the message (health.log, the last 20 distinct ones), so
--            "errors = 168" says what went wrong. One error never stops the rest: handlers and timers run
--            through Guard.run. Messages never hold a GUID or your name.
--   tally    what was recorded lately, per zone or dungeon (EverlookDBSettings.recent, the last 12 places).
--            It lives in the settings, which are never uploaded. /edb status reads it (Report.lua).
local _, ns = ...

local G = {}
ns.Guard = G
local isSecret = issecretvalue or function() return false end

local MAX_KINDS, MAX_LOG, MAX_MSG, MAX_COUNT = 40, 20, 140, 1000000

local health            -- EverlookDBData.health, once the data is loaded
local early = {}        -- noted before that: { kind, msg, counted }
local session = { errors = 0, kinds = {} }
G.session = session

-- An error message as it is kept: no addon path, nothing GUID-shaped, no quoted text (it could be a name), short.
local function clean(msg)
  if isSecret(msg) then return "(hidden)" end
  if type(msg) ~= "string" then return type(msg) end
  msg = msg:gsub("[Ii]nterface[/\\][Aa]dd[Oo]ns[/\\]", "")
  msg = msg:gsub("%a+%-%d[%w]*%-[%w%-]+", "GUID")
  msg = msg:gsub('"[^"\n]*"', '".."')
  msg = msg:gsub("[%c]+", " ")
  if #msg > MAX_MSG then msg = msg:sub(1, MAX_MSG) end
  local hide = ns.NoName
  if hide and hide(msg) == nil then return "(hidden)" end
  return msg
end
G.Clean = clean

-- only these characters in a kind: it is a word the site shows
local function kindName(kind)
  kind = type(kind) == "string" and kind:gsub("[^%w_%.:]", "") or "other"
  if kind == "" then kind = "other" end
  return #kind > 48 and kind:sub(1, 48) or kind
end

local function addSample(h, kind, msg)
  h.log = type(h.log) == "table" and h.log or {}
  local line = kind .. " | " .. msg
  for _, l in ipairs(h.log) do if l == line then return end end
  h.log[#h.log + 1] = line
  while #h.log > MAX_LOG do table.remove(h.log, 1) end
end

local function addCount(h, kind)
  h.errors = math.min((tonumber(h.errors) or 0) + 1, MAX_COUNT)
  h.errs = type(h.errs) == "table" and h.errs or {}
  if not h.errs[kind] then
    local n = 0
    for _ in pairs(h.errs) do n = n + 1 end
    if n >= MAX_KINDS then kind = "other" end
  end
  h.errs[kind] = math.min((tonumber(h.errs[kind]) or 0) + 1, MAX_COUNT)
end

local said = false
local function say(kind)
  if said or kind:find("^api:") then return end  -- an API that says no is counted, not announced
  local s = EverlookDBSettings
  if type(s) == "table" and s.problemMessage == false then return end
  said = true
  local line = "|cffffd200EverlookDB Collector|r: something went wrong while recording (" .. kind
    .. "). It keeps recording. |cffffd200/edb status|r says more."
  if C_Timer and C_Timer.After then C_Timer.After(1, function() print(line) end) else print(line) end
end

local function seen(kind, counted)
  if not counted then return end
  session.errors = session.errors + 1
  session.kinds[kind] = (session.kinds[kind] or 0) + 1
  if ns.Tally then ns.Tally("errors") end
end

-- A sample for an error the caller has counted itself (EverlookDB.lua's safe() counts API errors by name).
function G.sample(kind, msg)
  kind, msg = kindName(kind), clean(msg)
  session.errors = session.errors + 1
  session.kinds[kind] = (session.kinds[kind] or 0) + 1
  if health then addSample(health, kind, msg) elseif #early < 50 then early[#early + 1] = { kind, msg, false } end
end

-- Count an error of this kind and keep a sample of its message.
function G.note(kind, msg)
  kind, msg = kindName(kind), clean(msg)
  seen(kind, true)
  if health then
    addCount(health, kind)
    addSample(health, kind, msg)
  elseif #early < 50 then
    early[#early + 1] = { kind, msg, true }
  end
  say(kind)
end

-- Something that isn't an error but should be seen: a count by name in health.notes (partial reads, repairs, ...).
function G.count(name, n)
  if not health then return end
  health.notes = type(health.notes) == "table" and health.notes or {}
  name = kindName(name)
  health.notes[name] = math.min((tonumber(health.notes[name]) or 0) + (n or 1), MAX_COUNT)
end

-- From now on errors go into this health table (and the ones noted before it existed).
function G.bind(h)
  health = h
  if not h then return end
  for _, e in ipairs(early) do
    if e[3] then addCount(h, e[1]) end
    addSample(h, e[1], e[2])
  end
  early = {}
end

local function pack(...) return { n = select("#", ...), ... } end

-- Run f; an error is counted under `kind` and the caller goes on. -> true, results... or false
function G.run(kind, f, ...)
  local r = pack(pcall(f, ...))
  if not r[1] then
    G.note(kind, r[2])
    return false
  end
  return true, unpack(r, 2, r.n)
end

-- f as a function that never throws (for timers and tickers)
function G.wrap(kind, f)
  return function(...) G.run(kind, f, ...) end
end

---------------------------------------------------------------------------------------------------
-- Tally: what was recorded lately, per place

local RECENT_PLACES = 12     -- places kept
local PLACE_IDS = 600        -- NPC ids kept per place
local SAME_PLACE_GAP = 1800  -- back in the same place within 30 minutes: the same visit

local cur, readAt = nil, -100

-- the zone or dungeon the player is in: key, name, dungeon?
local function readPlace()
  local safe = ns.safe
  if not safe then return nil end
  local name, itype, _, _, _, _, _, inst = safe(GetInstanceInfo)
  if type(itype) == "string" and itype ~= "none" then
    inst = type(inst) == "number" and inst or 0
    return "i" .. inst, (type(name) == "string" and name ~= "") and name or ("Dungeon " .. inst), true
  end
  local zone = GetRealZoneText and safe(GetRealZoneText)
  if type(zone) ~= "string" or zone == "" then return nil end  -- a loading screen: still the last place
  return "z" .. zone, zone, false
end

local function entry()
  local s = EverlookDBSettings
  if type(s) ~= "table" then return nil end
  local now = GetTime()
  if cur and now - readAt < 5 and s.recent and s.recent[#s.recent] == cur then return cur end
  readAt = now
  local k, name, inst = readPlace()
  local list = type(s.recent) == "table" and s.recent or {}
  s.recent = list
  local last = list[#list]
  if type(last) ~= "table" then last = nil end
  if not k then
    cur = last
    return cur
  end
  local t = time()
  if last and last.k == k and t - (tonumber(last.to) or 0) < SAME_PLACE_GAP then
    cur = last
  else
    cur = { k = k, name = name, inst = inst or nil, from = t, to = t }
    list[#list + 1] = cur
    while #list > RECENT_PLACES do table.remove(list, 1) end
  end
  if type(cur.c) ~= "table" then cur.c = {} end
  if type(cur.ids) ~= "table" then cur.ids, cur.nids = {}, 0 end
  cur.nids = tonumber(cur.nids) or 0
  return cur
end

-- Add n to the counter `what` of the place the player is in; npc: an NPC id seen there.
function ns.Tally(what, n, npc)
  local okRun, e = pcall(entry)
  if not okRun or not e then return end
  if what then
    e.c[what] = (tonumber(e.c[what]) or 0) + (n or 1)
    e.to = time()
  end
  if npc and not e.ids[npc] and e.nids < PLACE_IDS then
    e.ids[npc], e.nids = 1, e.nids + 1
    e.to = time()
  end
end

-- The player moved: read the place again at the next tally.
function ns.PlaceChanged() readAt = -100 end
