local _, ns = ...

-- A button by the minimap, written without libraries. It is a child of UIParent and
-- only anchored to the minimap, so UI suites that hide or collect the minimap's own
-- children leave it alone. Drag it around the minimap's edge (round or square), or
-- Shift-drag it anywhere on screen, which also keeps it usable when a UI hides the minimap.
local Button = {}
ns.MinimapButton = Button

local SIZE = 31
local EDGE_GAP = 10 -- how far outside the minimap's edge it sits
local DEFAULT_ANGLE = 200

local button
local atan2 = math.atan2 or math.atan -- Lua 5.1 (the game) / 5.3+ (tests)

-- Many UI suites declare a square minimap through GetMinimapShape (a long-standing
-- convention); anything else is treated as round.
local function minimapShape()
  if type(GetMinimapShape) == "function" then
    local ok, shape = pcall(GetMinimapShape)
    if ok and shape == "SQUARE" then return "SQUARE" end
  end
  return "ROUND"
end

-- Offset from the minimap's centre for an angle in degrees: on a ring around a round
-- minimap, on the edge of a square one.
function Button.Offset(angle, width, height, shape)
  local rad = math.rad(angle)
  local x, y = math.cos(rad), math.sin(rad)
  if shape == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
  end
  return x * (width / 2 + EDGE_GAP), y * (height / 2 + EDGE_GAP)
end

local function settings()
  local db = ns.db
  db.minimap = db.minimap or {}
  return db.minimap
end

function Button.Place()
  if not button then return end
  local cfg = settings()
  button:ClearAllPoints()
  if (cfg.free and cfg.x) or not Minimap then
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cfg.x or 300, cfg.y or 300)
    return
  end
  local x, y = Button.Offset(cfg.angle or DEFAULT_ANGLE, Minimap:GetWidth() or 140, Minimap:GetHeight() or 140,
    minimapShape())
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Follow the cursor while dragging (OnUpdate runs only during a drag).
local function follow()
  local cfg = settings()
  local cx, cy = GetCursorPosition()
  if IsShiftKeyDown() or not Minimap then
    local scale = UIParent:GetEffectiveScale() or 1
    cfg.free, cfg.x, cfg.y = true, cx / scale, cy / scale
  else
    local scale = Minimap:GetEffectiveScale() or 1
    local mx, my = Minimap:GetCenter()
    cfg.free = nil
    cfg.angle = math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360
  end
  Button.Place()
end

local function onClick(_, mouseButton)
  if mouseButton == "RightButton" then
    if ns.Mailer.IsMailboxOpen() then
      ns.Mailer.SendAll(true)
    else
      ns.Print("Open a mailbox, then right-click here to send everything to your bank alts.")
    end
    return
  end
  ns.Config.Toggle()
end

local function onEnter(self)
  ns.Widgets.ShowTextTooltip(self, "Hamal\n"
    .. "|cffffffffClick:|r settings\n"
    .. "|cffffffffRight-click:|r send all (at a mailbox)\n"
    .. "|cffffffffDrag:|r move around the minimap\n"
    .. "|cffffffffShift-drag:|r place anywhere")
end

function Button.Create()
  if button then return end
  button = CreateFrame("Button", "HamalMinimapButton", UIParent)
  button:SetSize(SIZE, SIZE)
  button:SetFrameStrata("MEDIUM")
  if Minimap then button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8) end
  button:SetClampedToScreen(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetPoint("CENTER")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  -- Hamal's logo; the game's letter icon if the client can't load it.
  if icon:SetTexture(ns.LOGO) == false then icon:SetTexture("Interface\\Icons\\INV_Letter_15") end
  icon:SetPoint("CENTER")
  Button.icon = icon
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", ns.Safely(onClick))
  button:SetScript("OnEnter", ns.Safely(onEnter))
  button:SetScript("OnLeave", ns.Safely(ns.Widgets.HideTooltip))
  button:SetScript("OnDragStart", ns.Safely(function(self)
    self:SetScript("OnUpdate", ns.Safely(follow))
  end))
  button:SetScript("OnDragStop", ns.Safely(function(self)
    self:SetScript("OnUpdate", nil)
    follow()
  end))
  Button.button = button
end

function Button.Refresh()
  if settings().hide then
    if button then button:Hide() end
    return
  end
  Button.Create()
  Button.Place()
  button:Show()
end

function Button.SetShown(shown)
  settings().hide = not shown or nil
  Button.Refresh()
end

-- Back on the minimap ring, at the default spot.
function Button.Reset()
  local cfg = settings()
  cfg.free, cfg.x, cfg.y, cfg.angle = nil, nil, nil, nil
  Button.Refresh()
end

ns.On("PLAYER_LOGIN", function()
  if ns.db then Button.Refresh() end
end)
