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
-- `prepare(w)` runs before the addon loads (e.g. to give Bagnon data or bag items).
function F.setup(prepare)
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
  if prepare then prepare(w) end
  local ns = Mock.loadAddon(w)
  return w, ns
end

-- Make `name` a character of this account that has logged in on the current realm,
-- which is what Hamal requires before it mails anything to it.
function F.own(ns, name)
  name = ns.CleanName(name)
  local chars = ns.db.characters[ns.RealmKey()]
  chars[name] = chars[name] or { class = "WARRIOR", level = 1, faction = "Horde" }
  chars[name].realm = Mock.world.realmName
  chars[name].region, chars[name].realmID = Mock.world.region, Mock.world.realmID
  return name
end

-- Marks a saved character entry as seen by Hamal at a login on the current realm.
function F.seenHere(info)
  info.realm = info.realm or Mock.world.realmName
  info.region = info.region or Mock.world.region
  info.realmID = info.realmID or Mock.world.realmID
  return info
end

-- Every character of the account counts as logged in on the current realm.
function F.placeAll(ns)
  for _, info in pairs(ns.db.characters[ns.RealmKey()]) do
    F.seenHere(info)
  end
end

-- One of your characters, made a bank alt.
function F.addMule(ns, name)
  return ns.Mules.Add(ns.db, F.own(ns, name))
end

-- Same, plus one bank alt "Vault Keeper" that takes cloth.
function F.withVault()
  local w, ns = F.setup()
  local key = F.addMule(ns, "Vault Keeper")
  ns.Mules.ToggleCategory(ns.db, key, "cloth")
  return w, ns, key
end

return F
