#!/usr/bin/env zsh
# Persona A: GitHub, Jira Cloud, no time tracker, TestFlight, no VPN, Slack.
source ${0:A:h}/../lib/env.zsh
zmodload zsh/datetime
p_init
p_repo https://github.com/alice/myapp.git feature/ABC-123-login
p_secret justcode-code-token fake-secret-code-a
p_secret justcode-tracker-token fake-secret-jira-a
p_secret justcode-slack-webhook "$MOCK/hooks/slack?token=fake-secret-slack-a"
p_config "CODE_PROVIDER=github
CODE_API_URL=$MOCK/github
CODE_USER=alice
DEFAULT_REVIEWERS=(bob)
SHIP_LABELS=(mobile)
TRACKER_PROVIDER=jira-cloud
TRACKER_URL=$MOCK/jira-cloud
TRACKER_USER=alice@example.com
TICKET_PROJECT=ABC
TICKET_BOARD=5
STATUS_MAP=( 'feature/*' 'In Review' )
STATUS_SKIP=(Done)
TICKET_FIELDS_BUG=('Severity=Minor')
TICKET_ESTIMATE_TYPES=(Story)
DEPLOY_PROVIDER=testflight
APP_NAME=MyApp
XCODE_WORKSPACE=MyApp.xcworkspace
BUILD_OUTPUT_DIR=$T/builds
SHIP_POST_TO=slack
TICKET_POST_TO=slack
BUILD_POST_TO=slack"

print "ship dry run"
p_mark; p_run ship -n -l 9-10
t_eq "ship -n exits 0" $RC 0
t_eq "ship -n sends no writes" "$(p_writes)" ""
t_has "plans the ticket move" "$OUT" "[dry-run] move ABC-123: 'In Progress' -> 'In Review'"
t_has "plans reviewers" "$OUT" "[dry-run] request reviewers: bob"
t_has "plans the slack message" "$OUT" "[dry-run] post to slack: <new pull request>"
t_has "no time tracker: time skipped" "$OUT" "time: not logged (no time tracker)"

print "auto-merge flags"
p_run env JUSTCODE_SET='SHIP_DEFAULT_ARGS=-a' ship -n
t_has "default -a plans auto-merge" "$OUT" "[dry-run] enable auto-merge"
p_run env JUSTCODE_SET='SHIP_DEFAULT_ARGS=-a' ship -n -A
t_eq "default -a with -A: no error" $RC 0
t_has "default -a with -A: no auto-merge" "$OUT" "• auto-merge off"
p_run env JUSTCODE_SET='SHIP_DEFAULT_ARGS=-a' ship -n -D
t_eq "default -a with -D: no error" $RC 0
t_has "default -a with -D: no auto-merge" "$OUT" "• auto-merge off"
t_has "draft leaves the ticket alone" "$OUT" "ticket: draft, ABC-123 left as it is"
p_run ship -n -a -D
t_eq "explicit -a -D is an error" $RC 1

print "untrusted repo file"
print -r -- "touch $T/team-marker" >.justcode
p_run ship -n
t_has "untrusted .justcode warned" "$OUT" ".justcode is not trusted; review it, then run: justcode trust"
t_no "untrusted .justcode not executed" test -e $T/team-marker
p_run zsh -c 'print y | justcode trust'
p_run ship -n
t_ok "trusted .justcode executed" test -e $T/team-marker
rm -f .justcode

print "ship for real"
p_mark; p_run env JUSTCODE_SET='SHIP_MESSAGE={url} {ticket_url};SHIP_PR_DESCRIPTION=Ticket: {ticket_url}' ship -a
t_eq "real ship exits 0" $RC 0
t_has "ticket_url filled in the PR description" "$(grep '^PATCH /github/repos/alice/myapp/pulls/7 ' $SHIM_STATE/requests.log)" "Ticket: $MOCK/jira-cloud/browse/ABC-123"
t_has "ticket_url filled in the team message" "$(grep '^POST /hooks/slack' $SHIM_STATE/requests.log)" "/jira-cloud/browse/ABC-123"
t_eq "real ship makes exactly the expected writes" "$(p_writes)" "POST /github/repos/alice/myapp/pulls
PATCH /github/repos/alice/myapp/pulls/7
POST /github/repos/alice/myapp/issues/7/labels
POST /github/repos/alice/myapp/pulls/7/requested_reviewers
POST /github/graphql
POST /jira-cloud/rest/api/3/issue/ABC-123/transitions
POST /hooks/slack"
t_has "auto-merge mutation sent" "$(<$SHIM_STATE/requests.log)" "enablePullRequestAutoMerge"
p_fail merge-now
p_mark; p_run ship -a
t_eq "would merge immediately: exit 0" $RC 0
t_has "would merge immediately: skip line" "$OUT" "• auto-merge not enabled: merge state is 'clean'"
t_lacks "would merge immediately: no merge call" "$(p_writes)" "/graphql"
p_fail state-unknown
p_mark; p_run ship -a
t_has "new PR (state unknown): auto-merge enabled" "$OUT" "✓ auto-merge enabled"
t_has "new PR (state unknown): mutation sent" "$(p_writes)" "POST /github/graphql"
p_fail ''

