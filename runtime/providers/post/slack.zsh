# Message target: Slack incoming webhook. The webhook URL is the secret SLACK_WEBHOOK_SECRET.
post_send() {
  df_http "$SLACK_WEBHOOK_SECRET" url POST - -H 'Content-Type: application/json' \
    --data-binary "$(jq -nc --arg t "$1" '{text:$t}')" || { print -ru2 -- "  slack: $DF_HTTP_ERR"; return 1 }
}
