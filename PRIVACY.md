# Privacy

i-just-want-to-code (the plugin) and justcode (its shell runtime) collect nothing. There is no analytics, no telemetry and no server run by this project.

## What runs where

- Everything runs on your machine, as you, when you run a command or ask Claude to.
- Config lives in `~/.config/justcode/` and in the repo files you choose to trust (`.justcode`, `.justcode.local`).
- Tokens and webhook URLs stay in your OS keychain (macOS Keychain or libsecret). justcode reads them only when a step needs them and never prints, logs or writes them.

## What leaves your machine

When you let Claude install or update the runtime, it downloads the matching release from this project's public GitHub repository; nothing is sent besides that request.

Otherwise, only the requests you configure, sent straight to the services you configured:

- your code host (GitHub, GitLab, Bitbucket or your own server)
- your tracker and time tracker (Jira, Linear, Tempo, Toggl, Clockify)
- your build distribution (TestFlight, Google Play or your own command)
- your chat (Slack, Teams or a webhook)

Each token goes only to the service it belongs to, in a request header passed on stdin, never on the command line. Every command has `-n` (dry run), which shows what would be sent and sends nothing.

What those services do with your data is governed by their own privacy policies.

## Claude

When you use the plugin in Claude, Claude sees the command output you let it run, under your Claude account's terms. The skill tells Claude never to read, print or store secret values.

## Contact

Questions or concerns: open an issue at https://github.com/yusasarisoy/i-just-want-to-code/issues
