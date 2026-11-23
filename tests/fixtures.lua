local Mock = require("mock_wow")

local F = {
  LINEN = 2589,
  PEACEBLOOM = 2447,
  LEATHER = 2318,
  HEARTHSTONE = 6948,
  THIEVES_TOOLS = 5060,
  GREEN_SWORD = 1000,
  GREY_SHIRT = 1001,
  QUEST_ITEM = 2000,
  HEALING_POTION = 118,
}

-- A fresh fake client with the addon loaded and a few known items.
function F.setup()
  local w = Mock.new()
  w:DefineItem(F.LINEN, "Linen Cloth", 7, 5)
  w:DefineItem(F.PEACEBLOOM, "Peacebloom", 7, 9)
  w:DefineItem(F.LEATHER, "Light Leather", 7, 6)
  w:DefineItem(F.HEARTHSTONE, "Hearthstone", 15, 0)
  w:DefineItem(F.THIEVES_TOOLS, "Thieves' Tools", 7, 0)
  w:DefineItem(F.GREEN_SWORD, "Green Sword", 2, 7, 2)
  w:DefineItem(F.GREY_SHIRT, "Grey Shirt", 4, 1, 0)
  w:DefineItem(F.QUEST_ITEM, "Quest Thing", 12, 0)
  w:DefineItem(F.HEALING_POTION, "Minor Healing Potion", 0, 1)
  local ns = Mock.loadAddon(w)
  return w, ns
end

-- Same, plus one bank alt "Vault Keeper" that takes cloth.
function F.withVault()
  local w, ns = F.setup()
  local key = ns.Mules.Add(ns.db, "Vault Keeper")
  ns.Mules.ToggleCategory(ns.db, key, "cloth")
  return w, ns, key
end

return F
