local addonName, ns = ...

-- Drives one "session": filling the Send Mail form for one bank alt, 12 items at a
-- time, and sending batch after batch until nothing for that alt is left in the bags.
local Mailer = {}
ns.Mailer = Mailer

-- Seconds to wait for MAIL_SEND_SUCCESS / MAIL_FAILED before letting the player retry.
local SEND_TIMEOUT = 15
-- Short pauses so Blizzard's mail form finishes resetting before we refill it.
local REFILL_DELAY = 0.2
local CHAIN_DELAY = 0.3
-- How long the "To:" text must stay on a bank alt's name before we fill the mail.
local TYPE_DELAY = 0.4

local settingRecipient = false
local typeToken = 0

local function refresh()
  if ns.UI then ns.UI.Refresh() end
end

local function maxSlots()
  return ATTACHMENTS_MAX_SEND or 12
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function Mailer.AttachedCount()
  local n = 0
  for i = 1, maxSlots() do
    if GetSendMailItem(i) then n = n + 1 end
  end
  return n
end

function Mailer.IsMailboxOpen()
  return MailFrame ~= nil and MailFrame:IsShown()
end

-- Mails needed in total for this session, counting the ones already sent.
function Mailer.Estimate(s)
  local pending = #s.queue
  if not s.sending then pending = pending + Mailer.AttachedCount() end
  return s.mails + math.ceil(pending / maxSlots())
end

function Mailer.SetRecipient(name)
  if not SendMailNameEditBox or SendMailNameEditBox:GetText() == name then return end
  settingRecipient = true
  SendMailNameEditBox:SetText(name)
  settingRecipient = false
end

local function showSendTab()
  if SendMailFrame and not SendMailFrame:IsShown() and MailFrameTab2 then
    MailFrameTab2:Click()
  end
end

-- Fill the empty attachment slots from the session queue. Returns how many were attached.
function Mailer.AttachNext()
  local s = Mailer.session
  if not s or #s.queue == 0 then return 0 end
  if CursorHasItem() then
    ns.Print("Your cursor is holding an item. Put it down and try again.")
    return 0
  end
  local added = 0
  for i = 1, maxSlots() do
    if #s.queue == 0 then break end
    if not GetSendMailItem(i) then
      while #s.queue > 0 do
        local item = table.remove(s.queue, 1)
        local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
        -- Skip stacks that moved or got locked since the scan.
        if info and info.itemID == item.itemID and not info.isLocked then
          C_Container.PickupContainerItem(item.bag, item.slot)
          ClickSendMailItemButton(i)
          if CursorHasItem() then
            -- The game refused this item (e.g. it cannot be mailed); put it back and try the next one.
            ClearCursor()
          else
            s.attached[i] = item
            added = added + 1
            break
          end
        end
      end
    end
  end
  return added
end

function Mailer.Start(key)
  local db = ns.db
  local mule = db and db.mules[key]
  if not mule then return false end
  if not Mailer.IsMailboxOpen() then
    ns.Print("Open a mailbox first.")
    return false
  end
  local current = Mailer.session
  if current then
    if current.key == key then return true end
    if current.sending then
      ns.Print("Wait until the mail to %s has gone out.", current.name)
      return false
    end
    Mailer.Cancel()
  end
  if ns.NormalizeName(UnitName("player")) == key then
    ns.Print("You are logged in as %s. Use another character to fill this bank.", mule.name)
    return false
  end
  local queue = ns.Scanner.Collect(db, key)
  if #queue == 0 then
    ns.Print("Nothing in your bags goes to %s.", mule.name)
    return false
  end
  showSendTab()
  Mailer.session = {
    key = key,
    name = mule.name,
    queue = queue,
    attached = {},
    sent = 0,
    mails = 0,
    sending = false,
    chain = db.options.chain,
  }
  Mailer.SetRecipient(mule.name)
  Mailer.AttachNext()
  refresh()
  return true
end

function Mailer.Send()
  local s = Mailer.session
  if not s or s.sending then return false end
  if Mailer.AttachedCount() == 0 then Mailer.AttachNext() end
  if Mailer.AttachedCount() == 0 then
    Mailer.Finish()
    return false
  end
  local price = GetSendMailPrice and GetSendMailPrice() or 0
  if GetMoney() < price then
    ns.Print("Not enough money for postage (%s).", ns.FormatMoney(price))
    return false
  end
  -- Never let a leftover money or C.O.D. value ride along with a bank mail.
  if SetSendMailMoney then SetSendMailMoney(0) end
  if SetSendMailCOD then SetSendMailCOD(0) end
  local subject = ("Hamal %d/%d"):format(s.mails + 1, Mailer.Estimate(s))
  -- Called through the global on purpose: the SendMail hook below must see it.
  SendMail(s.name, subject, "")
  return true
end

function Mailer.Cancel()
  local s = Mailer.session
  if not s then return end
  Mailer.session = nil
  if not s.sending and Mailer.IsMailboxOpen() then
    for i in pairs(s.attached) do
      if GetSendMailItem(i) then ClickSendMailItemButton(i, true) end
    end
    if CursorHasItem() then ClearCursor() end
  end
  refresh()
end

