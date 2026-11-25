local _, ns = ...

-- Where your items go, shown where you look at them:
--   * the tooltip of an item in your bags says which bank alt gets it ("Hamal: goes to
--     Vault Keeper"), at the mailbox or not (Options can switch this off);
--   * while a mailbox is open, stacks about to be mailed look greyed out in the game's
--     own bags.
--
-- Bag addons (Bagnon, Baganator, AdiBags, ElvUI...) draw bags of their own. Hamal reads
-- none of their frames, so they get no grey marks; the tooltip line works with them,
-- because it hooks the game's tooltip, not a bag.
--
-- Away from a mailbox the only work is on hovering an item in your bags: that one slot
-- is read and checked against your rules. At the mailbox the bag buttons are walked once
-- per refresh (already merged into one per frame by UI.RequestRefresh).
local BagMarks = {}
ns.BagMarks = BagMarks

-- Drawn between the item's icon and its stack count, so the count stays readable.
local SHADE = { 0.08, 0.08, 0.08, 0.72 }

local slots = nil -- while a mailbox is open: [SlotKey] = bank alt key
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

-- What this mailbox visit sends (from Scanner.Summary). A stack left out of the running
-- session stays in the bags, so it isn't marked.
function BagMarks.Update(slotMap, session)
  if session then
    local queued = {}
    for _, item in ipairs(session.queue) do
      queued[ns.Scanner.SlotKey(item.bag, item.slot)] = true
    end
    for slotKey, key in pairs(slotMap) do
      if key == session.key and not queued[slotKey] then slotMap[slotKey] = nil end
    end
  end
  slots = slotMap
  hookFrames()
  BagMarks.Apply()
end

function BagMarks.Clear()
  slots = nil
  for _, mark in pairs(marks) do
    mark:Hide()
  end
end

-- The bank alt the stack in this bag slot goes to, or nil.
function BagMarks.Destination(bag, slot)
  local db = ns.db
  if not db or not bag or not slot then return nil end
  -- At the mailbox: what this visit will really send.
  if slots then return slots[ns.Scanner.SlotKey(bag, slot)] end
  if not ns.Scanner.IsMailBag(bag) then return nil end -- the bank, for one
  local item = ns.Scanner.ReadSlot(bag, slot)
  local key = item and ns.Rules.Resolve(item, db)
  if not key or key == ns.NormalizeName(ns.PlayerName()) then return nil end
  return key
end

local function onBagItemTooltip(tooltip, bag, slot)
  if ns.Widgets.ownTooltip or not (ns.db and ns.db.options.bagTooltips) then return end
  local key = BagMarks.Destination(bag, slot)
  local mule = key and ns.db.mules[key]
  if not mule then return end
  tooltip:AddLine(("Hamal: goes to %s"):format(mule.name), 0.9, 0.72, 0.36)
  tooltip:Show() -- fit the new line
end

ns.OnInit(function()
  if GameTooltip and GameTooltip.SetBagItem then
    hooksecurefunc(GameTooltip, "SetBagItem", ns.Safely(onBagItemTooltip))
  end
end)
