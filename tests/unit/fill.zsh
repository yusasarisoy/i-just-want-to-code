#!/usr/bin/env zsh
# tcheck --fill: the overlap rule shared with tlog, sessions from commits,
# trimming around existing entries, the daily cap, keys from branches.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../runtime}
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX"); cd $HOME
export GIT_CONFIG_GLOBAL=$HOME/gitconfig GIT_CONFIG_NOSYSTEM=1
source $DF_ROOT/lib/justcode-lib.zsh
source $DF_ROOT/lib/reports.zsh

print "overlap rule (tlog and --fill)"
entries='[{"id":"1","key":"ABC-1","start":"09:00","secs":3600},{"id":"2","key":"ABC-2","start":"13:30","secs":1800}]'
t_eq "a range inside an entry clashes" "$(df_time_clash $entries 570 580)" "ABC-1 at 09:00"
t_eq "the second entry is found too" "$(df_time_clash $entries 780 840)" "ABC-2 at 13:30"
t_no "touching ranges do not clash" df_time_clash $entries 600 660
t_no "the entry being moved is skipped" df_time_clash $entries 540 600 1
t_no "no entries, no clash" df_time_clash '[]' 540 600

print "proposals"
day=2026-03-03
at() { print -r -- "$(df_epoch $day $1) $2 sha$RANDOM" }
DAY_TARGET_HOURS=8 TCHECK_FILL_LEAD_MINUTES=60 TCHECK_FILL_GAP_MINUTES=120 TCHECK_FILL_ROUND_MINUTES=30 TCHECK_FILL_MIN_MINUTES=30
one='[{"id":"1","key":"ABC-1","start":"09:00","secs":3600}]'
c=$(at 10:05 ABC-123; at 10:40 ABC-123; at 11:20 ABC-123; at 11:50 ABC-123)
t_eq "a session is trimmed to start after the entry" "$(df_fill_blocks $day $one $c)" "600 720 ABC-123 4"
c2="$c"$'\n'"$(at 11:00 ABC-124)"
t_eq "a session that only overlaps is never proposed" "$(df_fill_blocks $day $one $c2)" "600 720 ABC-123 4"
c3=$(at 14:00 ABC-125; at 17:30 ABC-125)
t_eq "a long gap splits the sessions" "$(df_fill_blocks $day '[]' $c3)" $'780 840 ABC-125 1\n990 1050 ABC-125 1'
DAY_TARGET_HOURS=2
t_eq "the day never goes past the target" "$(df_fill_blocks $day $one $c)" "600 660 ABC-123 4"
DAY_TARGET_HOURS=1
t_eq "a full day gets nothing" "$(df_fill_blocks $day $one $c)" ""
DAY_TARGET_HOURS=8 TCHECK_FILL_MIN_MINUTES=180
t_eq "shorter than the minimum is dropped" "$(df_fill_blocks $day $one $c)" ""
TCHECK_FILL_MIN_MINUTES=30
t_eq "an early commit starts at midnight at the latest" "$(df_fill_blocks $day '[]' "$(at 00:10 ABC-9)")" "0 30 ABC-9 1"
TCHECK_FILL_ROUND_MINUTES=15 TCHECK_FILL_LEAD_MINUTES=0
t_eq "lead and rounding are the user's" "$(df_fill_blocks $day '[]' "$(at 10:20 ABC-9; at 10:50 ABC-9)")" "615 660 ABC-9 2"
TCHECK_FILL_ROUND_MINUTES=30 TCHECK_FILL_LEAD_MINUTES=60
out=$(df_fill_blocks $day $one "$c"$'\n'"$(at 15:00 ABC-7)")
for l in ${(f)out}; do
  f=(${=l}); t_no "proposal $f[3] $f[1]-$f[2] overlaps nothing" df_time_clash $one $f[1] $f[2]
done

print "ticket keys from branches"
git init -q repo; cd repo
git config user.email me@example.com; git config user.name me
GIT_AUTHOR_DATE="$day 08:00" GIT_COMMITTER_DATE="$day 08:00" git commit -q --allow-empty -m init
git checkout -q -b feature/ABC-123-login
GIT_AUTHOR_DATE="$day 10:00" GIT_COMMITTER_DATE="$day 10:00" git commit -q --allow-empty -m "Validate"
git checkout -q -b bugfix/abc-124-crash main 2>/dev/null || git checkout -q -b bugfix/abc-124-crash master
GIT_AUTHOR_DATE="$day 11:00" GIT_COMMITTER_DATE="$day 11:00" git commit -q --allow-empty -m "Fix crash"
git checkout -q -b misc
GIT_AUTHOR_DATE="$day 12:00" GIT_COMMITTER_DATE="$day 12:00" git commit -q --allow-empty -m "ABC-125 update the docs"
GIT_AUTHOR_DATE="$day 13:00" GIT_COMMITTER_DATE="$day 13:00" git commit -q --allow-empty -m "tidy up"
TARGET_BRANCHES=(main master)
got=$(df_rpt_keyed_commits $PWD $(df_epoch $day) $(df_epoch $(df_add_days $day 1)) | awk '{print $2}' | sort)
t_eq "keys from branches and subjects, commits without one left out" "$got" $'ABC-123\nABC-124\nABC-125'
t_lacks "the target branch's own commit has no key" "$got" init
git checkout -q feature/ABC-123-login
GIT_AUTHOR_DATE="$day 14:00" GIT_COMMITTER_DATE="$day 14:00" git commit -q --allow-empty -m "ABC-999 hotfix on the login branch"
key_of() { df_rpt_keyed_commits $PWD $(df_epoch $day) $(df_epoch $(df_add_days $day 1)) | awk -v t=$(df_epoch $day 14:00) '$1 == t {print $2}' }
t_eq "by default the branch key wins" "$(key_of)" ABC-123
TCHECK_FILL_KEY_FROM=(subject branch)
t_eq "the order is the user's" "$(key_of)" ABC-999
TCHECK_FILL_KEY_FROM=(branch)
t_eq "only branch keys when asked" "$(df_rpt_keyed_commits $PWD $(df_epoch $day) $(df_epoch $(df_add_days $day 1)) | awk '{print $2}' | sort -u)" $'ABC-123\nABC-124'
TCHECK_FILL_KEY_FROM=(branch subject)

cd $HOME/..; rm -rf $HOME
t_done
