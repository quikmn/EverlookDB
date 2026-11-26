-- EverlookDB Collector: the window (/edb), chat commands and the Settings > AddOns entry, on EverlookUI.
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")

local FILE = "World of Warcraft\\_forever_\\WTF\\Account\\<your account>\\SavedVariables\\EverlookDB.lua"
local UPLOAD_URL = "https://everlookdb.com/contribute.html"

local app = UI:NewApp({
  name = "EverlookDB Collector",
  addon = ADDON,
  slash = "/edb",
  aliases = { "/everlookdb" },
  frameName = "EverlookDB",
  tagline = "Notes loot, vendors, quests and where NPCs and nodes are while you play, for EverlookDB.com. Saves nothing about you.",
  accent = { 1.0, 0.824, 0.0 }, -- EverlookDB gold
  position = function() return EverlookDBSettings end,
  feedbackURL = "https://github.com/quikmn/EverlookDB/issues",
})
ns.app = app

local function S() return EverlookDBSettings end

app:Setting({
  key = "savedmessage", type = "bool", label = "Say \"data saved\" in chat after a save", keywords = { "message", "notification", "quiet", "announce" },
  get = function() return S().savedMessage end, set = function(v) S().savedMessage = v end,
})

app:Setting({
  key = "problemmessage", type = "bool", label = "Say in chat when something goes wrong while recording",
  desc = "One line a session at most. /edb status always says what happened.",
  keywords = { "error", "problem", "warning", "message", "quiet" },
  get = function() return S().problemMessage end, set = function(v) S().problemMessage = v end,
})

app:Setting({
  key = "sparkles", type = "bool", label = "Show quest item sparkles",
  desc = "Keeps the glitter on quest objects you can loot, even after a graphics preset turns it off.",
  keywords = { "sparkle", "glitter", "shine", "quest item", "loot effect", "outline", "highlight", "graphics" },
  get = function() return S().questSparkles end, set = function(v) ns.SetSparkles(v) end,
})

local function SetPaused(on)
  ns.SetPaused(on)
  app:Refresh()
  app:Print(on and "paused. /edb resume to record again." or "recording.")
end

local function StatusLine()
  local s = ns.Status()
  local line = ("Recorded: %d NPCs, %d loot sources (%d looted), %d objects, %d vendors, %d trainers, %d quests, %d items' sources."):format(
    s.npcs, s.loot, s.looted, s.objects, s.vendors, s.trainers, s.quests, s.got or 0)
  local beasts, tames, lore = ns.BeastStatus()
  if beasts > 0 then line = line .. (" Beast abilities: %d beasts (%d tames, %d Beast Lore reads)."):format(beasts, tames, lore) end
  return line
end

