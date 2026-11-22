#!/usr/bin/env zsh
# install.sh from a clone: dry run writes nothing, a real run installs the
# runtime, docs and self-tests, links the commands, and guards built-in names.
source ${0:A:h}/../lib/assert.zsh
INSTALL=${0:A:h}/../../runtime/install.sh
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-install.XXXXXX")
export JUSTCODE_PREFIX=$HOME/.local
trap 'rm -rf $HOME' EXIT
share=$JUSTCODE_PREFIX/share/justcode bin=$JUSTCODE_PREFIX/bin

print "dry run"
out=$(zsh $INSTALL -n 2>&1); rc=$?
t_eq "install -n exits 0" $rc 0
t_has "install -n plans the copy" "$out" "[dry-run] cp -R"
t_eq "install -n writes nothing" "$(ls -A $HOME)" ""

print "real run"
mkdir -p $HOME/.config/justcode/commands
print -r -- 'print hi' >$HOME/.config/justcode/commands/hello
print -r -- 'print shadow' >$HOME/.config/justcode/commands/ship
out=$(zsh $INSTALL -y 2>&1); rc=$?
t_eq "install exits 0" $rc 0
t_ok "runtime lib copied" test -f $share/lib/justcode-lib.zsh
t_ok "config reference copied" test -f $share/docs/config.md
t_ok "self-tests copied" test -f $share/selftest/assert.zsh
t_eq "justcode link target" "$(readlink $bin/justcode)" "$share/bin/justcode"
t_eq "personal command linked" "$(readlink $bin/hello)" "$HOME/.config/justcode/commands/hello"
t_has "built-in name is not shadowed" "$out" "shadows a built-in command"
t_eq "ship still points at the runtime" "$(readlink $bin/ship)" "$share/bin/ship"

print "second run"
out=$(zsh $INSTALL -y 2>&1); rc=$?
t_eq "reinstall exits 0" $rc 0
t_has "existing links are kept" "$out" "justcode already linked"
t_done
