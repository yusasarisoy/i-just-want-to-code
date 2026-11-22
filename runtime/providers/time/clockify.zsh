# Time provider: Clockify (API v1). Auth: X-Api-Key header.
# TIME_WORKSPACE is the workspace id, TIME_USER the user id (empty = token owner).
# Entries are stored in UTC; the description is "<KEY> <comment>"; TIME_TYPES values are tag ids.

_ck() { local m=$1 p=$2; shift 2; df_http "$TIME_TOKEN_SECRET" header:X-Api-Key $m "${${TIME_URL:-https://api.clockify.me/api/v1}%/}$p" "$@" }
_ck_json() { _ck $1 $2 -H 'Content-Type: application/json' --data-binary "$3" }
_ck_uid() {
  [[ -n $TIME_USER ]] && { print -r -- $TIME_USER; return }
  _ck GET /user || return 1
  jq -r .id <<<$DF_HTTP_BODY
}

_ck_range() {
  local uid from=$(df_iso_utc $(df_epoch $1)) to=$(df_iso_utc $(df_epoch $(df_add_days $2 1)))
  uid=$(_ck_uid) || return 1
  _ck GET "/workspaces/$TIME_WORKSPACE/user/$uid/time-entries?start=$(df_urlencode $from)&end=$(df_urlencode $to)&page-size=500" || return 1
  jq -c --argjson types "$(df_time_types_json)" --arg re "^${TICKET_KEY_REGEX}" '[.[] | select(.timeInterval.end != null) |
      (.timeInterval.start | sub("\\.[0-9]+"; "") | fromdateiso8601) as $s |
      (.timeInterval.end | sub("\\.[0-9]+"; "") | fromdateiso8601) as $e |
      ((.description // "") | capture("^(?<k>\\S+)\\s*(?<c>.*)$") // {k:"", c:""}) as $d |
      {id, key:(if ($d.k | test($re; "i")) then ($d.k|ascii_upcase) else "" end),
       comment:(if ($d.k | test($re; "i")) then $d.c else (.description // "") end),
       day:($s | strflocaltime("%Y-%m-%d")), start:($s | strflocaltime("%H:%M")), secs:($e - $s),
       type:((.tagIds // [])[0] as $v | ($types | to_entries | map(select(.value == $v and $v != null)) | .[0].key) // $v // "")}]' <<<$DF_HTTP_BODY
}

_ck_body() {
  local key=$1 day=$2 start=$3 secs=$4 type=$5 comment=$6 tag=$(df_time_type_value $5) e
  e=$(df_epoch $day $start)
  jq -nc --arg d "$key $comment" --arg s "$(df_iso_utc $e)" --arg en "$(df_iso_utc $(( e + secs )))" --arg tag "$tag" \
    '{description:$d, start:$s, end:$en, tagIds:(if $tag != "" then [$tag] else [] end)}'
}

time_list() { _ck_range $1 $1 }
time_create() { _ck_json POST "/workspaces/$TIME_WORKSPACE/time-entries" "$(_ck_body "$@")" && jq -r .id <<<$DF_HTTP_BODY }
time_update() { local id=$1; shift; _ck_json PUT "/workspaces/$TIME_WORKSPACE/time-entries/$id" "$(_ck_body "$@")" }
time_day_total() { time_list $1 | df_sum_secs }
time_week_totals() { _ck_range $1 $2 | df_group_days }

time_doctor() {
  [[ -n $TIME_WORKSPACE ]] || { df_fail "clockify: TIME_WORKSPACE is not set"; return 1 }
  _ck GET /user && df_ok "clockify: signed in as $(jq -r .email <<<$DF_HTTP_BODY)" || { df_fail "clockify: $DF_HTTP_ERR"; return 1 }
}
