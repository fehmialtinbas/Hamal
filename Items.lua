local _, ns = ...

-- Data behind the Items tab: every item Hamal knows and where each one goes.
local Items = {}
ns.Items = Items

-- Name, link and quality only when the client already has them. Asking for an
-- uncached item makes the client query the server, so that is left to
-- Items.RequestNames for the few rows actually on screen.
local function cachedInfo(itemID)
  local isCached = C_Item and C_Item.IsItemDataCachedByID
  if isCached and not isCached(itemID) then return nil end
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return nil end
  return getInfo(itemID)
end

function Items.RequestNames(entries)
  local request = C_Item and C_Item.RequestLoadItemDataByID
  if not request then return end
  for _, entry in ipairs(entries) do
    if not entry.name and not entry.requested then
      entry.requested = true
      request(entry.itemID) -- GET_ITEM_INFO_RECEIVED fires when it arrives
    end
  end
end

-- Where an item goes and why: (bankAltKey, reason) or (nil, reason).
-- reason is "item" (picked by hand), a category key, "never", "kept", "bound", "quest"
-- (a quest-type item nobody picked), "held" (Alt-clicked at this mailbox visit) or "none".
function Items.Destination(db, entry, keys)
  if ns.Rules.ALWAYS_KEEP[entry.itemID] then return nil, "kept" end
  if db.exclude[entry.itemID] then return nil, "never" end
  if entry.isBound then return nil, "bound" end
  if ns.Rules.held[entry.itemID] then return nil, "held" end
  local key, reason = ns.Rules.Resolve({
    itemID = entry.itemID, classID = entry.classID, subclassID = entry.subclassID, quality = entry.quality,
    isCraftingReagent = entry.isCraftingReagent,
  }, db, keys)
  if key then return key, reason end
  if entry.classID == ns.Rules.QUEST_ITEM_CLASS then return nil, "quest" end
  return nil, "none"
end

-- Groups on the Items tab: trade goods and consumables by their kind (Cloth, Herb, Metal &
-- Stone, Potion...), everything else by its class (Weapon, Armor, Recipe...). The names
-- come from the game, in the player's language. Trade goods come first: they are what
-- bank alts mostly get.
local GROUP_RANK = { [7] = 1, [0] = 2, [3] = 3, [9] = 4, [5] = 5, [2] = 6, [4] = 7, [1] = 8, [12] = 9, [15] = 10 }
local BY_KIND = { [7] = true, [0] = true }
local groupNames = {}

local function groupName(classID, subclassID)
  local key = subclassID and (classID .. ":" .. subclassID) or tostring(classID)
  local name = groupNames[key]
  if name == nil then
    if subclassID then
      local getSub = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
      name = getSub and getSub(classID, subclassID) or nil
    else
      local getClass = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
      name = getClass and getClass(classID) or nil
    end
    name = name or false
    groupNames[key] = name
  end
  return name or nil
end

-- (group key, group name, rank) of an item, from its class and subclass.
function Items.GroupOf(entry)
  local classID, subclassID = entry.classID, entry.subclassID
  if not classID then return "other", "Other", 99 end
  local rank = GROUP_RANK[classID] or (20 + classID)
  if BY_KIND[classID] and subclassID then
    local name = groupName(classID, subclassID) or groupName(classID) or "Other"
    return classID .. ":" .. subclassID, name, rank
  end
  return tostring(classID), groupName(classID) or "Other", rank
end

-- The "Show" buttons of the Items tab.
local SHOW = {
  all = function() return true end,
  going = function(e) return e.destination ~= nil end,
  -- Could be mailed, but no rule sends it. Soulbound items, the Hearthstone and tools
  -- can't go at all, so they aren't listed here.
  staying = function(e)
    return e.destination == nil and (e.reason == "none" or e.reason == "quest" or e.reason == "held")
  end,
  never = function(e) return e.reason == "never" end,
}

function Items.IsShow(show)
  return SHOW[show] ~= nil
end

function Items.Shows(entry, show)
  return (SHOW[show] or SHOW.all)(entry)
end

