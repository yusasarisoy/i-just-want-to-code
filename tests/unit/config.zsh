#!/usr/bin/env zsh
# Config layering, JUSTCODE_SET, typeset -A survival, and trust gating.
# Each case runs in a fresh zsh so the lib's top-level loader runs again.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../skills/i-just-want-to-code/runtime}
DF_ROOT=${DF_ROOT:A}
T=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX")
export HOME=$T/home GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
mkdir -p $HOME/.config/justcode $T/repo
git -C $T/repo init -q

# q <expr>: print an expression after loading config inside $T/repo
q() { (cd $T/repo && DF_ROOT=$DF_ROOT zsh -c "source $DF_ROOT/lib/justcode-lib.zsh 2>/dev/null; print -r -- $1") }
trust() { print -r -- "$(shasum -a 256 $1 2>/dev/null || sha256sum $1)" | awk -v p=${1:A} '{print $1"  "p}' >>$HOME/.config/justcode/trusted }

print -r -- $'SHIP_MESSAGE=global\nMERGE_METHOD=merge\ntypeset -A TIME_TYPES=( code Dev review Review )' >$HOME/.config/justcode/config
t_eq "global layer loads" "$(q '$SHIP_MESSAGE')" global
t_eq "typeset -A in a config survives loading" "$(q '${TIME_TYPES[review]}')" Review
t_eq "map keeps every key" "$(q '${(ok)TIME_TYPES}')" "code review"

print -r -- $'SHIP_MESSAGE=team\ntouch '$T/marker >$T/repo/.justcode
t_eq "untrusted team file is ignored" "$(q '$SHIP_MESSAGE')" global
t_no "untrusted team file did not execute" test -e $T/marker
out=$(cd $T/repo && DF_ROOT=$DF_ROOT zsh -c "source $DF_ROOT/lib/justcode-lib.zsh" 2>&1)
t_has "untrusted warning printed" "$out" "is not trusted; review it, then run: justcode trust"
trust $T/repo/.justcode
t_eq "trusted team file wins over global" "$(q '$SHIP_MESSAGE')" team
t_ok "trusted team file executed" test -e $T/marker
rm -f $T/marker
print -r -- 'MERGE_METHOD=rebase' >>$T/repo/.justcode
t_eq "changed team file is untrusted again" "$(q '$SHIP_MESSAGE')" global
t_no "changed team file did not execute" test -e $T/marker

print -r -- 'SHIP_MESSAGE=local' >$T/repo/.justcode.local
trust $T/repo/.justcode.local
t_eq "trusted local file is the last file layer" "$(q '$SHIP_MESSAGE')" local
t_eq "JUSTCODE_SET beats every file" "$(JUSTCODE_SET='SHIP_MESSAGE=once;MERGE_METHOD=squash' q '$SHIP_MESSAGE-$MERGE_METHOD')" once-squash
t_eq "JUSTCODE_SET on an array sets one element" "$(JUSTCODE_SET='TARGET_BRANCHES=develop' q '${#TARGET_BRANCHES}:$TARGET_BRANCHES')" 1:develop
t_eq "JUSTCODE_SET refuses hooks" "$(JUSTCODE_SET='SHIP_PRE_HOOK=touch x' q '"[$SHIP_PRE_HOOK]"')" "[]"
t_eq "JUSTCODE_SET refuses maps" "$(JUSTCODE_SET='TIME_TYPES=x' q '${TIME_TYPES[code]}')" Dev
t_eq "JUSTCODE_SET ignores bad items" "$(JUSTCODE_SET='lower=x;;SHIP_LABELS' q '$SHIP_MESSAGE')" local

rm -rf $T
t_done
