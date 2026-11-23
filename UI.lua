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

local panel, status, sendButton, settingsButton, moreText, hintText
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
    button:SetHeight(BUTTON_HEIGHT)
    button:SetScript("OnClick", onMuleClick)
    muleButtons[i] = button
  end
  return button
end

local function getItemButton(i)
  local button = itemButtons[i]
  if not button then
    button = ns.Widgets.IconButton(panel, ICON)
    button:SetScript("OnClick", onItemClick)
    button:SetScript("OnEnter", onItemEnter)
    itemButtons[i] = button
  end
  return button
end

local function fullWidth(widget, y)
  widget:ClearAllPoints()
  widget:SetPoint("TOPLEFT", PAD, y)
  widget:SetPoint("TOPRIGHT", -PAD, y)
end

function UI.Create()
  if panel or not SendMailFrame then return end
  panel = CreateFrame("Frame", "HamalPanel", SendMailFrame, "BackdropTemplate")
  panel:SetWidth(WIDTH)
  panel:SetPoint("TOPLEFT", MailFrame or SendMailFrame, "TOPRIGHT", 2, -30)
  if panel.SetBackdrop then
    panel:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -PAD)
  title:SetText("Hamal")

  status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetWidth(WIDTH - 2 * PAD)
  status:SetJustifyH("LEFT")

  moreText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hintText:SetWidth(WIDTH - 2 * PAD)
  hintText:SetJustifyH("LEFT")
  hintText:SetText("Click an item to leave it out.")

  sendButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  sendButton:SetHeight(BUTTON_HEIGHT)
  sendButton:SetScript("OnClick", function() ns.Mailer.Send() end)

  settingsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  settingsButton:SetHeight(BUTTON_HEIGHT)
  settingsButton:SetText("Settings")
  settingsButton:SetScript("OnClick", function()
    local session = ns.Mailer.session
    ns.Config.Open(session and session.key)
  end)

  panel:SetScript("OnShow", function() UI.Refresh() end)

  UI.panel, UI.status, UI.sendButton, UI.settingsButton = panel, status, sendButton, settingsButton
  UI.muleButtons, UI.itemButtons = muleButtons, itemButtons
end

local function statusText(keys, session)
  if #keys == 0 then
    return "No bank alts yet.\nPress Settings to add one."
  end
  if not session then
    return "Click a bank alt, or type its name in To:."
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
    button:SetAlpha(entry.slot and 1 or 0.5) -- dimmed: waits for a later mail
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

function UI.Refresh()
  if not panel or not panel:IsVisible() or not ns.db then return end
  local db = ns.db
  local keys = ns.Mules.SortedKeys(db)
  local counts = ns.Scanner.CountAll(db)
  local session = ns.Mailer.session
  local busy = session and session.sending

  local y = -PAD - 20
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
  status:SetText(statusText(keys, session))
  y = y - 2 - (status:GetStringHeight() or 12) - 6

  y = layoutItems(session, busy, y)

  if session then
    fullWidth(sendButton, y)
    if busy then
      sendButton:SetText("Sending...")
    else
      sendButton:SetText(("Send mail %d/%d"):format(session.mails + 1, ns.Mailer.Estimate(session)))
    end
    sendButton:SetEnabled(not busy and ns.Mailer.AttachedCount() > 0)
    sendButton:Show()
    y = y - BUTTON_HEIGHT - 4
  else
    sendButton:Hide()
  end

  fullWidth(settingsButton, y)
  y = y - BUTTON_HEIGHT - 4

  panel:SetHeight(-y + PAD)
end

ns.On("MAIL_SHOW", function()
  UI.Create()
  UI.Refresh()
end)
ns.On("BAG_UPDATE_DELAYED", UI.Refresh)
ns.On("MAIL_SEND_INFO_UPDATE", UI.Refresh)
