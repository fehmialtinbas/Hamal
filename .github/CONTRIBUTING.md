# Contributing to Hamal

Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Open an issue with the bug report form. The most useful things are the lines `/hamal status` prints
at the mailbox (a screenshot is fine) and any Lua error the game showed.

## Pull requests

- Run the tests and the linter first. CI runs both on Lua 5.1 for every push and pull request.

  ```
  lua tests/run.lua
  luacheck .
  ```

- Add a test for what you change. The tests run against a fake game client
  (`tests/mock_wow.lua`), so you don't need the game to run them.
- Keep a pull request to one change, and say in it what you tried in the game.

## Rules Hamal keeps

Every change has to keep these four. A pull request that breaks one can't be merged.

1. **Items only reach your own characters.** Hamal mails only this account's characters that it
   has seen on the same realm and region (`Characters.CanMail`, checked again by `Mailer.VerifiedRecipient`
   right before a mail goes out). There is no way to type in someone else's name, and nothing is
   mailed while the realm is unknown.
2. **Blizzard's rules.** Official API only. When the game blocks something, Hamal falls back to a
   click per mail instead of working around it. No network, no addon or chat messages, nothing in
   combat, no obfuscated code. Hamal stays free and asks for nothing inside the game: no ads, no
   donation requests.
3. **It stands alone.** No libraries or dependencies, and it never reads another addon's data.
4. **No load on the game, no nagging.** No constant `OnUpdate`, nothing on busy events away from the
   mailbox, no bulk item queries, no chat at login, and errors go through `ns.Safely`.
   `tests/spec_quiet.lua` checks this.
