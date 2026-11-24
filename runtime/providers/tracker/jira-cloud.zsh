# Tracker provider: Jira Cloud (REST v3, ADF descriptions, basic email:token).
# jira-dc.zsh sets _JIRA_KIND=dc and sources this file (v2, Bearer PAT, wiki markup).
: ${_JIRA_KIND:=cloud}
if [[ $_JIRA_KIND == cloud ]]; then _JIRA_API=3 _JIRA_AUTH=basic; else _JIRA_API=2 _JIRA_AUTH=bearer; fi

_jira() {
  local m=$1 p=$2; shift 2
  DF_HTTP_USER=$TRACKER_USER df_http "$TRACKER_TOKEN_SECRET" $_JIRA_AUTH $m "${TRACKER_URL%/}$p" -H 'Accept: application/json' "$@"
}
_jira_json() { _jira $1 $2 -H 'Content-Type: application/json' --data-binary "$3" }
_jira_err() { print -r -- "${DF_HTTP_ERR:-HTTP $DF_HTTP_CODE}" }

# Sets DF_TICKET_STATUS and DF_TICKET_ID in the calling shell (never call in $( )).
tracker_get() {
  DF_TICKET_STATUS='' DF_TICKET_ID=''
  _jira GET "/rest/api/$_JIRA_API/issue/$1?fields=status" || return 1
  DF_TICKET_STATUS=$(jq -r '.fields.status.name // empty' <<<$DF_HTTP_BODY)
  DF_TICKET_ID=$(jq -r '.id // empty' <<<$DF_HTTP_BODY)
}

# 0 moved, 4 no transition to <status>, 1 error.
_jira_transition() {
  local key=$1 st=$2 tid
  _jira GET "/rest/api/$_JIRA_API/issue/$key/transitions" || return 1
  tid=$(jq -r --arg s "$st" '.transitions | map(select((.to.name|ascii_downcase)==($s|ascii_downcase) or (.name|ascii_downcase)==($s|ascii_downcase)))[0].id // empty' <<<$DF_HTTP_BODY)
  [[ -n $tid ]] || return 4
  _jira_json POST "/rest/api/$_JIRA_API/issue/$key/transitions" "$(jq -nc --arg t $tid '{transition:{id:$t}}')"
}

tracker_move() {
  local rc
  _jira_transition $1 "$2"; rc=$?
  if (( rc == 4 )) && [[ -n $STATUS_VIA ]]; then
    _jira_transition $1 "$STATUS_VIA" && _jira_transition $1 "$2"; rc=$?
  fi
  (( rc == 4 )) && df_err "no transition to '$2'$([[ -n $STATUS_VIA ]] && print -n " (also tried via '$STATUS_VIA')")"
  return $rc
}

tracker_url() { print -r -- "${TRACKER_URL%/}/browse/$1" }

