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
function Frame:SetShown(on)
  if on then self:Show() else self:Hide() end
end
function Frame:IsShown() return self.shown end
function Frame:HasFocus() return self.focus == true end
function Frame:SetChecked(on) self.checked = not not on end
function Frame:GetChecked() return self.checked == true end
function Frame:CreateTexture() return Mock.newFrame("Texture", nil, self) end
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
  if not self.enabled then return end
  if self.objType == "CheckButton" then self.checked = not self.checked end
  fireScript(self, "OnClick", "LeftButton")
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
    failNext = false, playerName = "Main Character", playerClass = "ROGUE", playerLevel = 22,
    playerFaction = "Horde", realmName = "PvP", gameRules = { [213] = true },
  }, World)
  Mock.world = w
  for bag = 0, 4 do w.bagSize[bag] = 16 end
  return w
end

function World:installGlobals()
  local w = self

  _G.CreateFrame = function(objType, name, parent) return Mock.newFrame(objType, name, parent) end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(w.printed, msg) end }
  _G.C_Timer = { After = function(_, fn) table.insert(w.timers, fn) end }
  -- Forever: characters have a first and a last name; UnitFullName returns both.
  _G.WOW_PROJECT_ID = 18
  _G.UnitName = function() return (w.playerName:match("^(%S+)")) end
  _G.UnitFullName = function() return w.playerName:match("^(%S+)%s*(.-)$") end
  _G.UnitClass = function() return "Rogue", w.playerClass end
  _G.UnitLevel = function() return w.playerLevel end
  _G.UnitFactionGroup = function() return w.playerFaction end
  -- One realm per ruleset, named after it (as AceDB profile keys show: "Name - PvP").
  _G.GetRealmName = function() return w.realmName end
  _G.C_GameRules = { IsGameRuleActive = function(rule) return w.gameRules[rule] == true end }
  _G.BrotherBags = w.brotherBags
  _G.RAID_CLASS_COLORS = {}
  _G.ITEM_QUALITY_COLORS = {}
  _G.MenuUtil = {
    CreateContextMenu = function(owner, generator)
      local entries = {}
      local root = {}
      function root.CreateTitle(_, label) entries[#entries + 1] = { title = label } end
      function root.CreateDivider() end
      function root.CreateRadio(_, label, isSelected, setSelected, data)
        entries[#entries + 1] = { text = label, selected = isSelected(data), pick = function() setSelected(data) end }
      end
      generator(owner, root)
      w.menu = entries
    end,
  }
  _G.NUM_BAG_SLOTS = 4
  _G.ATTACHMENTS_MAX_SEND = 12
  _G.Enum = {
    BagIndex = { ReagentBag = 5 },
    GameRule = { HardcoreRuleset = 10, PvPRuleset = 213, RPRuleset = 214 },
    PlayerInteractionType = { MailInfo = 17 },
  }
  _G.unpack = unpack -- the game's Lua 5.1 has it as a global
  _G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
  -- The game's error frame; only installed when a test asks for it.
  w.errors = {}
  _G.geterrorhandler = w.useErrorHandler and function()
    return function(err) table.insert(w.errors, err) end
  end or nil
  _G.SlashCmdList = {}
  _G.HamalDB = w.savedDB -- Hamal's saved data from earlier sessions, if a test gives some
  _G.GetMoney = function() return w.money end
  _G.GetCoinTextureString = function(copper) return copper .. "c" end
  _G.SetSendMailMoney = function() end
  _G.SetSendMailCOD = function() end
  _G.IsShiftKeyDown = function() return w.shift end
  _G.UISpecialFrames = {}
  _G.YES, _G.NO = "Yes", "No"
  _G.StaticPopupDialogs = {}
  _G.StaticPopup_Show = function(which, _, _, data)
    w.popup = { which = which, data = data }
  end
  _G.GetCursorInfo = function()
    if w.cursor then return "item", w.cursor.itemID end
  end

  w.calls = { info = 0, request = 0 }
  _G.C_Item = {
    -- Items the test defined count as cached; anything else would need the server.
    IsItemDataCachedByID = function(id) return w.items[id] ~= nil end,
    GetItemMaxStackSizeByID = function(id)
      local d = w.items[id]
      return d and d.stack
    end,
    RequestLoadItemDataByID = function() w.calls.request = w.calls.request + 1 end,
    GetItemInfoInstant = function(id)
      local d = w.items[id]
      if not d then return nil end
      return id, nil, nil, nil, 100000 + id, d.classID, d.subclassID
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
      w.calls.info = w.calls.info + 1
      local it = w.bags[bag] and w.bags[bag][slot]
      if not it then return nil end
      local d = w.items[it.itemID]
      return {
        itemID = it.itemID, stackCount = it.count, isLocked = it.locked, isBound = it.bound,
        quality = d.quality, hyperlink = "[" .. d.name .. "]", itemName = d.name, iconFileID = 100000 + it.itemID,
      }
    end,
    -- Picking up: the item stays in its bag slot, locked, while it is on the cursor.
    -- With an item on the cursor, clicking another stack of the same item merges them
    -- (up to the stack size; the rest stays where it was). Both slots stay locked until
    -- the "server" confirms the move a moment later.
    PickupContainerItem = function(bag, slot)
      local it = w.bags[bag] and w.bags[bag][slot]
      local held = w.cursor
      if held then
        if it == held then
          held.locked = false
          w.cursor = nil
          return
        end
        if not it or it.itemID ~= held.itemID or it.locked then return end
        local room = w.items[it.itemID].stack - it.count
        local moved = math.min(room, held.count)
        if moved <= 0 then return end
        it.count = it.count + moved
        held.count = held.count - moved
        if held.count == 0 then w.bags[held.bag][held.slot] = nil end
        w.cursor = nil
        it.locked, held.locked = true, held.count > 0
        w.moves = (w.moves or 0) + 1
        if not w.stuckLocks then
          table.insert(w.timers, function()
            it.locked, held.locked = false, false
            w:Fire("BAG_UPDATE_DELAYED")
          end)
        end
        return
      end
      if not it or it.locked then return end
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

  _G.UIParent = Mock.newFrame("Frame", "UIParent")
  _G.GameTooltip = Mock.newFrame("GameTooltip", "GameTooltip", _G.UIParent)
  _G.MailFrame = Mock.newFrame("Frame", "MailFrame")
  _G.SendMailFrame = Mock.newFrame("Frame", "SendMailFrame", _G.MailFrame)
  _G.SendMailNameEditBox = Mock.newFrame("EditBox", "SendMailNameEditBox", _G.SendMailFrame)
  _G.MailFrameTab2 = Mock.newFrame("Button", "MailFrameTab2", _G.MailFrame)
  _G.MailFrame.shown = false -- closed until OpenMailbox()
end

function World:DefineItem(id, name, classID, subclassID, quality, stack)
  self.items[id] = { name = name, classID = classID, subclassID = subclassID, quality = quality or 1, stack = stack or 20 }
end

-- How many separate stacks of an item, and their sizes, sorted.
function World:StackSizes(itemID)
  local sizes = {}
  for _, slots in pairs(self.bags) do
    for _, it in pairs(slots) do
      if it.itemID == itemID then sizes[#sizes + 1] = it.count end
    end
  end
  table.sort(sizes)
  return table.concat(sizes, ",")
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

function World:ShiftClick(button)
  self.shift = true
  self:Click(button)
  self.shift = false
end

-- The player confirms the last StaticPopup.
function World:AcceptPopup()
  local popup = assert(self.popup, "no popup is open")
  self.popup = nil
  _G.StaticPopupDialogs[popup.which].OnAccept(nil, popup.data)
end

-- The player types into an edit box and presses Enter.
function World:Enter(box, value)
  box.text = value
  box:FireScript("OnEnterPressed")
end

-- The player picks up a bag item and drops it on `target`.
function World:DragItem(bag, slot, target)
  _G.C_Container.PickupContainerItem(bag, slot)
  target:FireScript("OnReceiveDrag")
end

function World:Printed(pattern)
  for _, msg in ipairs(self.printed) do
    if msg:find(pattern) then return true end
  end
  return false
end

-- The player picks the menu entry whose text contains `label`.
function World:PickMenu(label)
  for _, entry in ipairs(self.menu or {}) do
    if entry.pick and entry.text:find(label, 1, true) then
      self.menu = nil
      entry.pick()
      return
    end
  end
  error("no menu entry " .. label)
end

-- Loads the addon files in TOC order, like the client does, then logs in.
function Mock.loadAddon(world)
  world:installGlobals()
  local ns = {}
  for line in io.lines("Hamal.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then
      local chunk = assert(loadfile(line))
      chunk("Hamal", ns)
    end
  end
  world:Fire("ADDON_LOADED", "Hamal")
  world:Fire("PLAYER_LOGIN")
  return ns
end

return Mock
