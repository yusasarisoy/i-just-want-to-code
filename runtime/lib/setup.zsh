# justcode setup: terminal wizard. Sourced by `justcode setup`.
# The writer functions (df_cfg_*) are pure and unit-tested.

DF_SETUP_SECTIONS=(commands code tracker time build network messages)

# ---------------------------------------------------------------- writer
# Statement for KEY from the current shell value: KEY=v, KEY=(a b), typeset -A KEY=( k v ).
df_cfg_statement() {
  local k=$1 x out
  case ${(tP)k} in
    association*)
      local -A h=("${(@kvP)k}"); out="typeset -A $k=("
      for x in ${(ok)h}; do out+=" ${(q-)x} ${(q-)h[$x]}"; done
      print -r -- "$out )" ;;
    array*) local -a arr=("${(@P)k}"); print -r -- "$k=(${(j: :)${(@q-)arr}})" ;;
    *) print -r -- "$k=${(q-)${(P)k}}" ;;
  esac
}

# Replaces the statement that assigns KEY in FILE (single or multi-line) with
# STMT, keeping a trailing comment; appends when KEY is absent. Every other
# byte of the file is preserved.
df_cfg_rewrite() {
  local file=$1 key=$2 stmt=$3 content='' i j start=0 end=0 comment=''
  [[ -f $file ]] && { content="$(cat -- $file; print -n x)"; content=${content%x} }
  local -a lines=("${(@f)content}")
  local re="^[[:space:]]*((typeset|export)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*)?$key="
  for (( i = 1; i <= ${#lines}; i++ )); do
    [[ $lines[i] =~ $re ]] || continue
    start=$i end=$i
    if [[ $lines[i] == *=\(* && $lines[i] != *\)[[:space:]]#(\#*|) ]]; then
      for (( j = i + 1; j <= ${#lines}; j++ )); do
        [[ $lines[j] == *\)[[:space:]]#(\#*|) ]] && { end=$j; break }
      done
    fi
  done
  if (( start )); then
    (( start == end )) && [[ $lines[start] =~ '[^\\]([[:space:]]+#[^"'\'']*)$' ]] && comment=$match[1]
    lines[start,end]=("$stmt$comment")
  elif [[ -z $content ]]; then
    lines=("$stmt" '')
  elif [[ $lines[-1] == '' ]]; then
    lines[-1]=("$stmt" '')
  else
    lines+=("$stmt" '')
  fi
  print -rn -- "${(pj:\n:)lines}" >|$file
}

# Applies DF_NEW (KEY -> statement) to FILE in DF_NEW_ORDER.
df_cfg_apply() {
  local file=$1 k
  shift
  for k; do df_cfg_rewrite $file $k "$DF_NEW[$k]"; done
}

# ---------------------------------------------------------------- prompts
typeset -gA DF_NEW
typeset -ga DF_NEW_ORDER

_sa_help() {
  local f
  for f in $DF_ROOT/docs/config.md $DF_ROOT/../plugin/skills/i-just-want-to-code/references/config.md; do
    [[ -r $f ]] || continue
    local line=$(grep -m1 -F "| \`$1\` |" $f)
    [[ -n $line ]] && { line=${line%|*}; print -r -- "  ${${line##*|}## }"; return }
  done
  print -r -- "  (no help for $1)"
}

# Reads one answer into REPLY; '?' prints help and asks again; Enter = default.
_sa_read() {
  local key=$1 prompt=$2 def=$3
  while :; do
    print -rn -- "$prompt${def:+ [$def]}: "
    read -r REPLY || { print; print -ru2 -- "✗ input ended; nothing was written"; exit 1 }
    [[ $REPLY == '?' ]] && { _sa_help $key; continue }
    [[ -z $REPLY ]] && REPLY=$def
    return 0
  done
}

# Default: the value a layer sets, else the detected one, else the built-in default.
_sa_default() {
  local k=$1 det=$2 f
  for f in $DF_LAYERS; do grep -Eq "^[[:space:]]*((typeset|export)[^=]*[[:space:]]+)?$k=" $f && { print -r -- "${(j: :)${(P)k}}"; return }; done
  [[ -n $det ]] && { print -r -- $det; return }
  print -r -- "${(j: :)${(P)k}}"
}

# Records KEY when its new statement differs from the current one.
_sa_record() {
  local k=$1 old=$2 new=$(df_cfg_statement $1)
  [[ $new == $old ]] && return 0
  DF_NEW[$k]=$new
  df_in_list $k $DF_NEW_ORDER || DF_NEW_ORDER+=($k)
}

_sa_text() {  # _sa_text KEY "Question" [detected]
  local k=$1 old=$(df_cfg_statement $1)
  _sa_read $k "$2" "$(_sa_default $k "$3")"
  typeset -g "$k=$REPLY"
  _sa_record $k "$old"
}

_sa_list() {  # space-separated list
  local k=$1 old=$(df_cfg_statement $1)
  _sa_read $k "$2 (space separated, - for none)" "$(_sa_default $k "$3")"
  [[ $REPLY == - ]] && set -A $k || set -A $k ${(z)REPLY}
  set -A $k ${(Q)${(P)k}}
  _sa_record $k "$old"
}

_sa_choice() {  # _sa_choice KEY "Question" detected opt...
  local k=$1 q=$2 det=$3 old=$(df_cfg_statement $1) def i
  shift 3
  local -a opts=($@)
  def=$(_sa_default $k "$det")
  if (( $+commands[fzf] )) && [[ -z $JUSTCODE_NO_FZF ]]; then
    REPLY=$(print -rl -- $opts | fzf --prompt="$q > " --query="$def" --select-1 --height=10) || REPLY=$def
  else
    print -r -- "$q"
    for (( i = 1; i <= ${#opts}; i++ )); do
      print -r -- "  $i) $opts[i]$([[ $opts[i] == $def ]] && print '  (current)')"
    done
    while :; do
      _sa_read $k "choice" "$def"
      [[ $REPLY == [0-9]## ]] && (( REPLY >= 1 && REPLY <= ${#opts} )) && REPLY=$opts[REPLY]
      df_in_list "$REPLY" $opts && break
      print -r -- "  '$REPLY' is not one of the choices. For a tool justcode has no provider for, ask Claude to add one."
    done
  fi
  typeset -g "$k=$REPLY"
  _sa_record $k "$old"
}

_sa_multi() {  # comma-separated numbers or names; stored as KEY=(a b) or KEY=a,b (scalar)
  local k=$1 q=$2 old=$(df_cfg_statement $1) i x def
  shift 2
  local -a opts=($@) picked
  def=$(_sa_default $k)
  def=${${def//,/ }// ##/,}
  print -r -- "$q"
  for (( i = 1; i <= ${#opts}; i++ )); do print -r -- "  $i) $opts[i]"; done
  while :; do
    _sa_read $k "choices, comma separated" "$def"
    picked=()
    for x in ${(s:,:)REPLY// /}; do
      [[ $x == [0-9]## ]] && (( x >= 1 && x <= ${#opts} )) && x=$opts[x]
      df_in_list "$x" $opts || { print -r -- "  '$x' is not one of the choices"; continue 2 }
      picked+=($x)
    done
    break
  done
  if [[ ${(tP)k} == array* ]]; then set -A $k $picked
  else typeset -g "$k=${(j:,:)picked}"
  fi
  _sa_record $k "$old"
}

_sa_yes() {  # _sa_yes "Question" Y|N
  print -rn -- "$1 [$([[ $2 == Y ]] && print 'Y/n' || print 'y/N')]: "
  read -r REPLY || { print; print -ru2 -- "✗ input ended; nothing was written"; exit 1 }
  [[ -z $REPLY ]] && REPLY=$2
  [[ $REPLY == [yY]* ]]
}

# Asks for a secret entry name and offers to store it; never sees the value.
_sa_secret() {
  local k=$1
  _sa_text $k "$2: name of the secret-store entry"
  local name=${(P)k} cmd=$(df_secret_store_cmd ${(P)k})
  if df_secret_exists $name; then print -r -- "  ✓ $name is already stored"; return; fi
  print -r -- "  store it with: $cmd"
  if _sa_yes "  Run that now? The OS asks for the value; justcode never sees it." N; then
    if [[ $DF_OS == macos ]]; then security add-generic-password -a "$USER" -s "$name" -w
    else secret-tool store --label="$name" service "$name"
    fi
  fi
}

# ---------------------------------------------------------------- detection
_sd_detect() {
  typeset -g DET_HOST='' DET_CODE='' DET_API='' DET_BRANCH='' DET_KEY='' DET_PREFIX='' DET_TITLE='' DET_DEPLOY='' DET_WS='' DET_PROJ=''
  DET_HOST=$(df_remote_host 2>/dev/null)
  DET_CODE=$(df_detect_code_provider "$DET_HOST")
  case $DET_CODE in
    github) [[ $DET_HOST == github.com ]] && DET_API=https://api.github.com || DET_API=https://$DET_HOST/api/v3 ;;
    gitlab) DET_API=https://$DET_HOST/api/v4 ;;
    bitbucket) DET_API=https://api.bitbucket.org/2.0 ;;
  esac
  DET_BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null)
  DET_KEY=$(df_ticket_from_branch "$DET_BRANCH")
  DET_PREFIX=${DET_KEY%-*}
  DET_TITLE=$(git log -1 --format=%s 2>/dev/null)
  if [[ -n $DF_REPO ]]; then
    local -a ws=($DF_REPO/*.xcworkspace(N/)) pj=($DF_REPO/*.xcodeproj(N/))
    DET_WS=${ws[1]:t} DET_PROJ=${pj[1]:t}
    if [[ -n $DET_WS$DET_PROJ ]]; then DET_DEPLOY=testflight
    elif [[ -x $DF_REPO/gradlew ]]; then DET_DEPLOY=play
    fi
  fi
  print -r -- "Detected:"
  print -r -- "  OS: $DF_OS, shell: zsh $ZSH_VERSION"
  [[ -n $DET_CODE ]] && print -r -- "  Code host: $DET_CODE (from the remote $DET_HOST)"
  [[ -n $DET_KEY ]] && print -r -- "  Ticket key: $DET_KEY (from the branch $DET_BRANCH)"
  [[ -n $DET_DEPLOY ]] && print -r -- "  Build: $DET_DEPLOY (from the project files)"
  local t found=()
  for t in gh glab fastlane xcodebuild warp-cli tailscale wg-quick openvpn fzf; do (( $+commands[$t] )) && found+=($t); done
  (( ${#found} )) && print -r -- "  Tools: ${(j:, :)found}"
  print
}

# ---------------------------------------------------------------- sections
_ss_commands() {
  _sa_multi JUSTCODE_COMMANDS "Which commands do you want?" ship tpull tlog tcheck ticket build vpn standup release-notes nudge
  _sa_text DEFAULT_START "Default start time for durations (HH:MM)"
}

_ss_code() {
  _sa_choice CODE_PROVIDER "Code host" "$DET_CODE" github gitlab bitbucket
  local api=$DET_API
  [[ $CODE_PROVIDER != $DET_CODE ]] && api=''
  _sa_text CODE_API_URL "API URL (empty = derive from the remote)" "$api"
  _sa_text CODE_USER "Your account name on the code host (the token must belong to it)"
  _sa_secret CODE_TOKEN_SECRET "Code host token"
  _sa_list TARGET_BRANCHES "Target branches"
  _sa_list DEFAULT_REVIEWERS "Default reviewers"
  _sa_choice MERGE_METHOD "Merge method for auto-merge" '' squash merge rebase
}

_ss_tracker() {
  _sa_choice TRACKER_PROVIDER "Issue tracker" '' jira-cloud jira-dc linear none
  [[ $TRACKER_PROVIDER == none ]] && return
  local def=''
  [[ $TRACKER_PROVIDER == linear ]] && def=https://api.linear.app
  _sa_text TRACKER_URL "Tracker URL" "$def"
  [[ $TRACKER_PROVIDER == jira-cloud ]] && _sa_text TRACKER_USER "Your Atlassian account email"
  _sa_secret TRACKER_TOKEN_SECRET "Tracker token"
  _sa_text TICKET_PROJECT "Project or team key for new tickets" "$DET_PREFIX"
  _sa_text TICKET_PREFIX "Prefix for bare ticket numbers" "$DET_PREFIX"
  _sa_text STATUS_ON_SHIP "Status to move a ticket to on ship"
}

_ss_time() {
  _sa_choice TIME_PROVIDER "Time tracker" '' tempo-cloud tempo-dc toggl clockify none
  [[ $TIME_PROVIDER == none ]] && return
  [[ $TIME_PROVIDER == tempo-dc ]] && _sa_text TIME_URL "Jira base URL for Tempo" "$TRACKER_URL"
  case $TIME_PROVIDER in
    tempo-cloud) _sa_text TIME_USER "Your Atlassian account ID" ;;
    tempo-dc) _sa_text TIME_USER "Your Tempo worker key" ;;
    clockify) _sa_text TIME_USER "Your Clockify user id (empty = token owner)" ;;
  esac
  _sa_secret TIME_TOKEN_SECRET "Time tracker token"
  [[ $TIME_PROVIDER == (toggl|clockify) ]] && _sa_text TIME_WORKSPACE "Workspace id"
  _sa_text DAY_TARGET_HOURS "Hours per workday"
}

_ss_build() {
  _sa_choice DEPLOY_PROVIDER "Build and distribution" "$DET_DEPLOY" testflight play command none
  case $DEPLOY_PROVIDER in
    none) return ;;
    testflight)
      _sa_text APP_NAME "App name" "${${DET_WS:-$DET_PROJ}%.*}"
      if [[ -n $DET_WS || -n $XCODE_WORKSPACE ]]; then _sa_text XCODE_WORKSPACE "Xcode workspace" "$DET_WS"
      else _sa_text XCODE_PROJECT "Xcode project" "$DET_PROJ"
      fi
      _sa_text XCODE_SCHEME_PATTERN "Scheme pattern ({app} {env} {config})" ;;
    play)
      _sa_text GRADLE_TASK_PATTERN "Gradle task pattern ({Env} {env} {config})"
      _sa_text PLAY_PACKAGE "Application id"
      _sa_text PLAY_TRACK "Play track"
      _sa_secret PLAY_JSON_KEY_SECRET "Play service account JSON" ;;
    command) _sa_text DEPLOY_COMMAND "Build-and-upload command" ;;
  esac
  _sa_text BUILD_OUTPUT_DIR "Folder for build logs"
  _sa_list BUILD_KINDS "Build kinds"
}

_ss_network() {
  _sa_choice VPN_PROVIDER "VPN" '' command none
  [[ $VPN_PROVIDER == none ]] && return
  print -r -- "  presets for common clients: references/network.md"
  _sa_text VPN_UP_CMD "Connect command"
  _sa_text VPN_DOWN_CMD "Disconnect command"
  _sa_text VPN_STATUS_CMD "Status command (exit 0 = connected)"
  _sa_list VPN_HOSTS "Hosts that need the VPN (empty = all tracker and code hosts)"
}

_sa_template() {  # _sa_template KEY "what" template...
  local k=$1 what=$2 old=$(df_cfg_statement $1) t preview
  shift 2
  local -a opts=($@ custom)
  df_in_list "${(P)k}" $opts || opts=("${(P)k}" $opts)
  while :; do
    local -a tmp=($opts)
    _sa_choice $k "$what message template" '' $tmp
    if [[ ${(P)k} == custom ]]; then
      _sa_read $k "your template" "$(print -r -- $opts[1])"
      typeset -g "$k=$REPLY"
    fi
    local url=https://git.example.com/pr/1
    [[ $k == TICKET_MESSAGE ]] && url="https://jira.example.com/browse/${DET_KEY:-ABC-123}"
    preview=$(df_fill "${(P)k}" url "$url" title "${DET_TITLE:-Add login screen}" \
      branch "${DET_BRANCH:-feature/ABC-123-login}" ticket "${DET_KEY:-ABC-123}" key "${DET_KEY:-ABC-123}" \
      ticket_url "https://jira.example.com/browse/${DET_KEY:-ABC-123}" target main \
      env test version 1.2.3 build 7 kind "${BUILD_KINDS[1]:-qa}" config Release)
    print -r -- "  preview: $preview"
    _sa_yes "  Keep?" Y && break
  done
  DF_NEW_ORDER=(${DF_NEW_ORDER:#$k}); unset "DF_NEW[$k]"
  _sa_record $k "$old"
}

_ss_messages() {
  _sa_template SHIP_MESSAGE ship '{url}' '{title}: {url}' 'Ready for review: {ticket} {title} {url}'
  _sa_multi SHIP_POST_TO "Where does the ship message go?" clipboard slack teams webhook none
  _sa_template BUILD_MESSAGE build '{env} {version} ({build}) {kind} build uploaded' 'New {kind} build {version} ({build}) on {env}'
  _sa_multi BUILD_POST_TO "Where does the build message go?" clipboard slack teams webhook none
  _sa_template TICKET_MESSAGE ticket '{url}' '{key}: {title} {url}'
  _sa_multi TICKET_POST_TO "Where do new ticket links go?" clipboard slack teams webhook none
  local all=",$SHIP_POST_TO,$BUILD_POST_TO,$TICKET_POST_TO,"
  [[ $all == *,slack,* ]] && _sa_secret SLACK_WEBHOOK_SECRET "Slack webhook URL"
  if [[ $all == *,teams,* ]]; then
    _sa_secret TEAMS_WEBHOOK_SECRET "Teams webhook URL"
    _sa_choice TEAMS_PAYLOAD "Teams payload" '' text adaptive-card
  fi
  [[ $all == *,webhook,* ]] && _sa_secret WEBHOOK_SECRET "Webhook URL"
}

# ---------------------------------------------------------------- main
df_setup_main() {
  local layer=global dry=0 a file
  local -a sections=()
  while (( $# )); do
    case $1 in
      --layer) layer=$2; shift ;;
      --layer=*) layer=${1#*=} ;;
      -n) dry=1 ;;
      -h|--help) print -r -- "usage: justcode setup [section...] [--layer global|team|local] [-n]
  sections: ${(j: :)DF_SETUP_SECTIONS}"; return 0 ;;
      *) df_in_list $1 $DF_SETUP_SECTIONS || df_die "unknown section '$1' (${(j: :)DF_SETUP_SECTIONS})"; sections+=($1) ;;
    esac
    shift
  done
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -r -- "justcode setup needs a terminal; ask Claude to run the setup instead, or edit the file with: justcode edit"
    return 1
  fi
  case $layer in
    global) file=$DF_GLOBAL_CONFIG ;;
    team|local) [[ -n $DF_REPO ]] || df_die "--layer $layer needs a git repository"
      [[ $layer == team ]] && file=$DF_REPO/.justcode || file=$DF_REPO/.justcode.local ;;
    *) df_die "--layer is global, team or local" ;;
  esac
  (( ${#sections} )) || sections=($DF_SETUP_SECTIONS)
  print -r -- "justcode setup: writing to $file ($layer layer). Enter keeps the value in brackets, ? explains a question."
  print
  _sd_detect
  local s
  for s in $sections; do
    print -r -- "== $s"
    _ss_$s
    print
  done

  local -a here=() global_keys=() k
  for k in $DF_NEW_ORDER; do
    if [[ $layer == team ]] && df_is_personal_key $k; then
      print -ru2 -- "• $k is personal; it goes to the global config, not the team file"
      global_keys+=($k)
    else
      here+=($k)
    fi
  done
  if (( ! ${#DF_NEW_ORDER} )); then df_skip "nothing changed"; return 0; fi

  local f tmp old
  local -A plan=( $file "$here" )
  (( ${#global_keys} )) && plan[$DF_GLOBAL_CONFIG]="$global_keys"
  for f in ${(k)plan}; do
    [[ -n $plan[$f] ]] || continue
    tmp=$(mktemp "${TMPDIR:-/tmp}/justcode-setup.XXXXXX")
    [[ -f $f ]] && cp $f $tmp || : >|$tmp
    [[ -s $tmp ]] || print -r -- "# justcode config ($([[ $f == $DF_GLOBAL_CONFIG ]] && print global || print $layer)). Keys: references/config.md" >|$tmp
    df_cfg_apply $tmp ${=plan[$f]}
    print -r -- "---- $f"
    old=/dev/null; [[ -f $f ]] && old=$f
    diff -u $old $tmp | tail -n +3
    if (( dry )); then rm -f $tmp; continue; fi
    mkdir -p ${f:h}
    # Backups go to the personal config dir, never into the repo where they could be committed.
    [[ -f $f ]] && mkdir -p $DF_CONFIG_DIR/backups &&
      cp $f $DF_CONFIG_DIR/backups/${${f#$HOME/}//\//_}.$(df_date %Y%m%d-%H%M%S)
    cp $tmp $f; rm -f $tmp
    df_ok "wrote $f"
    if [[ $f == $DF_REPO/.justcode.local ]] && ! grep -qxF .justcode.local $DF_REPO/.gitignore 2>/dev/null; then
      print .justcode.local >>$DF_REPO/.gitignore; df_ok "added .justcode.local to .gitignore"
    fi
    [[ $f != $DF_GLOBAL_CONFIG ]] && df_skip "$f must be trusted before it is used: justcode trust"
  done
  (( dry )) && { df_dry "nothing written"; return 0 }
  print
  $DF_ROOT/bin/justcode doctor $sections
  return 0
}
