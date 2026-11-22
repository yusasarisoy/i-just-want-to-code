# VPN provider: none. Every operation is a no-op.
vpn_status() { return 0 }
vpn_up() { return 0 }
vpn_down() { return 0 }
vpn_doctor() { df_skip "vpn: none configured"; return 0 }
