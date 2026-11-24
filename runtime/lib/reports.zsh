# Helpers for standup, tcheck --fill, release-notes and nudge. Pure where it
# can be (unit-tested in tests/unit), git reads otherwise; no network here.
# Templates belong to the user: an unset key keeps its documented default, an
# empty key means "leave this part out".

# df_rpt_lines <template> <json-array>: one filled line per object; every key of
# the object is a placeholder ({key}, {title}, ...). Empty template: no lines.
df_rpt_lines() {
  [[ -n $1 ]] || return 0
  # One pass, so a value that contains "{other}" is never filled again.
  jq -r --arg t "$1" '.[] | . as $o | $t | gsub("\\{(?<k>[A-Za-z0-9_]+)\\}";
    .k as $k | if ($o | has($k)) then ($o[$k] | if type == "string" then . else tostring end) else "{\($k)}" end)' <<<$2
}

# df_rpt_section <none-text> <lines>: the lines, or <none-text> when there are none.
df_rpt_section() {
  local none=$1 body=$2
  [[ -n ${body//[[:space:]]/} ]] && print -r -- "$body" || print -r -- "$none"
}

# df_rpt_author <repo>: COMMIT_AUTHOR, else that repo's git user.email.
df_rpt_author() {
  [[ -n $COMMIT_AUTHOR ]] && { print -r -- $COMMIT_AUTHOR; return }
  git -C "$1" config user.email 2>/dev/null
}

# df_rpt_repos <configured...>: the given repos (~ expanded), or the current one.
df_rpt_repos() {
  local r
  (( $# )) || { [[ -n $DF_REPO ]] && print -r -- $DF_REPO; return 0 }
  for r; do print -r -- ${r/#\~/$HOME}; done
}

# df_rpt_commits <repo> <from-epoch> <to-epoch>: "<author-epoch>\t<sha>\t<subject>" for
# the author's non-merge commits on any ref, authored in [from, to).
df_rpt_commits() {
  local repo=$1 from=$2 to=$3 author
  author=$(df_rpt_author $repo)
  [[ -n $author ]] || return 1
  # --since filters on the committer date, which is never before the author date.
  git -C $repo log --all --no-merges -F --author="$author" --since="@$from" \
    --format=$'%at\t%H\t%s' 2>/dev/null | awk -F'\t' -v f=$from -v t=$to '$1 >= f && $1 < t'
}

# df_rpt_keyed_commits <repo> <from> <to>: "<epoch> <KEY> <sha>" per commit. The
# ticket key comes from the sources in TCHECK_FILL_KEY_FROM, first match wins:
# branch = the branch the commit was made on (commits only on that branch, not on
# TARGET_BRANCHES); subject = a key in the commit subject. No key: left out.
df_rpt_keyed_commits() {
  local repo=$1 from=$2 to=$3 author ref name key b line t sha subj src
  author=$(df_rpt_author $repo)
  [[ -n $author ]] || return 1
  local -a not=() refs order=(${TCHECK_FILL_KEY_FROM:-branch subject})
  local -A by_branch by_subject when
  for b in $TARGET_BRANCHES; do
    for ref in refs/heads/$b refs/remotes/$GIT_REMOTE/$b; do
      git -C $repo rev-parse -q --verify $ref >/dev/null && not+=($ref)
    done
  done
  refs=(${(f)"$(git -C $repo for-each-ref --format='%(refname)' refs/heads refs/remotes 2>/dev/null)"})
  for ref in $refs; do
    name=${ref#refs/heads/}; name=${name#refs/remotes/*/}
    key=$(df_ticket_from_branch $name) || continue
    for line in ${(f)"$(git -C $repo log --no-merges -F --author="$author" --since="@$from" --format='%at %H' $ref ${not:+--not} $not 2>/dev/null)"}; do
      (( ${line%% *} >= from && ${line%% *} < to )) || continue
      (( ${+by_branch[${line#* }]} )) || by_branch[${line#* }]=$key
    done
  done
  for line in ${(f)"$(df_rpt_commits $repo $from $to)"}; do
    t=${line%%$'\t'*} sha=${${line#*$'\t'}%%$'\t'*} subj=${line#*$'\t'*$'\t'}
    when[$sha]=$t
    key=$(df_ticket_from_branch "$subj") && by_subject[$sha]=$key
  done
  for sha in ${(k)when}; do
    key=''
    for src in $order; do
      case $src in
        branch) key=${by_branch[$sha]:-} ;;
        subject) key=${by_subject[$sha]:-} ;;
      esac
      [[ -n $key ]] && break
    done
    [[ -n $key ]] && print -r -- "$when[$sha] $key $sha"
  done
}

# ---------------------------------------------------------------- tcheck --fill
# df_fill_blocks <day> <entries-json> <commit-lines>: proposals "<start-min> <end-min> <KEY> <commits>".
# A session is a run of one ticket's commits with gaps of at most TCHECK_FILL_GAP_MINUTES;
# it starts TCHECK_FILL_LEAD_MINUTES before its first commit and ends at its last one,
# rounded out to TCHECK_FILL_ROUND_MINUTES. Each proposal is the longest part of a
# session that overlaps no entry and no earlier proposal (df_time_clash), shorter than
# TCHECK_FILL_MIN_MINUTES is dropped, and the day never goes past DAY_TARGET_HOURS.
df_fill_blocks() {
  local day=$1 entries=$2 commits=$3 line key t m
  integer lead=${TCHECK_FILL_LEAD_MINUTES:-0} gap=${TCHECK_FILL_GAP_MINUTES:-0}
  integer round=${TCHECK_FILL_ROUND_MINUTES:-1} min=${TCHECK_FILL_MIN_MINUTES:-1}
  (( round > 0 )) || round=1
  (( min > 0 )) || min=1
  integer day0=$(df_epoch $day)
  integer budget=$(( DAY_TARGET_HOURS * 60 - $(jq '[.[].secs] | add // 0' <<<$entries) / 60 ))
  (( budget > 0 )) || return 0

  # sessions per key, in minutes of the day
  local -a sess=()
  local -A last first count
  for line in ${(f)"$(print -r -- $commits | sort -n)"}; do
    [[ -n $line ]] || continue
    t=${line%% *} key=${${line#* }%% *}
    m=$(( (t - day0) / 60 ))
    if (( ${+last[$key]} )) && (( m - last[$key] <= gap )); then
      last[$key]=$m; (( count[$key]++ ))
    else
      (( ${+last[$key]} )) && sess+=("$first[$key] $last[$key] $key $count[$key]")
      first[$key]=$m last[$key]=$m count[$key]=1
    fi
  done
  for key in ${(k)last}; do sess+=("$first[$key] $last[$key] $key $count[$key]"); done
  sess=(${(f)"$(print -rl -- $sess | sort -n -k1,1)"})

  local busy=$entries c bl
  integer s e bs be ps best_s best_e
  for line in $sess; do
    [[ -n $line ]] || continue
    local -a f=(${=line})
    s=$(( f[1] - lead )) e=$f[2] key=$f[3] c=$f[4]
    (( s = s / round * round, e = (e + round - 1) / round * round ))
    (( e > s )) || (( e = s + round ))
    (( s < 0 )) && s=0
    (( e > 1440 )) && e=1440
    # free parts of [s, e): walk the busy ranges in order
    best_s=0 best_e=0 ps=$s
    for bl in ${(f)"$(jq -r '.[] | ((.start|split(":")|(.[0]|tonumber)*60+(.[1]|tonumber))) as $a | "\($a) \($a + (.secs/60|floor))"' <<<$busy | sort -n)"}; do
      bs=${bl% *} be=${bl#* }
      (( be <= ps || bs >= e )) && continue
      (( bs > ps && bs - ps > best_e - best_s )) && { best_s=$ps; best_e=$bs }
      (( be > ps )) && ps=$be
    done
    (( e > ps && e - ps > best_e - best_s )) && { best_s=$ps; best_e=$e }
    (( best_e - best_s > budget )) && best_e=$(( best_s + budget ))
    (( best_e - best_s >= min )) || continue
    df_time_clash "$busy" $best_s $best_e >/dev/null && continue  # never propose an overlap
    print -r -- "$best_s $best_e $key $c"
    (( budget -= best_e - best_s ))
    busy=$(jq -c --arg st $(df_min_to_hhmm $best_s) --argjson n $(( (best_e - best_s) * 60 )) --arg k $key \
      '. + [{id:"proposed", key:$k, start:$st, secs:$n}]' <<<$busy)
    (( budget > 0 )) || break
  done
}

# ---------------------------------------------------------------- release-notes
# df_rn_keys <text>: every ticket key in <text>, upper-cased, once, in order.
df_rn_keys() {
  setopt local_options no_case_match
  local rest=$1
  local -a out=()
  while [[ $rest =~ $TICKET_KEY_REGEX ]]; do
    df_in_list ${MATCH:u} $out || out+=(${MATCH:u})
    rest=${rest[$(( MEND + 1 )),-1]}
  done
  print -rl -- $out
}

# df_rn_group <type>: the first RELEASE_NOTES_GROUPS name whose comma-separated
# globs match <type> (case-insensitive); RELEASE_NOTES_NO_TICKET_GROUP when none does.
df_rn_group() {
  setopt local_options no_case_glob extended_glob
  local t=$1 i g
  for (( i = 1; i < ${#RELEASE_NOTES_GROUPS}; i += 2 )); do
    for g in ${(s:,:)RELEASE_NOTES_GROUPS[i+1]}; do
      [[ $t == (#i)${~g} ]] && { print -r -- $RELEASE_NOTES_GROUPS[i]; return }
    done
  done
  print -r -- $RELEASE_NOTES_NO_TICKET_GROUP
}

# df_rn_render <from> <to> <items-json>: markdown. Items are {group, line}; groups
# come in RELEASE_NOTES_GROUPS order, then any other group; empty groups are left out.
df_rn_render() {
  local from=$1 to=$2 items=$3 g lines head i
  local -a order=() out=()
  [[ $(jq length <<<$items) == 0 ]] && return 0  # nothing to say: no header either
  for (( i = 1; i < ${#RELEASE_NOTES_GROUPS}; i += 2 )); do order+=($RELEASE_NOTES_GROUPS[i]); done
  for g in ${(f)"$(jq -r '.[].group' <<<$items)"}; do df_in_list "$g" $order || order+=("$g"); done
  local date=$(df_today)
  head=$(df_fill "$RELEASE_NOTES_HEADER" from "$from" to "$to" date $date)
  [[ -n $head ]] && out+=("$head" '')
  for g in $order; do
    lines=$(jq -r --arg g "$g" '.[] | select(.group == $g) | .line' <<<$items)
    [[ -n $lines ]] || continue
    head=$(df_fill "$RELEASE_NOTES_GROUP_HEADER" group "$g" from "$from" to "$to" date $date)
    [[ -n $head ]] && out+=("$head")
    out+=("$lines" '')
  done
  (( ${#out} )) && [[ -z $out[-1] ]] && out[-1]=()
  (( ${#out} )) && print -rl -- "${out[@]}"
}

# ---------------------------------------------------------------- nudge
# df_fmt_age <secs>: 2d 3h | 5h | 45m
df_fmt_age() {
  integer s=$1 d h
  (( d = s / (24 * 3600), h = (s % (24 * 3600)) / 3600 ))
  if (( d )); then print -r -- "${d}d$( (( h )) && print -n " ${h}h")"; return; fi
  df_fmt_duration $s
}

# df_nudge_mention <user> [name]: NUDGE_MENTIONS[user], else NUDGE_MENTION filled.
df_nudge_mention() {
  if (( ${+NUDGE_MENTIONS[$1]} )); then print -r -- $NUDGE_MENTIONS[$1]
  else df_fill "$NUDGE_MENTION" user "$1" name "${2:-$1}"
  fi
}

# df_nudge_wait <prs-json> <now> <after-hours>: the non-draft PRs with their reviewers
# that have waited at least <after-hours>; each reviewer gets "waited" (secs).
df_nudge_wait() {
  jq -c --argjson now $2 --argjson h $3 '[.[] | select(.draft | not)
    | .reviewers = [.reviewers[] | . + {waited: ($now - .since)} | select(.waited >= $h * 3600)]
    | select(.reviewers | length > 0)]' <<<$1
}
