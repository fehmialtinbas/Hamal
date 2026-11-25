local T = require("harness")
local F = require("fixtures")

-- At the mailbox, what's about to be mailed looks greyed out in the game's own bags,
-- and an item's tooltip names the bank alt it goes to.

local function markShown(ns, button)
  local mark = ns.BagMarks.marks[button]
  return mark ~= nil and mark:IsShown()
end

-- The combined backpack lists bag 0's 16 slots first.
local function combinedButton(frame, bag, slot)
  return frame.buttons[bag * 16 + slot]
end

T.describe("Bag marks", function()
  T.it("grey out the stacks going to a bank alt while the mailbox is open", function()
    local w, ns = F.withVault()
    w:Put(0, 1, F.LINEN, 20)
    w:Put(0, 2, F.LINEN, 7)
    w:Put(0, 3, F.PEACEBLOOM, 5)
    local bags = w:ShowCombinedBags()
    T.truthy(not markShown(ns, combinedButton(bags, 0, 1)), "nothing before the mailbox")
    w:OpenMailbox()
    w:Flush()
    T.truthy(markShown(ns, combinedButton(bags, 0, 1)), "linen")
    T.truthy(markShown(ns, combinedButton(bags, 0, 2)), "the other linen stack")
    T.truthy(not markShown(ns, combinedButton(bags, 0, 3)), "peacebloom stays")
    T.truthy(not markShown(ns, combinedButton(bags, 0, 4)), "empty slot")
    w:CloseMailbox()
    T.truthy(not markShown(ns, combinedButton(bags, 0, 1)), "gone once the mailbox closes")
  end)

  T.it("mark a bag window opened after the mailbox, one window per bag", function()
    local w, ns = F.withVault()
    w:Put(1, 4, F.LINEN, 20)
    local window = w:ShowBagWindow(1, 1)
    window.shown = false
    w:OpenMailbox()
    w:Flush()
    window:Show()
    w:Flush()
    T.truthy(markShown(ns, window.buttons[4]), "linen in bag 1, slot 4")
    T.truthy(not markShown(ns, window.buttons[3]), "the slot next to it")
  end)

  T.it("follow the rules when they change at the mailbox", function()
    local w, ns, key = F.withVault()
    w:Put(0, 1, F.PEACEBLOOM, 5)
    local bags = w:ShowCombinedBags()
    w:OpenMailbox()
    w:Flush()
    T.truthy(not markShown(ns, combinedButton(bags, 0, 1)), "herbs stay")
    ns.Mules.ToggleCategory(ns.db, key, "herb")
    ns.UI.Refresh()
    T.truthy(markShown(ns, combinedButton(bags, 0, 1)), "herbs go now")
  end)

  T.it("unmark a stack left out of this mail", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 14, 20)
    local bags = w:ShowCombinedBags()
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    w:Flush()
    local session = ns.Mailer.session
    T.eq(#session.queue, 2, "12 attached, 2 waiting")
    local left = session.queue[1]
    local waiting = session.queue[2]
    ns.Mailer.Skip(left)
    w:Flush()
    T.truthy(not markShown(ns, combinedButton(bags, left.bag, left.slot)), "left out: not marked")
    T.truthy(markShown(ns, combinedButton(bags, waiting.bag, waiting.slot)), "still waiting: marked")
  end)
end)

T.describe("Tooltip line", function()
  T.it("names the bank alt of an item in your bags, at the mailbox or not", function()
    local w = F.withVault()
    w:Put(0, 1, F.LINEN, 20)
    w:Put(0, 2, F.PEACEBLOOM, 5)
    T.eq(w:HoverBagItem(0, 1), "Hamal: goes to Vault Keeper", "away from the mailbox")
    T.eq(w:HoverBagItem(0, 2), "", "an item that stays")
    T.eq(w:HoverBagItem(0, 3), "", "an empty slot")
    w:OpenMailbox()
    w:Flush()
    T.eq(w:HoverBagItem(0, 1), "Hamal: goes to Vault Keeper", "at the mailbox")
    w:CloseMailbox()
    T.eq(w:HoverBagItem(0, 1), "Hamal: goes to Vault Keeper", "after it")
  end)

  T.it("says nothing at the mailbox for a stack left out of this mail", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 14, 20)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    w:Flush()
    local left = ns.Mailer.session.queue[1]
    ns.Mailer.Skip(left)
    w:Flush()
    T.eq(w:HoverBagItem(left.bag, left.slot), "")
  end)

  T.it("stays out of the bank, Hamal's own icons, and tooltips you switched it off for", function()
    local w, ns = F.withVault()
    w:Put(-1, 1, F.LINEN, 20)
    w:Put(0, 1, F.LINEN, 20)
    T.eq(w:HoverBagItem(-1, 1), "", "bank slot")
    ns.Widgets.ShowItemTooltip(ns.UI.panel or UIParent, { bag = 0, slot = 1, itemID = F.LINEN })
    T.truthy(not table.concat(GameTooltip.lines, "\n"):find("Hamal: goes to"), "Hamal's own icon")
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("options")
    local check = ns.Config.widgets.tooltipCheck
    T.truthy(check:GetChecked(), "on by default")
    check:Click()
    T.eq(ns.db.options.bagTooltips, false)
    T.eq(w:HoverBagItem(0, 1), "", "switched off")
  end)

  T.it("reads only the hovered slot away from the mailbox, and nothing when switched off", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 30, 20)
    w.calls.info = 0
    w:HoverBagItem(0, 1)
    T.eq(w.calls.info, 1, "one slot")
    ns.db.options.bagTooltips = false
    w.calls.info = 0
    w:HoverBagItem(0, 1)
    T.eq(w.calls.info, 0, "switched off")
  end)
end)
