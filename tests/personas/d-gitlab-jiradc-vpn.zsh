#!/usr/bin/env zsh
# Persona D: GitLab, Jira Data Center, Tempo DC, TestFlight, a VPN whose host
# is down until `vpn up`, webhook messages.
source ${0:A:h}/../lib/env.zsh
p_init
p_repo https://git.example.com/alice/myapp.git feature/ABC-123-login
Q=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
print $Q >$SHIM_STATE/vpn_port
VPN=http://127.0.0.1:$Q
p_secret justcode-code-token fake-secret-gl-d
p_secret justcode-tracker-token fake-secret-jdc-d
p_secret justcode-time-token fake-secret-tdc-d
p_secret justcode-webhook "$MOCK/hooks/webhook?key=fake-secret-hook-d"
config() {
  p_config "CODE_PROVIDER=gitlab
CODE_API_URL=$MOCK/gitlab/api/v4
CODE_USER=alice
TRACKER_PROVIDER=jira-dc
TRACKER_URL=$VPN/jira-dc
TICKET_PROJECT=ABC
TIME_PROVIDER=tempo-dc
TIME_URL=$VPN/jira-dc
TIME_USER=alice
DEPLOY_PROVIDER=testflight
APP_NAME=MyApp
XCODE_PROJECT=MyApp.xcodeproj
BUILD_OUTPUT_DIR=$T/builds
VPN_PROVIDER=command
VPN_HOSTS=(127.0.0.1:$Q)
VPN_STATUS_CMD='fakevpn status'
VPN_UP_CMD='$1'
VPN_DOWN_CMD='fakevpn down'
NETWORK_WAIT_SECS=${2:-60}
SHIP_POST_TO=webhook"
}
config 'fakevpn up'
today=$(zsh -c 'zmodload zsh/datetime; strftime %Y-%m-%d $EPOCHSECONDS')

print "VPN host down, then up"
p_run vpn status
t_has "vpn status reports the host down" "$OUT" "✗ 127.0.0.1:$Q not reachable"
p_mark; p_run ship -n -l 10-11
t_eq "ship -n exits 0 after the VPN comes up" $RC 0
t_has "ship -n started the VPN" "$OUT" "is not reachable; starting the VPN"
t_has "ship -n saw the host come up" "$OUT" "✓ 127.0.0.1:$Q is reachable"
t_eq "ship -n sends no writes" "$(p_writes)" ""
t_has "plans the Jira DC move" "$OUT" "[dry-run] move ABC-123"
t_has "plans the Tempo DC log" "$OUT" "[dry-run] log 1h on ABC-123, $today 10:00"
p_mark; p_run tlog -n ABC-123 10-11
t_eq "tlog -n sends no writes" "$(p_writes)" ""
p_run tcheck
t_has "tcheck reads Tempo DC" "$OUT" "total:"
print -r -- $'Slow sync\nSync takes a minute.' >$T/d.txt
p_mark; p_run ticket -n -t Bug -e ABC-1 $T/d.txt
t_eq "jira-dc ticket -n exits 0" $RC 0
t_has "jira-dc uses Epic Link" "$OUT" "customfield_104"
t_eq "jira-dc ticket -n sends no writes" "$(p_writes)" ""
p_run build -n test 1.2.3 7
t_has "build -n plans a project build" "$OUT" "xcodebuild -project MyApp.xcodeproj"
p_run justcode doctor
t_has "doctor checks jira-dc" "$OUT" "jira-dc: signed in as alice"

print "VPN never comes up"
fakevpn down
config 'fakevpn never' 3
start=$EPOCHSECONDS
p_run ship -n
took=$(( EPOCHSECONDS - start ))
t_eq "no wait hang: ship -n fails" $RC 1
t_has "no wait hang: names the host" "$OUT" "127.0.0.1:$Q is still not reachable after 3s"
(( took <= 8 )) && t_pass "no wait hang: ended in ${took}s (limit 3s + checks)" || t_failed "no wait hang" "took ${took}s"

t_lacks "no secret value in any curl argv" "$(<$SHIM_STATE/curl.argv)" fake-secret
t_done
