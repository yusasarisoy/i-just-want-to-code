#!/usr/bin/env zsh
# Persona C: self-hosted GitLab, Linear, Toggl, a deploy command, no VPN, clipboard.
source ${0:A:h}/../lib/env.zsh
p_init
p_repo https://git.example.com/alice/myapp.git alice/eng-42-login
p_secret justcode-code-token fake-secret-gl-c
p_secret justcode-tracker-token fake-secret-linear-c
p_secret justcode-time-token "fake-secret-toggl-c:api_token"
p_config "CODE_PROVIDER=gitlab
CODE_API_URL=$MOCK/gitlab/api/v4
CODE_USER=alice
DEFAULT_REVIEWERS=(bob)
CI_NUDGE_JOB=nudge
TRACKER_PROVIDER=linear
TRACKER_URL=$MOCK/linear
TICKET_PROJECT=ENG
STATUS_ON_SHIP='In Review'
TIME_PROVIDER=toggl
TIME_URL=$MOCK/toggl/api/v9
TIME_WORKSPACE=1
DEPLOY_PROVIDER=command
DEPLOY_COMMAND='print building \$JUSTCODE_VERSION'
BUILD_OUTPUT_DIR=$T/builds
SHIP_POST_TO=clipboard"

print "ship"
p_mark; p_run ship -n -a -l 1h
t_eq "ship -n exits 0" $RC 0
t_eq "ship -n sends no writes and no GraphQL mutation" "$(p_writes)" ""
t_has "lowercase branch key is found" "$OUT" "move ENG-42: 'In Progress' -> 'In Review'"
t_has "plans the CI nudge" "$OUT" "[dry-run] play then cancel manual job 'nudge'"
p_mark; p_run ship -a
t_eq "real ship exits 0" $RC 0
t_eq "real ship writes" "$(p_writes)" "POST /gitlab/api/v4/projects/alice%2Fmyapp/merge_requests
PUT /gitlab/api/v4/projects/alice%2Fmyapp/merge_requests/7
POST /gitlab/api/v4/projects/alice%2Fmyapp/jobs/21/play
POST /gitlab/api/v4/projects/alice%2Fmyapp/jobs/21/cancel
PUT /gitlab/api/v4/projects/alice%2Fmyapp/merge_requests/7/merge
POST /linear/graphql"
p_fail preparing-briefly
p_mark; p_run ship -a
t_has "new MR still preparing: auto-merge enabled after a re-read" "$OUT" "✓ auto-merge enabled"
t_has "new MR still preparing: merge-when-pipeline-succeeds sent" "$(p_writes)" "merge_requests/7/merge"
p_fail ''

print "tlog, tcheck, ticket, build"
p_mark; p_run tlog -n ENG-42 14-15
t_eq "tlog -n exits 0" $RC 0
t_eq "tlog -n sends no writes" "$(p_writes)" ""
p_run tcheck -w 1
t_has "tcheck covers last week" "$OUT" "Mon"
print -r -- $'Dark mode\nSupport the system setting.' >$T/d.txt
p_mark; p_run ticket -n -t Bug $T/d.txt
t_eq "linear ticket -n exits 0" $RC 0
t_eq "linear ticket -n sends no mutation" "$(p_writes)" ""
t_has "linear ticket -n plans the create" "$OUT" "[dry-run] create in ENG: \"Dark mode\""
p_fail search-fails
p_mark; p_run ticket -t Bug $T/d.txt
t_eq "linear search failure stops" $RC 1
t_eq "linear search failure creates nothing" "$(p_writes)" ""
p_fail ''
p_run build -n qa 1.2.3 7
t_has "build -n plans the deploy command" "$OUT" "JUSTCODE_VERSION=1.2.3"
p_run justcode doctor
t_has "doctor checks gitlab" "$OUT" "gitlab: token belongs to alice"
t_has "doctor checks linear" "$OUT" "linear: signed in as alice@example.com"
p_run justcode config
t_has "config shows the provider" "$OUT" "TRACKER_PROVIDER             linear"

t_lacks "no secret value in any curl argv" "$(<$SHIM_STATE/curl.argv)" fake-secret
t_done
