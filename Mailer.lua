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
Mailer.MaxSlots = maxSlots

-- Postage model: price = base (per mail) + perStack * stacks attached. Learned from
-- two readings of the game's own price while a mail is filled; until then Classic's
-- 30 copper per stack with no base fee is assumed.
local DEFAULT_PER_STACK = 30

-- Returns base, perStack, learned.
function Mailer.Postage()
  local postage = ns.db and ns.db.postage
  if postage and postage.perStack then return postage.base or 0, postage.perStack, true end
  return 0, DEFAULT_PER_STACK, false
end

local function learnPostage(first, last)
  local db = ns.db
  if not last or last.stacks <= 0 or not last.price or last.price <= 0 then return end
  if first and first.stacks ~= last.stacks then
    local perStack = (last.price - first.price) / (last.stacks - first.stacks)
    local base = first.price - perStack * first.stacks
    if perStack >= 0 and base >= 0 then
      db.postage = { base = base, perStack = perStack, exact = true }
    end
  elseif not (db.postage and db.postage.exact) then
    -- A single reading can't separate a per-mail fee; assume none until it can.
    db.postage = { base = 0, perStack = last.price / last.stacks }
  end
end

local function priceReading()
  if not GetSendMailPrice then return nil end
  return { stacks = Mailer.AttachedCount(), price = GetSendMailPrice() }
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

-- Safety ---------------------------------------------------------------------------

-- The exact name to mail, or nil when Hamal must not mail this bank alt from here.
-- Every send goes through this (see Characters.CanMail for the rule).
function Mailer.VerifiedRecipient(key)
  local db = ns.db
  if not key or not ns.Mules.IsActive(db, key) then return nil end
  if key == ns.NormalizeName(ns.PlayerName()) then return nil end
  local info, name = ns.Characters.Entry(db, key)
  if not info or ns.NormalizeName(name) ~= key then return nil end
  return name
end

function Mailer.ExplainRefusal(key)
  local db = ns.db
  local mule = db.mules[key]
  local name = mule and mule.name or key
  if mule and mule.disabled then
    return ns.Print("%s is switched off in Hamal's settings.", name)
  end
  local place = ns.Characters.Place(db, key)
  if place == "other" then
    local info = ns.Characters.Entry(db, key)
    ns.Print("%s is on the %s realm; mail can't safely reach it from %s.", name, info.realm,
      ns.Characters.CurrentRealm() or "here")
  elseif place == "hidden" then
    ns.Print("%s is hidden in Hamal's settings.", name)
  elseif place == "unknown" then
    ns.Print("Log in on %s once so Hamal can confirm it is yours and on this realm. Until then it gets nothing.", name)
  else
    ns.Print("%s is not one of your characters. Hamal only mails your own characters.", name)
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
  local added, firstReading = 0, nil
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
            firstReading = firstReading or priceReading()
            break
          end
        end
      end
    end
  end
  if added > 0 then learnPostage(firstReading, priceReading()) end
  return added
end

-- Merge partial stacks for `key` first, then start. Returns "stacking".
local function stackThenStart(key)
  if Mailer.stacking then return "stacking" end
  local job = { key = key }
  Mailer.stacking = job
  refresh()
  ns.Stacker.Run(ns.db, key, job, function()
    if Mailer.stacking ~= job then return end
    Mailer.stacking = nil
    if job.cancelled or not Mailer.IsMailboxOpen() then
      refresh()
      return
    end
    local started = Mailer.Start(key, true)
    local run = Mailer.run
    if started == true and run and run.sendWhenReady then Mailer.Send() end
    refresh()
  end)
  return "stacking"
end

