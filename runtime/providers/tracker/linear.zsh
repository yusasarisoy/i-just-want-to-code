# Tracker provider: Linear (GraphQL). Auth: personal API key in the
# Authorization header. TICKET_PROJECT is the team key (e.g. ENG).
# Issue types map to labels with the same name; custom fields are not supported.

_lin() {
  local body vars=$2
  [[ -n $vars ]] || vars='{}'
  body=$(jq -nc --arg q "$1" --argjson v "$vars" '{query:$q, variables:$v}')
  df_http "$TRACKER_TOKEN_SECRET" header:Authorization POST "${${TRACKER_URL:-https://api.linear.app}%/}/graphql" \
    -H 'Content-Type: application/json' --data-binary "$body" || return 1
  if [[ -n $(jq -r '.errors // empty' <<<$DF_HTTP_BODY) ]]; then df_err "$(jq -r '.errors[0].message' <<<$DF_HTTP_BODY)"; return 1; fi
}
_lin_mutate() {
  (( DF_DRY )) && { df_dry "linear: ${1%%\(*}"; return 0 }
  _lin "$@"
}

tracker_get() {
  DF_TICKET_STATUS='' DF_TICKET_ID=''
  _lin 'query($id:String!){ issue(id:$id){ id state{ name } } }' "$(jq -nc --arg i $1 '{id:$i}')" || return 1
  DF_TICKET_STATUS=$(jq -r '.data.issue.state.name // empty' <<<$DF_HTTP_BODY)
  DF_TICKET_ID=$(jq -r '.data.issue.id // empty' <<<$DF_HTTP_BODY)
}

tracker_move() {
  local sid id
  _lin 'query($id:String!){ issue(id:$id){ id team{ states{ nodes{ id name } } } } }' "$(jq -nc --arg i $1 '{id:$i}')" || return 1
  id=$(jq -r '.data.issue.id' <<<$DF_HTTP_BODY)
  sid=$(jq -r --arg s "$2" '[.data.issue.team.states.nodes[] | select((.name|ascii_downcase) == ($s|ascii_downcase)) | .id][0] // empty' <<<$DF_HTTP_BODY)
  [[ -n $sid ]] || { df_err "no workflow state '$2'"; return 4 }
  _lin_mutate 'mutation($id:String!,$s:String!){ issueUpdate(id:$id, input:{stateId:$s}){ success } }' \
    "$(jq -nc --arg i $id --arg s $sid '{id:$i, s:$s}')"
}

tracker_url() {
  _lin 'query($id:String!){ issue(id:$id){ url } }' "$(jq -nc --arg i $1 '{id:$i}')" || return 1
  jq -r '.data.issue.url // empty' <<<$DF_HTTP_BODY
}

tracker_find_by_title() {
  _lin 'query($t:String!,$k:String!){ issues(first:5, filter:{ title:{ eq:$t }, team:{ key:{ eq:$k } } }){ nodes{ identifier } } }' \
    "$(jq -nc --arg t "$1" --arg k "$TICKET_PROJECT" '{t:$t, k:$k}')" || return 1
  jq -r '.data.issues.nodes[0].identifier // empty' <<<$DF_HTTP_BODY
}

tracker_create() {
  local type=$1 title=$2 desc=$(<$3) team item prio=null
  _lin 'query($k:String!){ teams(filter:{ key:{ eq:$k } }){ nodes{ id labels{ nodes{ id name } } } } }' \
    "$(jq -nc --arg k "$TICKET_PROJECT" '{k:$k}')" || return 1
  team=$(jq -c '.data.teams.nodes[0] // empty' <<<$DF_HTTP_BODY)
  [[ -n $team ]] || { df_err "no Linear team with key '$TICKET_PROJECT'"; return 1 }
  local label=$(jq -r --arg t "$type" '[.labels.nodes[] | select((.name|ascii_downcase) == ($t|ascii_downcase)) | .id][0] // empty' <<<$team)
  [[ -n $type && -z $label ]] && df_skip "linear: no label '$type'; creating without it"
  for item in $DF_CREATE_FIELDS; do
    case ${${item%%=*}:l} in
      priority) case ${${item#*=}:l} in urgent|1) prio=1;; high|2) prio=2;; medium|3) prio=3;; low|4) prio=4;; *) prio=0;; esac ;;
      *) df_unsupported "field '${item%%=*}'" linear ;;
    esac
  done
  local input=$(jq -nc --arg t "$(jq -r .id <<<$team)" --arg ti "$title" --arg d "$desc" --arg l "$label" --argjson p $prio \
    '{teamId:$t, title:$ti, description:$d} + (if $l != "" then {labelIds:[$l]} else {} end) + (if $p != null then {priority:$p} else {} end)')
  if (( DF_DRY )); then df_dry "create in $TICKET_PROJECT: \"$title\""; return 0; fi
  _lin 'mutation($i:IssueCreateInput!){ issueCreate(input:$i){ success issue{ identifier } } }' "$(jq -nc --argjson i "$input" '{i:$i}')" || return 1
  jq -r '.data.issueCreate.issue.identifier' <<<$DF_HTTP_BODY
}

# Linear has no issue types: the first label stands in for one.
tracker_issue() {
  _lin 'query($id:String!){ issue(id:$id){ identifier title url state{ name } labels{ nodes{ name } } } }' "$(jq -nc --arg i $1 '{id:$i}')" || return 1
  jq -c '.data.issue | {key:.identifier, title, type:((.labels.nodes // [])[0].name // ""), status:(.state.name // ""), url}' <<<$DF_HTTP_BODY
}

tracker_list_mine() {
  local states=$(jq -nc '$ARGS.positional' --args "$@")
  _lin 'query($s:[String!]){ viewer{ assignedIssues(first:50, filter:{ state:{ name:{ in:$s } } }){ nodes{ identifier title url } } } }' \
    "$(jq -nc --argjson s "$states" '{s:(if ($s|length) > 0 then $s else null end)}')" || return 1
  jq -c '[.data.viewer.assignedIssues.nodes[]? | {key:.identifier, title, url}]' <<<$DF_HTTP_BODY
}

tracker_set_estimate() {
  tracker_get $1 || return 1
  _lin_mutate 'mutation($id:String!,$e:Int!){ issueUpdate(id:$id, input:{estimate:$e}){ success } }' \
    "$(jq -nc --arg i $DF_TICKET_ID --argjson e $2 '{id:$i, e:$e}')"
}

tracker_doctor() {
  _lin 'query{ viewer{ email } }' || { df_fail "linear: cannot authenticate ($DF_HTTP_ERR)"; return 1 }
  df_ok "linear: signed in as $(jq -r .data.viewer.email <<<$DF_HTTP_BODY)"
}
