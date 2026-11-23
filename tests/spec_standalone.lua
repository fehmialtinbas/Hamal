local T = require("harness")
local F = require("fixtures")

local function sentTo(w)
  local names = {}
  for _, mail in ipairs(w.sent) do names[#names + 1] = mail.to .. ":" .. #mail.items end
  return table.concat(names, ",")
end

-- The whole flow, from first login to the last mail, on a client where Hamal is the
-- only addon: no Bagnon, no libraries, nothing else to lean on.
local function fullRun(w, ns)
  -- 1. The bank alt logs in once (Hamal records it), then the main logs in again.
  w.playerName = "Bank Alt"
  ns.Characters.Register(ns.db)
  w.playerName = "Main Character"
  ns.Characters.Register(ns.db)
  -- 2. Settings window: tick the bank alt, give it cloth.
  SlashCmdList.HAMAL("")
  local ui = ns.Config.widgets
  for _, row in ipairs(ui.charRows) do
    if row:IsShown() and row.entry.name == "Bank Alt" then w:Click(row.check) end
  end
  for _, check in ipairs(ui.categoryChecks) do
    if check.category == "cloth" then w:Click(check) end
  end
  -- 3. Mailbox: one click on Send all.
  w:Fill(F.LINEN, 14, 20)
  w:OpenMailbox()
  w:Click(ns.UI.sendAllButton)
  w:Flush()
end

T.describe("Standalone", function()
  T.it("works with no other addon installed", function()
    local w, ns = F.setup()
    T.eq(_G.BrotherBags, nil, "no Bagnon")
    T.eq(_G.LibStub, nil, "no libraries")
    fullRun(w, ns)
    T.eq(sentTo(w), "Bank Alt:12,Bank Alt:2")
  end)

  T.it("does exactly the same with other addons around, reading none of their data", function()
    local w, ns = F.setup(function(w)
      w.brotherBags = {
        forever = {
          ["Stranger Name"] = { class = "MAGE", level = 60, faction = false },
          ["Bank Alt"] = { class = "WARRIOR", level = 1, faction = false },
        },
      }
    end)
    for name in pairs(ns.db.characters.forever) do
      T.truthy(name == "Main Character", "only Hamal's own record, not " .. name)
    end
    fullRun(w, ns)
    T.eq(sentTo(w), "Bank Alt:12,Bank Alt:2")
  end)

  T.it("drops characters an older build copied from Bagnon", function()
    local _, ns = F.setup(function(w)
      w.savedDB = { characters = { forever = {
        ["Copied Name"] = { class = "WARRIOR", level = 1, imported = true },
      } } }
    end)
    T.eq(ns.db.characters.forever["Copied Name"], nil)
  end)
end)
