-- An update that adds files, then /reload without restarting the game: the game runs the new EverlookDB.lua and
-- Options.lua but not the files it didn't know at start (Guard.lua, Care.lua, Report.lua). It must keep recording.
local ROOT = ...
local ns = {}
time, date = os.time, os.date
GetBuildInfo = function() return "1.60.1", "71037" end
C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end }
C_NamePlate = { GetNamePlates = function() return {} end }
C_TooltipInfo = { GetUnit = function() return nil end }
GetInstanceInfo = function() return "Elwynn", "none" end
C_UI = { Reload = function() end }
EverlookDBData = { format = 1, locale = "enUS", since = 1794560502, npc = { [1] = { name = "Kobold" } }, loot = { ["u:1"] = { n = 3, i = {} } } }
EverlookDBSettings = nil
local env = setmetatable({}, { __index = _G, __newindex = function(_, k, v) _G[k] = v end })
for _, file in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/EverlookUI/EverlookUI.lua", "EverlookDB.lua", "Health.lua", "Beasts.lua", "Sparkles.lua", "Options.lua" }) do
	local chunk = assert(loadfile(ROOT .. "/" .. file))
	setfenv(chunk, env)
	chunk("EverlookDB", ns)
end
local realPrint = print
print = function(s) MOCK.log[#MOCK.log + 1] = tostring(s) end
MOCK.Fire("PLAYER_LOGIN"); MOCK.Fire("PLAYER_ENTERING_WORLD"); MOCK.RunTimers()
GetNumLootItems = function() return 1 end
GetLootSlotLink = function() return "|Hitem:2589:|h[Linen Cloth]|h" end
GetLootSourceInfo = function() return "Creature-0-1-2-3-6-0000AA0001", 1 end
IsFishingLoot = function() return false end
GetMoney = function() return 0 end
MOCK.Fire("LOOT_READY"); MOCK.Fire("LOOT_OPENED"); MOCK.Fire("LOOT_CLOSED")
MOCK.Fire("PLAYER_LOGOUT")
MOCK.log = {}
SlashCmdList.EVERLOOKDB("status")
SlashCmdList.EVERLOOKDB("errors")
SlashCmdList.EVERLOOKDB("")
SlashCmdList.EVERLOOKDB("loot")
print = realPrint
local out = table.concat(MOCK.log, "\n")
local failures = {}
if not (EverlookDBData.loot["u:6"] and EverlookDBData.loot["u:6"].n == 1) then failures[#failures + 1] = "loot not recorded without the new files" end
if EverlookDBData.npc[1].name ~= "Kobold" then failures[#failures + 1] = "data lost" end
if not out:find("Restart the game to finish the update", 1, true) then failures[#failures + 1] = "status doesn't ask for a restart: " .. out end
if not out:find("dungeon loot comes with it", 1, true) then failures[#failures + 1] = "/edb loot doesn't ask for a restart" end
if #MOCK.errors > 0 then failures[#failures + 1] = table.concat(MOCK.errors, "\n") end
print(#failures == 0 and "  ok   updated without a restart: it keeps recording and says to restart" or ("  FAIL updated without a restart\n         " .. table.concat(failures, "\n         ")))
return #failures
