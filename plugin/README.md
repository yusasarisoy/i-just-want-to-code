# i-just-want-to-code

The Claude skill for **justcode**: one command per workflow step. `ship` opens the pull request with reviewers, moves the ticket, logs the time and posts to the team. `tpull` pulls safely. `tlog` and `tcheck` handle timesheets. `ticket` files tickets from a draft. `build` builds and distributes. `vpn` waits for the VPN.

This plugin contains only the skill: the setup interview, the approval rules for daily use, the config reference and the provider contracts. The shell runtime comes from the project repository's release that matches this plugin's version: ask Claude to "set up justcode" and it fetches that release, shows what the installer would do and installs only after you say yes. To install it yourself, see https://github.com/yusasarisoy/i-just-want-to-code#-install

Example prompts:

- "set up justcode for this repo"
- "ship this branch as a draft, reviewer bob, dry run first"
- "log 9-10 today on ABC-123"
- "how many hours am I missing this week?"
- "create the tickets in draft.md as Tasks"
- "add a command that opens a deploy preview"

Every command has `-n` (a dry run: all reads, no writes). Repo config loads only after you trust it, and secrets stay in the OS keychain.

License: MIT. See `LICENSE` and the project's `DISCLAIMER.md`.
