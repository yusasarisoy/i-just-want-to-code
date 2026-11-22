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

# 0 = auto-merge set; 2 = would merge immediately or state unknown (no merge call).
code_auto_merge() {
  local pr state; pr=$(_gh_pull $1) || return 1
  state=$(jq -r .merge_state <<<$pr)
  case $state in
    blocked|behind|dirty|draft) ;;
    *) df_skip "auto-merge not enabled: merge state is '$state' (would merge immediately or unknown)"; return 2 ;;
  esac
  _gh_graphql "$(jq -nc --arg id "$(jq -r .node_id <<<$pr)" --arg mm ${MERGE_METHOD:u} \
    '{query:("mutation($id:ID!){ enablePullRequestAutoMerge(input:{pullRequestId:$id, mergeMethod:\($mm)}){ clientMutationId } }"), variables:{id:$id}}')" && return 0
  [[ $DF_HTTP_ERR == *clean\ status* ]] && { df_skip "auto-merge not enabled: the pull request can merge now"; return 2 }
  return 1
}

code_ci_nudge() { df_unsupported "CI nudge" github }

code_doctor() {
  local who repo
  who=$(code_whoami) || { df_fail "github: cannot read the token owner ($DF_HTTP_ERR)"; return 1 }
  [[ $who == $CODE_USER ]] && df_ok "github: token belongs to $who" ||
    { df_fail "github: token belongs to '$who', CODE_USER is '$CODE_USER'"; return 1 }
  repo=$(code_repo_path) || { df_fail "github: cannot parse the $GIT_REMOTE remote; set CODE_REPO"; return 1 }
  _gh GET /repos/$repo >/dev/null && df_ok "github: repository $repo" || { df_fail "github: repository $repo ($DF_HTTP_ERR)"; return 1 }
}
