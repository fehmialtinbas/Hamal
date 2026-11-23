local T = require("harness")
local F = require("fixtures")

-- Problems found in the first test in the game (2026-11-23).

local LUCKY_CHARM = 5373
local FLASH_POWDER = 5140

local function withCharm(w)
  w:DefineItem(LUCKY_CHARM, "Lucky Charm", 15, 0, 1, 20)
  w.items[LUCKY_CHARM].reagent = true -- the game marks it "Crafting Reagent"
  w:DefineItem(FLASH_POWDER, "Flash Powder", 5, 0, 1, 20) -- a rogue's reagent, not a crafting one
end

local function itemRow(ui, itemID)
  for _, row in ipairs(ui.itemRows) do
    if row:IsShown() and row.entry.itemID == itemID then return row end
  end
end

T.describe("In-game findings", function()
  T.it("uses the ruleset as the realm when the game gives no realm name", function()
    local _, ns = F.setup(function(w) w.realmName = "" end)
    T.eq(ns.Characters.CurrentRealm(), "PvP")
    T.eq(ns.db.characters.forever["Main Character"].realm, "PvP")
  end)

  T.it("repairs characters saved with an empty realm name", function()
    local w, ns = F.setup(function(w)
      w.realmName = ""
      w.savedDB = { characters = { forever = {
        ["Bank Keeper"] = { class = "WARRIOR", level = 1, faction = "Horde", realm = "", ruleset = "PvP" },
        ["Mystery Alt"] = { class = "WARRIOR", level = 1, faction = "Horde", realm = "" },
      } } }
    end)
    local bank = ns.Mules.Add(ns.db, "Bank Keeper")
    local mystery = ns.Mules.Add(ns.db, "Mystery Alt")
    T.eq(ns.Characters.Place(ns.db, bank), "here", "realm taken from its ruleset")
    T.eq(ns.Characters.Place(ns.db, mystery), "unknown", "no ruleset either: not mailed")
    T.eq(ns.Mailer.VerifiedRecipient(mystery), nil)
    T.eq(#w.sent, 0)
  end)

  T.it("mails nothing when it can't tell which realm it is on", function()
    local w, ns = F.setup(function(w)
      w.realmName = ""
      w.noGameRules = true
    end)
    T.eq(ns.Characters.CurrentRealm(), nil)
    local key = F.addMule(ns, "Bank Keeper")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    w:Fill(F.LINEN, 2, 20)
    w:OpenMailbox()
    T.eq(#ns.Mailer.PendingAlts(), 0, "an unknown realm is never the same realm")
    T.eq(ns.Mailer.Start(key), false)
  end)

  T.it("adds an item no type covers with a right-click in the Items tab", function()
    local w, ns = F.setup(function(w)
      withCharm(w)
      w:Put(0, 1, LUCKY_CHARM, 1)
    end)
    F.addMule(ns, "Bank Keeper")
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("items")
    local ui = ns.Config.widgets
    T.truthy(itemRow(ui, LUCKY_CHARM).dest:GetText():find("stays in bags"), "no type covers it")
    w:RightClick(itemRow(ui, LUCKY_CHARM))
    T.truthy(ns.db.mules["bank keeper"].items[LUCKY_CHARM], "picked")
    T.truthy(w:Printed("Lucky Charm.* always goes to Bank Keeper"), "confirmed in chat")
    T.truthy(itemRow(ui, LUCKY_CHARM).dest:GetText():find("picked"), "row shows it")
    w:RightClick(itemRow(ui, LUCKY_CHARM))
    T.truthy(ns.db.exclude[LUCKY_CHARM], "next choice: never")
    w:RightClick(itemRow(ui, LUCKY_CHARM))
    T.eq(ns.db.exclude[LUCKY_CHARM], nil, "and back to the item types")
  end)

  T.it("adds an item dropped on the Items list to the bank alt", function()
    local w, ns = F.setup(function(w)
      withCharm(w)
      w:Put(0, 1, LUCKY_CHARM, 1)
    end)
    F.addMule(ns, "Bank Keeper")
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("items")
    local ui = ns.Config.widgets
    w:DragItem(0, 1, ui.itemRows[1]:GetParent() or ui.itemRows[1])
    T.truthy(ns.db.mules["bank keeper"].items[LUCKY_CHARM], "dropped on the list")
    T.eq(w:LockedInBags(), 0, "the item went back to the bag")
  end)

  T.it("sends crafting reagents by their flag, never class reagents like Flash Powder", function()
    local w, ns = F.setup(function(w)
      withCharm(w)
      w:Put(0, 1, LUCKY_CHARM, 1)
      w:Put(0, 2, FLASH_POWDER, 18)
    end)
    local key = F.addMule(ns, "Bank Keeper")
    ns.Mules.ToggleCategory(ns.db, key, "reagents")
    w:OpenMailbox()
    w:Click(ns.UI.sendAllButton)
    w:Flush()
    T.eq(#w.sent, 1)
    T.eq(#w.sent[1].items, 1)
    T.eq(w.sent[1].items[1].itemID, LUCKY_CHARM)
    T.eq(w:StacksInBags(FLASH_POWDER), 1, "Flash Powder stays")
  end)

  T.it("keeps every tab button usable and marks the open one", function()
    local _, ns = F.setup()
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("items")
    for key, tab in pairs(ns.Config.widgets.tabs) do
      T.truthy(tab:IsEnabled(), key .. " tab stays clickable")
    end
  end)
end)
