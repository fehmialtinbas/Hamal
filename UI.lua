local _, ns = ...

-- A small panel next to the Send Mail tab: one button per bank alt, the items about
-- to be sent (click to leave one out), a Send button and a way into the settings.
local UI = {}
ns.UI = UI

local BUTTON_HEIGHT = 22
local PAD = 10
local WIDTH = 210
local ICON = 26
local ICON_GAP = 4
local ICONS_PER_ROW = 6
local MAX_ICONS = 36

local panel, status, sendButton, sendAllButton, settingsButton, moreText, hintText
local muleButtons = {}
local itemButtons = {}

local function onMuleClick(button)
  ns.Mailer.Start(button.muleKey)
end

local function onItemClick(button)
  ns.Mailer.Skip(button.item, IsShiftKeyDown())
end

local function onItemEnter(button)
  ns.Widgets.ShowItemTooltip(button, button.item, "Click: leave out this time\nShift-click: never send")
end

local function getMuleButton(i)
  local button = muleButtons[i]
  if not button then
    button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    ns.Theme.Button(button)
    button:SetHeight(BUTTON_HEIGHT)
    button:SetScript("OnClick", ns.Safely(onMuleClick))
    muleButtons[i] = button
  end
  return button
end

local function getItemButton(i)
  local button = itemButtons[i]
  if not button then
    button = ns.Widgets.IconButton(panel, ICON)
    button:SetScript("OnClick", ns.Safely(onItemClick))
    button:SetScript("OnEnter", ns.Safely(onItemEnter))
    itemButtons[i] = button
  end
  return button
end

local function fullWidth(widget, y)
  widget:ClearAllPoints()
  widget:SetPoint("TOPLEFT", PAD, y)
  widget:SetPoint("TOPRIGHT", -PAD, y)
end

-- Is the game's own mail window really on screen? Mailbox addons (DaylightUI, TSM...)
-- often keep it open but hidden away (see-through, shrunk or off screen) and show
-- their own window instead.
function UI.MailWindowOnScreen()
  local mail = MailFrame
  if not (mail and mail:IsVisible()) then return false end
  local alpha = mail:GetEffectiveAlpha() or 1
  local scale = mail:GetEffectiveScale() or 1
  local normal = (UIParent and UIParent:GetEffectiveScale()) or 1
  return alpha > 0.1 and scale > normal * 0.1
end

-- Docked beside the game's mail window when it shows; otherwise on its own, where the
-- player last dragged it.
function UI.Place()
  if not panel then return end
  panel:ClearAllPoints()
  panel.docked = UI.MailWindowOnScreen()
  if panel.docked then
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, -30)
    return
  end
  local pos = ns.db and ns.db.panelPos
  if pos and pos.point then
    panel:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
  else
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 680, -116)
  end
end

function UI.Show()
  UI.Create()
  if not panel then return end
  UI.Place()
  panel:Show()
  panel:Raise()
  UI.Refresh()
  -- A mailbox addon may hide the game's window a moment after it opens.
  ns.After(0.3, function()
    if panel:IsShown() then UI.Place() end
  end)
end

function UI.Hide()
  if panel then panel:Hide() end
  if ns.BagMarks then ns.BagMarks.Clear() end
end

