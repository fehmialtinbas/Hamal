-- A small fake of the WoW client: bags, cursor, the Send Mail form and the mail server.
-- It models only what Hamal touches, closely enough to test the mailing flow offline.
local unpack = unpack or table.unpack

local Mock = {}

-- Widgets -----------------------------------------------------------------------

local Frame = {}
local FrameMT = {
  __index = function(_, key)
    local method = Frame[key]
    if method then return method end
    -- Layout and styling methods we don't model (SetPoint, SetBackdrop...) are no-ops;
    -- plain fields (lowercase) stay nil.
    if type(key) == "string" and key:match("^%u") then
      return function() end
    end
    return nil
  end,
}

local function fireScript(frame, script, ...)
  local fn = frame.scripts[script]
  if fn then fn(frame, ...) end
  local hooks = frame.hooks[script]
  if hooks then
    for i = 1, #hooks do hooks[i](frame, ...) end
  end
end

Frame.FireScript = fireScript
function Frame:SetScript(script, fn) self.scripts[script] = fn end
function Frame:GetScript(script) return self.scripts[script] end
function Frame:HookScript(script, fn)
  self.hooks[script] = self.hooks[script] or {}
  table.insert(self.hooks[script], fn)
end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:Show()
  if not self.shown then
    self.shown = true
    fireScript(self, "OnShow")
  end
end
function Frame:Hide()
  if self.shown then
    self.shown = false
    fireScript(self, "OnHide")
  end
end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
  if not self.shown then return false end
  if self.parent then return self.parent:IsVisible() end
  return true
end
function Frame:SetText(text)
  local old = self.text
  self.text = text or ""
  if self.objType == "EditBox" and old ~= self.text then
    fireScript(self, "OnTextChanged", false)
  end
end
function Frame:GetText() return self.text end
function Frame:SetEnabled(on) self.enabled = not not on end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:IsEnabled() return self.enabled end
function Frame:CreateFontString() return Mock.newFrame("FontString", nil, self) end
function Frame:Click()
  if self.enabled then fireScript(self, "OnClick", "LeftButton") end
end

function Mock.newFrame(objType, name, parent)
  local frame = setmetatable({
    objType = objType, name = name, parent = parent, shown = true, text = "", enabled = true,
    scripts = {}, hooks = {}, events = {},
  }, FrameMT)
  table.insert(Mock.world.frames, frame)
  if name then _G[name] = frame end
  return frame
end

-- World -------------------------------------------------------------------------

local World = {}
World.__index = World

function Mock.new()
  local w = setmetatable({
    frames = {}, timers = {}, bags = {}, bagSize = {}, items = {}, mail = {}, sent = {}, printed = {},
    cursor = nil, money = 100000, hardware = false, requireHardware = false, pending = false,
    failNext = false, playerName = "Main Character",
  }, World)
  Mock.world = w
  for bag = 0, 4 do w.bagSize[bag] = 16 end
  w:installGlobals()
  return w
end

