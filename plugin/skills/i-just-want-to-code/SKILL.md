---
name: i-just-want-to-code
description: Use to set up, run, change or extend justcode (the i-just-want-to-code plugin), one command per engineering chore - ship (PR, reviewers, ticket, time, message), tpull, tlog, tcheck (and --fill), ticket, standup, release-notes, nudge, build, vpn - or when a workflow command is missing. Covers setup, approval rules, config layers, trust, custom commands and providers.
---

# i-just-want-to-code

## 1. What it is

The plugin teaches Claude to drive **justcode**: shell commands (zsh, git and jq) that run a whole workflow step with one call. Every step prints one line: `✓` done, `•` skipped, `✗` failed. Every command has `-n` (dry run: all reads, zero writes) and `-h`.

| command | does |
|---|---|
| `ship` | push, find or open the PR/MR, title, description, reviewers, draft or auto-merge, CI nudge, ticket status, time log, team message |
| `tpull` | fetch and fast-forward; on divergence recommends rebase or merge and asks |
| `tlog` | log or move a time entry (`9-10`, `09:30-12:00`), overlap-checked |
| `tcheck` | weekly time check against `DAY_TARGET_HOURS`; `--fill` proposes entries for short days from your commits and logs them with tlog |
| `ticket` | create tickets from a draft file (fields by screen name, estimates, sprint, epic) |
| `build` | build a clean worktree, upload (TestFlight, Play, any command), post the message |
| `standup` | Yesterday / Today / Blockers from a day's time logs, commits and PRs, and your in-progress tickets |
| `release-notes` | markdown notes for `<from> [to]`: ticket keys from commits and PRs, grouped by ticket type |
| `nudge` | one message to the reviewers your open PRs have waited on for `NUDGE_AFTER_HOURS` |
| `vpn` | status, up, down, re, watch |
| `justcode` | setup, config, doctor, trust, untrust, edit, files, command, run, agent, selfcheck, version |
| `justcode-post` | send stdin to clipboard, Slack, Teams or a webhook |

**Everything is configurable.** No value, step, hook or message is hard-coded; every behaviour is a key in `references/config.md` with a neutral default. Org-specific behaviour is an optional key, off by default. Templates belong to the user: unset keeps the default, empty leaves that part out (`references/messages.md`).

**Layers** (later wins): `~/.config/justcode/config` (personal) → `<repo>/.justcode` (team, committed) → `<repo>/.justcode.local` (personal per repo, git-ignored) → `JUSTCODE_SET='K=v;K2=v'` (one run, single values only) → flags.

**Trust:** repo files and team commands load only when their sha256 is in `~/.config/justcode/trusted` (`justcode trust` shows content and diff, asks y/N). A changed file is untrusted again. Untrusted means the layer is skipped with one `•` line, never sourced.

### 1.1 Runtime check (every request, once per session)

The plugin ships only this skill; the runtime is the release of the project repository whose tag matches the plugin version. Before the first justcode step in a session:

- **Values.** Plugin version: `.version` in `<this skill's base directory>/../../.claude-plugin/plugin.json`. Release tag: `v<version>`. Repository: `https://github.com/yusasarisoy/i-just-want-to-code.git`. Managed source: `${JUSTCODE_PREFIX:-$HOME/.local}/share/justcode-src`. Quote every path.
- **Look.** `command -v justcode`, then `justcode version` (prints `justcode <version>`).
- **Not installed.** Say what will happen: a shallow copy of the repository at the release tag goes into the managed source, then its installer shows its plan. Ask. Only after a yes: `git clone --depth 1 --branch v<version> <repository> "<managed source>"`. Then `zsh "<managed source>/runtime/install.sh" -n`, summarise its lines and ask again. Only after that second yes: `zsh "<managed source>/runtime/install.sh"`, without `-y`.
- **Older than the plugin, managed source exists.** Offer the update the same way: on a yes, `git -C "<managed source>" fetch --depth 1 origin tag v<version>` and `git -C "<managed source>" checkout -q v<version>`, then the installer's `-n`, a second yes, the real run. A no means the update is not offered again in this session.
- **Older, no managed source.** The runtime came from the user's own clone. Say it is older than the plugin and that it updates with `git pull` and `zsh runtime/install.sh` in that clone. Do not reinstall it.
- **Tag not found** (clone or fetch fails on it). Say the matching release is not published yet and stop; never fall back to another branch or tag.
- **Same or newer.** Nothing to do.
- **After an install run.** For each `• kept <path> (justcode's <name> not linked)` line: show what that file is (`ls -l`, and the first lines when it is a script) and ask about that one file; only after its own yes, `ln -sf "<install dir>/bin/<name>" "<path>"`. For `• add <dir> to your PATH`: show the exact line `export PATH="<dir>:$PATH"` and the startup file (`~/.zshrc` for zsh, `~/.bashrc` for bash); append it only after a yes; on a no, use full paths for the rest of the session.

