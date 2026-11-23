# justcode shared library. Every command sources this file at its top level:
#   DF_ROOT=${0:A:h:h}; DF_CMD=ship; source $DF_ROOT/lib/justcode-lib.zsh
# Status lines go to stderr; data (JSON, URLs, keys) goes to stdout.

emulate zsh
setopt extended_glob pipe_fail
zmodload zsh/datetime

DF_VERSION=0.3.0
: ${DF_ROOT:=${${(%):-%x}:A:h:h}}
DF_LIB=$DF_ROOT/lib
typeset -gi DF_FAILED=0 DF_DRY=0

case ${JUSTCODE_OS:-$(uname -s)} in
  Darwin|macos) DF_OS=macos ;;
  *) DF_OS=linux ;;
esac
source $DF_LIB/os-$DF_OS.zsh

# ---------------------------------------------------------------- defaults
# Every key is listed in references/config.md and runtime/config.example.
REPO_DIR=''
TICKET_KEY_REGEX='[A-Za-z][A-Za-z0-9]+-[0-9]+'
TICKET_PREFIX=''
DEFAULT_START=09:00
JUSTCODE_NOTIFY=1
JUSTCODE_SOUNDS=1
NETWORK_WAIT_SECS=120
JUSTCODE_COMMANDS=(ship tpull tlog tcheck ticket build vpn)
GIT_REMOTE=origin

for __df_c in SHIP TPULL TLOG TCHECK TICKET BUILD; do
  typeset -ga ${__df_c}_DEFAULT_ARGS ${__df_c}_SKIP
  typeset -g ${__df_c}_PRE_HOOK='' ${__df_c}_POST_HOOK=''
done
unset __df_c

CODE_PROVIDER=github
CODE_API_URL=''
CODE_REPO=''
CODE_USER=''
CODE_TOKEN_SECRET=justcode-code-token
TARGET_BRANCHES=(main)
PROTECTED_BRANCHES=(main 'release/*')
DEFAULT_REVIEWERS=()
SHIP_LABELS=()
SHIP_PR_DESCRIPTION=''
MERGE_METHOD=squash
CI_NUDGE_JOB=''

TRACKER_PROVIDER=none
TRACKER_URL=''
TRACKER_USER=''
TRACKER_TOKEN_SECRET=justcode-tracker-token
STATUS_MAP=()
STATUS_ON_SHIP='In Review'
STATUS_VIA=''
STATUS_SKIP=()
TICKET_PROJECT=''
TICKET_BOARD=''
TICKET_DEFAULT_TYPE=''
TICKET_DEFAULT_PRIORITY=''
TICKET_DEFAULT_COMPONENT=''
TICKET_DEFAULT_SPRINT=''
TICKET_FIELDS=()
TICKET_ESTIMATE_TYPES=()
TICKET_PREFER_CUSTOM_FIELDS=1
TICKET_SEPARATOR='---8<---'

TIME_PROVIDER=none
TIME_URL=''
TIME_USER=''
TIME_TOKEN_SECRET=justcode-time-token
TIME_WORKSPACE=''
DAY_TARGET_HOURS=8
WORK_DAYS=(1 2 3 4 5)
typeset -gA TIME_TYPES=( code '' meeting '' )
TIME_TYPE_ATTRIBUTE=''
TLOG_DEFAULT_TYPE=code
SHIP_TIME_TYPE=code
TLOG_DEFAULT_COMMENT='Development'
TLOG_DAY_FULL_HOOK=''
DAY_LABELS=(Mon Tue Wed Thu Fri Sat Sun)

