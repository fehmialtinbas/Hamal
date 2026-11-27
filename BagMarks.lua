local _, ns = ...

-- Where your items go, shown where you look at them:
--   * the tooltip of an item in your bags says which bank alt gets it ("Hamal: goes to
--     Vault Keeper"), at the mailbox or not, and how many you keep of it (Options can
--     switch this off);
--   * while a mailbox is open, stacks about to be mailed look greyed out in the game's
--     own bags;
--   * at the mailbox, Alt-click on one of them keeps that item in the bags for the rest
--     of the visit, and another Alt-click sends it again (Options can switch this off).
--
-- Bag addons (Bagnon, Baganator, AdiBags, ElvUI...) draw bags of their own. Hamal reads
-- none of their frames, so they get no grey marks; the tooltip line and Alt-click work
-- with them, because they hook the game's tooltip and click handling, not a bag.
--
-- Away from a mailbox the only work is on hovering an item in your bags: that one slot
-- is read and checked against your rules. At the mailbox the bag buttons are walked once
-- per refresh (already merged into one per frame by UI.RequestRefresh).
local BagMarks = {}
ns.BagMarks = BagMarks

-- Drawn between the item's icon and its stack count, so the count stays readable.
local SHADE = { 0.08, 0.08, 0.08, 0.72 }

local slots = nil -- while a mailbox is open: [SlotKey] = bank alt key
-- The bag slot under the mouse at the mailbox, from its tooltip: { owner, bag, slot }.
-- That is how an Alt-click is matched to a stack, in the game's bags or a bag addon's.
local hovered = nil
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
  hovered = nil
  for _, mark in pairs(marks) do
    mark:Hide()
  end
end

-- The bank alt the stack in this bag slot goes to, or nil. Away from the mailbox also
-- the stack, as read for that.
function BagMarks.Destination(bag, slot)
  local db = ns.db
  if not db or not bag or not slot then return nil end
  -- At the mailbox: what this visit will really send.
  if slots then return slots[ns.Scanner.SlotKey(bag, slot)] end
  if not ns.Scanner.IsMailBag(bag) then return nil end -- the bank, for one
  local item = ns.Scanner.ReadSlot(bag, slot)
  local key = item and ns.Rules.Resolve(item, db)
  if not key or key == ns.NormalizeName(ns.PlayerName()) then return nil end
  return key, item
end

local GOLD = { 0.9, 0.72, 0.36 }
local HINT = { 0.6, 0.8, 1 }

local function altClickOn()
  return ns.db and ns.db.options.altClickKeep
end

-- At the mailbox, a stack not in this visit's mail that a rule would send: one a keep
-- amount holds back.
local function keptBack(item)
  local key = ns.Rules.Resolve(item, ns.db)
  return key ~= nil and key ~= ns.NormalizeName(ns.PlayerName())
end

local function onBagItemTooltip(tooltip, bag, slot)
  if ns.Widgets.ownTooltip then return end
  hovered = nil
  if slots and bag and slot and ns.Scanner.IsMailBag(bag) then
    hovered = { owner = tooltip:GetOwner(), bag = bag, slot = slot }
  end
  local db = ns.db
  if not (db and db.options.bagTooltips) then return end
  local key, item = BagMarks.Destination(bag, slot)
  local hint
  if hovered then
    item = ns.Scanner.ReadSlot(bag, slot)
    if not item then return end
    if ns.Rules.held[item.itemID] then
      tooltip:AddLine("Hamal: stays in your bags this time", GOLD[1], GOLD[2], GOLD[3])
      if altClickOn() then tooltip:AddLine(ns.AltClick() .. ": send it", HINT[1], HINT[2], HINT[3]) end
      tooltip:Show()
      return
    end
    hint = altClickOn() and (ns.AltClick() .. ": keep it this time") or nil
  end
  local mule = key and db.mules[key]
  local keep = item and ns.Rules.KeepAmount(db, item.itemID)
  local keepText = keep and (" (you keep %d)"):format(keep) or ""
  if mule then
    tooltip:AddLine(("Hamal: goes to %s%s"):format(mule.name, keepText), GOLD[1], GOLD[2], GOLD[3])
  elseif hovered and keep and keptBack(item) then
    tooltip:AddLine("Hamal: stays in your bags" .. keepText, GOLD[1], GOLD[2], GOLD[3])
    if hint then hint = ns.AltClick() .. ": keep all of it this time" end
  else
    return
  end
  if hint then tooltip:AddLine(hint, HINT[1], HINT[2], HINT[3]) end
  tooltip:Show() -- fit the new line
end

local function linkedItemID(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Alt-click (left button, no other modifier) on a stack in your bags at the mailbox
-- keeps that item in the bags this visit, or lets it go again. On a Mac that is the
-- Option key, which the game reports as Alt (IsAltKeyDown), so the texts say Option. Plain clicks stay the
-- game's: a left-click picks the item up and a right-click puts it into the mail, and
-- Hamal never takes those over. The game passes every modified click on an item
-- through HandleModifiedItemClick; Hamal only listens after the game has handled it.
local function onModifiedItemClick(link)
  if not slots or not hovered or not altClickOn() then return end
  if not (IsAltKeyDown and IsAltKeyDown()) then return end
  if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
  if GetMouseButtonClicked and GetMouseButtonClicked() ~= "LeftButton" then return end
  -- The click must be on the bag slot whose tooltip is up, not on a chat link.
  if not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= hovered.owner then return end
  local item = ns.Scanner.ReadSlot(hovered.bag, hovered.slot)
  if not item then return end
  local linked = linkedItemID(link)
  if linked and linked ~= item.itemID then return end
  if ns.Mailer.ToggleHold(item) and GameTooltip:GetOwner() == hovered.owner then
    -- Say the new state at once in the tooltip that is up.
    local bag, slot = hovered.bag, hovered.slot
    GameTooltip:SetBagItem(bag, slot)
  end
end

ns.OnInit(function()
  if GameTooltip and GameTooltip.SetBagItem then
    hooksecurefunc(GameTooltip, "SetBagItem", ns.Safely(onBagItemTooltip))
  end
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", ns.Safely(onModifiedItemClick))
  end
end)
