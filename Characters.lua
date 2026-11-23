local _, ns = ...

-- Remembers this account's characters so the settings window can list them.
-- Each character adds itself when it logs in with Hamal. Hamal reads no other
-- addon's data: it works the same whether or not anything else is installed.
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

-- The safety rule: Hamal mails a character only when it is certainly yours and on
-- this realm. That means it logged in on this account with Hamal, on the realm you
-- are on now, and you haven't hidden it. A name on another realm can belong to a
-- stranger here, so characters on other realms, characters not placed yet, hidden
-- ones and typed-in names all get nothing.
function Characters.CanMail(db, key)
  return Characters.Place(db, key) == "here"
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

-- Earlier builds copied characters from Bagnon's data. Those entries were never
-- confirmed by a login with Hamal, so they are dropped (unless the character has
-- since logged in, which clears the flag).
function Characters.DropImported(db)
  local list = realmList(db)
  for name, info in pairs(list) do
    if info.imported then list[name] = nil end
  end
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
  Characters.DropImported(ns.db)
  Characters.Register(ns.db)
end)

ns.On("PLAYER_LEVEL_UP", function(level)
  local entry = ns.db and realmList(ns.db)[ns.PlayerName()]
  if entry then entry.level = level end
end)
