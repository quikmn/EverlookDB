-- Offline tests for EverlookDB Collector against wowmock.lua: settings live apart from the uploaded data
-- (and `paused` moves out of it), every slash command and the window; no names of players in the data.
local ROOT = ...
local ADDON = "EverlookDB"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("  ok   " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(err)
		print("  FAIL " .. name .. "\n         " .. tostring(err))
	end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function last() return MOCK.log[#MOCK.log] or "" end

-- Extra API the collector touches
time, date = os.time, os.date
GetBuildInfo = function() return "1.16.1", "12345" end
C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end }
C_NamePlate = { GetNamePlates = function() return {} end }
C_TooltipInfo = { GetUnit = function() return nil end }
GetInstanceInfo = function() return "Elwynn", "none" end
UnitFactionGroup = function() return "Alliance" end
CORPSE_TOOLTIP = "Corpse of %s"
UNITNAME_TITLE_COMPANION, UNITNAME_TITLE_PET = "%s's Companion", "%s's Pet"
MOCK.reloads = 0
C_UI = { Reload = function() MOCK.reloads = MOCK.reloads + 1 end }
LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %s.", "You receive item: %sx%d."
CURRENCY_GAINED, CURRENCY_GAINED_MULTIPLE = "You receive currency: %s.", "You receive currency: %s x%d."
CURRENCY_GAINED_MULTIPLE_BONUS = "You receive currency: %s x%d. (Bonus Objective)"

local globalWrites = {}
local addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end })

step("load TOC files", function()
	-- data saved by an older version: paused inside the uploaded data, and a pending save confirmation
	EverlookDBData = { format = 1, locale = "enUS", since = 1700000000, paused = true, savingAt = os.time(),
		npc = { [1] = { name = "Kobold" } }, loot = { ["u:1"] = { n = 3, i = {} } }, obj = {}, vendor = {}, quest = {}, trainer = {} }
	EverlookDBSettings = nil
	local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
			if not chunk then error("syntax: " .. err) end
			setfenv(chunk, addonEnv)
			chunk(ADDON, ns)
		end
	end
	SlashCmdList.EVERLOOKDB("") -- before login: nothing yet, and no error
end)