DEPLOY_PROVIDER=none
APP_NAME=''
BUILD_PROJECT_DIR=.
BUILD_OUTPUT_DIR=$HOME/Builds
BUILD_KINDS=(qa beta)
BUILD_CONFIG=Release
XCODE_PROJECT=''
XCODE_WORKSPACE=''
XCODE_SCHEME_PATTERN='{app} {env} {config}'
ASC_KEY_ID=''
ASC_ISSUER_ID=''
ASC_KEY_PATH=''
GRADLE_TASK_PATTERN=':app:bundle{Env}Release'
PLAY_PACKAGE=''
PLAY_TRACK=internal
PLAY_JSON_KEY_SECRET=justcode-play-json-key
DEPLOY_COMMAND=''

VPN_PROVIDER=none
VPN_HOSTS=()
VPN_STATUS_CMD=''
VPN_UP_CMD=''
VPN_DOWN_CMD=''
VPN_APP=''
VPN_WATCH_SECS=30

SHIP_MESSAGE='{url}'
SHIP_POST_TO=clipboard
BUILD_MESSAGE='{env} {version} ({build}) {kind} build uploaded'
BUILD_POST_TO=clipboard
TICKET_MESSAGE='{url}'
TICKET_POST_TO=clipboard
SLACK_WEBHOOK_SECRET=justcode-slack-webhook
TEAMS_WEBHOOK_SECRET=justcode-teams-webhook
WEBHOOK_SECRET=justcode-webhook
TEAMS_PAYLOAD=text

# Keys personal to one engineer; never allowed in the team layer.
DF_PERSONAL_KEYS=(CODE_USER TRACKER_USER TIME_USER REPO_DIR)
df_is_personal_key() { [[ $1 == *_SECRET ]] || (( ${DF_PERSONAL_KEYS[(Ie)$1]} )) }

# Every key, in documentation order (used by `justcode config` and setup).
__df_cmds=(SHIP TPULL TLOG TCHECK TICKET BUILD)
DF_KEYS=(
  REPO_DIR TICKET_KEY_REGEX TICKET_PREFIX DEFAULT_START JUSTCODE_NOTIFY JUSTCODE_SOUNDS
  NETWORK_WAIT_SECS JUSTCODE_COMMANDS GIT_REMOTE
  ${^__df_cmds}_{DEFAULT_ARGS,SKIP,PRE_HOOK,POST_HOOK}
  CODE_PROVIDER CODE_API_URL CODE_REPO CODE_USER CODE_TOKEN_SECRET TARGET_BRANCHES
  PROTECTED_BRANCHES DEFAULT_REVIEWERS SHIP_LABELS SHIP_PR_DESCRIPTION MERGE_METHOD CI_NUDGE_JOB
  TRACKER_PROVIDER TRACKER_URL TRACKER_USER TRACKER_TOKEN_SECRET STATUS_MAP STATUS_ON_SHIP
  STATUS_VIA STATUS_SKIP TICKET_PROJECT TICKET_BOARD TICKET_DEFAULT_TYPE TICKET_DEFAULT_PRIORITY
  TICKET_DEFAULT_COMPONENT TICKET_DEFAULT_SPRINT TICKET_FIELDS TICKET_ESTIMATE_TYPES
  TICKET_PREFER_CUSTOM_FIELDS TICKET_SEPARATOR
  TIME_PROVIDER TIME_URL TIME_USER TIME_TOKEN_SECRET TIME_WORKSPACE DAY_TARGET_HOURS WORK_DAYS
  TIME_TYPES TIME_TYPE_ATTRIBUTE TLOG_DEFAULT_TYPE SHIP_TIME_TYPE TLOG_DEFAULT_COMMENT
  TLOG_DAY_FULL_HOOK DAY_LABELS
  DEPLOY_PROVIDER APP_NAME BUILD_PROJECT_DIR BUILD_OUTPUT_DIR BUILD_KINDS BUILD_CONFIG
  XCODE_PROJECT XCODE_WORKSPACE XCODE_SCHEME_PATTERN ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH
  GRADLE_TASK_PATTERN PLAY_PACKAGE PLAY_TRACK PLAY_JSON_KEY_SECRET DEPLOY_COMMAND
  VPN_PROVIDER VPN_HOSTS VPN_STATUS_CMD VPN_UP_CMD VPN_DOWN_CMD VPN_APP VPN_WATCH_SECS
  SHIP_MESSAGE SHIP_POST_TO BUILD_MESSAGE BUILD_POST_TO TICKET_MESSAGE TICKET_POST_TO
  SLACK_WEBHOOK_SECRET TEAMS_WEBHOOK_SECRET WEBHOOK_SECRET TEAMS_PAYLOAD
)

