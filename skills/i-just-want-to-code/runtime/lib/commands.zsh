# Custom commands: personal ones in ~/.config/justcode/commands/<name>, team ones
# in <repo>/.justcode-commands/<name> (run only when trusted). Sourced by `justcode`.

df_cmd_valid_name() { [[ $1 == [a-z][a-z0-9-]# ]] && ! df_in_list "$1" $DF_BUILTINS }

# Prints "<team|personal> <path>" for the active definition of <name>.
# Returns 2 for a bad or built-in name, 4 when only an untrusted team file exists, 1 when none.
df_cmd_resolve() {
  local n=$1 t='' p=$DF_PERSONAL_COMMANDS/$1
  df_cmd_valid_name $n || return 2
  [[ -n $DF_TEAM_COMMANDS ]] && t=$DF_TEAM_COMMANDS/$n
  if [[ -n $t && -f $t ]] && df_trusted $t; then print -r -- "team $t"; return 0; fi
  [[ -f $p ]] && { print -r -- "personal $p"; return 0 }
  [[ -n $t && -f $t ]] && return 4
  return 1
}

# justcode run <name> [args]: runs the trusted bytes of a team file (verified copy)
# or the personal file, with JUSTCODE_ROOT pointing at this runtime.
df_cmd_run() {
  local n=$1 r rc kind file tmp; shift
  r=$(df_cmd_resolve $n); rc=$?
  case $rc in
    2) df_die "'$n' is not a valid custom command name (built-in names cannot be shadowed)" ;;
    4) df_skip "$n is not trusted; review it, then run: justcode trust"; exit 1 ;;
    1) df_die "no custom command '$n' (justcode command list)" ;;
  esac
  kind=${r%% *} file=${r#* }
  if [[ $kind == team ]]; then
    tmp=$(df_trusted_copy $file) || { df_skip "$n is not trusted; review it, then run: justcode trust"; exit 1 }
    JUSTCODE_ROOT=$DF_ROOT zsh $tmp "$@"; rc=$?
    rm -f $tmp
  else
    JUSTCODE_ROOT=$DF_ROOT zsh $file "$@"; rc=$?
  fi
  return $rc
}

df_cmd_list() {
  local f n state
  print -r -- "personal ($DF_PERSONAL_COMMANDS):"
  for f in $DF_PERSONAL_COMMANDS/*(N.); do print -r -- "  ${f:t}"; done
  [[ -n $DF_TEAM_COMMANDS ]] || return 0
  print -r -- "team ($DF_TEAM_COMMANDS):"
  for f in $DF_TEAM_COMMANDS/*(N.); do
    df_trusted $f && state=trusted || state='NOT trusted'
    n=${f:t}
    [[ -f $DF_PERSONAL_COMMANDS/$n && $state != trusted ]] && state+=', personal one is active'
    print -r -- "  $n ($state)"
  done
}

# Static check of the contract. Prints one ✗ per problem; returns 1 on any.
df_cmd_check() {
  local file=$1 i line code bad=0 j guarded
  [[ -r $file ]] || { df_fail "cannot read $file"; return 1 }
  local -a lines=("${(@f)$(<$file)}")
  local -a src=()
  for line in $lines; do [[ $line == [[:space:]]#\#* ]] && src+=('') || src+=("$line"); done
  for (( i = 1; i <= ${#src}; i++ )); do
    code=$src[i]
    [[ -z $code ]] && continue
    if [[ $code =~ '(^|[^A-Za-z0-9_-])(curl|wget)([^A-Za-z0-9_-]|$)' ]]; then df_fail "${file:t}:$i: raw curl/wget; use df_http"; bad=1; fi
    if [[ $code =~ '(^|[^A-Za-z0-9_-])eval([^A-Za-z0-9_-]|$)' ]]; then df_fail "${file:t}:$i: eval is not allowed"; bad=1; fi
    if [[ $code =~ '(^|[^A-Za-z0-9_-])(security|secret-tool)[[:space:]]|find-generic-password|gh auth token' ]]; then
      df_fail "${file:t}:$i: direct secret read; use df_secret"; bad=1
    fi
    if [[ $code =~ 'df_http .*(POST|PUT|PATCH|DELETE)|git push|tracker_(move|create|set_estimate)|time_(create|update)|code_(create|update)_pr' ]]; then
      guarded=0
      for (( j = i; j >= 1 && j >= i - 6; j-- )); do [[ $src[j] == *DF_DRY* ]] && { guarded=1; break }; done
      (( guarded )) || { df_fail "${file:t}:$i: write not guarded by the dry-run flag (DF_DRY)"; bad=1 }
    fi
  done
  if ! [[ ${(F)src} =~ "getopts '?:?[A-Za-z:]*n" && ${(F)src} == *DF_DRY=1* ]]; then
    df_fail "${file:t}: no -n handling (getopts with n setting DF_DRY=1)"; bad=1
  fi
  [[ ${(F)src} == *justcode-lib.zsh* ]] || { df_fail "${file:t}: does not source lib/justcode-lib.zsh"; bad=1 }
  (( bad )) || df_ok "${file:t}: follows the command contract"
  return $bad
}

df_cmd_new() {
  local n=$1 scope=${2:-personal} dir file key
  df_cmd_valid_name "$n" || df_die "'$n' is not allowed: use lowercase letters, digits and dashes, and no built-in name (${(j:, :)DF_BUILTINS})"
  if [[ $scope == team ]]; then
    [[ -n $DF_TEAM_COMMANDS ]] || df_die "not inside a git repository"
    dir=$DF_TEAM_COMMANDS
  else
    dir=$DF_PERSONAL_COMMANDS
  fi
  file=$dir/$n
  [[ -e $file ]] && df_die "$file already exists"
  key=${${n:u}//[^A-Z0-9]/_}
  mkdir -p $dir
  df_cmd_skeleton $n $key >$file
  chmod +x $file
  df_ok "created $file"
  df_info "settings: ${key}_URL, ${key}_TOKEN_SECRET, ${key}_DEFAULT_ARGS, ${key}_SKIP, ${key}_PRE_HOOK, ${key}_POST_HOOK"
  df_info "check it:  justcode command check $n"
  df_info "dry run:   justcode run $n -n"
  if [[ $scope == team ]]; then
    df_skip "team command: commit it; every teammate (you too) must review it and run: justcode trust"
  else
    df_info "run install.sh again to put '$n' on your PATH, or use: justcode run $n"
  fi
}

df_cmd_skeleton() {
  local n=$1 k=$2
  print -r -- "#!/usr/bin/env zsh
# $n: describe in one line what this command does.
#
# Lib API (the only allowed way to do these things):
#   df_http SECRET STYLE METHOD URL [curl args]  every network call; sets DF_HTTP_BODY, DF_HTTP_CODE, DF_HTTP_ERR
#   df_secret NAME                                read a secret from the OS store
#   df_wait_for_host URL                          VPN-aware wait that never hangs
#   df_fill TEMPLATE key value ...                replace {key} placeholders
#   df_step_off STEP                              true when STEP is listed in ${k}_SKIP
#   df_hook PRE|POST                              run ${k}_PRE_HOOK / ${k}_POST_HOOK
#   df_ok / df_skip / df_fail / df_dry / df_die   one status line per step
#   df_post TARGETS MESSAGE                       clipboard, slack, teams, webhook
#   df_finish                                     exit 1 when any step failed
# Settings come from the config layers: ${k}_URL, ${k}_TOKEN_SECRET,
# ${k}_DEFAULT_ARGS, ${k}_SKIP, ${k}_PRE_HOOK, ${k}_POST_HOOK.
DF_ROOT=\${JUSTCODE_ROOT:-\$HOME/.local/share/justcode}
DF_CMD=$n
source \$DF_ROOT/lib/justcode-lib.zsh || exit 1

usage() {
  print -r -- \"usage: $n [-n]
  -n  dry run: read everything, write nothing\"
}

set -- \"\${DF_DEFAULT_ARGS[@]}\" \"\$@\"
while getopts ':nh' o; do
  case \$o in
    n) DF_DRY=1 ;;
    h) usage; exit 0 ;;
    *) df_die \"unknown option -\$OPTARG ($n -h)\" ;;
  esac
done
shift \$(( OPTIND - 1 ))

url=\${${k}_URL:-}
secret=\${${k}_TOKEN_SECRET:-justcode-$n-token}
[[ -n \$url ]] || df_die \"${k}_URL is not set (justcode edit global)\"
df_wait_for_host \"\$url\" || df_finish
df_hook PRE

# Read step: runs in a dry run too.
if df_http \"\$secret\" bearer GET \"\$url/status\"; then df_ok \"status read\"
else df_fail \"status: \$DF_HTTP_ERR\"; df_finish
fi

# Write step: never runs in a dry run.
if df_step_off write; then df_skip \"write skipped\"
elif (( DF_DRY )); then df_dry \"POST \$url/items\"
elif df_http \"\$secret\" bearer POST \"\$url/items\" -H 'Content-Type: application/json' --data-binary '{}'; then df_ok \"item created\"
else df_fail \"create: \$DF_HTTP_ERR\"
fi

df_hook POST
df_finish"
}
