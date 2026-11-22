# Time provider: Tempo Timesheets on Jira Data Center (tempo-timesheets/4).
# Auth: Jira personal access token (Bearer). TIME_URL is the Jira base URL,
# TIME_USER is the Tempo worker key.

_tdc() { local m=$1 p=$2; shift 2; df_http "$TIME_TOKEN_SECRET" bearer $m "${${TIME_URL:-$TRACKER_URL}%/}/rest/tempo-timesheets/4$p" -H 'Accept: application/json' "$@" }
_tdc_json() { _tdc $1 $2 -H 'Content-Type: application/json' --data-binary "$3" }

_tdc_range() {
  _tdc_json POST /worklogs/search "$(jq -nc --arg f $1 --arg t $2 --arg w "$TIME_USER" '{from:$f, to:$t, worker:[$w]}')" || return 1
  jq -c --argjson types "$(df_time_types_json)" --arg attr "$TIME_TYPE_ATTRIBUTE" '[.[] | {
      id:(.tempoWorklogId|tostring), key:.issue.key, day:.started[0:10], start:.started[11:16],
      secs:.timeSpentSeconds, comment:(.comment // ""),
      type:((.attributes[$attr].value // null) as $v | ($types | to_entries | map(select(.value == $v and $v != null)) | .[0].key) // $v // "")}]' <<<$DF_HTTP_BODY
}

_tdc_body() {
  local key=$1 day=$2 start=$3 secs=$4 type=$5 comment=$6
  jq -nc --arg w "$TIME_USER" --arg k $key --arg s "${day}T$start:00.000" --argjson t $secs --arg c "$comment" \
    --arg ak "$TIME_TYPE_ATTRIBUTE" --arg av "$(df_time_type_value $type)" \
    '{worker:$w, originTaskId:$k, started:$s, timeSpentSeconds:$t, comment:$c}
     + (if $ak != "" and $av != "" then {attributes:{($ak):{name:$ak, value:$av}}} else {} end)'
}

time_list() { _tdc_range $1 $1 }
time_create() { _tdc_json POST /worklogs "$(_tdc_body "$@")" && jq -r '(if type == "array" then .[0] else . end).tempoWorklogId' <<<$DF_HTTP_BODY }
time_update() { local id=$1; shift; _tdc_json PUT /worklogs/$id "$(_tdc_body "$@")" }
time_day_total() { time_list $1 | df_sum_secs }
time_week_totals() { _tdc_range $1 $2 | df_group_days }

time_doctor() {
  [[ -n $TIME_USER ]] || { df_fail "tempo-dc: TIME_USER (worker key) is not set"; return 1 }
  _tdc_range $(df_today) $(df_today) >/dev/null && df_ok "tempo-dc: worklogs readable" || { df_fail "tempo-dc: $DF_HTTP_ERR"; return 1 }
}
