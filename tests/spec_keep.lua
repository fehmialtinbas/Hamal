local T = require("harness")
local F = require("fixtures")

-- "Keep at least N in my bags": whole stacks of an item stay, the rest goes.

local LINEN_LINK = "|cffffffff|Hitem:2589::::::::24:::::::|h[Linen Cloth]|h|r"

local function stacks(counts)
  local list = {}
  for i, n in ipairs(counts) do list[i] = { count = n } end
  return list
end

local function keptCounts(kept)
  local counts = {}
  for i, stack in ipairs(kept) do counts[i] = stack.count end
  table.sort(counts)
  return table.concat(counts, ",")
end

local function sentCounts(w)
  local counts = {}
  for i, mail in ipairs(w.sent) do counts[i] = #mail.items end
  return table.concat(counts, ",")
end

local function markShown(ns, button)
  local mark = ns.BagMarks.marks[button]
  return mark ~= nil and mark:IsShown()
end

local function itemRow(ui, itemID)
  for _, row in ipairs(ui.itemRows) do
    if row:IsShown() and row.entry and row.entry.itemID == itemID then return row end
  end
end

local function menuEntry(w, label)
  for _, entry in ipairs(w.menu or {}) do
    if entry.text == label then return entry end
  end
end

local function sendAll(w, ns)
  w:OpenMailbox()
  w:Click(ns.UI.sendAllButton)
  w:Flush()
end

