# Time provider: Toggl Track (API v9). Auth: basic, secret value "<api-token>:api_token".
# TIME_WORKSPACE is the numeric workspace id. Entries are stored in UTC; the
# description is "<KEY> <comment>" and TIME_TYPES values are tag names.

_tg() { local m=$1 p=$2; shift 2; df_http "$TIME_TOKEN_SECRET" token-basic $m "${${TIME_URL:-https://api.track.toggl.com/api/v9}%/}$p" "$@" }
_tg_json() { _tg $1 $2 -H 'Content-Type: application/json' --data-binary "$3" }

_tg_range() {
  local from=$(df_iso_utc $(df_epoch $1)) to=$(df_iso_utc $(df_epoch $(df_add_days $2 1)))
  _tg GET "/me/time_entries?start_date=$(df_urlencode $from)&end_date=$(df_urlencode $to)" || return 1
  jq -c --argjson types "$(df_time_types_json)" --arg re "^${TICKET_KEY_REGEX}" '[.[] | select(.duration >= 0) |
      (.start | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) as $e |
      ((.description // "") | capture("^(?<k>\\S+)\\s*(?<c>.*)$") // {k:"", c:""}) as $d |
      {id:(.id|tostring), key:(if ($d.k | test($re; "i")) then ($d.k|ascii_upcase) else "" end),
       comment:(if ($d.k | test($re; "i")) then $d.c else (.description // "") end),
       day:($e | strflocaltime("%Y-%m-%d")), start:($e | strflocaltime("%H:%M")), secs:.duration,
       type:((.tags // [])[0] as $v | ($types | to_entries | map(select(.value == $v and $v != null)) | .[0].key) // $v // "")}]' <<<$DF_HTTP_BODY
}

_tg_body() {
  local key=$1 day=$2 start=$3 secs=$4 type=$5 comment=$6 tag=$(df_time_type_value $5)
  jq -nc --arg d "$key $comment" --arg s "$(df_iso_utc $(df_epoch $day $start))" --argjson t $secs --arg tag "$tag" --arg w "$TIME_WORKSPACE" \
    '{created_with:"justcode", description:$d, start:$s, duration:$t, workspace_id:($w|tonumber), tags:(if $tag != "" then [$tag] else [] end)}'
}

time_list() { _tg_range $1 $1 }
time_create() { _tg_json POST "/workspaces/$TIME_WORKSPACE/time_entries" "$(_tg_body "$@")" && jq -r .id <<<$DF_HTTP_BODY }
time_update() { local id=$1; shift; _tg_json PUT "/workspaces/$TIME_WORKSPACE/time_entries/$id" "$(_tg_body "$@")" }
time_day_total() { time_list $1 | df_sum_secs }
time_week_totals() { _tg_range $1 $2 | df_group_days }

time_doctor() {
  [[ -n $TIME_WORKSPACE ]] || { df_fail "toggl: TIME_WORKSPACE is not set"; return 1 }
  _tg GET /me && df_ok "toggl: signed in as $(jq -r .email <<<$DF_HTTP_BODY)" || { df_fail "toggl: $DF_HTTP_ERR"; return 1 }
}