step("login: settings get their defaults; paused and the save stamp move out of the data", function()
	local realPrint = print
	print = function(s) MOCK.log[#MOCK.log + 1] = s end
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.RunTimers()
	print = realPrint
	local s = EverlookDBSettings
	check(type(s) == "table", "no settings table")
	check(s.saveReminder == nil and s.savedMessage == true, "defaults")
	check(s.paused == true and ns.IsPaused(), "paused not carried over")
	check(EverlookDBData.paused == nil and EverlookDBData.savingAt == nil, "settings left in the uploaded data")
	check(s.lastSave ~= nil and last():find("data saved", 1, true), "save confirmation: " .. last())
	check(EverlookDBData.npc[1].name == "Kobold", "data lost")
end)

step("pause, resume and status from chat", function()
	SlashCmdList.EVERLOOKDB("resume")
	check(not ns.IsPaused() and EverlookDBSettings.paused == false and last():find("recording", 1, true), "resume")
	SlashCmdList.EVERLOOKDB("pause")
	check(ns.IsPaused() and EverlookDBSettings.paused == true and EverlookDBData.paused == nil, "pause")
	SlashCmdList.EVERLOOKDB("resume")
	MOCK.log = {}
	SlashCmdList.EVERLOOKDB("status")
	check(MOCK.log[1]:find("v0.1.0-test", 1, true) and MOCK.log[1]:find("Recording:", 1, true), "status header: " .. tostring(MOCK.log[1]))
	check(MOCK.log[2]:find("1 NPCs, 1 loot sources %(3 looted%)") and MOCK.log[3]:find("SavedVariables", 1, true), "status: " .. table.concat(MOCK.log, " / "))
end)

step("chat commands follow the shared pattern: on/off, get/set, aliases, suggestions", function()
	check(SLASH_EVERLOOKDB1 == "/edb" and SLASH_EVERLOOKDB2 == "/everlookdb", "slash words")
	SlashCmdList.EVERLOOKDB("off")
	check(ns.IsPaused() and last():find("Recording: off", 1, true), "off: " .. last())
	SlashCmdList.EVERLOOKDB("on")
	check(not ns.IsPaused() and last():find("Recording: on", 1, true), "on: " .. last())
	SlashCmdList.EVERLOOKDB("toggle")
	check(ns.IsPaused(), "toggle")
	SlashCmdList.EVERLOOKDB("resume")
	check(not ns.IsPaused(), "resume after toggle")
	SlashCmdList.EVERLOOKDB("set savedmessage off")
	check(EverlookDBSettings.savedMessage == false, "set")
	SlashCmdList.EVERLOOKDB("get savedmessage")
	check(last():find(": off", 1, true), "get: " .. last())
	SlashCmdList.EVERLOOKDB("savedmessage on")
	SlashCmdList.EVERLOOKDB("sav")
	check(last():find("Did you mean /edb save", 1, true) or last():find("Did you mean /edb savedmessage", 1, true), "suggestion: " .. last())
	SlashCmdList.EVERLOOKDB("stats")
	check(last():find("Did you mean /edb status?", 1, true), "typo suggestion: " .. last())
	SlashCmdList.EVERLOOKDB("version")
	check(last():find("v0.1.0-test", 1, true), "version: " .. last())
	SlashCmdList.EVERLOOKDB("reset")
	check(last():find("nothing to reset", 1, true), "reset: " .. last())
end)

step("settings from chat, with checks", function()
	SlashCmdList.EVERLOOKDB("savedmessage off")
	check(EverlookDBSettings.savedMessage == false, "savedmessage")
	SlashCmdList.EVERLOOKDB("savedmessage on")
	SlashCmdList.EVERLOOKDB("settings")
	SlashCmdList.EVERLOOKDB("bogus")
	check(last():find("/edb help", 1, true), "unknown")
	MOCK.log = {}
	SlashCmdList.EVERLOOKDB("help")
	local s = table.concat(MOCK.log, "\n")
	for _, c in ipairs({ "save", "on || off || toggle", "status", "feedback", "get [setting]", "search <words>" }) do check(s:find("/edb " .. c, 1, true), "help lacks " .. c) end
	check(s:find("Also works as /everlookdb", 1, true), "help lacks the alias")
end)

step("save reloads and stamps the settings, not the data", function()
	SlashCmdList.EVERLOOKDB("save")
	check(MOCK.reloads == 1, "no reload")
	check(EverlookDBSettings.savingAt and EverlookDBData.savingAt == nil, "save stamp in the data")
end)

step("feedback opens our own link window, not a Blizzard popup", function()
	SlashCmdList.EVERLOOKDB("feedback")
	check(EverlookDBFeedbackWindow and EverlookDBFeedbackWindow:IsShown(), "feedback window")
	check(EverlookDBFeedbackWindow.box:GetText():find("github.com/quikmn/EverlookDB", 1, true), "feedback url")
	EverlookDBFeedbackWindow:Hide()
	SlashCmdList.EVERLOOKDB("bug")
	check(EverlookDBFeedbackWindow:IsShown(), "bug alias")
	EverlookDBFeedbackWindow:Hide()
	check(next(StaticPopupDialogs) == nil, "StaticPopupDialogs used")
end)

step("window: bare /edb toggles it; every section builds; pause button; Escape closes", function()
	SlashCmdList.EVERLOOKDB("")
	local f = EverlookDBOptionsWindow
	check(f and f:IsShown() and f.navButtons and f.navButtons.privacy, "window with sidebar")
	for _, id in ipairs({ "status", "records", "privacy", "options", "status" }) do ns.app:Open(id) end
	local row
	for _, w in ipairs(ns.app.sections.status.stack.widgets) do if w.buttons and w.buttons[1]:GetText() == "Pause" then row = w end end
	check(row, "pause button")
	row.buttons[1]:GetScript("OnClick")(row.buttons[1])
	check(ns.IsPaused() and row.buttons[1]:GetText() == "Resume", "pause button didn't pause / relabel")
	row.buttons[1]:GetScript("OnClick")(row.buttons[1])
	check(not ns.IsPaused(), "resume button")
	f:GetScript("OnKeyDown")(f, "ESCAPE")
	check(not f:IsShown(), "escape")
	SlashCmdList.EVERLOOKDB("")
	check(f:IsShown(), "reopen")
	SlashCmdList.EVERLOOKDB("")
	check(not f:IsShown(), "toggle")
end)

step("privacy: the data file holds no settings and no window position", function()
	ns.app:Open()
	EverlookDBOptionsWindow:GetScript("OnDragStop")(EverlookDBOptionsWindow)
	check(EverlookDBSettings.window, "window position not saved")
	for _, k in ipairs({ "window", "paused", "saveReminder", "reminderMinutes", "savingAt", "lastSave" }) do
		check(EverlookDBData[k] == nil, "data file holds " .. k)
	end
	ns.app:Close()
end)

step("no taint: only our own globals", function()
	local allowed = { EverlookDBData = true, EverlookDBSettings = true, SLASH_EVERLOOKDB1 = true, SLASH_EVERLOOKDB2 = true, LibStub = true }
	for k in pairs(globalWrites) do check(allowed[k], "addon assigned the global " .. tostring(k)) end
	check(next(UISpecialFrames) == nil, "UISpecialFrames used")
end)

step("status totals are counted once per frame and fresh on the next", function()
	local a = ns.Status()
	check(ns.Status() == a, "counted again in the same frame")
	local npcs = a.npcs
	EverlookDBData.npc[987654] = EverlookDBData.npc[987654] or { n = "Test" }
	MOCK.time = MOCK.time + 1
	local b = ns.Status()
	check(b ~= a and b.npcs == npcs + 1, "next frame not recounted")
	EverlookDBData.npc[987654] = nil
end)

step("quest turn-in: the NPC that takes it and where, never the player", function()
	local realGUID = UnitGUID
	UnitGUID = function(u) if u == "npc" then return "Creature-0-1-2-3-1077-0000ABCD" end return realGUID(u) end
	UnitLevel = UnitLevel or function() return 30 end
	GetQuestID = function() return 95810 end
	GetTitleText = function() return "Lost Relic Carry" end
	GetNumQuestRewards, GetNumQuestChoices, GetRewardMoney = function() return 0 end, function() return 0 end, function() return 0 end
	MOCK.Fire("QUEST_COMPLETE")
	MOCK.Fire("QUEST_TURNED_IN", 95810, 1250, 0)
	UnitGUID = realGUID
	local q = EverlookDBData.quest[95810]
	check(q and q.to == "u:1077", "turn-in NPC not recorded: " .. tostring(q and q.to))
	check(q.toAt == "1429:500:500", "turn-in spot: " .. tostring(q.toAt))
	check(q.done == 1 and q.xp and q.xp[30] == 1250, "turn-in or its XP not counted")
	local me = MOCK.units.player.name
	for k, v in pairs(q) do
		check(type(v) ~= "string" or not (me and v:find(me, 1, true)), "player name stored in " .. k)
	end
end)

step("quest turn-in: XP and money the game hides are skipped, not compared", function()
	MOCK.Fire("QUEST_TURNED_IN", 95812, MOCK.Secret(900), MOCK.Secret(50))
	local q = EverlookDBData.quest[95812]
	check(q and q.done == 1 and q.xp == nil and q.money == nil, "hidden values saved or turn-in lost")
end)

local FAVOR = "|cffffffff|Hcurrency:3402:0|h[Merchant's Favor]|h|r"
local function itemLink(id) return "|cff1eff00|Hitem:" .. id .. "::::::::60:::::|h[Thing]|h|r" end
local function crateWindow(qid)
	local realGUID = UnitGUID
	UnitGUID = function(u) if u == "npc" then return "Creature-0-1-2-3-256390-0000ABCD" end return realGUID(u) end
	GetQuestID = function() return qid end
	GetTitleText = function() return "A Sealed Crate" end
	MOCK.Fire("QUEST_COMPLETE")
	UnitGUID = realGUID
end

step("reward window: listed currencies, and reward items whose link is still loading (by the item id)", function()
	GetNumQuestRewards, GetNumQuestChoices, GetRewardMoney = function() return 1 end, function() return 0 end, function() return 750 end
	GetQuestItemLink = function() return nil end
	GetQuestItemInfo = function(kind, i) if kind == "reward" and i == 1 then return "Bag", 1, 2, 1, true, 248800 end end
	GetNumRewardCurrencies = function() return 1 end
	C_QuestOffer = { GetQuestRewardCurrencyInfo = function(kind, i)
		if kind == "reward" and i == 1 then return { currencyID = 3402, totalRewardAmount = 10, baseRewardAmount = 10 } end
	end }
	crateWindow(91901)
	local q = EverlookDBData.quest[91901]
	check(q.currency == "3402x10", "listed currency: " .. tostring(q.currency))
	check(q.reward == "248800x2" and q.money == 750, "listed item or money: " .. tostring(q.reward) .. " " .. tostring(q.money))
	-- the older API, and a hidden amount is left out, not compared
	C_QuestOffer = nil
	GetQuestCurrencyID = function() return 3402 end
	GetQuestCurrencyInfo = function() return "Merchant's Favor", 1, MOCK.Secret(10), 1 end
	crateWindow(91904)
	check(EverlookDBData.quest[91904].currency == nil, "hidden currency amount saved")
	GetQuestCurrencyInfo = function() return "Merchant's Favor", 1, 15, 1 end
	crateWindow(91904)
	check(EverlookDBData.quest[91904].currency == "3402x15", "older API: " .. tostring(EverlookDBData.quest[91904].currency))
	GetNumRewardCurrencies, GetQuestCurrencyID, GetQuestCurrencyInfo = nil, nil, nil
	GetNumQuestRewards, GetRewardMoney = function() return 0 end, function() return 0 end
	MOCK.RunTimers()
end)

step("turn-in: what it really gave goes to the quest, bonus amounts as a spread", function()
	MOCK.RunTimers() -- no window open
	local q = EverlookDBData.quest[91901]
	q.got = nil
	MOCK.Fire("QUEST_TURNED_IN", 91901, 0, 750)
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 110, 10)
	MOCK.Fire("CHAT_MSG_CURRENCY", "You receive currency: " .. FAVOR .. " x10.")  -- the same gain again: not counted twice
	MOCK.Fire("CHAT_MSG_LOOT", "You receive item: " .. itemLink(248801) .. "x3.")
	MOCK.Fire("CHAT_MSG_LOOT", "You receive loot: " .. itemLink(2589) .. ".")     -- looting, not the quest
	MOCK.time = MOCK.time + 1
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 111, 1)                              -- Performance Bonus
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 101, -10)                            -- spent: not a reward
	MOCK.RunTimers()
	check(q.got and q.got.n == 1, "turn-in not watched")
	check(q.got.c[3402][11] == 1 and q.got.c[3402][10] == nil, "Favor with bonus: " .. tostring(q.got.c[3402][11]))
	check(q.got.i[248801][3] == 1 and q.got.i[2589] == nil, "received items")
	-- the next one: the gain arrives just before the event; one after the window is not the quest's
	MOCK.time = MOCK.time + 10
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 121, 10)
	MOCK.time = MOCK.time + 0.5
	MOCK.Fire("QUEST_TURNED_IN", 91901, 0, 750)
	MOCK.time = MOCK.time + 5
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 131, 10)
	MOCK.RunTimers()
	check(q.got.n == 2 and q.got.c[3402][10] == 1 and q.got.c[3402][11] == 1, "second turn-in: " .. tostring(q.got.c[3402][10]))
	-- an old gain (long before) is not taken
	MOCK.time = MOCK.time + 10
	MOCK.Fire("QUEST_TURNED_IN", 91901, 0, 750)
	MOCK.RunTimers()
	check(q.got.n == 3 and q.got.c[3402][10] == 1, "a gain from before the window counted")
