# macOS and Linux

All runtime code is zsh (preinstalled on macOS; `apt install zsh` / `dnf install zsh` on Linux) plus `git`, `curl` and `jq`. OS differences live only in `runtime/lib/os-macos.zsh` and `runtime/lib/os-linux.zsh`; the lib picks one by `uname`.

| need | macOS | Linux |
|---|---|---|
| read a secret | `security find-generic-password -s NAME -w` | `secret-tool lookup service NAME` (libsecret) |
| store a secret | `security add-generic-password -a "$USER" -s NAME -w` (prompts) | `secret-tool store --label=NAME service NAME` (prompts) |
| clipboard | `pbcopy`; rich HTML through `osascript` | `wl-copy` (Wayland) or `xclip -selection clipboard`; HTML with `--type text/html` / `-t text/html` |
| notification | `osascript display notification` (sounds with `JUSTCODE_SOUNDS=1`) | `notify-send`; sound with `canberra-gtk-play` if present |
| open a URL | `open` | `xdg-open` |
| open an app | `open -a NAME` | not used (set `VPN_UP_CMD`) |
| background agent | LaunchAgent (`launchctl`) | systemd user unit (`systemctl --user`) |
| sha256 | `shasum -a 256` | `sha256sum` |
| dates | `zsh/datetime` (`strftime`) on both; no GNU/BSD `date` differences | same |

Install locations are the same on both: runtime in `~/.local/share/justcode`, commands linked into `~/.local/bin`, config in `~/.config/justcode/`. Make sure `~/.local/bin` is on `PATH`.

Windows: use WSL with the Linux column.