-- The list as the Items tab draws it: a header row ({ header = true, label, count })
-- before each group. `entries` must be in Collect's order.
function Items.WithHeaders(entries)
  local out, header = {}, nil
  for _, e in ipairs(entries) do
    if not header or header.group ~= e.group then
      header = { header = true, group = e.group, label = e.groupLabel, count = 0 }
      out[#out + 1] = header
    end
    header.count = header.count + 1
    out[#out + 1] = e
  end
  return out
end

-- Items in your bags now, items your characters carried before, and items with a rule.
-- Group by group (see GroupOf); in each, in-bag items first, then by name.
function Items.Collect(db)
  local byID = {}
  local function entry(id)
    local e = byID[id]
    if not e then
      e = { itemID = id, count = 0 }
      byID[id] = e
    end
    return e
  end
  ns.Scanner.EachItem(function(item)
    local e = entry(item.itemID)
    e.count = e.count + item.count
    e.inBags = true
    e.classID, e.subclassID, e.quality = item.classID, item.subclassID, item.quality
    e.isCraftingReagent = item.isCraftingReagent
    e.name, e.link, e.icon = item.name, item.link, item.icon
    -- A bind-on-equip item counts as bound only when every stack of it is.
    if item.isBound then
      e.boundStacks = (e.boundStacks or 0) + 1
    else
      e.freeStacks = (e.freeStacks or 0) + 1
    end
  end)
  for id in pairs(db.seen) do entry(id) end
  for id in pairs(db.exclude) do entry(id) end
  for _, mule in pairs(db.mules) do
    for id in pairs(mule.items) do entry(id) end
  end

  local keys = ns.Mules.ActiveKeys(db)
  local list = {}
  for id, e in pairs(byID) do
    if not e.classID then e.classID, e.subclassID = ns.Scanner.ItemClass(id) end
    if not e.name then
      local name, link, quality = cachedInfo(id)
      e.name, e.link = name, link
      e.quality = e.quality or quality
    end
    e.icon = e.icon or ns.ItemIcon(id)
    e.isBound = (e.boundStacks or 0) > 0 and (e.freeStacks or 0) == 0
    e.destination, e.reason = Items.Destination(db, e, keys)
    e.group, e.groupLabel, e.groupRank = Items.GroupOf(e)
    list[#list + 1] = e
  end
  table.sort(list, function(a, b)
    if a.groupRank ~= b.groupRank then return a.groupRank < b.groupRank end
    if a.groupLabel ~= b.groupLabel then return a.groupLabel < b.groupLabel end
    if a.group ~= b.group then return a.group < b.group end
    if (a.inBags or false) ~= (b.inBags or false) then return a.inBags == true end
    local an, bn = a.name or "~", b.name or "~"
    if an ~= bn then return an < bn end
    return a.itemID < b.itemID
  end)
  return list
end

-- The hand-made choice for an item: a bank alt key, "never", or nil (follow item types).
function Items.Choice(db, itemID)
  if db.exclude[itemID] then return "never" end
  for _, key in ipairs(ns.Mules.SortedKeys(db)) do
    if db.mules[key].items[itemID] then return key end
  end
  return nil
end

function Items.SetChoice(db, itemID, choice)
  for _, mule in pairs(db.mules) do
    mule.items[itemID] = nil
  end
  db.exclude[itemID] = nil
  if choice == "never" then
    db.exclude[itemID] = true
  elseif choice and db.mules[choice] then
    db.mules[choice].items[itemID] = true
  end
end

-- Remember mailable items so they stay pickable after they leave your bags.
function Items.RecordSeen(db)
  ns.Scanner.EachItem(function(item)
    if not item.isBound and not ns.Rules.ALWAYS_KEEP[item.itemID] then
      db.seen[item.itemID] = true
    end
  end)
end

-- One bag scan at login and logout (and when the mailbox or the Items tab opens),
-- never on every bag change: looting must cost Hamal nothing.
local function recordSeen()
  if ns.db then Items.RecordSeen(ns.db) end
end
ns.On("PLAYER_LOGIN", recordSeen)
ns.On("PLAYER_LOGOUT", recordSeen)
