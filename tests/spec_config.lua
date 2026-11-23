local T = require("harness")
local F = require("fixtures")

-- Bagnon data for this account: two rogues, two level-1 bank characters, a guild
-- bank and an Alliance character that must not show up.
local function withAccount(w)
  w.brotherBags = {
    forever = {
      ["Main Character"] = { class = "ROGUE", level = 22, faction = false },
      ["Cloth Bank"] = { class = "WARRIOR", level = 1, faction = false },
      ["Herb Bank"] = { class = "WARRIOR", level = 1, faction = false },
      ["Other Rogue"] = { class = "ROGUE", level = 24, faction = false },
      ["Some Guild*"] = { faction = false },
      ["Ally Mage"] = { class = "MAGE", level = 10, faction = true },
    },
  }
end

local function open(ns, tab)
  SlashCmdList.HAMAL("")
  if tab then ns.Config.ShowTab(tab) end
  return ns.Config.widgets
end

local function rowFor(ui, name)
  for _, row in ipairs(ui.charRows) do
    if row:IsShown() and row.entry.name == name then return row end
  end
end

local function categoryCheck(ui, key)
  for _, check in ipairs(ui.categoryChecks) do
    if check.category == key then return check end
  end
end

local function itemRow(ui, itemID)
  for _, row in ipairs(ui.itemRows) do
    if row:IsShown() and row.entry.itemID == itemID then return row end
  end
end

