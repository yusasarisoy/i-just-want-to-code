# Code host provider: Bitbucket Cloud (REST 2.0).
# Auth: basic, secret value "username:app-password" or "email:api-token".
# Reviewers are Bitbucket account IDs. Labels and auto-merge are not supported.

_bb_api() { print -r -- ${${CODE_API_URL:-https://api.bitbucket.org/2.0}%/} }
_bb() { local m=$1 p=$2; shift 2; df_http "$CODE_TOKEN_SECRET" token-basic $m "$(_bb_api)$p" "$@" }
_bb_json() { _bb $1 $2 -H 'Content-Type: application/json' --data-binary "$3" }
_bb_norm='{id, url:.links.html.href, title, draft:(.draft // false), description:(.description // ""),
  reviewers:[.reviewers[]? | (.account_id // .nickname)], merge_state:"unknown"}'
_bb_pr() { _bb GET "/repositories/$(code_repo_path)/pullrequests/$1" && jq -c "$_bb_norm" <<<$DF_HTTP_BODY }

code_repo_path() { df_repo_path }

code_whoami() { _bb GET /user || return 1; jq -r '.username // .nickname // empty' <<<$DF_HTTP_BODY }

code_find_pr() {
  local q="source.branch.name=\"$1\" AND state=\"OPEN\""
  _bb GET "/repositories/$(code_repo_path)/pullrequests?q=$(df_urlencode $q)" || return 1
  jq -c ".values[0] // empty | $_bb_norm" <<<$DF_HTTP_BODY
}

code_create_pr() {
  _bb_json POST "/repositories/$(code_repo_path)/pullrequests" "$(jq -nc --arg s $1 --arg t $2 --arg ti "$3" --argjson d ${4:-0} \
    '{title:$ti, source:{branch:{name:$s}}, destination:{branch:{name:$t}}, draft:($d==1)}')" || return 1
  jq -c "$_bb_norm" <<<$DF_HTTP_BODY
}

code_update_pr() {
  local id=$1 a pr put; shift
  pr=$(_bb_pr $id) || return 1
  put=$(jq -c '{title}' <<<$pr)
  for a; do
    case $a in
      title=*) put=$(jq -c --arg v "${a#title=}" '.title=$v' <<<$put) ;;
      description=*) [[ -z $(jq -r .description <<<$pr) ]] && put=$(jq -c --arg v "${a#description=}" '.description=$v' <<<$put) ;;
      labels+=*) df_unsupported labels bitbucket ;;
    esac
  done
  [[ $put == $(jq -c '{title}' <<<$pr) ]] || _bb_json PUT "/repositories/$(code_repo_path)/pullrequests/$id" "$put"
}

code_set_draft() {
  local pr; pr=$(_bb_pr $1) || return 1
  _bb_json PUT "/repositories/$(code_repo_path)/pullrequests/$1" \
    "$(jq -c --argjson d $([[ $2 == 1 ]] && print true || print false) '{title, draft:$d}' <<<$pr)"
}

code_add_reviewers() {
  local id=$1 pr; shift
  pr=$(_bb_pr $id) || return 1
  local -a cur=(${(f)"$(jq -r '.reviewers[]' <<<$pr)"}) all
  all=(${(u)cur} $@); all=(${(u)all})
  (( ${#all} > ${#cur} )) || return 0
  _bb_json PUT "/repositories/$(code_repo_path)/pullrequests/$id" \
    "$(jq -c '{title, reviewers:($ARGS.positional|map({account_id:.}))}' --args $all <<<$pr)"
}

code_auto_merge() { df_unsupported auto-merge bitbucket }
code_ci_nudge() { df_unsupported "CI nudge" bitbucket }

_bb_ep='def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;'

code_list_my_prs() {
  local q="author.nickname=\"$CODE_USER\" AND updated_on >= $(df_iso_utc $1) AND updated_on < $(df_iso_utc $2)"
  _bb GET "/repositories/$(code_repo_path)/pullrequests?q=$(df_urlencode $q)&state=OPEN&state=MERGED&state=DECLINED&pagelen=50" || return 1
  jq -c "$_bb_ep"' [.values[] | {id, url:.links.html.href, title, draft:(.draft // false),
    created:(.created_on|ep), updated:(.updated_on|ep)}]' <<<$DF_HTTP_BODY
}

# Bitbucket keeps no request time per reviewer: "since" is when the PR was opened.
code_pending_reviews() {
  local q="author.nickname=\"$CODE_USER\" AND state=\"OPEN\"" ids id out='[]'
  _bb GET "/repositories/$(code_repo_path)/pullrequests?q=$(df_urlencode $q)&pagelen=50" || return 1
  ids=(${(f)"$(jq -r '.values[].id' <<<$DF_HTTP_BODY)"})
  for id in $ids; do
    _bb GET "/repositories/$(code_repo_path)/pullrequests/$id" || return 1
    out=$(jq -c --argjson pr "$DF_HTTP_BODY" "$_bb_ep"' . + [$pr | (.created_on|ep) as $c | {id, url:.links.html.href, title,
      draft:(.draft // false), created:$c, reviewers:[.participants[]? | select(.role == "REVIEWER" and (.approved | not) and .state == null)
        | {user:(.user.nickname // .user.account_id), name:(.user.display_name // .user.nickname), since:$c}]}]' <<<$out) || return 1
  done
  print -r -- $out
}

code_prs_for_commit() {
  _bb GET "/repositories/$(code_repo_path)/commit/$1/pullrequests" || return 1
  jq -c '[.values[] | {id, url:.links.html.href, title, branch:.source.branch.name}]' <<<$DF_HTTP_BODY
}

code_doctor() {
  local who
  who=$(code_whoami) || { df_fail "bitbucket: cannot read the token owner ($DF_HTTP_ERR)"; return 1 }
  [[ $who == $CODE_USER ]] && df_ok "bitbucket: token belongs to $who" ||
    { df_fail "bitbucket: token belongs to '$who', CODE_USER is '$CODE_USER'"; return 1 }
  _bb GET "/repositories/$(code_repo_path)" && df_ok "bitbucket: repository $(code_repo_path)" ||
    { df_fail "bitbucket: repository $(code_repo_path) ($DF_HTTP_ERR)"; return 1 }
}
