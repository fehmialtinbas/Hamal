local T = require("harness")
local F = require("fixtures")

-- Ways in that other UI suites can't take away: a minimap button of Hamal's own,
-- key bindings, the slash command and the mailbox panel.

local function near(a, b) return math.abs(a - b) < 0.01 end

local function anchor(frame)
  local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
  return { point = point, to = relativeTo, relativePoint = relativePoint, x = x, y = y }
end

local function drag(w, button, x, y, shift)
  w.cursorX, w.cursorY = x, y
  w.shift = shift
  button:FireScript("OnDragStart")
  button:FireScript("OnDragStop")
  w.shift = false
end

T.describe("Minimap button", function()
  T.it("sits by the minimap after login", function()
    local _, ns = F.setup()
    local button = ns.MinimapButton.button
    T.truthy(button and button:IsShown(), "shown")
    local a = anchor(button)
    T.eq(a.to, Minimap, "anchored to the minimap")
    local x, y = ns.MinimapButton.Offset(200, 140, 140, "ROUND")
    T.truthy(near(a.x, x) and near(a.y, y), "at the default spot on the ring")
  end)

  T.it("is not a child of the minimap, so hiding the minimap keeps it", function()
    local _, ns = F.setup()
    Minimap:Hide()
    T.truthy(ns.MinimapButton.button:IsVisible(), "still on screen")
  end)

  T.it("opens the settings on click and sends all on right-click at a mailbox", function()
    local w, ns = F.withVault()
    local button = ns.MinimapButton.button
    w:Click(button)
    T.truthy(ns.Config.frame:IsShown(), "settings open")
    w:Click(button)
    T.truthy(not ns.Config.frame:IsShown(), "and closed again")
    w:RightClick(button)
    T.truthy(w:Printed("Open a mailbox"), "says what to do away from a mailbox")
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    w:RightClick(button)
    w:Flush()
    T.eq(#w.sent, 1, "sent")
  end)

  T.it("moves around the edge of a round minimap", function()
    local w, ns = F.setup()
    local button = ns.MinimapButton.button
    drag(w, button, 1900, 900) -- straight to the right of the centre
    T.truthy(near(ns.db.minimap.angle, 0), "angle 0")
    local a = anchor(button)
    T.truthy(near(a.x, 80) and near(a.y, 0), "70 radius + 10 gap")
  end)

  T.it("follows the edge of a square minimap", function()
    local w, ns = F.setup(function(w) w.minimapShape = "SQUARE" end)
    local button = ns.MinimapButton.button
    drag(w, button, 1900, 1000) -- 45 degrees, towards the corner
    local a = anchor(button)
    T.truthy(near(a.x, 80) and near(a.y, 80), "in the corner, not cut inside it")
  end)

  T.it("goes anywhere with Shift-drag and comes back with Reset", function()
    local w, ns = F.setup()
    local button = ns.MinimapButton.button
    drag(w, button, 500, 400, true)
    local a = anchor(button)
    T.eq(a.to, UIParent)
    T.truthy(near(a.x, 500) and near(a.y, 400), "where it was dropped")
    SlashCmdList.HAMAL("minimap reset")
    T.eq(anchor(button).to, Minimap, "back by the minimap")
  end)

  T.it("can be hidden and shown again", function()
    local _, ns = F.setup()
    SlashCmdList.HAMAL("minimap off")
    T.truthy(not ns.MinimapButton.button:IsShown(), "hidden")
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("options")
    local check = ns.Config.widgets.minimapCheck
    T.eq(check:GetChecked(), false)
    check:Click()
    T.truthy(ns.MinimapButton.button:IsShown(), "shown from the options")
  end)
end)

T.describe("Key bindings", function()
  T.it("open the settings and send all at a mailbox", function()
    local w, ns = F.withVault()
    T.eq(BINDING_HEADER_HAMAL, "Hamal")
    Hamal_ToggleSettings()
    T.truthy(ns.Config.frame:IsShown(), "settings open")
    Hamal_SendAll()
    T.truthy(w:Printed("Open a mailbox first"), "away from a mailbox")
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    w.hardware = true -- a key press
    Hamal_SendAll()
    w.hardware = false
    w:Flush()
    T.eq(#w.sent, 1)
  end)
end)