T.describe("Characters", function()
  T.it("register themselves and come in from Bagnon", function()
    local _, ns = F.setup(withAccount)
    local names = {}
    for _, entry in ipairs(ns.Characters.List(ns.db)) do
      names[#names + 1] = entry.name .. (entry.isMe and "*" or "")
    end
    T.eq(table.concat(names, ","), "Cloth Bank,Herb Bank,Main Character*,Other Rogue")
    T.eq(ns.db.characters.forever["Main Character"].level, 22)
  end)

  T.it("use the first and last name on Forever", function()
    local _, ns = F.setup()
    T.eq(ns.PlayerName(), "Main Character")
  end)
end)

T.describe("Settings: bank alts tab", function()
  T.it("ticks characters of the account as bank alts", function()
    local w, ns = F.setup(withAccount)
    local ui = open(ns)
    local row = rowFor(ui, "Cloth Bank")
    T.truthy(row, "Cloth Bank listed")
    T.eq(row.check:GetChecked(), false)
    w:Click(row.check)
    T.truthy(ns.Mules.IsActive(ns.db, "cloth bank"), "now a bank alt")
    T.eq(ui.header:GetText(), "Cloth Bank")
    T.truthy(categoryCheck(ui, "cloth"):IsShown(), "item types shown")
  end)

  T.it("gives each bank alt its own item types", function()
    local w, ns = F.setup(withAccount)
    local ui = open(ns)
    w:Click(rowFor(ui, "Cloth Bank").check)
    w:Click(categoryCheck(ui, "cloth"))
    w:Click(rowFor(ui, "Herb Bank").check)
    T.eq(ui.header:GetText(), "Herb Bank")
    T.eq(categoryCheck(ui, "cloth"):GetChecked(), false, "Herb Bank has no cloth")
    T.truthy(categoryCheck(ui, "cloth").label:GetText():find("Cloth Bank"), "label says who gets cloth")
    w:Click(categoryCheck(ui, "herb"))
    w:Put(0, 1, F.LINEN, 20)
    w:Put(0, 2, F.PEACEBLOOM, 5)
    w:Put(0, 3, F.LINEN, 20)
    local counts = ns.Scanner.CountAll(ns.db)
    T.eq(counts["cloth bank"], 2)
    T.eq(counts["herb bank"], 1)
  end)

  T.it("keeps the rules of an unticked bank alt for later", function()
    local w, ns = F.setup(withAccount)
    local ui = open(ns)
    local row = rowFor(ui, "Cloth Bank")
    w:Click(row.check)
    w:Click(categoryCheck(ui, "cloth"))
    w:Click(row.check)
    T.eq(ns.Mules.IsActive(ns.db, "cloth bank"), false, "off")
    T.eq(ns.Mules.FindExact(ns.db, "Cloth Bank"), nil, "typing its name does nothing")
    w:Put(0, 1, F.LINEN, 20)
    T.eq(ns.Scanner.CountAll(ns.db)["cloth bank"], nil, "gets nothing")
    w:Click(row.check)
    T.truthy(ns.db.mules["cloth bank"].categories.cloth, "cloth rule is back")
  end)

  T.it("adds a bank alt from another account by name", function()
    local w, ns = F.setup(withAccount)
    local ui = open(ns)
    w:Enter(ui.nameBox, "Friend Bank")
    T.truthy(ns.Mules.IsActive(ns.db, "friend bank"))
    T.truthy(rowFor(ui, "Friend Bank"), "listed")
    T.eq(ui.subHeader:GetText(), "Added by name")
  end)

  T.it("adds single items by drag and drop", function()
    local w, ns = F.setup(withAccount)
    w:Put(0, 1, F.PEACEBLOOM, 5)
    local ui = open(ns)
    w:Click(rowFor(ui, "Herb Bank").check)
    w:DragItem(0, 1, ui.itemDrop)
    T.truthy(ns.db.mules["herb bank"].items[F.PEACEBLOOM], "item rule")
    T.eq(w:LockedInBags(), 0, "item went back to the bag")
    T.eq(ui.itemButtons[1].itemID, F.PEACEBLOOM)
    w:Click(ui.itemButtons[1])
    T.eq(ns.db.mules["herb bank"].items[F.PEACEBLOOM], nil, "removed")
  end)

  T.it("keeps one shortcut per bank alt", function()
    local w, ns = F.setup(withAccount)
    local ui = open(ns)
    w:Click(rowFor(ui, "Cloth Bank").check)
    w:Enter(ui.aliasBox, "cb")
    T.eq(ns.db.aliases.cb, "cloth bank")
    w:Enter(ui.aliasBox, "cc")
    T.eq(ns.db.aliases.cb, nil, "old shortcut gone")
    T.eq(ns.db.aliases.cc, "cloth bank")
  end)

  T.it("asks before forgetting a bank alt's rules", function()
    local w, ns = F.setup(withAccount)
    local ui = open(ns)
    w:Click(rowFor(ui, "Cloth Bank").check)
    w:Click(ui.forgetButton)
    T.truthy(ns.db.mules["cloth bank"], "not before confirming")
    w:AcceptPopup()
    T.eq(ns.db.mules["cloth bank"], nil, "forgotten")
    T.truthy(rowFor(ui, "Cloth Bank"), "still listed as a character")
  end)
end)

T.describe("Settings: items tab", function()
  T.it("lists bag items and where they go", function()
    local w, ns = F.setup(function(w)
      withAccount(w)
      w:Put(0, 1, F.LINEN, 20)
      w:Put(0, 2, F.PEACEBLOOM, 5)
      w:Put(0, 3, F.HEARTHSTONE, 1)
    end)
    local cloth = ns.Mules.Add(ns.db, "Cloth Bank")
    ns.Mules.ToggleCategory(ns.db, cloth, "cloth")
    local ui = open(ns, "items")
    T.truthy(itemRow(ui, F.LINEN).dest:GetText():find("Cloth Bank"), "linen goes to Cloth Bank")
    T.truthy(itemRow(ui, F.PEACEBLOOM).dest:GetText():find("stays"), "peacebloom stays")
    T.truthy(itemRow(ui, F.HEARTHSTONE).dest:GetText():find("always kept"), "hearthstone kept")
    T.eq(itemRow(ui, F.LINEN).count:GetText(), "20")
  end)

  T.it("chooses a bank alt for an item from its menu", function()
    local w, ns = F.setup(function(w)
      withAccount(w)
      w:Put(0, 1, F.PEACEBLOOM, 5)
    end)
    ns.Mules.Add(ns.db, "Cloth Bank")
    ns.Mules.Add(ns.db, "Herb Bank")
    local ui = open(ns, "items")
    w:Click(itemRow(ui, F.PEACEBLOOM))
    w:PickMenu("Always send to Herb Bank")
    T.truthy(ns.db.mules["herb bank"].items[F.PEACEBLOOM], "picked")
    T.truthy(itemRow(ui, F.PEACEBLOOM).dest:GetText():find("Herb Bank"), "row updated")
    w:Click(itemRow(ui, F.PEACEBLOOM))
    w:PickMenu("Never send")
    T.truthy(ns.db.exclude[F.PEACEBLOOM], "never")
    T.eq(ns.db.mules["herb bank"].items[F.PEACEBLOOM], nil, "only one choice at a time")
    w:Click(itemRow(ui, F.PEACEBLOOM))
    w:PickMenu("Follow item types")
    T.eq(ns.db.exclude[F.PEACEBLOOM], nil, "back to type rules")
  end)

  T.it("remembers items your characters carried before", function()
    local w, ns = F.setup(function(w)
      w:Put(0, 1, F.LEATHER, 10)
    end)
    w.bags[0][1] = nil -- the leather was mailed away or sold
    local ui = open(ns, "items")
    local row = itemRow(ui, F.LEATHER)
    T.truthy(row, "still listed")
    T.eq(row.count:GetText(), "-")
  end)

  T.it("filters by name", function()
    local w, ns = F.setup(function(w)
      w:Put(0, 1, F.LINEN, 20)
      w:Put(0, 2, F.PEACEBLOOM, 5)
    end)
    local ui = open(ns, "items")
    ui.searchBox:SetText("peace")
    T.truthy(itemRow(ui, F.PEACEBLOOM), "match shown")
    T.eq(itemRow(ui, F.LINEN), nil, "other items hidden")
  end)
end)

T.describe("Settings: options tab", function()
  T.it("switches the options and keeps a never-send list", function()
    local w, ns = F.setup(function(w)
      w:Put(0, 1, F.LINEN, 20)
    end)
    local ui = open(ns, "options")
    T.eq(ui.openCheck:GetChecked(), false, "auto-send starts off")
    w:Click(ui.autoCheck)
    w:Click(ui.chainCheck)
    w:Click(ui.openCheck)
    T.eq(ns.db.options.autoAttach, false)
    T.eq(ns.db.options.chain, false)
    T.eq(ns.db.options.autoSendOnOpen, true)
    w:DragItem(0, 1, ui.excludeDrop)
    T.truthy(ns.db.exclude[F.LINEN], "never send")
    T.eq(ui.excludeButtons[1].itemID, F.LINEN)
    w:Click(ui.excludeButtons[1])
    T.eq(ns.db.exclude[F.LINEN], nil, "removed")
  end)

  T.it("opens from the mailbox panel on the bank alt being filled", function()
    local w, ns = F.setup()
    local cloth = ns.Mules.Add(ns.db, "Cloth Bank")
    local herb = ns.Mules.Add(ns.db, "Herb Bank")
    ns.Mules.ToggleCategory(ns.db, cloth, "cloth")
    ns.Mules.ToggleCategory(ns.db, herb, "herb")
    w:Fill(F.PEACEBLOOM, 2, 5)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[2])
    T.eq(ns.Mailer.session.key, herb)
    w:Click(ns.UI.settingsButton)
    T.truthy(ns.Config.frame:IsShown(), "window open")
    T.eq(ns.Config.widgets.header:GetText(), "Herb Bank")
  end)
end)
