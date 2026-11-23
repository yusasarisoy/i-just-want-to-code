# Code hosts

Provider files: `runtime/providers/code/<name>.zsh`. Contract (every function; return 3 = not supported, shown as `•`):

| function | does |
|---|---|
| `code_whoami` | prints the token owner's username; ship stops if it differs from `CODE_USER` |
| `code_find_pr <branch>` | prints `{id, url, title, draft, reviewers:[...], merge_state}` or nothing |
| `code_create_pr <branch> <target> <title> <draft 0/1>` | prints the same JSON for the new PR |
| `code_update_pr <id> title=... description=... labels+=...` | description only when empty |
| `code_set_draft <id> 0/1` | |
| `code_add_reviewers <id> <users...>` | keeps existing reviewers |
| `code_auto_merge <id>` | 0 = set; 2 = would merge immediately or state unknown, and then it does **not** merge |
| `code_ci_nudge <branch> <sha>` | optional (GitLab) |
| `code_doctor` | read-only self-check |

Remotes understood: `https://host[:port]/owner/name(.git)`, `git@host:owner/name`, `ssh://git@host:2222/owner/name`. `CODE_REPO` overrides the path, `CODE_API_URL` the API base.

## GitHub (`github`)
- REST v3 for everything, GraphQL for draft toggles and auto-merge (`enablePullRequestAutoMerge`).
- API URL: `https://api.github.com`; GitHub Enterprise: `https://<host>/api/v3`.
- Token: fine-grained token with Pull requests read/write and Contents read, or a classic token with `repo`. `CODE_TOKEN_SECRET=gh` reuses the GitHub CLI login.
- Auto-merge needs "Allow auto-merge" in the repository settings; when the PR is already mergeable GitHub would merge at once, so justcode returns 2 and leaves it. A new PR whose state is still `unknown` gets auto-merge; GitHub refuses it if the PR turns out to be mergeable already.

## GitLab (`gitlab`)
- REST v4, gitlab.com or self-hosted (`https://<host>/api/v4`, derived from the remote).
- Token: personal or project access token with scope `api`, sent as `PRIVATE-TOKEN`.
- Auto-merge is "merge when pipeline succeeds"; a new MR that is still being checked or has no pipeline yet is read again for up to ~8 s; still without a running pipeline, justcode returns 2.
- `CI_NUDGE_JOB`: name of a manual job that ship plays and cancels at once, so a pipeline that would wait on it settles as passed with warnings. Off by default.

## Bitbucket Cloud (`bitbucket`)
- REST 2.0 at `https://api.bitbucket.org/2.0`.
- Secret value is `username:app-password` or `email:api-token` (basic auth).
- Reviewers are account IDs (`{...}`), not usernames.
- Labels and auto-merge are not supported (•).

## Not built in (write a provider from the contract)
- **Bitbucket Data Center:** REST 1.0 under `/rest/api/1.0/projects/<key>/repos/<slug>/pull-requests`, Bearer HTTP access token; reviewers are user slugs.
- **Gitea / Forgejo:** `/api/v1/repos/<owner>/<repo>/pulls`, `Authorization: token <t>` (use `header:Authorization` with the secret `token <t>`).
- **Azure DevOps:** `/<org>/<project>/_apis/git/repositories/<repo>/pullrequests?api-version=7.1`, basic auth with an empty user and a PAT; auto-merge is "autoCompleteSetBy".

Add mock routes in `tests/mock/server.py` and a persona test for a new provider.