end)

step("turn-in: a hidden amount is not compared; the chat line stands in for it", function()
	local q = EverlookDBData.quest[91904]
	MOCK.Fire("QUEST_TURNED_IN", 91904, 0, 500)
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, MOCK.Secret(140), MOCK.Secret(12))
	MOCK.Fire("CHAT_MSG_CURRENCY", "You receive currency: " .. FAVOR .. " x12.")
	MOCK.Fire("CHAT_MSG_CURRENCY", MOCK.Secret("You receive currency: " .. FAVOR .. " x99."))
	MOCK.Fire("CHAT_MSG_LOOT", "You receive item: " .. itemLink(248802) .. ".")
	MOCK.RunTimers()
	check(q.got.n == 1 and q.got.c[3402][12] == 1, "chat fallback")
	check(q.got.i[248802][1] == 1, "single item line")
	-- a second turn-in closes the first one's window at once
	MOCK.Fire("QUEST_TURNED_IN", 91904, 0, 500)
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 150, 10)
	MOCK.Fire("QUEST_TURNED_IN", 91901, 0, 750)
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 165, 15)
	MOCK.RunTimers()
	check(q.got.n == 2 and q.got.c[3402][10] == 1, "first window")
	check(EverlookDBData.quest[91901].got.c[3402][15] == 1, "second window")
end)

step("turn-in: nothing is watched while recording is paused", function()
	local q = EverlookDBData.quest[91904]
	ns.SetPaused(true)
	MOCK.Fire("QUEST_TURNED_IN", 91904, 0, 500)
	MOCK.Fire("CURRENCY_DISPLAY_UPDATE", 3402, 175, 10)
	MOCK.RunTimers()
	ns.SetPaused(false)
	check(q.got.n == 2 and q.got.c[3402][10] == 1, "watched while paused")
end)

step("settings from the save pop-up's time lose its options", function()
	EverlookDBSettings.saveReminder, EverlookDBSettings.reminderMinutes = true, 20
	ns.InitSettings(EverlookDBData)
	check(EverlookDBSettings.saveReminder == nil and EverlookDBSettings.reminderMinutes == nil, "old options kept")
	check(ns.app:GetSetting("savereminder") == nil and ns.app:GetSetting("reminderminutes") == nil, "old settings still offered")
end)

step("a title line that names an owner (Bob's Companion) is never kept", function()
	check(ns.OwnerTitle("Bob's Companion") and ns.OwnerTitle("Zoë's Pet"), "owner line not recognised")
	check(not ns.OwnerTitle("<Weapon Merchant>") and not ns.OwnerTitle("Weapon Merchant"), "a real title taken for an owner line")
end)

step("quest completion: a title holding the player's name is not saved", function()
	local me = MOCK.units.player.name
	local secrets = MOCK.secretsOn
	MOCK.secretsOn = false
	GetQuestID = function() return 95811 end
	GetTitleText = function() return "A letter for " .. me end
	MOCK.Fire("QUEST_COMPLETE")
	local q = EverlookDBData.quest[95811]
	MOCK.secretsOn = secrets
	check(q and q.title == nil, "title with the player's name saved: " .. tostring(q and q.title))
end)

---------------------------------------------------------------------------------------------------------------
-- Hunters: fresh tames and Beast Lore (Beasts.lua)

-- A small world for the hunter steps: a wild beast as the target, the player's pet, its spellbook and tooltip lines.
local H = { guids = {}, levels = {}, families = {}, petSpells = {}, lines = {}, secretLine = false }
local NAMES = { [17253] = "Bite", [17255] = "Bite", [17256] = "Bite", [23099] = "Dash", [23109] = "Dash",
	[24450] = "Prowl", [1263099] = "Faster Attack I", [1263100] = "Faster Attack II", [26064] = "Shell Shield" }
local saved = {}
local function stub(name, fn) if saved[name] == nil then saved[name] = _G[name] or false end; _G[name] = fn end
local function unstubAll() for k, v in pairs(saved) do _G[k] = v or nil end; saved = {} end
local function hunterWorld()
	stub("UnitGUID", function(u) return H.guids[u] end)
	stub("UnitLevel", function(u) return H.levels[u] end)
	stub("UnitCreatureFamily", function(u) local f = H.families[u]; if f then return f[1], f[2] end end)
	stub("UnitAttackSpeed", function(u) if u == "pet" then return 1.8, nil end end)
	stub("C_PetInfo", { GetPetTrainingPoints = function() return 24, 0 end, GetPetFoodTypes = function() return { "Meat", "Fish" } end })
	stub("PET_DIET_TEMPLATE", "Diet: %s")
	stub("TAMEABLE", "Tameable")
	stub("C_SpellBook", {
		HasPetSpells = function() return #H.petSpells, "PET" end,
		GetSpellBookItemInfo = function(i) local s = H.petSpells[i]; return s and { spellID = s[1], isPassive = s[2], name = "Wolfie's " .. s[1] } end,
	})
	stub("C_UnitAuras", { GetAuraDataByIndex = function(u, i)
		if u ~= "pet" then return nil end
		return ({ { spellId = 1263100, duration = 0 }, { spellId = 999, duration = 30 } })[i]
	end })
	stub("C_Spell", { GetSpellName = function(id) return NAMES[id] or ("Spell" .. id) end })
	stub("C_TooltipInfo", { GetUnit = function(u)
		if u ~= "target" then return nil end
		local out = {}
		for i, t in ipairs(H.lines) do out[i] = { leftText = (H.secretLine and i == 2) and MOCK.Secret(t) or t, type = 0 } end
		return { lines = out }
	end })
	ns.BeastsReady()
end
local function runTimers(n) for _ = 1, n or 10 do MOCK.RunTimers() end end
local function hasText(t, needle)
	for k, v in pairs(t) do
		if type(k) == "string" and k:find(needle, 1, true) then return true end
		if type(v) == "string" and v:find(needle, 1, true) then return true end
		if type(v) == "table" and hasText(v, needle) then return true end
	end
	return false
end
local LORE_BEFORE = { "Mangy Wolf", "Level 11 Beast (Wolf)", "Skinnable" }
local LORE_AFTER = { "Mangy Wolf", "Level 11 Beast (Wolf)", "Skinnable", "Tameable", "Diet: Meat", "Abilities: Bite (Rank 2), Dash (Rank 1)" }

