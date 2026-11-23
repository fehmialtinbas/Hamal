-- Hamal: carries the right items from your bags to your bank alts at the mailbox.
local addonName, ns = ...

ns.name = addonName

-- WoW: Forever runs as its own project (WOW_PROJECT_ID 18). Its characters have a
-- first and a last name, and UnitFullName returns the last name instead of a realm.
ns.IsForever = WOW_PROJECT_ID == 18

-- "Vault Keeper" on Forever, "Vault" elsewhere.
function ns.PlayerName()
  if ns.IsForever and UnitFullName then
    local name, surname = UnitFullName("player")
    if name and surname and surname ~= "" then return name .. " " .. surname end
    return name
  end
  return (UnitName("player"))
end

-- Where this account's characters are filed in Hamal's saved data. Forever keeps
-- them in one list (each entry records its real realm, see Characters.lua).
function ns.RealmKey()
  if ns.IsForever then return "forever" end
  return (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
end

function ns.Version()
  local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local version = getMetadata and getMetadata(addonName, "Version")
  if not version or version:find("@") then return "dev" end -- not packaged yet
  return version
end

-- Where the source code and bug reports live (also in the .toc as X-Website).
ns.WEBSITE = "https://github.com/fehmialtinbas/Hamal"

local PREFIX = "|cffe6b85cHamal|r: "

function ns.Print(fmt, ...)
  local msg = fmt
  if select("#", ...) > 0 then
    msg = string.format(fmt, ...)
  end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
  else
    print(PREFIX .. msg)
  end
end

function ns.Trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "  Vault   Keeper " -> "Vault Keeper"
function ns.CleanName(name)
  return (ns.Trim(name):gsub("%s+", " "))
end

-- Names are compared case-insensitively with single spaces, so
-- "vault  keeper" and "Vault Keeper" are the same bank alt.
function ns.NormalizeName(name)
  if type(name) ~= "string" then return nil end
  local s = ns.CleanName(name):lower()
  if s == "" then return nil end
  return s
end

function ns.FormatMoney(copper)
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  return tostring(copper) .. "c"
end

function ns.ItemLabel(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if getInfo then
    local name, link = getInfo(itemID)
    if link or name then return link or name end
  end
  return "item " .. tostring(itemID)
end

local QUESTION_MARK_ICON = 134400

function ns.ItemIcon(itemID)
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local icon = getInstant and select(5, getInstant(itemID))
  return icon or QUESTION_MARK_ICON
end

function ns.SortedIDs(set)
  local ids = {}
  for id in pairs(set) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

-- Saved data ------------------------------------------------------------------

ns.DB_VERSION = 1

local DEFAULTS = {
  -- [normalized name] = { name = "Vault Keeper", categories = { cloth = true }, items = { [2589] = true } }
  mules = {},
  -- [alias] = normalized bank alt name
  aliases = {},
  -- [itemID] = true: never mailed by Hamal
  exclude = {},
  -- [realm key][full name] = { class, level, faction }: this account's characters
  characters = {},
  -- [itemID] = true: mailable items any character has carried (for the Items tab)
  seen = {},
  options = {
    autoAttach = true,      -- fill the mail as soon as a bank alt's name is typed in "To:"
    chain = true,           -- after one mail goes out, send the next batch without another click
    autoSendOnOpen = false, -- send to every bank alt as soon as a mailbox opens
    stackFirst = true,      -- combine partial stacks of outgoing items before mailing
    look = "game",          -- "game" or "dark" (see Theme.lua)
  },
}

local function applyDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      applyDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

function ns.InitDB()
  if type(HamalDB) ~= "table" then HamalDB = {} end
  applyDefaults(HamalDB, DEFAULTS)
  -- Earlier builds stored only a per-stack price.
  if HamalDB.postagePerStack then
    HamalDB.postage = HamalDB.postage or { base = 0, perStack = HamalDB.postagePerStack }
    HamalDB.postagePerStack = nil
  end
  HamalDB.version = ns.DB_VERSION
  ns.db = HamalDB
  return ns.db
end

-- Errors ----------------------------------------------------------------------

-- A bug in Hamal must never nag the player: it goes to the game's error handler
-- (silent unless Lua errors are switched on, or caught by BugSack), the player gets
-- at most one short chat line per session, and /hamal status shows the details.
-- Outside the game (tests) errors are raised so they can't go unnoticed.
local inGame = geterrorhandler ~= nil
ns.errorCount = 0

function ns.ReportError(err)
  if not inGame then error(err, 0) end
  ns.errorCount = ns.errorCount + 1
  ns.lastError = tostring(err)
  if not ns.errorNoticeShown then
    ns.errorNoticeShown = true
    ns.Print("Something went wrong. Type /hamal status for details to report.")
  end
  geterrorhandler()(err)
end

-- Wrap a script handler or callback so an error in it is reported as above.
function ns.Safely(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.ReportError(err) end
  end
end

function ns.After(delay, fn)
  C_Timer.After(delay, ns.Safely(fn))
end

-- Events ----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- Some clients error on unknown event names; a missing event must not break the addon.
    pcall(eventFrame.RegisterEvent, eventFrame, event)
  end
  local list = handlers[event]
  list[#list + 1] = fn
end

-- Switch delivery of a busy event on or off (its handlers stay registered).
function ns.Listen(event, enabled)
  if enabled then
    pcall(eventFrame.RegisterEvent, eventFrame, event)
  else
    eventFrame:UnregisterEvent(event)
  end
end

-- No tables or closures per event: some events fire hundreds of times a second.
eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then ns.ReportError(err) end
  end
end)

local initCallbacks = {}

function ns.OnInit(fn)
  initCallbacks[#initCallbacks + 1] = fn
end

ns.On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  ns.InitDB()
  for i = 1, #initCallbacks do
    initCallbacks[i]()
  end
end)
