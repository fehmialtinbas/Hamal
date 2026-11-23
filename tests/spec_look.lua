local T = require("harness")
local F = require("fixtures")

-- The game look (default) and the dark, plain look.

local function openAll(w, ns)
  w:OpenMailbox()
  SlashCmdList.HAMAL("")
  return ns.UI.panel, ns.Config.frame, ns.UI.sendAllButton
end

T.describe("Look", function()
  T.it("starts with the game's look", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 2, 20)
    local panel, window, button = openAll(w, ns)
    T.eq(panel.hamalLook, "game")
    T.eq(window.hamalLook, "game")
    T.eq(button.hamalLook, "game")
    T.truthy(not button.hamalFill or not button.hamalFill:IsShown(), "the red button art shows")
  end)

  T.it("switches open windows at once from the Options tab, and back", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 2, 20)
    local panel, window, button = openAll(w, ns)
    ns.Config.ShowTab("options")
    local check = ns.Config.widgets.darkCheck
    check:Click()
    T.eq(ns.db.options.look, "dark")
    T.eq(panel.hamalLook, "dark", "mailbox panel")
    T.eq(window.hamalLook, "dark", "settings window")
    T.truthy(button.hamalFill:IsShown(), "flat button")
    T.truthy(ns.Config.widgets.tabs.items.hamalFill:IsShown(), "tabs too")
    check:Click()
    T.eq(panel.hamalLook, "game")
    T.truthy(not button.hamalFill:IsShown(), "red buttons again")
  end)

  T.it("remembers the dark look for windows built later", function()
    local w, ns = F.setup(function(w) w.savedDB = { options = { look = "dark" } } end)
    local key = F.addMule(ns, "Vault Keeper")
    ns.Mules.ToggleCategory(ns.db, key, "cloth")
    w:Fill(F.LINEN, 2, 20)
    local panel, window, button = openAll(w, ns)
    T.eq(panel.hamalLook, "dark")
    T.eq(window.hamalLook, "dark")
    T.truthy(button.hamalFill:IsShown())
  end)

  T.it("switches with /hamal look", function()
    local _, ns = F.setup()
    SlashCmdList.HAMAL("look dark")
    T.eq(ns.Theme.Look(), "dark")
    SlashCmdList.HAMAL("look")
    T.eq(ns.Theme.Look(), "game", "no word: toggles")
  end)

  T.it("costs nothing but the restyling", function()
    local w, ns = F.withVault()
    w:Fill(F.LINEN, 2, 20)
    openAll(w, ns)
    local scans = 0
    local eachItem = ns.Scanner.EachItem
    ns.Scanner.EachItem = function(...)
      scans = scans + 1
      return eachItem(...)
    end
    ns.Theme.SetLook("dark")
    ns.Theme.SetLook("game")
    T.eq(scans, 0, "no bag reads")
  end)
end)

T.describe("About", function()
  T.it("shows the version and a copyable GitHub address that can't be edited", function()
    local _, ns = F.setup()
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("options")
    local box = ns.Config.widgets.websiteBox
    T.eq(box:GetText(), "https://github.com/fehmialtinbas/Hamal")
    T.truthy(ns.Config.widgets.about:GetText():find("Hamal dev by fehmialtinbas"), "version and author")
    box.text = "https://github.com/fehmialtinbas/Hamalxyz"
    box:FireScript("OnTextChanged", true)
    T.eq(box:GetText(), "https://github.com/fehmialtinbas/Hamal", "typing changes nothing")
  end)

  T.it("asks for nothing in game: no tips, no donations", function()
    local _, ns = F.setup()
    SlashCmdList.HAMAL("")
    ns.Config.ShowTab("options")
    local about = ns.Config.widgets.about:GetText():lower()
    for _, word in ipairs({ "tip", "donat", "coffee", "gold", "support" }) do
      T.truthy(not about:find(word), "no '" .. word .. "' in the about text")
    end
  end)
end)