step("ISO week buckets: no day, no time of day", function()
	check(ns.IsoWeek(os.time({ year = 2026, month = 11, day = 18, hour = 12 })) == "2026-W47", "2026-11-18")
	check(ns.IsoWeek(os.time({ year = 2021, month = 1, day = 1, hour = 12 })) == "2020-W53", "2021-01-01 belongs to 2020's week 53")
	check(ns.IsoWeek(os.time({ year = 2024, month = 12, day = 30, hour = 12 })) == "2025-W01", "2024-12-30 is week 1 of 2025")
end)

step("Beast Lore ability lines turn into spell ids in the client's language", function()
	hunterWorld()
	local ids = ns.SpellsIn("Abilities: Bite (Rank 3), Dash (Rank 1), Faster Attack II, Shell Shield")
	table.sort(ids)
	check(table.concat(ids, ",") == "17256,23099,26064,1263100", "got " .. table.concat(ids, ","))
	check(#ns.SpellsIn("Bite") == 0, "a many-rank ability without a rank was placed")
	unstubAll()
end)

step("fresh tame: the new pet's spellbook, auras, speed, level, family, training points, diet; never its name", function()
	hunterWorld()
	if ns.IsPaused() then ns.SetPaused(false) end
	H.guids.target = "Creature-0-1-2-3-3825-0000AB12CD"
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	H.levels.target, H.levels.pet = 12, 12
	H.families.pet = { "Cat", 2 }
	H.petSpells = {}   -- the spellbook arrives late
	MOCK.Fire("UNIT_SPELLCAST_SENT", "player", "Ashenvale Panther", "cast-1", 1515)
	MOCK.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-1", 1515)
	H.guids.target = nil
	H.guids.pet = "Pet-0-1-2-3-3825-0100AB12CD"
	MOCK.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-1", 1515)
	MOCK.Fire("UNIT_PET", "player")
	runTimers(2)
	check(not EverlookDBData.beast[3825], "noted before the 30 seconds were up")
	H.petSpells = { { 17253, false }, { 24450, false }, { 1263100, true } }
	runTimers(10)
	local t = EverlookDBData.beast[3825] and EverlookDBData.beast[3825].tame
	check(t and t.n == 1, "tame not noted")
	check(t.lvl[12] == 1 and t.plvl[12] == 1 and t.fam[2] == 1, "levels / family")
	check(t.s[17253] == 1 and t.s[24450] == 1 and t.s[1263100] == 1 and t.pas[1263100] and not t.pas[17253], "spells / passive flag")
	check(t.set["17253,24450,1263100"] == 1, "whole list")
	check(t.aura[1263100] == 1 and not t.aura[999], "permanent auras only")
	check(t.spd["1.80"] == 1 and t.tp["12:24:0"] == 1 and t.diet.Meat == 1 and t.diet.Fish == 1, "speed / training points / diet")
	local key = next(EverlookDBData.beast[3825].wk)
	check(key and key:match("^1%.16%.1%.12345:%d%d%d%d%-W%d%d$"), "time bucket: " .. tostring(key))
	check(not hasText(EverlookDBData.beast, "Wolfie") and not hasText(EverlookDBData.beast, "Tester"), "a name was saved")
	-- the same pet again (a summon, a reload) is not a second tame
	MOCK.Fire("UNIT_PET", "player")
	runTimers(10)
	check(t.n == 1, "counted twice")
	unstubAll()
end)

step("a failed tame, then calling an old pet, notes nothing", function()
	hunterWorld()
	H.guids.target = "Creature-0-1-2-3-1131-0000AB12CE"
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	H.levels.target = 9
	MOCK.Fire("UNIT_SPELLCAST_SENT", "player", "Mangy Wolf", "cast-2", 1515)
	MOCK.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-2", 1515)
	H.guids.pet = "Pet-0-1-2-3-3825-0100FFFFFF"   -- the old cat: another creature id
	H.petSpells = { { 17253, false } }
	MOCK.Fire("UNIT_PET", "player")
	runTimers(10)
	check(not EverlookDBData.beast[1131], "an old pet was taken for a tame")
	unstubAll()
end)

step("Beast Lore: the lines it adds, as the game gives them, spell ids, level and a count of reads", function()
	hunterWorld()
	H.guids.target = "Creature-0-1-2-3-1131-0000AB12CF"
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	H.levels.target = 11
	H.lines = LORE_BEFORE
	MOCK.Fire("UNIT_SPELLCAST_SENT", "player", "Mangy Wolf", "cast-3", 1462)
	H.lines = LORE_AFTER
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 1462)
	runTimers(4)
	local L = EverlookDBData.beast[1131] and EverlookDBData.beast[1131].lore
	check(L and L.n == 1 and L.lvl[11] == 1, "read not counted")
	check(L.t and L.t.Tameable == 1, "tameable line")
	check(L.d and L.d["Diet: Meat"] == 1, "diet line")
	check(L.a and L.a["Abilities: Bite (Rank 2), Dash (Rank 1)"] == 1, "ability line")
	check(L.s[17255] == 1 and L.s[23099] == 1, "spell ids")
	check(not hasText(L, "Skinnable") and not hasText(L, "Level 11") and not hasText(L, "Mangy Wolf"), "the usual lines were kept")
	-- a second cast is a second read
	H.lines = LORE_BEFORE
	MOCK.Fire("UNIT_SPELLCAST_SENT", "player", "Mangy Wolf", "cast-4", 1462)
	H.lines = LORE_AFTER
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 1462)
	runTimers(4)
	check(L.n == 2 and L.s[17255] == 2 and L.a["Abilities: Bite (Rank 2), Dash (Rank 1)"] == 2, "second read")
	-- a read with a line hidden from addons (combat) is skipped
	H.secretLine = true
	H.lines = LORE_BEFORE
	MOCK.Fire("UNIT_SPELLCAST_SENT", "player", "Mangy Wolf", "cast-5", 1462)
	H.lines = LORE_AFTER
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 1462)
	runTimers(4)
	check(L.n == 2, "a read with hidden values was counted")
	H.secretLine = false
	unstubAll()
end)

step("beasts: each spawn's level counted once, so the level spread shows", function()
	hunterWorld()
	H.guids.target = "Creature-0-1-2-3-1131-0000AB1300"
	H.levels.target = 10
	H.families.target = { "Wolf", 1 }
	stub("UnitExists", function(u) return u == "target" end)
	stub("UnitIsPlayer", function() return false end)
	stub("UnitPlayerControlled", function() return false end)
	stub("UnitName", function(u) if u == "target" then return "Mangy Wolf" end end)
	stub("UnitHealthMax", function() return 100 end)
	stub("UnitClassification", function() return "normal" end)
	stub("UnitCreatureType", function() return "Beast" end)
	stub("UnitReaction", function() return 2 end)
	stub("CheckInteractDistance", function() return false end)
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	H.guids.target = "Creature-0-1-2-3-1131-0000AB1301"
	H.levels.target = 11
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	local lvl = EverlookDBData.npc[1131] and EverlookDBData.npc[1131].lvl
	check(lvl and lvl[10] == 1 and lvl[11] == 1, "levels: " .. tostring(lvl and lvl[10]))
	unstubAll()
end)

