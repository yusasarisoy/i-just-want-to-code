#!/usr/bin/env zsh
# Persona A: GitHub, Jira Cloud, no time tracker, TestFlight, no VPN, Slack.
source ${0:A:h}/../lib/env.zsh
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

print "secrets"
t_lacks "no secret value in any curl argv" "$(<$SHIM_STATE/curl.argv)" fake-secret
t_done
