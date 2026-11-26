-- EverlookDB Collector: the dungeon loot browser (/edb loot). Pick a dungeon or raid, then a boss (or its trash), and
-- see what drops with how often; search all loot; filter by your class, armor type and slot. Data: LootData.lua,
-- written by Quarry's tools/loot_addon_data.py. Reads your bags only to tick what you already have; saves nothing
-- but the window's place and filters (EverlookDBSettings.loot).
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")
local U = UI.Util
local app = ns.app
local D = ns.LootData
if not app or not D then return end

local Loot = {}
ns.Loot = Loot

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
local itemCache = {}

-- { id, name, q, ilvl, inv, cls, sub, req, classes } of an item in the data, or nil.
function Loot.Item(id)
  local it = itemCache[id]
  if it ~= nil then return it or nil end
  local s = D.items[id]
  if not s then itemCache[id] = false return nil end
  local name, q, ilvl, inv, cls, sub, req, classes = s:match("^(.-)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)$")
  if not name then itemCache[id] = false return nil end
  it = { id = id, name = name, q = tonumber(q), ilvl = tonumber(ilvl), inv = tonumber(inv), cls = tonumber(cls),
    sub = tonumber(sub), req = tonumber(req), classes = tonumber(classes) }
  itemCache[id] = it
  return it
end

