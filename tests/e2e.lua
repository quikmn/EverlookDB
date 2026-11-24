-- End to end, the addon's half: a scripted play session (open world, combat, loading screens, a dungeon, a
-- vendor, a trainer, a quest) through the real addon files, then the data as the game would write it to
-- SavedVariables. Everything the session did is listed in EXPECT, in the shape the site keeps it (crowd.rs
-- `Crowd`), so nothing may be lost on the way: tests/e2e.py checks the addon's data here and writes
--   collector-session.lua    the SavedVariables file
--   collector-session.json   what the site must read from it
-- and Quarry's `collector_session_end_to_end` test sends that file through the server's import.
local ROOT = ...
local ADDON = "EverlookDB"
local ns = {}

-- a fixed clock, so the file comes out the same every time
time = function() return 1795500000 + MOCK.time end
date = function(fmt, t) return os.date("!" .. fmt, t or time()) end
GetBuildInfo = function() return "1.60.1", "71037" end
GetLocale = function() return "enUS" end
UnitFactionGroup = function() return "Alliance" end
CORPSE_TOOLTIP = "Corpse of %s"
UNITNAME_TITLE_COMPANION, UNITNAME_TITLE_PET = "%s's Companion", "%s's Pet"
UNIT_SKINNABLE_LEATHER = "Skinnable"
C_UI = { Reload = function() end }
C_Item = { GetItemInfo = function(id) return "Item " .. tostring(id) end }
LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %s.", "You receive item: %sx%d."
CURRENCY_GAINED, CURRENCY_GAINED_MULTIPLE = "You receive currency: %s.", "You receive currency: %s x%d."
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
MOCK.secretsOn = false

---------------------------------------------------------------------------------------------------
-- The world

local W = { map = 1429, zone = "Elwynn Forest", x = 0.40, y = 0.60, money = 1000, units = {}, plates = {}, dist = {},
	loot = nil, fishing = false, merchant = nil, trainer = nil, quest = nil, log = {}, calls = 0 }
local function G(npc, spawn) return ("Creature-0-1-2-3-%d-%010X"):format(npc, spawn or 1) end
local function O(id, spawn) return ("GameObject-0-1-2-3-%d-%010X"):format(id, spawn or 1) end

-- A unit function: a secret token makes the game throw; a field marked secret comes back as a secret value
local function unitFn(name, field, default)
	_G[name] = function(u)
		if MOCK.isSecret(u) then error(name .. ": secret unit token") end
		local d = W.units[u]
		if u == "player" then d = W.player end
		if not d then return default end
		local v = d[field]
		if v == nil then v = default end
		if d.secret and d.secret[field] then return MOCK.Secret(v) end
		return v
	end
end
W.player = { level = 30, name = "Tester" }
unitFn("UnitGUID", "guid"); unitFn("UnitName", "name"); unitFn("UnitLevel", "level"); unitFn("UnitHealthMax", "hp")
unitFn("UnitClassification", "class"); unitFn("UnitCreatureType", "type"); unitFn("UnitCreatureFamily", "family")
unitFn("UnitIsDead", "dead", false)
UnitExists = function(u) if MOCK.isSecret(u) then error("UnitExists: secret unit token") end return W.units[u] ~= nil end
UnitIsPlayer = function(u) return u == "player" end
UnitPlayerControlled = function() return false end
UnitReaction = function(u) local d = W.units[u]; return d and d.react end
CheckInteractDistance = function(u, i)
	if MOCK.isSecret(u) then error("CheckInteractDistance: secret unit token") end
	if MOCK.combat then error("CheckInteractDistance: not in combat") end
	local d = W.dist[u] or 100
	return d <= (i == 3 and 10 or 28)
end
C_NamePlate = { GetNamePlates = function() return W.plates end }
C_Map = {
	GetBestMapForUnit = function() return W.map end,
	GetPlayerMapPosition = function() if not W.x then return nil end return { GetXY = function() return W.x, W.y end } end,
}
GetInstanceInfo = function()
	if W.inst then return W.inst.name, "party", 1, "Normal", 5, 0, false, W.inst.id end
	return W.zone, "none", 0, "", 0, 0, false, 0