function UI.Create()
  if panel then return end
  -- Its own frame, not part of the game's mail window, so it still shows when another
  -- addon replaces that window.
  panel = CreateFrame("Frame", "HamalPanel", UIParent, "BackdropTemplate")
  panel:SetWidth(WIDTH)
  panel:Hide()
  -- Above ordinary windows (another addon's mailbox included), below popups and menus;
  -- a click brings it to the front.
  panel:SetFrameStrata("HIGH")
  panel:SetToplevel(true)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", ns.Safely(function(self)
    if not self.docked then self:StartMoving() end
  end))
  panel:SetScript("OnDragStop", ns.Safely(function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    if point and not self.docked then
      ns.db.panelPos = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
  end))
  ns.Theme.Frame(panel, "panel")

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 10, -PAD)
  title:SetText("Hamal")
  UI.logo = ns.Logo(panel, title, 16)

  status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetWidth(WIDTH - 2 * PAD)
  status:SetJustifyH("LEFT")

  moreText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hintText:SetWidth(WIDTH - 2 * PAD)
  hintText:SetJustifyH("LEFT")
  hintText:SetText("Click an item to leave it out.")

  sendButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  ns.Theme.Button(sendButton)
  sendButton:SetHeight(BUTTON_HEIGHT)
  sendButton:SetScript("OnClick", ns.Safely(function() ns.Mailer.Send() end))

  sendAllButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  ns.Theme.Button(sendAllButton)
  sendAllButton:SetHeight(BUTTON_HEIGHT)
  sendAllButton:SetScript("OnClick", ns.Safely(function() ns.Mailer.SendAll(true) end))
  sendAllButton:SetScript("OnEnter", ns.Safely(function(self)
    if self.details then ns.Widgets.ShowTextTooltip(self, self.details) end
  end))
  sendAllButton:SetScript("OnLeave", ns.Safely(ns.Widgets.HideTooltip))

  settingsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  ns.Theme.Button(settingsButton)
  settingsButton:SetHeight(BUTTON_HEIGHT)
  settingsButton:SetText("Settings")
  settingsButton:SetScript("OnClick", ns.Safely(function()
    local session = ns.Mailer.session
    ns.Config.Open(session and session.key)
  end))

  panel:HookScript("OnShow", ns.Safely(function() UI.Refresh() end))

  UI.panel, UI.status, UI.sendButton, UI.settingsButton = panel, status, sendButton, settingsButton
  UI.sendAllButton = sendAllButton
  UI.muleButtons, UI.itemButtons = muleButtons, itemButtons
end

