local _, ns = ...

local Categories = {}
ns.Categories = Categories

-- Item class IDs (Enum.ItemClass)
local CONSUMABLE, WEAPON, GEM, ARMOR, TRADEGOODS, RECIPE = 0, 2, 3, 4, 7, 9

-- Each entry matches on { classID, subclassID }; a missing subclassID matches the whole class.
-- Ordered from specific to broad: the first match is the reason shown in /hamal preview.
Categories.list = {
  { key = "cloth",       label = "Cloth",                        match = { { TRADEGOODS, 5 } } },
  { key = "leather",     label = "Leather",                      match = { { TRADEGOODS, 6 } } },
  { key = "metal",       label = "Metal & stone",                match = { { TRADEGOODS, 7 } } },
  { key = "herb",        label = "Herbs",                        match = { { TRADEGOODS, 9 } } },
  { key = "meat",        label = "Cooking ingredients",          match = { { TRADEGOODS, 8 } } },
  { key = "elemental",   label = "Elemental",                    match = { { TRADEGOODS, 10 } } },
  { key = "enchanting",  label = "Enchanting",                   match = { { TRADEGOODS, 12 } } },
  { key = "engineering", label = "Parts, explosives & devices",
    match = { { TRADEGOODS, 1 }, { TRADEGOODS, 2 }, { TRADEGOODS, 3 } } },
  { key = "tradegoods",  label = "All trade goods",              match = { { TRADEGOODS } } },
  { key = "gems",        label = "Gems",                         match = { { GEM } } },
  { key = "recipes",     label = "Recipes",                      match = { { RECIPE } } },
  { key = "potions",     label = "Potions, elixirs & flasks",
    match = { { CONSUMABLE, 1 }, { CONSUMABLE, 2 }, { CONSUMABLE, 3 } } },
  { key = "scrolls",     label = "Scrolls",                      match = { { CONSUMABLE, 4 } } },
  { key = "food",        label = "Food & drink",                 match = { { CONSUMABLE, 5 } } },
  { key = "bandages",    label = "Bandages",                     match = { { CONSUMABLE, 7 } } },
  { key = "boe",         label = "Unbound gear, green or better", match = { { WEAPON }, { ARMOR } }, minQuality = 2 },
}

Categories.byKey = {}
for _, def in ipairs(Categories.list) do
  Categories.byKey[def.key] = def
end

function Categories.Get(key)
  if type(key) ~= "string" then return nil end
  return Categories.byKey[key:lower()]
end

function Categories.Matches(key, item)
  local def = Categories.byKey[key]
  if not def or not item then return false end
  if def.minQuality and (item.quality or 0) < def.minQuality then return false end
  for _, m in ipairs(def.match) do
    if item.classID == m[1] and (m[2] == nil or item.subclassID == m[2]) then
      return true
    end
  end
  return false
end
