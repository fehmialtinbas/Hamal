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

function Scanner.ItemClass(itemID)
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not getInstant then return nil, nil end
  local _, _, _, _, _, classID, subclassID = getInstant(itemID)
  return classID, subclassID
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

-- Every bag item that belongs to `targetKey`, sorted so similar items share a mail.
function Scanner.Collect(db, targetKey)
  local keys = ns.Mules.ActiveKeys(db)
  local out = {}
  Scanner.EachItem(function(item)
    local key, reason = ns.Rules.Resolve(item, db, keys)
    if key == targetKey then
      item.reason = reason
      out[#out + 1] = item
    end
  end)
  table.sort(out, byKind)
  return out
end

-- Stack counts for every active bank alt in one pass (for the mailbox panel).
function Scanner.CountAll(db)
  local keys = ns.Mules.ActiveKeys(db)
  local counts = {}
  for _, key in ipairs(keys) do
    counts[key] = 0
  end
  Scanner.EachItem(function(item)
    local key = ns.Rules.Resolve(item, db, keys)
    if key then counts[key] = counts[key] + 1 end
  end)
  return counts
end
