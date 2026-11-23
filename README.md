# Hamal

*Hamal* is Turkish for "porter": someone who carries other people's loads. This addon carries your
materials to your bank alts.

Open a mailbox and type your bank alt's name in **To:** (or click it in the Hamal panel). Hamal fills
the mail with everything in your bags that belongs to that alt. One click on **Send** mails it all,
12 items per mail, batch after batch.

Built for **World of Warcraft: Forever** (1.60.1, interface 16001).

> Status: early. The mailing flow is covered by offline tests against a fake client but has not
> been tried in the game yet.

## Setup

```
/hamal add Vault Keeper                    -- your bank alt's full name
/hamal cat Vault Keeper cloth leather herb  -- item types it collects (/hamal cats lists them)
/hamal item Vault Keeper [shift-click item] -- one specific item, always
/hamal alias vk Vault Keeper               -- typing "vk" in To: means Vault Keeper
/hamal preview vault                       -- what would be sent right now
```

Names can be shortened in commands as long as they stay unique (`vault` instead of `Vault Keeper`).
With a single bank alt you can leave the name out.

## At the mailbox

1. Open the **Send Mail** tab. The Hamal panel next to it lists your bank alts and how many stacks are waiting for each.
2. Type a bank alt's full name or alias in **To:**, or click its button. Hamal attaches the first 12 stacks.
3. Press **Send mail 1/N** (Hamal's button or the game's own Send). Hamal sends the remaining batches one after another.

If the game insists on a click for every mail, Hamal notices, turns chaining off and lets you press
Send once per batch. `/hamal chain on` tries chaining again.

Writing to someone else after Hamal filled the mail? Change the name in **To:** and Hamal takes its items back out.

## What is never sent

- Soulbound, quest and locked items
- Hearthstone, Thieves' Tools and profession tools (mining pick, skinning knife, hammer, rods, ...)
- Anything on your exclude list: `/hamal exclude [item]`

If two bank alts want the same item, a specific item rule beats an item-type rule. Between equal
rules, the alphabetically first bank alt gets it.

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
