local T = require("harness")
local F = require("fixtures")

-- Hamal's saved data after earlier logins on this account: two level-1 bank
-- characters, another rogue, and an Alliance character that must not show up.
-- Main Character (logged in now) registers itself.
local function withAccount(w)
  local function char(class, level, faction)
    return { class = class, level = level, faction = faction, realm = "PvP", region = 3, realmID = 1 }
  end
  w.savedDB = {
    characters = {
      forever = {
        ["Cloth Bank"] = char("WARRIOR", 1, "Horde"),
        ["Herb Bank"] = char("WARRIOR", 1, "Horde"),
        ["Other Rogue"] = char("ROGUE", 24, "Horde"),
        ["Ally Mage"] = char("MAGE", 10, "Alliance"),
      },
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
    if row:IsShown() and row.entry and row.entry.itemID == itemID then return row end
  end
end

T.describe("Characters", function()
  T.it("are remembered from earlier logins", function()
    local _, ns = F.setup(withAccount)
    local names = {}
    for _, entry in ipairs(ns.Characters.List(ns.db)) do
      names[#names + 1] = entry.name .. (entry.isMe and "*" or "")
    end
    T.eq(table.concat(names, ","), "Main Character*,Cloth Bank,Herb Bank,Other Rogue", "you first, then by name")
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
    T.truthy(ns.Mules.IsEnabled(ns.db, "cloth bank"), "now a bank alt")
    T.eq(ui.header:GetText(), "Cloth Bank")
    T.truthy(categoryCheck(ui, "cloth"):IsShown(), "item types shown")
    T.truthy(ui.subHeader:GetText():find("PvP realm"), "shows its realm")
    T.truthy(ns.Mules.IsActive(ns.db, "cloth bank"), "logged in here before, so it can be mailed")
  end)

  T.it("gives each bank alt its own item types", function()
    local w, ns = F.setup(withAccount)
    F.placeAll(ns) -- every character has logged in once on this realm
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
    F.placeAll(ns)
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

  T.it("has no way to type in a stranger's name", function()
    local _, ns = F.setup(withAccount)
    local ui = open(ns)
    T.eq(ui.nameBox, nil, "no name box")
    T.eq(ui.addButton, nil, "no add-by-name button")
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
    local cloth = F.addMule(ns, "Cloth Bank")
    ns.Mules.ToggleCategory(ns.db, cloth, "cloth")
    local ui = open(ns, "items")
    T.truthy(itemRow(ui, F.LINEN).dest:GetText():find("Cloth Bank"), "linen goes to Cloth Bank")
    T.truthy(itemRow(ui, F.PEACEBLOOM).dest:GetText():find("stays"), "peacebloom stays")
    T.truthy(itemRow(ui, F.HEARTHSTONE).dest:GetText():find("always kept"), "hearthstone kept")
    T.eq(itemRow(ui, F.LINEN).count:GetText(), "20")
  end)

  T.it("keeps a quest-type item until it is picked for a bank alt", function()
    local w, ns = F.setup(function(w)
      withAccount(w)
      w:Put(0, 1, F.QUEST_ITEM, 5)
    end)
    local vault = F.addMule(ns, "Vault Keeper")
    ns.Mules.ToggleCategory(ns.db, vault, "tradegoods")
    local ui = open(ns, "items")
    T.truthy(itemRow(ui, F.QUEST_ITEM).dest:GetText():find("quest item, stays"), "stays at first")
    w:Click(itemRow(ui, F.QUEST_ITEM))
    w:PickMenu("Always send to Vault Keeper")
    T.truthy(itemRow(ui, F.QUEST_ITEM).dest:GetText():find("Vault Keeper"), "goes once picked")
  end)

  T.it("chooses a bank alt for an item from its menu", function()
    local w, ns = F.setup(function(w)
      withAccount(w)
      w:Put(0, 1, F.PEACEBLOOM, 5)
    end)
    F.addMule(ns, "Cloth Bank")
    F.addMule(ns, "Herb Bank")
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

  T.it("shows only what is in your bags when asked, and remembers it", function()
    local w, ns = F.setup(function(w)
      w:Put(0, 1, F.LINEN, 20)
      w:Put(0, 2, F.LEATHER, 10)
    end)
    w.bags[0][2] = nil -- the leather was mailed away or sold
    local ui = open(ns, "items")
    T.truthy(itemRow(ui, F.LEATHER), "everything Hamal knows at first")
    T.eq(ui.bagsOnlyCheck:GetChecked(), false, "off by default")
    w:Click(ui.bagsOnlyCheck)
    T.eq(ns.db.options.itemsBagsOnly, true, "remembered")
    T.truthy(itemRow(ui, F.LINEN), "linen is in the bags")
    T.eq(itemRow(ui, F.LEATHER), nil, "leather is not")
    ui.searchBox:SetText("leather")
    T.truthy(ui.emptyItems:IsShown() and ui.emptyItems:GetText():find("No item matches"), "nothing found")
    ui.searchBox:SetText("")
    w.bags[0][1] = nil
    ns.Config.ShowTab("items")
    T.truthy(ui.emptyItems:IsShown() and ui.emptyItems:GetText():find("Nothing in your bags"), "says why it's empty")
    w:Click(ui.bagsOnlyCheck)
    T.truthy(itemRow(ui, F.LEATHER), "everything again")
  end)

  -- What the list shows, top to bottom: "# Group (n)" for a header, else the item's name.
  local function listed(ui)
    local out = {}
    for _, row in ipairs(ui.itemRows) do
      if row:IsShown() then
        if row.entry then
          out[#out + 1] = row.entry.name
        else
          local count = row.name:GetText():match("|cff%x%x%x%x%x%x(%d+)|r$")
          out[#out + 1] = ("# %s (%s)"):format(row.headerLabel, count)
        end
      end
    end
    return table.concat(out, ", ")
  end

  T.it("groups items by type, trade goods first", function()
    local w, ns = F.setup(function(w)
      w:Put(0, 1, F.PEACEBLOOM, 5)
      w:Put(0, 2, F.LINEN, 20)
      w:Put(0, 3, F.HEALING_POTION, 3)
      w:Put(0, 4, F.GREEN_SWORD, 1)
      w:Put(0, 5, F.LEATHER, 10)
      w:Put(0, 6, F.LINEN, 7)
    end)
    w:DefineItem(9001, "Copper Ore", 7, 7)
    w:DefineItem(9002, "Tin Ore", 7, 7)
    w:Put(1, 1, 9002, 10)
    w:Put(1, 2, 9001, 20)
    local ui = open(ns, "items")
    T.eq(listed(ui), "# Cloth (1), Linen Cloth, # Herb (1), Peacebloom, # Leather (1), Light Leather, "
      .. "# Metal & Stone (2), Copper Ore, Tin Ore, # Potion (1), Minor Healing Potion, # Weapon (1), Green Sword")
    T.eq(itemRow(ui, F.LINEN).count:GetText(), "27", "one row per item, both stacks counted")
    T.eq(ui.itemsPage:GetText(), "1-7 of 7", "headers don't count as items")
    w:Click(itemRow(ui, 9002))
    w:PickMenu("Never send")
    T.truthy(ns.db.exclude[9002], "an item row still works under its header")
  end)

  T.it("shows only items going, staying or never sent, and remembers the choice", function()
    local w, ns = F.setup(function(w)
      w:Put(0, 1, F.LINEN, 20)
      w:Put(0, 2, F.PEACEBLOOM, 5)
      w:Put(0, 3, F.HEARTHSTONE, 1)
      w:Put(0, 4, F.LEATHER, 10)
    end)
    local vault = F.addMule(ns, "Vault Keeper")
    ns.Mules.ToggleCategory(ns.db, vault, "cloth")
    ns.Items.SetChoice(ns.db, F.LEATHER, "never")
    local ui = open(ns, "items")
    T.eq(listed(ui), "# Cloth (1), Linen Cloth, # Herb (1), Peacebloom, # Leather (1), Light Leather, "
      .. "# Miscellaneous (1), Hearthstone", "All")
    w:Click(ui.showButtons.going)
    T.eq(listed(ui), "# Cloth (1), Linen Cloth", "Going")
    T.eq(ns.db.options.itemsShow, "going", "remembered")
    w:Click(ui.showButtons.staying)
    T.eq(listed(ui), "# Herb (1), Peacebloom", "Staying: could go, but no rule sends it")
    w:Click(ui.showButtons.never)
    T.eq(listed(ui), "# Leather (1), Light Leather", "Never")
    w:Click(itemRow(ui, F.LEATHER))
    w:PickMenu("Follow item types")
    T.eq(listed(ui), "", "the last one left the list")
    T.truthy(ui.emptyItems:IsShown() and ui.emptyItems:GetText():find("Click All"), "says how to see the rest")
    w:Click(ui.showButtons.all)
    T.truthy(itemRow(ui, F.HEARTHSTONE), "everything again")
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
    local cloth = F.addMule(ns, "Cloth Bank")
    local herb = F.addMule(ns, "Herb Bank")
    ns.Mules.ToggleCategory(ns.db, cloth, "cloth")
    ns.Mules.ToggleCategory(ns.db, herb, "herb")
    w:Fill(F.PEACEBLOOM, 2, 5)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[2])
    w:Flush() -- the two half stacks are combined first
    T.eq(ns.Mailer.session.key, herb)
    w:Click(ns.UI.settingsButton)
    T.truthy(ns.Config.frame:IsShown(), "window open")
    T.eq(ns.Config.widgets.header:GetText(), "Herb Bank")
  end)
end)
