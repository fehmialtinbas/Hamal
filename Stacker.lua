local _, ns = ...

-- Combines partial stacks of the items about to be mailed (7 + 12 + 5 Linen Cloth
-- become 20 + 4), so fewer attachments, fewer mails and less postage. It only ever
-- moves items that are going to a bank alt anyway, one move at a time, and waits for
-- the server to confirm each move before the next.
local Stacker = {}
ns.Stacker = Stacker

local STEP_DELAY = 0.1
local MAX_LOCKED_STEPS = 30 -- give up after ~3 s of slots that stay locked
-- Each move removes one partial stack, so a full set of bags never needs more.
local MAX_MOVES = 150

function Stacker.MaxStack(itemID)
  if C_Item and C_Item.GetItemMaxStackSizeByID then
    local size = C_Item.GetItemMaxStackSizeByID(itemID)
    if size then return size end
  end
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if getInfo then return (select(8, getInfo(itemID))) end
  return nil
end

-- Stacks going to `targetKey`, grouped by item ID. A locked stack (one just moved,
-- or picked up by the player) is reported instead of listed.
local function stacksByItem(db, targetKey)
  local keys = ns.Mules.ActiveKeys(db)
  local groups, anyLocked = {}, false
  ns.Scanner.EachItem(function(item)
    local locked = item.isLocked
    item.isLocked = false
    local key = ns.Rules.Resolve(item, db, keys)
    if key == targetKey then
      if locked then
        anyLocked = true
      else
        local group = groups[item.itemID]
        if not group then
          group = {}
          groups[item.itemID] = group
        end
        group[#group + 1] = item
      end
    end
  end)
  return groups, anyLocked
end

local function bySize(a, b)
  if a.count ~= b.count then return a.count < b.count end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

-- The next merge: the smallest partial stack onto the fullest other partial one.
-- Returns from, to (bag items), anyLocked.
function Stacker.NextMove(db, targetKey, skip)
  local groups, anyLocked = stacksByItem(db, targetKey)
  local ids = {}
  for itemID in pairs(groups) do ids[#ids + 1] = itemID end
  table.sort(ids)
  for _, itemID in ipairs(ids) do
    local max = Stacker.MaxStack(itemID)
    if max and max > 1 and not (skip and skip[itemID]) then
      local partial = {}
      for _, item in ipairs(groups[itemID]) do
        if item.count < max then partial[#partial + 1] = item end
      end
      if #partial >= 2 then
        table.sort(partial, bySize)
        return partial[1], partial[#partial], anyLocked
      end
    end
  end
  return nil, nil, anyLocked
end

function Stacker.HasWork(db, targetKey)
  return (Stacker.NextMove(db, targetKey)) ~= nil
end

-- Merge until nothing is left to merge, then call onDone. `job.cancelled` stops it.
function Stacker.Run(db, targetKey, job, onDone)
  local moves, lockedSteps = 0, 0
  local skip, last = {}, nil

  local function step()
    if job.cancelled or not ns.Mailer.IsMailboxOpen() or CursorHasItem() then
      return onDone() -- the player is holding an item or left: don't touch anything
    end
    local from, to, anyLocked = Stacker.NextMove(db, targetKey, skip)
    if anyLocked then
      -- Wait for the server to confirm the last move.
      lockedSteps = lockedSteps + 1
      if lockedSteps > MAX_LOCKED_STEPS then return onDone() end
      return ns.After(STEP_DELAY, step)
    end
    -- A confirmed move that changed nothing (the game refused it) is not tried again.
    if last then
      local info = C_Container.GetContainerItemInfo(last.bag, last.slot)
      local unchanged = info and info.itemID == last.itemID and info.stackCount == last.count
      local itemID = last.itemID
      last = nil
      if unchanged then
        skip[itemID] = true
        from, to = Stacker.NextMove(db, targetKey, skip)
      end
    end
    if not from or moves >= MAX_MOVES then return onDone() end
    lockedSteps = 0
    moves = moves + 1
    last = { bag = from.bag, slot = from.slot, itemID = from.itemID, count = from.count }
    C_Container.PickupContainerItem(from.bag, from.slot)
    C_Container.PickupContainerItem(to.bag, to.slot)
    if CursorHasItem() then ClearCursor() end -- didn't merge: put it back where it was
    ns.After(STEP_DELAY, step)
  end

  step()
end
