local _, ns = ...

-- Hamal's two looks:
--   game  the game's own: dialog frames and red buttons (default)
--   dark  plain: flat dark background, a 1-pixel border, flat buttons with white text,
--         to sit well next to UI suites such as DaylightUI or ElvUI
-- Every frame and button Hamal styles is remembered, so switching looks restyles them
-- at once. Nothing here runs except when a window is built or the look changes.
local Theme = {}
ns.Theme = Theme

local WHITE = "Interface\\Buttons\\WHITE8X8"

local DARK = {
  background = { 0.06, 0.06, 0.07, 0.94 },
  border = { 0.24, 0.24, 0.27, 1 },
  buttonFill = { 0.14, 0.14, 0.16, 1 },
  buttonEdge = { 0.30, 0.30, 0.34, 1 },
}

local GAME_BACKDROPS = {
  -- The settings window: the game's dialog frame.
  window = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  },
  -- The mailbox panel: dialog background with a thinner edge.
  panel = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  },
}

local DARK_BACKDROP = {
  bgFile = WHITE,
  edgeFile = WHITE,
  edgeSize = 1,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local frames, buttons = {}, {}

function Theme.Look()
  return (ns.db and ns.db.options.look) or "game"
end

local function styleFrame(frame)
  if not frame.SetBackdrop then return end
  local look = Theme.Look()
  frame.hamalLook = look
  if look == "dark" then
    frame:SetBackdrop(DARK_BACKDROP)
    frame:SetBackdropColor(unpack(DARK.background))
    frame:SetBackdropBorderColor(unpack(DARK.border))
  else
    frame:SetBackdrop(GAME_BACKDROPS[frame.hamalKind] or GAME_BACKDROPS.panel)
    frame:SetBackdropColor(1, 1, 1, 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
  end
end

-- A button from UIPanelButtonTemplate. The dark look lays a flat fill over the
-- template's red art (which sits on the BACKGROUND layer) instead of removing it, so
-- the game look can come back at any time. Hover and the "selected tab" glow are the
-- template's highlight, which draws above both.
local function styleButton(button)
  local dark = Theme.Look() == "dark"
  button.hamalLook = dark and "dark" or "game"
  if dark and not button.hamalFill then
    button.hamalEdge = button:CreateTexture(nil, "BORDER", nil, 6)
    button.hamalEdge:SetAllPoints()
    button.hamalEdge:SetColorTexture(unpack(DARK.buttonEdge))
    button.hamalFill = button:CreateTexture(nil, "BORDER", nil, 7)
    button.hamalFill:SetPoint("TOPLEFT", 1, -1)
    button.hamalFill:SetPoint("BOTTOMRIGHT", -1, 1)
    button.hamalFill:SetColorTexture(unpack(DARK.buttonFill))
  end
  if button.hamalFill then
    button.hamalEdge:SetShown(dark)
    button.hamalFill:SetShown(dark)
  end
  -- Font objects, not a text colour: the button re-applies them on enable/disable.
  if dark then
    button:SetNormalFontObject("GameFontHighlight")
  else
    button:SetNormalFontObject("GameFontNormal")
  end
  button:SetHighlightFontObject("GameFontHighlight")
  button:SetDisabledFontObject("GameFontDisable")
end

-- kind: "window" (the settings window) or "panel" (the mailbox panel).
function Theme.Frame(frame, kind)
  frame.hamalKind = kind
  frames[#frames + 1] = frame
  styleFrame(frame)
  return frame
end

function Theme.Button(button)
  buttons[#buttons + 1] = button
  styleButton(button)
  return button
end

function Theme.Apply()
  for _, frame in ipairs(frames) do styleFrame(frame) end
  for _, button in ipairs(buttons) do styleButton(button) end
end

function Theme.SetLook(look)
  ns.db.options.look = (look == "dark") and "dark" or "game"
  Theme.Apply()
end
