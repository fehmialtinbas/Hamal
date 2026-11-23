local _, ns = ...

-- A small panel next to the Send Mail tab: one button per bank alt and a Send button.
local UI = {}
ns.UI = UI

local BUTTON_HEIGHT = 22
local PAD = 10
local WIDTH = 210

local panel, status, sendButton
local muleButtons = {}

local function onMuleClick(button)
  ns.Mailer.Start(button.muleKey)
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

  sendButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  sendButton:SetHeight(BUTTON_HEIGHT)
  sendButton:SetScript("OnClick", function() ns.Mailer.Send() end)

  panel:SetScript("OnShow", function() UI.Refresh() end)

  UI.panel, UI.status, UI.sendButton, UI.muleButtons = panel, status, sendButton, muleButtons
end

local function statusText(keys, session)
  if #keys == 0 then
    return "No bank alts yet.\nType /hamal add Name Surname"
  end
  if not session then
    return "Click a bank alt, or type its name in To:."
  end
  if session.sending then
    return ("Sending to %s..."):format(session.name)
  end
  return ("To %s: %d stack(s) left."):format(session.name, #session.queue + ns.Mailer.AttachedCount())
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
    button.muleKey = key
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", PAD, y)
    button:SetPoint("TOPRIGHT", -PAD, y)
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

  if session then
    sendButton:ClearAllPoints()
    sendButton:SetPoint("TOPLEFT", PAD, y)
    sendButton:SetPoint("TOPRIGHT", -PAD, y)
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

  panel:SetHeight(-y + PAD)
end

ns.On("MAIL_SHOW", function()
  UI.Create()
  UI.Refresh()
end)
ns.On("BAG_UPDATE_DELAYED", UI.Refresh)
ns.On("MAIL_SEND_INFO_UPDATE", UI.Refresh)
