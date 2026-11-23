local _, ns = ...

-- A "mule" is a bank alt: a character that collects items mailed by your other characters.
local Mules = {}
ns.Mules = Mules

function Mules.SortedKeys(db)
  local keys = {}
  for key in pairs(db.mules) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

function Mules.Add(db, name)
  local key = ns.NormalizeName(name)
  if not key then return nil, "Give the bank alt's full name, e.g. /hamal add Vault Keeper" end
  if db.mules[key] then return nil, ("%s is already a bank alt."):format(db.mules[key].name) end
  db.mules[key] = { name = ns.CleanName(name), categories = {}, items = {} }
  return key
end

function Mules.Remove(db, key)
  if not db.mules[key] then return false end
  db.mules[key] = nil
  for alias, target in pairs(db.aliases) do
    if target == key then db.aliases[alias] = nil end
  end
  return true
end

-- Used for the mail "To:" box: only a full name or an alias counts, so typing
-- "Vault" never fills a mail meant for some other "Vault ...".
function Mules.FindExact(db, text)
  local norm = ns.NormalizeName(text)
  if not norm then return nil end
  if db.mules[norm] then return norm end
  local target = db.aliases[norm]
  if target and db.mules[target] then return target end
  return nil
end

-- Used for slash commands: full name, alias, or a unique start of a name ("vault" -> "vault keeper").
function Mules.Find(db, text)
  local key = Mules.FindExact(db, text)
  if key then return key end
  local norm = ns.NormalizeName(text)
  if not norm then return nil, "Which bank alt? Add one with /hamal add Name Surname" end
  local found
  for candidate in pairs(db.mules) do
    if candidate:sub(1, #norm) == norm then
      if found then
        return nil, ("'%s' matches more than one bank alt; type more of the name."):format(text)
      end
      found = candidate
    end
  end
  if not found then
    return nil, ("No bank alt called '%s'. Add one with /hamal add Name Surname"):format(text)
  end
  return found
end

function Mules.SetAlias(db, alias, key)
  local a = ns.NormalizeName(alias)
  if not a or a:find(" ") then return false, "An alias is a single word." end
  if db.mules[a] then return false, "That alias is already a bank alt's name." end
  db.aliases[a] = key
  return true
end

-- The settings window keeps one alias per bank alt: replace whatever it had.
-- An empty alias just removes the old one.
function Mules.SetOnlyAlias(db, key, alias)
  for a, target in pairs(db.aliases) do
    if target == key then db.aliases[a] = nil end
  end
  if not alias or ns.Trim(alias) == "" then return true end
  return Mules.SetAlias(db, alias, key)
end

function Mules.AliasOf(db, key)
  local found = {}
  for alias, target in pairs(db.aliases) do
    if target == key then found[#found + 1] = alias end
  end
  table.sort(found)
  return found[1] or ""
end

-- Bank alts that take a type, in the order Rules.Resolve tries them.
function Mules.CategoryOwners(db, category)
  local owners = {}
  for _, key in ipairs(Mules.SortedKeys(db)) do
    if db.mules[key].categories[category] then owners[#owners + 1] = key end
  end
  return owners
end

function Mules.ToggleCategory(db, key, category)
  local mule = db.mules[key]
  local on = not mule.categories[category]
  mule.categories[category] = on or nil
  return on
end

function Mules.ToggleItem(db, key, itemID)
  local mule = db.mules[key]
  local on = not mule.items[itemID]
  mule.items[itemID] = on or nil
  return on
end