-- Returns true when the mail is filled, "stacking" while partial stacks are being
-- combined first (the mail is filled right after), false when it can't start.
function Mailer.Start(key, skipStacking)
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
  if ns.NormalizeName(ns.PlayerName()) == key then
    ns.Print("You are logged in as %s. Use another character to fill this bank.", mule.name)
    return false
  end
  local recipient = Mailer.VerifiedRecipient(key)
  if not recipient then
    Mailer.ExplainRefusal(key)
    return false
  end
  if Mailer.stacking then return "stacking" end
  if not skipStacking and db.options.stackFirst and ns.Stacker.HasWork(db, key) then
    showSendTab()
    return stackThenStart(key)
  end
  local queue = ns.Scanner.Collect(db, key)
  if #queue == 0 then
    ns.Print("Nothing in your bags goes to %s.", mule.name)
    return false
  end
  showSendTab()
  Mailer.session = {
    key = key,
    name = recipient,
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
  -- Last gate before anything leaves the bags: check the recipient again, now.
  local recipient = Mailer.VerifiedRecipient(s.key)
  if not recipient or recipient ~= s.name then
    ns.Print("Stopped: %s is not a verified character of yours on this realm. Nothing was sent.", s.name)
    Mailer.Cancel()
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
  Mailer.SetRecipient(recipient)
  local subject = ("Hamal %d/%d"):format(s.mails + 1, Mailer.Estimate(s))
  -- Called through the global on purpose: the SendMail hook below must see it.
  SendMail(recipient, subject, "")
  return true
end

-- What this session will send: attached stacks first (with their mail slot), then the queue.
function Mailer.SessionItems()
  local s = Mailer.session
  local out = {}
  if not s then return out end
  for i = 1, maxSlots() do
    local item = s.attached[i]
    if item and GetSendMailItem(i) then out[#out + 1] = { item = item, slot = i } end
  end
  for _, item in ipairs(s.queue) do
    out[#out + 1] = { item = item }
  end
  return out
end

-- Leave a stack out of this session. With `forever`, every stack of that item is
-- left out and the item goes on the never-send list.
function Mailer.Skip(item, forever)
  local s = Mailer.session
  if not s or s.sending or not item then return end
  local function isTarget(other)
    if forever then return other.itemID == item.itemID end
    return other == item
  end
  for i = #s.queue, 1, -1 do
    if isTarget(s.queue[i]) then table.remove(s.queue, i) end
  end
  local freed = false
  for i, attached in pairs(s.attached) do
    if isTarget(attached) then
      if GetSendMailItem(i) then ClickSendMailItemButton(i, true) end
      s.attached[i] = nil
      freed = true
    end
  end
  if forever then
    ns.db.exclude[item.itemID] = true
    ns.Print("%s will never be sent (remove it in /hamal).", item.link or ns.ItemLabel(item.itemID))
  end
  if next(s.attached) == nil and #s.queue == 0 then
    Mailer.Cancel()
    return
  end
  if freed then Mailer.AttachNext() end
  refresh()
end

-- Sending to every bank alt ------------------------------------------------------

-- Active bank alts (not this character) with something waiting in the bags.
function Mailer.PendingAlts(counts)
  local db = ns.db
  local me = ns.NormalizeName(ns.PlayerName())
  counts = counts or ns.Scanner.CountAll(db)
  local keys, stacks = {}, 0
  for _, key in ipairs(ns.Mules.ActiveKeys(db)) do
    local n = counts[key] or 0
    if key ~= me and n > 0 then
      keys[#keys + 1] = key
      stacks = stacks + n
    end
  end
  return keys, stacks
end

-- Fill and send the next bank alt of the run. `byClick` means a real click started
-- this, so the first SendMail is allowed even when chaining is off.
function Mailer.NextInRun(byClick)
  local run = Mailer.run
  if not run then return false end
  local started
  repeat
    run.index = run.index + 1
    local key = run.keys[run.index]
    if not key then
      Mailer.run = nil
      if run.index > 2 then ns.Print("All bank alts are done.") end
      refresh()
      return false
    end
    started = Mailer.Start(key)
  until started
  if started == "stacking" then
    -- Sent once the stacks are combined, unless the game wants a click per mail.
    run.sendWhenReady = ns.db.options.chain
    return true
  end
  if byClick or ns.db.options.chain then Mailer.Send() end
  return true
end

function Mailer.SendAll(byClick, quiet)
  if Mailer.session or Mailer.run or Mailer.stacking or not Mailer.IsMailboxOpen() then return false end
  local keys = Mailer.PendingAlts()
  if #keys == 0 then
    if not quiet then ns.Print("Nothing in your bags goes to a bank alt.") end
    return false
  end
  Mailer.run = { keys = keys, index = 0 }
  return Mailer.NextInRun(byClick)
end

function Mailer.Cancel()
  local s = Mailer.session
  Mailer.run = nil
  if Mailer.stacking then
    Mailer.stacking.cancelled = true
    Mailer.stacking = nil
  end
  if not s then
    refresh()
    return
  end
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
  if Mailer.run then
    -- On to the next bank alt once the form has been reset.
    ns.After(REFILL_DELAY, function()
      if Mailer.run and not Mailer.session and Mailer.IsMailboxOpen() then Mailer.NextInRun(false) end
    end)
  end
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
  ns.After(SEND_TIMEOUT, function()
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
  ns.After(REFILL_DELAY, function()
    if Mailer.session ~= s then return end
    s.awaitingRefill = false
    if not Mailer.IsMailboxOpen() then return end
    Mailer.SetRecipient(s.name)
    Mailer.AttachNext()
    refresh()
    if s.chain and ns.db.options.chain then
      ns.After(CHAIN_DELAY, function()
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
      ns.After(0, function() s.blocked = false end)
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
    if key == s.key or s.sending or s.awaitingRefill then return end
    -- To: no longer names our bank alt (typed, autocompleted or set by anything else):
    -- take our items back out before the game's Send button could mail them there.
    Mailer.Cancel()
    if not userInput then return end
  end
  if not key or not db.options.autoAttach then return end
  typeToken = typeToken + 1
  local token = typeToken
  ns.After(TYPE_DELAY, function()
    if token ~= typeToken or Mailer.session or Mailer.stacking or not Mailer.IsMailboxOpen() then return end
    if ns.Mules.FindExact(db, SendMailNameEditBox:GetText()) ~= key then return end
    Mailer.Start(key)
  end)
end

-- Several signals report the same opening/closing; handle each visit once.
local mailboxHandled = false

local function onMailboxClosed()
  mailboxHandled = false
  local s = Mailer.session
  Mailer.run = nil
  if Mailer.stacking then
    Mailer.stacking.cancelled = true
    Mailer.stacking = nil
  end
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
  if MailFrame then MailFrame:HookScript("OnHide", ns.Safely(onMailboxClosed)) end
  if SendMailNameEditBox then
    SendMailNameEditBox:HookScript("OnTextChanged", ns.Safely(function(_, userInput)
      onRecipientChanged(userInput)
    end))
  end
end

ns.OnInit(function()
  hooksecurefunc("SendMail", ns.Safely(onSendMail))
end)

local OPEN_DELAY = 0.5

function Mailer.OnMailboxOpened()
  if mailboxHandled then return end
  mailboxHandled = true
  Mailer.HookMailFrame()
  if ns.Items and ns.db then ns.Items.RecordSeen(ns.db) end
  if ns.UI then
    ns.UI.Create()
    ns.UI.Refresh()
  end
  if ns.db and ns.db.options.autoSendOnOpen then
    ns.After(OPEN_DELAY, function()
      if Mailer.IsMailboxOpen() and not Mailer.session then Mailer.SendAll(false, true) end
    end)
  end
end

-- Newer clients report opening a mailbox as a "player interaction"; older ones fire
-- MAIL_SHOW / MAIL_CLOSED. Listen to both.
local function isMailInteraction(kind)
  local types = Enum and Enum.PlayerInteractionType
  return types ~= nil and types.MailInfo ~= nil and kind == types.MailInfo
end

ns.On("MAIL_SHOW", Mailer.OnMailboxOpened)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
  if isMailInteraction(kind) then Mailer.OnMailboxOpened() end
end)
ns.On("MAIL_CLOSED", onMailboxClosed)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
  if isMailInteraction(kind) then onMailboxClosed() end
end)
ns.On("MAIL_SEND_SUCCESS", onSendSuccess)
ns.On("MAIL_FAILED", onSendFailed)
ns.On("ADDON_ACTION_BLOCKED", onBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked)