print "tickets"
drafts=$T/drafts.txt
print -r -- $'Crash on login\nSteps: open the app.\n---8<---\nTypo on the welcome screen\nIt says Welcom.' >$drafts
p_mark; p_run ticket -n -t Bug $drafts
t_eq "ticket -n exits 0" $RC 0
t_eq "ticket -n sends no writes" "$(p_writes)" ""
t_has "custom field preferred over the system one" "$OUT" "customfield_101"
p_run ticket -n -t Bug -f 'Severity=Huge' $drafts
t_eq "bad field value stops" $RC 1
t_has "bad value lists the allowed ones" "$OUT" "allowed: Minor, Major"
p_run ticket -n -t Story $drafts
t_eq "estimate required for Story" $RC 1
p_mark; p_run ticket -t Story -P 3,5 $drafts
t_eq "real ticket run exits 0" $RC 0
t_eq "real ticket run writes" "$(p_writes)" "POST /jira-cloud/rest/api/3/issue
PUT /jira-cloud/rest/agile/1.0/issue/ABC-200/estimation
POST /jira-cloud/rest/api/3/issue
PUT /jira-cloud/rest/agile/1.0/issue/ABC-200/estimation
POST /hooks/slack"
p_fail search-fails
p_mark; p_run ticket -t Bug $drafts
t_eq "search failure: exit 1" $RC 1
t_eq "search failure: nothing created" "$(p_writes)" ""
p_fail exists
p_mark; p_run ticket -t Bug $drafts
t_has "existing ticket is reused" "$OUT" "• exists: ABC-7"
t_lacks "existing ticket: no create" "$(p_writes)" "/rest/api/3/issue"
p_fail ''

print "build, doctor, config"
p_run build -n -K "ABC-123" test 1.2.3 7
t_eq "build -n exits 0" $RC 0
t_has "build -n plans the archive" "$OUT" "xcodebuild -workspace MyApp.xcworkspace -scheme 'MyApp test Release'"
t_has "build -n plans the upload" "$OUT" "-exportArchive"
t_has "build -n shows the message" "$OUT" "test 1.2.3 (7) qa build uploaded"
t_lacks "build -n ran no xcodebuild" "$(<$SHIM_STATE/calls.log)" "xcodebuild"
print -r -- "new" >never-added.txt
print -r -- "changed" >>login.txt
p_run build -w test 1.2.3 8
t_eq "build -w snapshot has the file that was never added" "$(git show refs/justcode/builds/test-1.2.3-8:never-added.txt 2>&1)" "new"
t_has "build -w snapshot has the tracked change" "$(git show refs/justcode/builds/test-1.2.3-8:login.txt 2>&1)" "changed"
t_eq "build -w leaves the real index alone" "$(git status --porcelain)" " M login.txt
?? never-added.txt"
git checkout -q login.txt; rm -f never-added.txt
p_run justcode doctor
t_eq "doctor passes" $RC 0
p_run justcode config
t_has "config shows the tracker" "$OUT" "TRACKER_PROVIDER             jira-cloud"

