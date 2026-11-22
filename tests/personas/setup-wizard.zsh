#!/usr/bin/env zsh
# justcode setup driven through a pseudo-terminal for personas A and E; the
# written config must equal tests/fixtures/setup/<persona>.config.
source ${0:A:h}/../lib/env.zsh
p_init

# Runs `justcode setup [args]` on a pseudo-terminal, typing one answer per prompt.
# (script(1) is not used: on macOS it sends an EOF first when stdin is a file.)
pty_run() {
  local answers=$1; shift
  python3 -c 'import pty' 2>/dev/null || return 99
  python3 $TESTS/lib/pty_feed.py $answers justcode setup "$@"
}

check_fixture() {
  local name=$1 want got
  want=$(sed "s#@MOCK@#$MOCK#g" $TESTS/fixtures/setup/$name.config)
  got=$(<$HOME/.config/justcode/config)
  t_eq "setup $name: written config equals the fixture" "$got" "$want"
}

print "no terminal"
p_run justcode setup </dev/null
t_eq "setup without a TTY exits 1" $RC 1
t_has "setup without a TTY explains" "$OUT" "justcode setup needs a terminal; ask Claude to run the setup instead, or edit the file with: justcode edit"

print "persona E"
p_repo https://github.com/alice/myapp.git feature/ABC-123-login
p_secret justcode-code-token fake-secret-setup
: >$HOME/.config/justcode/config && rm $HOME/.config/justcode/config
print -l '' '' '' "$MOCK/github" alice '' '' '' '' none none '' '' '' '' '' '' '' '' '' '' '' >$T/answers-e
pty_run $T/answers-e >$T/out-e 2>&1; rc=$?
if (( rc == 99 )); then
  t_skip "setup E scripted run" "no usable script(1)"
else
  check_fixture e
  t_has "setup E shows detection" "$(<$T/out-e)" "Code host: github (from the remote github.com)"
  t_has "setup E previews the template" "$(<$T/out-e)" "preview: https://git.example.com/pr/1"
  cp $HOME/.config/justcode/config $T/before
  pty_run $T/answers-e >/dev/null 2>&1
  t_eq "re-running with the same answers changes nothing" "$(cmp -s $T/before $HOME/.config/justcode/config && print same)" same
  t_has "re-run reports nothing changed" "$(pty_run $T/answers-e 2>&1)" "nothing changed"
fi

print "persona A"
rm -f $HOME/.config/justcode/config
mkdir -p $T/work/MyApp.xcworkspace
p_secret justcode-tracker-token fake-secret-setup
p_secret justcode-slack-webhook "$MOCK/hooks/slack"
print -l '' '' '' "$MOCK/github" alice '' '' bob '' \
  jira-cloud "$MOCK/jira-cloud" alice@example.com '' '' '' '' \
  '' \
  '' '' '' '' '' '' \
  '' \
  2 '' slack '' '' 1,2 '' '' '' '' >$T/answers-a
pty_run $T/answers-a >$T/out-a 2>&1; rc=$?
if (( rc == 99 )); then
  t_skip "setup A scripted run" "no usable script(1)"
else
  check_fixture a
  t_has "setup A previews the chosen template" "$(<$T/out-a)" "preview: Add login screen: https://git.example.com/pr/1"
  t_has "setup A runs doctor afterwards" "$(<$T/out-a)" "jira-cloud: signed in as alice@example.com"
  t_lacks "setup never prints a secret value" "$(<$T/out-a)" fake-secret
fi

print "team layer"
print -l '' "$MOCK/github" carol '' '' '' '' >$T/answers-t
if (( rc != 99 )); then
  rm -f $HOME/.config/justcode/config
  pty_run $T/answers-t code --layer team >$T/out-t 2>&1
  t_has "personal key moved out of the team file" "$(<$T/out-t)" "CODE_USER is personal; it goes to the global config"
  t_lacks "team file has no personal key" "$(<$T/work/.justcode)" CODE_USER
  t_has "team file got the team key" "$(<$T/work/.justcode)" "CODE_API_URL=$MOCK/github"
  t_has "global file got the personal key" "$(<$HOME/.config/justcode/config)" "CODE_USER=carol"
fi
t_done