function Mailer.Finish()
  local s = Mailer.session
  if not s then return end
  Mailer.session = nil
  if s.sent > 0 then
    ns.Print("Sent %d stack(s) to %s in %d mail(s).", s.sent, s.name, s.mails)
  end
  refresh()
end

-- Every SendMail call goes through here, ours or the Send button of the default UI,
-- so a session keeps going whichever button the player presses.
local function onSendMail(recipient)
  local s = Mailer.session
  if not s or s.sending then return end
  if s.blocked then
    -- The game refused this call (see onBlocked); nothing is on its way.
    s.blocked = false
    return
  end
  if ns.NormalizeName(recipient) ~= s.key then return end
  s.sending = true
  s.mails = s.mails + 1
  s.inFlight = s.attached
  s.attached = {}
  local mailNumber = s.mails
  C_Timer.After(SEND_TIMEOUT, function()
    if Mailer.session == s and s.sending and s.mails == mailNumber then
      s.sending = false
      s.attached = s.inFlight or {}
      s.inFlight = nil
      ns.Print("The mailbox did not answer. Press Send to try again.")
      refresh()
    end
  end)
  refresh()
end

local function onSendSuccess()
  local s = Mailer.session
  if not s or not s.sending then return end
  s.sending = false
  s.sent = s.sent + countKeys(s.inFlight or {})
  s.inFlight = nil
  if #s.queue == 0 then
    Mailer.Finish()
    return
  end
  -- Blizzard clears the form after a send; wait for that, then fill the next mail.
  s.awaitingRefill = true
  C_Timer.After(REFILL_DELAY, function()
    if Mailer.session ~= s then return end
    s.awaitingRefill = false
    if not Mailer.IsMailboxOpen() then return end
    Mailer.SetRecipient(s.name)
    Mailer.AttachNext()
    refresh()
    if s.chain and ns.db.options.chain then
      C_Timer.After(CHAIN_DELAY, function()
        if Mailer.session == s and not s.sending then Mailer.Send() end
      end)
    end
  end)
end

local function onSendFailed()
  local s = Mailer.session
  if not s or not s.sending then return end
  s.sending = false
  s.mails = s.mails - 1
  s.attached = s.inFlight or {}
  s.inFlight = nil
  s.chain = false
  ns.Print("The mail to %s failed. Check the name and your postage, then press Send.", s.name)
  refresh()
end

-- If this client only allows SendMail from a real click, stop chaining and let the
-- player press Send once per mail instead.
local function onBlocked(who, func)
  if who ~= addonName or type(func) ~= "string" or not func:find("SendMail") then return end
  ns.db.options.chain = false
  local s = Mailer.session
  if s then
    s.chain = false
    if s.sending then
      s.sending = false
      s.mails = s.mails - 1
      s.attached = s.inFlight or {}
      s.inFlight = nil
    else
      -- Our SendMail hook may still run for the refused call; tell it to ignore that one.
      s.blocked = true
      C_Timer.After(0, function() s.blocked = false end)
    end
  end
  ns.Print("The game wants a click for every mail here, so I turned off auto-chaining. "
    .. "Press Send for each batch (/hamal chain on to try again).")
  refresh()
end

local function onRecipientChanged(userInput)
  if settingRecipient or not ns.db or not SendMailNameEditBox then return end
  local db = ns.db
  local key = ns.Mules.FindExact(db, SendMailNameEditBox:GetText())
  local s = Mailer.session
  if s then
    if key == s.key or s.sending or s.awaitingRefill or not userInput then return end
    -- The player is now writing to someone else: take our items back out of the mail.
    Mailer.Cancel()
  end
  if not key or not db.options.autoAttach then return end
  typeToken = typeToken + 1
  local token = typeToken
  C_Timer.After(TYPE_DELAY, function()
    if token ~= typeToken or Mailer.session or not Mailer.IsMailboxOpen() then return end
    if ns.Mules.FindExact(db, SendMailNameEditBox:GetText()) ~= key then return end
    Mailer.Start(key)
  end)
end

local function onMailboxClosed()
  local s = Mailer.session
  if not s then return end
  Mailer.session = nil
  local left = #s.queue + countKeys(s.attached)
  if left > 0 then
    ns.Print("Mailbox closed: %d stack(s) sent to %s, %d still in your bags.", s.sent, s.name, left)
  elseif s.sent > 0 then
    ns.Print("Sent %d stack(s) to %s in %d mail(s).", s.sent, s.name, s.mails)
  end
end

-- The mail frame may not exist until the first mailbox opens, so hook it then.
local hooked = false
function Mailer.HookMailFrame()
  if hooked then return end
  hooked = true
  if MailFrame then MailFrame:HookScript("OnHide", onMailboxClosed) end
  if SendMailNameEditBox then
    SendMailNameEditBox:HookScript("OnTextChanged", function(_, userInput)
      onRecipientChanged(userInput)
    end)
  end
end

ns.OnInit(function()
  hooksecurefunc("SendMail", onSendMail)
end)

ns.On("MAIL_SHOW", Mailer.HookMailFrame)
ns.On("MAIL_SEND_SUCCESS", onSendSuccess)
ns.On("MAIL_FAILED", onSendFailed)
ns.On("ADDON_ACTION_BLOCKED", onBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked)
