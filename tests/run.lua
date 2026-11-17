-- Offline tests for EverlookDB Collector against wowmock.lua: settings live apart from the uploaded data
-- (and `paused` moves out of it), every slash command, the save reminder option and the window.
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
	check(MOCK.log[1]:find("1 NPCs, 1 loot sources %(3 looted%)") and MOCK.log[2]:find("SavedVariables", 1, true), "status: " .. table.concat(MOCK.log, " / "))
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
	for _, c in ipairs({ "save", "pause", "resume", "status", "feedback" }) do check(s:find("/edb " .. c, 1, true), "help lacks " .. c) end
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

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
