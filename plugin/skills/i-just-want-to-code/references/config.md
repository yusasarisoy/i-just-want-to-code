# Configuration keys

Config files are zsh source. Layers, later wins:

1. `~/.config/justcode/config`: personal and global
2. `<repo>/.justcode`: team, committed, loaded only if trusted (`justcode trust`)
3. `<repo>/.justcode.local`: personal per repo, git-ignored, also needs trust
4. `JUSTCODE_SET='KEY=value;KEY2=value'`: one run only; single values only (no arrays, maps, hooks or commands)
5. command flags

`<repo>` is the git top level of the current directory, else `REPO_DIR`.

**Templates are yours.** Every message and line template is a key: read it with `justcode config`, change it with `justcode edit`. A template you never set keeps the default shown here; for the standup, release-notes, nudge and tcheck --fill templates, a template set to empty leaves that part out (an empty line template drops those lines, an empty message sends nothing). `SHIP_MESSAGE`, `BUILD_MESSAGE` and `TICKET_MESSAGE` fall back to their default when empty; turn their message off with `<CMD>_POST_TO=none`.

Columns: **wizard** is the `justcode setup` section that asks the key (`-` = edit by hand). **personal** keys are never allowed in the team layer; the wizard moves them to the global file with a warning. The last column is also the one-line help that `?` prints in the wizard, so keep it on one line.

## General

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `REPO_DIR` | path | empty | - | yes | all | Repository used when a command runs outside a git checkout |
| `TICKET_KEY_REGEX` | regex | `[A-Za-z][A-Za-z0-9]+-[0-9]+` | - | | ship, tlog, build | Ticket key pattern in branch names; matched case-insensitively and upper-cased |
| `TICKET_PREFIX` | string | empty | tracker | | ship, tlog, ticket, build | A bare number on the command line becomes PREFIX-number, e.g. 42 becomes ABC-42 |
| `DEFAULT_START` | HH:MM | `09:00` | commands | | ship, tlog | Start time of a duration log on a day with no entries yet |
| `JUSTCODE_NOTIFY` | 0/1 | `1` | - | | all | Desktop notification when a command finishes |
| `JUSTCODE_SOUNDS` | 0/1 | `1` | - | | all | Sound with the notification (macOS) |
| `NETWORK_WAIT_SECS` | int | `120` | - | | all network commands | Longest wait for a VPN-only host before the command stops |
| `JUSTCODE_COMMANDS` | array | all built-ins | commands | | setup, Claude | Commands you use; a record for setup and Claude, every command stays installed |
| `GIT_REMOTE` | string | `origin` | - | | ship, tpull | Remote used for the code host and for pushing |
| `COMMIT_AUTHOR` | string | empty | - | yes | standup, tcheck | Author whose commits count as yours (git --author, fixed string); empty means git user.email |

## Per command

`<CMD>` is `SHIP TPULL TLOG TCHECK TICKET BUILD STANDUP RELEASE_NOTES NUDGE`, or a custom command name upper-cased with `-` turned into `_` (`deploy-preview` becomes `DEPLOY_PREVIEW`).

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `<CMD>_DEFAULT_ARGS` | array | `()` | - | | that command | Arguments put in front of every call, e.g. SHIP_DEFAULT_ARGS=(-a) |
| `<CMD>_SKIP` | array | `()` | - | | that command | Steps to skip: ship description reviewers ci ticket time; standup time commits prs today; release-notes prs tickets |
| `<CMD>_PRE_HOOK` | string | empty | - | | that command | Runs with zsh -c in the repo root before any write; a failure stops the command |
| `<CMD>_POST_HOOK` | string | empty | - | | that command | Runs with zsh -c in the repo root after success |

Hooks are read only from files you trusted; `JUSTCODE_SET` refuses them.

