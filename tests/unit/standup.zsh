#!/usr/bin/env zsh
# standup helpers: template lines, empty sections, the commits of one day.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../runtime}
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX"); cd $HOME
export GIT_CONFIG_GLOBAL=$HOME/gitconfig GIT_CONFIG_NOSYSTEM=1
source $DF_ROOT/lib/justcode-lib.zsh
source $DF_ROOT/lib/reports.zsh

print "template lines"
rows='[{"key":"ABC-1","title":"Login","duration":"1h"},{"key":"ABC-2","title":"Crash","duration":"30m"}]'
t_eq "one line per row" "$(df_rpt_lines '- {key} {title} ({duration})' $rows)" $'- ABC-1 Login (1h)\n- ABC-2 Crash (30m)'
t_eq "an empty template leaves the part out" "$(df_rpt_lines '' $rows)" ''
t_eq "unknown placeholder stays" "$(df_rpt_lines '{key} {nope}' '[{"key":"A-1"}]')" "A-1 {nope}"
t_eq "numbers are filled as text" "$(df_rpt_lines '{n} commits' '[{"n":4}]')" "4 commits"
t_eq "a value with braces is not filled again" "$(df_rpt_lines '{a} {b}' '[{"a":"{b}","b":"x"}]')" "{b} x"
t_eq "no rows, no lines" "$(df_rpt_lines '- {key}' '[]')" ''

print "sections"
t_eq "empty section shows the none text" "$(df_rpt_section none '')" none
t_eq "blank lines count as empty" "$(df_rpt_section none $'\n ')" none
t_eq "lines are kept" "$(df_rpt_section none '- a')" "- a"
t_eq "the none text is the user's" "$(df_rpt_section 'nothing, all good' '')" "nothing, all good"

print "commits of one day"
git init -q repo
git -C repo config user.email me@example.com; git -C repo config user.name me
c() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="${3:-$1}" git -C repo commit -q --allow-empty -m "$2" }
c '2026-03-02 09:00' 'Before the day'
c '2026-03-03 10:15' 'Validate the password'
c '2026-03-03 16:40' 'Show the error' '2026-03-05 08:00'
GIT_AUTHOR_EMAIL=other@example.com c '2026-03-03 11:00' 'Not mine'
c '2026-03-04 09:00' 'After the day'
from=$(df_epoch 2026-03-03) to=$(df_epoch 2026-03-04)
subjects=$(df_rpt_commits $HOME/repo $from $to | cut -f3 | sort)
t_eq "only the author's commits of that day" "$subjects" $'Show the error\nValidate the password'
COMMIT_AUTHOR=other@example.com
t_eq "COMMIT_AUTHOR picks the author" "$(df_rpt_commits $HOME/repo $from $to | cut -f3)" "Not mine"
COMMIT_AUTHOR=''
t_eq "repos default to the current one" "$(DF_REPO=$HOME/repo df_rpt_repos)" $HOME/repo
t_eq "configured repos win, ~ expanded" "$(df_rpt_repos '~/a' /b)" "$HOME/a
/b"

rm -rf $HOME
t_done
