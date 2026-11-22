# Disclaimer

Please read this before you install or run justcode. By using justcode you accept the points below. They add to, and do not replace, the [MIT License](LICENSE), which governs the software.

## 1. No warranty
justcode is provided **"as is"**, without warranty of any kind, express or implied, including merchantability, fitness for a particular purpose and non-infringement. The authors and contributors are not liable for any claim, damage or loss arising from its use, including lost data, lost work time, wrong time entries, failed or unintended merges, broken builds, rejected uploads, account suspension or exposed credentials.

## 2. You are responsible for every action
justcode acts on your accounts with your tokens. It can push branches, open and change pull requests, enable auto-merge, change ticket status, create tickets, write time entries, upload builds and post messages to your team.
- Run every command with `-n` (dry run) first and read the output. A dry run shows what justcode *would* do; it cannot guarantee how a remote service will respond to the real call.
- When Claude runs justcode for you, it asks before every real run. **Your approval is your decision.** Claude can be wrong; review what it proposes as you would review a colleague's change.
- Check your own organisation's policies before automating time entries, ticket workflows, merges or releases. Some teams require these steps to be done by hand.

## 3. Third-party services
justcode talks to services such as GitHub, GitLab, Bitbucket, Jira, Linear, Tempo, Toggl Track, Clockify, Apple App Store Connect, Google Play, Slack and Microsoft Teams through their public APIs.
- justcode is **not affiliated with, endorsed by or sponsored by** any of these companies. All product names, logos and trademarks belong to their owners and are used only to describe compatibility.
- Your use of each service is governed by **its** terms, API policies and rate limits. You are responsible for complying with them, and for any cost they charge.
- APIs change. A provider that works today may break after a vendor update. justcode's tests run against a local mock server, not against the real services.

## 4. Credentials and data
- Secrets are read only from your OS secret store (macOS Keychain, libsecret on Linux) and are passed to curl on stdin, never on the command line. justcode does not send your data anywhere except the services you configure.
- You choose which tokens you create and which scopes they get. **Use the narrowest scopes that work**, and revoke tokens you no longer use.
- Messages you configure (Slack, Teams, webhooks, clipboard) may contain branch names, ticket keys, titles and links. Make sure that is acceptable in the channel you post to.
- justcode does not collect telemetry.

## 5. Repository config and custom commands run code
`.justcode`, `.justcode.local`, hooks and custom commands are shell code that runs on your machine with your permissions. justcode loads repo files and team commands only after you trust them with `justcode trust`, and asks again whenever they change. **Trusting a file means you have read it and accept what it does.** Do not trust files from repositories you do not control or understand.

## 6. Builds and releases
`build` drives your own toolchain (Xcode, Gradle, fastlane or your own command) with your signing setup. justcode does not sign, review or test your app, and gives no guarantee that a build is accepted by App Store Connect, Google Play or any other store. Claude never runs a real build or upload; you do.

## 7. Network and VPN presets
The VPN presets in `references/network.md` are examples built from each vendor's public CLI. They are **not tested against your client version**; verify every command on your machine before you use it. justcode never stores VPN passwords or one-time codes.

## 8. Not professional advice
Nothing in justcode or its documentation is legal, security, compliance or HR advice, including anything about time tracking or working hours.

## 9. Reporting problems
Report bugs and security issues through the repository's issue tracker. For a security issue, do not include tokens, logs with secrets or private company data in a public issue; describe the problem and ask for a private channel.