## Code host

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `CODE_PROVIDER` | enum | from the remote | code | | ship, doctor | github, gitlab or bitbucket |
| `CODE_API_URL` | URL | empty | code | | ship | API base URL; empty means derive it from the git remote |
| `CODE_REPO` | string | empty | - | | ship | owner/name of the repository; empty means take it from the remote |
| `CODE_USER` | string | empty | code | yes | ship, doctor | Required: your account on the code host; the token must belong to it |
| `CODE_TOKEN_SECRET` | secret name | `justcode-code-token` | code | yes | ship | Secret-store entry with the code host token; gh means use the GitHub CLI token |
| `TARGET_BRANCHES` | array | `(main)` | code | | ship | Candidate target branches; ship picks the closest one (release branches included) |
| `PROTECTED_BRANCHES` | array of globs | `(main 'release/*')` | - | | ship | ship refuses to run from these branches (and from TARGET_BRANCHES) |
| `DEFAULT_REVIEWERS` | array | `()` | code | | ship | Reviewers added to every pull request; existing reviewers are kept |
| `SHIP_LABELS` | array | `()` | - | | ship | Labels added to the pull request |
| `SHIP_PR_DESCRIPTION` | template | empty | - | | ship | Description set only when the pull request has none; placeholders as in messages.md |
| `MERGE_METHOD` | enum | `squash` | code | | ship | Auto-merge method: squash, merge or rebase |
| `CI_NUDGE_JOB` | string | empty | - | | ship | GitLab only: manual job that ship plays and cancels at once so the pipeline settles |

## Tracker

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `TRACKER_PROVIDER` | enum | `none` | tracker | | ship, ticket, build, tlog | jira-cloud, jira-dc, linear or none |
| `TRACKER_URL` | URL | empty | tracker | | tracker commands | Base URL of the tracker, e.g. https://jira.example.com |
| `TRACKER_USER` | string | empty | tracker | yes | tracker commands | Jira Cloud only: your Atlassian account email |
| `TRACKER_TOKEN_SECRET` | secret name | `justcode-tracker-token` | tracker | yes | tracker commands | Secret-store entry with the tracker token |
| `STATUS_MAP` | array of pairs | `('feature/*' 'In Review')` | - | | ship | Branch glob and the status ship moves the ticket to; first match wins |
| `STATUS_ON_SHIP` | string | `In Review` | tracker | | ship | Status used when no STATUS_MAP entry matches the branch |
| `STATUS_VIA` | string | empty | - | | ship | Intermediate status when the tracker has no direct transition |
| `STATUS_SKIP` | array | `()` | - | | ship | Statuses a ticket is never moved back from, e.g. Done |
| `TICKET_PROJECT` | string | empty | tracker | | ticket | Project key (Jira) or team key (Linear) for new tickets |
| `TICKET_BOARD` | string | empty | - | | ticket | Board id, used for sprints and estimates |
| `TICKET_DEFAULT_TYPE` | string | empty | - | | ticket | Type used when -t is not given |
| `TICKET_DEFAULT_PRIORITY` | string | empty | - | | ticket | Priority used when -p is not given |
| `TICKET_DEFAULT_COMPONENT` | string | empty | - | | ticket | Component set on every new ticket |
| `TICKET_DEFAULT_SPRINT` | string | empty | - | | ticket | Sprint name used when -s is not given; an active or future sprint on TICKET_BOARD |
| `TICKET_FIELDS` | array | `()` | - | | ticket | Field=Value items set on every new ticket, by screen name |
| `TICKET_FIELDS_<TYPE>` | array | `()` | - | | ticket | Field=Value items for one type only, e.g. TICKET_FIELDS_BUG |
| `TICKET_ESTIMATE_TYPES` | array | `()` | - | | ticket | Types that must get an estimate with -P |
| `TICKET_PREFER_CUSTOM_FIELDS` | 0/1 | `1` | - | | ticket | When a custom and a system field share a screen name, use the custom one |
| `TICKET_SEPARATOR` | string | `---8<---` | - | | ticket | Line that separates tickets in a draft file |

