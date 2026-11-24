local T = require("harness")
local F = require("fixtures")

local function sentCounts(w)
  local counts = {}
  for i, mail in ipairs(w.sent) do counts[i] = #mail.items end
  return table.concat(counts, ",")
end

T.describe("Combining stacks", function()
  T.it("combines partial stacks of outgoing items before filling the mail", function()
    local w, ns = F.withVault()
    w:Put(0, 1, F.LINEN, 7)
    w:Put(0, 2, F.LINEN, 12)
    w:Put(0, 3, F.LINEN, 5)
    w:Put(0, 4, F.LINEN, 20)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    T.truthy(ns.Mailer.stacking, "combining first")
    T.truthy(ns.UI.status:GetText():find("Combining stacks"), "says so")
    w:Flush()
    T.eq(w:StackSizes(F.LINEN), "4,20,20", "44 cloth in 3 stacks instead of 4")
    T.eq(ns.Mailer.stacking, nil)
    T.eq(ns.Mailer.AttachedCount(), 3, "then the mail is filled")
    T.eq(#w.sent, 0, "nothing sent without a click")
  end)

  T.it("never touches items that aren't being mailed", function()
    local w, ns = F.withVault() -- takes cloth only
    w:Put(0, 1, F.PEACEBLOOM, 3)
    w:Put(0, 2, F.PEACEBLOOM, 4)
    w:Put(0, 3, F.LINEN, 5)
    w:Put(0, 4, F.LINEN, 6)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    w:Flush()
    T.eq(w:StackSizes(F.PEACEBLOOM), "3,4", "herbs left as they were")
    T.eq(w:StackSizes(F.LINEN), "11")
  end)

  T.it("sends fewer mails for 100 half-full stacks", function()
    local w, ns = F.setup(function(w)
      for bag = 0, 4 do w.bagSize[bag] = 24 end
    end)
    local key = F.addMule(ns, "Bank Keeper")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    w:Fill(F.LINEN, 100, 10) -- 100 stacks of 10 = 50 full stacks
    w:OpenMailbox()
    T.eq(ns.UI.sendAllButton:GetText(), "Send all: 5 mail(s), ~15s", "estimate after combining")
    w:Click(ns.UI.sendAllButton)
    w:Flush()
    T.eq(sentCounts(w), "12,12,12,12,2", "5 mails instead of 9")
    T.eq(w:StacksInBags(F.LINEN), 0)
  end)

  T.it("can be switched off", function()
    local w, ns = F.withVault()
    ns.db.options.stackFirst = false
    w:Put(0, 1, F.LINEN, 7)
    w:Put(0, 2, F.LINEN, 5)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    T.eq(ns.Mailer.stacking, nil)
    T.eq(ns.Mailer.AttachedCount(), 2)
    T.eq(w.moves, nil, "no moves")
  end)

  T.it("leaves your bags alone while you hold an item", function()
    local w, ns = F.withVault()
    w:Put(0, 1, F.LINEN, 7)
    w:Put(0, 2, F.LINEN, 5)
    w:Put(1, 1, F.PEACEBLOOM, 3)
    w:OpenMailbox()
    C_Container.PickupContainerItem(1, 1) -- the player picked up some herbs
    w:Click(ns.UI.muleButtons[1])
    w:Flush()
    T.eq(w.moves, nil, "no moves")
    T.eq(w:StackSizes(F.LINEN), "5,7")
  end)

  T.it("gives up waiting on slots that stay locked and mails what it can", function()
    local w, ns = F.withVault()
    w.stuckLocks = true -- the server never confirms
    w:Put(0, 1, F.LINEN, 7)
    w:Put(0, 2, F.LINEN, 5)
    w:Put(0, 3, F.LINEN, 3)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    w:Flush()
    T.eq(ns.Mailer.stacking, nil, "stopped waiting")
    T.truthy(ns.Mailer.session, "and went on")
  end)

  T.it("stops when the mailbox closes", function()
    local w, ns = F.withVault()
    w:Put(0, 1, F.LINEN, 7)
    w:Put(0, 2, F.LINEN, 5)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    w:CloseMailbox()
    w:Flush()
    T.eq(ns.Mailer.stacking, nil)
    T.eq(ns.Mailer.session, nil)
  end)

  T.it("learns the real postage from the game", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    T.eq(ns.db.postage.perStack, 30)
    T.eq(ns.db.postage.base, 0)
  end)

  T.it("finds a per-mail fee too and counts it in the estimate", function()
    local w, ns = F.setup(function(w)
      for bag = 0, 4 do w.bagSize[bag] = 24 end
      w.postageBase = 50 -- a client that charges 50 copper per mail plus 30 per stack
    end)
    local key = F.addMule(ns, "Bank Keeper")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    w:Fill(F.LINEN, 25, 20)
    w:OpenMailbox()
    T.eq(ns.UI.sendAllButton:GetText(), "Send all: 3 mail(s), ~7s 50c", "assumed price before any mail")
    w:Click(ns.UI.muleButtons[1])
    T.eq(ns.db.postage.base, 50, "per-mail fee measured")
    T.eq(ns.db.postage.perStack, 30, "per-stack fee measured")
    ns.Mailer.Cancel()
    ns.UI.Refresh()
    T.eq(ns.UI.sendAllButton:GetText(), "Send all: 3 mail(s), ~9s", "3 x 50 + 25 x 30")
    local money = w.money
    w:Click(ns.UI.sendAllButton)
    w:Flush()
    T.eq(money - w.money, 900, "the estimate is what it cost")
  end)

  T.it("always sends the fewest stacks and mails possible", function()
    math.randomseed(7)
    for round = 1, 20 do
      local w, ns = F.setup(function(w)
        for bag = 0, 4 do w.bagSize[bag] = 24 end
        w:DefineItem(F.LEATHER, "Light Leather", 7, 6, 1, 10) -- stacks of 10
      end)
      local key = F.addMule(ns, "Bank Keeper")
      ns.Mules.ToggleCategory(ns.db, key, "tradegoods")
      local totals, max = {}, { [F.LINEN] = 20, [F.PEACEBLOOM] = 20, [F.LEATHER] = 10 }
      for itemID, size in pairs(max) do
        totals[itemID] = 0
        for _ = 1, math.random(0, 35) do
          local count = math.random(1, size)
          w:Fill(itemID, 1, count)
          totals[itemID] = totals[itemID] + count
        end
      end
      local fewestStacks = 0
      for itemID, total in pairs(totals) do
        fewestStacks = fewestStacks + math.ceil(total / max[itemID])
      end
      w:OpenMailbox()
      w:Click(ns.UI.sendAllButton)
      w:Flush()
      local stacks, sent = 0, {}
      for _, mail in ipairs(w.sent) do
        stacks = stacks + #mail.items
        for _, it in ipairs(mail.items) do sent[it.itemID] = (sent[it.itemID] or 0) + it.count end
      end
      local where = "round " .. round
      T.eq(stacks, fewestStacks, where .. ": stacks")
      T.eq(#w.sent, math.ceil(fewestStacks / 12), where .. ": mails")
      for itemID, total in pairs(totals) do
        T.eq(sent[itemID] or 0, total, where .. ": every item arrived")
      end
    end
  end)
end)
