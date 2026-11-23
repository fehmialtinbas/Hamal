local _, ns = ...

-- Small building blocks shared by the mailbox panel and the settings window.
local Widgets = {}
ns.Widgets = Widgets

function Widgets.HideTooltip()
  GameTooltip:Hide()
end

-- `item` is an item ID, or a scanned bag item ({ bag, slot, itemID }).
function Widgets.ShowItemTooltip(owner, item, hint)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if type(item) == "table" and item.bag then
    GameTooltip:SetBagItem(item.bag, item.slot)
  else
    GameTooltip:SetItemByID(type(item) == "table" and item.itemID or item)
  end
  if hint then GameTooltip:AddLine(hint, 0.6, 0.8, 1, true) end
  GameTooltip:Show()
end

function Widgets.ShowTextTooltip(owner, text)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(text, 1, 1, 1, 1, true)
  GameTooltip:Show()
end

function Widgets.IconButton(parent, size)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(size, size)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  button.count:SetPoint("BOTTOMRIGHT", -1, 1)
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetScript("OnLeave", Widgets.HideTooltip)
  return button
end

-- The item on the cursor (picked up from a bag), returned to its slot.
function Widgets.TakeCursorItem()
  local kind, itemID = GetCursorInfo()
  if kind ~= "item" or not itemID then return nil end
  ClearCursor()
  return itemID
end