print "standup"
p_secret justcode-time-token fake-secret-tempo-a
tempo="TIME_PROVIDER=tempo-cloud;TIME_URL=$MOCK/tempo;TIME_USER=acc-alice;STANDUP_POST_TO=slack"
yday=$(strftime %Y-%m-%d $(( EPOCHSECONDS - 24 * 3600 )))
GIT_AUTHOR_DATE="$yday 10:00" GIT_COMMITTER_DATE="$yday 10:00" git commit -q --allow-empty -m "Validate the password"
p_mark; p_run env JUSTCODE_SET="$tempo" standup -n -d $yday -b "Waiting for the API keys"
t_eq "standup -n exits 0" $RC 0
t_eq "standup -n sends no writes" "$(p_writes)" ""
t_has "standup: time log with the ticket title" "$OUT" "- ABC-123 Login (1h)"
t_has "standup: a pull request opened that day" "$OUT" "- opened Add login screen https://git.example.com/alice/myapp/pull/7"
t_has "standup: a pull request updated that day" "$OUT" "- updated Fix the crash on start"
t_has "standup: the day's commit" "$OUT" "- Validate the password"
t_lacks "standup: today's commit is not yesterday's" "$OUT" "- Add login screen"$'\n'
t_has "standup: today from In Progress tickets" "$OUT" $'Today\n- ABC-123 Login\n- ABC-124 Crash on start'
t_has "standup: the blocker" "$OUT" $'Blockers\n- Waiting for the API keys'
t_has "standup -n plans the post" "$OUT" "[dry-run] post to slack: Yesterday"
p_run env JUSTCODE_SET="$tempo;STANDUP_COMMIT_LINE=;STANDUP_SKIP=today" standup -n -d $yday
t_lacks "an emptied template leaves its lines out" "$OUT" "Validate the password"
t_has "a skipped step is a skip line" "$OUT" "• today: skipped"
t_has "no blockers: the none text" "$OUT" $'Blockers\nnone'
p_run standup -n -d 2026-02-30
t_eq "standup: impossible day stops" $RC 1
p_mark; p_run env JUSTCODE_SET="$tempo" standup -d $yday -b "Waiting for the API keys"
t_eq "real standup exits 0" $RC 0
t_eq "real standup only posts" "$(p_writes)" "POST /hooks/slack"
t_has "the post carries the message" "$(grep '^POST /hooks/slack' $SHIM_STATE/requests.log | tail -1)" "Waiting for the API keys"

print "tcheck --fill"
now=$(strftime -r '%Y-%m-%d %H:%M' '2026-11-18 12:00')
for t in 10:05 10:40 11:20 11:50; do
  GIT_AUTHOR_DATE="2026-11-17 $t" GIT_COMMITTER_DATE="2026-11-17 $t" git commit -q --allow-empty -m "Login step $t"
done
fill="TIME_PROVIDER=tempo-cloud;TIME_URL=$MOCK/tempo;TIME_USER=acc-alice"
p_mark; p_run env JUSTCODE_NOW=$now JUSTCODE_SET="$fill" tcheck --fill -n
t_eq "tcheck --fill -n exits 0" $RC 0
t_eq "tcheck --fill -n sends no writes" "$(p_writes)" ""
t_has "the short day is still reported" "$OUT" "✗ Tue 2026-11-17 0m, 8h short"
t_has "proposal from the branch's commits" "$OUT" "Tue 10:00-12:00 → ABC-123 (4 commits)"
t_has "a day without commits is a skip" "$OUT" "• fill: Mon 2026-11-16 has no commits with a ticket key"
t_has "dry run shows the tlog call" "$OUT" "[dry-run] tlog -t code ABC-123 10:00-12:00 2026-11-17 Development"
t_lacks "never proposes the logged 09:00-10:00" "$OUT" "09:00-"
p_mark; p_run env JUSTCODE_NOW=$now JUSTCODE_SET="$fill" tcheck --fill
t_has "without -y and a terminal nothing is logged" "$OUT" "• fill: not confirmed; nothing logged (run again with -y to log them)"
t_eq "unconfirmed fill sends no writes" "$(p_writes)" ""
p_mark; p_run env JUSTCODE_NOW=$now JUSTCODE_SET="$fill" tcheck --fill -y
t_eq "tcheck --fill -y exits 0" $RC 0
t_has "logged through tlog" "$OUT" "✓ logged 2h on ABC-123, 2026-11-17 10:00 (code)"
t_eq "one worklog written" "$(p_writes)" "POST /tempo/4/worklogs"
p_run env JUSTCODE_SET="$fill" tlog -n ABC-123 9:30-10:30
t_eq "tlog refuses an overlapping new entry" $RC 1
t_has "tlog names the overlap" "$OUT" "9:30-10:30 would overlap ABC-123 at 09:00"

