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

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
