# VPN provider: command. VPN_STATUS_CMD exits 0 when connected; VPN_UP_CMD and
# VPN_DOWN_CMD connect and disconnect. Without VPN_UP_CMD, VPN_APP is opened.
# See references/network.md for presets of common clients.

vpn_status() {
  [[ -n $VPN_STATUS_CMD ]] || { df_unsupported status "vpn command (VPN_STATUS_CMD empty)"; return }
  zsh -c "$VPN_STATUS_CMD" >/dev/null 2>&1
}
vpn_up() {
  if [[ -n $VPN_UP_CMD ]]; then zsh -c "$VPN_UP_CMD"
  elif [[ -n $VPN_APP ]]; then df_open_app "$VPN_APP"
  else df_unsupported connect "vpn command (set VPN_UP_CMD or VPN_APP)"
  fi
}
vpn_down() {
  [[ -n $VPN_DOWN_CMD ]] || { df_unsupported disconnect "vpn command (VPN_DOWN_CMD empty)"; return }
  zsh -c "$VPN_DOWN_CMD"
}
vpn_doctor() {
  [[ -n $VPN_UP_CMD || -n $VPN_APP ]] && df_ok "vpn: connect command set" || { df_fail "vpn: set VPN_UP_CMD or VPN_APP"; return 1 }
  [[ -n $VPN_STATUS_CMD ]] || df_skip "vpn: VPN_STATUS_CMD empty (status comes from host checks)"
  return 0
}