# Prints the key of an issue in TICKET_PROJECT whose summary equals <title>.
# Exit 0 = searched (key or nothing), 1 = search failed: callers must stop.
tracker_find_by_title() {
  local words=${1//[^[:alnum:] ]/ } jql endpoint
  jql="project = \"$TICKET_PROJECT\" AND summary ~ \"${words}\""
  [[ $_JIRA_KIND == cloud ]] && endpoint=/rest/api/3/search/jql || endpoint=/rest/api/2/search
  _jira GET "$endpoint?jql=$(df_urlencode $jql)&fields=summary&maxResults=50" || return 1
  jq -r --arg t "$1" '[.issues[]? | select(.fields.summary == $t) | .key][0] // empty' <<<$DF_HTTP_BODY
}

# Resolves one 'Field name=Value' against the create metadata in $meta.
_jira_field() {
  local meta=$1 name=$2 value=$3
  jq -c --arg n "$name" --arg v "$value" --argjson pc ${TICKET_PREFER_CUSTOM_FIELDS:-1} --arg kind $_JIRA_KIND '
    def custom: .fieldId | startswith("customfield_");
    [.[] | select(.fieldId == $n or ((.name|ascii_downcase) == ($n|ascii_downcase)))] as $c
    | if ($c|length) == 0 then {error:"no field named \"\($n)\" on this issue type"}
      else ($c | if $pc == 1 then map(select(custom)) + map(select(custom|not)) else map(select(custom|not)) + map(select(custom)) end | .[0]) as $f
      | if (($f.allowedValues // []) | length) > 0 then
          ([$f.allowedValues[] | select(((.name // .value // "")|ascii_downcase) == ($v|ascii_downcase))][0]) as $a
          | if $a == null then {error:"invalid value \"\($v)\" for \($f.name); allowed: \([$f.allowedValues[] | .name // .value] | join(", "))"}
            else {key:$f.fieldId, value:(if $f.schema.type == "array" then [{id:$a.id}] else {id:$a.id} end)} end
        elif ($f.schema.custom // "" | test("gh-sprint")) then {key:$f.fieldId, value:($v|tonumber)}
        elif $f.schema.type == "number" then {key:$f.fieldId, value:($v|tonumber)}
        elif $f.schema.type == "array" then {key:$f.fieldId, value:($v|split(",")|map(if $f.schema.items == "string" then . else {name:.} end))}
        elif $f.schema.type == "user" then {key:$f.fieldId, value:(if $kind == "cloud" then {accountId:$v} else {name:$v} end)}
        elif $f.schema.type == "option" then {key:$f.fieldId, value:{value:$v}}
        else {key:$f.fieldId, value:$v} end
      end' <<<$meta
}

_jira_sprint_id() {
  [[ $1 == [0-9]## ]] && { print $1; return }
  [[ -n $TICKET_BOARD ]] || { df_err "sprint '$1' needs TICKET_BOARD to look up its id"; return 1 }
  _jira GET "/rest/agile/1.0/board/$TICKET_BOARD/sprint?state=active,future" || return 1
  local id=$(jq -r --arg n "$1" '[.values[] | select(.name == $n) | .id][0] // empty' <<<$DF_HTTP_BODY)
  [[ -n $id ]] || { df_err "no active or future sprint named '$1' on board $TICKET_BOARD"; return 1 }
  print $id
}

_jira_account() {
  [[ $_JIRA_KIND == dc ]] && { jq -nc --arg n "$1" '{name:$n}'; return }
  _jira GET "/rest/api/3/user/search?query=$(df_urlencode $1)" || return 1
  local id=$(jq -r '.[0].accountId // empty' <<<$DF_HTTP_BODY)
  [[ -n $id ]] || { df_err "no user matching '$1'"; return 1 }
  jq -nc --arg a $id '{accountId:$a}'
}

# tracker_create <type> <title> <description-file>
# Extra fields come from DF_CREATE_FIELDS=('Field name=Value' ...); the special
# names assignee, parent and sprint are resolved here. Prints the new key.
tracker_create() {
  local type=$1 title=$2 desc=$(<$3) tid meta fields item n v r
  _jira GET "/rest/api/$_JIRA_API/issue/createmeta/$TICKET_PROJECT/issuetypes" || return 1
  tid=$(jq -r --arg t "$type" '[(.issueTypes // .values)[] | select((.name|ascii_downcase) == ($t|ascii_downcase)) | .id][0] // empty' <<<$DF_HTTP_BODY)
  if [[ -z $tid ]]; then
    df_err "no issue type '$type' in $TICKET_PROJECT; allowed: $(jq -r '[(.issueTypes // .values)[].name] | join(", ")' <<<$DF_HTTP_BODY)"
    return 1
  fi
  _jira GET "/rest/api/$_JIRA_API/issue/createmeta/$TICKET_PROJECT/issuetypes/$tid?maxResults=200" || return 1
  meta=$(jq -c '.fields // .values' <<<$DF_HTTP_BODY)
  if [[ $_JIRA_KIND == cloud ]]; then
    v=$(jq -c --arg d "$desc" '{type:"doc", version:1, content:($d | split("\n\n") | map(select(length > 0)) | map({type:"paragraph", content:[{type:"text", text:.}]}))}' <<<null)
  else
    v=$(jq -c --arg d "$desc" '$d' <<<null)
  fi
  fields=$(jq -nc --arg p "$TICKET_PROJECT" --arg t $tid --arg s "$title" --argjson d "$v" \
    '{project:{key:$p}, issuetype:{id:$t}, summary:$s, description:$d}')
  for item in $DF_CREATE_FIELDS; do
    n=${item%%=*} v=${item#*=}
    case ${n:l} in
      assignee) r=$(_jira_account "$v") || return 1; r=$(jq -nc --argjson v "$r" '{key:"assignee", value:$v}') ;;
      parent|epic) if [[ $_JIRA_KIND == cloud ]]; then r=$(jq -nc --arg v "$v" '{key:"parent", value:{key:$v}}')
                   else r=$(_jira_field "$meta" 'Epic Link' "$v"); fi ;;
      sprint) v=$(_jira_sprint_id "$v") || return 1; r=$(_jira_field "$meta" Sprint "$v") ;;
      *) r=$(_jira_field "$meta" "$n" "$v") ;;
    esac
    if [[ -n $(jq -r '.error // empty' <<<$r) ]]; then df_err "$(jq -r .error <<<$r)"; return 1; fi
    fields=$(jq -c --argjson r "$r" '.[$r.key] = $r.value' <<<$fields)
  done
  if (( DF_DRY )); then
    df_dry "create $type in $TICKET_PROJECT: \"$title\" (fields: $(jq -r 'keys | join(", ")' <<<$fields))"
    return 0
  fi
  _jira_json POST "/rest/api/$_JIRA_API/issue" "$(jq -c '{fields:.}' <<<$fields)" || return 1
  jq -r .key <<<$DF_HTTP_BODY
}

# tracker_issue <key>: {key, title, type, status, url}.
tracker_issue() {
  _jira GET "/rest/api/$_JIRA_API/issue/$1?fields=summary,issuetype,status" || return 1
  jq -c --arg u "${TRACKER_URL%/}/browse/" '{key, title:(.fields.summary // ""), type:(.fields.issuetype.name // ""),
    status:(.fields.status.name // ""), url:($u + .key)}' <<<$DF_HTTP_BODY
}

# tracker_list_mine <status...>: [{key, title, url}] assigned to the token owner.
tracker_list_mine() {
  local jql endpoint s list=''
  for s; do list+="${list:+, }\"${s//\"/}\""; done
  jql="assignee = currentUser()${list:+ AND status in ($list)} ORDER BY updated DESC"
  [[ $_JIRA_KIND == cloud ]] && endpoint=/rest/api/3/search/jql || endpoint=/rest/api/2/search
  _jira GET "$endpoint?jql=$(df_urlencode $jql)&fields=summary&maxResults=50" || return 1
  jq -c --arg u "${TRACKER_URL%/}/browse/" '[.issues[]? | {key, title:(.fields.summary // ""), url:($u + .key)}]' <<<$DF_HTTP_BODY
}

tracker_set_estimate() {
  [[ -n $TICKET_BOARD ]] || { df_err "estimates need TICKET_BOARD"; return 1 }
  _jira_json PUT "/rest/agile/1.0/issue/$1/estimation?boardId=$TICKET_BOARD" "$(jq -nc --arg v $2 '{value:$v}')"
}

tracker_doctor() {
  local who
  _jira GET "/rest/api/$_JIRA_API/myself" || { df_fail "jira-$_JIRA_KIND: cannot authenticate at $TRACKER_URL ($(_jira_err))"; return 1 }
  who=$(jq -r '.emailAddress // .name // .displayName' <<<$DF_HTTP_BODY)
  df_ok "jira-$_JIRA_KIND: signed in as $who"
  [[ -z $TICKET_PROJECT ]] && { df_skip "jira-$_JIRA_KIND: TICKET_PROJECT not set (ticket creation off)"; return 0 }
  _jira GET "/rest/api/$_JIRA_API/project/$TICKET_PROJECT" && df_ok "jira-$_JIRA_KIND: project $TICKET_PROJECT" ||
    { df_fail "jira-$_JIRA_KIND: project $TICKET_PROJECT ($(_jira_err))"; return 1 }
}
