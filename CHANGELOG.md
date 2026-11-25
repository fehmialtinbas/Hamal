# Hamal

## v0.1.4

- While the mailbox is open, stacks about to be mailed look greyed out in the game's own bags,
  and an item's tooltip says which bank alt it goes to. Bag addons such as Bagnon draw their own
  bags, so they get the tooltip line but not the grey marks.
- Hamal's logo on the minimap button, in the window titles and in the game's addon list.

## v0.1.3

- Quest items that aren't soulbound, such as Torn Bear Pelt (a Darkmoon Faire turn-in), can be
  mailed now: pick one for a bank alt on the Items tab, or drag it onto **Always send these
  items**. Item types still never send them.

## v0.1.2

- Postage on the **Send all** button and in `/hamal status` reads in gold, silver and copper
  (`2s 10c`) instead of one long copper number.

## v0.1.1

First public release.

- Mails your bank alts the items their rules pick: item types per bank alt (cloth, herbs, metal
  and stone, gems, recipes, potions, unbound gear and more), single items, and a never-send list.
- **Send all** at the mailbox fills mails of 12 stacks and sends them one after another. Partial
  stacks are combined first, so the fewest stacks and mails go out and postage stays low.
- Only your own characters that Hamal has seen on the same realm and in the same region can be
  mailed. There is no way to type in someone else's name.
- Settings window (`/hamal`), minimap button, key bindings, and a dark look (`/hamal look dark`).
- Works next to addons that replace the game's mail window.
- `/hamal status` shows what Hamal sees, for bug reports.
