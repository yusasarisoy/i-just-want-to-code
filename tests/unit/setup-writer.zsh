#!/usr/bin/env zsh
# The setup writer: in-place rewrite that keeps comments and unknown keys.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../skills/i-just-want-to-code/runtime}
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX"); cd $HOME
source $DF_ROOT/lib/justcode-lib.zsh
source $DF_ROOT/lib/setup.zsh

f=$HOME/config
cat >$f <<'EOF'
# my notes
CODE_PROVIDER=gitlab   # we moved last year
MY_OWN_KEY='keep me'
TARGET_BRANCHES=(
  main
  develop
)
typeset -A TIME_TYPES=( code Dev )
EOF
orig=$(<$f; print x)

print "no change"
DF_NEW_ORDER=() DF_NEW=()
CODE_PROVIDER=gitlab; _sa_record CODE_PROVIDER "$(df_cfg_statement CODE_PROVIDER)"
t_eq "unchanged value records nothing" ${#DF_NEW_ORDER} 0
df_cfg_apply $f $DF_NEW_ORDER
t_eq "re-run without changes is byte-identical" "$(<$f; print x)" "$orig"

print "one key"
CODE_PROVIDER=github
df_cfg_rewrite $f CODE_PROVIDER "$(df_cfg_statement CODE_PROVIDER)"
t_eq "only that line changed, comment kept" "$(diff <(print -rn -- ${orig%x}) $f | grep -c '^[<>]')" 2
t_has "new value with its trailing comment" "$(<$f)" "CODE_PROVIDER=github   # we moved last year"
t_has "comments survive" "$(<$f)" "# my notes"
t_has "unknown keys survive" "$(<$f)" "MY_OWN_KEY='keep me'"

print "arrays and maps"
TARGET_BRANCHES=(main 'release/next')
df_cfg_rewrite $f TARGET_BRANCHES "$(df_cfg_statement TARGET_BRANCHES)"
t_has "multi-line array replaced by one line" "$(<$f)" "TARGET_BRANCHES=(main release/next)"
t_lacks "old array lines removed" "$(<$f)" "develop"
typeset -A TIME_TYPES=( code 'Dev work' meeting Meet )
df_cfg_rewrite $f TIME_TYPES "$(df_cfg_statement TIME_TYPES)"
t_has "typeset -A block written" "$(<$f)" "typeset -A TIME_TYPES=( code 'Dev work' meeting Meet )"
SHIP_MESSAGE='{title}: {url}'
df_cfg_rewrite $f SHIP_MESSAGE "$(df_cfg_statement SHIP_MESSAGE)"
t_has "missing key appended" "$(tail -1 $f)" "SHIP_MESSAGE='{title}: {url}'"
t_ok "file stays valid zsh" zsh -n $f
got=$(zsh -c "source $f; print -r -- \"\$TIME_TYPES[code]|\$SHIP_MESSAGE|\${#TARGET_BRANCHES}\"")
t_eq "file sources back to the same values" "$got" "Dev work|{title}: {url}|2"

print "empty and new files"
rm -f $HOME/new
df_cfg_rewrite $HOME/new CODE_USER "CODE_USER=alice"
t_eq "new file gets one statement and a newline" "$(<$HOME/new; print x)" $'CODE_USER=alice\nx'

print "team layer keeps personal keys out"
t_ok "CODE_USER is personal" df_is_personal_key CODE_USER
t_ok "*_SECRET is personal" df_is_personal_key SLACK_WEBHOOK_SECRET
t_ok "TRACKER_USER is personal" df_is_personal_key TRACKER_USER
t_ok "TIME_USER is personal" df_is_personal_key TIME_USER
t_no "TARGET_BRANCHES is a team key" df_is_personal_key TARGET_BRANCHES

rm -rf $HOME
t_done
