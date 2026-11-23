local T = require("harness")
local F = require("fixtures")

-- Hamal must not slow the game down or bother the player. These tests count the
-- work it does and the messages it prints.

local function hamalEventFrame(w)
  for _, frame in ipairs(w.frames) do
    if frame.events.ADDON_LOADED then return frame end
  end
end

local function countPrinted(w, pattern)
  local n = 0
  for _, msg in ipairs(w.printed) do
    if msg:find(pattern) then n = n + 1 end
  end
  return n
end

T.describe("Quiet and light", function()
  T.it("says nothing in chat when you log in", function()
    local w = F.setup()
    T.eq(#w.printed, 0)
  end)

  T.it("costs nothing when your bags change away from the mailbox", function()
    local w = F.withVault()
    w:Fill(F.LINEN, 10, 20)
    w.calls.info = 0
    for _ = 1, 50 do w:Fire("BAG_UPDATE_DELAYED") end
    w:Flush()
    T.eq(w.calls.info, 0, "no bag reads while looting")
  end)

  T.it("turns a burst of bag and mail events into one refresh", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 20, 20)
    w:OpenMailbox()
    local scans = 0
    local countAll = ns.Scanner.CountAll
    ns.Scanner.CountAll = function(...)
      scans = scans + 1
      return countAll(...)
    end
    for _ = 1, 20 do w:Fire("BAG_UPDATE_DELAYED") end
    for _ = 1, 12 do w:Fire("MAIL_SEND_INFO_UPDATE") end
    w:Flush()
    T.eq(scans, 1, "32 events, one bag scan")
  end)

  T.it("listens to item-info events only while the Items tab is open", function()
    local w, ns = F.setup()
    local events = hamalEventFrame(w).events
    T.eq(events.GET_ITEM_INFO_RECEIVED, nil, "not after login")
    SlashCmdList.HAMAL("")
    T.eq(events.GET_ITEM_INFO_RECEIVED, nil, "not on the Bank alts tab")
    ns.Config.ShowTab("items")
    T.eq(events.GET_ITEM_INFO_RECEIVED, true, "on the Items tab")
    ns.Config.frame:Hide()
    T.eq(events.GET_ITEM_INFO_RECEIVED, nil, "window closed")
  end)

  T.it("asks the server only for the item names on screen", function()
    local w, ns = F.setup(function(w)
      local seen = {}
      for id = 50001, 50300 do seen[id] = true end -- 300 items the client doesn't have cached
      w.savedDB = { seen = seen }
    end)
    T.eq(w.calls.request, 0, "nothing asked at login")
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("items")
    T.truthy(w.calls.request > 0 and w.calls.request <= 15, "one page, asked " .. w.calls.request)
    local before = w.calls.request
    w:Click(ns.Config.widgets.nextButton)
    T.truthy(w.calls.request - before <= 15, "the next page only")
  end)

  T.it("shows one short line for a bug, however often it happens", function()
    local w, ns = F.setup(function(w) w.useErrorHandler = true end)
    local key = F.addMule(ns, "Vault Keeper")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    w:Fill(F.LINEN, 3, 20)
    w:OpenMailbox()
    w:Click(ns.UI.muleButtons[1])
    ns.Mailer.Send = function() error("pretend bug") end
    for _ = 1, 3 do w:Click(ns.UI.sendButton) end
    T.eq(#w.errors, 3, "each one reaches the game's error handler (silent by default)")
    T.eq(countPrinted(w, "Something went wrong"), 1, "the player sees one line")
    SlashCmdList.HAMAL("status")
    T.truthy(w:Printed("errors this session: 3, last: .*pretend bug"), "details in /hamal status")
  end)
end)
