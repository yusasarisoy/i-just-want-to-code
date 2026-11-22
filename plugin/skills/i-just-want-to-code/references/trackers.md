# Trackers

Provider files: `runtime/providers/tracker/<name>.zsh`. Contract (return 3 = not supported):

| function | does |
|---|---|
| `tracker_get <key>` | sets `DF_TICKET_STATUS` and `DF_TICKET_ID` in the **current shell**; never call it inside `$( )` |
| `tracker_move <key> <status>` | via `STATUS_VIA` when there is no direct transition |
| `tracker_url <key>` | browse URL |
| `tracker_find_by_title <title>` | prints the key or nothing; exit 1 = search failed, and callers must stop (fail closed) |
| `tracker_create <type> <title> <description-file>` | resolves fields by screen name; a bad value lists the allowed ones and stops |
| `tracker_set_estimate <key> <points>` | |
| `tracker_doctor` | read-only self-check |

`ticket` resolves every `-f 'Field=Value'`, `TICKET_FIELDS` and `TICKET_FIELDS_<TYPE>` item by its screen name from the create metadata. With `TICKET_PREFER_CUSTOM_FIELDS=1` a custom field wins over a system field of the same name.

## Jira Cloud (`jira-cloud`)
- `TRACKER_URL=https://<site>.atlassian.net`, `TRACKER_USER` = your Atlassian email.
- Token: API token from id.atlassian.com (Security, API tokens); basic auth `email:token`.
- REST v3, descriptions in Atlassian Document Format, search through `/rest/api/3/search/jql`, assignees by accountId.
- Sprints and estimates need `TICKET_BOARD` (agile API).

## Jira Data Center / Server (`jira-dc`)
- `TRACKER_URL=https://jira.example.com`; no `TRACKER_USER`.
- Token: personal access token (profile, Personal Access Tokens), sent as Bearer.
- REST v2, wiki-markup descriptions, Epic Link field for epics, estimates through the agile estimation endpoint.
- Often behind a VPN: list the host in `VPN_HOSTS` (see network.md).

## Linear (`linear`)
- `TRACKER_URL` defaults to `https://api.linear.app`; GraphQL at `/graphql`.
- Token: personal API key (Settings, Security and access), sent as the `Authorization` header.
- `TICKET_PROJECT` is the team key (`ENG`); branches like `eng-42-fix` match the default key regex.
- States are set directly (no transitions); issue types map to labels of the same name; custom fields are not supported.

## None (`none`)
Every function returns 3. ship, tlog and build never touch a tracker secret.

## Not built in
- **GitHub Issues / Projects:** REST `/repos/<o>/<r>/issues`, keys are `#123`; set `TICKET_KEY_REGEX='[0-9]+'`. Projects v2 status needs GraphQL `updateProjectV2ItemFieldValue`.
- **Azure Boards:** `/_apis/wit/workitems/$<type>?api-version=7.1` with JSON Patch; state is the `System.State` field.
- **YouTrack:** `/api/issues`, Bearer permanent token; state through `customFields`.
- **Shortcut:** `/api/v3/stories`, `Shortcut-Token` header (`header:Shortcut-Token`).
