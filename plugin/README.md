# i-just-want-to-code

The Claude skill for **justcode**: one command per workflow step. `ship` opens the pull request with reviewers, moves the ticket, logs the time and posts to the team. `tpull` pulls safely. `tlog` and `tcheck` handle timesheets. `ticket` files tickets from a draft. `build` builds and distributes. `vpn` waits for the VPN.

This plugin contains only the skill: the setup interview, the approval rules for daily use, the config reference and the provider contracts. The shell runtime is installed separately from the project repository, so you can read it before running it. See the install section: https://github.com/yusasarisoy/i-just-want-to-code#-install

Every command has `-n` (a dry run: all reads, no writes). Repo config loads only after you trust it, and secrets stay in the OS keychain.

License: MIT. See `LICENSE` and the project's `DISCLAIMER.md`.
