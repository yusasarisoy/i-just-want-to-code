# Message target: generic webhook. POSTs {"text": ..., "html": ...} to the URL in WEBHOOK_SECRET.
post_send() {
  df_http "$WEBHOOK_SECRET" url POST - -H 'Content-Type: application/json' \
    --data-binary "$(jq -nc --arg t "$1" --arg h "${2:-}" '{text:$t} + (if $h != "" then {html:$h} else {} end)')" ||
    { print -ru2 -- "  webhook: $DF_HTTP_ERR"; return 1 }
}
