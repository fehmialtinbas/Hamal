# Hamal

*Hamal* is Turkish for "porter": someone who carries other people's loads. This addon carries your
materials to your bank alts.

Open a mailbox and type your bank alt's name in **To:** (or click it in the Hamal panel). Hamal fills
the mail with everything in your bags that belongs to that alt. One click on **Send** mails it all,
12 items per mail, batch after batch.

Built for **World of Warcraft: Forever** (1.60.1, interface 16001).

> Status: early. The mailing flow is covered by offline tests against a fake client but has not
> been tried in the game yet.

## Setup (in game)

Type `/hamal` (or use the minimap addon menu, or **Settings** in the mailbox panel) to open the settings window.

**Bank alts tab**

- Your characters are listed on the left. Each one appears after you log in on it once; if you use
  Bagnon, the characters it knows are imported right away.
- Tick the ones that are bank alts. You can have as many as you like.
- Select a bank alt and tick the **item types** it gets: cloth for one, herbs and leather for another, and so on.
  A grey name next to a type shows which other alt already takes it.
- **Always send these items**: drag a single item from your bags onto the slot.
- **Shortcut for To:**: a one-word alias, e.g. `vk` for Vault Keeper.
- Unticking a bank alt keeps its rules for later; **Forget** deletes them.

**Realms and rulesets.** Forever has one realm per ruleset (PvE, PvP, RP, ...) and mail does not
cross realms. Each character records its realm and ruleset when you log in on it, and then:

- the list shows the characters on your current realm; characters on other realms sit behind
  **Show other realms and hidden**;
- items only go to bank alts on your current realm (a cloth alt on another realm is skipped and the
  next matching alt on this realm gets the cloth);
- characters Bagnon imported but you have not logged in on yet show a `?` and get nothing until they do;
- **Hide** a character you no longer play: it leaves the list and gets no mail. Logging in on it
  shows it again.

**Items tab**

Every item in your bags, every item your characters carried before, and every item with a rule,
with where it goes right now. Click one to choose: *Follow item types*, *Always send to (bank alt)*, or *Never send*.

**Options tab**

- Fill the mail when you type a bank alt's name.
- Send every batch with one click.
- Send to every bank alt as soon as you open a mailbox (off by default).
- The never-send list.

Everything can also be done with slash commands (see below), e.g.:

```
/hamal add Vault Keeper
/hamal cat Vault Keeper cloth leather herb
/hamal preview vault
```

Names can be shortened in commands as long as they stay unique (`vault` instead of `Vault Keeper`).
With a single bank alt you can leave the name out.

## At the mailbox

**Everything at once:** press **Send all** at the top of the Hamal panel. Hamal mails each bank alt
its items, one after another. With "send as soon as I open a mailbox" on, this happens by itself.

**One bank alt, with a final check:**

1. Open the **Send Mail** tab. The Hamal panel next to it lists your bank alts and how many stacks are waiting for each.
2. Type a bank alt's full name or alias in **To:**, or click its button. Hamal attaches the first 12 stacks
   and shows every stack it is about to send as an icon. Dimmed icons wait for a later mail.
3. Changed your mind about one? **Click** its icon to leave it out this time, **Shift-click** to never send that item.
4. Press **Send mail 1/N** (Hamal's button or the game's own Send). Hamal sends the remaining batches one after another.

If the game insists on a click for every mail, Hamal notices, turns chaining off and lets you press
Send once per batch. `/hamal chain on` tries chaining again.

Writing to someone else after Hamal filled the mail? Change the name in **To:** and Hamal takes its items back out.

## Your items never go to anyone else

Hamal mails a character only when it is certainly one of yours and on the realm you are on:

- it has logged in on this account with Hamal installed, on this realm, and you haven't hidden it;
- there is no way to type in another name: bank alts are picked from your own characters;
- characters on other realms are refused (the same name there can belong to a stranger here),
  and so are characters Hamal has not seen log in yet;
- the recipient is checked again right before every mail, and the exact name of your character is used;
- if the **To:** field changes to anything else after Hamal filled the mail, Hamal takes its items back out;
- money and C.O.D. are always set to zero on Hamal's mails.

The one thing Hamal cannot know: if you delete a character, its name becomes free for others.
Use **Forget** on a bank alt before you delete it.

## What is never sent

- Soulbound, quest and locked items
- Hearthstone, Thieves' Tools and profession tools (mining pick, skinning knife, hammer, rods, ...)
- Anything on your exclude list: `/hamal exclude [item]`

If two bank alts want the same item:

1. A single-item rule beats any type rule.
2. A specific type beats a broad one: the alt with `cloth` gets Linen Cloth even if another alt takes `tradegoods`.
3. Between equal rules, the alphabetically first bank alt gets it (the settings window warns you).

## Item types

| key | what |
| --- | --- |
| `cloth`, `leather`, `metal`, `herb`, `meat`, `elemental`, `enchanting` | the matching trade goods |
| `engineering` | parts, explosives and devices |
| `tradegoods` | all trade goods |
| `gems`, `recipes`, `potions`, `scrolls`, `food`, `bandages` | as named |
| `boe` | unbound weapons and armor, green or better |

## Commands

| command | does |
| --- | --- |
| `/hamal` | open the settings window |
| `/hamal add Name` / `remove Name` | add or forget a bank alt |
| `/hamal cat Name type...` | toggle item types |
| `/hamal item Name [item]` | toggle one item |
| `/hamal exclude [item]` | never send an item |
| `/hamal alias word Name` | one-word shortcut for To: |
| `/hamal list` | bank alts and their rules |
| `/hamal preview Name` | what would be sent now |
| `/hamal send Name` | fill the mail (at a mailbox) |
| `/hamal auto on\|off` | fill the mail when you type a bank alt's name |
| `/hamal chain on\|off` | send every batch with one click |

`/ham` works as a short form of `/hamal`.

## Development

```
lua tests/run.lua        # offline tests (Lua 5.1 or newer)
luacheck .               # lint
```

To try it in the game, link the repository into the AddOns folder:

```
ln -s "$PWD" "/Applications/World of Warcraft/_forever_/Interface/AddOns/Hamal"
```

Then `/reload` in the game after each change.

Releases are packaged by the BigWigs packager when a `v*` tag is pushed (see `.github/workflows/release.yml`).
