#!/usr/bin/env zsh
# Runs every unit test and persona scenario; prints a summary table.
# Exit status is non-zero when any test fails. Usage: tests/run.zsh [-v] [filter]
emulate zsh
setopt extended_glob
zmodload zsh/datetime
here=${0:A:h}
verbose=0
[[ $1 == -v ]] && { verbose=1; shift }
filter=${1:-}

for t in git curl jq python3; do (( $+commands[$t] )) || { print -r -- "missing tool: $t"; exit 2 }; done

typeset -a rows
typeset -i total_fail=0 total_pass=0 total_skip=0
for f in $here/unit/*.zsh(N) $here/personas/*.zsh(N); do
  name=${f:h:t}/${f:t:r}
  [[ -n $filter && $name != *$filter* ]] && continue
  start=$EPOCHSECONDS
  out=$(zsh $f 2>&1); rc=$?
  secs=$(( EPOCHSECONDS - start ))
  res=${${(M)${(f)out}:#RESULT *}[-1]}
  p=${${res#*pass=}%% *} x=${${res#*fail=}%% *} s=${${res#*skip=}%% *}
  [[ -z $res ]] && { p=0 x=1 s=0 }
  (( rc && x == 0 )) && x=1
  (( total_pass += p, total_fail += x, total_skip += s ))
  rows+=("$(printf '%-28s %5s %5s %5s %5ss' $name $p $x $s $secs)")
  if (( verbose || x )); then print -r -- "== $name"; print -r -- "${(F)${(M)${(f)out}:#*(FAIL|skip)*}}"; (( verbose )) && print -r -- "$out"; fi
done

print
printf '%-28s %5s %5s %5s %6s\n' suite pass fail skip time
printf '%s\n' ${rows}
printf '%-28s %5s %5s %5s\n' TOTAL $total_pass $total_fail $total_skip
(( total_fail == 0 ))
