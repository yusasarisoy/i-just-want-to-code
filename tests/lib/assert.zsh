# Minimal assertions. Each test file ends with t_done, which prints
# "RESULT pass=N fail=N skip=N" and exits 1 on any failure.
typeset -gi T_PASS=0 T_FAIL=0 T_SKIP=0

t_pass() { (( T_PASS++ )); print -r -- "  ok    $1" }
t_failed() { (( T_FAIL++ )); print -r -- "  FAIL  $1${2:+: $2}" }
t_skip() { (( T_SKIP++ )); print -r -- "  skip  $1${2:+ ($2)}" }

# t_eq <name> <got> <want>
t_eq() { [[ $2 == $3 ]] && t_pass $1 || t_failed $1 "got '$2', want '$3'" }
# t_ok <name> <command...>   passes when the command succeeds
t_ok() { local n=$1; shift; "$@" >/dev/null 2>&1 && t_pass $n || t_failed $n "command failed: $*" }
# t_no <name> <command...>   passes when the command fails
t_no() { local n=$1; shift; "$@" >/dev/null 2>&1 && t_failed $n "command succeeded: $*" || t_pass $n }
# t_has <name> <haystack> <needle>
t_has() { [[ $2 == *$3* ]] && t_pass $1 || t_failed $1 "'$3' not found in: ${2[1,600]}" }
t_lacks() { [[ $2 != *$3* ]] && t_pass $1 || t_failed $1 "'$3' unexpectedly found in: ${2[1,600]}" }

t_done() {
  print -r -- "RESULT pass=$T_PASS fail=$T_FAIL skip=$T_SKIP"
  (( T_FAIL == 0 ))
  exit $?
}
