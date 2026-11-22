# Message target: Microsoft Teams (incoming webhook or workflow URL in TEAMS_WEBHOOK_SECRET).
# TEAMS_PAYLOAD=text sends {"text": ...}; adaptive-card wraps the text in an Adaptive Card.
post_send() {
  local body
  if [[ $TEAMS_PAYLOAD == adaptive-card ]]; then
    body=$(jq -nc --arg t "$1" '{type:"message", attachments:[{contentType:"application/vnd.microsoft.card.adaptive",
      content:{type:"AdaptiveCard", version:"1.4", "$schema":"http://adaptivecards.io/schemas/adaptive-card.json",
      body:[{type:"TextBlock", text:$t, wrap:true}]}}]}')
  else
    body=$(jq -nc --arg t "$1" '{text:$t}')
  fi
  df_http "$TEAMS_WEBHOOK_SECRET" url POST - -H 'Content-Type: application/json' --data-binary "$body" ||
    { print -ru2 -- "  teams: $DF_HTTP_ERR"; return 1 }
}
