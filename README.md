![i-just-want-to-code icon: a smiling face with headphones, in focus mode](assets/icon.png)

# i-just-want-to-code

**Ship, log, ticket, build: one command each. No Jira tabs needed!**

The busywork around your code (pull requests, ticket status, timesheets, builds, team posts) done by **justcode**, on your stack, with your tools. Claude sets it up for you; every value, step, hook and message is configurable.

`ship` · `tpull` · `tlog` · `tcheck` · `ticket` · `build` · `vpn`

---

## 😮‍💨 Before / after

> **Before:** push, open the code host, create the PR, paste the title, add reviewers, flip auto-merge, open the tracker, move the ticket, open the timesheet, log an hour, copy the link, paste it in the team channel. Seven tabs, four copy-pastes, one forgotten timesheet.

> **After:** `ship -l 9-10 -a`


## ✨ What one `ship` does

```mermaid
flowchart LR
    A([ship]) --> B[push branch]
    B --> C[find or open<br>PR / MR]
    C --> D[title, description,<br>labels, reviewers]
    D --> E{draft?}
    E -- no --> F[auto-merge<br>if asked]
    E -- yes --> G[stay draft]
    F --> H[ticket →<br>In Review]
    G --> I
    H --> I[log time]
    I --> J[post message<br>Slack · Teams · clipboard]
```

Always look first. `-n` does every read and **zero writes**:

```console
$ ship -n -l 9-10 -a
✓ signed in as alice
✓ target main
[dry-run] git push -u origin feature/ABC-123-login
[dry-run] create pull request feature/ABC-123-login -> main: "Add login screen"
[dry-run] set description (only if empty) and labels: mobile
[dry-run] request reviewers: bob
[dry-run] enable auto-merge (squash) when checks pass
[dry-run] move ABC-123: 'In Progress' -> 'In Review'
• time: not logged (no time tracker)
[dry-run] post to slack: <new pull request>
```

One line per step: **✓** done · **•** skipped · **✗** failed. Exit 1 if anything failed, and every command is safe to re-run.

## 🧰 Commands

| | command | what it does |
|---|---|---|
| 🚀 | `ship` | push, PR/MR, reviewers, draft or auto-merge, CI nudge, ticket status, time log, team message |
| ⬇️ | `tpull` | fetch and fast-forward; on divergence recommends rebase or merge and lets you choose |
| ⏱️ | `tlog` | log or move a time entry: `tlog ABC-123 9-10`, `tlog 42 09:30-12:00 yesterday` |
| 📅 | `tcheck` | every day this week (or back `-w N` weeks) against your daily target |
| 🎫 | `ticket` | create tickets from a draft file, fields by their screen names |
| 📦 | `build` | build a clean worktree, upload, post "build uploaded" |
| 🔐 | `vpn` | `status` · `up` · `down` · `re` · `watch` |
| ⚙️ | `justcode` | `setup` · `config` · `doctor` · `trust` · `edit` · `command` · `run` · … |
| 💬 | `justcode-post` | send any text to clipboard, Slack, Teams or a webhook |

Every command takes `-n` (dry run) and `-h` (help).

## 📥 Install

Two parts: the **plugin** (the skill that teaches Claude justcode) and the **runtime** (the shell commands). Needs `zsh`, `git`, `curl` and `jq`. macOS and Linux (WSL works too).

**1. Plugin, in Claude Code**

```text
/plugin marketplace add yusasarisoy/i-just-want-to-code
/plugin install i-just-want-to-code@i-just-want-to-code
```

**Claude app:** from the plugin directory, once i-just-want-to-code is listed there.

**2. Runtime.** Clone the repo, read `runtime/install.sh` if you like, then run it (`-n` first shows what it would do):

```bash
git clone https://github.com/yusasarisoy/i-just-want-to-code.git
cd i-just-want-to-code
zsh runtime/install.sh -n
zsh runtime/install.sh
```

It copies the runtime to `~/.local/share/justcode`, links the commands into `~/.local/bin` and asks before overwriting anything. To update: `git pull`, then run it again.

## ⚡ Quick start

Ask Claude:

> set up justcode

Claude detects your remote, branch naming and tools, asks at most three rounds of clickable questions, shows the plan and the full config, and writes nothing until you say yes. Then it runs `justcode doctor` and every command with `-n` so you see it work.

### Example prompts

| Ask Claude | What happens |
|---|---|
| "set up justcode for this repo" | Detects your stack, asks up to three rounds of questions, shows the config, writes it on your yes, then runs `justcode doctor` |
| "ship this branch as a draft, reviewer bob, dry run first" | Runs `ship -n` and shows every planned step; runs `ship` only after you approve |
| "log 9-10 today on ABC-123" | Runs `tlog -n ABC-123 9-10`, checks for overlaps, then logs it on your yes |
| "how many hours am I missing this week?" | Runs `tcheck` and lists the days under your daily target |
| "create the tickets in draft.md as Tasks" | Runs `ticket -n -t Task draft.md`, shows each ticket, creates them on your yes |
| "add a command that opens a deploy preview" | Creates a custom command skeleton with `-n` and `-h`, checks it, and runs it as a dry run |

## 🛠️ Configure

Three ways, pick one:

