# Messages

`ship`, `build` and `ticket` fill a template and send it to every target in `<CMD>_POST_TO` (comma list). `justcode-post <targets> <message-on-stdin>` does the same by hand. In a dry run the message and its targets are printed, nothing is sent.

## Templates and placeholders
`{name}` is replaced; an unknown placeholder stays as written.

| template | placeholders | default |
|---|---|---|
| `SHIP_MESSAGE` | `{url} {title} {branch} {target} {ticket} {ticket_url}` | `{url}` |
| `SHIP_PR_DESCRIPTION` | `{ticket} {ticket_url} {branch} {title} {target}` | empty |
| `BUILD_MESSAGE` | `{env} {version} {build} {kind} {config}` | `{env} {version} ({build}) {kind} build uploaded` |
| `TICKET_MESSAGE` | `{url} {key} {title}` (one line per ticket) | `{url}` |

`build -K "ABC-1 ABC-2"` appends one line per ticket key with its link.

Ready-made templates (the setup wizard offers these):
- ship: `{url}`, `{title}: {url}`, `Ready for review: {ticket} {title} {url}`
- build: `{env} {version} ({build}) {kind} build uploaded`, `New {kind} build {version} ({build}) on {env}`
- ticket: `{url}`, `{key}: {title} {url}`

## Targets
| target | secret | payload |
|---|---|---|
| `clipboard` | none | rich HTML (links clickable) where the OS supports it, plain text otherwise |
| `slack` | `SLACK_WEBHOOK_SECRET`: incoming webhook URL | `{"text": ...}` |
| `teams` | `TEAMS_WEBHOOK_SECRET`: incoming webhook or workflow URL | `TEAMS_PAYLOAD=text` sends `{"text": ...}`; `adaptive-card` wraps it in an Adaptive Card |
| `webhook` | `WEBHOOK_SECRET`: any URL | `{"text": ..., "html": ...}` |
| `none` | | nothing |

The webhook URL is the secret: it is read with `df_secret` and passed to curl on stdin, never on the command line. Each target runs on its own; one failing target is reported with `✗` and the others are still sent.
