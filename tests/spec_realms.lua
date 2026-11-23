local T = require("harness")
local F = require("fixtures")

-- The account from the WTF folder, shaped like real data: two characters on the PvP
-- realm, two on the PvE realm. Main Character (logged in) is on PvP.
local function twoRealms(w)
  w.brotherBags = {
    forever = {
      ["Main Character"] = { class = "ROGUE", level = 24, faction = false },
      ["Pvp Bank"] = { class = "WARRIOR", level = 1, faction = false },
      ["Old Rogue"] = { class = "ROGUE", level = 22, faction = false },
      ["Pve Bank"] = { class = "WARRIOR", level = 1, faction = false },
    },
  }
end

-- What Hamal would know once each character has logged in with it once.
local function placeOnRealms(ns)
  local chars = ns.db.characters.forever
  chars["Pvp Bank"].realm = "PvP"
  chars["Old Rogue"].realm = "PvE"
  chars["Pve Bank"].realm = "PvE"
end

local function names(entries)
  local out = {}
  for _, entry in ipairs(entries) do out[#out + 1] = entry.name end
  return table.concat(out, ",")
end

T.describe("Rulesets", function()
  T.it("are read from the game rules", function()
    local w, ns = F.setup()
    T.eq(ns.Characters.Ruleset(), "PvP")
    w.gameRules = { [214] = true }
    T.eq(ns.Characters.Ruleset(), "RP")
    w.gameRules = { [213] = true, [214] = true }
    T.eq(ns.Characters.Ruleset(), "RP-PvP")
    w.gameRules = { [10] = true }
    T.eq(ns.Characters.Ruleset(), "Hardcore")
    w.gameRules = {}
    T.eq(ns.Characters.Ruleset(), "PvE")
  end)

  T.it("are saved with the character at login", function()
    local _, ns = F.setup()
    local me = ns.db.characters.forever["Main Character"]
    T.eq(me.realm, "PvP")
    T.eq(me.ruleset, "PvP")
  end)
end)

T.describe("Realms", function()
  T.it("list this realm first and keep other realms behind a switch", function()
    local _, ns = F.setup(twoRealms)
    T.eq(names(ns.Characters.List(ns.db)), "Main Character,Old Rogue,Pve Bank,Pvp Bank", "nothing placed yet")
    placeOnRealms(ns)
    local entries, leftOut = ns.Characters.List(ns.db)
    T.eq(names(entries), "Main Character,Pvp Bank")
    T.eq(leftOut, 2)
    T.eq(names(ns.Characters.List(ns.db, true)), "Main Character,Pvp Bank,Old Rogue,Pve Bank")
  end)

  T.it("never mail a bank alt on another realm", function()
    local w, ns = F.setup(twoRealms)
    placeOnRealms(ns)
    local pve = ns.Mules.Add(ns.db, "Pve Bank")
    local pvp = ns.Mules.Add(ns.db, "Pvp Bank")
    ns.Mules.ToggleCategory(ns.db, pve, "cloth")
    ns.Mules.ToggleCategory(ns.db, pvp, "tradegoods")
    T.eq(ns.Rules.Resolve({ itemID = F.LINEN, classID = 7, subclassID = 5 }, ns.db), pvp,
      "linen goes to the bank alt on this realm")
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    local keys = ns.Mailer.PendingAlts()
    T.eq(table.concat(keys, ","), pvp)
    T.eq(ns.Mailer.Start(pve), false)
    T.truthy(w:Printed("on the PvE realm"), "says why")
  end)

  T.it("let you hide characters you no longer play", function()
    local w, ns = F.setup(twoRealms)
    local ui
    SlashCmdList.HAMAL("")
    ui = ns.Config.widgets
    local function row(name)
      for _, r in ipairs(ui.charRows) do
        if r:IsShown() and r.entry.name == name then return r end
      end
    end
    w:Click(row("Old Rogue"))
    T.eq(ui.hideButton:GetText(), "Hide")
    w:Click(ui.hideButton)
    T.eq(row("Old Rogue"), nil, "gone from the list")
    T.truthy(ui.showAllCheck.label:GetText():find("%(1%)"), "counted behind the switch")
    w:Click(ui.showAllCheck)
    T.truthy(row("Old Rogue"), "back with the switch on")
    w:Click(row("Old Rogue"))
    T.eq(ui.hideButton:GetText(), "Show")
    w:Click(ui.hideButton)
    T.eq(ns.Characters.Place(ns.db, "old rogue"), "unknown", "shown again")
  end)

  T.it("send nothing to a hidden bank alt and unhide a character that logs in", function()
    local w, ns = F.setup(twoRealms)
    local key = ns.Mules.Add(ns.db, "Pvp Bank")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    ns.Characters.SetHidden(ns.db, key, true)
    T.eq(#ns.Mules.ActiveKeys(ns.db), 0)
    w.playerName = "Pvp Bank"
    ns.Characters.Register(ns.db)
    T.eq(ns.Characters.Place(ns.db, key), "here")
  end)
end)