1. **Ask Claude** to set up justcode (or to change one thing: "ship should post to Teams").
2. **`justcode setup`** in a terminal: the same questions without Claude. `justcode setup messages` re-runs one section; `--layer team` writes the shared repo file; `-n` shows the diff only.
3. **`justcode edit global|team|local`** opens the file in `$EDITOR`. Every key is in [`references/config.md`](plugin/skills/i-just-want-to-code/references/config.md).

- `justcode config` shows every effective value and which file it came from.
- `justcode trust` reviews and trusts the repo's `.justcode`, `.justcode.local` and team commands.

```text
~/.config/justcode/config      personal, all repos
<repo>/.justcode               team, committed          🔒 needs trust
<repo>/.justcode.local         personal, git-ignored    🔒 needs trust
JUSTCODE_SET='K=v;K2=v'        one run, single values
command flags                 wins
```

## 🎛️ Make it yours

Turn off what you don't use, add what you need:

| you want | set |
|---|---|
| skip ship steps | `SHIP_SKIP=(description reviewers ci ticket time)`, any subset |
| no tracker / no time tracker | `TRACKER_PROVIDER=none` / `TIME_PROVIDER=none` |
| no team message | `SHIP_POST_TO=none` (also `BUILD_POST_TO`, `TICKET_POST_TO`) |
| auto-merge or draft by default | `SHIP_DEFAULT_ARGS=(-a)` or `(-D)`; `-A` turns it off for one run |
| your own step before or after | `SHIP_PRE_HOOK='make lint'`, `SHIP_POST_HOOK='...'` (same for every command) |
| a whole new flow | a custom command (below) |

The core of each command stays on: `ship` always checks the account, pushes and opens or updates the PR, because without them there is nothing to ship.

## 👥 Teams

1. Commit a `.justcode` with the shared settings (target branches, reviewers, status names, message templates). Personal keys such as `CODE_USER` and secret names never go in it; `justcode setup --layer team` moves them to your own file for you.
2. Everyone runs `justcode trust` once, after reading it. When the file changes, it is untrusted again until reviewed.
3. Shared scripts go in `.justcode-commands/`; they are trusted per file in the same way.

## 🛡️ Safety

| | |
|---|---|
| 🧪 **Dry run** | `-n` reads everything and writes nothing; Claude always shows it before the real run and asks again for every run. |
| 🔒 **Trust** | repo files are sourced only when their sha256 is trusted (the direnv model); untrusted files are skipped, never executed. |
| 🔑 **Secrets** | read only from the macOS Keychain or libsecret, passed to curl on stdin, never in argv, logs or output. justcode never asks for a value. |
| 🧱 **Fail closed** | a wrong account, a failed ticket search or an unreachable host stops the command before any write. |
| 🤝 **No surprise merges** | auto-merge is only set when the PR would wait for checks; it never merges by itself. |
| ⏳ **No hangs** | VPN waits are bounded (`NETWORK_WAIT_SECS`). |
| 👤 **You build** | Claude prints `build` commands; you run them. |

## 🔌 Supported tools

| layer | built in | via config |
|---|---|---|
| Code host | GitHub (incl. Enterprise) · GitLab (incl. self-hosted) · Bitbucket Cloud | |
| Tracker | Jira Cloud · Jira Data Center · Linear | none |
| Time | Tempo Cloud · Tempo DC · Toggl Track · Clockify | none |
| Build | TestFlight · Google Play | any command (e.g. Firebase App Distribution) · none |
| Messages | clipboard (rich) · Slack · Microsoft Teams · webhook | none |
| VPN | any client with a CLI or an app | presets in [`network.md`](plugin/skills/i-just-want-to-code/references/network.md) |

Not listed? Ask Claude to add a provider, or write one yourself (below).

## 🧩 Custom commands

Need `deploy-preview` or `release-notes`? Make it a justcode command:

```console
$ justcode command new deploy-preview     # skeleton with -n, -h, hooks, dry-run guards
$ justcode command check deploy-preview   # static check: no curl, eval or raw secret reads
$ justcode run deploy-preview -n
```

Personal commands live in `~/.config/justcode/commands/`; team commands in `<repo>/.justcode-commands/` and run only after `justcode trust`. Built-in names cannot be shadowed. `justcode doctor` checks them all.

## 🤲 Contributing a provider

1. Read the contract in `plugin/skills/i-just-want-to-code/references/<layer>.md` (code-hosts, trackers, time-tracking, distribution, messages).
2. Add `runtime/providers/<layer>/<tool>.zsh`: only the contract functions plus `<layer>_doctor`; network via `df_http`, secrets via `df_secret`; unsupported → return 3.
3. Add routes to `tests/mock/server.py` and a persona in `tests/personas/`.
4. Run the checks:

```bash
zsh tests/run.zsh
```

```bash
scripts/leakcheck.sh
```

Tests run against a local mock server only: no real APIs, no real secrets.

## ⚠️ Disclaimer

justcode acts on your real accounts: it can push, merge, change tickets, log time, upload builds and post to your team. It comes **as is, with no warranty**; you are responsible for every run you approve, so read the `-n` output first. justcode is not affiliated with or endorsed by GitHub, GitLab, Atlassian, Linear, Tempo, Toggl, Clockify, Apple, Google, Slack, Microsoft or any other vendor; their names and trademarks belong to their owners. Your use of each service follows its own terms and rate limits. Full text: [DISCLAIMER.md](DISCLAIMER.md).

## 📄 License

[MIT](LICENSE)