# ---------------------------------------------------------------- output
df_ok()   { print -ru2 -- "✓ $*" }
df_skip() { print -ru2 -- "• $*" }
df_fail() { print -ru2 -- "✗ $*"; DF_FAILED=1 }
df_dry()  { print -ru2 -- "[dry-run] $*" }
df_info() { print -ru2 -- "  $*" }
df_die() {
  print -ru2 -- "✗ $*"
  df_notify justcode "${DF_CMD:-justcode}: $*" fail
  exit 1
}
df_unsupported() { df_skip "$1 not supported by $2"; return 3 }

# Ends a command: exit 1 when any step failed.
df_finish() {
  if (( DF_FAILED )); then
    df_notify justcode "${DF_CMD:-justcode} finished with errors" fail
    exit 1
  fi
  exit 0
}

# ---------------------------------------------------------------- trust (direnv model)
DF_CONFIG_DIR=${JUSTCODE_CONFIG_DIR:-$HOME/.config/justcode}
DF_GLOBAL_CONFIG=$DF_CONFIG_DIR/config
DF_TRUST_FILE=$DF_CONFIG_DIR/trusted
DF_TRUST_COPIES=$DF_CONFIG_DIR/trusted.d

# True when <file>'s current hash is recorded for its absolute path.
df_trusted() {
  local file=$1 hash
  [[ -f $file && -r $DF_TRUST_FILE ]] || return 1
  hash=$(df_sha256 "$file") || return 1
  grep -Fxq -- "$hash  ${file:A}" "$DF_TRUST_FILE"
}

# Copies <file> to a temp file and prints that path only if the copy is trusted
# for <file>'s path, so the bytes that were hashed are the bytes that get sourced.
df_trusted_copy() {
  local file=$1 tmp hash
  [[ -r $DF_TRUST_FILE ]] || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/justcode.XXXXXX") || return 1
  cp "$file" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1 }
  hash=$(df_sha256 "$tmp")
  if grep -Fxq -- "$hash  ${file:A}" "$DF_TRUST_FILE"; then print -r -- "$tmp"
  else rm -f "$tmp"; return 1
  fi
}

# ---------------------------------------------------------------- df_load_config
# Runs at top level (not in a function) so `typeset -A` in a config stays global.
typeset -ga DF_LAYERS DF_UNTRUSTED
typeset -gA DF_SET_KEYS
if [[ -r $DF_GLOBAL_CONFIG ]]; then
  if source "$DF_GLOBAL_CONFIG"; then DF_LAYERS+=("$DF_GLOBAL_CONFIG")
  else print -ru2 -- "✗ $DF_GLOBAL_CONFIG has errors"
  fi
