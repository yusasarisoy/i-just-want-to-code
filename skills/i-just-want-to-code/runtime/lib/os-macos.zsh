# macOS layer: notifications, clipboard, open, secrets, hashing.

df_notify() {
  (( ${JUSTCODE_NOTIFY:-1} )) || return 0
  local title=$1 msg=$2 kind=${3:-info} sound=''
  (( ${JUSTCODE_SOUNDS:-1} )) && { [[ $kind == fail ]] && sound=Basso || sound=Glass }
  osascript -e 'on run argv' \
    -e 'if (item 3 of argv) is "" then' \
    -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
    -e 'else' \
    -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name (item 3 of argv)' \
    -e 'end if' -e 'end run' "$title" "$msg" "$sound" >/dev/null 2>&1 || true
}

df_clipboard() { print -rn -- "$1" | pbcopy }

# Copies HTML with a plain-text fallback so rich editors get links.
df_clipboard_rich() {
  local plain=$1 html=$2 hex
  hex=$(print -rn -- "$html" | xxd -p | tr -d '\n') || { df_clipboard "$plain"; return }
  osascript -e 'on run argv' \
    -e "set the clipboard to {«class HTML»:«data HTML${hex}», string:(item 1 of argv)}" \
    -e 'end run' "$plain" >/dev/null 2>&1 || df_clipboard "$plain"
}

df_open() { open "$1" >/dev/null 2>&1 }
df_open_app() { open -a "$1" >/dev/null 2>&1 }

df_os_secret() { security find-generic-password -s "$1" -w 2>/dev/null }
df_os_secret_store_cmd() { print -r -- "security add-generic-password -a \"\$USER\" -s ${(q-)1} -w" }

df_sha256() { shasum -a 256 "$1" | awk '{print $1}' }
