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

-- Forever has one realm per ruleset (PvE, PvP, RP, ...) and mail stays inside a realm.
function Characters.CurrentRealm()
  return GetRealmName()
end

function Characters.Ruleset()
  local rules = C_GameRules
  local gameRule = Enum and Enum.GameRule
  if not (rules and rules.IsGameRuleActive and gameRule) then return nil end
  local function on(rule) return rule ~= nil and rules.IsGameRuleActive(rule) end
  if on(gameRule.HardcoreRuleset) then return "Hardcore" end
  local pvp, rp = on(gameRule.PvPRuleset), on(gameRule.RPRuleset)
  if pvp and rp then return "RP-PvP" end
  if pvp then return "PvP" end
  if rp then return "RP" end
  return "PvE"
end

-- The registry entry (and its exact name) for a normalized name, if this account has it.
function Characters.Entry(db, key)
  for name, info in pairs(realmList(db)) do
    if ns.NormalizeName(name) == key then return info, name end
  end
end

-- Where a character stands seen from the one logged in:
-- "here" (same realm), "unknown" (not logged in with Hamal yet), "other" (another realm),
-- "hidden" (you said you don't play it) or "manual" (added by name, not on this account).
function Characters.Place(db, key)
  local info = Characters.Entry(db, key)
  if not info then return "manual" end
  if info.hidden then return "hidden" end
  if not info.realm then return "unknown" end
  if info.realm == Characters.CurrentRealm() then return "here" end
  return "other"
end

-- Mail can't cross realms, and hidden characters get nothing. Unknown ones get a try.
function Characters.CanMail(db, key)
  local place = Characters.Place(db, key)
  return place ~= "other" and place ~= "hidden"
end

function Characters.SetHidden(db, key, hidden)
  local info = Characters.Entry(db, key)
  if info then info.hidden = hidden or nil end
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
  entry.realm = Characters.CurrentRealm()
  entry.ruleset = Characters.Ruleset()
  entry.imported = nil
  entry.hidden = nil -- playing it again
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

local PLACE_ORDER = { here = 1, manual = 2, unknown = 3, other = 4, hidden = 5 }

-- Characters for the settings window, same faction only: this realm first, then
-- bank alts added by name, then characters not placed yet. Characters on other realms
-- and hidden ones are left out unless `showAll`; the second result counts them.
function Characters.List(db, showAll)
  local me = ns.PlayerName()
  local myFaction = UnitFactionGroup("player")
  local out, listed, leftOut = {}, {}, 0
  for name, info in pairs(realmList(db)) do
    if not info.faction or not myFaction or info.faction == myFaction then
      local key = ns.NormalizeName(name)
      listed[key] = true
      local place = Characters.Place(db, key)
      if showAll or (place ~= "other" and place ~= "hidden") then
        out[#out + 1] = {
          name = name, key = key, class = info.class, level = info.level, isMe = name == me,
          place = place, realm = info.realm, ruleset = info.ruleset,
        }
      else
        leftOut = leftOut + 1
      end
    end
  end
  for key, mule in pairs(db.mules) do
    if not listed[key] then
      out[#out + 1] = { name = mule.name, key = key, manual = true, place = "manual", isMe = false }
    end
  end
  for _, entry in ipairs(out) do
    entry.isBank = ns.Mules.IsEnabled(db, entry.key)
  end
  table.sort(out, function(a, b)
    if a.isMe ~= b.isMe then return a.isMe == true end
    local pa, pb = PLACE_ORDER[a.place], PLACE_ORDER[b.place]
    if pa ~= pb then return pa < pb end
    return a.key < b.key
  end)
  return out, leftOut
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