## Time

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `TIME_PROVIDER` | enum | `none` | time | | ship, tlog, tcheck | tempo-cloud, tempo-dc, toggl, clockify or none |
| `TIME_URL` | URL | empty | time | | time commands | API base URL override; Tempo DC uses the Jira base URL (default TRACKER_URL) |
| `TIME_USER` | string | empty | time | yes | time commands | Tempo Cloud account id, Tempo DC worker key or Clockify user id |
| `TIME_TOKEN_SECRET` | secret name | `justcode-time-token` | time | yes | time commands | Secret-store entry with the time tracker token |
| `TIME_WORKSPACE` | string | empty | time | | time commands | Toggl or Clockify workspace id |
| `DAY_TARGET_HOURS` | number | `8` | time | | tlog, tcheck | Hours a workday should reach |
| `WORK_DAYS` | array | `(1 2 3 4 5)` | - | | tcheck | Workdays, 1 is Monday |
| `TIME_TYPES` | map | `(code '' meeting '')` | - | | tlog, ship | Short type name to provider value (Tempo attribute value, Toggl tag, Clockify tag id) |
| `TIME_TYPE_ATTRIBUTE` | string | empty | - | | tlog, ship | Tempo work attribute key that holds the type; empty means none |
| `TLOG_DEFAULT_TYPE` | string | `code` | - | | tlog | Type used when -t is not given |
| `SHIP_TIME_TYPE` | string | `code` | - | | ship | Type of the time log ship writes |
| `TLOG_DEFAULT_COMMENT` | string | `Development` | - | | tlog, ship | Worklog comment when none is given |
| `TLOG_DAY_FULL_HOOK` | string | empty | - | | tlog | Runs once when the day reaches DAY_TARGET_HOURS |
| `DAY_LABELS` | array | `(Mon Tue Wed Thu Fri Sat Sun)` | - | | tcheck, standup | Day names in the weekly report and as {label} |
| `TCHECK_FILL_REPOS` | array of paths | `()` | - | | tcheck --fill | Repositories whose commits fill short days; empty means the current repository |
| `TCHECK_FILL_KEY_FROM` | array | `(branch subject)` | - | | tcheck --fill | Where a commit's ticket key comes from, first match wins: branch (the branch it was made on), subject |
| `TCHECK_FILL_LEAD_MINUTES` | int | `60` | - | | tcheck --fill | Work counted before the first commit of a session |
| `TCHECK_FILL_GAP_MINUTES` | int | `120` | - | | tcheck --fill | A longer pause between two commits of one ticket starts a new session |
| `TCHECK_FILL_ROUND_MINUTES` | int | `30` | - | | tcheck --fill | Session start is rounded down and end rounded up to this step |
| `TCHECK_FILL_MIN_MINUTES` | int | `30` | - | | tcheck --fill | Shorter proposals are dropped |
| `TCHECK_FILL_TODAY` | 0/1 | `0` | - | | tcheck --fill | 1 also proposes entries for today |
| `TCHECK_FILL_TYPE` | string | empty | - | | tcheck --fill | Type of the logged entries; empty means TLOG_DEFAULT_TYPE |
| `TCHECK_FILL_COMMENT` | string | empty | - | | tcheck --fill | Comment of the logged entries; empty means TLOG_DEFAULT_COMMENT |
| `TCHECK_FILL_LINE` | template | `{label} {start}-{end} → {key} ({commits} commits)` | - | | tcheck --fill | One line per proposal; placeholders label day start end key commits duration |