function World:installGlobals()
  local w = self

  _G.CreateFrame = function(objType, name, parent) return Mock.newFrame(objType, name, parent) end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(w.printed, msg) end }
  _G.C_Timer = { After = function(_, fn) table.insert(w.timers, fn) end }
  _G.UnitName = function() return w.playerName end
  _G.NUM_BAG_SLOTS = 4
  _G.ATTACHMENTS_MAX_SEND = 12
  _G.Enum = { BagIndex = { ReagentBag = 5 } }
  _G.SlashCmdList = {}
  _G.HamalDB = nil
  _G.GetMoney = function() return w.money end
  _G.GetCoinTextureString = function(copper) return copper .. "c" end
  _G.SetSendMailMoney = function() end
  _G.SetSendMailCOD = function() end

  _G.C_Item = {
    GetItemInfoInstant = function(id)
      local d = w.items[id]
      if not d then return nil end
      return id, nil, nil, nil, nil, d.classID, d.subclassID
    end,
    GetItemInfo = function(id)
      local d = w.items[id]
      if not d then return nil end
      return d.name, "[" .. d.name .. "]"
    end,
  }

  _G.C_Container = {
    GetContainerNumSlots = function(bag) return w.bagSize[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local it = w.bags[bag] and w.bags[bag][slot]
      if not it then return nil end
      local d = w.items[it.itemID]
      return {
        itemID = it.itemID, stackCount = it.count, isLocked = it.locked, isBound = it.bound,
        quality = d.quality, hyperlink = "[" .. d.name .. "]", itemName = d.name,
      }
    end,
    -- The real item stays in its bag slot, locked, while it is on the cursor or attached.
    PickupContainerItem = function(bag, slot)
      local it = w.bags[bag] and w.bags[bag][slot]
      if w.cursor or not it or it.locked then return end
      it.locked = true
      w.cursor = it
    end,
  }

  _G.CursorHasItem = function() return w.cursor ~= nil end
  _G.ClearCursor = function()
    if w.cursor then
      w.cursor.locked = false
      w.cursor = nil
    end
  end

  _G.GetSendMailItem = function(i)
    local it = w.mail[i]
    if not it then return nil end
    local d = w.items[it.itemID]
    return d.name, it.itemID, 0, it.count, d.quality
  end
  _G.GetSendMailPrice = function()
    local n = 0
    for i = 1, 12 do
      if w.mail[i] then n = n + 1 end
    end
    return n * 30
  end
  _G.ClickSendMailItemButton = function(i, clear)
    if clear then
      local it = w.mail[i]
      if it then
        it.locked = false
        w.mail[i] = nil
      end
      return
    end
    local it = w.cursor
    if not it or w.mail[i] or it.noMail then return end
    w.mail[i] = it
    w.cursor = nil
  end

  _G.SendMail = function(to, subject)
    assert(type(subject) == "string" and subject ~= "", "SendMail needs a subject")
    if w.requireHardware and not w.hardware then
      w:Fire("ADDON_ACTION_BLOCKED", "Hamal", "SendMail()")
      return
    end
    if w.pending then return end -- the client ignores sends until the last one is answered
    w.pending = true
    if w.failNext then
      w.failNext = false
      table.insert(w.timers, function()
        w.pending = false
        w:Fire("MAIL_FAILED")
      end)
      return
    end
    local items = {}
    for i = 1, 12 do
      local it = w.mail[i]
      if it then
        items[#items + 1] = it
        w.bags[it.bag][it.slot] = nil
      end
    end
    w.mail = {}
    w.money = w.money - 30 * #items
    table.insert(w.sent, { to = to, subject = subject, items = items })
    table.insert(w.timers, function()
      w.pending = false
      _G.SendMailNameEditBox:SetText("") -- the default UI clears the form after a send
      w:Fire("MAIL_SEND_SUCCESS")
    end)
  end

  _G.hooksecurefunc = function(tbl, name, fn)
    if type(tbl) == "string" then
      tbl, name, fn = _G, tbl, name
    end
    local original = tbl[name]
    tbl[name] = function(...)
      local results = { original(...) }
      fn(...)
      return unpack(results)
    end
  end

  _G.MailFrame = Mock.newFrame("Frame", "MailFrame")
  _G.SendMailFrame = Mock.newFrame("Frame", "SendMailFrame", _G.MailFrame)
  _G.SendMailNameEditBox = Mock.newFrame("EditBox", "SendMailNameEditBox", _G.SendMailFrame)
  _G.MailFrameTab2 = Mock.newFrame("Button", "MailFrameTab2", _G.MailFrame)
  _G.MailFrame.shown = false -- closed until OpenMailbox()
end

function World:DefineItem(id, name, classID, subclassID, quality)
  self.items[id] = { name = name, classID = classID, subclassID = subclassID, quality = quality or 1 }
end

function World:Put(bag, slot, itemID, count, opts)
  self.bags[bag] = self.bags[bag] or {}
  self.bags[bag][slot] = {
    itemID = itemID, count = count or 1, bag = bag, slot = slot,
    bound = opts and opts.bound, noMail = opts and opts.noMail,
  }
end

-- Put `stacks` stacks of an item into the first free bag slots.
function World:Fill(itemID, stacks, count, opts)
  for _ = 1, stacks do
    local placed = false
    for bag = 0, 4 do
      for slot = 1, self.bagSize[bag] do
        if not (self.bags[bag] and self.bags[bag][slot]) then
          self:Put(bag, slot, itemID, count, opts)
          placed = true
          break
        end
      end
      if placed then break end
    end
    assert(placed, "bags are full")
  end
end

function World:StacksInBags(itemID)
  local n = 0
  for _, slots in pairs(self.bags) do
    for _, it in pairs(slots) do
      if it.itemID == itemID then n = n + 1 end
    end
  end
  return n
end

function World:LockedInBags()
  local n = 0
  for _, slots in pairs(self.bags) do
    for _, it in pairs(slots) do
      if it.locked then n = n + 1 end
    end
  end
  return n
end

function World:Fire(event, ...)
  for _, frame in ipairs(self.frames) do
    if frame.events[event] then
      local fn = frame.scripts.OnEvent
      if fn then fn(frame, event, ...) end
    end
  end
end

-- Run every pending C_Timer callback (and any they schedule), in order.
function World:Flush()
  local guard = 0
  while #self.timers > 0 do
    guard = guard + 1
    assert(guard < 1000, "timers keep scheduling timers")
    local fn = table.remove(self.timers, 1)
    fn()
  end
end

function World:OpenMailbox()
  _G.MailFrame:Show()
  _G.SendMailFrame.shown = true
  self:Fire("MAIL_SHOW")
end

function World:CloseMailbox()
  _G.MailFrame:Hide()
end

-- The player typing into the "To:" box.
function World:Type(text)
  local box = _G.SendMailNameEditBox
  box.text = text
  box:FireScript("OnTextChanged", true)
end

-- A real mouse click: hardware-event-only APIs are allowed during it.
function World:Click(button)
  self.hardware = true
  button:Click()
  self.hardware = false
end

function World:Printed(pattern)
  for _, msg in ipairs(self.printed) do
    if msg:find(pattern) then return true end
  end
  return false
end

-- Loads the addon files in TOC order, like the client does, and fires ADDON_LOADED.
function Mock.loadAddon(world)
  local ns = {}
  for line in io.lines("Hamal.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then
      local chunk = assert(loadfile(line))
      chunk("Hamal", ns)
    end
  end
  world:Fire("ADDON_LOADED", "Hamal")
  return ns
end

return Mock
