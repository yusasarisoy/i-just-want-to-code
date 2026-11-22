#!/usr/bin/env zsh
# Persona B: Bitbucket Cloud, Jira Cloud, Tempo Cloud, Google Play, a VPN
# command preset, Teams messages.
source ${0:A:h}/../lib/env.zsh
p_init
p_repo https://bitbucket.org/alice/myapp.git feature/ABC-123-login
p_secret justcode-code-token "alice:fake-secret-bb"
p_secret justcode-tracker-token fake-secret-jira-b
p_secret justcode-time-token fake-secret-tempo-b
p_secret justcode-play-json-key fake-secret-play-b
p_secret justcode-teams-webhook "$MOCK/hooks/teams?sig=fake-secret-teams-b"
p_config "CODE_PROVIDER=bitbucket
CODE_API_URL=$MOCK/bitbucket/2.0
CODE_USER=alice
DEFAULT_REVIEWERS=(acc-bob)
TRACKER_PROVIDER=jira-cloud
TRACKER_URL=$MOCK/jira-cloud
TRACKER_USER=alice@example.com
TICKET_PROJECT=ABC
TIME_PROVIDER=tempo-cloud
TIME_URL=$MOCK/tempo
TIME_USER=acc-alice
TIME_TYPE_ATTRIBUTE=_Activity_
typeset -A TIME_TYPES=( code Development meeting Meeting )
DEPLOY_PROVIDER=play
GRADLE_TASK_PATTERN=':app:bundle{Env}Release'
PLAY_PACKAGE=com.example.myapp
BUILD_OUTPUT_DIR=$T/builds
VPN_PROVIDER=command
VPN_STATUS_CMD='fakevpn status'
VPN_UP_CMD='fakevpn up'
VPN_DOWN_CMD='fakevpn down'
SHIP_POST_TO=teams
TEAMS_PAYLOAD=adaptive-card"
today=$(zsh -c 'zmodload zsh/datetime; strftime %Y-%m-%d $EPOCHSECONDS')

print "ship"
p_mark; p_run ship -n -a -l 10-11
t_eq "ship -n exits 0" $RC 0
t_eq "ship -n sends no writes" "$(p_writes)" ""
t_has "plans the time log" "$OUT" "[dry-run] log 1h on ABC-123, $today 10:00 (code)"
t_has "auto-merge unsupported is a skip" "$OUT" "[dry-run] enable auto-merge"
p_run ship -n -l 9-10
t_has "duplicate worklog is skipped" "$OUT" "• time: 1h on ABC-123 at 09:00 already logged"
p_run ship -n -l 1h
t_has "a duration starts after the day's last entry" "$OUT" "$today 10:00"
p_fail 500@/worklogs/user
p_mark; p_run ship -l 10-11
t_eq "time list fails: exit 1" $RC 1
t_has "time list fails: clear message" "$OUT" "cannot read $today's worklogs; nothing logged"
t_lacks "time list fails: nothing logged" "$(p_writes)" "/worklogs"
t_has "a failed step holds back the message" "$OUT" "• message not sent: a step failed"
p_fail ''

print "tlog and tcheck"
p_mark; p_run tlog -n ABC-123 10-11
t_eq "tlog -n exits 0" $RC 0
t_eq "tlog -n sends no writes" "$(p_writes)" ""
p_run tlog -n ABC-123 9-10
t_has "tlog duplicate skipped" "$OUT" "already logged"
p_run tlog -n -e 9 ABC-123 11-12
t_has "tlog -e plans the move" "$OUT" "[dry-run] move ABC-123 $today 09:00 -> 11:00"
p_run tlog -n -e 14 ABC-123 15-16
t_eq "tlog -e without a match stops" $RC 1
p_mark; p_run tcheck
t_has "tcheck prints a total" "$OUT" "total:"
t_eq "tcheck sends no writes" "$(p_writes)" ""

print "ticket, build, doctor, config"
print -r -- $'Offline banner\nShow a banner when offline.' >$T/d.txt
p_mark; p_run ticket -n -t Task $T/d.txt
t_eq "ticket -n exits 0" $RC 0
t_eq "ticket -n sends no writes" "$(p_writes)" ""
p_run build -n beta 1.2.3 7
t_has "build -n says the upload needs fastlane" "$OUT" "fastlane is not installed"
t_has "build -n plans the Gradle task" "$OUT" ":app:bundleBetaRelease -Pjustcode.versionName=1.2.3 -Pjustcode.versionCode=7"
t_lacks "build -n ran no Gradle" "$(<$SHIM_STATE/calls.log)" "gradle "
p_run justcode doctor
t_has "doctor checks the VPN preset" "$OUT" "vpn: connect command set"
t_has "doctor checks Tempo" "$OUT" "tempo-cloud: worklogs readable"
p_run justcode config
t_has "config shows the map" "$OUT" "TIME_TYPES                   ( code Development meeting Meeting )"

t_lacks "no secret value in any curl argv" "$(<$SHIM_STATE/curl.argv)" fake-secret
t_done
