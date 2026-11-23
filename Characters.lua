local _, ns = ...

-- Remembers this account's characters so the settings window can list them.
-- Each character adds itself when it logs in; characters Bagnon already knows are
-- imported so they show up before you have logged in on them with Hamal.
local Characters = {}
ns.Characters = Characters

local function realmList(db)
  local realm = ns.RealmKey()
  db.characters[realm] = db.characters[realm] or {}
  return db.characters[realm]
end

function Characters.Register(db)
  local name = ns.PlayerName()
  if not name then return end
  local list = realmList(db)
  local entry = list[name] or {}
  local _, class = UnitClass("player")
  entry.class = class
  entry.level = UnitLevel("player")
  entry.faction = UnitFactionGroup("player")
  entry.imported = nil
  list[name] = entry
end

-- Bagnon (BagBrother) keeps BrotherBags[realm][name] = { class, level, faction = isAlliance, ... }.
function Characters.ImportBagnon(db)
  local realmChars = type(BrotherBags) == "table" and BrotherBags[ns.RealmKey()]
  if type(realmChars) ~= "table" then return 0 end
  local list = realmList(db)
  local added = 0
  for name, info in pairs(realmChars) do
    -- Guild banks are stored as "Guild Name*"; characters always have a class.
    if type(name) == "string" and type(info) == "table" and info.class
      and not name:find("%*$") and not list[name] then
      local faction
      if info.faction == true then faction = "Alliance" elseif info.faction == false then faction = "Horde" end
      list[name] = { class = info.class, level = info.level, faction = faction, imported = true }
      added = added + 1
    end
  end
  return added
end

-- Characters to show in the settings window: this realm and faction, plus any bank
-- alt added by name. Sorted by name.
function Characters.List(db)
  local me = ns.PlayerName()
  local myFaction = UnitFactionGroup("player")
  local out, listed = {}, {}
  for name, info in pairs(realmList(db)) do
    if not info.faction or not myFaction or info.faction == myFaction then
      local key = ns.NormalizeName(name)
      out[#out + 1] = { name = name, key = key, class = info.class, level = info.level, isMe = name == me }
      listed[key] = true
    end
  end
  for key, mule in pairs(db.mules) do
    if not listed[key] then
      out[#out + 1] = { name = mule.name, key = key, manual = true }
    end
  end
  for _, entry in ipairs(out) do
    entry.isBank = ns.Mules.IsActive(db, entry.key)
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

ns.On("PLAYER_LOGIN", function()
  if not ns.db then return end
  Characters.Register(ns.db)
  Characters.ImportBagnon(ns.db)
end)

ns.On("PLAYER_LEVEL_UP", function(level)
  local entry = ns.db and realmList(ns.db)[ns.PlayerName()]
  if entry then entry.level = level end
end)