## 2. Setup

### 2.1 Detect silently
Find out without asking: OS and shell; `git remote get-url origin` → code host (`github.com`, `gitlab.*`, `bitbucket.org`) and API URL; recent branch names → ticket key regex and prefix (`feature/ABC-123-login` → `ABC`); installed CLIs (`gh`, `xcodebuild`, `gradle`, `fastlane`, `warp-cli`, `tailscale`, `fzf`); `*.xcworkspace`, `*.xcodeproj`, `build.gradle`; existing `~/.config/justcode/config`, `.justcode`, `.justcode.local` (`justcode config` if installed); connected Claude connectors (tracker, chat) that can answer read-only questions such as project keys or status names.

### 2.2 Interview
- Ask with **AskUserQuestion** (clickable cards). Only when that tool is unavailable (headless), ask one short numbered plain-text list.
- At most **3 rounds**, up to 4 questions each, grouped by layer:
  1. commands they want + code host
  2. tracker + time tracker
  3. build/distribution + network/VPN + messages
- Skip a question whose answer was detected and say so in one line instead: `Code host: GitHub (from the remote)`.
- Only ask for the commands the user picked (no tracker questions if they skip `ticket` and ship's ticket step, etc.).
- Fixed-choice questions list the known providers plus `None / I don't use this`; the user can always type Other. A tool with no provider → §3.
- Put the detected or recommended option first, labelled `(Recommended)`.
- Message templates (ship, build, ticket), in round 3:
  - offer 2–3 ready templates from `references/messages.md` (neutral wording, documented placeholders);
  - show a live preview filled with this user's real branch, PR title and ticket key;
  - ask the target as a **multi-select**: clipboard, Slack, Teams, webhook, none.
- After the rounds, ask all free-text values **once, together** (URLs, account names, project keys, reviewers), each with the detected or guessed default.
- Never ask for a secret value. Ask only the secret-store entry name and suggest a default (`justcode-code-token`).

Example round 1:
- "Which justcode commands do you want?" (multi) ship, tpull, tlog + tcheck, ticket, standup, release-notes, nudge, build, vpn
- "Code host?" GitHub (Recommended, from the remote), GitLab, Bitbucket, None
- "How should ship finish?" Ask me every time (Recommended), Auto-merge by default, Draft by default
- "Default reviewers?" None, Type names

### 2.3 Show the plan
Before writing anything show, in one message: the files to create or change; the full resulting config, **personal and team layers separately**, with a comment per key; what each step does on their stack (e.g. "ship: push → GitHub PR → reviewers bob → Jira ABC-123 to In Review → Tempo 1h → Slack"). Then one yes/no question.

### 2.4 Write on approval
1. The runtime is installed by §1.1. If the user declined there, point them to the install section, https://github.com/yusasarisoy/i-just-want-to-code#-install, and wait until `justcode version` works.
2. Write the config files. Personal keys (`*_SECRET`, `CODE_USER`, `TRACKER_USER`, `TIME_USER`, `REPO_DIR`) never go into `.justcode`.
3. For `.justcode.local`, add it to `.gitignore`.

The user can also run `justcode setup` in a terminal (same questions, no Claude) and `justcode setup <section>` later.

### 2.5 Secrets
For each missing secret, show the user the store command that `justcode doctor` prints for their OS and let them run it themselves; the OS keychain prompts for the value.

`CODE_TOKEN_SECRET=gh` reuses the GitHub CLI login. Never read, echo or store the value yourself.

### 2.6 Verify
Run `justcode doctor`, then every chosen command with `-n` (`ship -n`, `tpull -n`, `tlog -n ABC-1 9-10`, `tcheck --fill -n`, `ticket -n -t Task draft.md`, `standup -n`, `release-notes -n <last-tag>`, `nudge -n`, `build -n test`). Show a table: command, result (✓/•/✗), what to fix. Fix config problems before finishing.

### 2.7 Team config exists
If a trusted or untrusted `.justcode` is already in the repo: ask only for personal keys. Tell the user to review the file and run `justcode trust` themselves; never trust a file on their behalf.

## 3. Adding a tool that has no provider

1. Read the contract in the matching references file (`code-hosts.md`, `trackers.md`, `time-tracking.md`, `distribution.md`, `messages.md`, `network.md`).
2. In a clone of the project repository, write `runtime/providers/<layer>/<tool>.zsh`: only the contract functions plus `<layer>_doctor`; network through `df_http`, secrets through `df_secret`; unsupported capabilities call `df_unsupported` and return 3.
3. If the user wants to contribute it: add routes to `tests/mock/server.py` and a persona test in `tests/personas/`.
4. Run `zsh tests/run.zsh` and `scripts/leakcheck.sh`; then `justcode doctor` and the commands with `-n`.

Files added by hand inside the installed runtime (`~/.local/share/justcode`) are replaced on the next install or update; providers belong in a clone.

## 4. Custom commands

When the user asks for a command justcode does not have, offer to create it as a custom command:
1. `justcode command new <name>` (personal, `~/.config/justcode/commands/<name>`) or `--team` (`<repo>/.justcode-commands/<name>`).
2. Fill in the steps in the skeleton: reads and writes through `df_http`, settings from `<NAME>_*` keys, writes guarded by `DF_DRY`, `df_hook PRE`/`POST`.
3. `justcode command check <name>` until clean.
4. `justcode run <name> -n` and show the output.
5. Only then offer the real run, with the approval rules in §5.

Contract: `-n` and `-h`; ✓/•/✗ lines; exit 1 if any step failed; safe to re-run; lib API only (`df_http`, `df_secret`, `df_wait_for_host`, `df_fill`, `df_step_off`, `df_hook`); no raw network calls, no dynamic code evaluation, no direct secret reads (`justcode command check` enforces this); English messages. Built-in names cannot be shadowed. A team command wins over a personal one only when trusted.

**Before writing a team command, always tell the user that every teammate has to review it and run `justcode trust` before it runs for them.**

## 5. Daily use rules

- **ship:** ask in **one** AskUserQuestion turn for: time range or duration (or none), PR title (offer the current one), auto-merge (**ask every time**; never carry over an earlier answer), draft. Then dry run.
- **Always `-n` first.** Summarise the dry run: target branch, PR, reviewers, ticket transition, time log, message and targets. Run for real only after an explicit go for that exact command. Approval never carries over to the next run, another branch or changed flags.
- **Stop on unexpected dry-run output** (wrong target, wrong account, wrong ticket, a `✗`): say what is off and do not offer the real run until it is resolved.
- **build:** Claude prints the command (`build -k qa test 1.2.3 14`); the user runs it. Claude never runs a real build or upload. `build -n` is fine.
- **tpull divergence:** relay justcode's recommendation (rebase or merge) and the reason, and let the user choose.
- **tlog:** times are local; show the resulting day total from the dry run.
- **ticket:** dry run resolves every field; show it before creating anything.
- **standup:** ask for blockers (or none) in one turn, run `standup -n`, show the message and its targets; send with `standup` only after a go for that message.
- **tcheck --fill:** run `tcheck --fill -n`, show the proposals as a table (day, range, ticket, commits); after an explicit go, `tcheck --fill -y`. If the real run's list would differ from the one approved (new commits or entries), show it again and ask again.
- **release-notes:** `release-notes -n <from> [to]`, show the markdown; writing a file (`-o`) and sending to `RELEASE_NOTES_POST_TO` need a go.
- **nudge:** run `nudge -n`, show the exact message, the reviewers and the target; send with `nudge -y` only after an explicit go for that message. Never nudge on the user's behalf unasked.
- **Read-only lookups** (ticket status, sprint names, field values) may use connected Claude connectors. **Writes always go through the justcode commands.**
- Reply in the user's language; justcode's own output stays English.

## 6. Changing things

- **A value** (reviewer, template, status name) → set the key in the right layer: personal → global or `.justcode.local`; shared with the team → `.justcode` (then everyone runs `justcode trust`). `justcode setup <section>` or `justcode edit global|team|local`.
- **A tool** (Jira → Linear, Slack → Teams) → change the `*_PROVIDER` key; nothing else changes.
- **New behaviour** → a new key with a neutral default that keeps today's behaviour, documented in `references/config.md` and `config.example`. Never hard-code org values.
- `justcode config` shows every effective value and which file it came from.

## 7. Contract and safety rules

- Config files are zsh source loaded at the lib's top level. Repo layers and team commands only when trusted; untrusted → one `• <path> is not trusted; review it, then run: justcode trust` line and continue without it.
- Hooks only from trusted layers; each runs in its own shell in the repo root. `JUSTCODE_SET` refuses hooks, commands, arrays and maps. Config values are never evaluated as code.
- Secrets: only through `df_secret <name>`; never in a process argument list (HTTP headers go on stdin); never printed, logged or written. `justcode config` shows only entry names; `justcode doctor` prints the store command, never asks for the value.
- Dry run (`-n`) does every read and zero writes; each write it would make prints a `[dry-run]` line.
- Fail closed: a failed tracker search, an unknown account (`CODE_USER` mismatch) or an unreachable host stops the command before any write.
- `code_auto_merge` never merges: when the PR would merge immediately or the state is unknown it skips (`•`).
- Network waits are bounded by `NETWORK_WAIT_SECS`; nothing hangs.
- Status lines go to stderr, data to stdout. Exit 1 if any step failed. Every command is safe to re-run.
- Claude never commits, pushes or trusts files for the user unless asked for that exact action.