## Build

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `DEPLOY_PROVIDER` | enum | `none` | build | | build | testflight, play, command or none |
| `APP_NAME` | string | empty | build | | build | App name, used as {app} in the scheme pattern |
| `BUILD_PROJECT_DIR` | path | `.` | - | | build | Project folder relative to the repo root |
| `BUILD_OUTPUT_DIR` | path | `~/Builds` | build | | build | Folder for archives, exports and build logs |
| `BUILD_KINDS` | array | `(qa beta)` | build | | build | Allowed values for build -k; the first is the default |
| `BUILD_CONFIG` | string | `Release` | - | | build | Build configuration used when -c is not given |
| `XCODE_PROJECT` | path | empty | build | | build | Xcode project, when there is no workspace |
| `XCODE_WORKSPACE` | path | empty | build | | build | Xcode workspace |
| `XCODE_SCHEME_PATTERN` | template | `{app} {env} {config}` | build | | build | Scheme name built from {app} {env} {config} |
| `ASC_KEY_ID` | string | empty | - | | build | Optional App Store Connect API key id for uploads |
| `ASC_ISSUER_ID` | string | empty | - | | build | Optional App Store Connect issuer id |
| `ASC_KEY_PATH` | path | empty | - | | build | Optional path to the App Store Connect .p8 key |
| `GRADLE_TASK_PATTERN` | template | `:app:bundle{Env}Release` | build | | build | Gradle task built from {Env} {env} {config} {Config} |
| `PLAY_PACKAGE` | string | empty | build | | build | Android application id |
| `PLAY_TRACK` | string | `internal` | build | | build | Google Play track for uploads |
| `PLAY_JSON_KEY_SECRET` | secret name | `justcode-play-json-key` | build | yes | build | Secret-store entry with the Play service account JSON |
| `DEPLOY_COMMAND` | string | empty | build | | build | command provider: one command that builds and uploads, with JUSTCODE_* variables set |

## VPN

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `VPN_PROVIDER` | enum | `none` | network | | all network commands, vpn | command or none; presets in network.md |
| `VPN_HOSTS` | array | `()` | network | | all network commands, vpn | Hosts that need the VPN; empty with provider command means every tracker and code host |
| `VPN_STATUS_CMD` | string | empty | network | | vpn | Exits 0 when connected |
| `VPN_UP_CMD` | string | empty | network | | vpn, network wait | Connects the VPN |
| `VPN_DOWN_CMD` | string | empty | network | | vpn | Disconnects the VPN |
| `VPN_APP` | string | empty | - | | network wait | Fallback: open this app and wait for the hosts |
| `VPN_WATCH_SECS` | int | `30` | - | | vpn watch | Poll interval of vpn watch |

## Messages

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `SHIP_MESSAGE` | template | `{url}` | messages | | ship | Message after ship; placeholders url title branch target ticket ticket_url |
| `SHIP_POST_TO` | list | `clipboard` | messages | | ship | Comma list of clipboard, slack, teams, webhook or none |
| `BUILD_MESSAGE` | template | `{env} {version} ({build}) {kind} build uploaded` | messages | | build | Message after an upload; placeholders env version build kind config |
| `BUILD_POST_TO` | list | `clipboard` | messages | | build | Comma list of clipboard, slack, teams, webhook or none |
| `TICKET_MESSAGE` | template | `{url}` | messages | | ticket | One line per new ticket; placeholders url key title |
| `TICKET_POST_TO` | list | `clipboard` | messages | | ticket | Comma list of clipboard, slack, teams, webhook or none |
| `SLACK_WEBHOOK_SECRET` | secret name | `justcode-slack-webhook` | messages | yes | posts | Secret-store entry with the Slack incoming webhook URL |
| `TEAMS_WEBHOOK_SECRET` | secret name | `justcode-teams-webhook` | messages | yes | posts | Secret-store entry with the Teams webhook URL |
| `WEBHOOK_SECRET` | secret name | `justcode-webhook` | messages | yes | posts | Secret-store entry with a generic webhook URL |
| `TEAMS_PAYLOAD` | enum | `text` | messages | | posts | text or adaptive-card |

