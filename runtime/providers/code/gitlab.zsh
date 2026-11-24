# Code host provider: GitLab (REST v4, gitlab.com or self-hosted).
# Auth: PRIVATE-TOKEN header from CODE_TOKEN_SECRET (scope: api).

_gl_api() {
  [[ -n $CODE_API_URL ]] && { print -r -- ${CODE_API_URL%/}; return }
  print -r -- "https://$(df_remote_host)/api/v4"
}
_gl_pid() { df_urlencode "$(code_repo_path)" }
_gl() { local m=$1 p=$2; shift 2; df_http "$CODE_TOKEN_SECRET" header:PRIVATE-TOKEN $m "$(_gl_api)$p" "$@" }
_gl_json() { _gl $1 $2 -H 'Content-Type: application/json' --data-binary "$3" }
_gl_norm='{id:.iid, url:.web_url, title, draft:(.draft // .work_in_progress // false),
  reviewers:[.reviewers[]?.username], reviewer_ids:[.reviewers[]?.id],
  merge_state:(.detailed_merge_status // .merge_status // "unknown"),
  has_pipeline:(.head_pipeline != null), description:(.description // "")}'
_gl_mr() { _gl GET "/projects/$(_gl_pid)/merge_requests/$1" && jq -c "$_gl_norm" <<<$DF_HTTP_BODY }
_gl_strip_draft() {
  setopt local_options no_case_match
  local t=$1
  [[ $t =~ '^(\[draft\]|\(draft\)|draft:|draft -) *' ]] && t=${t[$(( ${#MATCH} + 1 )),-1]}
  print -r -- $t
}

code_repo_path() { df_repo_path }

code_whoami() { _gl GET /user || return 1; jq -r '.username // empty' <<<$DF_HTTP_BODY }

code_find_pr() {
  _gl GET "/projects/$(_gl_pid)/merge_requests?state=opened&source_branch=$(df_urlencode $1)" || return 1
  jq -c ".[0] // empty | $_gl_norm" <<<$DF_HTTP_BODY
}

code_create_pr() {
  local title=$3; [[ $4 == 1 ]] && title="Draft: $title"
  _gl_json POST "/projects/$(_gl_pid)/merge_requests" \
    "$(jq -nc --arg s $1 --arg t $2 --arg ti "$title" '{source_branch:$s, target_branch:$t, title:$ti}')" || return 1
  jq -c "$_gl_norm" <<<$DF_HTTP_BODY
}

code_update_pr() {
  local id=$1 a put='{}'; shift
  for a; do
    case $a in
      title=*) put=$(jq -c --arg v "${a#title=}" '.title=$v' <<<$put) ;;
      description=*)
        local cur; cur=$(_gl_mr $id) || return 1
        [[ -z $(jq -r .description <<<$cur) ]] && put=$(jq -c --arg v "${a#description=}" '.description=$v' <<<$put) ;;
      labels+=*) put=$(jq -c --arg v "${a#labels+=}" '.add_labels=$v' <<<$put) ;;
    esac
  done
  [[ $put == '{}' ]] || _gl_json PUT "/projects/$(_gl_pid)/merge_requests/$id" "$put"
}

code_set_draft() {
  local mr title; mr=$(_gl_mr $1) || return 1
  [[ $(jq -r .draft <<<$mr) == $([[ $2 == 1 ]] && print true || print false) ]] && return 0
  title=$(_gl_strip_draft "$(jq -r .title <<<$mr)")
  [[ $2 == 1 ]] && title="Draft: $title"
  _gl_json PUT "/projects/$(_gl_pid)/merge_requests/$1" "$(jq -nc --arg t "$title" '{title:$t}')"
}

code_add_reviewers() {
  local id=$1 mr u uid; shift
  mr=$(_gl_mr $id) || return 1
  local -a cur=(${(f)"$(jq -r '.reviewers[]' <<<$mr)"}) ids=(${(f)"$(jq -r '.reviewer_ids[]' <<<$mr)"})
  local added=0
  for u; do
    df_in_list $u $cur && continue
    _gl GET "/users?username=$(df_urlencode $u)" || return 1
    uid=$(jq -r '.[0].id // empty' <<<$DF_HTTP_BODY)
    [[ -n $uid ]] || { df_skip "gitlab: no user '$u'"; continue }
    ids+=($uid); added=1
  done
  (( added )) || return 0
  _gl_json PUT "/projects/$(_gl_pid)/merge_requests/$id" "$(jq -nc '{reviewer_ids:($ARGS.positional|map(tonumber))}' --args $ids)"
}

# 0 = set to merge when the pipeline succeeds; 2 = would merge now or state unknown.
code_auto_merge() {
  local mr state try
  for try in 1 2 3 4 5; do  # a new MR is still being checked and may have no pipeline yet: ask again, at most ~8 s
    mr=$(_gl_mr $1) || return 1
    state=$(jq -r .merge_state <<<$mr)
    [[ $state == (unchecked|checking|preparing|unknown|) || $(jq -r .has_pipeline <<<$mr) == false ]] || break
    (( try < 5 )) && sleep 2
  done
  if [[ $state == (mergeable|can_be_merged|unchecked|checking|preparing|unknown|) || $(jq -r .has_pipeline <<<$mr) == false ]]; then
    df_skip "auto-merge not enabled: merge state is '$state' (would merge immediately or unknown)"
    return 2
  fi
  _gl_json PUT "/projects/$(_gl_pid)/merge_requests/$1/merge" \
    "$(jq -nc --argjson sq $([[ $MERGE_METHOD == squash ]] && print true || print false) \
      '{auto_merge:true, merge_when_pipeline_succeeds:true, squash:$sq}')"
}

# Plays then cancels the manual job CI_NUDGE_JOB so the pipeline leaves "skipped".
code_ci_nudge() {
  local branch=$1 sha=$2 pid jid
  _gl GET "/projects/$(_gl_pid)/pipelines?sha=$sha&ref=$(df_urlencode $branch)" || return 1
  pid=$(jq -r '.[0].id // empty' <<<$DF_HTTP_BODY)
  [[ -n $pid ]] || { df_skip "no pipeline for $sha yet"; return 3 }
  _gl GET "/projects/$(_gl_pid)/pipelines/$pid/jobs?scope%5B%5D=manual" || return 1
  jid=$(jq -r --arg n "$CI_NUDGE_JOB" 'map(select(.name==$n))[0].id // empty' <<<$DF_HTTP_BODY)
  [[ -n $jid ]] || { df_skip "no manual job '$CI_NUDGE_JOB' in pipeline $pid"; return 3 }
  _gl POST "/projects/$(_gl_pid)/jobs/$jid/play" || return 1
  _gl POST "/projects/$(_gl_pid)/jobs/$jid/cancel"
}

_gl_ep='def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;'

code_list_my_prs() {
  _gl GET "/projects/$(_gl_pid)/merge_requests?author_username=$(df_urlencode $CODE_USER)&state=all&updated_after=$(df_urlencode $(df_iso_utc $1))&updated_before=$(df_urlencode $(df_iso_utc $2))&per_page=100" || return 1
  jq -c --argjson f $1 --argjson t $2 "$_gl_ep"' [.[] | {id:.iid, url:.web_url, title, draft:(.draft // .work_in_progress // false),
    created:(.created_at|ep), updated:(.updated_at|ep)} | select(.updated >= $f and .updated < $t)]' <<<$DF_HTTP_BODY
}

# Reviewers in state "unreviewed" (GitLab 15.9+); older GitLab has no such endpoint: 3.
code_pending_reviews() {
  local prs n
  _gl GET "/projects/$(_gl_pid)/merge_requests?state=opened&author_username=$(df_urlencode $CODE_USER)&per_page=100" || return 1
  prs=$(jq -c "$_gl_ep"' [.[] | {id:.iid, url:.web_url, title, draft:(.draft // .work_in_progress // false),
    created:(.created_at|ep), reviewers:[]}]' <<<$DF_HTTP_BODY) || return 1
  for n in ${(f)"$(jq -r '.[] | select(.draft | not) | .id' <<<$prs)"}; do
    if ! _gl GET "/projects/$(_gl_pid)/merge_requests/$n/reviewers"; then
      [[ $DF_HTTP_CODE == 404 ]] && { df_unsupported "pending reviewers" "this GitLab version"; return 3 }
      return 1
    fi
    prs=$(jq -c --argjson n $n --argjson r "$DF_HTTP_BODY" "$_gl_ep"' map(if .id != $n then . else
      .reviewers = [$r[] | select(.state == "unreviewed") | {user:.user.username, name:(.user.name // .user.username),
        since:((.created_at // null) | if . == null then null else ep end)}]
      | .created as $c | .reviewers |= map(.since //= $c) end)' <<<$prs) || return 1
  done
  print -r -- $prs
}

code_prs_for_commit() {
  _gl GET "/projects/$(_gl_pid)/repository/commits/$1/merge_requests" || return 1
  jq -c '[.[] | {id:.iid, url:.web_url, title, branch:.source_branch}]' <<<$DF_HTTP_BODY
}

code_doctor() {
  local who
  who=$(code_whoami) || { df_fail "gitlab: cannot read the token owner ($DF_HTTP_ERR)"; return 1 }
  [[ $who == $CODE_USER ]] && df_ok "gitlab: token belongs to $who" ||
    { df_fail "gitlab: token belongs to '$who', CODE_USER is '$CODE_USER'"; return 1 }
  _gl GET "/projects/$(_gl_pid)" && df_ok "gitlab: project $(code_repo_path)" ||
    { df_fail "gitlab: project $(code_repo_path) ($DF_HTTP_ERR)"; return 1 }
}