local function statusText(keys, session, iAmBank)
  if #keys == 0 then
    if iAmBank then return "This character is a bank alt.\nOpen your inbox to collect." end
    return "No bank alts yet.\nPress Settings to add one."
  end
  local stacking = ns.Mailer.stacking
  if stacking then
    return ("Combining stacks for %s..."):format(ns.db.mules[stacking.key].name)
  end
  if not session then
    return "Click a bank alt, or type\nits name in To:"
  end
  if session.sending then
    return ("Sending to %s..."):format(session.name)
  end
  return ("To %s: %d stack(s) left."):format(session.name, #session.queue + ns.Mailer.AttachedCount())
end

-- Item icons of the running session; returns the new y.
local function layoutItems(session, busy, y)
  local entries = session and ns.Mailer.SessionItems() or {}
  local shown = math.min(#entries, MAX_ICONS)
  for i = 1, shown do
    local entry = entries[i]
    local button = getItemButton(i)
    button.item = entry.item
    button.icon:SetTexture(entry.item.icon or ns.ItemIcon(entry.item.itemID))
    button.count:SetText(entry.item.count > 1 and tostring(entry.item.count) or "")
    button:SetAlpha(i <= ns.Mailer.MaxSlots() and 1 or 0.5) -- dimmed: waits for a later mail
    button:SetEnabled(not busy)
    local col, row = (i - 1) % ICONS_PER_ROW, math.floor((i - 1) / ICONS_PER_ROW)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", PAD + col * (ICON + ICON_GAP), y - row * (ICON + ICON_GAP))
    button:Show()
  end
  for i = shown + 1, #itemButtons do
    itemButtons[i]:Hide()
  end
  if shown == 0 then
    moreText:Hide()
    hintText:Hide()
    return y
  end
  y = y - math.ceil(shown / ICONS_PER_ROW) * (ICON + ICON_GAP)
  if #entries > shown then
    moreText:SetText(("+%d more"):format(#entries - shown))
    moreText:ClearAllPoints()
    moreText:SetPoint("TOPLEFT", PAD, y)
    moreText:Show()
    y = y - 14
  else
    moreText:Hide()
  end
  hintText:ClearAllPoints()
  hintText:SetPoint("TOPLEFT", PAD, y)
  hintText:Show()
  return y - 16
end

-- What "Send all" will do: mails, postage and one tooltip line per bank alt.
function UI.Totals(db, summary, keys)
  local perMail = ns.Mailer.MaxSlots()
  local base, perStack = ns.Mailer.Postage()
  local mails, postage, lines = 0, 0, {}
  for _, key in ipairs(keys) do
    local s = summary[key]
    local stacks = db.options.stackFirst and s.minStacks or s.stacks
    local n = math.ceil(stacks / perMail)
    mails = mails + n
    postage = postage + n * base + stacks * perStack
    local line = ("%s: %d stack(s), %d mail(s)"):format(db.mules[key].name, stacks, n)
    if stacks < s.stacks then
      line = line .. (" (%d before combining)"):format(s.stacks)
    end
    lines[#lines + 1] = line
  end
  return mails, math.floor(postage + 0.5), lines
end

function UI.Refresh()
  if not panel or not panel:IsVisible() or not ns.db then return end
  local db = ns.db
  -- Bank alts this character can mail; never itself.
  local me = ns.NormalizeName(ns.PlayerName())
  local keys = {}
  for _, key in ipairs(ns.Mules.ActiveKeys(db)) do
    if key ~= me then keys[#keys + 1] = key end
  end
  local summary, slotMap = ns.Scanner.Summary(db)
  local counts = {}
  for key, s in pairs(summary) do counts[key] = s.stacks end
  local session = ns.Mailer.session
  local busy = (session and session.sending) or ns.Mailer.stacking ~= nil

  -- A bank alt's own rules don't send anything from itself.
  for slotKey, key in pairs(slotMap) do
    if key == me then slotMap[slotKey] = nil end
  end
  ns.BagMarks.Update(slotMap, session)

  local y = -PAD - 20
  local pendingAlts = ns.Mailer.PendingAlts(counts)
  if not session and not ns.Mailer.run and not ns.Mailer.stacking and #pendingAlts > 0 then
    local mails, postage, lines = UI.Totals(db, summary, pendingAlts)
    fullWidth(sendAllButton, y)
    sendAllButton:SetText(("Send all: %d mail(s), ~%s"):format(mails, ns.FormatMoney(postage)))
    sendAllButton.details = table.concat(lines, "\n")
    sendAllButton:Show()
    y = y - BUTTON_HEIGHT - 8
  else
    sendAllButton:Hide()
  end

  for i, key in ipairs(keys) do
    local button = getMuleButton(i)
    local n = counts[key] or 0
    if session and session.key == key then
      n = #session.queue + ns.Mailer.AttachedCount()
    end
    button.muleKey = key
    fullWidth(button, y)
    button:SetText(("%s (%d)"):format(db.mules[key].name, n))
    button:SetEnabled(n > 0 and not busy)
    button:Show()
    y = y - BUTTON_HEIGHT - 4
  end
  for i = #keys + 1, #muleButtons do
    muleButtons[i]:Hide()
  end

  status:ClearAllPoints()
  status:SetPoint("TOPLEFT", PAD, y - 2)
  status:SetText(statusText(keys, session, ns.Mules.IsActive(db, me)))
  y = y - 2 - (status:GetStringHeight() or 12) - 6

  y = layoutItems(session, busy, y)

  if session then
    fullWidth(sendButton, y)
    if busy then
      sendButton:SetText("Sending...")
    else
      sendButton:SetText(("Send mail %d/%d"):format(session.mails + 1, ns.Mailer.Estimate(session)))
    end
    -- Items may still be only queued (another addon's mail window: attached on Send).
    sendButton:SetEnabled(not busy and (ns.Mailer.AttachedCount() > 0 or #session.queue > 0))
    sendButton:Show()
    y = y - BUTTON_HEIGHT - 4
  else
    sendButton:Hide()
  end

  fullWidth(settingsButton, y)
  y = y - BUTTON_HEIGHT - 4

  panel:SetHeight(-y + PAD)
end

-- Bursts of bag and attachment changes (12 attachments = 12 events) become a single
-- refresh on the next frame, and nothing at all while the panel isn't on screen.
local refreshQueued = false
function UI.RequestRefresh()
  if refreshQueued or not panel or not panel:IsVisible() then return end
  refreshQueued = true
  ns.After(0, function()
    refreshQueued = false
    UI.Refresh()
  end)
end

-- Created when a mailbox opens (Mailer.OnMailboxOpened).
ns.On("BAG_UPDATE_DELAYED", UI.RequestRefresh)
ns.On("MAIL_SEND_INFO_UPDATE", UI.RequestRefresh)
