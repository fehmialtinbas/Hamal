local _, ns = ...

local Rules = {}
ns.Rules = Rules

local QUEST_ITEM_CLASS = 12
Rules.QUEST_ITEM_CLASS = QUEST_ITEM_CLASS

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

-- Items kept in the bags for the rest of this mailbox visit (Alt-click in the bags, see
-- BagMarks.lua): [itemID] = true. Not saved; emptied when the mailbox closes.
Rules.held = {}

-- "Keep at least N in my bags" for an item (db.keep[itemID] = N), or nil.
function Rules.KeepAmount(db, itemID)
  local amount = tonumber(db.keep and db.keep[itemID])
  if not amount or amount < 1 then return nil end
  return math.floor(amount)
end

-- Which of an item's outgoing stacks stay so that at least `amount` remain in the bags.
-- Whole stacks only (nothing is split), and as few items as possible: the smallest stack
-- that covers what is still missing; when none does, the biggest one, and on. Taking a
-- stack out of `stacks` that wasn't picked never changes the pick, so a mail already
-- on its way doesn't move the line. Returns the stacks that stay.
function Rules.PickKept(stacks, amount)
  local kept, left, need = {}, {}, amount
  for i, stack in ipairs(stacks) do left[i] = stack end
  while need > 0 and #left > 0 do
    local pick
    for i, stack in ipairs(left) do
      if stack.count >= need and (not pick or stack.count < left[pick].count) then pick = i end
    end
    if not pick then
      for i, stack in ipairs(left) do
        if not pick or stack.count > left[pick].count then pick = i end
      end
    end
    need = need - left[pick].count
    kept[#kept + 1] = table.remove(left, pick)
  end
  return kept
end

function Rules.IsMailable(item, db)
  if not item or not item.itemID then return false end
  if item.isBound or item.isLocked then return false end
  if Rules.ALWAYS_KEEP[item.itemID] or db.exclude[item.itemID] then return false end
  if Rules.held[item.itemID] then return false end
  return true
end

-- Which bank alt should get this item, and why?
-- 1. An item rule beats any type rule.
-- 2. A specific type beats a broad one: an alt with "cloth" gets Linen Cloth
--    even if another alt takes "tradegoods" (Categories.list is ordered specific first).
-- 3. Between equal rules the alphabetically first bank alt wins, so the answer
--    never changes from one scan to the next.
-- Items of the game's Quest class (unbound ones such as Torn Bear Pelt, a Darkmoon
-- Faire turn-in) go only by an item rule: no item type ever sends them, so something
-- you carry for a quest never leaves unless you picked it yourself.
function Rules.Resolve(item, db, keys)
  if not Rules.IsMailable(item, db) then return nil end
  keys = keys or ns.Mules.ActiveKeys(db)
  for _, key in ipairs(keys) do
    if db.mules[key].items[item.itemID] then return key, "item" end
  end
  if item.classID == QUEST_ITEM_CLASS then return nil end
  for _, def in ipairs(ns.Categories.list) do
    if ns.Categories.Matches(def.key, item) then
      for _, key in ipairs(keys) do
        if db.mules[key].categories[def.key] then return key, def.key end
      end
    end
  end
  return nil
end
