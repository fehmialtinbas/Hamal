local T = require("harness")
local F = require("fixtures")

-- Another addon (DaylightUI, TradeSkillMaster...) replaces the game's mail window: the
-- game's window stays open but hidden away. Hamal must still be usable, and must not
-- leave items in the game's mail form where that addon's Send button could mail them
-- to any name typed into it.

local function sentCounts(w)
  local counts = {}
  for i, mail in ipairs(w.sent) do counts[i] = #mail.items end
  return table.concat(counts, ",")
end

local function openReplaced(w)
  w:OpenMailbox()
  w:ParkMailWindow()
  w:Flush()
end

T.describe("Other mail windows", function()
  T.it("docks beside the game's mail window when it is on screen", function()
    local w, ns = F.withVault()
    w:OpenMailbox()
    T.truthy(ns.UI.panel:IsVisible(), "panel shown")
    T.eq(ns.UI.panel.docked, true)
  end)

  T.it("still shows its panel when another addon hides the game's window", function()
    local w, ns = F.withVault()
    openReplaced(w)
    T.truthy(ns.UI.panel:IsVisible(), "panel shown on its own")
    T.eq(ns.UI.panel.docked, false, "floating, not stuck to the hidden window")
    w:CloseMailbox()
    T.truthy(not ns.UI.panel:IsShown(), "hidden when the mailbox closes")
  end)

  T.it("never leaves items in the mail form behind another window", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 15, 20)
    openReplaced(w)
    w:Click(ns.UI.muleButtons[1])
    T.eq(ns.Mailer.AttachedCount(), 0, "queued, not attached")
    T.eq(#ns.Mailer.SessionItems(), 15, "the panel still lists them")
    T.truthy(ns.UI.sendButton:IsEnabled(), "Send is ready")
    w:Click(ns.UI.sendButton)
    w:Flush()
    T.eq(sentCounts(w), "12,3")
    T.eq(ns.Mailer.AttachedCount(), 0)
  end)

  T.it("takes the items back out when the game wants a click per mail", function()
    local w, ns = F.withVault()
    w.requireHardware = true
    w:Fill(F.LINEN, 15, 20)
    openReplaced(w)
    w:Click(ns.UI.sendAllButton)
    w:Flush()
    T.eq(sentCounts(w), "12", "first mail by the click")
    T.eq(ns.Mailer.AttachedCount(), 0, "the refused second mail left nothing in the form")
    T.eq(w:LockedInBags(), 0)
    T.eq(#ns.Mailer.session.queue, 3, "back in the queue")
    w:Click(ns.UI.sendButton)
    w:Flush()
    T.eq(sentCounts(w), "12,3")
  end)

  T.it("sends nothing of ours when that window mails someone else", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 5, 20)
    openReplaced(w)
    w:Click(ns.UI.muleButtons[1])
    -- The player uses the other addon's own Send to write to a friend.
    w.hardware = true
    SendMail("Some Friend", "hello", "")
    w.hardware = false
    w:Flush()
    T.eq(#w.sent, 1)
    T.eq(#w.sent[1].items, 0, "none of Hamal's items went with it")
  end)
end)
