-- EverlookDB Collector: the window (/edb), chat commands and the Settings > AddOns entry, on EverlookUI.
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")

local FILE = "World of Warcraft\\_forever_\\WTF\\Account\\<your account>\\SavedVariables\\EverlookDB.lua"
local UPLOAD_URL = "https://everlookdb.com/contribute.html"

local app = UI:NewApp({
  name = "EverlookDB Collector",
  addon = ADDON,
  slash = "/edb",
  frameName = "EverlookDB",
  tagline = "Notes loot, vendors, quests and where NPCs and nodes are while you play, for EverlookDB.com. Saves nothing about you.",
  accent = { 1.0, 0.824, 0.0 }, -- EverlookDB gold
  position = function() return EverlookDBSettings end,
  feedbackURL = "https://github.com/quikmn/EverlookDB/issues",
})
ns.app = app

local function S() return EverlookDBSettings end

app:Setting({
  key = "savedmessage", type = "bool", label = "Say \"data saved\" in chat after a save",
  get = function() return S().savedMessage end, set = function(v) S().savedMessage = v end,
})

local function SetPaused(on)
  ns.SetPaused(on)
  app:Refresh()
  app:Print(on and "paused. /edb resume to record again." or "recording.")
end

local function StatusLine()
  local s = ns.Status()
  return ("%s. %d NPCs, %d loot sources (%d looted), %d objects, %d vendors, %d trainers, %d quests."):format(
    ns.IsPaused() and "paused" or "recording", s.npcs, s.loot, s.looted, s.objects, s.vendors, s.trainers, s.quests)
end

app:Command("save", "save", "write the data file now (reloads the UI)", function() ns.Save() end)
app:Command("pause", "pause", "stop recording", function() SetPaused(true) end)
app:Command("resume", "resume", "record again", function() SetPaused(false) end)
app:Command("status", "status", "what's recorded so far, in chat (what a bare /edb used to print)", function()
  app:Print(StatusLine())
  app:Print("Upload " .. FILE .. " on EverlookDB.com, or let the EverlookDB App do it.")
end)
app:Command("feedback", "feedback", "a link for bugs and ideas", function() app:ShowFeedback() end, { "bug" })

local function N(key) return function() return tostring(ns.Status()[key]) end end

app:Section("status", "Status", function(stack)
  UI.Header(stack, "Recording", "It runs in the background while you play. Nothing to set up.")
  UI.Stat(stack, "Now", function() return ns.IsPaused() and "|cffef5d5dpaused|r" or "|cff62cf88recording|r" end)
  UI.ButtonRow(stack, {
    { label = "Pause", width = 140, onClick = function() SetPaused(not ns.IsPaused()) end },
    refresh = function(row) row.buttons[1]:SetText(ns.IsPaused() and "Resume" or "Pause") end,
  })
  UI.Header(stack, "Recorded so far", "Everything in your data file, from all your play since it started.")
  UI.Stat(stack, "NPCs", N("npcs"))
  UI.Stat(stack, "Loot sources", function() local s = ns.Status(); return s.loot .. "  (" .. s.looted .. " times looted)" end)
  UI.Stat(stack, "Herbs, veins, chests", N("objects"))
  UI.Stat(stack, "Vendors", N("vendors"))
  UI.Stat(stack, "Trainers", N("trainers"))
  UI.Stat(stack, "Quests", N("quests"))
  UI.Stat(stack, "Collecting since", function() local t = ns.Status().since; return t and date("%Y-%m-%d", t) or "-" end)

  UI.Header(stack, "Saving and uploading", "The game writes the data file only when you log out or reload.")
  UI.Stat(stack, "Changed since the last save", function() return ns.Status().unsaved .. " records" end)
  UI.Stat(stack, "Last saved", function()
    local t = ns.Status().lastSave
    return t and date("%Y-%m-%d %H:%M", t) or "when you last logged out"
  end)
  UI.ButtonRow(stack, {
    { label = "Save now (reloads the UI)", width = 220, style = "accent", onClick = function() ns.Save() end },
  })
  UI.Note(stack, "Then upload the file: the EverlookDB App (free, on everlookdb.com) uploads it by itself after you play, or upload it by hand on the site.")
  UI.CopyBox(stack, "The file", FILE)
  UI.CopyBox(stack, "Upload page", UPLOAD_URL)
end)

app:Section("records", "What it records", function(stack)
  UI.Header(stack, "What it records", "Game facts only, for drop rates, maps, vendors and quests on EverlookDB.com.")
  UI.Note(stack, "|cffe6e8eeLoot|r  what each mob dropped, what skinning and pickpocketing gave, and what came from herbs, ore veins, chests and fishing. Each corpse or node counts once, which is what gives drop rates.")
  UI.Note(stack, "|cffe6e8eeNPCs|r  name, level, type and family, rare or elite, skinnable, health per level, the zones they are in, and where they stand. Positions are taken only when you are within about 10 yards, so they are accurate.")
  UI.Note(stack, "|cffe6e8eeServices|r  flight masters, bankers, auctioneers, stable masters, innkeepers and trainers, and what each trainer teaches, for how much, from which level.")
  UI.Note(stack, "|cffe6e8eeVendors|r  what they sell, the price, the stack size and whether stock is limited.")
  UI.Note(stack, "|cffe6e8eeQuests|r  who starts and ends each quest and where, the lowest level it was offered at, objectives, required items, rewards and XP.")
  UI.Note(stack, "|cffe6e8eeXP|r  the XP a kill gave when you play solo.")
end)

app:Section("privacy", "Privacy", function(stack)
  UI.Header(stack, "Privacy", "It never records anything about you.")
  UI.Note(stack, "Never recorded: your character, realm or account name, other players, chat, your gear or bags.")
  UI.Note(stack, "Quest text the game fills in with your character's name is never saved. A player's corpse or your own name is never taken as the name of something you loot.")
  UI.Note(stack, "Your level is used only to note the lowest level a quest was offered at and the XP a kill or quest gave at your level.")
  UI.Note(stack, "Your settings for this window (pause, the chat message, the window position) are kept apart from the recorded data; the site reads only the game facts.")
  UI.Note(stack, "Uploads are merged with other players' into drop rates and maps. EverlookDB doesn't keep the file itself or anything that identifies you. More on everlookdb.com/privacy.html.")
end)

app:Section("options", "Options", function(stack)
  UI.Header(stack, "Saving")
  app:Widget(stack, "savedmessage")
  UI.Header(stack, "Chat commands")
  UI.Note(stack, "/edb  this window\n/edb save  write the data file now (reloads the UI)\n/edb pause, /edb resume\n/edb status  what's recorded, in chat\n/edb feedback  a link for bugs and ideas\n/edb savedmessage off  change a setting (/edb settings lists them)\n/edb help  all of this in chat")
end)

SLASH_EVERLOOKDB1 = "/edb"
SLASH_EVERLOOKDB2 = "/everlookdb"
SlashCmdList.EVERLOOKDB = function(msg)
  if not ns.Ready() then return end -- before PLAYER_LOGIN there is nothing to show yet
  app:HandleSlash(msg)
end