fi
DF_REPO=$(git rev-parse --show-toplevel 2>/dev/null) || DF_REPO=${REPO_DIR/#\~/$HOME}
for __df_f in "$DF_REPO/.justcode" "$DF_REPO/.justcode.local"; do
  [[ -n $DF_REPO && -f $__df_f ]] || continue
  if __df_copy=$(df_trusted_copy "$__df_f"); then
    source "$__df_copy" || print -ru2 -- "✗ $__df_f has errors"
    rm -f "$__df_copy"
    DF_LAYERS+=("$__df_f")
  else
    DF_UNTRUSTED+=("$__df_f")
    print -ru2 -- "• $__df_f is not trusted; review it, then run: justcode trust"
  fi
done
unset __df_f __df_copy

# JUSTCODE_SET='KEY=value;KEY2=value': single values only, for one run.
df_apply_set() {
  local item k v
  for item in "${(@s:;:)JUSTCODE_SET}"; do
    [[ -z $item ]] && continue
    k=${item%%=*} v=${item#*=}
    if [[ $item != *=* || $k != [A-Z][A-Z0-9_]# ]]; then
      print -ru2 -- "✗ JUSTCODE_SET: ignoring '$item' (expected KEY=value)"; continue
    fi
    if [[ $k == (*_HOOK|*_CMD|DEPLOY_COMMAND) ]]; then
      print -ru2 -- "✗ JUSTCODE_SET: $k runs code; set it in a config file"; continue
    fi
    case ${(tP)k} in
      association*) print -ru2 -- "✗ JUSTCODE_SET: $k is a map; set it in a config file"; continue ;;
      array*) set -A $k "$v" ;;
      *) typeset -g "$k=$v" ;;
    esac
    DF_SET_KEYS[$k]=1
  done
}
df_apply_set

# Config key prefix of the running command: deploy-preview -> DEPLOY_PREVIEW.
DF_CMD_KEY=${${DF_CMD:-justcode}:u}
DF_CMD_KEY=${DF_CMD_KEY//[^A-Z0-9]/_}
# <CMD>_DEFAULT_ARGS, for: set -- "${DF_DEFAULT_ARGS[@]}" "$@"
typeset -ga DF_DEFAULT_ARGS
DF_DEFAULT_ARGS=(${(P)${:-${DF_CMD_KEY}_DEFAULT_ARGS}})

# ---------------------------------------------------------------- custom commands
DF_BUILTINS=(ship tpull tlog tcheck ticket build vpn justcode justcode-post)
DF_PERSONAL_COMMANDS=$DF_CONFIG_DIR/commands
DF_TEAM_COMMANDS=${DF_REPO:+$DF_REPO/.justcode-commands}

# ---------------------------------------------------------------- small helpers
df_step_off() { local -a s; s=(${(P)${:-${DF_CMD_KEY}_SKIP}}); (( ${s[(Ie)$1]} )) }

# Replaces every {key} in <template> with value; unknown placeholders stay.
df_fill() {
  local out=$1; shift
  while (( $# >= 2 )); do out=${out//"{$1}"/$2}; shift 2; done
  print -r -- "$out"
}

df_urlencode() { jq -rn --arg v "$1" '$v|@uri' }
df_html_escape() { local s=${1//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; print -r -- "${s//\"/&quot;}" }

df_status_for_branch() {
  local b=$1 i
  for (( i = 1; i < ${#STATUS_MAP}; i += 2 )); do
    [[ $b == ${~STATUS_MAP[i]} ]] && { print -r -- "$STATUS_MAP[i+1]"; return 0 }
  done
  print -r -- "$STATUS_ON_SHIP"
}

df_ticket_from_branch() {
  setopt local_options no_case_match
  [[ -n $1 && $1 =~ $TICKET_KEY_REGEX ]] || return 1
  print -r -- "${MATCH:u}"
}

# A bare number becomes PREFIX-number; anything else must match the key regex.
df_ticket_key() {
  if [[ $1 == [0-9]## && -n $TICKET_PREFIX ]]; then print -r -- "${TICKET_PREFIX:u}-$1"
  else df_ticket_from_branch "$1"
  fi
}

# Splits ticket draft files into DF_T_TITLES / DF_T_DESCS. Tickets are
# separated by a line exactly equal to TICKET_SEPARATOR (compared literally).
df_split_tickets() {
  typeset -ga DF_T_TITLES DF_T_DESCS
  DF_T_TITLES=() DF_T_DESCS=()
  local f line
  local -a block
  _df_flush() {
    while (( ${#block} )) && [[ -z ${block[1]//[[:space:]]/} ]]; do shift block; done
    while (( ${#block} )) && [[ -z ${block[-1]//[[:space:]]/} ]]; do block[-1]=(); done
    (( ${#block} )) || return 0
    DF_T_TITLES+=("$block[1]")
    DF_T_DESCS+=("${(pj:\n:)${(@)block[2,-1]}}")
    block=()
  }
  for f; do
    [[ -r $f ]] || { print -ru2 -- "✗ cannot read $f"; return 1 }
    block=()
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == "$TICKET_SEPARATOR" ]]; then _df_flush; else block+=("$line"); fi
    done <$f
    _df_flush
  done
  unfunction _df_flush
}

df_in_list() { local needle=$1; shift; (( ${@[(Ie)$needle]} )) }

# ---------------------------------------------------------------- time
df_now() { print -r -- ${JUSTCODE_NOW:-$EPOCHSECONDS} }
df_date() { strftime "$1" ${2:-$(df_now)} }
df_today() { df_date %Y-%m-%d }
df_epoch() { strftime -r '%Y-%m-%d %H:%M' "$1 ${2:-00:00}" }
df_add_days() { strftime %Y-%m-%d $(( $(df_epoch $1 12:00) + $2 * 24 * 3600 )) }
df_dow() { strftime %u $(df_epoch $1 12:00) }
df_iso_utc() { TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $1 }

df_to_min() {
  [[ $1 =~ '^([0-9]{1,2})(:([0-9]{2}))?$' ]] || return 1
  local h=$match[1] m=${match[3]:-0}
  (( 10#$h <= 23 && 10#$m <= 59 )) || return 1
  print $(( 10#$h * 60 + 10#$m ))
}
df_min_to_hhmm() { printf '%02d:%02d\n' $(( $1 / 60 )) $(( $1 % 60 )) }

# 9-10 | 09:30-12:00 -> "<start-min> <end-min>"; end must be after start.
df_parse_range() {
  [[ $1 == [^-]##-[^-]## ]] || return 1
  local s e
  s=$(df_to_min ${1%%-*}) && e=$(df_to_min ${1#*-}) || return 1
  (( e > s )) || return 1
  print "$s $e"
}

# 1h30m | 45m | 2h -> seconds (> 0).
df_parse_duration() {
  [[ -n $1 && $1 =~ '^(([0-9]+)h)?(([0-9]+)m)?$' ]] || return 1
  local secs=$(( ${match[2]:-0} * 3600 + ${match[4]:-0} * 60 ))
  (( secs > 0 )) || return 1
  print $secs
}

# today | yesterday | YYYY-MM-DD | DD.MM.YYYY -> YYYY-MM-DD
df_parse_day() {
  local d
  case $1 in
    ''|today) df_today; return ;;
    yesterday) df_add_days $(df_today) -1; return ;;
    [0-9](#c4)-[0-9](#c2)-[0-9](#c2)) d=$1 ;;
    [0-9](#c1,2).[0-9](#c1,2).[0-9](#c4))
      local -a p=("${(@s:.:)1}"); d=$(printf '%04d-%02d-%02d' $p[3] $(( 10#$p[2] )) $(( 10#$p[1] ))) ;;
    *) return 1 ;;
  esac
  local e; e=$(df_epoch $d 12:00 2>/dev/null) || return 1
  [[ $(strftime %Y-%m-%d $e) == $d ]] || return 1
  print -r -- $d
}

df_fmt_duration() {
  local s=${1:-0} h m out=''
  (( h = s / 3600, m = (s % 3600) / 60 ))
  (( h )) && out+="${h}h"
  (( m || ! h )) && out+="${m}m"
  print -r -- $out
}

# Monday and Sunday of the week <n> weeks back from today.
df_week_bounds() {
  local today=$(df_today) mon
  mon=$(df_add_days $today $(( -($(df_dow $today) - 1) - 7 * ${1:-0} )))
  print -r -- "$mon $(df_add_days $mon 6)"
}

# Two half-open minute ranges overlap.
df_overlaps() { (( $1 < $4 && $3 < $2 )) }

# Time types: short name <-> provider value, as JSON for jq.
df_time_types_json() {
  local k json='{}'
  for k in ${(k)TIME_TYPES}; do json=$(jq -c --arg k $k --arg v "$TIME_TYPES[$k]" '. + {($k): $v}' <<<$json); done
  print -r -- $json
}
df_time_type_value() { print -r -- "${TIME_TYPES[$1]-$1}" }
df_sum_secs() { jq '[.[].secs] | add // 0' }
df_group_days() { jq -r 'group_by(.day)[] | "\(.[0].day) \(map(.secs) | add)"' }

# ---------------------------------------------------------------- git remote
df_remote_url() { git config --get "remote.${GIT_REMOTE:-origin}.url" 2>/dev/null }

# https://host[:port]/a/b(.git) | ssh://git@host:2222/a/b | git@host:a/b -> "host path"
df_parse_remote() {
  local u=$1 host rpath  # never name a variable "path": zsh ties it to PATH
  case $u in
    (http|https|ssh|git)://*)
      local r=${u#*://}; host=${${r%%/*}##*@}; rpath=${r#*/}
      [[ $u == ssh://* || $u == git://* ]] && host=${host%%:*} ;;
    [^/]##@[^/:]##:*) host=${${u%%:*}#*@}; rpath=${u#*:} ;;
    *) return 1 ;;
  esac
  rpath=${${rpath%/}%.git}
  [[ -n $host && -n $rpath && $rpath != $u ]] || return 1
  print -r -- "$host $rpath"
}
df_repo_path() {
  [[ -n $CODE_REPO ]] && { print -r -- $CODE_REPO; return }
  local p; p=$(df_parse_remote "$(df_remote_url)") || return 1
  print -r -- ${p#* }
}
df_remote_host() { local p; p=$(df_parse_remote "$(df_remote_url)") || return 1; print -r -- ${p%% *} }
df_detect_code_provider() {
  case $1 in
    github.com|*github*) print github ;;
    bitbucket.org|*bitbucket*) print bitbucket ;;
    gitlab.com|*gitlab*) print gitlab ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------- providers
# Sources providers/<layer>/<name>.zsh for the configured provider.
df_use() {
  local layer=$1 name
  case $layer in
    code) name=$CODE_PROVIDER ;; tracker) name=$TRACKER_PROVIDER ;; time) name=$TIME_PROVIDER ;;
    deploy) name=$DEPLOY_PROVIDER ;; vpn) name=$VPN_PROVIDER ;;
    *) df_die "unknown provider layer '$layer'" ;;
  esac
  [[ $name == [a-z0-9-]## && -r $DF_ROOT/providers/$layer/$name.zsh ]] ||
    df_die "unknown $layer provider '$name' (see references for the supported ones)"
  source $DF_ROOT/providers/$layer/$name.zsh
}

# ---------------------------------------------------------------- secrets
# The only way justcode reads a secret. `gh` means: ask the GitHub CLI.
df_secret() {
  [[ -n $1 ]] || return 1
  local v
  if [[ $1 == gh ]]; then v=$(gh auth token 2>/dev/null)
  else v=$(df_os_secret "$1")
  fi
  v=${v%%$'\n'*}
  [[ -n $v ]] || return 1
  print -rn -- "$v"
}
df_secret_exists() { df_secret "$1" >/dev/null }
df_secret_store_cmd() { df_os_secret_store_cmd "$1" }

# ---------------------------------------------------------------- errors
# Provider errors are also written to a per-run file so a caller can report an
# error raised inside $( ) (where DF_HTTP_ERR would be lost).
DF_ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/justcode-err.XXXXXX")
autoload -Uz add-zsh-hook
_df_cleanup() { rm -f "$DF_ERR_FILE" }
add-zsh-hook zshexit _df_cleanup
df_err() { DF_HTTP_ERR=$1; print -r -- "$1" >|$DF_ERR_FILE }
df_last_error() { local e=$(<$DF_ERR_FILE); print -r -- "${e:-unknown error}" }

# Newest "<env> <version> <build>" from BUILD_OUTPUT_DIR/*/.uploaded.
df_last_uploaded() {
  local -a m=(${BUILD_OUTPUT_DIR/#\~/$HOME}/*/.uploaded(N.om))
  (( ${#m} )) && print -r -- "$(<$m[1])"
}

# ---------------------------------------------------------------- http
# df_http <secret-name> <bearer|basic|token-basic|header:Name|url|none> <METHOD> <url> [curl args...]
#   basic:       user from $DF_HTTP_USER, password = secret
#   token-basic: secret is already "user:password"
#   url:         the secret IS the URL (webhooks); pass '-' as <url>
# Secrets travel to curl on stdin (curl --config -), never in argv.
# Sets DF_HTTP_CODE, DF_HTTP_BODY, DF_HTTP_ERR; returns 0 only for 2xx.
df_http() {
  local secret=$1 style=$2 method=$3 url=$4 v='' cfg='' out rc
  shift 4
  DF_HTTP_CODE=000 DF_HTTP_BODY='' DF_HTTP_ERR=''
  : >|$DF_ERR_FILE
  if (( DF_DRY )) && [[ $method != GET ]] && ! df_http_is_read "$url" "$@"; then
    df_dry "blocked $method ${url%%\?*}"
    DF_HTTP_CODE=dry; return 0
  fi
  if [[ $style != none ]]; then
    v=$(df_secret "$secret") || { df_err "secret '$secret' not found (see: justcode doctor)"; return 1 }
    v=${${v//\\/\\\\}//\"/\\\"}
    case $style in
      bearer) cfg="header = \"Authorization: Bearer $v\"" ;;
      basic) cfg="user = \"${DF_HTTP_USER//\"/\\\"}:$v\"" ;;
      token-basic) cfg="user = \"$v\"" ;;
      header:*) cfg="header = \"${style#header:}: $v\"" ;;
      url) cfg="url = \"$v\""; url='' ;;
      *) df_err "unknown auth style '$style'"; return 1 ;;
    esac
  fi
  [[ $url == - ]] && url=''
  out=$(print -r -- "$cfg" | curl -q -sS --max-time ${DF_HTTP_TIMEOUT:-20} -X $method \
    -w '\n%{http_code}' -K - "$@" ${url:+"$url"} 2>/dev/null)
  rc=$?
  v=''
  DF_HTTP_CODE=${out##*$'\n'}
  DF_HTTP_BODY=${out%$'\n'*}
  [[ $out == *$'\n'* ]] || DF_HTTP_BODY=''
  if (( rc )); then
    df_err "request to ${url:-webhook} failed (curl exit $rc$([[ $rc == 28 ]] && print -n ', timeout'))"
    return 1
  fi
  [[ $DF_HTTP_CODE == 2[0-9][0-9] ]] && return 0
  df_err "HTTP $DF_HTTP_CODE$(df_http_message)"
  return 1
}

# POSTs that only read: GraphQL queries and search endpoints.
df_http_is_read() {
  local url=$1; shift
  [[ $url == */graphql && "$*" == *'"query"'* && "$*" != *mutation* ]] && return 0
  [[ $url == */search(|\?*) ]] && return 0
  return 1
}

df_http_message() {
  local m
  m=$(jq -r '(.message // .error_description // .error.message // .error // (.errorMessages // [])[0] // (.errors // [] | if type=="array" then .[0].message else (to_entries|map("\(.key): \(.value)")|join(", ")) end) // empty) | tostring' <<<$DF_HTTP_BODY 2>/dev/null)
  [[ -n $m && $m != null ]] && print -rn -- ": ${m[1,200]}"
}

# ---------------------------------------------------------------- network
df_url_hostport() { local r=${1#*://}; r=${r%%/*}; print -r -- ${r##*@} }

df_host_reachable() {
  local scheme=${1%%://*} hp=$(df_url_hostport $1) rc
  [[ $scheme == http(|s) ]] || scheme=https
  curl -q -s -o /dev/null --connect-timeout 5 --max-time 5 "$scheme://$hp/" 2>/dev/null
  rc=$?
  (( rc == 0 || rc == 51 || rc == 60 ))
}

df_host_needs_vpn() {
  [[ -n $VPN_PROVIDER && $VPN_PROVIDER != none ]] || return 1
  (( ${#VPN_HOSTS} )) || return 0
  local hp=$(df_url_hostport $1) h
  for h in $VPN_HOSTS; do
    [[ $hp == ${~h} || ${hp%:*} == ${~h} ]] && return 0
  done
  return 1
}

# Returns at once when <url>'s host is reachable or needs no VPN; otherwise
# starts the VPN and polls every 5 s for at most NETWORK_WAIT_SECS. Never hangs.
df_wait_for_host() {
  local url=$1 hp pid deadline left
  [[ -n $url ]] || return 0
  df_host_needs_vpn $url || return 0
  df_host_reachable $url && return 0
  hp=$(df_url_hostport $url)
  df_skip "$hp is not reachable; starting the VPN (waiting up to ${NETWORK_WAIT_SECS}s)"
  df_use vpn
  ( vpn_up ) >/dev/null 2>&1 &
  pid=$!
  deadline=$(( EPOCHSECONDS + NETWORK_WAIT_SECS ))
  while kill -0 $pid 2>/dev/null && (( EPOCHSECONDS < deadline )); do sleep 0.2; done
  while :; do
    if df_host_reachable $url; then df_ok "$hp is reachable"; return 0; fi
    left=$(( deadline - EPOCHSECONDS ))
    (( left > 0 )) || break
    sleep $(( left < 5 ? left : 5 ))
  done
  kill $pid 2>/dev/null
  df_fail "$hp is still not reachable after ${NETWORK_WAIT_SECS}s; connect the VPN (vpn up) and run again"
  return 1
}

# ---------------------------------------------------------------- hooks and messages
# Runs <CMD>_PRE_HOOK / <CMD>_POST_HOOK with zsh -c in the repo root.
df_hook() {
  local which=$1 var=${DF_CMD_KEY}_$1_HOOK rc
  local hook=${(P)var}
  [[ -n $hook ]] || return 0
  if (( DF_DRY )); then df_dry "${which:l} hook: $hook"; return 0; fi
  ( cd "${DF_REPO:-.}" && zsh -c "$hook" ); rc=$?
  if (( rc )); then
    [[ $which == PRE ]] && df_die "pre hook failed (exit $rc); nothing was sent"
    df_fail "post hook failed (exit $rc)"
    return 1
  fi
  df_ok "${which:l} hook"
}

# df_post <targets,comma,separated> <message> [html]
df_post() {
  local targets=$1 msg=$2 html=${3:-} t bad=0
  for t in ${(s:,:)targets// /}; do
    [[ $t == none ]] && continue
    if [[ $t != [a-z0-9-]## || ! -r $DF_ROOT/providers/post/$t.zsh ]]; then
      df_fail "unknown message target '$t'"; bad=1; continue
    fi
    if (( DF_DRY )); then df_dry "post to $t: $msg"; continue; fi
    if ( source $DF_ROOT/providers/post/$t.zsh && post_send "$msg" "$html" ); then df_ok "message sent to $t"
    else df_fail "message to $t failed (the work itself is done)"; bad=1
    fi
  done
  return $bad
}

