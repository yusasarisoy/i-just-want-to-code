# Time provider: Tempo Cloud (REST v4). Auth: Tempo API token (Bearer).
# TIME_USER is the Atlassian account ID. Worklogs reference the numeric Jira
# issue id, so the Jira Cloud tracker settings (TRACKER_*) must be set too.

_tempo() { local m=$1 p=$2; shift 2; df_http "$TIME_TOKEN_SECRET" bearer $m "${${TIME_URL:-https://api.tempo.io}%/}/4$p" -H 'Accept: application/json' "$@" }
_tempo_json() { _tempo $1 $2 -H 'Content-Type: application/json' --data-binary "$3" }
_jira_issue() {
  DF_HTTP_USER=$TRACKER_USER df_http "$TRACKER_TOKEN_SECRET" basic GET "${TRACKER_URL%/}/rest/api/3/issue/$1?fields=summary" -H 'Accept: application/json'
}

# _tempo_range <from> <to> [resolve-keys 1|0]: normalised worklogs.
_tempo_range() {
  _tempo GET "/worklogs/user/$TIME_USER?from=$1&to=$2&limit=1000" || return 1
  local list ids id map='{}'
  list=$(jq -c --argjson types "$(df_time_types_json)" --arg attr "$TIME_TYPE_ATTRIBUTE" '[.results[] | {
      id:(.tempoWorklogId|tostring), issue_id:(.issue.id|tostring), day:.startDate, start:(.startTime[0:5]),
      secs:.timeSpentSeconds, comment:(.description // ""),
      type:(((.attributes.values // []) | map(select(.key == $attr)) | .[0].value) as $v
            | ($types | to_entries | map(select(.value == $v and $v != null)) | .[0].key) // $v // "")}]' <<<$DF_HTTP_BODY) || return 1
  if [[ ${3:-1} == 1 ]]; then
    for id in ${(u)${(f)"$(jq -r '.[].issue_id' <<<$list)"}}; do
      _jira_issue $id || return 1
      map=$(jq -c --arg i $id --arg k "$(jq -r .key <<<$DF_HTTP_BODY)" '.[$i]=$k' <<<$map)
    done
  fi
  jq -c --argjson m "$map" 'map(. + {key:($m[.issue_id] // .issue_id)})' <<<$list
}

_tempo_body() {
  local key=$1 day=$2 start=$3 secs=$4 type=$5 comment=$6 iid
  _jira_issue $key || return 1
  iid=$(jq -r .id <<<$DF_HTTP_BODY)
  jq -nc --arg a "$TIME_USER" --argjson i $iid --arg d $day --arg s "$start:00" --argjson t $secs --arg c "$comment" \
    --arg ak "$TIME_TYPE_ATTRIBUTE" --arg av "$(df_time_type_value $type)" \
    '{authorAccountId:$a, issueId:$i, startDate:$d, startTime:$s, timeSpentSeconds:$t, description:$c}
     + (if $ak != "" and $av != "" then {attributes:[{key:$ak, value:$av}]} else {} end)'
}

time_list() { _tempo_range $1 $1 }
time_create() { local b; b=$(_tempo_body "$@") || return 1; _tempo_json POST /worklogs "$b" && jq -r .tempoWorklogId <<<$DF_HTTP_BODY }
time_update() { local id=$1 b; shift; b=$(_tempo_body "$@") || return 1; _tempo_json PUT /worklogs/$id "$b" }
time_day_total() { time_list $1 | df_sum_secs }
time_week_totals() { _tempo_range $1 $2 0 | df_group_days }

time_doctor() {
  [[ -n $TIME_USER ]] || { df_fail "tempo-cloud: TIME_USER (Atlassian account ID) is not set"; return 1 }
  _tempo GET "/worklogs/user/$TIME_USER?from=$(df_today)&to=$(df_today)&limit=1" && df_ok "tempo-cloud: worklogs readable" ||
    { df_fail "tempo-cloud: $DF_HTTP_ERR"; return 1 }
}
