local _, ns = ...

-- The settings window: bank alts on the left, the selected alt's rules on the right,
-- the never-send list and options below. Open with /hamal.
local Config = {}
ns.Config = Config

local WIDTH, HEIGHT = 600, 520
local LEFT, LEFT_WIDTH = 14, 170
local RIGHT = LEFT + LEFT_WIDTH + 18
local RIGHT_WIDTH = WIDTH - RIGHT - 14
local CHECK = 22
local ICON = 28
local ICON_GAP = 4
local ICONS_PER_ROW = 10
local MAX_ICONS = 2 * ICONS_PER_ROW
local MAX_MULE_BUTTONS = 9

local frame, selectedKey
local header, noSelection, emptyList, removeButton, aliasBox, nameBox
local itemDrop, excludeDrop, autoCheck, chainCheck, itemMore, excludeMore
local itemIconsY, excludeIconsY = 0, 0
local muleButtons, categoryChecks, itemButtons, excludeButtons = {}, {}, {}, {}
local mulePane = {} -- widgets shown only while a bank alt is selected

local function changed()
  Config.Refresh()
  if ns.UI then ns.UI.Refresh() end
end

local function text(parent, value, template, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(value)
  return fs
end

local function inPane(widget)
  mulePane[#mulePane + 1] = widget
  return widget
end

local function inputBox(width, x, y)
  local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetPoint("TOPLEFT", x + 6, y) -- the template draws its border outside the box
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return box
end

local function checkBox(x, y, labelWidth, onClick)
  local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  check:SetSize(CHECK, CHECK)
  check:SetPoint("TOPLEFT", x, y)
  check.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
  check.label:SetWidth(labelWidth)
  check.label:SetJustifyH("LEFT")
  check:SetScript("OnClick", onClick)
  return check
end

local function button(label, width, x, y, onClick)
  local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

-- A slot you drop items on (drag from a bag, or click while holding one).
local function dropZone(x, y, tooltip, onItem)
  local zone = ns.Widgets.IconButton(frame, ICON)
  zone:SetPoint("TOPLEFT", x, y)
  zone.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  local function receive()
    local itemID = ns.Widgets.TakeCursorItem()
    if itemID then onItem(itemID) end
  end
  zone:SetScript("OnReceiveDrag", receive)
  zone:SetScript("OnClick", receive)
  zone:SetScript("OnEnter", function(self) ns.Widgets.ShowTextTooltip(self, tooltip) end)
  return zone
end

-- Lay out a row of item icons after a drop zone; clicking an icon calls onClick(itemID).
local function layoutIcons(pool, ids, x, y, onClick, more)
  local shown = math.min(#ids, MAX_ICONS)
  for i = 1, shown do
    local b = pool[i]
    if not b then
      b = ns.Widgets.IconButton(frame, ICON)
      b:SetScript("OnClick", function(self) onClick(self.itemID) end)
      b:SetScript("OnEnter", function(self) ns.Widgets.ShowItemTooltip(self, self.itemID, "Click to remove") end)
      pool[i] = b
    end
    b.itemID = ids[i]
    b.icon:SetTexture(ns.ItemIcon(ids[i]))
    local col, row = (i - 1) % ICONS_PER_ROW, math.floor((i - 1) / ICONS_PER_ROW)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x + col * (ICON + ICON_GAP), y - row * (ICON + ICON_GAP))
    b:Show()
  end
  for i = shown + 1, #pool do
    pool[i]:Hide()
  end
  more:SetText(#ids > shown and ("+%d more"):format(#ids - shown) or "")
end

-- Actions ---------------------------------------------------------------------

local function selectMule(self)
  selectedKey = self.muleKey
  Config.Refresh()
end

local function addMule()
  local key, err = ns.Mules.Add(ns.db, nameBox:GetText())
  if not key then return ns.Print(err) end
  nameBox:SetText("")
  nameBox:ClearFocus()
  selectedKey = key
  changed()
end

local function saveAlias()
  if not selectedKey then return end
  local ok, err = ns.Mules.SetOnlyAlias(ns.db, selectedKey, aliasBox:GetText())
  if not ok then ns.Print(err) end
  aliasBox:ClearFocus()
  Config.Refresh()
end

local function toggleCategory(check)
  if not selectedKey then return end
  ns.db.mules[selectedKey].categories[check.category] = check:GetChecked() and true or nil
  changed()
end

local function addItem(itemID)
  if not selectedKey then return end
  ns.db.mules[selectedKey].items[itemID] = true
  ns.db.exclude[itemID] = nil
  changed()
end

local function removeItem(itemID)
  if not selectedKey then return end
  ns.db.mules[selectedKey].items[itemID] = nil
  changed()
end

local function addExclude(itemID)
  ns.db.exclude[itemID] = true
  for _, mule in pairs(ns.db.mules) do
    mule.items[itemID] = nil
  end
  changed()
end

local function removeExclude(itemID)
  ns.db.exclude[itemID] = nil
  changed()
end

StaticPopupDialogs.HAMAL_REMOVE_MULE = {
  text = "Remove bank alt %s and its rules?",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function(_, key)
    local session = ns.Mailer.session
    if session and session.key == key then ns.Mailer.Cancel() end
    ns.Mules.Remove(ns.db, key)
    if selectedKey == key then selectedKey = nil end
    changed()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function confirmRemove()
  if not selectedKey then return end
  StaticPopup_Show("HAMAL_REMOVE_MULE", ns.db.mules[selectedKey].name, nil, selectedKey)
end

-- Building --------------------------------------------------------------------

function Config.Create()
  if frame then return end
  frame = CreateFrame("Frame", "HamalConfig", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()
  table.insert(UISpecialFrames, "HamalConfig") -- Esc closes it

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -6)
  title:SetText("Hamal")

  -- Left: the bank alts.
  text(frame, "Bank alts", "GameFontNormal", LEFT, -34)
  emptyList = text(frame, "None yet. Type your bank\nalt's full name below.", "GameFontDisableSmall", LEFT, -58)
  text(frame, "New bank alt (Name Surname)", "GameFontHighlightSmall", LEFT, -292)
  nameBox = inputBox(LEFT_WIDTH - 12, LEFT, -308)
  nameBox:SetScript("OnEnterPressed", addMule)
  button("Add bank alt", LEFT_WIDTH, LEFT, -334, addMule)

  -- Left, bottom: options for every bank alt.
  text(frame, "Options", "GameFontNormal", LEFT, -372)
  autoCheck = checkBox(LEFT, -390, LEFT_WIDTH - CHECK - 4, function(self)
    ns.db.options.autoAttach = self:GetChecked() and true or false
  end)
  autoCheck.label:SetText("Fill the mail when I type a bank alt's name")
  chainCheck = checkBox(LEFT, -430, LEFT_WIDTH - CHECK - 4, function(self)
    ns.db.options.chain = self:GetChecked() and true or false
  end)
  chainCheck.label:SetText("Send every batch with one click")

  -- Right: the selected bank alt.
  noSelection = text(frame, "Add a bank alt on the left to choose what it gets.", "GameFontDisable", RIGHT, -58)
  header = inPane(text(frame, "", "GameFontNormalLarge", RIGHT, -34))
  removeButton = inPane(button("Remove", 90, WIDTH - 14 - 90, -30, confirmRemove))

  inPane(text(frame, "Shortcut for To:", "GameFontHighlightSmall", RIGHT, -66))
  aliasBox = inPane(inputBox(90, RIGHT + 100, -62))
  aliasBox:SetScript("OnEnterPressed", saveAlias)
  aliasBox:SetScript("OnEditFocusLost", saveAlias)
  inPane(text(frame, "e.g. vk", "GameFontDisableSmall", RIGHT + 210, -66))

  inPane(text(frame, "Item types this alt gets", "GameFontNormal", RIGHT, -94))
  local perColumn = math.ceil(#ns.Categories.list / 2)
  local columnWidth = math.floor(RIGHT_WIDTH / 2)
  for i, def in ipairs(ns.Categories.list) do
    local column, row = math.floor((i - 1) / perColumn), (i - 1) % perColumn
    local check = checkBox(RIGHT + column * columnWidth, -112 - row * CHECK, columnWidth - CHECK - 6, toggleCategory)
    check.category = def.key
    categoryChecks[i] = inPane(check)
    inPane(check.label)
  end

  local iconRows = 2 * (ICON + ICON_GAP)
  local itemsTop = -112 - perColumn * CHECK - 10
  itemIconsY = itemsTop - 18
  inPane(text(frame, "Always send these items to this alt", "GameFontNormal", RIGHT, itemsTop))
  itemDrop = inPane(dropZone(RIGHT, itemIconsY, "Drag an item from your bags here.", addItem))
  itemMore = inPane(text(frame, "", "GameFontDisableSmall", RIGHT, itemIconsY - iconRows))

  local excludeTop = itemIconsY - iconRows - 14
  excludeIconsY = excludeTop - 18
  text(frame, "Never send (any bank alt)", "GameFontNormal", RIGHT, excludeTop)
  excludeDrop = dropZone(RIGHT, excludeIconsY, "Drag an item here to keep it in your bags.", addExclude)
  excludeMore = text(frame, "", "GameFontDisableSmall", RIGHT, excludeIconsY - iconRows)
  text(frame, "Hearthstone, tools, soulbound and quest items never go anyway.", "GameFontDisableSmall",
    RIGHT, excludeIconsY - iconRows - 12)

  frame:SetScript("OnShow", function() Config.Refresh() end)

  Config.frame = frame
  Config.widgets = {
    nameBox = nameBox, aliasBox = aliasBox, removeButton = removeButton, header = header,
    muleButtons = muleButtons, categoryChecks = categoryChecks,
    itemDrop = itemDrop, itemButtons = itemButtons, excludeDrop = excludeDrop, excludeButtons = excludeButtons,
    autoCheck = autoCheck, chainCheck = chainCheck,
  }
end

-- Refreshing ------------------------------------------------------------------

local function categoryLabel(db, def, checked)
  local owners = ns.Mules.CategoryOwners(db, def.key)
  local first = owners[1]
  if not first or first == selectedKey then return def.label end
  local otherName = db.mules[first].name
  if checked then
    -- Both alts ticked it; the alphabetically first one gets these items.
    return ("%s |cffff9933(goes to %s)|r"):format(def.label, otherName)
  end
  return ("%s |cff999999(%s)|r"):format(def.label, otherName)
end

local function refreshMuleList(db, keys)
  for i, key in ipairs(keys) do
    if i > MAX_MULE_BUTTONS then break end
    local b = muleButtons[i]
    if not b then
      b = button("", LEFT_WIDTH, LEFT, 0, selectMule)
      muleButtons[i] = b
    end
    b.muleKey = key
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", LEFT, -54 - (i - 1) * 25)
    b:SetText(db.mules[key].name)
    if key == selectedKey then b:LockHighlight() else b:UnlockHighlight() end
    b:Show()
  end
  for i = math.min(#keys, MAX_MULE_BUTTONS) + 1, #muleButtons do
    muleButtons[i]:Hide()
  end
  emptyList:SetShown(#keys == 0)
end

function Config.Refresh()
  if not frame or not frame:IsShown() or not ns.db then return end
  local db = ns.db
  local keys = ns.Mules.SortedKeys(db)
  if selectedKey and not db.mules[selectedKey] then selectedKey = nil end
  selectedKey = selectedKey or keys[1]
  local mule = selectedKey and db.mules[selectedKey]

  refreshMuleList(db, keys)

  for _, widget in ipairs(mulePane) do
    widget:SetShown(mule ~= nil)
  end
  noSelection:SetShown(mule == nil)

  if mule then
    header:SetText(mule.name)
    if not aliasBox:HasFocus() then aliasBox:SetText(ns.Mules.AliasOf(db, selectedKey)) end
    for _, check in ipairs(categoryChecks) do
      local on = mule.categories[check.category] and true or false
      check:SetChecked(on)
      check.label:SetText(categoryLabel(db, ns.Categories.byKey[check.category], on))
    end
    layoutIcons(itemButtons, ns.SortedIDs(mule.items), RIGHT + ICON + 8, itemIconsY, removeItem, itemMore)
  else
    layoutIcons(itemButtons, {}, 0, 0, removeItem, itemMore)
  end
  layoutIcons(excludeButtons, ns.SortedIDs(db.exclude), RIGHT + ICON + 8, excludeIconsY, removeExclude, excludeMore)

  autoCheck:SetChecked(db.options.autoAttach)
  chainCheck:SetChecked(db.options.chain)
end

function Config.Open(key)
  Config.Create()
  if key and ns.db.mules[key] then selectedKey = key end
  frame:Show()
  Config.Refresh()
end

function Config.Toggle()
  Config.Create()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
  end
end

-- Entry in the minimap's addon menu (## AddonCompartmentFunc in the TOC).
function Hamal_OnAddonCompartmentClick()
  Config.Toggle()
end
