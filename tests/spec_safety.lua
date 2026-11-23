local T = require("harness")
local F = require("fixtures")

-- Hamal must never mail your items to anyone but your own characters on this realm.
-- Each test tries one way it could go wrong and checks that nothing is sent.

local function sentTo(w)
  local names = {}
  for _, mail in ipairs(w.sent) do names[#names + 1] = mail.to end
  return table.concat(names, ",")
end

T.describe("Safety", function()
  T.it("never mails a character it has not seen log in on this realm", function()
    -- Another addon (Bagnon here) knows the name, but Hamal ignores other addons:
    -- without its own login record the name could belong to a stranger.
    local w, ns = F.setup(function(w)
      w.brotherBags = { forever = { ["Unplaced Bank"] = { class = "WARRIOR", level = 1, faction = false } } }
    end)
    local key = ns.Mules.Add(ns.db, "Unplaced Bank")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    T.eq(#ns.Mailer.PendingAlts(), 0, "not offered")
    T.eq(ns.Mailer.Start(key), false, "can't be started")
    T.truthy(w:Printed("Unplaced Bank is not one of your characters"), "says why")
    w:Type("Unplaced Bank")
    w:Flush()
    T.eq(ns.Mailer.AttachedCount(), 0, "typing the name fills nothing")
    w:Click(ns.UI.sendAllButton)
    w:Flush()
    T.eq(#w.sent, 0)
  end)

  T.it("never mails the same name on another realm", function()
    local w, ns = F.setup()
    local key = F.addMule(ns, "Twin Name")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    ns.db.characters.forever["Twin Name"].realm = "PvE" -- yours, but on the PvE realm; you are on PvP
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    T.eq(ns.Mailer.Start(key), false)
    T.truthy(w:Printed("on the PvE realm"), "says why")
    T.eq(#w.sent, 0)
  end)

  T.it("refuses to add a name that is not one of your characters", function()
    local w, ns = F.setup()
    SlashCmdList.HAMAL("add Total Stranger")
    T.eq(ns.db.mules["total stranger"], nil, "not added")
    T.truthy(w:Printed("only mails your own characters"), "says why")
  end)

  T.it("ignores a bank alt in the saved data that is not one of your characters", function()
    local w, ns = F.setup()
    -- e.g. left over from an older version, or edited by hand
    ns.db.mules["total stranger"] = { name = "Total Stranger", categories = { cloth = true }, items = {} }
    w:Fill(F.LINEN, 3, 20)
    T.eq(ns.Rules.Resolve({ itemID = F.LINEN, classID = 7, subclassID = 5 }, ns.db), nil, "no rule applies")
    w:OpenMailbox()
    T.eq(ns.Mailer.Start("total stranger"), false)
    T.truthy(w:Printed("is not one of your characters"), "says why")
    T.eq(#w.sent, 0)
  end)

  T.it("checks the recipient again right before sending", function()
    local w, ns, key = F.withVault()
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    T.eq(ns.Mailer.AttachedCount(), 3)
    ns.Characters.SetHidden(ns.db, key, true) -- something changes after the mail was filled
    ns.Mailer.Send()
    w:Flush()
    T.eq(#w.sent, 0, "nothing sent")
    T.eq(ns.Mailer.AttachedCount(), 0, "items taken back out")
    T.eq(w:LockedInBags(), 0)
    T.truthy(w:Printed("Stopped"), "says it stopped")
  end)

  T.it("takes its items back out when To: changes by any means", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    w:Type("Vault Keeper")
    w:Flush()
    T.eq(ns.Mailer.AttachedCount(), 3)
    SendMailNameEditBox:SetText("Someone Else") -- not typed: autocomplete or another addon
    T.eq(ns.Mailer.AttachedCount(), 0, "nothing left for the game's Send button")
    T.eq(ns.Mailer.session, nil)
  end)

  T.it("always mails the exact name of your character", function()
    local w, ns, key = F.withVault()
    ns.Mules.SetAlias(ns.db, "vk", key)
    w:Fill(F.LINEN, 2, 20)
    w:OpenMailbox()
    w:Type("vk")
    w:Flush()
    w:Click(ns.UI.sendButton)
    w:Flush()
    T.eq(sentTo(w), "Vault Keeper")
  end)

  T.it("never sends money or C.O.D. with a bank mail", function()
    local w, ns = F.withVault()
    local money, cod
    SetSendMailMoney = function(v) money = v end
    SetSendMailCOD = function(v) cod = v end
    w:Fill(F.LINEN, 1, 20)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    w:Click(ns.UI.sendButton)
    T.eq(money, 0)
    T.eq(cod, 0)
  end)
end)
