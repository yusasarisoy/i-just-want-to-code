# Messages

`ship`, `build`, `ticket`, `standup`, `release-notes` and `nudge` fill a template and send it to every target in `<CMD>_POST_TO` (comma list). `justcode-post <targets> <message-on-stdin>` does the same by hand. In a dry run the message and its targets are printed, nothing is sent.

## Templates and placeholders
`{name}` is replaced; an unknown placeholder stays as written.

| template | placeholders | default |
|---|---|---|
| `SHIP_MESSAGE` | `{url} {title} {branch} {target} {ticket} {ticket_url}` | `{url}` |
| `SHIP_PR_DESCRIPTION` | `{ticket} {ticket_url} {branch} {title} {target}` | empty |
| `BUILD_MESSAGE` | `{env} {version} {build} {kind} {config}` | `{env} {version} ({build}) {kind} build uploaded` |
| `TICKET_MESSAGE` | `{url} {key} {title}` (one line per ticket) | `{url}` |

| `STANDUP_MESSAGE` | `{day} {label} {yesterday} {today} {blockers}` | `Yesterday`, `{yesterday}`, `Today`, `{today}`, `Blockers`, `{blockers}`, one per line |
| `STANDUP_TIME_LINE` | `{key} {title} {duration} {secs} {entries} {comment} {url} {type}` | `- {key} {title} ({duration})` |
| `STANDUP_PR_LINE` | `{action} {id} {title} {url} {repo} {draft}` | `- {action} {title} {url}` |
| `STANDUP_COMMIT_LINE` | `{subject} {sha} {repo}` | `- {subject}` |
| `STANDUP_TODAY_LINE` | `{key} {title} {url}` | `- {key} {title}` |
| `STANDUP_BLOCKER_LINE` | `{text}` | `- {text}` |
| `RELEASE_NOTES_HEADER` | `{from} {to} {date}` | `## {to} ({date})` |
| `RELEASE_NOTES_GROUP_HEADER` | `{group} {from} {to} {date}` | `### {group}` |
| `RELEASE_NOTES_TICKET_LINE` | `{key} {title} {type} {status} {url} {commits} {sha}` | `- {key} {title}` |
| `RELEASE_NOTES_COMMIT_LINE` | `{subject} {sha} {full_sha}` | `- {subject} ({sha})` |
| `NUDGE_MESSAGE` | `{mentions} {items} {count}` | `{mentions} these pull requests are waiting for your review:` and `{items}` on the next line |
| `NUDGE_LINE` | `{id} {title} {url} {reviewers} {age}` | `- {title} {url} ({reviewers}, waiting {age})` |
| `NUDGE_MENTION` | `{user} {name}` | `@{user}` (a `NUDGE_MENTIONS` entry wins) |
| `TCHECK_FILL_LINE` | `{label} {day} {start} {end} {key} {commits} {duration}` | `{label} {start}-{end} → {key} ({commits} commits)` (shown, not sent) |

`build -K "ABC-1 ABC-2"` appends one line per ticket key with its link.

### Your templates, your rules
- Read every template with `justcode config`; change any of them in your config (`justcode edit global|team|local`) or for one run with `JUSTCODE_SET`.
- Leave a key unset and the default above is used. Set a standup, release-notes, nudge or tcheck --fill template to empty and that part is left out: `STANDUP_COMMIT_LINE=''` drops commit lines, `RELEASE_NOTES_HEADER=''` drops the title, `NUDGE_MESSAGE=''` sends nothing.
- Placeholders are filled in one pass, so a value that itself contains `{x}` is never filled again.
- `standup` and `release-notes` send right after the dry run you approved; `nudge` shows its message and sends only after a yes (or `-y`). A message is never blocked from being sent again; `NUDGE_REPEAT_HOURS` is an opt-in quiet period for nudges only.

Ready-made templates (the setup wizard offers these):
- ship: `{url}`, `{title}: {url}`, `Ready for review: {ticket} {title} {url}`
- build: `{env} {version} ({build}) {kind} build uploaded`, `New {kind} build {version} ({build}) on {env}`
- ticket: `{url}`, `{key}: {title} {url}`
- standup lines: `- {key} {title} ({duration})`, `- {key}: {comment} ({duration})`; Slack-style headings: `*Yesterday*` … in `STANDUP_MESSAGE`
- release-notes: `- {key} {title}`, `- [{key}]({url}) {title}`
- nudge: `@{user}`, `<@{user}>` (map Slack ids with `NUDGE_MENTIONS`)

## Targets
| target | secret | payload |
|---|---|---|
| `clipboard` | none | rich HTML (links clickable) where the OS supports it, plain text otherwise |
| `slack` | `SLACK_WEBHOOK_SECRET`: incoming webhook URL | `{"text": ...}` |
| `teams` | `TEAMS_WEBHOOK_SECRET`: incoming webhook or workflow URL | `TEAMS_PAYLOAD=text` sends `{"text": ...}`; `adaptive-card` wraps it in an Adaptive Card |
| `webhook` | `WEBHOOK_SECRET`: any URL | `{"text": ..., "html": ...}` |
| `none` | | nothing |

The webhook URL is the secret: it is read with `df_secret` and passed to curl on stdin, never on the command line. Each target runs on its own; one failing target is reported with `✗` and the others are still sent.
