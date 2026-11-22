# Time tracking

Provider files: `runtime/providers/time/<name>.zsh`. Contract:

| function | does |
|---|---|
| `time_list <day>` | prints `[{id, key, start:"HH:MM", secs, type, comment}]` (local time) or fails |
| `time_create <key> <day> <HH:MM> <secs> <type> <comment>` | |
| `time_update <id> <key> <day> <HH:MM> <secs> <type> <comment>` | used by `tlog -e` |
| `time_day_total <day>`, `time_week_totals <from> <to>` | seconds |
| `time_doctor` | read-only self-check |

`TIME_TYPES` maps a short name (`code`, `meeting`) to the provider's value. tlog refuses an entry that overlaps an existing one; a duration (`ship -l 1h30m`) starts at the end of the day's last entry, or at `DEFAULT_START`.

## Tempo Cloud (`tempo-cloud`)
- API `https://api.tempo.io/4`, Tempo API token (Tempo settings, API integration) as Bearer.
- `TIME_USER` = your Atlassian account ID. Worklogs need the numeric Jira issue id, so the Jira Cloud tracker must be configured too.
- Types: set `TIME_TYPE_ATTRIBUTE` to the work attribute key and `TIME_TYPES` values to its allowed values.

## Tempo Timesheets on Jira DC (`tempo-dc`)
- API `<jira>/rest/tempo-timesheets/4`; `TIME_URL` defaults to `TRACKER_URL`. Jira personal access token as Bearer.
- `TIME_USER` = your Tempo worker key (usually `JIRAUSER...`).

## Toggl Track (`toggl`)
- API `https://api.track.toggl.com/api/v9`; secret value `<api-token>:api_token` (basic).
- `TIME_WORKSPACE` = numeric workspace id. Entries are UTC; the description is `<KEY> <comment>`; `TIME_TYPES` values are tag names.

## Clockify (`clockify`)
- API `https://api.clockify.me/api/v1`, `X-Api-Key` header.
- `TIME_WORKSPACE` = workspace id, `TIME_USER` = user id (empty = token owner). UTC; description `<KEY> <comment>`; `TIME_TYPES` values are tag ids.

## None (`none`)
Nothing is read or written. `ship -l` is skipped (•).

## Not built in
- **Harvest:** `https://api.harvestapp.com/v2/time_entries`, Bearer token plus a `Harvest-Account-Id` header; entries need `project_id` and `task_id`, so map tickets to them with your own `<NAME>_*` keys.
