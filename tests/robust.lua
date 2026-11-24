---------------------------------------------------------------------------------------------------
-- Robustness: nothing is lost for one bad value, nothing fails quietly (Guard.lua, Care.lua, Report.lua).
-- Each step is a way data was, or could be, lost.

local function freshHealth()
	local h = EverlookDBData.health
	h.errors, h.errs, h.log, h.notes = 0, nil, nil, nil
	return h
end
local function lootWorld(slots)
	-- slots: { { guid = , id = (nil while loading), type = 1 item / 2 money, qty = } }
	stub("GetNumLootItems", function() return #slots end)
	stub("GetLootSlotLink", function(i) return slots[i].id and ("|Hitem:" .. slots[i].id .. ":|h[x]|h") or nil end)
	stub("GetLootSlotType", function(i) return slots[i].type or 1 end)
	stub("GetLootSourceInfo", function(i) return slots[i].guid, slots[i].qty or 1 end)
	stub("IsFishingLoot", function() return false end)
	stub("GetMoney", function() return 0 end)
end

step("errors: a handler that throws is counted by its event, with a sample that names no GUID and no player", function()
	local h = freshHealth()
	local before = ns.Guard.session.errors
	stub("UnitLevel", function() error('no level for "Tester" Creature-0-1-2-3-99-0000AB0001') end)
	MOCK.Fire("QUEST_TURNED_IN", 95900, 100, 0)
	check(h.errors == 1 and h.errs["event:QUEST_TURNED_IN"] == 1, "not counted by its event: " .. tostring(h.errors))
	check(h.log and #h.log == 1 and h.log[1]:find("event:QUEST_TURNED_IN | ", 1, true), "no sample")
	check(not hasText(h, "Creature-") and not hasText(h, "Tester"), "a GUID or the player's name in the health: " .. h.log[1])
	check(ns.Guard.session.errors == before + 1, "not counted for this session")
	-- the same error again: counted, but not a second sample
	MOCK.Fire("QUEST_TURNED_IN", 95900, 100, 0)
	check(h.errors == 2 and #h.log == 1, "the same sample twice")
	unstubAll()
	-- and the next event is handled as ever
	MOCK.Fire("QUEST_TURNED_IN", 95900, 100, 0)
	check(EverlookDBData.quest[95900].done >= 1, "the next hand-in was not recorded")
	MOCK.RunTimers()
	MOCK.log = {}
	SlashCmdList.EVERLOOKDB("errors")
	check(table.concat(MOCK.log, " "):find("event:QUEST_TURNED_IN x2", 1, true), "/edb errors: " .. table.concat(MOCK.log, " / "))
	check(table.concat(ns.Problems(), " "):find("while recording since you logged in", 1, true), "status doesn't say so")
end)

step("errors: the once-a-second scan goes on after one tick failed; kinds and samples stay bounded", function()
	local h = freshHealth()
	stub("C_NamePlate", { GetNamePlates = function() error("plates are gone") end })
	tick(2)
	check(h.errs.tick == 2, "tick errors: " .. tostring(h.errs.tick))
	check(#MOCK.tickers == 1, "more than one scan ticker after several logins: " .. #MOCK.tickers)
	unstubAll()
	nearWorld({ "Creature-0-1-2-3-4101-0000AC0001" })
	EverlookDBData.npc[4101] = nil
	tick(1)
	check(EverlookDBData.npc[4101] and EverlookDBData.npc[4101].name == "Kobold Vermin", "the scan stopped")
	unstubAll()
	for i = 1, 100 do ns.Guard.note("kind" .. i, "message " .. i) end
	local kinds = 0
	for _ in pairs(h.errs) do kinds = kinds + 1 end
	check(kinds <= 41 and h.errs.other and #h.log == 20, "unbounded: " .. kinds .. " kinds, " .. #h.log .. " samples")
	check(h.errors == 102, "total: " .. h.errors)
	freshHealth()
end)

step("loot: hidden money when the window closes never blocks the next loot window", function()
	resetTrust()
	lootWorld({ { guid = "Creature-0-1-2-3-4110-0000AD0001", id = 2589 } })
	MOCK.Fire("LOOT_READY")
	stub("GetMoney", function() return MOCK.Secret(50) end)
	MOCK.Fire("LOOT_CLOSED")
	unstubAll()
	lootWorld({ { guid = "Creature-0-1-2-3-4110-0000AD0002", id = 2589 } })
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_OPENED"); MOCK.Fire("LOOT_CLOSED")
	check(EverlookDBData.loot["u:4110"].n == 2, "the second corpse was not counted: " .. EverlookDBData.loot["u:4110"].n)
	unstubAll()
end)

step("loot: a LOOT_CLOSED that never came doesn't swallow the next corpse", function()
	resetTrust()
	lootWorld({ { guid = "Creature-0-1-2-3-4111-0000AD0003", id = 2589 } })
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_OPENED")
	unstubAll()
	lootWorld({ { guid = "Creature-0-1-2-3-4111-0000AD0004", id = 2592 } })
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_OPENED"); MOCK.Fire("LOOT_CLOSED")
	local l = EverlookDBData.loot["u:4111"]
	check(l.n == 2 and l.i[2589][1] == 1 and l.i[2592][1] == 1, "corpses counted: " .. l.n)
	unstubAll()
end)

step("loot: an item still loading is waited for, then the corpse counts once with all its items", function()
	resetTrust()
	local slots = { { guid = "Creature-0-1-2-3-4112-0000AD0005", id = 2589 }, { guid = "Creature-0-1-2-3-4112-0000AD0005", id = nil } }
	lootWorld(slots)
	MOCK.Fire("LOOT_READY")
	check(EverlookDBData.loot["u:4112"] == nil, "counted before it could be read")
	slots[2].id = 4306
	MOCK.Fire("LOOT_OPENED")
	local l = EverlookDBData.loot["u:4112"]
	check(l and l.n == 1 and l.i[2589] and l.i[4306], "not counted in full")
	MOCK.RunTimers(); MOCK.RunTimers()
	MOCK.Fire("LOOT_CLOSED")
	check(l.n == 1 and l.i[4306][1] == 1, "counted twice: " .. l.n)
	unstubAll()
end)

step("loot: a window that closes with an item unread is left out of the drop counts; its spot is kept and it is said", function()
	resetTrust()
	local h = freshHealth()
	lootWorld({ { guid = "Creature-0-1-2-3-4113-0000AD0006", id = 2589 }, { guid = "Creature-0-1-2-3-4113-0000AD0006", id = nil } })
	stub("C_Map", { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.3, 0.3 end } end })
	EverlookDBData.npc[4113] = nil
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_OPENED"); MOCK.Fire("LOOT_CLOSED")
	check(EverlookDBData.loot["u:4113"] == nil, "a corpse with an unread item was counted (its item would look rarer)")
	check(h.notes and h.notes.lootUnread == 1, "not noted")
	local n = EverlookDBData.npc[4113]
	check(n and n.p and n.p[1429] and n.p[1429]["300:300"] == 1, "the corpse's spot was lost")
	check(table.concat(ns.Problems(), " "):find("1 loot window couldn't be read fully", 1, true), "status doesn't say so")
	-- coins have no item link and are no reason to wait
	unstubAll()
	lootWorld({ { guid = "Creature-0-1-2-3-4114-0000AD0007", id = 2589 }, { guid = "Creature-0-1-2-3-4114-0000AD0007", type = 2 } })
	MOCK.Fire("LOOT_READY")
	check(EverlookDBData.loot["u:4114"] and EverlookDBData.loot["u:4114"].n == 1, "a coin slot held the corpse back")
	MOCK.Fire("LOOT_CLOSED")
	unstubAll()
	freshHealth()
end)

step("loot: quantities the game hides count as one; a source it hides is not guessed", function()
	resetTrust()
	lootWorld({ { guid = "Creature-0-1-2-3-4115-0000AD0008", id = 2589 } })
	stub("GetLootSourceInfo", function() return "Creature-0-1-2-3-4115-0000AD0008", MOCK.Secret(3) end)
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_CLOSED")
	local l = EverlookDBData.loot["u:4115"]
	check(l and l.n == 1 and l.i[2589][2] == 1, "hidden quantity")
	unstubAll()
	-- a source the game hides: the window is left out and said
	local h = freshHealth()
	lootWorld({ { guid = "Creature-0-1-2-3-4116-0000AD0009", id = 2589 } })
	stub("GetLootSourceInfo", function() return MOCK.Secret("Creature-0-1-2-3-4116-0000AD0009"), 1 end)
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_CLOSED")
	check(EverlookDBData.loot["u:4116"] == nil and h.notes and h.notes.lootUnread == 1, "a hidden source")
	unstubAll()
	-- a clam or lockbox opened from the bags (its source is an item), or loot the game names no source for: not
	-- ours to count, and nothing to report or wait for
	MOCK.RunTimers(); MOCK.RunTimers()
	h = freshHealth()
	lootWorld({ { guid = "Item-1-0-4000000ABCDEF123", id = 5498 }, { guid = "Item-1-0-4000000ABCDEF123", id = nil } })
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_OPENED"); MOCK.Fire("LOOT_CLOSED")
	lootWorld({ { id = 5498 } })
	stub("GetLootSourceInfo", function() return end)
	MOCK.time = MOCK.time + 5
	MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_OPENED"); MOCK.Fire("LOOT_CLOSED")
	check(h.notes == nil and #MOCK.timers == 0, "opening a clam was reported as an unreadable loot window")
	unstubAll()
	freshHealth()
end)

step("loading screens: a merchant window or loot window left open by one doesn't stay open for the addon", function()
	stub("UnitGUID", function(u) if u == "npc" then return "Creature-0-1-2-3-4120-0000AE0001" end end)
	stub("UnitExists", function() return false end)
	stub("GetMerchantNumItems", function() return 0 end)
	stub("UnitReaction", function() return 5 end)
	MOCK.Fire("MERCHANT_SHOW")
	unstubAll()
	MOCK.Fire("PLAYER_ENTERING_WORLD")  -- no MERCHANT_CLOSED came
	stub("UnitLevel", function() return 30 end)
	MOCK.Fire("QUEST_TURNED_IN", 95901, 100, 0)
	MOCK.Fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:159:|h[Refreshing Spring Water]|h|r.")
	MOCK.RunTimers()
	local q = EverlookDBData.quest[95901]
	check(q and q.got and q.got.i and q.got.i[159], "a reward item was taken for a purchase")
	unstubAll()
end)

step("vendor: a value the game hides this time keeps what was saved, and throws nothing", function()
	local h = freshHealth()
	stub("UnitGUID", function(u) if u == "npc" then return "Creature-0-1-2-3-4121-0000AE0002" end end)
	stub("UnitExists", function() return false end)
	stub("UnitReaction", function() return 5 end)
	stub("GetMerchantNumItems", function() return 2 end)
	stub("GetMerchantItemLink", function(slot) return "|Hitem:" .. (200 + slot) .. ":|h[x]|h" end)
	stub("C_MerchantFrame", { GetItemInfo = function() return { price = 120, stackCount = 5, numAvailable = 2, hasExtendedCost = false } end })
	MOCK.Fire("MERCHANT_SHOW")
	MOCK.Fire("MERCHANT_CLOSED")
	stub("C_MerchantFrame", { GetItemInfo = function(slot)
		if slot == 1 then return { price = MOCK.Secret(120), stackCount = MOCK.Secret(5), numAvailable = MOCK.Secret(2), hasExtendedCost = MOCK.Secret(false) } end
		return { price = 130, stackCount = 5, numAvailable = -1, hasExtendedCost = false }
	end })
	stub("UnitReaction", function() return MOCK.Secret(5) end)
	MOCK.Fire("MERCHANT_SHOW")
	MOCK.Fire("MERCHANT_CLOSED")
	local v = EverlookDBData.vendor[4121]
	check(h.errors == 0, "it threw: " .. table.concat(h.log or {}, " / "))
	check(v.i[201].price == 120 and v.i[201].stack == 5 and v.i[201].limited == 1 and v.i[201].react == 5, "a hidden value wiped a saved one")
	check(v.i[202].price == 130 and v.i[202].limited == nil, "the readable line was not updated")
	unstubAll()
end)

step("vendor: items that never load are tried three times, then said", function()
	local h = freshHealth()
	local reads = 0
	stub("UnitGUID", function(u) if u == "npc" then return "Creature-0-1-2-3-4122-0000AE0003" end end)
	stub("UnitExists", function() return false end)
	stub("UnitReaction", function() return 5 end)
	stub("GetMerchantNumItems", function() reads = reads + 1; return 2 end)
	stub("GetMerchantItemLink", function(slot) if slot == 1 then return "|Hitem:301:|h[x]|h" end end)
	stub("C_MerchantFrame", { GetItemInfo = function() return { price = 1, stackCount = 1, numAvailable = -1 } end })
	MOCK.Fire("MERCHANT_SHOW")
	runTimers(5)
	check(reads == 3, "reads: " .. reads)
	check(EverlookDBData.vendor[4122].i[301] and h.notes and h.notes.vendorItemsUnread == 1, "not noted")
	MOCK.Fire("MERCHANT_CLOSED")
	unstubAll()
	freshHealth()
end)

step("trainer: a cost the game hides this time keeps the saved one", function()
	stub("UnitGUID", function(u) if u == "npc" then return "Creature-0-1-2-3-4123-0000AE0004" end end)
	stub("UnitExists", function() return false end)
	stub("GetNumTrainerServices", function() return 1 end)
	stub("GetTrainerServiceInfo", function() return "Fireball", "Rank 2", "available" end)
	stub("GetTrainerServiceCost", function() return 100 end)
	stub("GetTrainerServiceLevelReq", function() return 6 end)
	MOCK.Fire("TRAINER_SHOW"); MOCK.RunTimers()
	stub("GetTrainerServiceCost", function() return MOCK.Secret(100) end)
	stub("GetTrainerServiceLevelReq", function() return nil end)
	MOCK.Fire("TRAINER_SHOW"); MOCK.RunTimers()
	local e = EverlookDBData.trainer[4123].s["Fireball (Rank 2)"]
	check(e and e.c == 100 and e.l == 6, "trainer line wiped: " .. tostring(e and e.c))
	unstubAll()
end)

step("quests: objectives never read in full are read from the quest log after a loading screen", function()
	-- saved by an older version while the item was loading, and a quest taken while the addon wasn't looking
	EverlookDBData.quest[95910] = { title = "Bounty", objectives = { "item|1|" } }
	EverlookDBData.quest[95911] = nil
	EverlookDBData.quest[95912] = { title = "Complete", objectives = { "monster|8|Kobold Vermin slain" } }
	local asked = {}
	stub("C_QuestLog", {
		GetNumQuestLogEntries = function() return 4 end,
		GetInfo = function(i)
			return ({ { isHeader = true, title = "Elwynn" }, { questID = 95910, title = "Bounty", level = 5, suggestedGroup = 0 },
				{ questID = 95911, title = "Taken unseen", level = 6, suggestedGroup = 0 }, { questID = 95912, title = "Complete", level = 2 } })[i]
		end,
		GetLogIndexForQuestID = function(q) return ({ [95910] = 2, [95911] = 3, [95912] = 4 })[q] end,
		GetQuestObjectives = function(q)
			asked[q] = (asked[q] or 0) + 1
			if q == 95910 then return { { text = "0/1 Garrick's Head", type = "item", numRequired = 1 } } end
			if q == 95911 then return { { text = "0/6 Wolf Pelt", type = "item", numRequired = 6 } } end
			return { { text = "0/8 Kobold Vermin slain", type = "monster", numRequired = 8 } }
		end,
	})
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	MOCK.RunTimers()
	check(EverlookDBData.quest[95910].objectives[1] == "item|1|Garrick's Head", "not filled in: " .. tostring(EverlookDBData.quest[95910].objectives[1]))
	local q = EverlookDBData.quest[95911]
	check(q and q.title == "Taken unseen" and q.objectives[1] == "item|6|Wolf Pelt", "a quest taken unseen was not read")
	check(not asked[95912], "a complete quest was read again")
	MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
	check(asked[95910] == 1, "read again in the same session")
	unstubAll()
end)

step("quests: a half-loaded list replaces only a list that says less; three more looks while one is loading", function()
	local loading, looks = true, 0
	stub("C_QuestLog", {
		GetLogIndexForQuestID = function() return 1 end,
		GetInfo = function() return { title = "Two Things", level = 10, suggestedGroup = MOCK.Secret(0) } end,
		GetQuestObjectives = function()
			looks = looks + 1
			return { { text = "0/4 Boars slain", type = "monster", numRequired = 4 }, { text = loading and "" or "0/2 Tusk", type = "item", numRequired = 2 } }
		end,
	})
	EverlookDBData.quest[95913] = { objectives = { "item|2|" } }
	MOCK.Fire("QUEST_ACCEPTED", 95913)
	local q = EverlookDBData.quest[95913]
	check(#q.objectives == 1 and q.objectives[1] == "monster|4|Boars slain", "a list that says more did not replace one that says nothing")
	check(q.level == 10 and q.group == nil, "a hidden group size was saved")
	runTimers(6)
	check(looks == 4, "looks: " .. looks)
	loading = false
	MOCK.Fire("QUEST_ACCEPTED", 95913)
	check(#q.objectives == 2 and q.objectives[2] == "item|2|Tusk", "the full list")
	unstubAll()
end)

step("data file: damaged rows are mended at login instead of breaking the addon or the upload", function()
	local d = EverlookDBData
	d.npc[4130] = 7                                           -- a row that became a number
	d.npc[4131] = { name = "Fine", p = "broken", lo = 9, hi = 3, hp = { [5] = math.huge } }
	d.loot["u:4132"] = { i = { [2589] = { 3, 2 }, [4306] = "x" } }  -- no count; an item row that isn't one
	d.vendor[4133] = "nope"
	d.trainer[4134] = { s = 5 }
	d.schema = nil
	freshHealth()
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	local h = d.health
	check((h.errors or 0) == 0, "login threw: " .. table.concat(h.log or {}, " / "))
	check(d.npc[4130] == nil and d.npc[4131].name == "Fine" and d.npc[4131].p == nil and d.npc[4131].lo == nil, "npc rows")
	check(d.npc[4131].hp[5] == nil, "a number that isn't finite was kept")
	local l = d.loot["u:4132"]
	check(l.n == 3 and l.i[2589][2] == 3 and l.i[4306] == nil, "loot row: n " .. tostring(l.n))
	check(d.vendor[4133] == nil and type(d.trainer[4134].s) == "table", "vendor / trainer")
	check(h.notes and h.notes.repaired and h.notes.repaired >= 6, "not said: " .. tostring(h.notes and h.notes.repaired))
	check(d.schema == ns.Care.SCHEMA, "migrations did not run: " .. tostring(d.schema))
	-- the whole data not being a table at all
	local keep = EverlookDBData
	EverlookDBData = "corrupt"
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	check(type(EverlookDBData) == "table" and type(EverlookDBData.npc) == "table" and EverlookDBData.since, "no fresh data")
	SlashCmdList.EVERLOOKDB("status")
	EverlookDBData = keep
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	check(ns.Data() == keep, "data not back")
	d.loot["u:4132"], d.npc[4131], d.trainer[4134] = nil, nil, nil
end)

step("login: a step that fails is counted and the rest still runs", function()
	local real = ns.HealthCheck
	ns.HealthCheck = function() error("health is broken") end
	EverlookDBData.health = nil
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	ns.HealthCheck = real
	local h = EverlookDBData.health
	check(h and h.errs and h.errs["init:health"] == 1, "not counted")
	check(ns.Ready() and EverlookDBSettings and not ns.IsPaused(), "login did not finish")
	nearWorld({ "Creature-0-1-2-3-4140-0000AF0001" })
	EverlookDBData.npc[4140] = nil
	tick(1)
	check(EverlookDBData.npc[4140], "recording stopped")
	unstubAll()
	EverlookDBData.health = nil
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
end)

step("data file from a newer addon version is left as it is, and status says so", function()
	EverlookDBData.schema = 99
	EverlookDBData.quest[95920] = { objective = "kept as the newer version wrote it" }
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	check(EverlookDBData.schema == 99 and EverlookDBData.quest[95920].objective, "a newer file was migrated")
	check(table.concat(ns.Problems(), " "):find("newer version", 1, true), "status doesn't say so")
	EverlookDBData.schema, EverlookDBData.quest[95920] = ns.Care.SCHEMA, nil
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	check(not table.concat(ns.Problems(), " "):find("newer version", 1, true), "still says newer")
end)

step("game language changed: names in the old language go, every count and position stays", function()
	local d = EverlookDBData
	d.npc[4150] = { name = "Kobold", type = "Humanoid", lo = 3, hi = 4, p = { [1429] = { n = 1, ["400:600"] = 1 } } }
	d.quest[95921] = { title = "Kobold Camp Cleanup", objectives = { "monster|8|Kobold slain" }, from = "u:4150", done = 1 }
	d.obj[4151] = { name = "Copper Vein", kind = "m" }
	d.trainer[4152] = { s = { ["Fireball (Rank 2)"] = { c = 100 }, [143] = { c = 100 } } }
	d.loot["u:4150"] = { n = 5, i = { [2589] = { 2, 3 } } }
	stub("GetLocale", function() return "deDE" end)
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	check(d.locale == "deDE" and d.npc[4150].name == nil and d.npc[4150].type == nil, "old-language name kept")
	check(d.npc[4150].lo == 3 and d.npc[4150].p[1429]["400:600"] == 1 and d.loot["u:4150"].n == 5, "counts or spots lost")
	check(d.quest[95921].title == nil and d.quest[95921].objectives == nil and d.quest[95921].from == "u:4150" and d.quest[95921].done == 1, "quest")
	check(d.obj[4151].name == nil and d.obj[4151].kind == "m", "object")
	check(d.trainer[4152].s["Fireball (Rank 2)"] == nil and d.trainer[4152].s[143], "trainer spells by name")
	check(d.health.notes and d.health.notes.localeChanged == 1, "not noted")
	unstubAll()
	MOCK.Fire("PLAYER_LOGIN"); MOCK.RunTimers()
	check(d.locale == "enUS", "locale back")
	d.npc[4150], d.quest[95921], d.obj[4151], d.trainer[4152], d.loot["u:4150"] = nil, nil, nil, nil, nil
end)

step("logout: a hand-in still being watched is finished; gaps, counts and size go into the health", function()
	local d = EverlookDBData
	stub("UnitLevel", function() return 30 end)
	MOCK.Fire("QUEST_TURNED_IN", 95930, 100, 0)
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 50, 10)
	d.npc[4160] = { name = "Placed", lo = 1, hi = 1, p = { [1429] = { n = 1, ["400:600"] = 1 } } }
	d.npc[4161] = { name = "Roughly", lo = 1, hi = 1, pa = { [1429] = { n = 1, ["400:600"] = 1 } } }
	d.npc[4162] = { zi = { [3039] = 1 } }
	d.npc[4163] = { name = "Zone only", lo = 1, hi = 1, z = { [1429] = 1 } }
	d.npc[4164] = { name = "Nowhere", lo = 1, hi = 1 }
	local before = ns.Care.Gaps(d)
	MOCK.Fire("PLAYER_LOGOUT")
	unstubAll()
	local q = d.quest[95930]
	check(q.got and q.got.n == 1 and q.got.c[3402][10] == 1, "the hand-in's gains were lost at logout")
	local h = d.health
	local g = h.gaps
	check(g and g.npcs == before.npcs and g.exact == before.exact and g.noName == before.noName, "gaps")
	check(g.exact >= 1 and g.approx >= 1 and g.inst >= 1 and g.zoneOnly >= 1 and g.noLoc >= 1 and g.noName >= 1, "every kind of place counted")
	local npcs = 0
	for _ in pairs(d.npc) do npcs = npcs + 1 end
	check(h.rec and h.rec.npc == npcs and h.rec.loot > 0 and h.rec.looted >= h.rec.loot, "the addon's own counts")
	check(type(h.bytes) == "number" and h.bytes > 1000, "size")
	check(not hasText(h, "Creature-") and not hasText(h, "Tester"), "a GUID or name in the health")
	for i = 4160, 4164 do d.npc[i] = nil end
end)

step("size: a file near the upload limit gives up its finest detail, never a record or a count", function()
	local Care = ns.Care
	local data = { npc = {}, obj = {}, loot = {}, vendor = {}, quest = {}, trainer = {}, beast = {} }
	local spots = 0
	for id = 1, 300 do
		local cells = { n = 0 }
		for i = 0, 59 do cells[(i * 5) .. ":" .. ((id + i) % 200 * 5)] = 1 + i % 3; cells.n = cells.n + 1; spots = spots + 1 + i % 3 end
		data.npc[id] = { name = "Npc " .. id, lo = 5, hi = 9, z = { [1429] = 1, [1433] = 1 }, p = { [1429] = cells },
			hp = { [5] = 100, [6] = 110, [7] = 120, [9] = 140 } }
	end
	data.loot["u:1"] = { n = 4, i = { [2589] = { 2, 3 } } }
	local size = Care.Size(data)
	local same, none = Care.Compact(data)
	check(none == 0 and same == size, "a small file was compacted")
	local after, stages = Care.Compact(data, size - 1, size * 0.9)
	check(stages >= 1 and after < size * 0.9, "not smaller: " .. size .. " -> " .. after)
	local npcs, sum = 0, 0
	for _, rec in pairs(data.npc) do
		npcs = npcs + 1
		for k, v in pairs(rec.p[1429]) do if k ~= "n" then sum = sum + v end end
		check(rec.name and rec.lo == 5 and rec.z[1433] and rec.hp[5] and rec.hp[9], "a record lost something that matters")
	end
	check(npcs == 300 and sum == spots, "sightings lost: " .. sum .. " of " .. spots)
	check(data.loot["u:1"].n == 4, "loot touched")
	-- the estimate is close to what the game writes (one line per value)
	local small = { a = { [1] = "xy", b = 12 } }
	check(math.abs(Care.Size(small) - #'T = {\r\n["a"] = {\r\n"xy", -- [1]\r\n["b"] = 12,\r\n},\r\n}\r\n') < 25, "size estimate: " .. Care.Size(small))
end)

step("status after a dungeon run: the dungeon, what was looted there, and what has no name or place yet", function()
	resetTrust()
	freshHealth()
	ns.Guard.session.errors, ns.Guard.session.kinds = 0, {}
	EverlookDBSettings.recent = nil
	ns.PlaceChanged()
	dungeonWorld({ dead = true, level = 37, class = "elite" })
	EverlookDBData.npc[258970], EverlookDBData.loot["u:258970"] = nil, nil
	MOCK.time = MOCK.time + 100
	openLoot({ ["Creature-0-1-2-3-258970-0000AA0011"] = { 275006, 267104 } })
	MOCK.time = MOCK.time + 10
	openLoot({ ["Creature-0-1-2-3-258970-0000AA0012"] = { 275006 } })
	unstubAll()
	local r = EverlookDBSettings.recent
	check(r and #r == 1 and r[1].name == "Krol'dok Stronghold" and r[1].inst and r[1].c.loot == 2 and r[1].c.items == 3, "tally")
	MOCK.log = {}
	SlashCmdList.EVERLOOKDB("status")
	local s = table.concat(MOCK.log, "\n")
	check(s:find("Recorded lately:", 1, true) and s:find("Krol'dok Stronghold|r (dungeon), now: 1 NPC (1 without a name yet), 2 corpses and nodes looted (3 items).", 1, true), s)
	check(not s:find("while recording since you logged in", 1, true) and not s:find("loot window", 1, true), "problems: " .. s)
	check(s:find("Where the %d+ NPCs are: %d+ on the map"), "coverage line")
	-- the tally lives in the settings, which are never uploaded, and holds no GUID
	check(EverlookDBData.recent == nil and not hasText(EverlookDBSettings, "Creature-"), "tally in the data, or a GUID in it")
	-- back in the open world: a new place; the list stays short
	nearWorld({ "Creature-0-1-2-3-4170-0000AA0013" })
	stub("GetRealZoneText", function() return "Elwynn Forest" end)
	ns.PlaceChanged()
	EverlookDBData.npc[4170] = nil
	tick(2)
	unstubAll()
	check(#r == 2 and r[2].name == "Elwynn Forest" and r[2].ids[4170], "the open-world place")
	MOCK.log = {}
	SlashCmdList.EVERLOOKDB("status")
	s = table.concat(MOCK.log, "\n")
	check(s:find("Elwynn Forest|r, now: 1 NPC (1 with a spot on the map).", 1, true), s)
	for i = 1, 30 do
		stub("GetRealZoneText", function() return "Zone " .. i end)
		ns.PlaceChanged(); ns.Tally("kills")
	end
	unstubAll()
	check(#EverlookDBSettings.recent == 12, "places kept: " .. #EverlookDBSettings.recent)
	EverlookDBSettings.recent = nil
	ns.PlaceChanged()
end)

step("positions: a creature you only fought (never close out of combat, never looted) gets a rough spot when it dies", function()
	resetTrust()
	nearWorld({ "Creature-0-1-2-3-4180-0000AB0021" })
	stub("CheckInteractDistance", function() return false end)
	stub("UnitName", function() return "Distant Caster" end)
	stub("IsInGroup", function() return true end)  -- in a group the XP isn't the mob's own, but the place still is
	EverlookDBData.npc[4180] = nil
	tick(2)
	local n = EverlookDBData.npc[4180]
	check(n and n.p == nil and n.pa == nil and ns.Care.Located(n) == "zone", "placed before the fight")
	MOCK.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Distant Caster dies, you gain 40 experience.")
	check(n.pa and n.pa[1429] and n.pa[1429]["400:600"] == 1 and n.xp == nil, "no rough spot from the kill")
	MOCK.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Distant Caster dies, you gain 40 experience.")
	check(n.pa[1429]["400:600"] == 1 and ns.Care.Located(n) == "approx", "counted again")
	unstubAll()
end)

step("paused: status says so; nothing is tallied", function()
	SlashCmdList.EVERLOOKDB("off")
	check(table.concat(ns.Problems(), " "):find("paused", 1, true), "status doesn't say paused")
	SlashCmdList.EVERLOOKDB("on")
end)