-- A loot string as rows: { id, chance (0..1 or nil), src, drops, n, npc }.
function Loot.Parse(s, trash)
  local rows = {}
  for entry in (s or ""):gmatch("%S+") do
    local f = {}
    for part in entry:gmatch("[^:]+") do f[#f + 1] = part end
    local id, ch, src = tonumber(f[1]), tonumber(f[2]) or 0, f[3]
    if id and src then
      local r = { id = id, chance = ch > 0 and ch / 10000 or nil, src = src }
      local k = 4
      if src == "p" then r.drops, r.n, k = tonumber(f[4]), tonumber(f[5]), 6 end
      if trash then r.npc = tonumber(f[k]) end
      rows[#rows + 1] = r
    end
  end
  return rows
end

local parsed = setmetatable({}, { __mode = "k" })
-- The rows of a boss ({ name, npc, loot }) or of an instance's trash.
function Loot.BossRows(inst, b)
  local key = b or inst
  if not parsed[key] then
    if b then parsed[key] = Loot.Parse(b[3]) else parsed[key] = Loot.Parse(inst.trash, true) end
  end
  return parsed[key]
end

function Loot.Instances() return D.instances end

-- Every drop of every boss: { row, inst, boss name or nil (trash) }, built on first use.
local everything
function Loot.All()
  if everything then return everything end
  everything = {}
  for _, inst in ipairs(D.instances) do
    for _, b in ipairs(inst.bosses) do
      for _, r in ipairs(Loot.BossRows(inst, b)) do everything[#everything + 1] = { row = r, inst = inst, boss = b[1] } end
    end
    for _, r in ipairs(Loot.BossRows(inst)) do everything[#everything + 1] = { row = r, inst = inst } end
  end
  return everything
end

-- item -> { { row, inst, boss }, ... } (best chance first), for "where does this drop".
local byItem
function Loot.WhereDrops(id)
  if not byItem then
    byItem = {}
    for _, e in ipairs(Loot.All()) do
      local l = byItem[e.row.id]
      if not l then l = {}; byItem[e.row.id] = l end
      l[#l + 1] = e
    end
    for _, l in pairs(byItem) do table.sort(l, function(a, b) return (a.row.chance or 0) > (b.row.chance or 0) end) end
  end
  return byItem[id]
end

------------------------------------------------------------------------
-- Words
------------------------------------------------------------------------
local SLOT_NAMES = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Trinket", [13] = "One-Hand", [14] = "Shield", [15] = "Ranged",
  [16] = "Back", [17] = "Two-Hand", [18] = "Bag", [19] = "Tabard", [20] = "Chest", [21] = "Main Hand", [22] = "Off Hand",
  [23] = "Held In Off-hand", [24] = "Ammo", [25] = "Thrown", [26] = "Ranged", [28] = "Relic",
}
local SLOT_GLOBALS = {
  [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST",
  [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND",
  [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED",
  [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [18] = "INVTYPE_BAG", [19] = "INVTYPE_TABARD", [20] = "INVTYPE_ROBE",
  [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE", [24] = "INVTYPE_AMMO",
  [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC",
}
local ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield", [7] = "Libram", [8] = "Idol", [9] = "Totem" }
local WEAPON = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm", [7] = "Sword",
  [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [14] = "Miscellaneous", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow",
  [19] = "Wand", [20] = "Fishing Pole" }

local function slotName(inv)
  local g = SLOT_GLOBALS[inv] and _G[SLOT_GLOBALS[inv]]
  return type(g) == "string" and g or SLOT_NAMES[inv]
end

local function subName(it)
  local get = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
  if get then
    local ok, n = pcall(get, it.cls, it.sub)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  if it.cls == 4 then return ARMOR[it.sub] elseif it.cls == 2 then return WEAPON[it.sub] end
end

-- "Head · Plate · item level 52 · level 47"
function Loot.Describe(it)
  local parts = {}
  local slot = it.inv > 0 and slotName(it.inv)
  if slot then parts[#parts + 1] = slot end
  if it.cls == 4 and it.sub >= 1 and it.sub <= 4 and it.inv ~= 16 then parts[#parts + 1] = subName(it)
  elseif it.cls == 2 then parts[#parts + 1] = subName(it)
  elseif it.cls == 9 then parts[#parts + 1] = "Recipe" end
  if it.ilvl > 0 and it.inv > 0 then parts[#parts + 1] = "item level " .. it.ilvl end
  if it.req > 1 then parts[#parts + 1] = "level " .. it.req end
  return table.concat(parts, "  \194\183  ")
end

local function pct(ch)
  local p = ch * 100
  if p >= 99.5 then return "100%" end
  if p >= 10 then return ("%d%%"):format(math.floor(p + 0.5)) end
  if p >= 1 then return (("%.1f%%"):format(p):gsub("%.0%%", "%%")) end
  return ("%.1f%%"):format(math.max(p, 0.1))
end

-- The chance column: "12%", "~12%" (an estimate), "2 of 9" (a small players' sample) or "?" (drops, how often unknown).
function Loot.ChanceText(r)
  if r.src == "p" then
    if (r.n or 0) < 30 then return ("%d of %d"):format(r.drops or 0, r.n or 0) end
    return pct(r.chance or 0)
  elseif r.src == "e" then return r.chance and ("~" .. pct(r.chance)) or "?"
  elseif r.chance then return pct(r.chance) end
  return "?"
end

-- Where a chance comes from, in words, for the tooltip.
function Loot.ChanceNote(r)
  if r.src == "p" then
    local n = r.n or 0
    local s = ("Players saw it drop %d %s in %d %s."):format(r.drops or 0, r.drops == 1 and "time" or "times", n, n == 1 and "kill" or "kills")
    if n < 30 then s = s .. " Too few kills for a drop chance yet." end
    return s
  elseif r.src == "f" then return "Drop chance as ForeverDB.net's players saw it in WoW Forever."
  elseif r.src == "e" then return r.chance and "An estimate (~): not measured in WoW Forever yet." or "Drops here."
  end
  return "Drops here; how often isn't known yet."
end

------------------------------------------------------------------------
-- Filters
------------------------------------------------------------------------
-- the best armor each class wears, and the weapon types it can learn (Classic rules)
local CLASS_ARMOR = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, MAGE = 1, PRIEST = 1, WARLOCK = 1 }
local CLASS_EXTRA = { WARRIOR = { [6] = true }, PALADIN = { [6] = true, [7] = true }, SHAMAN = { [6] = true, [9] = true },
  DRUID = { [8] = true } }
local CLASS_WEAPONS = {
  WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
  PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
  HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
  ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
  PRIEST = { 4, 10, 15, 19 },
  SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
  MAGE = { 7, 10, 15, 19 },
  WARLOCK = { 7, 10, 15, 19 },
  DRUID = { 4, 5, 10, 13, 15 },
}
local weaponSet = {}
for c, l in pairs(CLASS_WEAPONS) do
  weaponSet[c] = {}
  for _, s in ipairs(l) do weaponSet[c][s] = true end
  weaponSet[c][14], weaponSet[c][20] = true, true
end

local function playerClass()
  local _, file, id = UnitClass("player")
  return file, id
end

-- Whether your class can use the item (any item that isn't gear counts as usable).
function Loot.Usable(it, file, id)
  if not file then file, id = playerClass() end
  if it.classes and it.classes > 0 and id and id >= 1 then
    if math.floor(it.classes / 2 ^ (id - 1)) % 2 == 0 then return false end
  end
  if it.cls == 4 and it.inv ~= 16 then
    if it.sub >= 1 and it.sub <= 4 then return it.sub <= (CLASS_ARMOR[file] or 4) end
    if it.sub >= 6 then return CLASS_EXTRA[file] and CLASS_EXTRA[file][it.sub] or false end
  elseif it.cls == 2 then
    return not weaponSet[file] or weaponSet[file][it.sub] or false
  end
  return true
end

Loot.SLOTS = {
  { value = "any", text = "Any slot" },
  { value = "head", text = "Head", inv = { 1 } }, { value = "neck", text = "Neck", inv = { 2 } },
  { value = "shoulder", text = "Shoulder", inv = { 3 } }, { value = "back", text = "Back", inv = { 16 } },
  { value = "chest", text = "Chest", inv = { 5, 20 } }, { value = "wrist", text = "Wrist", inv = { 9 } },
  { value = "hands", text = "Hands", inv = { 10 } }, { value = "waist", text = "Waist", inv = { 6 } },
  { value = "legs", text = "Legs", inv = { 7 } }, { value = "feet", text = "Feet", inv = { 8 } },
  { value = "finger", text = "Finger", inv = { 11 } }, { value = "trinket", text = "Trinket", inv = { 12 } },
  { value = "onehand", text = "One-hand and main hand", inv = { 13, 21 } }, { value = "twohand", text = "Two-hand", inv = { 17 } },
  { value = "offhand", text = "Off hand and shield", inv = { 14, 22, 23 } }, { value = "ranged", text = "Ranged, wand, relic", inv = { 15, 25, 26, 28 } },
  { value = "recipe", text = "Recipes" }, { value = "other", text = "Everything else" },
}
Loot.ARMORS = {
  { value = "any", text = "Any armor" }, { value = 1, text = "Cloth" }, { value = 2, text = "Leather" },
  { value = 3, text = "Mail" }, { value = 4, text = "Plate" },
}
local slotInv = {}
for _, s in ipairs(Loot.SLOTS) do
  if s.inv then slotInv[s.value] = {}; for _, i in ipairs(s.inv) do slotInv[s.value][i] = true end end
end

-- f = { mine, slot, armor }
function Loot.Passes(it, f)
  if f.mine and not Loot.Usable(it) then return false end
  local slot = f.slot or "any"
  if slot == "recipe" then
    if it.cls ~= 9 then return false end
  elseif slot == "other" then
    if it.cls == 9 or (it.inv > 0 and it.inv ~= 18 and it.inv ~= 24 and it.inv ~= 4 and it.inv ~= 19) then return false end
  elseif slot ~= "any" and not (slotInv[slot] and slotInv[slot][it.inv]) then
    return false
  end
  local armor = f.armor or "any"
  if armor ~= "any" and not (it.cls == 4 and it.sub == armor and it.inv ~= 16) then return false end
  return true
end

local function lower(s) return (s or ""):lower() end

-- Search all loot: every word must be in the item's name, its boss or its dungeon. Best items first, at most `max`.
function Loot.Search(text, f, max)
  local words = {}
  for w in lower(text):gmatch("%S+") do words[#words + 1] = w end
  if #words == 0 then return {} end
  local out, seen = {}, {}
  for _, e in ipairs(Loot.All()) do
    local it = Loot.Item(e.row.id)
    if it and Loot.Passes(it, f) then
      local hay = lower(it.name) .. " " .. lower(e.boss or "trash mobs") .. " " .. lower(e.inst.name)
      local ok = true
      for _, w in ipairs(words) do if not hay:find(w, 1, true) then ok = false break end end
      local key = e.row.id .. ":" .. e.inst.id .. ":" .. (e.boss or "")
      if ok and not seen[key] then
        seen[key] = true
        out[#out + 1] = e
      end
    end
  end
  table.sort(out, function(a, b)
    local x, y = Loot.Item(a.row.id), Loot.Item(b.row.id)
    if x.q ~= y.q then return x.q > y.q end
    if x.ilvl ~= y.ilvl then return x.ilvl > y.ilvl end
    return x.name < y.name
  end)
  local more = #out > (max or 200)
  while #out > (max or 200) do out[#out] = nil end
  return out, more
end

-- Whether you have the item: worn, in your bags or (once you opened it this session) your bank. Never saved.
function Loot.Have(id)
  if IsEquippedItem and IsEquippedItem(id) then return true end
  local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, true) or (GetItemCount and GetItemCount(id, true))
  return (tonumber(count) or 0) > 0
end

------------------------------------------------------------------------
-- Clicks: shift links the item in chat, ctrl tries it on. Only the game's own links work in chat (the server drops
-- self-built ones), so an item the game hasn't loaded yet is asked for and linked once it is there.
-- The retry is adapted from OneForAll (Forever) 6.2.13, UI/DungeonHelpers.lua (GPL-3.0).
------------------------------------------------------------------------
local function itemLink(id)
  local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)
  return link
end

local function whenLoaded(id, fn)
  local link = itemLink(id)
  if link then fn(link) return end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  local tries = 0
  local function again()
    tries = tries + 1
    local l = itemLink(id)
    if l then fn(l) elseif tries < 10 then C_Timer.After(0.2, again) end
  end
  C_Timer.After(0.2, again)
end

function Loot.Click(id)
  local link = IsModifiedClick and IsModifiedClick("CHATLINK") or IsShiftKeyDown()
  if link then
    whenLoaded(id, function(l)
      if ChatEdit_InsertLink and ChatEdit_InsertLink(l) then return end
      if ChatFrame_OpenChat then ChatFrame_OpenChat(l) end
    end)
    return true
  end
  if (IsModifiedClick and IsModifiedClick("DRESSUP")) or IsControlKeyDown() then
    whenLoaded(id, function(l)
      if DressUpItemLink then pcall(DressUpItemLink, l) elseif DressUpLink then pcall(DressUpLink, l) end
    end)
    return true
  end
  return false
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
local T = app.T or UI.MakeTheme({ 1.0, 0.824, 0.0 })
local W, H = 970, 560
local LEFT_W, MID_W, ROW_H, SEARCH_ROW_H = 260, 255, 36, 50
local win
local state -- EverlookDBSettings.loot

local function S()
  local s = EverlookDBSettings
  if type(s) ~= "table" then return {} end
  if type(s.loot) ~= "table" then s.loot = {} end
  return s.loot
end

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  local fallback = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }
  local f = fallback[q] or fallback[1]
  return f[1], f[2], f[3]
end

local function itemIcon(id)
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if not icon and GetItemIcon then icon = GetItemIcon(id) end
  return icon or 134400
end

-- a list of clickable rows on a scroll page; rows are reused
local function List(parent)
  local scroll = UI.ScrollPage(parent)
  local l = { scroll = scroll, child = scroll.child, rows = {}, used = 0 }
  function l:Begin() self.used = 0; self.y = 0 end
  function l:Row(h)
    self.used = self.used + 1
    local r = self.rows[self.used]
    if not r then
      r = CreateFrame("Button", nil, self.child)
      r.hl = U.Round(r, 4, "BACKGROUND")
      r.hl:SetAllPoints(r)
      r.hl:Hide()
      r.bar = U.Solid(r, "ARTWORK", rgba(T.accent))
      r.bar:SetWidth(2)
      r.bar:SetPoint("TOPLEFT", 0, -6)
      r.bar:SetPoint("BOTTOMLEFT", 0, 6)
      r.text = UI.Text(r, T.font, T.text)
      r.text:SetWordWrap(false)
      r.sub = UI.Text(r, T.fontSmall, T.muted)
      r.sub:SetWordWrap(false)
      r.where = UI.Text(r, T.fontSmall, T.muted)
      r.where:SetWordWrap(false)
      r.right = UI.Text(r, T.fontSmall, T.muted)
      r.right:SetJustifyH("RIGHT")
      r.right:SetWordWrap(false)
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.have = r:CreateTexture(nil, "OVERLAY")
      r.have:SetSize(12, 12)
      r.isLootRow = true -- its tooltip says where the item drops itself
      r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      r:SetScript("OnEnter", function(self)
        if not self.selected then self.hl:SetVertexColor(rgba(T.surfaceHi)); self.hl:Show() end
        if self.onEnter then self.onEnter(self) end
      end)
      r:SetScript("OnLeave", function(self)
        if not self.selected then self.hl:Hide() end
        GameTooltip:Hide()
      end)
      r:SetScript("OnClick", function(self, button) if self.onClick then self.onClick(self, button) end end)
      self.rows[self.used] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -self.y)
    r:SetPoint("RIGHT", self.child, "RIGHT", 0, 0)
    r:SetHeight(h)
    self.y = self.y + h
    r.onEnter, r.onClick, r.selected, r.header = nil, nil, false, nil
    r.hl:Hide(); r.bar:Hide(); r.icon:Hide(); r.have:Hide()
    r.text:ClearAllPoints(); r.sub:ClearAllPoints(); r.right:ClearAllPoints(); r.where:ClearAllPoints()
    r.text:SetText(""); r.sub:SetText(""); r.right:SetText(""); r.where:SetText(""); r.where:Hide()
    r.text:SetTextColor(rgba(T.text))
    r.text:SetWordWrap(false)
    r:EnableMouse(true)
    r:Show()
    return r
  end
  function l:Select(r)
    r.selected = true
    r.hl:SetVertexColor(rgba(T.accentDim)); r.hl:Show(); r.bar:Show()
    r.text:SetTextColor(rgba(T.accent))
  end
  function l:Heading(text)
    local r = self:Row(26)
    r:EnableMouse(false)
    r.text:SetPoint("BOTTOMLEFT", 10, 4)
    r.text:SetText(text)
    r.text:SetTextColor(rgba(T.gold))
    return r
  end
  function l:Note(text)
    local r = self:Row(60)
    r:EnableMouse(false)
    r.text:SetPoint("TOPLEFT", 10, -8)
    r.text:SetPoint("RIGHT", -10, 0)
    r.text:SetWordWrap(true)
    r.text:SetText(text)
    r.text:SetTextColor(rgba(T.muted))
    return r
  end
  function l:End()
    for i = self.used + 1, #self.rows do self.rows[i]:Hide() end
    self.child:SetHeight(math.max(1, self.y))
    if self.scroll.UpdateBar then self.scroll.UpdateBar() end
  end
  function l:Top() if self.scroll.SetScroll then self.scroll.SetScroll(0) end end
  return l
end

local function panel(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.eluiTheme = T
  p.bg = U.Round(p, 6, "BACKGROUND")
  p.bg:SetAllPoints(p)
  p.bg:SetVertexColor(rgba(T.card))
  return p
end

local function findInstance(id)
  for _, inst in ipairs(D.instances) do if inst.id == id then return inst end end
end

local function filters() local s = S(); return { mine = s.mine, slot = s.slot or "any", armor = s.armor or "any" } end

local function itemTooltip(row, r, inst, boss)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  local ok = pcall(GameTooltip.SetItemByID, GameTooltip, r.id)
  if not ok or GameTooltip:NumLines() == 0 then
    local it = Loot.Item(r.id)
    GameTooltip:AddLine(it and it.name or ("Item " .. r.id), qualityColor(it and it.q or 1))
  end
  GameTooltip:AddLine(" ")
  local where = boss or "Trash mobs"
  if r.npc and inst.names and inst.names[r.npc] then where = where .. " (likeliest from " .. inst.names[r.npc] .. ")" end
  GameTooltip:AddDoubleLine(where .. ", " .. inst.name, Loot.ChanceText(r), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(Loot.ChanceNote(r), 0.6, 0.62, 0.68, true)
  if Loot.Have(r.id) then GameTooltip:AddLine("You have this one.", 0.38, 0.81, 0.53) end
  GameTooltip:AddLine("Shift-click: link in chat.  Ctrl-click: try it on.", 0.6, 0.62, 0.68)
  GameTooltip:Show()
end

-- `where` (search results): a third line with the boss and dungeon, as wide as the row
local function itemRow(list, r, inst, boss, sub, where)
  local it = Loot.Item(r.id)
  if not it then return end
  local row = list:Row(where and SEARCH_ROW_H or ROW_H)
  row.icon:SetSize(26, 26)
  row.icon:SetPoint("LEFT", 8, 0)
  row.icon:SetTexture(itemIcon(r.id))
  row.icon:Show()
  row.right:SetPoint("RIGHT", -10, 0)
  row.right:SetWidth(70)
  row.right:SetText(Loot.ChanceText(r))
  row.right:SetTextColor(rgba(r.src == "e" and T.muted or T.text))
  row.text:SetPoint("TOPLEFT", 42, -4)
  row.text:SetPoint("RIGHT", row.right, "LEFT", -24, 0)
  row.text:SetText(it.name)
  row.text:SetTextColor(qualityColor(it.q))
  if where then
    row.sub:SetPoint("TOPLEFT", 42, -19)
    row.where:SetPoint("BOTTOMLEFT", 42, 5)
    row.where:SetPoint("RIGHT", -10, 0)
    row.where:SetText(where)
    row.where:Show()
  else
    row.sub:SetPoint("BOTTOMLEFT", 42, 5)
  end
  row.sub:SetPoint("RIGHT", row.right, "LEFT", -24, 0)
  row.sub:SetText(sub or Loot.Describe(it))
  if Loot.Have(r.id) then
    if UI.SetIcon(row.have, "check") then row.have:SetVertexColor(rgba(T.ok)) end
    row.have:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
  end
  row.onEnter = function(self) itemTooltip(self, r, inst, boss) end
  row.onClick = function() Loot.Click(r.id) end
end

local function countText(n, more) return more and ("more than " .. n) or tostring(n) end

local function refreshItems()
  local L, f, s = win.items, filters(), S()
  L:Begin()
  local query = U.Trim(win.search:GetText() or "")
  if query ~= "" then
    local hits, more = Loot.Search(query, f, 200)
    win.itemsTitle:SetText(("Search: %s"):format(query))
    win.itemsSub:SetText(#hits == 0 and "Nothing found" or (countText(#hits, more) .. " drops"))
    for _, e in ipairs(hits) do
      local it = Loot.Item(e.row.id)
      itemRow(L, e.row, e.inst, e.boss, Loot.Describe(it), (e.boss or "Trash mobs") .. ", " .. e.inst.name)
    end
    if #hits == 0 then L:Note("No drop matches. Try fewer words, or clear the filters above.") end
    L:End()
    return
  end
  local inst = findInstance(s.instance) or D.instances[1]
  local which = s.boss or 0
  local groups = {}
  if which == 0 then
    for _, b in ipairs(inst.bosses) do groups[#groups + 1] = { b[1], Loot.BossRows(inst, b) } end
    groups[#groups + 1] = { "Trash mobs", Loot.BossRows(inst) }
  elseif which == -1 then
    groups[1] = { "Trash mobs", Loot.BossRows(inst) }
  else
    local b = inst.bosses[which]
    if b then groups[1] = { b[1], Loot.BossRows(inst, b) } end
  end
  local shown, total = 0, 0
  for _, g in ipairs(groups) do
    local rows = {}
    for _, r in ipairs(g[2]) do
      total = total + 1
      local it = Loot.Item(r.id)
      if it and Loot.Passes(it, f) then rows[#rows + 1] = r end
    end
    if #rows > 0 and #groups > 1 then L:Heading(g[1]) end
    for _, r in ipairs(rows) do itemRow(L, r, inst, g[1] ~= "Trash mobs" and g[1] or nil) end
    shown = shown + #rows
  end
  win.itemsTitle:SetText(#groups == 1 and groups[1][1] or inst.name)
  win.itemsSub:SetText(total == 0 and "" or (shown == total and (shown .. " drops") or (shown .. " of " .. total .. " drops match the filters")))
  if total == 0 then
    L:Note("No loot list here yet. Run it with the Collector on and upload your file: what you loot fills it in.")
  elseif shown == 0 then
    L:Note("Nothing here matches the filters above.")
  end
  L:End()
end

local function refreshBosses()
  local L, s = win.bosses, S()
  local inst = findInstance(s.instance) or D.instances[1]
  L:Begin()
  local function add(label, idx, n)
    local r = L:Row(28)
    r.text:SetPoint("LEFT", 12, 0)
    r.text:SetPoint("RIGHT", -34, 0)
    r.text:SetText(label)
    r.right:SetPoint("RIGHT", -10, 0)
    r.right:SetText(n > 0 and n or "")
    if (s.boss or 0) == idx then L:Select(r) end
    r.onEnter = function(self) -- a name too long for the column: the whole name
      if not (self.text.IsTruncated and self.text:IsTruncated()) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label, 1, 1, 1)
      GameTooltip:Show()
    end
    r.onClick = function() S().boss = idx; win.search:SetText(""); refreshBosses(); refreshItems(); win.items:Top() end
  end
  local all = 0
  for _, b in ipairs(inst.bosses) do all = all + #Loot.BossRows(inst, b) end
  local trash = #Loot.BossRows(inst)
  add("All loot", 0, all + trash)
  for i, b in ipairs(inst.bosses) do add(b[1], i, #Loot.BossRows(inst, b)) end
  if trash > 0 then add("Trash mobs", -1, trash) end
  L:End()
end

local function refreshInstances()
  local L, s = win.instances, S()
  L:Begin()
  local kind
  for _, inst in ipairs(D.instances) do
    if inst.kind ~= kind then
      kind = inst.kind
      L:Heading(kind == "r" and "Raids" or "Dungeons")
    end
    local r = L:Row(28)
    r.text:SetPoint("LEFT", 12, 0)
    r.text:SetPoint("RIGHT", -50, 0)
    r.text:SetText(inst.name)
    r.right:SetPoint("RIGHT", -10, 0)
    r.right:SetText(inst.min > 0 and (inst.min == inst.max and inst.min or (inst.min .. "-" .. inst.max)) or "")
    if inst.id == s.instance then L:Select(r) end
    r.onEnter = function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(inst.name, 1, 1, 1)
      local lv = inst.min > 0 and ("Level " .. (inst.min == inst.max and inst.min or (inst.min .. " to " .. inst.max))) or nil
      GameTooltip:AddLine((inst.kind == "r" and "Raid" or "Dungeon") .. (inst.players > 0 and (", " .. inst.players .. " players") or "")
        .. (lv and (", " .. lv:lower()) or ""), 0.6, 0.62, 0.68)
      if inst.forever == 1 then GameTooltip:AddLine("New in WoW Forever", 0.38, 0.81, 0.53) end
      GameTooltip:Show()
    end
    r.onClick = function()
      S().instance, S().boss = inst.id, 0
      win.search:SetText("")
      refreshInstances(); refreshBosses(); refreshItems(); win.items:Top(); win.bosses:Top()
    end
  end
  L:End()
end

local function refreshFilters()
  local s = S()
  local function label(list, v) for _, o in ipairs(list) do if o.value == v then return o.text end end return list[1].text end
  win.slotValue:SetText(label(Loot.SLOTS, s.slot or "any"))
  win.armorValue:SetText(label(Loot.ARMORS, s.armor or "any"))
  win.mine.label:SetTextColor(rgba(s.mine and T.accent or T.text))
  win.mine.border:SetColor(rgba(s.mine and T.accent or T.border))
end

function Loot.Refresh()
  if not win or not win:IsShown() then return end
  refreshFilters()
  refreshInstances()
  refreshBosses()
  refreshItems()
end

local function build()
  win = CreateFrame("Frame", "EverlookDBLootWindow", UIParent)
  win.eluiTheme = T
  win:SetSize(W, H)
  win:SetFrameStrata("HIGH")
  win:SetToplevel(true)
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    S().point = { p, rp, x, y }
  end)
  local pt = S().point
  if type(pt) == "table" and pt[1] then win:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else win:SetPoint("CENTER") end
  UI.WindowChrome(win, T)
  UI.RegisterWindow(win, { title = "Dungeon loot", icon = "bag", app = app })
  UI.CloseButton(win, T)

  local icon = win:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("TOPLEFT", 18, -18)
  if UI.SetIcon(icon, "bag") then icon:SetVertexColor(rgba(T.accent)) end
  local title = UI.Text(win, T.fontTitle, T.text)
  title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  title:SetText("Dungeon loot")
  local subtitle = UI.Text(win, T.fontSmall, T.muted)
  subtitle:SetPoint("TOPLEFT", 18, -40)
  subtitle:SetText("What drops where in WoW Forever's dungeons and raids, and how often.")

  -- search and filters
  local search = UI.EditBox(win, 260, 26)
  search:SetPoint("TOPLEFT", 18, -62)
  local hint = UI.Text(search, T.font, T.muted)
  hint:SetPoint("LEFT", 26, 0)
  hint:SetText("Search all loot")
  local sIcon = search:CreateTexture(nil, "OVERLAY")
  sIcon:SetSize(12, 12)
  sIcon:SetPoint("LEFT", 8, 0)
  if UI.SetIcon(sIcon, "search") then sIcon:SetVertexColor(rgba(T.muted)) end
  search:SetTextInsets(26, 8, 0, 0)
  search:SetScript("OnTextChanged", function(self)
    hint:SetShown(self:GetText() == "")
    if win:IsShown() then refreshItems(); win.items:Top() end
  end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  search:SetScript("OnEscapePressed", function(self)
    if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
  end)
  win.search = search

  local mine = UI.Button(win, "My class", function()
    S().mine = not S().mine
    refreshFilters(); refreshItems()
  end, 100)
  mine:SetPoint("LEFT", search, "RIGHT", 10, 0)
  UI.Tooltip(mine, "My class", "Only what your class can wear and use: its armor type, weapons it can learn, and items made for it.")
  win.mine = mine

  local armorB, armorV = UI.DropButton(win, T, 120)
  armorB:SetPoint("LEFT", mine, "RIGHT", 8, 0)
  armorB:SetScript("OnClick", function(self)
    UI.OpenPopup(self, Loot.ARMORS, S().armor or "any", function(v) S().armor = v; refreshFilters(); refreshItems() end)
  end)
  win.armorValue = armorV

  local slotB, slotV = UI.DropButton(win, T, 190)
  slotB:SetPoint("LEFT", armorB, "RIGHT", 8, 0)
  slotB:SetScript("OnClick", function(self)
    UI.OpenPopup(self, Loot.SLOTS, S().slot or "any", function(v) S().slot = v; refreshFilters(); refreshItems() end)
  end)
  win.slotValue = slotV

  local clear = UI.Button(win, "Clear", function()
    local s = S()
    s.mine, s.slot, s.armor = nil, nil, nil
    search:SetText("")
    refreshFilters(); refreshItems()
  end, 70)
  clear:SetPoint("LEFT", slotB, "RIGHT", 8, 0)
  UI.Tooltip(clear, "Clear", "Clears the search and the filters.")

  -- three columns: dungeons, bosses, items
  local top, bottom = -100, 40
  local left = panel(win)
  left:SetPoint("TOPLEFT", 16, top)
  left:SetPoint("BOTTOMLEFT", 16, bottom)
  left:SetWidth(LEFT_W)
  win.instances = List(left)
  win.instances.scroll:SetPoint("TOPLEFT", 4, -4)
  win.instances.scroll:SetPoint("BOTTOMRIGHT", -18, 4)

  local mid = panel(win)
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
  mid:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 8, 0)
  mid:SetWidth(MID_W)
  win.bosses = List(mid)
  win.bosses.scroll:SetPoint("TOPLEFT", 4, -4)
  win.bosses.scroll:SetPoint("BOTTOMRIGHT", -18, 4)

  local right = panel(win)
  right:SetPoint("TOPLEFT", mid, "TOPRIGHT", 8, 0)
  right:SetPoint("BOTTOMRIGHT", -16, bottom)
  win.itemsTitle = UI.Text(right, T.fontTitle, T.text)
  win.itemsTitle:SetPoint("TOPLEFT", 12, -10)
  win.itemsTitle:SetPoint("RIGHT", -140, 0)
  win.itemsTitle:SetWordWrap(false)
  win.itemsSub = UI.Text(right, T.fontSmall, T.muted)
  win.itemsSub:SetPoint("TOPRIGHT", -14, -12)
  win.itemsSub:SetJustifyH("RIGHT")
  local body = CreateFrame("Frame", nil, right)
  body.eluiTheme = T
  body:SetPoint("TOPLEFT", 4, -34)
  body:SetPoint("BOTTOMRIGHT", -4, 4)
  win.items = List(body)

  -- footer: how to click, and the credit for the drop chances ForeverDB.net's players measured
  local foot = UI.Text(win, T.fontSmall, T.muted)
  foot:SetPoint("BOTTOMLEFT", 18, 14)
  foot:SetText("Shift-click links an item, Ctrl-click tries it on. ~ marks an estimate.  /edb loot")
  local credit = UI.Text(win, T.fontSmall, T.muted)
  credit:SetPoint("BOTTOMRIGHT", -18, 14)
  credit:SetJustifyH("RIGHT")
  credit:SetText(D.credit or "")

  win:SetScript("OnShow", function() Loot.Refresh() end)
  win:SetScript("OnHide", function() GameTooltip:Hide() end)
  -- bags changed (the ticks) or items the game just loaded (names, icons): one redraw a moment later, not one each
  win:SetScript("OnEvent", function(self)
    if not self:IsShown() or self.redraw then return end
    self.redraw = true
    C_Timer.After(0.3, function() self.redraw = nil; if self:IsShown() then refreshItems() end end)
  end)
  win:RegisterEvent("BAG_UPDATE_DELAYED")
  win:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  UI.CloseOnEscape(win)
  win.eluiEscape = function()
    if search:HasFocus() then search:ClearFocus() return true end
  end
  win:Hide()
end

-- Opens the browser; `text` fills the search box ("/edb loot vancleef").
function Loot.Open(text)
  if not win then build() end
  local s = S()
  if not findInstance(s.instance) then s.instance = D.instances[1] and D.instances[1].id end
  -- in a dungeon, open on it
  local _, kind, _, _, _, _, _, mapID = GetInstanceInfo()
  if (kind == "party" or kind == "raid") and mapID and not text then
    for _, inst in ipairs(D.instances) do
      if inst.map == mapID then s.instance, s.boss = inst.id, 0 break end
    end
  end
  local was = win:IsShown()
  win.search:SetText(text or "")
  win:Show()
  if was then Loot.Refresh() end
end

function Loot.Toggle()
  if win and win:IsShown() then win:Hide() else Loot.Open() end
end

function Loot.IsShown() return win ~= nil and win:IsShown() end

------------------------------------------------------------------------
-- Commands, the settings page, and "where does this drop" on item tooltips
------------------------------------------------------------------------
-- /edb loot [words] (registered in Options.lua, so a /reload after an update without a restart can say so)
function Loot.Command(rest)
  rest = U.Trim(rest or "")
  if rest == "" then Loot.Toggle() else Loot.Open(rest) end
end

app:Setting({
  key = "loottooltip", type = "bool", label = "Show where an item drops in its tooltip",
  desc = "Adds the dungeon bosses that drop it, with the chance, to every item's tooltip.",
  keywords = { "loot", "drops", "dungeon", "boss", "raid", "tooltip", "where", "atlas" },
  get = function() return EverlookDBSettings.lootTooltip ~= false end,
  set = function(v) EverlookDBSettings.lootTooltip = v and true or false end,
})

app:Section("loot", "Dungeon loot", function(stack)
  UI.Header(stack, "Dungeon loot", "What drops where in WoW Forever's dungeons and raids, and how often.")
  UI.Note(stack, "Pick a dungeon, then a boss or its trash mobs. Search all loot at once, or show only what your class can use, one armor type or one slot. A tick marks what you already have.")
  UI.ButtonRow(stack, {
    { label = "Open dungeon loot", width = 200, style = "accent", onClick = function() Loot.Open() end,
      keywords = { "loot", "drops", "atlas", "atlasloot", "boss", "raid", "dungeon", "browser" } },
  })
  UI.Note(stack, "Drop chances come from what players looted in WoW Forever, the Collector's uploads first. ~ marks an estimate that hasn't been measured in WoW Forever yet. " .. (D.credit or "") .. ".")
  UI.Header(stack, "Tooltips")
  app:Widget(stack, "loottooltip")
  UI.Header(stack, "Chat commands")
  UI.Note(stack, "/edb loot  open or close it\n/edb loot <words>  search all loot, for example /edb loot vancleef")
end, { icon = "bag" })

local function addWhere(tooltip, id)
  if EverlookDBSettings == nil or EverlookDBSettings.lootTooltip == false then return end
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  if type(owner) == "table" and owner.isLootRow then return end
  if issecretvalue and issecretvalue(id) then return end
  id = tonumber(id)
  if not id then return end
  local l = Loot.WhereDrops(id)
  if not l then return end
  for i = 1, math.min(3, #l) do
    local e = l[i]
    tooltip:AddDoubleLine((e.boss or "Trash mobs") .. ", " .. e.inst.name, Loot.ChanceText(e.row), 1, 0.82, 0, 0.85, 0.87, 0.9)
  end
  if #l > 3 then tooltip:AddLine(("and %d more places: /edb loot"):format(#l - 3), 0.6, 0.62, 0.68) end
end

Loot.AddWhere = addWhere

local function hookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then
        pcall(addWhere, tooltip, data and data.id)
      end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    local function onItem(tooltip)
      local _, link = tooltip:GetItem()
      local id = link and tonumber(link:match("item:(%d+)"))
      if id then pcall(addWhere, tooltip, id) end
    end
    GameTooltip:HookScript("OnTooltipSetItem", onItem)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", onItem) end
  end
end
pcall(hookTooltips)
