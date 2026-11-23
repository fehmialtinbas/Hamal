local _, ns = ...

-- The settings window (/hamal), in three tabs:
--   Bank alts  your characters; tick the bank alts and choose the item types each one gets
--   Items      every item Hamal knows; click one to choose where it goes
--   Options    behaviour switches and the never-send list
local Config = {}
ns.Config = Config

local WIDTH, HEIGHT = 640, 540
local PANE_TOP = -56
local LEFT, LEFT_WIDTH = 14, 200
local RIGHT = LEFT + LEFT_WIDTH + 18
local RIGHT_WIDTH = WIDTH - RIGHT - 14
local CHECK = 22
local ICON = 28
local ICON_GAP = 4
local ICONS_PER_ROW = 10
local MAX_ICONS = 2 * ICONS_PER_ROW
local CHAR_ROWS = 11
local ITEM_ROWS = 15
local ITEM_ROW_HEIGHT = 26

local TABS = {
  { key = "alts", label = "Bank alts" },
  { key = "items", label = "Items" },
  { key = "options", label = "Options" },
}

local frame
local panes, tabButtons = {}, {}
local currentTab = "alts"
local selectedKey -- normalized name of the character selected on the Bank alts tab
local showAllCharacters = false -- also list characters on other realms and hidden ones
local charOffset, itemOffset = 0, 0
local itemIconsY = 0
local ui = {} -- widgets, also exposed as Config.widgets
local itemsCache -- the Items tab's list; rebuilt only after something changed, not on scroll

local function changed()
  itemsCache = nil
  Config.Refresh()
  if ns.UI then ns.UI.Refresh() end
end

-- Widget helpers -----------------------------------------------------------------

