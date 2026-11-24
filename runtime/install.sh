#!/usr/bin/env zsh
# install.sh [-y] [-n]: copy this runtime to ~/.local/share/justcode and symlink
# its commands (and your personal custom commands) into ~/.local/bin.
# -y overwrites existing files without asking; -n shows what would happen.
emulate zsh
setopt extended_glob
src=${0:A:h}
prefix=${JUSTCODE_PREFIX:-$HOME/.local}
share=$prefix/share/justcode bindir=$prefix/bin
personal=${JUSTCODE_CONFIG_DIR:-$HOME/.config/justcode}/commands
reserved=(ship tpull tlog tcheck ticket build vpn standup release-notes nudge justcode justcode-post)  # not "builtins": zsh reserves that name
yes=0 dry=0
for a; do
  case $a in -y) yes=1 ;; -n) dry=1 ;; *) print -r -- "usage: install.sh [-y] [-n]"; exit 1 ;; esac
done
run() { if (( dry )); then print -r -- "[dry-run] $*"; else "$@"; fi }

for t in git curl jq; do (( $+commands[$t] )) || print -r -- "• $t is not installed; justcode needs it"; done

if [[ -e $share && ! -f $share/lib/justcode-lib.zsh ]]; then
  print -r -- "✗ $share exists and is not a justcode runtime; move it away first"; exit 1
fi
run rm -rf $share
run mkdir -p $share $bindir
run cp -R $src/. $share/
refs=$src/../plugin/skills/i-just-want-to-code/references
[[ -d $refs ]] && run cp -R $refs $share/docs
if [[ -d $src/../tests/unit ]]; then
  run mkdir -p $share/selftest
  run cp $src/../tests/unit/*.zsh $src/../tests/lib/assert.zsh $share/selftest/
fi
print -r -- "✓ runtime in $share"

link() {  # link <source> <name>
  local target=$bindir/$2 ans
  if [[ -L $target && ${target:A} == ${1:A} ]]; then print -r -- "• $2 already linked"; return; fi
  if [[ -e $target || -L $target ]]; then
    if (( ! yes )); then
      if [[ -t 0 ]]; then read -r "ans?$target exists. Overwrite? [y/N] "; else ans=n; fi
      [[ $ans == [yY]* ]] || { print -r -- "• kept $target (justcode's $2 not linked)"; return }
    fi
    run rm -f $target
  fi
  run ln -s $1 $target && { (( dry )) || print -r -- "✓ $2" }
}
for f in $src/bin/*(N); do link $share/bin/${f:t} ${f:t}; done
for f in $personal/*(N.); do
  (( ${reserved[(Ie)${f:t}]} )) && { print -r -- "✗ $f shadows a built-in command; not linked"; continue }
  chmod +x $f 2>/dev/null
  link $f ${f:t}
done
[[ :$PATH: == *:$bindir:* ]] || print -r -- "• add $bindir to your PATH"
print -r -- "next: justcode setup (or ask Claude to set up justcode), then: justcode doctor"
