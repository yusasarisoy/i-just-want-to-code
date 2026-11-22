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

code_doctor() {
  local who
  who=$(code_whoami) || { df_fail "bitbucket: cannot read the token owner ($DF_HTTP_ERR)"; return 1 }
  [[ $who == $CODE_USER ]] && df_ok "bitbucket: token belongs to $who" ||
    { df_fail "bitbucket: token belongs to '$who', CODE_USER is '$CODE_USER'"; return 1 }
  _bb GET "/repositories/$(code_repo_path)" && df_ok "bitbucket: repository $(code_repo_path)" ||
    { df_fail "bitbucket: repository $(code_repo_path) ($DF_HTTP_ERR)"; return 1 }
}
