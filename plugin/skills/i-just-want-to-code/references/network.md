# Network and VPN

Most setups need no VPN: keep `VPN_PROVIDER=none` (the default). Every operation is then a no-op and hosts are called directly.

## How the wait works
Before the first call to a host that needs the VPN (`VPN_HOSTS`, or every tracker and code host when `VPN_HOSTS` is empty and the provider is `command`), justcode:

1. checks the host (any TLS answer counts as reachable);
2. if it does not answer, runs `vpn_up` in the background (`VPN_UP_CMD`, or opens `VPN_APP`);
3. polls the host every 5 s until it answers or `NETWORK_WAIT_SECS` (default 120) runs out;
4. on timeout prints `✗ <host> is still not reachable ...; connect the VPN (vpn up) and run again` and stops before any write.

It never hangs: the wait is bounded even when the connect command itself blocks. `vpn status|up|down|re|watch` drives the same provider by hand; `justcode agent install` runs `vpn watch` in the background (LaunchAgent on macOS, systemd user unit on Linux).

## Provider `command`
| key | meaning |
|---|---|
| `VPN_UP_CMD` | connects (may prompt; runs with `zsh -c`) |
| `VPN_DOWN_CMD` | disconnects |
| `VPN_STATUS_CMD` | exits 0 when connected; empty = judge by the hosts only |
| `VPN_APP` | app to open when there is no connect command |
| `VPN_HOSTS` | hosts that need the VPN, e.g. `(jira.example.com git.example.com)`; a pattern such as `*.example.com` is probed as `x.example.com` |

## Presets
None of these is a default. Each one is **verify on your machine**: install paths, profile names and whether the command needs `sudo` vary by version and OS. Replace `vpn.example.com` and profile names with your own.

**Cisco Secure Client / AnyConnect** (verify on your machine)
```zsh
VPN_PROVIDER=command
VPN_UP_CMD='/opt/cisco/secureclient/bin/vpn -s connect vpn.example.com'   # older: /opt/cisco/anyconnect/bin/vpn
VPN_DOWN_CMD='/opt/cisco/secureclient/bin/vpn disconnect'
VPN_STATUS_CMD='/opt/cisco/secureclient/bin/vpn state | grep -q "state: Connected"'
```

**Palo Alto GlobalProtect** (verify on your machine). macOS has no supported CLI, so use the app fallback:
```zsh
VPN_PROVIDER=command
VPN_APP=GlobalProtect
# Linux CLI client:
# VPN_UP_CMD='globalprotect connect --portal vpn.example.com'
# VPN_DOWN_CMD='globalprotect disconnect'
# VPN_STATUS_CMD='globalprotect show --status | grep -q Connected'
```

**Zscaler Client Connector** (verify on your machine). App only; status comes from the hosts:
```zsh
VPN_PROVIDER=command
VPN_APP='Zscaler'
```

**Cloudflare WARP** (verify on your machine)
```zsh
VPN_PROVIDER=command
VPN_UP_CMD='warp-cli connect'
VPN_DOWN_CMD='warp-cli disconnect'
VPN_STATUS_CMD='warp-cli status | grep -q Connected'
```

**Tailscale** (verify on your machine)
```zsh
VPN_PROVIDER=command
VPN_UP_CMD='tailscale up'
VPN_DOWN_CMD='tailscale down'
VPN_STATUS_CMD='tailscale status >/dev/null'
```

**WireGuard** (verify on your machine; usually needs sudo)
```zsh
VPN_PROVIDER=command
VPN_UP_CMD='sudo wg-quick up wg0'
VPN_DOWN_CMD='sudo wg-quick down wg0'
VPN_STATUS_CMD='sudo wg show wg0 >/dev/null 2>&1'
```

**OpenVPN** (verify on your machine)
```zsh
VPN_PROVIDER=command
VPN_UP_CMD='sudo openvpn --config ~/vpn/example.ovpn --daemon'
VPN_DOWN_CMD='sudo pkill -f "openvpn --config"'
VPN_STATUS_CMD='pgrep -f "openvpn --config" >/dev/null'
# NetworkManager: VPN_UP_CMD='nmcli connection up id example-vpn'
```

**FortiClient** (verify on your machine). The GUI client has no stable CLI; use the app, or `openfortivpn` on Linux:
```zsh
VPN_PROVIDER=command
VPN_APP=FortiClient
# Linux: VPN_UP_CMD='sudo openfortivpn vpn.example.com:443 -u alice'
#        VPN_DOWN_CMD='sudo pkill openfortivpn'
```

Passwords and one-time codes are entered by you in the client's own prompt; justcode never stores them.
