local _, ns = ...

local Rules = {}
ns.Rules = Rules

local QUEST_ITEM_CLASS = 12

-- Never mailed, whatever the rules say: things a character needs on itself.
Rules.ALWAYS_KEEP = {
  [6948] = true,  -- Hearthstone
  [5060] = true,  -- Thieves' Tools
  [2901] = true,  -- Mining Pick
  [7005] = true,  -- Skinning Knife
  [5956] = true,  -- Blacksmith Hammer
  [6256] = true,  -- Fishing Pole
  [4471] = true,  -- Flint and Tinder
  [6219] = true,  -- Arclight Spanner
  [10498] = true, -- Gyromatic Micro-Adjustor
  [6218] = true,  -- Runed Copper Rod
  [6339] = true,  -- Runed Silver Rod
  [11130] = true, -- Runed Golden Rod
  [11145] = true, -- Runed Truesilver Rod
  [16207] = true, -- Runed Arcanite Rod
  [9149] = true,  -- Philosopher's Stone
}

function Rules.IsMailable(item, db)
  if not item or not item.itemID then return false end
  if item.isBound or item.isLocked then return false end
  if item.classID == QUEST_ITEM_CLASS then return false end
  if Rules.ALWAYS_KEEP[item.itemID] or db.exclude[item.itemID] then return false end
  return true
end

-- Which bank alt should get this item, and why?
-- An item rule beats a type rule; between equal rules the alphabetically first
-- bank alt wins, so the answer never changes from one scan to the next.
function Rules.Resolve(item, db, keys)
  if not Rules.IsMailable(item, db) then return nil end
  keys = keys or ns.Mules.SortedKeys(db)
  for _, key in ipairs(keys) do
    if db.mules[key].items[item.itemID] then return key, "item" end
  end
  for _, key in ipairs(keys) do
    local categories = db.mules[key].categories
    for _, def in ipairs(ns.Categories.list) do
      if categories[def.key] and ns.Categories.Matches(def.key, item) then
        return key, def.key
      end
    end
  end
  return nil
end
