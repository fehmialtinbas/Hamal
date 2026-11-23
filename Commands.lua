local _, ns = ...

local Commands = {}
ns.Commands = Commands

local function refresh()
  if ns.UI then ns.UI.Refresh() end
end

-- Pull an item out of command text: a shift-clicked link anywhere, or an item ID at the end.
-- Returns itemID (or nil) and the remaining text.
function Commands.ExtractItem(text)
  local id = text:match("|Hitem:(%d+)")
  if id then
    local rest = text:gsub("|c[^|]*|Hitem:.-|h.-|h|r", ""):gsub("|Hitem:.-|h.-|h", "")
    return tonumber(id), ns.Trim(rest)
  end
  local only = text:match("^%s*(%d+)%s*$")
  if only then return tonumber(only), "" end
  local rest, num = text:match("^(.-)%s+(%d+)%s*$")
  if num then return tonumber(num), ns.Trim(rest) end
  return nil, ns.Trim(text)
end

-- "Vault Keeper cloth herb" -> "Vault Keeper", { "cloth", "herb" }
function Commands.SplitCategories(text)
  local words = {}
  for word in text:gmatch("%S+") do
    words[#words + 1] = word
  end
  local categories = {}
  while #words > 0 and ns.Categories.Get(words[#words]) do
    table.insert(categories, 1, words[#words]:lower())
    words[#words] = nil
  end
  return table.concat(words, " "), categories
end

-- With a single bank alt, commands may leave the name out.
local function findMule(text)
  local db = ns.db
  if ns.Trim(text) == "" then
    local keys = ns.Mules.SortedKeys(db)
    if #keys == 1 then return keys[1] end
  end
  return ns.Mules.Find(db, text)
end

local handlers = {}

function handlers.settings()
  ns.Config.Open()
end
handlers.config = handlers.settings
handlers.options = handlers.settings

-- Everything worth knowing when something doesn't work in the game.
function handlers.status()
  local db = ns.db
  local onOff = function(value) return value and "on" or "off" end
  ns.Print("status (version %s):", tostring(ns.Version()))
  ns.Print("  you: %s | realm: %s | ruleset: %s | Forever client: %s", tostring(ns.PlayerName()),
    tostring(ns.Characters.CurrentRealm()), tostring(ns.Characters.Ruleset()), ns.IsForever and "yes" or "no")
  ns.Print("  mailbox open: %s | items per mail: %d | mail frame found: %s",
    ns.Mailer.IsMailboxOpen() and "yes" or "no", ATTACHMENTS_MAX_SEND or 12,
    (MailFrame and SendMailNameEditBox) and "yes" or "no")
  ns.Print("  options: fill on name %s | one-click chain %s | send on open %s",
    onOff(db.options.autoAttach), onOff(db.options.chain), onOff(db.options.autoSendOnOpen))
  local counts = ns.Scanner.CountAll(db)
  local keys = ns.Mules.SortedKeys(db)
  if #keys == 0 then ns.Print("  no bank alts yet") end
  for _, key in ipairs(keys) do
    local mule = db.mules[key]
    local verdict = ns.Mailer.VerifiedRecipient(key) and "can be mailed" or "gets nothing"
    ns.Print("  bank alt %s: %s, %s, %d stack(s) waiting%s", mule.name, ns.Characters.Place(db, key), verdict,
      counts[key] or 0, mule.disabled and " [off]" or "")
  end
  -- The item types Hamal sees, to check its categories against this client's data.
  local shown, seenIDs = 0, {}
  ns.Scanner.EachItem(function(item)
    if shown < 6 and not seenIDs[item.itemID] then
      seenIDs[item.itemID] = true
      shown = shown + 1
      ns.Print("  bag item %s: class %s / subclass %s%s", item.link or item.itemID, tostring(item.classID),
        tostring(item.subclassID), item.isBound and " (bound)" or "")
    end
  end)
end

function handlers.help()
  ns.Print("commands:")
  ns.Print("  /hamal - open the settings window")
  ns.Print("  /hamal status - what Hamal sees (for bug reports)")
  ns.Print("  /hamal add Name Surname - make one of your characters a bank alt")
  ns.Print("  /hamal cat Name cloth herb - toggle item types for it (/hamal cats lists types)")
  ns.Print("  /hamal item Name [item] - always send this item to it (shift-click the item)")
  ns.Print("  /hamal exclude [item] - never send this item")
  ns.Print("  /hamal alias vk Name - typing vk in To: means this bank alt")
  ns.Print("  /hamal list - bank alts and their rules")
  ns.Print("  /hamal preview Name - what would be sent right now")
  ns.Print("  /hamal send Name - fill the mail (at a mailbox)")
  ns.Print("  /hamal auto on|off - fill the mail when you type a bank alt's name")
  ns.Print("  /hamal chain on|off - send every batch with one click")
  ns.Print("  /hamal remove Name - forget a bank alt")
end

-- Only characters of this account that Hamal has seen log in can become bank alts:
-- a typed name could belong to a stranger.
function handlers.add(args)
  local key = ns.NormalizeName(args)
  local info, name
  if key then info, name = ns.Characters.Entry(ns.db, key) end
  if not info then
    return ns.Print("Hamal only mails your own characters. Log in on %s once with Hamal, then add it.",
      key and ns.CleanName(args) or "that character")
  end
  local mule = ns.db.mules[key]
  if mule then
    mule.disabled = nil
  else
    ns.Mules.Add(ns.db, name)
  end
  ns.Print("Added bank alt %s. Now pick what goes there, e.g. /hamal cat %s cloth herb", name, name)
  if not ns.Characters.CanMail(ns.db, key) then ns.Mailer.ExplainRefusal(key) end
  refresh()
end

function handlers.remove(args)
  local key, err = findMule(args)
  if not key then return ns.Print(err) end
  local name = ns.db.mules[key].name
  if ns.Mailer.session and ns.Mailer.session.key == key then ns.Mailer.Cancel() end
  ns.Mules.Remove(ns.db, key)
  ns.Print("Removed bank alt %s.", name)
  refresh()
end

function handlers.cats()
  ns.Print("item types:")
  for _, def in ipairs(ns.Categories.list) do
    ns.Print("  %s - %s", def.key, def.label)
  end
end

function handlers.cat(args)
  local name, categories = Commands.SplitCategories(args)
  if #categories == 0 then
    return ns.Print("Usage: /hamal cat Name cloth herb  (see /hamal cats)")
  end
  local key, err = findMule(name)
  if not key then return ns.Print(err) end
  local changes = {}
  for _, category in ipairs(categories) do
    local on = ns.Mules.ToggleCategory(ns.db, key, category)
    changes[#changes + 1] = category .. (on and " on" or " off")
  end
  ns.Print("%s: %s", ns.db.mules[key].name, table.concat(changes, ", "))
  refresh()
end

function handlers.item(args)
  local itemID, name = Commands.ExtractItem(args)
  if not itemID then
    return ns.Print("Usage: /hamal item Name [shift-click an item]")
  end
  local key, err = findMule(name)
  if not key then return ns.Print(err) end
  local on = ns.Mules.ToggleItem(ns.db, key, itemID)
  ns.Print("%s %s %s.", ns.ItemLabel(itemID), on and "now goes to" or "no longer goes to", ns.db.mules[key].name)
  refresh()
end

function handlers.exclude(args)
  local itemID = Commands.ExtractItem(args)
  if not itemID then
    return ns.Print("Usage: /hamal exclude [shift-click an item]")
  end
  local exclude = ns.db.exclude
  exclude[itemID] = (not exclude[itemID]) or nil
  ns.Print("%s %s.", ns.ItemLabel(itemID), exclude[itemID] and "will never be sent" or "can be sent again")
  refresh()
end

function handlers.alias(args)
  local alias, name = args:match("^(%S+)%s+(.+)$")
  if not alias then
    return ns.Print("Usage: /hamal alias vk Name Surname")
  end
  local key, err = findMule(name)
  if not key then return ns.Print(err) end
  local ok, aliasErr = ns.Mules.SetAlias(ns.db, alias, key)
  if not ok then return ns.Print(aliasErr) end
  ns.Print("Typing '%s' in To: now means %s.", alias:lower(), ns.db.mules[key].name)
end

function handlers.list()
  local db = ns.db
  local keys = ns.Mules.SortedKeys(db)
  if #keys == 0 then
    return ns.Print("No bank alts yet. Add one: /hamal add Name Surname")
  end
  for _, key in ipairs(keys) do
    local mule = db.mules[key]
    local categories, items, aliases = {}, {}, {}
    for _, def in ipairs(ns.Categories.list) do
      if mule.categories[def.key] then categories[#categories + 1] = def.key end
    end
    for itemID in pairs(mule.items) do
      items[#items + 1] = ns.ItemLabel(itemID)
    end
    for alias, target in pairs(db.aliases) do
      if target == key then aliases[#aliases + 1] = alias end
    end
    table.sort(aliases)
    local aliasText = #aliases > 0 and (" (alias: " .. table.concat(aliases, ", ") .. ")") or ""
    ns.Print("%s%s%s", mule.name, aliasText, mule.disabled and " [off]" or "")
    ns.Print("  types: %s", #categories > 0 and table.concat(categories, ", ") or "none")
    if #items > 0 then ns.Print("  items: %s", table.concat(items, " ")) end
  end
end

function handlers.preview(args)
  local key, err = findMule(args)
  if not key then return ns.Print(err) end
  local name = ns.db.mules[key].name
  local items = ns.Scanner.Collect(ns.db, key)
  if #items == 0 then
    return ns.Print("Nothing in your bags goes to %s.", name)
  end
  local perMail = ATTACHMENTS_MAX_SEND or 12
  ns.Print("%d stack(s) go to %s in %d mail(s):", #items, name, math.ceil(#items / perMail))
  for i = 1, math.min(#items, 20) do
    local item = items[i]
    ns.Print("  %s x%d (%s)", item.link or ns.ItemLabel(item.itemID), item.count, item.reason or "?")
  end
  if #items > 20 then ns.Print("  ...and %d more.", #items - 20) end
end

function handlers.send(args)
  local key, err = findMule(args)
  if not key then return ns.Print(err) end
  ns.Mailer.Start(key)
end

local function setOption(option, label, args)
  local options = ns.db.options
  local word = ns.Trim(args or ""):lower()
  if word == "on" then
    options[option] = true
  elseif word == "off" then
    options[option] = false
  else
    options[option] = not options[option]
  end
  ns.Print("%s: %s", label, options[option] and "on" or "off")
end

function handlers.auto(args)
  setOption("autoAttach", "Fill the mail when you type a bank alt's name", args)
end

function handlers.chain(args)
  setOption("chain", "Send every batch with one click", args)
end

function Commands.Run(msg)
  if not ns.db then return end
  msg = ns.Trim(msg or "")
  if msg == "" then return handlers.settings() end
  local cmd, args = msg:match("^(%S+)%s*(.-)$")
  local handler = cmd and handlers[cmd:lower()] or handlers.help
  handler(args or "")
end

SLASH_HAMAL1 = "/hamal"
SLASH_HAMAL2 = "/ham"
SlashCmdList.HAMAL = Commands.Run
