# Security

If you find a way Hamal could mail items to someone other than your own characters, or any
other security problem, please report it privately instead of in a public issue:
**Security > Report a vulnerability** on this repository.

What Hamal does and doesn't do, so you know what to look for:

- It mails only characters of your own account that it has seen log in on the same realm and
  region, and checks the recipient again right before every mail.
- It never sends money or C.O.D., never takes anything from your inbox, and has no add-by-name.
- It uses no network, no addon or chat messages, no libraries, and runs no code from text
  (`loadstring` and the like).
- Its saved data (`HamalDB`) holds your settings and character list only, no secrets.
