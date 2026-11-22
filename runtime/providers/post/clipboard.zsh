# Message target: the clipboard (rich HTML where the OS supports it).
post_send() {
  if [[ -n $2 ]]; then df_clipboard_rich "$1" "$2"; else df_clipboard "$1"; fi
}
