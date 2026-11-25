local _, ns = ...

-- While a mailbox is open: items about to be mailed look greyed out in the game's own
-- bags, and an item's tooltip says which bank alt it goes to.
--
-- Bag addons (Bagnon, Baganator, AdiBags, ElvUI...) draw bags of their own. Hamal reads
-- none of their frames, so they get no grey marks; the tooltip line works with all of
-- them, because it hooks the game's tooltip, not a bag.
--
-- Nothing here runs away from a mailbox: the maps are empty and every hook returns at
-- once. At the mailbox, the bag buttons are walked once per refresh (already merged
-- into one per frame by UI.RequestRefresh).
local BagMarks = {}
ns.BagMarks = BagMarks

-- Drawn between the item's icon and its stack count, so the count stays readable.
local SHADE = { 0.08, 0.08, 0.08, 0.72 }

local slots, items = nil, nil -- [SlotKey] = bank alt key, [itemID] = bank alt key
local marks = setmetatable({}, { __mode = "k" }) -- [bag button] = our texture
local hookedFrames = {}
BagMarks.marks = marks

-- The game's bag windows: the combined backpack of newer clients and one window per bag.
local function bagFrames()
  local frames = {}
  if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local frame = _G["ContainerFrame" .. i]
    if frame then frames[#frames + 1] = frame end
  end
  return frames
end

-- Every item button a bag window shows, with its bag and slot.
local function eachButton(frame, fn)
  if frame.EnumerateValidItems then
    for _, button in frame:EnumerateValidItems() do
      fn(button, button.GetBagID and button:GetBagID() or frame:GetID(), button:GetID())
    end
    return
  end
  local name = frame:GetName()
  if not name then return end
  local bag = frame:GetID()
  for i = 1, frame.size or 36 do
    local button = _G[name .. "Item" .. i]
    if not button then break end
    if button:IsShown() then fn(button, bag, button:GetID()) end
  end
end

local function markOf(button)
  local mark = marks[button]
  if not mark then
    local icon = button.icon or button.Icon or _G[(button:GetName() or "") .. "IconTexture"]
    mark = button:CreateTexture(nil, "ARTWORK", nil, 1)
    mark:SetColorTexture(SHADE[1], SHADE[2], SHADE[3], SHADE[4])
    mark:SetAllPoints(icon or button)
    marks[button] = mark
  end
  return mark
end

function BagMarks.Apply()
  if not slots then return end
  for _, frame in ipairs(bagFrames()) do
    if frame:IsShown() then
      eachButton(frame, function(button, bag, slot)
        local going = bag and slot and slots[ns.Scanner.SlotKey(bag, slot)] ~= nil
        if going then
          markOf(button):Show()
        elseif marks[button] then
          marks[button]:Hide()
        end
      end)
    end
  end
end

-- A bag window opened after the mailbox (or rebuilt its buttons): mark it next frame,
-- once the game has filled it.
local applyQueued = false
local function requestApply()
  if applyQueued or not slots then return end
  applyQueued = true
  ns.After(0, function()
    applyQueued = false
    BagMarks.Apply()
  end)
end

local function hookFrames()
  for _, frame in ipairs(bagFrames()) do
    if not hookedFrames[frame] then
      hookedFrames[frame] = true
      frame:HookScript("OnShow", ns.Safely(requestApply))
    end
  end
end

-- What goes where right now (from Scanner.Summary). A stack left out of the running
-- session stays in the bags, so it isn't marked.
function BagMarks.Update(slotMap, itemMap, session)
  if session then
    local queued = {}
    for _, item in ipairs(session.queue) do
      queued[ns.Scanner.SlotKey(item.bag, item.slot)] = true
    end
    for slotKey, key in pairs(slotMap) do
      if key == session.key and not queued[slotKey] then slotMap[slotKey] = nil end
    end
  end
  slots, items = slotMap, itemMap
  hookFrames()
  BagMarks.Apply()
end

function BagMarks.Clear()
  slots, items = nil, nil
  for _, mark in pairs(marks) do
    mark:Hide()
  end
end

-- The bank alt an item goes to, while a mailbox is open.
function BagMarks.Destination(itemID)
  return items and itemID and items[itemID]
end

local function addTooltipLine(tooltip, itemID)
  if not items or tooltip ~= GameTooltip then return end
  local key = BagMarks.Destination(itemID)
  local mule = key and ns.db and ns.db.mules[key]
  if not mule then return end
  tooltip:AddLine(("Hamal: goes to %s"):format(mule.name), 0.9, 0.72, 0.36)
end

local function itemIDFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

ns.OnInit(function()
  local types = Enum and Enum.TooltipDataType
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and types and types.Item then
    TooltipDataProcessor.AddTooltipPostCall(types.Item, ns.Safely(function(tooltip, data)
      addTooltipLine(tooltip, data and data.id)
    end))
  elseif GameTooltip and GameTooltip.HookScript then
    -- Older clients; pcall because a client without this script would raise an error.
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", ns.Safely(function(tooltip)
      if not items then return end
      local _, link = tooltip:GetItem()
      addTooltipLine(tooltip, itemIDFromLink(link))
    end))
  end
end)