-- A creature next to the player, seen on its nameplate every second: one spawn, one count.
local function nearWorld(guids)
	local plates = {}
	for i, g in ipairs(guids) do plates[i] = { namePlateUnitToken = "nameplate" .. i } end
	local function guidOf(u) local i = tonumber(tostring(u):match("^nameplate(%d+)$")); return i and guids[i] end
	stub("UnitGUID", guidOf)
	stub("UnitExists", function(u) return guidOf(u) ~= nil end)
	stub("UnitIsPlayer", function() return false end)
	stub("UnitPlayerControlled", function() return false end)
	stub("UnitName", function(u) return guidOf(u) and "Kobold Vermin" end)
	stub("UnitLevel", function() return 2 end)
	stub("UnitHealthMax", function() return 50 end)
	stub("UnitClassification", function() return "normal" end)
	stub("UnitCreatureType", function() return "Humanoid" end)
	stub("UnitCreatureFamily", function() return nil end)
	stub("UnitReaction", function() return 2 end)
	stub("CheckInteractDistance", function() return true end)
	local whereCalls = 0
	stub("C_Map", {
		GetBestMapForUnit = function() whereCalls = whereCalls + 1; return 1429 end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end,
	})
	stub("C_NamePlate", { GetNamePlates = function() return plates end })
	return function() return whereCalls end
end

step("spawns: a creature you stand next to counts once a session, not once a second", function()
	local whereCalls = nearWorld({ "Creature-0-1-2-3-6-0000AA0001", "Creature-0-1-2-3-6-0000AA0002" })
	EverlookDBData.npc[6] = nil
	MOCK.time = MOCK.time + 1
	local before = ns.Status().unsaved
	for _ = 1, 30 do MOCK.time = MOCK.time + 1; MOCK.RunTimers() end
	local cells = EverlookDBData.npc[6] and EverlookDBData.npc[6].p and EverlookDBData.npc[6].p[1429]
	check(cells and cells["400:600"] == 2 and cells.n == 1, "two spawns, 30 s: " .. tostring(cells and cells["400:600"]))
	MOCK.time = MOCK.time + 1
	local unsaved = ns.Status().unsaved
	check(unsaved - before <= 4, "changed-since-save counts every second: " .. (unsaved - before))
	-- the player's position is read once a tick, not once per plate (two plates, 30 ticks)
	check(whereCalls() <= 30, "where() per plate: " .. whereCalls())
	-- looting the same spawn's corpse doesn't count it again
	stub("GetNumLootItems", function() return 1 end)
	stub("GetLootSlotLink", function() return "|Hitem:2589:|h[Linen Cloth]|h" end)
	stub("GetLootSourceInfo", function() return "Creature-0-1-2-3-6-0000AA0001", 1 end)
	stub("IsFishingLoot", function() return false end)
	stub("GetMoney", function() return 0 end)
	MOCK.Fire("LOOT_OPENED")
	MOCK.Fire("LOOT_CLOSED")
	check(cells["400:600"] == 2, "corpse counted the spawn again: " .. cells["400:600"])
	unstubAll()
end)

step("spawns: counts inflated by older versions become 1 once (sightings stay sightings)", function()
	local data = { npc = {
		[1] = { p = { [1429] = { n = 3, ["10:10"] = 408, ["15:10"] = 1, ["20:20"] = 7 } } },
		[2] = { p = { [229] = { n = 40 } } },   -- an instance, no positions
	}, obj = { [3] = { p = { [1429] = { n = 1, ["10:10"] = 5 } } } } }
	ns.NormalizeSpots(data)
	local c = data.npc[1].p[1429]
	check(c["10:10"] == 1 and c["15:10"] == 1 and c["20:20"] == 1 and c.n == 3, "cells not capped")
	check(data.npc[2].p[229].n == 1, "instance sightings: " .. data.npc[2].p[229].n)
	check(data.obj[3].p[1429]["10:10"] == 5, "node loot counts touched")
	data.npc[1].p[1429]["10:10"] = 2
	check(ns.NormalizeSpots(data) == 0 and data.npc[1].p[1429]["10:10"] == 2, "normalized twice")
	check(EverlookDBData.spotFormat == 2, "the real data file not marked")
end)

step("seen sets stay bounded and remember the newest keys", function()
	local s = ns.SeenSet(3)
	for i = 1, 10 do s.add(i) end
	check(s.has(10) and s.has(9) and s.has(7) and not s.has(1), "wrong keys kept")
end)

step("vendor: read once when every item is known, again a moment later when some were still loading", function()
	local reads, missingLinks = 0, 0
	stub("UnitGUID", function(u) if u == "npc" then return "Creature-0-1-2-3-1250-0000BB0001" end end)
	stub("UnitExists", function() return false end)
	stub("UnitReaction", function() return 5 end)
	stub("GetMerchantNumItems", function() reads = reads + 1; return 2 end)
	stub("GetMerchantItemLink", function(slot) if slot == 2 and missingLinks > 0 then missingLinks = missingLinks - 1; return nil end return "|Hitem:" .. (100 + slot) .. ":|h[x]|h" end)
	stub("C_MerchantFrame", { GetItemInfo = function() return { price = 10, stackCount = 1, numAvailable = -1 } end })
	MOCK.Fire("MERCHANT_SHOW")
	runTimers(3)
	check(reads == 1, "every item known, read " .. reads .. " times")
	reads, missingLinks = 0, 1
	MOCK.Fire("MERCHANT_SHOW")
	runTimers(3)
	check(reads == 2 and EverlookDBData.vendor[1250].i[102], "an item still loading: read " .. reads .. " times")
	unstubAll()
end)

step("status names the beasts", function()
	MOCK.log = {}
	SlashCmdList.EVERLOOKDB("status")
	check(table.concat(MOCK.log, " "):find("Beast abilities: 2 beasts (1 tames, 2 Beast Lore reads)", 1, true), table.concat(MOCK.log, " / "))
end)