print "release-notes"
git tag v0.1.0
git commit -q --allow-empty -m "ABC-124 fix the crash on start"
git commit -q --allow-empty -m "Polish the login form" -m "Refs ABC-123"
git commit -q --allow-empty -m "Bump the version"
git tag v0.2.0
p_mark; p_run release-notes -n v0.1.0 v0.2.0
t_eq "release-notes -n exits 0" $RC 0
t_eq "release-notes -n sends no writes" "$(p_writes)" ""
t_has "keys from subject and body, grouped by type" "$OUT" $'### Features\n- ABC-123 Login\n\n### Fixes\n- ABC-124 Crash on start'
t_has "a commit without a ticket goes to Other" "$OUT" $'### Other\n- Bump the version ('
t_has "the header names the release" "$OUT" "## v0.2.0 ("
t_has "release-notes -n plans the post" "$OUT" "[dry-run] post to clipboard: ## v0.2.0"
p_fail commit-prs
p_run release-notes -n v0.1.0 v0.2.0
t_has "a pull request's branch gives the ticket" "$OUT" $'### Other\n- ABC-125 Update the docs'
t_lacks "that commit is no longer ticketless" "$OUT" "Bump the version"
p_fail ''
p_run env JUSTCODE_SET='RELEASE_NOTES_TICKET_LINE=- [{key}]({url}) {title} ({type})' release-notes -n v0.1.0 v0.2.0
t_has "the line template is the user's" "$OUT" "- [ABC-124]($MOCK/jira-cloud/browse/ABC-124) Crash on start (Bug)"
p_run release-notes -n v0.2.0 v0.1.0
t_has "an empty range says so" "$OUT" "• message: the notes are empty"
p_run release-notes -n v9.9.9
t_eq "unknown ref stops" $RC 1
p_mark; p_run env JUSTCODE_SET='RELEASE_NOTES_POST_TO=slack' release-notes -o $T/notes.md v0.1.0 v0.2.0
t_eq "release-notes -o exits 0" $RC 0
t_has "notes written to the file" "$(<$T/notes.md)" "- ABC-124 Crash on start"
t_has "the file is markdown" "$(<$T/notes.md)" "### Fixes"
t_eq "release-notes only posts" "$(p_writes)" "POST /hooks/slack"
p_run release-notes -o $T/notes.md v0.1.0 v0.2.0
t_eq "a second run overwrites the same file" "$(grep -c 'ABC-124' $T/notes.md)" 1

print "nudge"
p_mark; p_run env JUSTCODE_SET='NUDGE_POST_TO=slack' nudge -n
t_eq "nudge -n exits 0" $RC 0
t_eq "nudge -n sends no writes" "$(p_writes)" ""
t_has "drafts are counted and skipped" "$OUT" "✓ open pull requests: 2 (1 draft skipped)"
t_has "only reviewers past 24h" "$OUT" "✓ waiting 24h or more: 1 pull request(s), reviewers bob"
t_has "one message, shown first" "$OUT" $'@bob these pull requests are waiting for your review:\n- Pull request 7 https://git.example.com/alice/myapp/pull/7 (@bob, waiting 1d 6h)'
t_lacks "a reviewer asked 2h ago is not nudged" "$OUT" "@carol"
t_lacks "a draft is never in the message" "$OUT" "Pull request 8"
t_lacks "someone else's pull request is left alone" "$OUT" "Pull request 9"
t_has "nudge -n plans the post" "$OUT" "[dry-run] post to slack: @bob"
p_mark; p_run env JUSTCODE_SET='NUDGE_POST_TO=slack' nudge
t_has "without -y and a terminal nothing is sent" "$OUT" "• not confirmed; nothing sent (run again with -y to send it)"
t_eq "unconfirmed nudge sends no writes" "$(p_writes)" ""
p_run env JUSTCODE_SET='NUDGE_POST_TO=slack;NUDGE_AFTER_HOURS=1' nudge -n
t_has "the limit is the user's" "$OUT" "reviewers bob, carol"
p_mark; p_run env JUSTCODE_SET='NUDGE_POST_TO=slack' nudge -y
t_eq "nudge -y exits 0" $RC 0
t_eq "nudge -y only posts" "$(p_writes)" "POST /hooks/slack"
p_mark; p_run env JUSTCODE_SET='NUDGE_POST_TO=slack' nudge -y
t_eq "a second nudge is sent again by default" "$(p_writes)" "POST /hooks/slack"
p_run env JUSTCODE_SET='NUDGE_POST_TO=slack;NUDGE_REPEAT_HOURS=12' nudge -y
p_mark; p_run env JUSTCODE_SET='NUDGE_POST_TO=slack;NUDGE_REPEAT_HOURS=12' nudge -y
t_has "an opted-in quiet period skips the reviewer" "$OUT" "• bob on #7 was nudged"
t_eq "quiet period: nothing sent" "$(p_writes)" ""
p_run env JUSTCODE_SET='CODE_USER=bob' nudge -n
t_eq "token of another account: nudge refuses" $RC 1

print "secrets"
t_lacks "no secret value in any curl argv" "$(<$SHIM_STATE/curl.argv)" fake-secret
t_done
