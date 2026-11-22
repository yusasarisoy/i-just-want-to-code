# Sandbox for persona tests: temp HOME, shims first on PATH, a mock server,
# a bare "origin" repo and a work clone. Nothing outside the temp dir is touched.
TESTS=${${(%):-%x}:A:h:h}
RUNTIME=$TESTS/../skills/i-just-want-to-code/runtime
RUNTIME=${RUNTIME:A}
source $TESTS/lib/assert.zsh

p_init() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/justcode-test.XXXXXX")
  export HOME=$T/home SHIM_STATE=$T/shim
  export JUSTCODE_NOTIFY=0 JUSTCODE_NO_FZF=1 MOCK_FAIL_FILE=$T/shim/fail
  unset JUSTCODE_SET JUSTCODE_CONFIG_DIR TICKET_PREFIX
  export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
  mkdir -p $HOME/.config/justcode $SHIM_STATE/secrets
  git config --global user.name tester
  git config --global user.email tester@example.com
  git config --global init.defaultBranch main
  export PATH=$TESTS/shims:$RUNTIME/bin:$PATH
  python3 $TESTS/mock/server.py --port 0 --port-file $T/port --log $SHIM_STATE/requests.log &
  MOCK_PID=$!
  repeat 100; do [[ -s $T/port ]] && break; sleep 0.05; done
  MOCK=http://127.0.0.1:$(<$T/port)
  : >$SHIM_STATE/requests.log
  : >$SHIM_STATE/curl.argv
  # zshexit runs only when the main shell exits, never in $( ) subshells.
  autoload -Uz add-zsh-hook
  add-zsh-hook zshexit p_cleanup
}

p_cleanup() {
  kill $MOCK_PID 2>/dev/null
  [[ -f $SHIM_STATE/vpn.pid ]] && kill $(<$SHIM_STATE/vpn.pid) 2>/dev/null
  rm -rf $T
}

# p_repo <remote-url-shown> <branch>: origin with main (+ release/1.2), work clone on <branch>.
p_repo() {
  local url=$1 branch=$2
  git init -q --bare $T/origin.git
  git init -q $T/seed && (cd $T/seed && git commit -q --allow-empty -m init && git push -q $T/origin.git main 2>/dev/null)
  git clone -q $T/origin.git $T/work 2>/dev/null
  cd $T/work
  git config remote.origin.url $url
  git config url.$T/origin.git.insteadOf $url
  git fetch -q origin
  git checkout -q -b $branch
  print -r -- "login" >login.txt; git add login.txt; git commit -q -m "Add login screen"
}

p_secret() { print -rn -- "$2" >$SHIM_STATE/secrets/$1 }
p_config() { print -r -- "$1" >$HOME/.config/justcode/config }
p_fail() { print -r -- "$1" >$MOCK_FAIL_FILE }
p_mark() { P_MARK=$(wc -l <$SHIM_STATE/requests.log) }

# Requests since the last p_mark that change something (read-only POSTs excluded).
p_writes() {
  tail -n +$(( P_MARK + 1 )) $SHIM_STATE/requests.log | while read -r m p rest; do
    case $m in
      GET) ;;
      POST)
        [[ $p == */graphql* && $rest != *mutation* ]] && continue
        [[ $p == */search* ]] && continue
        print -r -- "$m ${p%%\?*}" ;;
      *) print -r -- "$m ${p%%\?*}" ;;
    esac
  done
}

# Runs a command, capturing combined output in OUT and exit code in RC.
p_run() { OUT=$("$@" 2>&1); RC=$? }