-- A loot window: { [guid] = { item ids } }, one slot per item
local function openLoot(sources)
	local slots = {}
	for guid, items in pairs(sources) do
		for _, id in ipairs(items) do slots[#slots + 1] = { guid = guid, id = id } end
	end
	stub("GetNumLootItems", function() return #slots end)
	stub("GetLootSlotLink", function(i) return "|Hitem:" .. slots[i].id .. ":|h[x]|h" end)
	stub("GetLootSourceInfo", function(i) return slots[i].guid, 1 end)
	stub("IsFishingLoot", function() return false end)
	stub("GetMoney", function() return 0 end)
	MOCK.Fire("LOOT_READY")
	MOCK.Fire("LOOT_OPENED")
	MOCK.Fire("LOOT_CLOSED")
end

step("loot: a skinning cast counts for one loot window, not the next corpse looted soon after", function()
	local L = EverlookDBData.loot
	MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 8613)  -- Skinning (Spell8613 in the mock)
	openLoot({ ["Creature-0-1-2-3-113-0000C00001"] = { 2318 } })
	MOCK.time = MOCK.time + 1
	openLoot({ ["Creature-0-1-2-3-113-0000C00002"] = { 2672 } })
	check(L["s:113"] and L["s:113"].n == 1 and L["s:113"].i[2318], "skinning not counted")
	check(L["u:113"] and L["u:113"].i[2672] and not L["s:113"].i[2672], "the next corpse counted as skinned")
	unstubAll()
end)

step("loot: a world object's name is the tooltip just before it, never an older one", function()
	stub("GameTooltipTextLeft1", { GetText = function() return MOCK.tip end })
	GameTooltip.GetOwner = function() return UIParent end
	local show = GameTooltip:GetScript("OnShow")
	MOCK.tip = "Chair"; show(GameTooltip)
	MOCK.tip = MOCK.Secret("Doan's Strongbox"); show(GameTooltip)    -- hidden in an instance
	openLoot({ ["GameObject-0-1-2-3-103821-0000D00001"] = { 7146 } })
	check(EverlookDBData.obj[103821] and EverlookDBData.obj[103821].name == nil, "an older tooltip named the object")
	MOCK.tip = "Solid Chest"; show(GameTooltip)
	openLoot({ ["GameObject-0-1-2-3-2855-0000D00002"] = { 1710 } })
	MOCK.time = MOCK.time + 2
	openLoot({ ["GameObject-0-1-2-3-2689-0000D00003"] = { 4483 } })
	check(EverlookDBData.obj[2855].name == "Solid Chest", "object name")
	check(EverlookDBData.obj[2689].name == nil, "a name used twice")
	GameTooltip.GetOwner = nil
	unstubAll()
end)

step("vendor: a currency cost is saved by its id, which the site reads; older saved names are fixed", function()
	stub("UnitGUID", function(u) if u == "npc" then return "Creature-0-1-2-3-256730-0000BB0002" end end)
	stub("UnitExists", function() return false end)
	stub("UnitReaction", function() return 5 end)
	stub("GetMerchantNumItems", function() return 2 end)
	stub("GetMerchantItemLink", function(slot) return "|Hitem:" .. (251418 + slot) .. ":|h[x]|h" end)
	stub("C_MerchantFrame", { GetItemInfo = function() return { price = 0, stackCount = 1, numAvailable = -1, hasExtendedCost = true } end })
	stub("GetMerchantItemCostInfo", function() return 1 end)
	stub("GetMerchantItemCostItem", function(slot)
		if slot == 1 then return 1, 60, nil, "Merchant's Favor" end   -- a currency: only its name
		return 1, 2, "|Hitem:2589:|h[Linen Cloth]|h", nil
	end)
	stub("C_CurrencyInfo", {
		GetCurrencyListSize = function() return 2 end,
		GetCurrencyListInfo = function(i) return ({ { name = "Miscellaneous", isHeader = true }, { name = "Merchant's Favor" } })[i] end,
		GetCurrencyListLink = function(i) if i == 2 then return "|Hcurrency:3402:0|h[Merchant's Favor]|h" end end,
	})
	MOCK.Fire("MERCHANT_SHOW")
	MOCK.Fire("MERCHANT_CLOSED")
	runTimers(3)
	local v = EverlookDBData.vendor[256730].i
	check(v[251419].cost == "currency:3402x60", "currency cost: " .. tostring(v[251419].cost))
	check(v[251420].cost == "item:2589x2", "item cost: " .. tostring(v[251420].cost))
	local data = { vendor = { [1] = { i = { [5] = { cost = "currency:Merchant's Favorx200" }, [6] = { cost = "currency:Honor Pointsx5" } } } } }
	check(ns.FixVendorCosts(data) == 1, "older costs not fixed")
	check(data.vendor[1].i[5].cost == "currency:3402x200" and data.vendor[1].i[6].cost == "currency:Honor Pointsx5", "fixed wrongly")
	unstubAll()
end)

step("quests: a hand-in window notes the title; an objective still loading doesn't replace a full list", function()
	GetQuestID = function() return 7791 end
	GetTitleText = function() return "A Donation of Wool" end
	stub("GetNumQuestItems", function() return 1 end)
	stub("GetQuestItemLink", function() return "|Hitem:2592:|h[Wool Cloth]|h" end)
	stub("GetQuestItemInfo", function() return "Wool Cloth", 1, 60 end)
	MOCK.Fire("QUEST_PROGRESS")
	local q = EverlookDBData.quest[7791]
	check(q.title == "A Donation of Wool" and q.needs == "2592x60", "hand-in: " .. tostring(q.title) .. " " .. tostring(q.needs))
	local text = ""
	stub("C_QuestLog", {
		GetLogIndexForQuestID = function() return 1 end,
		GetInfo = function() return { title = "Bounty", level = 10 } end,
		GetQuestObjectives = function() return { { type = "item", numRequired = 8, text = text } } end,
	})
	MOCK.Fire("QUEST_ACCEPTED", 5545)
	check(EverlookDBData.quest[5545].objectives == nil, "an empty objective saved")
	text = "0/8 Bundle of Wood"
	runTimers(2)
	check(EverlookDBData.quest[5545].objectives[1] == "item|8|Bundle of Wood", "objective after loading: " .. tostring(EverlookDBData.quest[5545].objectives))
	text = ""
	MOCK.Fire("QUEST_ACCEPTED", 5545)
	runTimers(2)
	check(EverlookDBData.quest[5545].objectives[1] == "item|8|Bundle of Wood", "full list replaced")
	unstubAll()
end)

step("buying from a merchant right after a hand-in is not a quest reward", function()
	local q = EverlookDBData.quest[91904]
	stub("GetMerchantNumItems", function() return 0 end)
	MOCK.Fire("QUEST_TURNED_IN", 91904, 0, 500)
	MOCK.Fire("MERCHANT_SHOW")
	MOCK.Fire("CHAT_MSG_LOOT", "You receive item: " .. itemLink(159) .. "x5.")
	MOCK.Fire("MERCHANT_CLOSED")
	MOCK.RunTimers()
	check(q.got.n == 3 and not q.got.i[159], "a purchase counted as a reward")
	unstubAll()
end)

step("login drops saved titles that name an owner", function()
	EverlookDBData.npc[248463] = { name = "Rumbler", title = "Nimsy's Pet" }
	EverlookDBData.npc[1481] = { name = "Bart Tidewater", title = "Captain of the Maiden's Virtue" }
	MOCK.Fire("PLAYER_LOGIN")
	check(EverlookDBData.npc[248463].title == nil, "owner title kept")
	check(EverlookDBData.npc[1481].title == "Captain of the Maiden's Virtue", "a real title dropped")
end)

---------------------------------------------------------------------------------------------------
-- GUID trust: GUIDs are only a "same spawn?" key in memory, and only while they are stable

local function resetTrust()
	ns.GuidTrust.stable = true
	ns.TrustCounts({ checked = 0, badFormat = 0, changed = 0 })
end

-- creatures of `npc` on nameplates next to the player; scramble: every UnitGUID call gives a new spawn part
local function plateWorld(npc, plates, scramble)
	local n = 0
	local shown = {}
	for i = 1, plates do shown[i] = { namePlateUnitToken = "nameplate" .. i } end
	local world = { shown = shown, npc = npc }
	local function isPlate(u) local i = tonumber(tostring(u):match("^nameplate(%d+)$")); return i and shown[i] ~= nil end
	stub("UnitGUID", function(u)
		if not isPlate(u) then return nil end
		if scramble then n = n + 1; return ("Creature-0-%d-0-%d-%d-%010X"):format(n, n * 7, world.npc, n) end
		return ("Creature-0-1-2-3-%d-%010X"):format(world.npc, tonumber(u:match("%d+")))
	end)
	stub("UnitExists", isPlate)
	stub("UnitIsPlayer", function() return false end)
	stub("UnitPlayerControlled", function() return false end)
	stub("UnitName", function(u) return isPlate(u) and "Kobold Vermin" end)
	stub("UnitLevel", function() return 2 end)
	stub("UnitHealthMax", function() return 50 end)
	stub("UnitClassification", function() return "normal" end)
	stub("UnitCreatureType", function() return "Humanoid" end)
	stub("UnitCreatureFamily", function() return nil end)
	stub("UnitReaction", function() return 2 end)
	stub("CheckInteractDistance", function() return true end)
	stub("C_Map", {
		GetBestMapForUnit = function() return 1429 end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end,
	})
	stub("C_NamePlate", { GetNamePlates = function() local out = {}; for _, p in pairs(shown) do out[#out + 1] = p end; return out end })
	return world
end

local function tick(n) for _ = 1, n or 1 do MOCK.time = MOCK.time + 1; MOCK.RunTimers() end end

step("guid trust: steady GUIDs stay trusted; a GUID that changes on the next read is not", function()
	resetTrust()
	plateWorld(7, 2, false)
	tick(5)
	check(ns.GuidTrust.stable and ns.GuidTrust.counts.checked > 0 and ns.GuidTrust.counts.changed == 0, "steady GUIDs distrusted")
	unstubAll()
	plateWorld(7, 1, true)
	tick(1)
	check(not ns.GuidTrust.stable and ns.GuidTrust.counts.changed >= 1, "a changing GUID was trusted")
	unstubAll()
	-- a target that keeps its token (no target change) but shows a new GUID for the same NPC
	resetTrust()
	local g = "Creature-0-1-2-3-99-00000000A1"
	stub("UnitGUID", function(u) if u == "target" then return g end end)
	stub("UnitIsPlayer", function() return false end)
	tick(1)
	g = "Creature-0-9-2-8-99-00000000B7"
	tick(1)
	check(not ns.GuidTrust.stable, "the target's GUID changed and was still trusted")
	-- a real target change is not a GUID change
	resetTrust()
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	g = "Creature-0-1-2-3-99-00000000C3"
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	tick(2)
	check(ns.GuidTrust.stable, "a new target was taken for a changed GUID")
	unstubAll()
end)

step("stable GUIDs: two spawns of one NPC side by side count as two, each once", function()
	resetTrust()
	plateWorld(9, 2, false)
	tick(20)
	local cells = EverlookDBData.npc[9].p[1429]
	check(ns.GuidTrust.stable and cells["400:600"] == 2, "two spawns: " .. tostring(cells["400:600"]))
	unstubAll()
end)

step("unstable GUIDs: a creature you stand next to counts once by NPC and spot, again after 5 minutes out of sight", function()
	resetTrust()
	EverlookDBData.npc[8] = nil
	local w = plateWorld(8, 1, true)
	tick(30)
	local cells = EverlookDBData.npc[8].p[1429]
	check(not ns.GuidTrust.stable, "not distrusted")
	check(cells["400:600"] == 1, "30 s next to one creature: " .. tostring(cells["400:600"]))
	-- two plates of the same NPC on the same spot: we can't tell them apart, so one
	w.shown[2] = { namePlateUnitToken = "nameplate2" }
	tick(10)
	check(cells["400:600"] == 1, "same NPC, same spot, counted again: " .. cells["400:600"])
	-- out of sight for longer than 5 minutes: a new sighting
	w.shown[1], w.shown[2] = nil, nil
	tick(301)
	w.shown[1] = { namePlateUnitToken = "nameplate1" }
	tick(2)
	check(cells["400:600"] == 2, "back after 5 minutes: " .. cells["400:600"])
	unstubAll()
end)

step("unstable GUIDs: a corpse whose GUID differs per loot slot counts once; opened again soon, not again", function()
	resetTrust()
	ns.GuidTrust.stable = false
	stub("C_Map", {
		GetBestMapForUnit = function() return 1429 end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end,
	})
	local L = EverlookDBData.loot
	L["u:476"] = nil
	openLoot({ ["Creature-0-11-0-21-476-00000000F1"] = { 2589 }, ["Creature-0-12-0-22-476-00000000F2"] = { 2770 },
		["Creature-0-13-0-23-476-00000000F3"] = { 818 } })
	check(L["u:476"] and L["u:476"].n == 1, "one corpse counted " .. tostring(L["u:476"] and L["u:476"].n) .. " times")
	check(L["u:476"].i[2589][1] == 1 and L["u:476"].i[2770][1] == 1 and L["u:476"].i[818][1] == 1, "items lost")
	MOCK.time = MOCK.time + 5
	openLoot({ ["Creature-0-14-0-24-476-00000000F4"] = { 2589 } })
	check(L["u:476"].n == 1 and L["u:476"].i[2589][1] == 1, "the same corpse opened again was counted")
	MOCK.time = MOCK.time + 31
	openLoot({ ["Creature-0-15-0-25-476-00000000F5"] = { 2589 } })
	check(L["u:476"].n == 2 and L["u:476"].i[2589][1] == 2, "the next corpse half a minute later: " .. L["u:476"].n)
	unstubAll()
	-- stable GUIDs: two corpses of one NPC in one window are two
	resetTrust()
	L["u:477"] = nil
	openLoot({ ["Creature-0-1-2-3-477-00000000E1"] = { 2589 }, ["Creature-0-1-2-3-477-00000000E2"] = { 2589 } })
	check(L["u:477"].n == 2 and L["u:477"].i[2589][1] == 2, "stable: two corpses " .. L["u:477"].n)
	unstubAll()
end)

step("unstable GUIDs: a beast's level counts once per spot, not once per new GUID", function()
	resetTrust()
	ns.GuidTrust.stable = false
	EverlookDBData.npc[1132] = nil
	local n = 0
	stub("UnitGUID", function(u) if u == "target" then n = n + 1; return ("Creature-0-%d-0-0-1132-%010X"):format(n, n) end end)
	stub("UnitExists", function(u) return u == "target" end)
	stub("UnitIsPlayer", function() return false end)
	stub("UnitPlayerControlled", function() return false end)
	stub("UnitName", function(u) if u == "target" then return "Timber Wolf" end end)
	stub("UnitLevel", function() return 10 end)
	stub("UnitCreatureFamily", function() return "Wolf", 1 end)
	stub("UnitClassification", function() return "normal" end)
	stub("UnitCreatureType", function() return "Beast" end)
	stub("UnitReaction", function() return 2 end)
	stub("UnitHealthMax", function() return 100 end)
	stub("CheckInteractDistance", function() return false end)
	for _ = 1, 3 do MOCK.Fire("PLAYER_TARGET_CHANGED") end
	check(EverlookDBData.npc[1132].lvl[10] == 1, "level counted " .. tostring(EverlookDBData.npc[1132].lvl[10]) .. " times")
	unstubAll()
end)

step("a creature GUID of a shape we don't know records nothing and is counted for the self-test", function()
	resetTrust()
	local before = ns.GuidTrust.counts.badFormat
	stub("UnitGUID", function(u) if u == "target" then return "Creature-0-1-2-3333-00AB" end end)
	stub("UnitExists", function(u) return u == "target" end)
	stub("UnitIsPlayer", function() return false end)
	stub("UnitPlayerControlled", function() return false end)
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	check(EverlookDBData.npc[3333] == nil and EverlookDBData.npc[2] == nil, "a wrong id was saved")
	check(ns.GuidTrust.counts.badFormat == before + 1, "not counted")
	check(ns.parseGUID("Creature-0-1-2-3-6-0000AA0001") == "u" and ns.parseGUID("Creature-0-1-2-3-6") == nil, "parse")
	unstubAll()
end)

step("health: saved with the data as words and counts, never a GUID, a name or the realm", function()
	resetTrust()
	local cached = false
	local function f() end
	stub("GetItemInfo", function(id) if id == 2589 and cached then return "Linen Cloth" end end)
	-- the core APIs the mock doesn't have
	for _, name in ipairs({ "GetLootSourceInfo", "GetLootSlotLink", "GetNumLootItems", "GetMerchantItemLink", "GetMerchantNumItems", "GetQuestID" }) do
		if type(_G[name]) ~= "function" then stub(name, f) end
	end
	stub("C_QuestLog", { GetQuestObjectives = f })
	MOCK.Fire("PLAYER_LOGIN")
	local h = EverlookDBData.health
	check(h and h.build == "1.16.1.12345" and h.addon == "0.1.0-test", "build / addon: " .. tostring(h and h.build))
	check(EverlookDBData.build == "1.16.1.12345" and EverlookDBData.addon == "0.1.0-test", "data not tagged")
	check(h.realm == "ok" and h.item == "slow" and type(h.errors) == "number", "fields")
	check(h.missing == nil, "missing: " .. table.concat(h.missing or {}, ","))
	cached = true
	runTimers(2)
	check(h.item == "ok", "item info that loaded late: " .. tostring(h.item))
	check(h.guid == ns.GuidTrust.counts, "GUID counts not saved")
	check(not hasText(h, "Mock Realm") and not hasText(h, "Tester"), "a realm or name in the health")
	check(not hasText(EverlookDBData, "Creature-") and not hasText(EverlookDBData, "GameObject-")
		and not hasText(EverlookDBData, "Pet-0") and not hasText(EverlookDBData, "Player-"), "a GUID in the data file")
	-- the realm API answering "" (Forever since 71037), and a missing core API
	stub("GetRealmName", function() return "" end)
	_G.GetLootSourceInfo = nil
	MOCK.Fire("PLAYER_LOGIN")
	check(h.realm == "empty" and h.missing and h.missing[1] == "GetLootSourceInfo", "realm / missing: " .. tostring(h.realm))
	-- GUIDs found unstable stay distrusted on the next login with the same build; a new build starts again
	h.guid.changed = 2
	MOCK.Fire("PLAYER_LOGIN")
	check(not ns.GuidTrust.stable, "unstable GUIDs trusted again after a reload")
	stub("GetBuildInfo", function() return "1.16.2", "12399" end)
	MOCK.Fire("PLAYER_LOGIN")
	check(EverlookDBData.health.build == "1.16.2.12399" and EverlookDBData.health.guid.changed == 0, "counts carried into a new build")
	check(ns.GuidTrust.counts == EverlookDBData.health.guid, "the new counts are not the ones counted")
	unstubAll()
	resetTrust()
end)

step("quest item sparkles: on by default, kept on after a preset, the outline mode given back when turned off", function()
	-- a game with the outline CVars at High and no loot effect; SetCVar fires CVAR_UPDATE like the game
	local cv = { graphicsOutlineMode = "2", RAIDgraphicsOutlineMode = "1", outlineModeShowLootEffectWhenDisabled = "0" }
	local sets = 0
	stub("C_CVar", {
		GetCVar = function(n) return cv[n] end,
		SetCVar = function(n, v) sets = sets + 1; cv[n] = tostring(v); MOCK.Fire("CVAR_UPDATE", n, tostring(v)); return true end,
	})
	local s = EverlookDBSettings
	s.questSparkles, s.sparkleOutline = nil, nil
	ns.InitSettings(EverlookDBData)
	check(s.questSparkles == true, "not on by default")
	MOCK.Fire("PLAYER_LOGIN")
	runTimers(3)
	check(cv.graphicsOutlineMode == "0" and cv.RAIDgraphicsOutlineMode == "0" and cv.outlineModeShowLootEffectWhenDisabled == "1",
		"not applied at login: " .. cv.graphicsOutlineMode .. cv.outlineModeShowLootEffectWhenDisabled)
	check(ns.SparklesActive(), "not active")
	check(s.sparkleOutline.graphicsOutlineMode == "2" and s.sparkleOutline.RAIDgraphicsOutlineMode == "1", "old outline modes not kept")
	-- nothing is set when it is already right, and our own changes queue nothing
	MOCK.timers = {}
	sets = 0
	ns.SparklesApply()
	check(sets == 0, "set CVars that were already right")
	ns.SetSparkles(true)
	check(#MOCK.timers == 0, "our own CVar changes queued a re-apply")
	-- a graphics preset sets both back (as the game does, without our SetCVar): applied again a moment later,
	-- and the preset's outline mode is the one to give back
	cv.graphicsOutlineMode, cv.outlineModeShowLootEffectWhenDisabled = "1", "0"
	MOCK.Fire("CVAR_UPDATE", "graphicsOutlineMode", "1")
	MOCK.Fire("CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled", "0")
	check(#MOCK.timers == 1, "a preset should queue exactly one re-apply, got " .. #MOCK.timers)
	runTimers(1)
	check(cv.graphicsOutlineMode == "0" and cv.outlineModeShowLootEffectWhenDisabled == "1", "not applied after a preset")
	check(s.sparkleOutline.graphicsOutlineMode == "1", "the preset's outline mode not kept")
	cv.outlineModeShowLootEffectWhenDisabled = "0"
	MOCK.Fire("GX_RESTARTED")
	runTimers(1)
	check(ns.SparklesActive(), "lost after a graphics restart")
	-- off from chat: outline modes back, loot effect off, and it stays off after a preset
	SlashCmdList.EVERLOOKDB("sparkles off")
	check(s.questSparkles == false, "setting not off")
	check(cv.graphicsOutlineMode == "1" and cv.RAIDgraphicsOutlineMode == "1" and cv.outlineModeShowLootEffectWhenDisabled == "0",
		"not restored: " .. cv.graphicsOutlineMode .. cv.RAIDgraphicsOutlineMode .. cv.outlineModeShowLootEffectWhenDisabled)
	check(s.sparkleOutline == nil, "restore values left behind")
	cv.graphicsOutlineMode = "0"
	MOCK.Fire("CVAR_UPDATE", "graphicsOutlineMode", "0")
	runTimers(1)
	check(cv.outlineModeShowLootEffectWhenDisabled == "0", "applied while off")
	-- with no kept value the outline mode comes back as High
	SlashCmdList.EVERLOOKDB("set sparkles on")
	check(s.questSparkles == true and cv.outlineModeShowLootEffectWhenDisabled == "1", "on again")
	s.sparkleOutline = nil
	SlashCmdList.EVERLOOKDB("sparkles toggle")
	check(s.questSparkles == false and cv.graphicsOutlineMode == "2", "outline not High when nothing was kept: " .. cv.graphicsOutlineMode)
	-- a client without these CVars (or whose CVar API throws): nothing breaks
	stub("C_CVar", { GetCVar = function() error("no such cvar") end, SetCVar = function() error("nope") end })
	SlashCmdList.EVERLOOKDB("sparkles on")
	check(ns.SparklesApply() == false and not ns.SparklesActive(), "a missing CVar counted as applied")
	SlashCmdList.EVERLOOKDB("sparkles off")
	unstubAll()
	s.questSparkles = true
	check(not hasText(s, "Creature-") and not hasText(s, "Player-"), "a GUID in the settings")
end)

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