end
GetRealZoneText = function() return W.inst and W.inst.name or W.zone end
C_TooltipInfo = {
	GetUnit = function(u)
		local d = W.units[u]
		if not d or (d.secret and d.secret.name) then return nil end
		local lines = { { leftText = d.name }, { leftText = d.title or ("Level " .. tostring(d.level)) } }
		if d.skinnable then lines[#lines + 1] = { leftText = "Skinnable" } end
		return { lines = lines }
	end,
	GetTrainerService = function(i) return W.trainer and W.trainer[i] and { id = W.trainer[i].spell } end,
}
-- loot window
GetNumLootItems = function() return W.loot and #W.loot or 0 end
GetLootSlotLink = function(i) local s = W.loot[i]; return s.id and ("|cffffffff|Hitem:" .. s.id .. "::::|h[Item " .. s.id .. "]|h|r") or nil end
GetLootSlotType = function(i) return W.loot[i].money and 2 or 1 end
GetLootSourceInfo = function(i) return W.loot[i].guid, W.loot[i].qty or 1 end
GetLootSlotInfo = function(i) return 1, "x", W.loot[i].qty or 1 end
IsFishingLoot = function() return W.fishing end
GetMoney = function() return W.money end
-- merchant
GetMerchantNumItems = function() return W.merchant and #W.merchant or 0 end
GetMerchantItemLink = function(i) return "|Hitem:" .. W.merchant[i].id .. ":|h[x]|h" end
C_MerchantFrame = { GetItemInfo = function(i)
	local m = W.merchant[i]
	return { price = m.price, stackCount = m.stack, numAvailable = m.avail or -1, hasExtendedCost = m.cost ~= nil }
end }
GetMerchantItemCostInfo = function(i) return W.merchant[i].cost and 1 or 0 end
GetMerchantItemCostItem = function(i) local c = W.merchant[i].cost; return 1, c.n, "|Hcurrency:" .. c.id .. "|h[c]|h", "Merchant's Favor" end
-- trainer
GetNumTrainerServices = function() return W.trainer and #W.trainer or 0 end
GetTrainerServiceInfo = function(i) return W.trainer[i].name, "", "available" end
GetTrainerServiceCost = function(i) return W.trainer[i].cost end
GetTrainerServiceLevelReq = function(i) return W.trainer[i].level end
-- quests
GetQuestID = function() return W.quest and W.quest.id or 0 end
GetTitleText = function() return W.quest.title end
GetNumQuestRewards = function() return #W.quest.reward end
GetNumQuestChoices = function() return #W.quest.choice end
GetNumQuestItems = function() return #W.quest.required end
GetQuestItemInfo = function(kind, i) local e = W.quest[kind][i]; return "x", 1, e[2], 1, true, e[1] end
GetQuestItemLink = function(kind, i) return "|Hitem:" .. W.quest[kind][i][1] .. ":|h[x]|h" end
GetRewardMoney = function() return W.quest.money end
GetNumRewardCurrencies = function() return 1 end
GetQuestCurrencyID = function() return 3402 end
GetQuestCurrencyInfo = function() return "Merchant's Favor", 1, 10 end
C_QuestLog = {
	GetNumQuestLogEntries = function() return W.inLog and 1 or 0 end,
	GetInfo = function() return W.inLog and { questID = W.quest.id, title = W.quest.title, level = 6, suggestedGroup = 0 } or nil end,
	GetLogIndexForQuestID = function() return W.inLog and 1 or nil end,
	GetQuestObjectives = function()
		return { { text = "0/8 Test Wolf slain", type = "monster", numRequired = 8 },
			{ text = W.itemLoaded and "0/4 Wolf Pelt" or "", type = "item", numRequired = 4 } }
	end,
}
GameTooltip.GetOwner = function() return UIParent end
GameTooltipTextLeft1 = { GetText = function() return W.tip end }

---------------------------------------------------------------------------------------------------
-- Load the addon as the game does, and play

EverlookDBData, EverlookDBSettings = nil, nil
local env = setmetatable({}, { __index = _G, __newindex = function(_, k, v) _G[k] = v end })
local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
for line in toc:gmatch("[^\r\n]+") do
	if not line:match("^%s*#") and line:match("%.lua%s*$") then
		local chunk = assert(loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", "")))
		setfenv(chunk, env)
		chunk(ADDON, ns)
	end
end

local realPrint = print
print = function(s) W.log[#W.log + 1] = tostring(s) end
local function tick(n) for _ = 1, n or 1 do MOCK.time = MOCK.time + 1; MOCK.RunTimers() end end
local function unit(token, npc, spawn, name, level, more)
	local d = { guid = G(npc, spawn), name = name, level = level, class = "normal", type = "Beast", hp = 100 + level, react = 2 }
	for k, v in pairs(more or {}) do d[k] = v end
	W.units[token] = d
	return d
end
local function plates(...)
	W.plates = {}
	for _, t in ipairs({ ... }) do W.plates[#W.plates + 1] = { namePlateUnitToken = t } end
end
local function loot(slots, between)
	W.loot = slots
	MOCK.Fire("LOOT_READY", true)
	if between then between() end
	MOCK.Fire("LOOT_OPENED", true)
	W.loot = nil
	MOCK.Fire("LOOT_CLOSED")
	MOCK.time = MOCK.time + 2
end
local function talk(npc, name, level, title, x, y)
	W.x, W.y = x, y
	unit("npc", npc, 1, name, level, { type = "Humanoid", react = 5, title = title })
	W.dist.npc = 3
end

MOCK.Fire("PLAYER_LOGIN")
MOCK.Fire("PLAYER_ENTERING_WORLD")
tick(2)

-- Open world. A wolf right next to you, a bandit some 20 yards off, a boar further away.
unit("nameplate1", 9001, 1, "Test Wolf", 5, { family = "Wolf", skinnable = true })
unit("nameplate2", 9002, 1, "Far Bandit", 7, { type = "Humanoid" })
unit("nameplate3", 9003, 1, "Angry Boar", 6, { family = "Boar" })
W.dist.nameplate1, W.dist.nameplate2, W.dist.nameplate3 = 5, 20, 30
plates("nameplate1", "nameplate2", "nameplate3")
tick(3)

-- Combat with the boar: the game hides names and health, and range checks are not allowed.
MOCK.combat = true
W.units.nameplate3.secret = { name = true, hp = true, level = true }
W.units.target = W.units.nameplate3
MOCK.Fire("PLAYER_TARGET_CHANGED")
MOCK.Fire("PLAYER_REGEN_DISABLED")
tick(3)
MOCK.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Angry Boar dies, you gain 85 experience.")
if not (EverlookDBData.npc[9003].pa and EverlookDBData.npc[9003].pa[1429]["400:600"] == 1) then
	error("a creature killed in a fight got no rough spot")
end
MOCK.combat = false
MOCK.Fire("PLAYER_REGEN_ENABLED")
W.units.nameplate3, W.units.target, W.dist.nameplate3 = nil, nil, nil
plates("nameplate1", "nameplate2")
tick(1)
-- its corpse: cloth (a stack of 2), a second item, and coins
loot({ { guid = G(9003), id = 2589, qty = 2 }, { guid = G(9003), id = 4306 }, { guid = G(9003), money = true } }, function() W.money = W.money + 37 end)

-- The wolf dies and is looted: one of its items is still loading when the window opens. Then it is skinned.
W.units.nameplate1 = nil
plates("nameplate2")
local slow = { guid = G(9001), id = nil }
loot({ { guid = G(9001), id = 769 }, slow }, function() slow.id = 750 end)
MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 8613)
loot({ { guid = G(9001), id = 2318 } })

-- A herb a few steps on, then fishing.
W.x, W.y = 0.42, 0.61
W.tip = "Peacebloom"
GameTooltip:GetScript("OnShow")(GameTooltip)
MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 2366)
loot({ { guid = O(1618), id = 2447 } })
W.fishing = true
loot({ { guid = O(35591, 2), id = 6291 } })
W.fishing = false

-- A vendor (one item limited, one for a currency), a trainer, and a quest from one NPC to another.
W.units.nameplate2 = nil
plates()
talk(9010, "Test Vendor", 10, "General Goods", 0.50, 0.50)
W.merchant = { { id = 159, price = 25, stack = 5 }, { id = 4540, price = 100, stack = 1, avail = 2 },
	{ id = 21000, price = 0, stack = 1, cost = { id = 3402, n = 60 } } }
MOCK.Fire("MERCHANT_SHOW")
tick(1)
MOCK.Fire("MERCHANT_CLOSED")
W.merchant = nil

talk(9011, "Test Trainer", 12, "Cooking Trainer", 0.50, 0.50)
W.trainer = { { name = "Cooking", spell = 2018, cost = 100, level = 5 } }
MOCK.Fire("TRAINER_SHOW")
tick(1)
W.trainer = nil

talk(9012, "Quest Giver", 8, nil, 0.30, 0.30)
W.quest = { id = 9500, title = "A Test of Wolves", reward = { { 6070, 1 } }, choice = { { 60, 1 }, { 61, 1 } }, required = { { 2318, 4 } }, money = 150 }
MOCK.Fire("QUEST_DETAIL")
W.inLog = true
MOCK.Fire("QUEST_ACCEPTED", 9500)  -- the item objective is still loading
W.itemLoaded = true
tick(2)
talk(9013, "Quest Taker", 9, nil, 0.31, 0.33)
MOCK.Fire("QUEST_PROGRESS")
MOCK.Fire("QUEST_COMPLETE")
tick(1)
W.inLog = false
MOCK.Fire("QUEST_TURNED_IN", 9500, 480, 150)
MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 70, 10)
MOCK.Fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:6070::::|h[Wolfskin Boots]|h|r.")
tick(5)
W.units.npc = nil

-- A loading screen into a dungeon: no zone map, no position, nameplates with secret tokens, hidden names and GUIDs.
W.inst, W.map, W.x, W.y = { id = 3039, name = "Test Stronghold" }, nil, nil, nil
MOCK.Fire("PLAYER_ENTERING_WORLD")
plates(MOCK.Secret("nameplate1"))
tick(3)
MOCK.combat = true
tick(2)
MOCK.combat = false
MOCK.Fire("PLAYER_REGEN_ENABLED")
-- a dead elite under the cursor, its GUID and name hidden; the loot window names the corpse
W.units.mouseover = { guid = G(9020), name = "Hidden Brute", level = 37, class = "elite", type = "Humanoid", dead = true, react = 2,
	secret = { guid = true, name = true, type = true, hp = true } }
MOCK.Fire("UPDATE_MOUSEOVER_UNIT")
loot({ { guid = G(9020), id = 12001 } })
-- the boss: level ??, its name readable once it is dead
W.units.mouseover = { guid = G(9021), name = "Test Boss", level = -1, class = "elite", type = "Humanoid", dead = true, react = 2, secret = { guid = true } }
loot({ { guid = G(9021), id = 12002 }, { guid = G(9021), id = 12003 } })
W.units.mouseover = nil
plates()

-- Out again, and log out.
W.inst, W.map, W.x, W.y = nil, 1429, 0.40, 0.60
MOCK.Fire("PLAYER_ENTERING_WORLD")
tick(6)
MOCK.Fire("PLAYER_LOGOUT")
print = realPrint

---------------------------------------------------------------------------------------------------
-- What all of that must have left behind, in the shape the site keeps it (crowd.rs). Every table lists every row.

local function spot(map, cell) return { [tostring(map)] = { cells = { [cell] = 1 } } } end
local EXPECT = {
	npc = {
		["9001"] = { text = { enUS = { name = "Test Wolf", type = "Beast", family = "Wolf" } }, lo = 5, hi = 5, class = "normal", skin = "leather",
			react = { Alliance = 2 }, p = spot(1429, "400:600"), z = { ["1429"] = 1 }, hp = { ["5"] = 105 }, lvl = { ["5"] = 1 } },
		["9002"] = { text = { enUS = { name = "Far Bandit", type = "Humanoid" } }, lo = 7, hi = 7, pa = spot(1429, "400:600"), z = { ["1429"] = 1 } },
		["9003"] = { text = { enUS = { name = "Angry Boar", type = "Beast", family = "Boar" } }, lo = 6, hi = 6, p = spot(1429, "400:600"),
			xp = { ["30:6"] = 85 }, hp = { ["6"] = 106 } },
		["9010"] = { text = { enUS = { name = "Test Vendor", title = "General Goods", type = "Humanoid" } }, lo = 10, hi = 10, react = { Alliance = 5 }, p = spot(1429, "500:500") },
		["9011"] = { text = { enUS = { name = "Test Trainer", title = "Cooking Trainer" } }, svc = { "train" }, p = spot(1429, "500:500") },
		["9012"] = { text = { enUS = { name = "Quest Giver" } }, lo = 8, hi = 8, p = spot(1429, "300:300") },
		["9013"] = { text = { enUS = { name = "Quest Taker" } }, lo = 9, hi = 9, p = spot(1429, "310:330") },
		["9020"] = { lo = 37, hi = 37, class = "elite", zi = { ["3039"] = 1 } },
		["9021"] = { text = { enUS = { name = "Test Boss" } }, boss = true, class = "elite", zi = { ["3039"] = 1 } },
	},
	loot = {
		["u:9003"] = { n = 1, i = { ["2589"] = { 1, 2 }, ["4306"] = { 1, 1 } }, m = 37, mn = 1 },
		["u:9001"] = { n = 1, i = { ["769"] = { 1, 1 }, ["750"] = { 1, 1 } } },
		["s:9001"] = { n = 1, i = { ["2318"] = { 1, 1 } } },
		["h:1618"] = { n = 1, i = { ["2447"] = { 1, 1 } } },
		["f:1429"] = { n = 1, i = { ["6291"] = { 1, 1 } } },
		["u:9020"] = { n = 1, i = { ["12001"] = { 1, 1 } }, zi = { ["3039"] = 1 } },
		["u:9021"] = { n = 1, i = { ["12002"] = { 1, 1 }, ["12003"] = { 1, 1 } }, zi = { ["3039"] = 1 } },
	},
	obj = {
		["1618"] = { names = { enUS = { Peacebloom = 1 } }, kind = "h", p = spot(1429, "420:610") },
	},
	vendor = {
		["9010"] = { i = { ["159"] = { price = 25, stack = 5 }, ["4540"] = { price = 100, stack = 1, limited = true },
			["21000"] = { price = 0, stack = 1, cost = "currency:3402x60" } } },
	},
	trainer = {
		["9011"] = { s = { ["2018"] = { cost = 100, level = 5 } } },
	},
	quest = {
		["9500"] = { text = { enUS = { title = "A Test of Wolves", objectives = { "monster|8|Test Wolf slain", "item|4|Wolf Pelt" } } },
			from = { ["u:9012"] = 1 }, to = { ["u:9013"] = 1 }, from_at = { ["1429:300:300"] = 1 }, to_at = { ["1429:310:330"] = 1 },
			offered_at = 30, level = 6, group = 0, reward = "6070x1", choice = "60x1,61x1", needs = "2318x4", money = 150, done = 1,
			xp = { ["30"] = 480 }, currency = "3402x10", got_n = 1, got_c = { ["3402"] = { ["10"] = 1 } }, got_i = { ["6070"] = { ["1"] = 1 } } },
	},
}

---------------------------------------------------------------------------------------------------
-- The addon's own data against EXPECT (the site-shaped view of it), then the file

local failures = {}
local function fail(msg) failures[#failures + 1] = msg end
local d = EverlookDBData
local h = d.health

-- the addon's rows as the site will see them, as far as EXPECT names fields
local function cells(p)
	local out = {}
	for map, c in pairs(p or {}) do
		local e = { cells = {} }
		for k, v in pairs(c) do if k ~= "n" then e.cells[k] = v end end
		out[tostring(map)] = e
	end
	return out
end
local function strKeys(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[tostring(k)] = strKeys(v) end
	return out
end
local function vote(v) return v and { [v] = 1 } or nil end
local VIEW = { npc = {}, loot = {}, obj = {}, vendor = {}, trainer = {}, quest = {} }
for id, r in pairs(d.npc) do
	local svc
	if r.svc then svc = {}; for k in pairs(r.svc) do svc[#svc + 1] = k end; table.sort(svc) end
	VIEW.npc[tostring(id)] = { text = { enUS = { name = r.name, title = r.title, type = r.type, family = r.family } }, lo = r.lo, hi = r.hi,
		boss = r.boss and true or nil, class = r.class, skin = r.skin, react = r.react, p = cells(r.p), pa = cells(r.pa), z = strKeys(r.z),
		zi = strKeys(r.zi), hp = strKeys(r.hp), lvl = strKeys(r.lvl), xp = r.xp, svc = svc }
end
for k, r in pairs(d.loot) do
	local items = {}
	for item, it in pairs(r.i) do items[tostring(item)] = it end
	VIEW.loot[k] = { n = r.n, i = items, m = r.m, mn = r.mn, zi = strKeys(r.zi) }
end
for id, r in pairs(d.obj) do VIEW.obj[tostring(id)] = { names = { enUS = r.name and { [r.name] = 1 } }, kind = r.kind, p = cells(r.p) } end
for id, r in pairs(d.vendor) do
	local items = {}
	for item, e in pairs(r.i) do items[tostring(item)] = { price = e.price, stack = e.stack, limited = e.limited and true or nil, cost = e.cost } end
	VIEW.vendor[tostring(id)] = { i = items }
end
for id, r in pairs(d.trainer) do
	local s = {}
	for spell, e in pairs(r.s) do s[tostring(spell)] = { cost = e.c, level = e.l } end
	VIEW.trainer[tostring(id)] = { s = s }
end
for id, q in pairs(d.quest) do
	VIEW.quest[tostring(id)] = { text = { enUS = { title = q.title, objectives = q.objectives } }, from = vote(q.from), to = vote(q.to),
		from_at = vote(q.fromAt), to_at = vote(q.toAt), offered_at = q.offeredAt, level = q.level, group = q.group, reward = q.reward,
		choice = q.choice, needs = q.needs, money = q.money, done = q.done, xp = strKeys(q.xp), currency = q.currency,
		got_n = q.got and q.got.n, got_c = q.got and strKeys(q.got.c), got_i = q.got and strKeys(q.got.i) }
end

-- every field EXPECT names must be there and equal; every table must hold exactly EXPECT's rows
local function subset(want, got, path)
	if type(want) ~= "table" then
		if want ~= got then fail(path .. ": expected " .. tostring(want) .. ", the addon has " .. tostring(got)) end
		return
	end
	if type(got) ~= "table" then fail(path .. ": missing") return end
	for k, v in pairs(want) do subset(v, got[k], path .. "." .. tostring(k)) end
end
for name, rows in pairs(EXPECT) do
	subset(rows, VIEW[name], name)
	for id in pairs(VIEW[name]) do
		if rows[id] == nil then fail(name .. "." .. id .. ": a row the session never made") end
	end
end
-- positions that must not be there: the bandit was never close, the dungeon gives no map position
if d.npc[9002].p then fail("npc.9002: an exact spot from 20 yards away") end
if d.npc[9020].name then fail("npc.9020: a hidden name was saved") end
-- nothing went wrong on the way, and the file says how complete it is
if (h.errors or 0) ~= 0 then fail("errors during the session: " .. table.concat(h.log or {}, " / ")) end
if h.notes and next(h.notes) then
	local n = {}
	for k, v in pairs(h.notes) do n[#n + 1] = k .. "=" .. v end
	fail("notes during the session: " .. table.concat(n, ", "))
end
local g = h.gaps or {}
if not (g.npcs == 9 and g.noName == 1 and g.exact == 6 and g.approx == 1 and g.inst == 2 and g.zoneOnly == 0 and g.noLoc == 0) then
	fail(("gaps: npcs %s, noName %s, exact %s, approx %s, inst %s, zoneOnly %s, noLoc %s"):format(tostring(g.npcs), tostring(g.noName),
		tostring(g.exact), tostring(g.approx), tostring(g.inst), tostring(g.zoneOnly), tostring(g.noLoc)))
end
if not (h.rec and h.rec.npc == 9 and h.rec.loot == 7 and h.rec.looted == 7 and h.rec.quest == 1 and h.rec.vendor == 1 and h.rec.trainer == 1 and h.rec.obj == 1) then
	fail("the addon's own row counts are off")
end
-- /edb status after the run names the dungeon and the open world
MOCK.log = {}
SlashCmdList.EVERLOOKDB("status")
local status = table.concat(MOCK.log, "\n")
if not status:find("Test Stronghold|r (dungeon)", 1, true) or not status:find("2 corpses and nodes looted (3 items)", 1, true) then
	fail("status doesn't show the dungeon run:\n" .. status)
end
if not status:find("Elwynn Forest", 1, true) or not status:find("No problems", 1, true) then fail("status:\n" .. status) end
-- privacy: no GUID, no player name anywhere in the data
local function hasText(t, needle)
	for k, v in pairs(t) do
		if type(k) == "string" and k:find(needle, 1, true) then return true end
		if type(v) == "string" and v:find(needle, 1, true) then return true end
		if type(v) == "table" and hasText(v, needle) then return true end
	end
	return false
end
if hasText(d, "Creature-") or hasText(d, "GameObject-") or hasText(d, "Tester") then fail("a GUID or the player's name in the data") end

-- SavedVariables as the game writes them: one value a line, list entries with their index in a comment
local function write(v, out)
	local t = type(v)
	if t == "table" then
		out[#out + 1] = "{\n"
		local n = #v
		for i = 1, n do
			write(v[i], out)
			out[#out + 1] = ", -- [" .. i .. "]\n"
		end
		local keys = {}
		for k in pairs(v) do
			if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end
		end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		for _, k in ipairs(keys) do
			out[#out + 1] = (type(k) == "number" and ("[" .. k .. "]") or ("[" .. ("%q"):format(k) .. "]")) .. " = "
			write(v[k], out)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = "}"
	elseif t == "string" then
		out[#out + 1] = ("%q"):format(v):gsub("\\\n", "\\n")
	else
		out[#out + 1] = tostring(v)
	end
end
local out = { "\nEverlookDBData = " }
write(d, out)
out[#out + 1] = "\nEverlookDBSettings = "
write(EverlookDBSettings, out)
out[#out + 1] = "\n"

-- EXPECT as JSON (objects only by string key, lists as arrays)
local function json(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 then
			local parts = {}
			for i = 1, #v do parts[i] = json(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys, parts = {}, {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do parts[#parts + 1] = ("%q"):format(k) .. ":" .. json(v[k]) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return '"' .. v:gsub('[\\"]', "\\%0") .. '"'
	end
	return tostring(v)
end

return failures, table.concat(out), json(EXPECT) .. "\n"
