# Code host provider: GitHub (REST v3; GraphQL for draft and auto-merge).
# Auth: bearer token from CODE_TOKEN_SECRET (set it to `gh` to use `gh auth token`).

_gh_api() {
  [[ -n $CODE_API_URL ]] && { print -r -- ${CODE_API_URL%/}; return }
  local h=$(df_remote_host)
  [[ $h == github.com || -z $h ]] && print https://api.github.com || print -r -- "https://$h/api/v3"
}
_gh() { local m=$1 p=$2; shift 2; df_http "$CODE_TOKEN_SECRET" bearer $m "$(_gh_api)$p" -H 'Accept: application/vnd.github+json' "$@" }
_gh_json() { local m=$1 p=$2 body=$3; _gh $m $p -H 'Content-Type: application/json' --data-binary "$body" }
_gh_graphql() {
  local api=$(_gh_api) url
  [[ $api == */api/v3 ]] && url=${api%/v3}/graphql || url=$api/graphql
  df_http "$CODE_TOKEN_SECRET" bearer POST $url -H 'Content-Type: application/json' --data-binary "$1" || return 1
  [[ -z $(jq -r '.errors // empty' <<<$DF_HTTP_BODY) ]] || { df_err "$(jq -r '.errors[0].message' <<<$DF_HTTP_BODY)"; return 1 }
}
_gh_norm='{id:.number, url:.html_url, title, draft:(.draft // false), node_id,
  reviewers:[.requested_reviewers[]?.login], merge_state:(.mergeable_state // "unknown"), body:(.body // "")}'

code_repo_path() { df_repo_path }

code_whoami() { _gh GET /user || return 1; jq -r '.login // empty' <<<$DF_HTTP_BODY }

code_find_pr() {
  local repo; repo=$(code_repo_path) || return 1
  _gh GET "/repos/$repo/pulls?state=open&head=$(df_urlencode "${repo%%/*}:$1")" || return 1
  jq -c ".[0] // empty | $_gh_norm" <<<$DF_HTTP_BODY
}

code_create_pr() {
  local body=$(jq -nc --arg h $1 --arg b $2 --arg t "$3" --argjson d ${4:-0} '{head:$h, base:$b, title:$t, draft:($d==1)}')
  _gh_json POST "/repos/$(code_repo_path)/pulls" "$body" || return 1
  jq -c "$_gh_norm" <<<$DF_HTTP_BODY
}

_gh_pull() { _gh GET "/repos/$(code_repo_path)/pulls/$1" && jq -c "$_gh_norm" <<<$DF_HTTP_BODY }

# code_update_pr <id> title=... description=... (only if empty) labels+=a,b
code_update_pr() {
  local id=$1 a patch='{}' labels=''; shift
  for a; do
    case $a in
      title=*) patch=$(jq -c --arg v "${a#title=}" '.title=$v' <<<$patch) ;;
      description=*)
        local cur; cur=$(_gh_pull $id) || return 1
        [[ -z $(jq -r .body <<<$cur) ]] && patch=$(jq -c --arg v "${a#description=}" '.body=$v' <<<$patch) ;;
      labels+=*) labels=${a#labels+=} ;;
    esac
  done
  if [[ $patch != '{}' ]]; then _gh_json PATCH "/repos/$(code_repo_path)/pulls/$id" "$patch" || return 1; fi
  if [[ -n $labels ]]; then
    _gh_json POST "/repos/$(code_repo_path)/issues/$id/labels" \
      "$(jq -nc --arg l $labels '{labels:($l|split(","))}')" || return 1
  fi
}

code_set_draft() {
  local pr; pr=$(_gh_pull $1) || return 1
  [[ $(jq -r .draft <<<$pr) == $([[ $2 == 1 ]] && print true || print false) ]] && return 0
  local m=markPullRequestReadyForReview
  [[ $2 == 1 ]] && m=convertPullRequestToDraft
  _gh_graphql "$(jq -nc --arg id "$(jq -r .node_id <<<$pr)" --arg m $m \
    '{query:("mutation($id:ID!){ \($m)(input:{pullRequestId:$id}){ clientMutationId } }"), variables:{id:$id}}')"
}

code_add_reviewers() {
  local id=$1 pr u; shift
  pr=$(_gh_pull $id) || return 1
  local -a cur=(${(f)"$(jq -r '.reviewers[]' <<<$pr)"}) new=()
  for u; do df_in_list $u $cur || new+=($u); done
  (( ${#new} )) || return 0
  _gh_json POST "/repos/$(code_repo_path)/pulls/$id/requested_reviewers" \
    "$(jq -nc '{reviewers:$ARGS.positional}' --args $new)"
}

# 0 = auto-merge set; 2 = would merge immediately (no merge call).
code_auto_merge() {
  local pr state; pr=$(_gh_pull $1) || return 1
  state=$(jq -r .merge_state <<<$pr)
  case $state in
    # unknown: a new PR is still being checked; enabling auto-merge never merges, and a clean PR is refused below.
    blocked|behind|dirty|draft|unknown) ;;
    *) df_skip "auto-merge not enabled: merge state is '$state' (would merge immediately or unknown)"; return 2 ;;
  esac
  _gh_graphql "$(jq -nc --arg id "$(jq -r .node_id <<<$pr)" --arg mm ${MERGE_METHOD:u} \
    '{query:("mutation($id:ID!){ enablePullRequestAutoMerge(input:{pullRequestId:$id, mergeMethod:\($mm)}){ clientMutationId } }"), variables:{id:$id}}')" && return 0
  [[ $DF_HTTP_ERR == *clean\ status* ]] && { df_skip "auto-merge not enabled: the pull request can merge now"; return 2 }
  return 1
}

code_ci_nudge() { df_unsupported "CI nudge" github }

# ISO 8601 (with or without fractions or +00:00) -> epoch seconds, in jq.
_gh_ep='def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;'

# code_list_my_prs <from-epoch> <to-epoch>: CODE_USER's PRs updated in [from, to).
code_list_my_prs() {
  local repo q; repo=$(code_repo_path) || return 1
  q="is:pr repo:$repo author:$CODE_USER updated:>=$(df_iso_utc $1)"
  _gh GET "/search/issues?q=$(df_urlencode $q)&per_page=100" || return 1
  jq -c --argjson f $1 --argjson t $2 "$_gh_ep"' [.items[] | {id:.number, url:.html_url, title, draft:(.draft // false),
    created:(.created_at|ep), updated:(.updated_at|ep)} | select(.updated >= $f and .updated < $t)]' <<<$DF_HTTP_BODY
}

# code_pending_reviews: CODE_USER's open PRs with the reviewers who have not reviewed
# yet; "since" is when each one was last asked (or the PR left draft, if later).
code_pending_reviews() {
  local repo prs n out='[]' tl; repo=$(code_repo_path) || return 1
  _gh GET "/repos/$repo/pulls?state=open&per_page=100" || return 1
  prs=$(jq -c --arg u "$CODE_USER" "$_gh_ep"' [.[] | select(.user.login == $u) | {id:.number, url:.html_url, title,
    draft:(.draft // false), created:(.created_at|ep), reviewers:[.requested_reviewers[]? | {user:.login, name:.login}]}]' <<<$DF_HTTP_BODY) || return 1
  for n in ${(f)"$(jq -r '.[] | select(.draft | not) | select(.reviewers | length > 0) | .id' <<<$prs)"}; do
    _gh GET "/repos/$repo/issues/$n/timeline?per_page=100" || return 1
    tl=$DF_HTTP_BODY
    prs=$(jq -c --argjson n $n --argjson tl "$tl" "$_gh_ep"' map(if .id != $n then . else
      ([$tl[] | select(.event == "ready_for_review") | .created_at | ep] | max) as $ready
      | .reviewers |= map(.user as $u | . + {since: ([([$tl[] | select(.event == "review_requested" and .requested_reviewer.login == $u) | .created_at | ep] | max), $ready] | map(select(. != null)) | max)})
      | .created as $c | .reviewers |= map(.since //= $c) end)' <<<$prs) || return 1
  done
  jq -c 'map(.reviewers |= map(.since //= 0))' <<<$prs
}

# code_prs_for_commit <sha>: the PRs that contain <sha>.
code_prs_for_commit() {
  _gh GET "/repos/$(code_repo_path)/commits/$1/pulls" || return 1
  jq -c '[.[] | {id:.number, url:.html_url, title, branch:.head.ref}]' <<<$DF_HTTP_BODY
}

code_doctor() {
  local who repo
  who=$(code_whoami) || { df_fail "github: cannot read the token owner ($DF_HTTP_ERR)"; return 1 }
  [[ $who == $CODE_USER ]] && df_ok "github: token belongs to $who" ||
    { df_fail "github: token belongs to '$who', CODE_USER is '$CODE_USER'"; return 1 }
  repo=$(code_repo_path) || { df_fail "github: cannot parse the $GIT_REMOTE remote; set CODE_REPO"; return 1 }
  _gh GET /repos/$repo >/dev/null && df_ok "github: repository $repo" || { df_fail "github: repository $repo ($DF_HTTP_ERR)"; return 1 }
}