local function text(parent, value, template, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(value)
  return fs
end

local function inputBox(parent, width, x, y)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetPoint("TOPLEFT", x + 6, y) -- the template draws its border outside the box
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", ns.Safely(function(self) self:ClearFocus() end))
  return box
end

local function checkBox(parent, x, y, labelWidth, onClick)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetSize(CHECK, CHECK)
  check:SetPoint("TOPLEFT", x, y)
  check.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
  check.label:SetWidth(labelWidth)
  check.label:SetJustifyH("LEFT")
  check:HookScript("OnClick", ns.Safely(onClick)) -- keep the template's own click handling (sound)
  return check
end

local function button(parent, label, width, x, y, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(label)
  b:SetScript("OnClick", ns.Safely(onClick))
  return b
end

-- A slot you drop items on (drag from a bag, or click while holding one).
local function dropZone(parent, x, y, tooltip, onItem)
  local zone = ns.Widgets.IconButton(parent, ICON)
  zone:SetPoint("TOPLEFT", x, y)
  zone.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  local function receive()
    local itemID = ns.Widgets.TakeCursorItem()
    if itemID then onItem(itemID) end
  end
  zone:SetScript("OnReceiveDrag", ns.Safely(receive))
  zone:SetScript("OnClick", ns.Safely(receive))
  zone:SetScript("OnEnter", ns.Safely(function(self) ns.Widgets.ShowTextTooltip(self, tooltip) end))
  return zone
end

-- Icons after a drop zone; clicking one calls onClick(itemID).
local function layoutIcons(parent, pool, ids, x, y, onClick, more)
  local shown = math.min(#ids, MAX_ICONS)
  for i = 1, shown do
    local b = pool[i]
    if not b then
      b = ns.Widgets.IconButton(parent, ICON)
      b:SetScript("OnClick", ns.Safely(function(self) onClick(self.itemID) end))
      b:SetScript("OnEnter", ns.Safely(function(self) ns.Widgets.ShowItemTooltip(self, self.itemID, "Click to remove") end))
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

local function classColored(name, class)
  local color = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
  return name
end

local function titleCase(word)
  return word:sub(1, 1):upper() .. word:sub(2):lower()
end

-- Bank alts tab ---------------------------------------------------------------------

local function selectRow(row)
  selectedKey = row.entry.key
  Config.Refresh()
end

local function toggleBankAlt(check)
  local entry = check.row.entry
  local db = ns.db
  local mule = db.mules[entry.key]
  if check:GetChecked() then
    if mule then
      mule.disabled = nil -- ticked again: its old rules come back
    else
      ns.Mules.Add(db, entry.name)
    end
  elseif mule then
    mule.disabled = true
    local session = ns.Mailer.session
    if session and session.key == entry.key then ns.Mailer.Cancel() end
  end
  selectedKey = entry.key
  changed()
end

local function toggleHidden()
  if not selectedKey then return end
  local info = ns.Characters.Entry(ns.db, selectedKey)
  if not info then return end
  ns.Characters.SetHidden(ns.db, selectedKey, not info.hidden)
  local session = ns.Mailer.session
  if session and session.key == selectedKey then ns.Mailer.Cancel() end
  changed()
end

local function saveAlias()
  if not ns.Mules.IsEnabled(ns.db, selectedKey) then return end
  local ok, err = ns.Mules.SetOnlyAlias(ns.db, selectedKey, ui.aliasBox:GetText())
  if not ok then ns.Print(err) end
  ui.aliasBox:ClearFocus()
  Config.Refresh()
end

local function toggleCategory(check)
  if not ns.Mules.IsEnabled(ns.db, selectedKey) then return end
  ns.db.mules[selectedKey].categories[check.category] = check:GetChecked() and true or nil
  changed()
end

local function addItem(itemID)
  if not ns.Mules.IsEnabled(ns.db, selectedKey) then return end
  ns.Items.SetChoice(ns.db, itemID, selectedKey)
  ns.Print("%s always goes to %s.", ns.ItemLabel(itemID), ns.db.mules[selectedKey].name)
  changed()
end

local function removeItem(itemID)
  if not selectedKey then return end
  ns.db.mules[selectedKey].items[itemID] = nil
  changed()
end

StaticPopupDialogs.HAMAL_FORGET_MULE = {
  text = "Forget bank alt %s and all its rules?",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function(_, key)
    local session = ns.Mailer.session
    if session and session.key == key then ns.Mailer.Cancel() end
    ns.Mules.Remove(ns.db, key)
    changed()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function confirmForget()
  local mule = selectedKey and ns.db.mules[selectedKey]
  if mule then StaticPopup_Show("HAMAL_FORGET_MULE", mule.name, nil, selectedKey) end
end

local function buildAltsTab(pane)
  text(pane, "Your characters", "GameFontNormal", LEFT, -4)
  ui.charRows = {}
  for i = 1, CHAR_ROWS do
    local row = CreateFrame("Button", nil, pane)
    row:SetSize(LEFT_WIDTH, CHECK)
    row:SetPoint("TOPLEFT", LEFT, -24 - (i - 1) * (CHECK + 2))
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    -- A quiet band marks the selected character (hover keeps the light highlight).
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.12)
    row.selected:Hide()
    row:SetScript("OnClick", ns.Safely(selectRow))
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(CHECK, CHECK)
    row.check:SetPoint("LEFT", 0, 0)
    row.check.row = row
    row.check:HookScript("OnClick", ns.Safely(toggleBankAlt))
    row.check:SetScript("OnEnter", ns.Safely(function(self)
      ns.Widgets.ShowTextTooltip(self, "Bank alt: Hamal mails items to this character.")
    end))
    row.check:SetScript("OnLeave", ns.Safely(ns.Widgets.HideTooltip))
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", CHECK + 4, 0)
    row.label:SetPoint("RIGHT", -2, 0)
    row.label:SetJustifyH("LEFT")
    ui.charRows[i] = row
  end
  pane:EnableMouseWheel(true)
  pane:SetScript("OnMouseWheel", ns.Safely(function(_, delta)
    charOffset = math.max(0, charOffset - delta)
    Config.Refresh()
  end))

  local listBottom = -24 - CHAR_ROWS * (CHECK + 2)
  ui.emptyChars = text(pane, "Log in on your bank alts once\nand they show up here.", "GameFontDisableSmall", LEFT, -28)
  ui.showAllCheck = checkBox(pane, LEFT, listBottom - 2, LEFT_WIDTH - CHECK - 4, function(self)
    showAllCharacters = self:GetChecked() and true or false
    charOffset = 0
    Config.Refresh()
  end)
  local hint = text(pane, "Hamal only mails your own characters on the realm you are on, after you have "
    .. "logged in on them once with Hamal.", "GameFontDisableSmall", LEFT, listBottom - 28)
  hint:SetWidth(LEFT_WIDTH)

  ui.header = text(pane, "", "GameFontNormalLarge", RIGHT, -4)
  ui.subHeader = text(pane, "", "GameFontDisableSmall", RIGHT, -26)
  ui.forgetButton = button(pane, "Forget", 90, WIDTH - 14 - 90, -2, confirmForget)
  ui.hideButton = button(pane, "Hide", 90, WIDTH - 14 - 184, -2, toggleHidden)
  ui.hideButton:SetScript("OnEnter", ns.Safely(function(self)
    ns.Widgets.ShowTextTooltip(self, "Hide a character you no longer play. It gets no mail and leaves the list.")
  end))
  ui.hideButton:SetScript("OnLeave", ns.Safely(ns.Widgets.HideTooltip))
  ui.notBank = text(pane, "", "GameFontHighlight", RIGHT, -56)
  ui.notBank:SetWidth(RIGHT_WIDTH)

  -- Shown only while the selected character is a bank alt.
  local bank = {}
  local function add(widget) bank[#bank + 1] = widget; return widget end
  add(text(pane, "Shortcut for To:", "GameFontHighlightSmall", RIGHT, -52))
  ui.aliasBox = add(inputBox(pane, 90, RIGHT + 100, -48))
  ui.aliasBox:SetScript("OnEnterPressed", ns.Safely(saveAlias))
  ui.aliasBox:HookScript("OnEditFocusLost", ns.Safely(saveAlias))
  add(text(pane, "e.g. sb", "GameFontDisableSmall", RIGHT + 210, -52))

  add(text(pane, "Item types this alt gets", "GameFontNormal", RIGHT, -80))
  ui.categoryChecks = {}
  local perColumn = math.ceil(#ns.Categories.list / 2)
  local columnWidth = math.floor(RIGHT_WIDTH / 2)
  for i, def in ipairs(ns.Categories.list) do
    local column, row = math.floor((i - 1) / perColumn), (i - 1) % perColumn
    local check = checkBox(pane, RIGHT + column * columnWidth, -98 - row * CHECK, columnWidth - CHECK - 6, toggleCategory)
    check.category = def.key
    ui.categoryChecks[i] = add(check)
    add(check.label)
  end

  local itemsTop = -98 - perColumn * CHECK - 10
  itemIconsY = itemsTop - 18
  add(text(pane, "Always send these items to this alt", "GameFontNormal", RIGHT, itemsTop))
  ui.itemDrop = add(dropZone(pane, RIGHT, itemIconsY, "Drag an item from your bags here.", addItem))
  ui.itemMore = add(text(pane, "", "GameFontDisableSmall", RIGHT, itemIconsY - 2 * (ICON + ICON_GAP)))
  add(text(pane, "Or pick items on the Items tab.", "GameFontDisableSmall", RIGHT, itemIconsY - 2 * (ICON + ICON_GAP) - 14))
  ui.itemButtons = {}
  ui.bankWidgets = bank
end

local function findEntry(entries, key)
  for _, entry in ipairs(entries) do
    if entry.key == key then return entry end
  end
end

local PLACE_TAGS = {
  unknown = " |cff999999?|r",
  hidden = " |cff999999(hidden)|r",
  manual = " |cffff3333(not verified)|r",
}

local function rowLabel(entry)
  local label = classColored(entry.name, entry.class)
  if entry.level then label = label .. (" |cff999999%d|r"):format(entry.level) end
  if entry.isMe then
    label = label .. " |cff999999(you)|r"
  elseif entry.place == "other" then
    label = label .. (" |cffff9933%s|r"):format(entry.realm or "")
  elseif PLACE_TAGS[entry.place] then
    label = label .. PLACE_TAGS[entry.place]
  end
  return label
end

local function describe(entry, isBank)
  local parts = {}
  if entry.level and entry.class then
    parts[#parts + 1] = ("Level %d %s"):format(entry.level, titleCase(entry.class))
  elseif entry.manual then
    parts[#parts + 1] = "Not a character Hamal has seen on this account"
  end
  if entry.realm then parts[#parts + 1] = entry.realm .. " realm" end
  if entry.place == "unknown" then parts[#parts + 1] = "realm not known yet" end
  if entry.isMe then
    parts[#parts + 1] = isBank and "this character: it won't mail itself" or "this character"
  elseif isBank and entry.place ~= "here" then
    parts[#parts + 1] = "|cffff9933gets nothing until you log in on it on this realm|r"
  end
  return table.concat(parts, " - ")
end

local function notBankText(selected)
  if not selected then return "Log in on your characters once, or add a bank alt by name." end
  if selected.place == "hidden" then
    return ("%s is hidden. Press Show if you play it again."):format(selected.name)
  end
  local message = ("Tick the box next to %s to make it a bank alt."):format(selected.name)
  if selected.place == "other" then
    message = message .. ("\nIt is on the %s realm, so only characters there can mail it."):format(selected.realm)
  elseif selected.place == "unknown" then
    message = message .. "\nIf you no longer play it, press Hide."
  end
  return message
end

local function categoryLabel(db, def, checked)
  local owners = ns.Mules.CategoryOwners(db, def.key)
  local first
  for _, key in ipairs(owners) do
    if ns.Mules.IsActive(db, key) and key ~= selectedKey then
      first = first or key
    end
  end
  if not first then return def.label end
  local otherName = db.mules[first].name
  if checked and first < selectedKey then
    -- Both alts ticked it; the alphabetically first one gets these items.
    return ("%s |cffff9933(goes to %s)|r"):format(def.label, otherName)
  end
  return ("%s |cff999999(%s)|r"):format(def.label, otherName)
end

local function refreshAlts(db)
  local entries, leftOut = ns.Characters.List(db, showAllCharacters)
  ui.showAllCheck:SetChecked(showAllCharacters)
  if showAllCharacters or leftOut == 0 then
    ui.showAllCheck.label:SetText("Show other realms and hidden")
  else
    ui.showAllCheck.label:SetText(("Show other realms and hidden (%d)"):format(leftOut))
  end
  charOffset = math.min(charOffset, math.max(0, #entries - CHAR_ROWS))
  if selectedKey and not findEntry(entries, selectedKey) then selectedKey = nil end
  if not selectedKey then
    for _, entry in ipairs(entries) do
      if entry.isBank then
        selectedKey = entry.key
        break
      end
    end
    selectedKey = selectedKey or (entries[1] and entries[1].key)
  end

  for i, row in ipairs(ui.charRows) do
    local entry = entries[i + charOffset]
    if entry then
      row.entry = entry
      row.check:SetChecked(entry.isBank)
      row.label:SetText(rowLabel(entry))
      row.selected:SetShown(entry.key == selectedKey)
      row:Show()
    else
      row:Hide()
    end
  end
  ui.emptyChars:SetShown(#entries == 0)

  local selected = findEntry(entries, selectedKey)
  local mule = selectedKey and db.mules[selectedKey]
  local isBank = ns.Mules.IsEnabled(db, selectedKey) and not (selected and selected.place == "hidden")
  ui.header:SetText(selected and selected.name or "")
  ui.subHeader:SetText(selected and describe(selected, isBank) or "")
  ui.forgetButton:SetShown(mule ~= nil)
  ui.hideButton:SetShown(selected ~= nil and not selected.isMe and not selected.manual)
  ui.hideButton:SetText(selected and selected.place == "hidden" and "Show" or "Hide")
  for _, widget in ipairs(ui.bankWidgets) do
    widget:SetShown(isBank)
  end
  ui.notBank:SetShown(not isBank)

  if isBank then
    if not ui.aliasBox:HasFocus() then ui.aliasBox:SetText(ns.Mules.AliasOf(db, selectedKey)) end
    for _, check in ipairs(ui.categoryChecks) do
      local on = mule.categories[check.category] and true or false
      check:SetChecked(on)
      check.label:SetText(categoryLabel(db, ns.Categories.byKey[check.category], on))
    end
    layoutIcons(panes.alts, ui.itemButtons, ns.SortedIDs(mule.items), RIGHT + ICON + 8, itemIconsY, removeItem, ui.itemMore)
  else
    layoutIcons(panes.alts, ui.itemButtons, {}, 0, 0, removeItem, ui.itemMore)
    ui.notBank:SetText(notBankText(selected))
  end
end

-- Items tab ------------------------------------------------------------------------

local function destinationText(db, entry)
  local reason = entry.reason
  if reason == "kept" then return "|cff999999always kept|r" end
  if reason == "never" then return "|cffff6666never sent|r" end
  if reason == "bound" then return "|cff999999soulbound, stays|r" end
  if entry.destination then
    local name = db.mules[entry.destination].name
    if reason == "item" then return ("|cff66ff66%s|r (picked)"):format(name) end
    local def = ns.Categories.byKey[reason]
    return ("|cff66ff66%s|r (%s)"):format(name, def and def.label:lower() or reason)
  end
  return "|cff999999stays in bags|r"
end

local function itemName(entry)
  local name = entry.name or ("item " .. entry.itemID)
  local color = ITEM_QUALITY_COLORS and entry.quality and ITEM_QUALITY_COLORS[entry.quality]
  if color and color.hex then return color.hex .. name .. "|r" end
  return name
end

-- The choices for an item, in order: follow item types, always to each bank alt, never.
local function itemChoices(db)
  local options = { { label = "Follow item types", value = false } }
  for _, key in ipairs(ns.Mules.ActiveKeys(db)) do
    options[#options + 1] = { label = "Always send to " .. db.mules[key].name, value = key }
  end
  options[#options + 1] = { label = "Never send", value = "never" }
  return options
end

local function describeChoice(db, itemID)
  local choice = ns.Items.Choice(db, itemID)
  if choice == "never" then return "will never be sent" end
  if choice then return "always goes to " .. db.mules[choice].name end
  return "follows the item types again"
end

-- Every change is confirmed in chat (one line, answering the player's own click).
local function chooseFor(itemID, choice, label)
  ns.Items.SetChoice(ns.db, itemID, choice or nil)
  ns.Print("%s %s.", label or ns.ItemLabel(itemID), describeChoice(ns.db, itemID))
  changed()
end

-- Step to the next (or previous) choice without a menu.
local function cycleChoice(entry, step)
  local db = ns.db
  local options = itemChoices(db)
  local current = ns.Items.Choice(db, entry.itemID) or false
  local index = 1
  for i, option in ipairs(options) do
    if option.value == current then index = i end
  end
  local nextIndex = (index - 1 + step) % #options + 1
  chooseFor(entry.itemID, options[nextIndex].value, entry.link or entry.name)
end

-- An item dropped on the list always goes to the bank alt selected on the Bank alts
-- tab (or the only one there is).
local function dropOnItemList()
  local itemID = ns.Widgets.TakeCursorItem()
  if not itemID then return end
  local db = ns.db
  local target = ns.Mules.IsActive(db, selectedKey) and selectedKey or ns.Mules.ActiveKeys(db)[1]
  if not target then
    return ns.Print("Tick a bank alt on the Bank alts tab first.")
  end
  chooseFor(itemID, target)
end

-- Left-click: menu of choices. Right-click (or no menu on this client): next choice.
-- Holding an item: drop it here.
local function onItemClick(row, mouseButton)
  if CursorHasItem() then return dropOnItemList() end
  local entry = row.entry
  if not entry then return end
  if mouseButton == "RightButton" or not (MenuUtil and MenuUtil.CreateContextMenu) then
    return cycleChoice(entry, 1)
  end
  local db = ns.db
  local current = ns.Items.Choice(db, entry.itemID) or false
  MenuUtil.CreateContextMenu(row, function(_, root)
    root:CreateTitle(entry.name or ("item " .. entry.itemID))
    for _, option in ipairs(itemChoices(db)) do
      root:CreateRadio(option.label,
        function(value) return value == current end,
        ns.Safely(function(value) chooseFor(entry.itemID, value, entry.link or entry.name) end),
        option.value)
    end
  end)
end

local function buildItemsTab(pane)
  text(pane, "Search", "GameFontHighlightSmall", LEFT, -8)
  ui.searchBox = inputBox(pane, 170, LEFT + 44, -4)
  ui.searchBox:HookScript("OnTextChanged", ns.Safely(function()
    itemOffset = 0
    Config.Refresh()
  end))
  local hint = text(pane, "Click an item to choose where it goes (right-click: next choice). "
    .. "Drop an item from your bags here to always send it.", "GameFontDisableSmall", LEFT + 240, -4)
  hint:SetWidth(WIDTH - LEFT - 240 - 14)
  text(pane, "Item", "GameFontNormalSmall", LEFT + 30, -32)
  text(pane, "In bags", "GameFontNormalSmall", LEFT + 330, -32)
  text(pane, "Goes to", "GameFontNormalSmall", LEFT + 400, -32)

  ui.itemRows = {}
  for i = 1, ITEM_ROWS do
    local row = CreateFrame("Button", nil, pane)
    row:SetSize(WIDTH - 2 * LEFT, ITEM_ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", LEFT, -48 - (i - 1) * ITEM_ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 30, 0)
    row.name:SetWidth(290)
    row.name:SetJustifyH("LEFT")
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("LEFT", 330, 0)
    row.count:SetWidth(60)
    row.count:SetJustifyH("LEFT")
    row.dest = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dest:SetPoint("LEFT", 400, 0)
    row.dest:SetPoint("RIGHT", -4, 0)
    row.dest:SetJustifyH("LEFT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", ns.Safely(onItemClick))
    row:SetScript("OnReceiveDrag", ns.Safely(dropOnItemList))
    row:SetScript("OnEnter", ns.Safely(function(self)
      ns.Widgets.ShowItemTooltip(self, self.entry.itemID, "Click: choose where it goes\nRight-click: next choice")
    end))
    row:SetScript("OnLeave", ns.Safely(ns.Widgets.HideTooltip))
    ui.itemRows[i] = row
  end
  pane:EnableMouse(true)
  pane:SetScript("OnReceiveDrag", ns.Safely(dropOnItemList))
  pane:SetScript("OnMouseUp", ns.Safely(dropOnItemList))
  pane:EnableMouseWheel(true)
  pane:SetScript("OnMouseWheel", ns.Safely(function(_, delta)
    itemOffset = math.max(0, itemOffset - delta * 3)
    Config.Refresh()
  end))

  local bottom = -48 - ITEM_ROWS * ITEM_ROW_HEIGHT - 6
  ui.emptyItems = text(pane, "No items yet. Hamal lists what is in your bags and what your characters carried before.",
    "GameFontDisableSmall", LEFT, -52)
  ui.itemsPage = text(pane, "", "GameFontDisableSmall", LEFT, bottom - 4)
  ui.prevButton = button(pane, "Prev", 70, WIDTH - 14 - 146, bottom, function()
    itemOffset = math.max(0, itemOffset - ITEM_ROWS)
    Config.Refresh()
  end)
  ui.nextButton = button(pane, "Next", 70, WIDTH - 14 - 70, bottom, function()
    itemOffset = itemOffset + ITEM_ROWS
    Config.Refresh()
  end)
end

local function refreshItems(db)
  itemsCache = itemsCache or ns.Items.Collect(db)
  local query = ns.Trim(ui.searchBox:GetText() or ""):lower()
  local list = {}
  for _, entry in ipairs(itemsCache) do
    if query == "" or (entry.name and entry.name:lower():find(query, 1, true)) then
      list[#list + 1] = entry
    end
  end
  itemOffset = math.max(0, math.min(itemOffset, #list - ITEM_ROWS))
  local visible = {}
  for i, row in ipairs(ui.itemRows) do
    local entry = list[i + itemOffset]
    visible[#visible + 1] = entry
    if entry then
      row.entry = entry
      row.icon:SetTexture(entry.icon)
      row.name:SetText(itemName(entry))
      row.count:SetText(entry.inBags and tostring(entry.count) or "-")
      row.dest:SetText(destinationText(db, entry))
      row:Show()
    else
      row:Hide()
    end
  end
  if #list > 0 then
    ui.itemsPage:SetText(("%d-%d of %d"):format(itemOffset + 1, math.min(itemOffset + ITEM_ROWS, #list), #list))
  else
    ui.itemsPage:SetText("")
  end
  ui.prevButton:SetEnabled(itemOffset > 0)
  ui.nextButton:SetEnabled(itemOffset + ITEM_ROWS < #list)
  ui.emptyItems:SetShown(#list == 0)
  -- Ask the server only for the names of the rows on screen.
  ns.Items.RequestNames(visible)
end

-- Options tab -----------------------------------------------------------------------

local function addExclude(itemID)
  ns.Items.SetChoice(ns.db, itemID, "never")
  changed()
end

local function removeExclude(itemID)
  ns.db.exclude[itemID] = nil
  changed()
end

local function option(name)
  return function(self)
    ns.db.options[name] = self:GetChecked() and true or false
  end
end

local function buildOptionsTab(pane)
  local labelWidth = WIDTH - 2 * LEFT - CHECK - 4
  ui.autoCheck = checkBox(pane, LEFT, -8, labelWidth, option("autoAttach"))
  ui.autoCheck.label:SetText("Fill the mail when I type a bank alt's name (or its shortcut) in To:")
  ui.chainCheck = checkBox(pane, LEFT, -36, labelWidth, option("chain"))
  ui.chainCheck.label:SetText("After one mail goes out, send the next one without another click")
  ui.openCheck = checkBox(pane, LEFT, -64, labelWidth, option("autoSendOnOpen"))
  ui.openCheck.label:SetText("Send to every bank alt as soon as I open a mailbox")
  text(pane, "Everything goes right away, so there is no chance to leave items out at the mailbox.",
    "GameFontDisableSmall", LEFT + CHECK + 4, -86)
  ui.stackCheck = checkBox(pane, LEFT, -108, labelWidth, option("stackFirst"))
  ui.stackCheck.label:SetText("Combine partial stacks of outgoing items first (fewer mails, less postage)")

  local excludeY = -166
  text(pane, "Never send (any bank alt)", "GameFontNormal", LEFT, excludeY + 18)
  ui.excludeDrop = dropZone(pane, LEFT, excludeY, "Drag an item here to keep it in your bags.", addExclude)
  ui.excludeMore = text(pane, "", "GameFontDisableSmall", LEFT, excludeY - 2 * (ICON + ICON_GAP))
  text(pane, "Hearthstone, tools, soulbound and quest items never go anyway.", "GameFontDisableSmall",
    LEFT, excludeY - 2 * (ICON + ICON_GAP) - 14)
  ui.excludeButtons = {}
  ui.excludeY = excludeY
end

local function refreshOptions(db)
  ui.autoCheck:SetChecked(db.options.autoAttach)
  ui.chainCheck:SetChecked(db.options.chain)
  ui.openCheck:SetChecked(db.options.autoSendOnOpen)
  ui.stackCheck:SetChecked(db.options.stackFirst)
  layoutIcons(panes.options, ui.excludeButtons, ns.SortedIDs(db.exclude), LEFT + ICON + 8, ui.excludeY,
    removeExclude, ui.excludeMore)
end

-- Window -----------------------------------------------------------------------------

function Config.Create()
  if frame then return end
  frame = CreateFrame("Frame", "HamalConfig", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  -- Below DIALOG, so the game's menus and confirmation popups always open on top of it.
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", ns.Safely(function(self) self:StartMoving() end))
  frame:SetScript("OnDragStop", ns.Safely(function(self)
    self:StopMovingOrSizing()
    -- Remember where the player put it.
    local point, _, relativePoint, x, y = self:GetPoint()
    if point then ns.db.window = { point = point, relativePoint = relativePoint, x = x, y = y } end
  end))
  frame:Hide()
  table.insert(UISpecialFrames, "HamalConfig") -- Esc closes it

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -6)
  title:SetText("Hamal")

  for i, tab in ipairs(TABS) do
    local b = button(frame, tab.label, 110, LEFT + (i - 1) * 114, -28, function(self) Config.ShowTab(self.tab) end)
    b.tab = tab.key
    tabButtons[tab.key] = b
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", 0, PANE_TOP)
    pane:SetPoint("BOTTOMRIGHT", 0, 0)
    panes[tab.key] = pane
  end
  buildAltsTab(panes.alts)
  buildItemsTab(panes.items)
  buildOptionsTab(panes.options)

  frame:HookScript("OnShow", ns.Safely(function() Config.Refresh() end))
  frame:HookScript("OnHide", ns.Safely(function()
    ns.Listen("GET_ITEM_INFO_RECEIVED", false)
    itemsCache = nil
  end))

  Config.frame = frame
  ui.tabs = tabButtons
  Config.widgets = ui
end

function Config.Refresh()
  if not frame or not frame:IsShown() or not ns.db then return end
  if currentTab == "alts" then
    refreshAlts(ns.db)
  elseif currentTab == "items" then
    refreshItems(ns.db)
  else
    refreshOptions(ns.db)
  end
end

function Config.ShowTab(key)
  currentTab = key
  for k, pane in pairs(panes) do
    pane:SetShown(k == key)
  end
  for k, b in pairs(tabButtons) do
    if k == key then b:LockHighlight() else b:UnlockHighlight() end -- the open tab glows
  end
  local itemsOpen = key == "items" and frame:IsShown()
  -- Item-info events are only worth hearing while the Items tab is on screen.
  ns.Listen("GET_ITEM_INFO_RECEIVED", itemsOpen)
  if itemsOpen then
    ns.Items.RecordSeen(ns.db)
    itemsCache = nil
  end
  Config.Refresh()
end

-- Where the player last put the window; otherwise next to the mailbox panel, so it
-- doesn't cover it, or in the middle of the screen.
local function placeWindow()
  if frame:IsShown() then return end
  frame:ClearAllPoints()
  local saved = ns.db.window
  local panel = ns.UI and ns.UI.panel
  if saved and saved.point then
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  elseif panel and panel:IsVisible() then
    frame:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
  else
    frame:SetPoint("CENTER")
  end
end

function Config.Open(key, tab)
  Config.Create()
  if key and ns.db.mules[key] then
    selectedKey = key
    tab = tab or "alts"
  end
  placeWindow()
  frame:Show()
  Config.ShowTab(tab or currentTab)
end

function Config.Toggle()
  Config.Create()
  if frame:IsShown() then
    frame:Hide()
  else
    placeWindow()
    frame:Show()
    Config.ShowTab(currentTab)
  end
end

-- Item names arrive from the server a moment after first being asked for; bag changes
-- while the Items tab is open change counts. Both rebuild the list at most every 0.3 s.
local pendingRefresh = false
local function refreshItemsSoon()
  if pendingRefresh or not frame or not frame:IsShown() or currentTab ~= "items" then return end
  pendingRefresh = true
  ns.After(0.3, function()
    pendingRefresh = false
    itemsCache = nil
    Config.Refresh()
  end)
end
ns.On("GET_ITEM_INFO_RECEIVED", refreshItemsSoon)
ns.Listen("GET_ITEM_INFO_RECEIVED", false) -- switched on by ShowTab("items")
ns.On("BAG_UPDATE_DELAYED", refreshItemsSoon)

-- Entry in the minimap's addon menu (## AddonCompartmentFunc in the TOC).
function Hamal_OnAddonCompartmentClick()
  Config.Toggle()
end
