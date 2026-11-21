-- Quest item sparkles: keeps the glitter on lootable quest objects visible in WoW: Forever.
-- The game shows that glitter only while the unit outline mode is off and outlineModeShowLootEffectWhenDisabled is
-- 1, and a graphics preset (or a graphics restart) sets both back. With the setting on (the default), this sets them
-- at login and again after any graphics change. Turning it off puts the outline mode back to what it was before
-- (High when we don't know) and clears the loot effect; the game may need a restart before the glitter is gone.
-- Our own code, written from the game's CVar names and the public description of Forever Loot Sparkles (GPL-3.0;
-- its code was not read). Only CVars are touched: no unit, GUID or combat log.
local _, ns = ...

local SHOW = "outlineModeShowLootEffectWhenDisabled"
local OUTLINES = { "graphicsOutlineMode", "RAIDgraphicsOutlineMode" }  -- the normal and raid graphics settings
local OFF, HIGH = "0", "2"
local WATCHED = { [SHOW:lower()] = true }
for _, name in ipairs(OUTLINES) do WATCHED[name:lower()] = true end

local applying = false  -- our own SetCVar calls are under way (their CVAR_UPDATE is not a player's change)
local pending = false   -- a re-apply is queued (a preset changes many CVars at once)

local function S() return EverlookDBSettings end

-- A CVar's value as a string, or nil when the game doesn't have it (or won't say).
local function getCVar(name)
  local f = (C_CVar and C_CVar.GetCVar) or GetCVar
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, name)
  if not ok or v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  if type(v) ~= "string" and type(v) ~= "number" then return nil end
  return tostring(v)
end

-- Set a CVar the game has to `value` (only when it differs). True when it now has that value.
local function setCVar(name, value)
  local now = getCVar(name)
  if now == nil then return false end
  if now == value then return true end
  local f = (C_CVar and C_CVar.SetCVar) or SetCVar
  if type(f) ~= "function" then return false end
  applying = true
  pcall(f, name, value)
  applying = false
  return getCVar(name) == value
end

-- The setting is on: outline off (remembering what it was) and the loot effect on.
function ns.SparklesApply()
  local s = S()
  if type(s) ~= "table" or not s.questSparkles then return false end
  s.sparkleOutline = type(s.sparkleOutline) == "table" and s.sparkleOutline or {}
  for _, name in ipairs(OUTLINES) do
    local v = getCVar(name)
    if v and v ~= OFF then s.sparkleOutline[name] = v end
    setCVar(name, OFF)
  end
  return setCVar(SHOW, "1")
end

-- The setting was turned off: put the outline mode back and stop showing the loot effect.
function ns.SparklesRestore()
  local s = S()
  local saved = type(s) == "table" and type(s.sparkleOutline) == "table" and s.sparkleOutline or {}
  for _, name in ipairs(OUTLINES) do
    if getCVar(name) == OFF then setCVar(name, saved[name] or HIGH) end
  end
  setCVar(SHOW, "0")
  if type(s) == "table" then s.sparkleOutline = nil end
end

-- On or off, from the window or chat.
function ns.SetSparkles(on)
  local s = S()
  if type(s) ~= "table" then return end
  s.questSparkles = on and true or false
  if on then ns.SparklesApply() else ns.SparklesRestore() end
end

-- Whether the glitter can show right now (for the window).
function ns.SparklesActive()
  if getCVar(SHOW) ~= "1" then return false end
  return getCVar(OUTLINES[1]) == OFF
end

local function later()
  if pending then return end
  pending = true
  local after = C_Timer and C_Timer.After
  local run = function() pending = false; pcall(ns.SparklesApply) end
  if type(after) == "function" then after(0.5, run) else run() end
end

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "CVAR_UPDATE", "GX_RESTARTED" }) do pcall(f.RegisterEvent, f, event) end
f:SetScript("OnEvent", function(_, event, name, value)
  local s = S()
  if event == "PLAYER_LOGIN" then return later() end  -- the settings are set up by then; applied just after
  if type(s) ~= "table" or not s.questSparkles or applying then return end
  -- Any other CVar change may be a preset: look again a moment later (only a few reads, and only when they differ).
  if event == "CVAR_UPDATE" and type(name) == "string" and WATCHED[name:lower()] then
    -- the player (or a preset) picked an outline mode: that is the one to give back when the setting goes off
    for _, cvar in ipairs(OUTLINES) do
      if cvar:lower() == name:lower() then
        local v = value ~= nil and tostring(value) or getCVar(cvar)
        if v and v ~= OFF then
          s.sparkleOutline = type(s.sparkleOutline) == "table" and s.sparkleOutline or {}
          s.sparkleOutline[cvar] = v
        end
      end
    end
  end
  later()
end)
