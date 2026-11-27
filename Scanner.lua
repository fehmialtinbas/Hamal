local _, ns = ...

local Scanner = {}
ns.Scanner = Scanner

local function bagList()
  local bags = {}
  local last = NUM_BAG_SLOTS or 4
  for bag = 0, last do
    bags[#bags + 1] = bag
  end
  local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if reagentBag and reagentBag > last then
    bags[#bags + 1] = reagentBag
  end
  return bags
end

-- Is this one of the bags Hamal mails from (not the bank)?
function Scanner.IsMailBag(bag)
  for _, b in ipairs(bagList()) do
    if b == bag then return true end
  end
  return false
end

function Scanner.ItemClass(itemID)
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not getInstant then return nil, nil end
  local _, _, _, _, _, classID, subclassID = getInstant(itemID)
  return classID, subclassID
end

-- The game's "Crafting Reagent" flag (item info is always cached for bag items).
function Scanner.IsCraftingReagent(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return false end
  return select(17, getInfo(itemID)) == true
end

function Scanner.ReadSlot(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info or not info.itemID then return nil end
  local classID, subclassID = Scanner.ItemClass(info.itemID)
  return {
    bag = bag,
    slot = slot,
    itemID = info.itemID,
    count = info.stackCount or 1,
    quality = info.quality,
    isBound = info.isBound,
    isLocked = info.isLocked,
    link = info.hyperlink,
    name = info.itemName,
    icon = info.iconFileID,
    classID = classID,
    subclassID = subclassID,
    isCraftingReagent = Scanner.IsCraftingReagent(info.itemID),
  }
end

function Scanner.EachItem(fn)
  for _, bag in ipairs(bagList()) do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local item = Scanner.ReadSlot(bag, slot)
      if item then fn(item) end
    end
  end
end

local function byKind(a, b)
  local ac, bc = a.classID or -1, b.classID or -1
  if ac ~= bc then return ac < bc end
  local as, bs = a.subclassID or -1, b.subclassID or -1
  if as ~= bs then return as < bs end
  if a.itemID ~= b.itemID then return a.itemID < b.itemID end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

-- Every bag stack a rule sends to a bank alt, as a list of { item, key, reason }, and
-- the set of those stacks that stay because of a keep amount (see Rules.PickKept).
local function resolveBags(db, keys)
  local going, keepGroups = {}, nil
  Scanner.EachItem(function(item)
    local key, reason = ns.Rules.Resolve(item, db, keys)
    if not key then return end
    going[#going + 1] = { item = item, key = key, reason = reason }
    if ns.Rules.KeepAmount(db, item.itemID) then
      keepGroups = keepGroups or {}
      local group = keepGroups[item.itemID] or {}
      keepGroups[item.itemID] = group
      group[#group + 1] = item
    end
  end)
  local kept = {}
  for itemID, stacks in pairs(keepGroups or {}) do
    for _, stack in ipairs(ns.Rules.PickKept(stacks, ns.Rules.KeepAmount(db, itemID))) do
      kept[stack] = true
    end
  end
  return going, kept
end

-- Every bag item that goes to `targetKey`, sorted so similar items share a mail.
function Scanner.Collect(db, targetKey)
  local going, kept = resolveBags(db, ns.Mules.ActiveKeys(db))
  local out = {}
  for _, g in ipairs(going) do
    if g.key == targetKey and not kept[g.item] then
      g.item.reason = g.reason
      out[#out + 1] = g.item
    end
  end
  table.sort(out, byKind)
  return out
end

-- Where a bag slot's stack goes, as one number key: bag * 1000 + slot.
function Scanner.SlotKey(bag, slot)
  return bag * 1000 + slot
end

-- How many stacks of one item go once partial stacks are combined (see Stacker.lua) and
-- a keep amount has held some back. totals.count: every item of it a rule sends, kept
-- ones too; totals.stacks: the stacks that go without combining.
local function combinedStacks(db, itemID, totals)
  local max = ns.Stacker.MaxStack(itemID)
  if not max or max <= 0 or not ns.Stacker.Combinable(db, itemID, max) then return totals.stacks end
  local amount = ns.Rules.KeepAmount(db, itemID)
  if not amount then return math.min(totals.stacks, math.ceil(totals.count / max)) end
  local combined = {}
  for _ = 1, math.floor(totals.count / max) do combined[#combined + 1] = { count = max } end
  if totals.count % max > 0 then combined[#combined + 1] = { count = totals.count % max } end
  return #combined - #ns.Rules.PickKept(combined, amount)
end

-- For every active bank alt, in one pass over the bags:
--   stacks     stacks waiting for it now
--   minStacks  stacks once partial stacks are combined (see Stacker.lua)
-- Also returns where each outgoing stack goes ([SlotKey] = bank alt key), for the bag
-- marks and tooltips at the mailbox. Stacks a keep amount holds back go nowhere.
function Scanner.Summary(db)
  local keys = ns.Mules.ActiveKeys(db)
  local summary, perItem, slots = {}, {}, {}
  for _, key in ipairs(keys) do
    summary[key] = { stacks = 0, minStacks = 0 }
    perItem[key] = {}
  end
  local going, kept = resolveBags(db, keys)
  for _, g in ipairs(going) do
    local item, key = g.item, g.key
    local totals = perItem[key][item.itemID]
    if not totals then
      totals = { count = 0, stacks = 0 }
      perItem[key][item.itemID] = totals
    end
    totals.count = totals.count + item.count
    if not kept[item] then
      slots[Scanner.SlotKey(item.bag, item.slot)] = key
      summary[key].stacks = summary[key].stacks + 1
      totals.stacks = totals.stacks + 1
    end
  end
  for key, totalsByItem in pairs(perItem) do
    local min = 0
    for itemID, totals in pairs(totalsByItem) do
      min = min + combinedStacks(db, itemID, totals)
    end
    summary[key].minStacks = min
  end
  return summary, slots
end

-- Stack counts for every active bank alt in one pass.
function Scanner.CountAll(db)
  local keys = ns.Mules.ActiveKeys(db)
  local counts = {}
  for _, key in ipairs(keys) do
    counts[key] = 0
  end
  local going, kept = resolveBags(db, keys)
  for _, g in ipairs(going) do
    if not kept[g.item] then counts[g.key] = counts[g.key] + 1 end
  end
  return counts
end