## Standup

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `STANDUP_DAY` | string | `yesterday` | - | | standup | Day reported without -d: yesterday, last-workday (by WORK_DAYS), today or a date |
| `STANDUP_REPOS` | array of paths | `()` | - | | standup | Repositories for commits and pull requests; empty means the current repository |
| `STANDUP_TODAY_STATUSES` | array | `('In Progress')` | - | | standup | Statuses of your tickets that fill the Today part |
| `STANDUP_MESSAGE` | template | `Yesterday {yesterday} Today {today} Blockers {blockers}`, one per line | - | | standup | The whole message; placeholders day label yesterday today blockers |
| `STANDUP_TIME_LINE` | template | `- {key} {title} ({duration})` | - | | standup | One line per ticket with time that day; placeholders key title duration secs entries comment url type |
| `STANDUP_PR_LINE` | template | `- {action} {title} {url}` | - | | standup | One line per pull request; placeholders action id title url repo draft |
| `STANDUP_PR_OPENED` | string | `opened` | - | | standup | {action} of a pull request created that day |
| `STANDUP_PR_UPDATED` | string | `updated` | - | | standup | {action} of an older pull request updated that day |
| `STANDUP_COMMIT_LINE` | template | `- {subject}` | - | | standup | One line per commit (same subjects once); placeholders subject sha repo |
| `STANDUP_TODAY_LINE` | template | `- {key} {title}` | - | | standup | One line per ticket in STANDUP_TODAY_STATUSES; placeholders key title url |
| `STANDUP_BLOCKER_LINE` | template | `- {text}` | - | | standup | One line per -b; placeholder text |
| `STANDUP_NONE` | string | `none` | - | | standup | Text of a part with nothing in it |
| `STANDUP_POST_TO` | list | `clipboard` | - | | standup | Comma list of clipboard, slack, teams, webhook or none |

## Release notes

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `RELEASE_NOTES_GROUPS` | array of pairs | `(Features 'Story,Feature' Fixes 'Bug' Other '*')` | - | | release-notes | Group name and comma list of ticket type globs, in output order; first match wins |
| `RELEASE_NOTES_NO_TICKET_GROUP` | string | `Other` | - | | release-notes | Group of commits without a ticket and of types no group matches |
| `RELEASE_NOTES_PR_LOOKUP` | 0/1 | `1` | - | | release-notes | Ask the code host for the pull request of each commit that names no ticket |
| `RELEASE_NOTES_HEADER` | template | `## {to} ({date})` | - | | release-notes | First line of the notes; placeholders from to date |
| `RELEASE_NOTES_GROUP_HEADER` | template | `### {group}` | - | | release-notes | Heading of each group; placeholders group from to date |
| `RELEASE_NOTES_TICKET_LINE` | template | `- {key} {title}` | - | | release-notes | One line per ticket; placeholders key title type status url commits sha |
| `RELEASE_NOTES_COMMIT_LINE` | template | `- {subject} ({sha})` | - | | release-notes | One line per commit without a ticket; placeholders subject sha full_sha |
| `RELEASE_NOTES_POST_TO` | list | `clipboard` | - | | release-notes | Comma list of clipboard, slack, teams, webhook or none |

## Nudge

| key | type | default | wizard | personal | read by | description |
|---|---|---|---|---|---|---|
| `NUDGE_AFTER_HOURS` | number | `24` | - | | nudge | A reviewer is nudged once a review has waited this many hours |
| `NUDGE_REPEAT_HOURS` | number | empty | - | | nudge | Optional quiet period: skip a reviewer nudged about the same pull request within this many hours; empty means off |
| `NUDGE_MESSAGE` | template | `{mentions} these pull requests are waiting for your review:` then `{items}` | - | | nudge | The one message; placeholders mentions items count |
| `NUDGE_LINE` | template | `- {title} {url} ({reviewers}, waiting {age})` | - | | nudge | One line per pull request; placeholders id title url reviewers age |
| `NUDGE_MENTION` | template | `@{user}` | - | | nudge | How a reviewer is named; placeholders user name |
| `NUDGE_MENTIONS` | map | `()` | - | | nudge | Code host user to chat handle, e.g. (bob '<@U123>'); wins over NUDGE_MENTION |
| `NUDGE_POST_TO` | list | `clipboard` | - | | nudge | Comma list of clipboard, slack, teams, webhook or none |

## Custom commands

A custom command `<name>` reads its own `<NAME>_*` keys (e.g. `DEPLOY_PREVIEW_URL`) plus the four per-command keys above. Personal commands live in `~/.config/justcode/commands/`, team commands in `<repo>/.justcode-commands/` (trusted per file).
