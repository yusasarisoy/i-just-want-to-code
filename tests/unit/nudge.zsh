#!/usr/bin/env zsh
# nudge helpers: who has waited long enough, ages, mentions.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../runtime}
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX"); cd $HOME
source $DF_ROOT/lib/justcode-lib.zsh
source $DF_ROOT/lib/reports.zsh

print "waiting"
now=$(( 100 * 3600 ))
prs='[{"id":7,"draft":false,"reviewers":[{"user":"bob","since":'$(( now - 30 * 3600 ))'},{"user":"carol","since":'$(( now - 2 * 3600 ))'}]},
      {"id":8,"draft":true,"reviewers":[{"user":"dave","since":0}]},
      {"id":9,"draft":false,"reviewers":[{"user":"erin","since":'$(( now - 3600 ))'}]}]'
w=$(df_nudge_wait $prs $now 24)
t_eq "only reviewers past the limit" "$(jq -r '.[].reviewers[].user' <<<$w)" bob
t_eq "drafts are skipped" "$(jq -r 'map(.id) | join(",")' <<<$w)" 7
t_eq "the wait is kept for the message" "$(jq '.[0].reviewers[0].waited' <<<$w)" $(( 30 * 3600 ))
t_eq "a lower limit takes more" "$(jq -r '[.[].reviewers[].user] | join(",")' <<<$(df_nudge_wait $prs $now 1))" "bob,carol,erin"
t_eq "nothing waits: empty list" "$(df_nudge_wait $prs $now 99)" "[]"

print "ages"
t_eq "days and hours" "$(df_fmt_age $(( 30 * 3600 )))" "1d 6h"
t_eq "whole days" "$(df_fmt_age $(( 48 * 3600 )))" "2d"
t_eq "hours" "$(df_fmt_age $(( 5 * 3600 )))" "5h"
t_eq "minutes" "$(df_fmt_age 2700)" "45m"

print "mentions"
t_eq "default mention" "$(df_nudge_mention bob Bob)" "@bob"
NUDGE_MENTION='<@{user}> ({name})'
t_eq "the mention format is the user's" "$(df_nudge_mention bob 'Bob B')" "<@bob> (Bob B)"
NUDGE_MENTIONS=(bob '@bobby')
t_eq "a mapped chat handle wins" "$(df_nudge_mention bob Bob)" "@bobby"

rm -rf $HOME
t_done