-- /edb on, off, toggle: recording (/edb pause and /edb resume still work). status and feedback come from EverlookUI.
app:OnOff({ label = "Recording", get = function() return not ns.IsPaused() end, set = function(on) ns.SetPaused(not on) end })
app:StatusLines(function()
  local lines = { StatusLine() }
  for _, l in ipairs(ns.ReportLines()) do lines[#lines + 1] = l end
  lines[#lines + 1] = "Upload " .. FILE .. " on EverlookDB.com, or let the EverlookDB App do it."
  return lines
end)
app:Command("errors", "errors", "what went wrong while recording, if anything", function()
  for _, l in ipairs(ns.ErrorLines()) do app:Print(l) end
end)
-- the dungeon loot browser lives in Loot.lua; a /reload after an update that added it doesn't load it yet
app:Command("loot", "loot [words]", "dungeon loot: what drops where; with words, it searches all loot", function(rest)
  if ns.Loot then ns.Loot.Command(rest) return end
  app:Print("restart the game to finish the update: dungeon loot comes with it.")
end, { "dungeons", "drops" })
app:Command("save", "save", "write the data file now (reloads the UI)", function() ns.Save() end)
app:Command("pause", "pause", "stop recording", function() SetPaused(true) end).hidden = true
app:Command("resume", "resume", "record again", function() SetPaused(false) end).hidden = true

local function N(key) return function() return tostring(ns.Status()[key]) end end

app:Section("status", "Status", function(stack)
  UI.Header(stack, "Recording", "It runs in the background while you play. Nothing to set up.")
  UI.Stat(stack, "Now", function() return ns.IsPaused() and "|cffef5d5dpaused|r" or "|cff62cf88recording|r" end)
  UI.ButtonRow(stack, {
    { label = "Pause", width = 140, onClick = function() SetPaused(not ns.IsPaused()) end,
      keywords = { "resume", "stop", "recording", "collecting" } },
    refresh = function(row) row.buttons[1]:SetText(ns.IsPaused() and "Resume" or "Pause") end,
  })
  UI.Header(stack, "Recorded so far", "Everything in your data file, from all your play since it started.")
  UI.Stat(stack, "NPCs", N("npcs"))
  UI.Stat(stack, "Loot sources", function() local s = ns.Status(); return s.loot .. "  (" .. s.looted .. " times looted)" end)
  UI.Stat(stack, "Herbs, veins, chests", N("objects"))
  UI.Stat(stack, "Vendors", N("vendors"))
  UI.Stat(stack, "Trainers", N("trainers"))
  UI.Stat(stack, "Quests", N("quests"))
  UI.Stat(stack, "Where items came from", N("got"))
  UI.Stat(stack, "Beasts (hunters)", function()
    local beasts, tames, lore = ns.BeastStatus()
    if beasts == 0 then return "none yet" end
    return beasts .. "  (" .. tames .. " tames, " .. lore .. " Beast Lore reads)"
  end)
  UI.Stat(stack, "Collecting since", function() local t = ns.Status().since; return t and date("%Y-%m-%d", t) or "-" end)

  UI.Header(stack, "Lately", "What was recorded where, newest first. /edb status shows the same in chat.")
  -- whole lines that wrap: a place's line is far longer than a value column
  UI.Note(stack, function()
    local l = ns.RecentLines()
    if #l == 0 then return "Nothing recorded since you logged in yet." end
    return table.concat(l, "\n\n")
  end)
  UI.Note(stack, function()
    local _, g = ns.CoverageLine()
    if not g then return "" end
    return ("|cffe6e8eeWhere the NPCs are|r: %d on the map, %d roughly, %d in dungeons, %d only by zone, %d nowhere yet."):format(g.exact, g.approx, g.inst, g.zoneOnly, g.noLoc)
  end)
  UI.Note(stack, function()
    local p = ns.Problems()
    if #p == 0 then return "|cffe6e8eeProblems|r: |cff62cf88none|r" end
    return "|cffe6e8eeProblems|r: |cffef5d5d" .. #p .. "|r  " .. table.concat(p, "\n")
  end)

  UI.Header(stack, "Saving and uploading", "The game writes the data file only when you log out or reload.")
  UI.Stat(stack, "Changed since the last save", function() return ns.Status().unsaved .. " records" end)
  UI.Stat(stack, "Last saved", function()
    local t = ns.Status().lastSave
    return t and date("%Y-%m-%d %H:%M", t) or "when you last logged out"
  end)
  UI.ButtonRow(stack, {
    { label = "Save now (reloads the UI)", width = 220, style = "accent", onClick = function() ns.Save() end,
      keywords = { "reload", "write", "upload", "file" } },
  })
  UI.Note(stack, "Then upload the file: the EverlookDB App (free, on everlookdb.com) uploads it by itself after you play, or upload it by hand on the site.")
  UI.CopyBox(stack, "The file", FILE)
  UI.CopyBox(stack, "Upload page", UPLOAD_URL)
end)

app:Section("records", "What it records", function(stack)
  UI.Header(stack, "What it records", "Game facts only, for drop rates, maps, vendors and quests on EverlookDB.com.")
  UI.Note(stack, "|cffe6e8eeLoot|r  what each mob dropped, what skinning and pickpocketing gave, and what came from herbs, ore veins, chests and fishing. Each corpse or node counts once, which is what gives drop rates.")
  UI.Note(stack, "|cffe6e8eeNPCs|r  name, level, type and family, rare or elite, skinnable, health per level, the zones and dungeons they are in, and where they stand. Exact positions are taken only when you are within about 10 yards; within about 28 yards a rough spot is noted apart.")
  UI.Note(stack, "|cffe6e8eeServices|r  flight masters, bankers, auctioneers, stable masters, innkeepers and trainers, and what each trainer teaches, for how much, from which level.")
  UI.Note(stack, "|cffe6e8eeVendors|r  what they sell, the price, the stack size and whether stock is limited (and how many at most).")
  UI.Note(stack, "|cffe6e8eeWhere items came from|r  when an item reaches your bags without a loot window: bought from which vendor, given by an NPC or on taking a quest, made by a craft or by using an item, or sent by an NPC's mail. What a clam, lockbox or other item opened from your bags held, and what disenchanting gave. Never trades, players' mail or the auction house.")
  UI.Note(stack, "|cffe6e8eeQuests|r  who starts and ends each quest and where, the lowest level it was offered at, objectives, required items, rewards (items and currencies) and XP, and what handing it in actually gave you.")
  UI.Note(stack, "|cffe6e8eeXP|r  the XP a kill gave when you play solo.")
  UI.Note(stack, "|cffe6e8eeHunters|r  when you tame a beast: which beast it was and its level, and what the new pet knows in its first 30 seconds (its abilities and ranks, Faster or Slower Attack, attack speed, level, family, training points and diet). When you cast Beast Lore: the lines it adds to the beast's tooltip, the beast and its level. Never the pet's name. Kept as counts with the game version and the week, never the day or time.")
end)

app:Section("privacy", "Privacy", function(stack)
  UI.Header(stack, "Privacy", "It never records anything about you.")
  UI.Note(stack, "Never recorded: your character, realm or account name, other players, chat, your gear or bags, or your pets' names.")
  UI.Note(stack, "Quest text the game fills in with your character's name is never saved. A player's corpse or your own name is never taken as the name of something you loot.")
  UI.Note(stack, "Your level is used only to note the lowest level a quest was offered at and the XP a kill or quest gave at your level.")
  UI.Note(stack, "Your settings for this window (pause, the chat message, quest item sparkles and the outline mode to give back, the window position) are kept apart from the recorded data; the site reads only the game facts.")
  UI.Note(stack, "Uploads are merged with other players' into drop rates and maps. EverlookDB doesn't keep the file itself or anything that identifies you. More on everlookdb.com/privacy.html.")
end)

app:Section("options", "Options", function(stack)
  UI.Header(stack, "Saving")
  app:Widget(stack, "savedmessage")
  app:Widget(stack, "problemmessage")
  UI.Header(stack, "Quest items")
  app:Widget(stack, "sparkles")
  UI.Note(stack, "It switches the unit outline off (Graphics > Outline Mode), because the game only shows the glitter without it. Turning this off gives your outline mode back; restart the game if the glitter stays.")
  UI.Header(stack, "Chat commands")
  UI.Note(stack, "/edb  this window\n/edb loot  dungeon loot: what drops where\n/edb off, /edb on  pause or resume recording\n/edb sparkles off  stop keeping quest item sparkles on\n/edb save  write the data file now (reloads the UI)\n/edb status  what's recorded, in chat\n/edb savedmessage off  change a setting (/edb get lists them)\n/edb search <words>  find a setting\n/edb feedback  a link for bugs and ideas\n/edb help  all of this in chat")
end)

-- /edb, also /everlookdb. Before PLAYER_LOGIN there is nothing to show yet.
app:RegisterSlash("EVERLOOKDB", function() return not ns.Ready() end)