T.describe("Keep at least N", function()
  T.it("keeps the fewest items it can in whole stacks", function()
    local _, ns = F.setup()
    local pick = ns.Rules.PickKept
    T.eq(keptCounts(pick(stacks({ 20, 20, 5 }), 10)), "20", "one stack covers it")
    T.eq(keptCounts(pick(stacks({ 20, 20, 5 }), 22)), "5,20", "the biggest, then the smallest that covers the rest")
    T.eq(keptCounts(pick(stacks({ 3, 3, 3, 3, 3 }), 5)), "3,3")
    T.eq(keptCounts(pick(stacks({ 20, 20 }), 40)), "20,20")
    T.eq(keptCounts(pick(stacks({ 7, 5 }), 50)), "5,7", "less than asked: all of it stays")
  end)

  T.it("leaves the kept stacks in the bags and mails the rest", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 3, 20)
    ns.Items.SetKeep(ns.db, F.LINEN, 20)
    sendAll(w, ns)
    T.eq(sentCounts(w), "2", "two stacks in one mail")
    T.eq(w:StackSizes(F.LINEN), "20", "one stack stays")
  end)

  T.it("still combines partial stacks when the amount is whole stacks", function()
    local w, ns = F.withVault()
    w:Put(0, 1, F.LINEN, 7)
    w:Put(0, 2, F.LINEN, 12)
    w:Put(0, 3, F.LINEN, 5)
    w:Put(0, 4, F.LINEN, 20)
    ns.Items.SetKeep(ns.db, F.LINEN, 20)
    sendAll(w, ns)
    T.eq(sentCounts(w), "2", "20 + 4 go")
    T.eq(w:StackSizes(F.LINEN), "20")
  end)

  T.it("doesn't combine stacks when the amount isn't whole stacks", function()
    local w, ns = F.withVault()
    for slot = 1, 5 do w:Put(0, slot, F.LINEN, 3) end
    ns.Items.SetKeep(ns.db, F.LINEN, 5)
    w:OpenMailbox()
    T.truthy(ns.UI.sendAllButton:GetText():find("^Send all: 1 mail"), ns.UI.sendAllButton:GetText())
    w:Click(ns.UI.sendAllButton)
    w:Flush()
    T.eq(w.moves, nil, "no moves: one stack of 15 would keep all 15")
    T.eq(sentCounts(w), "3")
    T.eq(w:StackSizes(F.LINEN), "3,3", "6 stay for a keep of 5")
  end)

  T.it("leaves the kept stacks out of the Send all estimate", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 25, 20)
    ns.Items.SetKeep(ns.db, F.LINEN, 40)
    w:OpenMailbox()
    T.truthy(ns.UI.sendAllButton:GetText():find("^Send all: 2 mail%(s%)"), ns.UI.sendAllButton:GetText())
    w:Click(ns.UI.sendAllButton)
    w:Flush()
    T.eq(sentCounts(w), "12,11")
    T.eq(w:StacksInBags(F.LINEN), 2)
  end)

  T.it("doesn't grey out the kept stacks and says so in their tooltip", function()
    local w, ns = F.withVault()
    w:Put(0, 1, F.LINEN, 20)
    w:Put(0, 2, F.LINEN, 20)
    ns.Items.SetKeep(ns.db, F.LINEN, 20)
    T.eq(w:HoverBagItem(0, 2), "Hamal: goes to Vault Keeper (you keep 20)", "away from the mailbox")
    local bags = w:ShowCombinedBags()
    w:OpenMailbox()
    w:Flush()
    T.truthy(not markShown(ns, bags.buttons[1]), "the kept stack")
    T.truthy(markShown(ns, bags.buttons[2]), "the stack that goes")
    T.eq(w:HoverBagItem(0, 1), "Hamal: stays in your bags (you keep 20)\nAlt-click: keep all of it this time")
    T.eq(w:HoverBagItem(0, 2), "Hamal: goes to Vault Keeper (you keep 20)\nAlt-click: keep it this time")
  end)

  T.it("is chosen from an item's menu on the Items tab", function()
    local w, ns = F.withVault()
    w:Put(0, 1, F.LINEN, 20)
    w:Put(0, 2, F.PEACEBLOOM, 5)
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("items")
    local ui = ns.Config.widgets
    w:Click(itemRow(ui, F.LINEN))
    T.truthy(menuEntry(w, "Send every stack").selected, "nothing kept at first")
    w:PickMenu("Keep 2 stacks (40)")
    T.eq(ns.db.keep[F.LINEN], 40)
    T.truthy(w:Printed("at least 40 stay in your bags"), "said in chat")
    T.truthy(itemRow(ui, F.LINEN).dest:GetText():find("keeps 40", 1, true), "the row says so")
    w:Click(itemRow(ui, F.LINEN))
    T.truthy(menuEntry(w, "Keep 2 stacks (40)").selected, "ticked in the menu")
    w:PickMenu("Send every stack")
    T.eq(ns.db.keep[F.LINEN], nil)
    T.truthy(not itemRow(ui, F.LINEN).dest:GetText():find("keeps", 1, true))
    w:Click(itemRow(ui, F.PEACEBLOOM))
    T.eq(menuEntry(w, "Send every stack"), nil, "no keep choices for an item no rule sends")
  end)

  T.it("is set, listed and cleared with /hamal keep", function()
    local w, ns = F.withVault()
    SlashCmdList.HAMAL("keep " .. LINEN_LINK .. " 30")
    T.eq(ns.db.keep[F.LINEN], 30)
    SlashCmdList.HAMAL("keep")
    T.truthy(w:Printed("You keep at least: .- 30"), "listed")
    w:Put(0, 1, F.LINEN, 20)
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("items")
    w:Click(itemRow(ns.Config.widgets, F.LINEN))
    T.truthy(menuEntry(w, "Keep 30").selected, "a typed amount shows in the menu")
    SlashCmdList.HAMAL("keep 2589 off")
    T.eq(ns.db.keep[F.LINEN], nil)
    SlashCmdList.HAMAL("keep 2589 lots")
    T.truthy(w:Printed("Usage: /hamal keep"), "a word that isn't a number")
    T.eq(ns.db.keep[F.LINEN], nil)
  end)

  T.it("ignores a broken saved amount", function()
    local w, ns = F.withVault()
    ns.db.keep[F.LINEN] = "lots"
    w:Fill(F.LINEN, 2, 20)
    sendAll(w, ns)
    T.eq(w:StacksInBags(F.LINEN), 0, "everything went")
  end)
end)
