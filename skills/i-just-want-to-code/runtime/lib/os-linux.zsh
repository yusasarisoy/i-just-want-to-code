# Linux layer: notifications, clipboard, open, secrets, hashing.

df_notify() {
  (( ${JUSTCODE_NOTIFY:-1} )) || return 0
  local title=$1 msg=$2 kind=${3:-info}
  (( $+commands[notify-send] )) && notify-send -- "$title" "$msg" >/dev/null 2>&1
  if (( ${JUSTCODE_SOUNDS:-1} )) && (( $+commands[canberra-gtk-play] )); then
    [[ $kind == fail ]] && canberra-gtk-play -i dialog-error >/dev/null 2>&1 &!
    [[ $kind != fail ]] && canberra-gtk-play -i complete >/dev/null 2>&1 &!
  fi
  return 0
}

df_clipboard() {
  if (( $+commands[wl-copy] )) && [[ -n $WAYLAND_DISPLAY ]]; then print -rn -- "$1" | wl-copy
  elif (( $+commands[xclip] )); then print -rn -- "$1" | xclip -selection clipboard
  elif (( $+commands[xsel] )); then print -rn -- "$1" | xsel --clipboard --input
  else return 1
  fi
}

df_clipboard_rich() {
  local plain=$1 html=$2
  if (( $+commands[wl-copy] )) && [[ -n $WAYLAND_DISPLAY ]]; then print -rn -- "$html" | wl-copy --type text/html
  elif (( $+commands[xclip] )); then print -rn -- "$html" | xclip -selection clipboard -t text/html
  else df_clipboard "$plain"
  fi
}

df_open() { xdg-open "$1" >/dev/null 2>&1 &! }
df_open_app() { { gtk-launch "$1" || "$1" } >/dev/null 2>&1 &! }

df_os_secret() { secret-tool lookup service "$1" 2>/dev/null }
df_os_secret_store_cmd() { print -r -- "secret-tool store --label=${(q-)1} service ${(q-)1}" }

df_sha256() { sha256sum "$1" | awk '{print $1}' }
