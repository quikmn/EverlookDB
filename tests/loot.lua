-- The dungeon loot browser (Loot.lua, LootData.lua): the data is whole, the window opens on /edb loot and lists a
-- dungeon's bosses and drops, search and filters work, the class rules hold, clicks link and try on, and item
-- tooltips say where an item drops. Shares run.lua's helpers.
local D, L = ns.LootData, ns.Loot

step("loot data: every dungeon has bosses, every drop row parses and names an item in the data", function()
	check(type(D) == "table" and type(L) == "table", "Loot.lua or LootData.lua not loaded")
	check(#D.instances >= 30, "only " .. #D.instances .. " dungeons and raids")
	check(type(D.credit) == "string" and D.credit:find("ForeverDB.net", 1, true), "ForeverDB's credit line missing")
	local rows, kinds = 0, {}
	for _, inst in ipairs(D.instances) do
		check(type(inst.name) == "string" and (inst.kind == "d" or inst.kind == "r"), "instance shape: " .. tostring(inst.name))
		check(type(inst.map) == "number", "no map for " .. inst.name)
		for _, b in ipairs(inst.bosses) do
			check(type(b[1]) == "string" and type(b[2]) == "number" and b[2] > 0, "boss shape in " .. inst.name)
			for _, r in ipairs(L.BossRows(inst, b)) do
				rows = rows + 1
				kinds[r.src] = true
				check(L.Item(r.id), "no item " .. r.id .. " (" .. b[1] .. ")")
				check(r.src ~= "p" or (r.n and r.n > 0 and r.drops and r.drops > 0), "players' row without its sample")
				check(r.chance == nil or (r.chance > 0 and r.chance <= 1), "chance out of range")
			end
		end
		for _, r in ipairs(L.BossRows(inst)) do
			check(L.Item(r.id) and r.npc, "trash row " .. r.id .. " in " .. inst.name)
		end
	end
	check(rows > 1500, "only " .. rows .. " boss drops")
	for _, k in ipairs({ "p", "f", "e", "a" }) do check(kinds[k], "no drops from source " .. k) end
	local it = L.Item(5191)
	check(it and it.name == "Cruel Barb" and it.q == 3 and it.inv == 13, "Cruel Barb: " .. tostring(it and it.name))
end)

step("loot words: chances, estimates, small samples and slots read as players say them", function()
	check(L.ChanceText({ src = "p", chance = 0.1234, drops = 44, n = 360 }) == "12%", "players' chance")
	check(L.ChanceText({ src = "p", chance = 0.5, drops = 2, n = 4 }) == "2 of 4", "small sample")
	check(L.ChanceText({ src = "e", chance = 0.025 }) == "~2.5%", "estimate: " .. L.ChanceText({ src = "e", chance = 0.025 }))
	check(L.ChanceText({ src = "f", chance = 0.003 }) == "0.3%", "small chance")
	check(L.ChanceText({ src = "a" }) == "?", "unknown chance")
	check(L.ChanceNote({ src = "p", drops = 1, n = 3 }):find("Too few", 1, true), "small sample note")
	check(L.Describe({ inv = 1, cls = 4, sub = 4, ilvl = 52, req = 47 }):find("Plate", 1, true), "describe plate head")
end)

step("loot class rules: armor type, weapons, shields and class-only items", function()
	local plate = { cls = 4, sub = 4, inv = 5, classes = -1 }
	local cloak = { cls = 4, sub = 1, inv = 16, classes = -1 }
	local wand = { cls = 2, sub = 19, inv = 26, classes = -1 }
	local shield = { cls = 4, sub = 6, inv = 14, classes = -1 }
	local mageOnly = { cls = 4, sub = 1, inv = 1, classes = 128 }
	check(L.Usable(plate, "WARRIOR", 1) and not L.Usable(plate, "MAGE", 8), "plate")
	check(L.Usable(cloak, "WARRIOR", 1) and L.Usable(cloak, "MAGE", 8), "cloaks are for everyone")
	check(L.Usable(wand, "PRIEST", 5) and not L.Usable(wand, "ROGUE", 4), "wands")
	check(L.Usable(shield, "SHAMAN", 7) and not L.Usable(shield, "DRUID", 11), "shields")
	check(L.Usable(mageOnly, "MAGE", 8) and not L.Usable(mageOnly, "PRIEST", 5), "class mask")
	check(L.Passes({ cls = 9, sub = 1, inv = 0 }, { slot = "recipe" }) and not L.Passes(plate, { slot = "recipe" }), "recipes slot")
	check(L.Passes(plate, { slot = "chest", armor = 4 }) and not L.Passes(plate, { armor = 2 }), "slot and armor")
end)

step("/edb loot opens the browser on a dungeon, its bosses and drops; search and filters narrow it", function()
	MOCK.log = {}
	SlashCmdList.EVERLOOKDB("loot")
	local w = EverlookDBLootWindow
	check(w and w:IsShown() and L.IsShown(), "window not shown")
	check(type(EverlookDBSettings.loot) == "table" and EverlookDBSettings.loot.instance, "no instance chosen")
	check(EverlookDBData.loot == nil or EverlookDBData.lootBrowser == nil, "browser state in the uploaded data")
	-- Deadmines, Edwin VanCleef
	local dm
	for i, inst in ipairs(D.instances) do if inst.name == "Deadmines" then dm = inst end end
	check(dm, "no Deadmines")
	EverlookDBSettings.loot.instance, EverlookDBSettings.loot.boss = dm.id, #dm.bosses
	L.Refresh()
	local hits = L.Search("cruel barb", {}, 50)
	check(#hits >= 1 and hits[1].inst.name == "Deadmines" and hits[1].boss == "Edwin VanCleef", "search by item")
	local boss = L.Search("vancleef", {}, 200)
	check(#boss >= 5, "search by boss name: " .. #boss)
	check(#L.Search("vancleef", { slot = "onehand" }, 200) < #boss, "slot filter doesn't narrow the search")
	w.search:SetText("barb")
	w.search:GetScript("OnTextChanged")(w.search)
	check(w.itemsTitle:GetText():find("barb", 1, true), "search title: " .. tostring(w.itemsTitle:GetText()))
	SlashCmdList.EVERLOOKDB("loot")
	check(not w:IsShown(), "/edb loot doesn't close it again")
	SlashCmdList.EVERLOOKDB("loot vancleef")
	check(w:IsShown() and w.search:GetText() == "vancleef", "/edb loot <words> doesn't search")
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
	w:Hide()
end)

step("loot clicks: shift links the game's own link in chat, ctrl tries it on", function()
	local linked, dressed
	stub("GetItemInfo", function(id) return "Cruel Barb", "|cff0070dd|Hitem:" .. id .. "::::::::60:::::|h[Cruel Barb]|h|r" end)
	stub("C_Item", nil)
	stub("ChatEdit_InsertLink", function(l) linked = l return true end)
	stub("DressUpItemLink", function(l) dressed = l end)
	MOCK.mods.shift = true
	check(L.Click(5191) and linked and linked:find("item:5191", 1, true), "shift-click didn't link")
	MOCK.mods.shift = false
	stub("IsControlKeyDown", function() return true end)
	check(L.Click(5191) and dressed and dressed:find("item:5191", 1, true), "ctrl-click didn't try it on")
	stub("IsControlKeyDown", function() return false end)
	check(not L.Click(5191), "a plain click did something")
	unstubAll()
end)

step("loot tooltips: an item's tooltip says where it drops; the setting turns it off", function()
	local lines = {}
	local tip = { AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " " .. b end, AddLine = function(_, a) lines[#lines + 1] = a end }
	L.AddWhere(tip, 5191)
	check(#lines >= 1 and lines[1]:find("Edwin VanCleef, Deadmines", 1, true), "where line: " .. tostring(lines[1]))
	lines = {}
	SlashCmdList.EVERLOOKDB("loottooltip off")
	check(EverlookDBSettings.lootTooltip == false, "setting not off")
	L.AddWhere(tip, 5191)
	check(#lines == 0, "lines with the setting off")
	SlashCmdList.EVERLOOKDB("loottooltip on")
	lines = {}
	L.AddWhere(tip, 2589) -- Linen Cloth: drops everywhere, listed nowhere
	check(#lines == 0, "a world drop got dungeon lines")
end)
