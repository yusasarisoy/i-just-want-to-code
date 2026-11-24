#!/usr/bin/env zsh
# Persona E, the minimal user: GitHub only, no tracker, no time, no deploy,
# no VPN, clipboard messages. Also covers custom commands.
source ${0:A:h}/../lib/env.zsh
p_init
p_repo https://github.com/alice/myapp.git feature/ABC-123-login
p_secret justcode-code-token fake-secret-code-e
p_config "CODE_PROVIDER=github
CODE_API_URL=$MOCK/github
CODE_USER=alice
DEPLOY_PREVIEW_URL=$MOCK/preview
DEMO_URL=$MOCK/preview"

print "ship"
p_mark; p_run ship -n
t_eq "ship -n exits 0" $RC 0
t_eq "ship -n sends no writes" "$(p_writes)" ""
t_has "ship -n plans the push" "$OUT" "[dry-run] git push -u origin feature/ABC-123-login"
t_has "ship -n plans the pull request" "$OUT" "[dry-run] create pull request feature/ABC-123-login -> main"
t_has "no tracker is a skip" "$OUT" "• ticket: no tracker configured"
t_lacks "no tracker secret is read" "$(<$SHIM_STATE/calls.log)" justcode-tracker-token

p_run env JUSTCODE_SET='CODE_USER=' ship -n
t_eq "empty CODE_USER: ship refuses" $RC 1
t_has "empty CODE_USER: clear reason" "$OUT" "CODE_USER is not set"
p_run env JUSTCODE_SET='CODE_USER=bob' ship -n
t_eq "token of another account: ship refuses" $RC 1
p_run env JUSTCODE_SET='CODE_TOKEN_SECRET=missing-entry' ship -n
t_eq "unreadable token: ship refuses (fail closed)" $RC 1
git checkout -q main
p_run ship -n
t_eq "ship from a target branch is refused" $RC 1
git checkout -q feature/ABC-123-login

p_mark; p_run ship
t_eq "real ship exits 0" $RC 0
t_eq "real ship makes exactly the expected writes" "$(p_writes)" "POST /github/repos/alice/myapp/pulls"
t_eq "branch pushed to origin" "$(git -C $T/origin.git rev-parse feature/ABC-123-login)" "$(git rev-parse HEAD)"
t_eq "message on the clipboard" "$(<$SHIM_STATE/clipboard)" "https://git.example.com/alice/myapp/pull/7"

print "standup"
print -r -- "STANDUP_PRE_HOOK='touch $T/standup-pre'" >>$HOME/.config/justcode/config
p_mark; p_run standup -n
t_eq "standup -n exits 0 without tracker or time" $RC 0
t_eq "standup -n sends no writes" "$(p_writes)" ""
t_has "no time tracker is a skip" "$OUT" "• time: no time tracker configured"
t_has "no tracker is a skip for today" "$OUT" "• today: no tracker configured"
t_has "pull requests still read" "$OUT" "✓ pull requests: 2 opened or updated"
t_has "empty today shows the none text" "$OUT" $'Today\nnone'
t_has "standup -n plans the pre hook only" "$OUT" "[dry-run] pre hook: touch"
t_no "the hook did not run in a dry run" test -e $T/standup-pre
p_run env JUSTCODE_SET='STANDUP_DAY=last-workday' standup -n
t_lacks "last-workday is never a Saturday" "$OUT" "(Sat)"
t_lacks "last-workday is never a Sunday" "$OUT" "(Sun)"
p_run env JUSTCODE_SET='STANDUP_MESSAGE=' standup -n
t_has "an emptied message sends nothing" "$OUT" "• message: STANDUP_MESSAGE is empty"
p_mark; p_run standup -b "Waiting for review"
t_eq "real standup exits 0" $RC 0
t_eq "real standup writes nothing remote" "$(p_writes)" ""
t_ok "the pre hook ran" test -e $T/standup-pre
t_has "standup message on the clipboard" "$(<$SHIM_STATE/clipboard)" $'Blockers\n- Waiting for review'

print "tcheck --fill"
p_mark; p_run tcheck --fill -n
t_eq "tcheck --fill without a time tracker exits 0" $RC 0
t_has "tcheck --fill without a time tracker is a skip" "$OUT" "• tcheck: no time tracker configured"
t_eq "tcheck --fill without a time tracker writes nothing" "$(p_writes)" ""

print "release-notes"
git tag v0.1.0
git commit -q --allow-empty -m "ABC-200 add the settings screen"
git commit -q --allow-empty -m "Bump the version"
p_mark; p_run release-notes -n v0.1.0
t_eq "release-notes -n exits 0 without a tracker" $RC 0
t_eq "release-notes -n sends no writes" "$(p_writes)" ""
t_has "no tracker is a skip" "$OUT" "• tickets: no tracker configured; 1 key(s) listed with their commit subject"
t_has "the key keeps its commit subject" "$OUT" "- ABC-200 ABC-200 add the settings screen"
t_has "ticketless commits are listed" "$OUT" "- Bump the version ("
p_run release-notes v0.1.0
t_has "notes on the clipboard" "$(<$SHIM_STATE/clipboard)" "### Other"

print "other commands"
p_run tlog -n ABC-123 9-10
t_eq "tlog without a time tracker stops" $RC 1
p_run ticket -n -t Task /dev/null
t_has "ticket without a tracker explains" "$OUT" "no tracker configured"
p_run build -n test 1.2.3 7
t_has "build without a deploy provider explains" "$OUT" "no deploy provider configured"
p_run justcode doctor
t_eq "doctor passes" $RC 0
t_has "doctor checks the token owner" "$OUT" "✓ github: token belongs to alice"
p_run justcode config
t_has "config shows the source file" "$OUT" "CODE_USER                    alice   # $HOME/.config/justcode/config"
t_has "config shows secret entry names only" "$OUT" "justcode-code-token   # default, secret entry name"
t_lacks "config never shows a secret value" "$OUT" fake-secret
t_has "a multi-line template stays on one line" "$OUT" "STANDUP_MESSAGE              \$'Yesterday\\n{yesterday}\\nToday\\n{today}\\nBlockers\\n{blockers}'   # default"

print "custom commands"
mkdir -p $HOME/.config/justcode/commands
cp $TESTS/fixtures/deploy-preview $HOME/.config/justcode/commands/
p_secret justcode-deploy-preview-token fake-secret-preview
p_run justcode command check deploy-preview
t_eq "fixture passes command check" $RC 0
p_mark; p_run justcode run deploy-preview -n
t_eq "custom command -n exits 0" $RC 0
t_eq "custom command -n sends no writes" "$(p_writes)" ""
t_has "custom command -n plans its write" "$OUT" "[dry-run] POST $MOCK/preview/deploy"
p_mark; p_run justcode run deploy-preview
t_eq "custom command real run" "$(p_writes)" "POST /preview/deploy"
t_has "custom command posts its link" "$(<$SHIM_STATE/clipboard)" "Preview of feature/ABC-123-login: https://preview.example.com/7"

p_run justcode command new demo
t_eq "skeleton created" $RC 0
p_secret justcode-demo-token fake-secret-demo
p_secret justcode-mark-token fake-secret-mark
p_run justcode command check demo
t_eq "skeleton passes command check" $RC 0
p_mark; p_run justcode run demo -n
t_eq "skeleton -n exits 0" $RC 0
t_eq "skeleton -n sends no writes" "$(p_writes)" ""
p_run justcode command new ship
t_eq "shadowing a built-in is refused" $RC 1
cp $HOME/.config/justcode/commands/demo $HOME/.config/justcode/commands/tlog
p_run justcode run tlog
t_eq "a personal file named like a built-in never runs" $RC 1

bad=$T/bad
print -r -- '#!/usr/bin/env zsh
source $DF_ROOT/lib/justcode-lib.zsh
curl -H "Authorization: Bearer $(cat token)" https://api.example.com/x
eval "$SOMETHING"' >$bad
p_run justcode command check $bad
t_eq "command check fails a bad command" $RC 1
t_has "catches raw curl" "$OUT" "raw curl/wget; use df_http"
t_has "catches eval" "$OUT" "eval is not allowed"
t_has "catches missing -n" "$OUT" "no -n handling"
print -r -- 'while getopts n o; do DF_DRY=1; done
source $DF_ROOT/lib/justcode-lib.zsh
x=1
x=2
x=3
x=4
x=5
x=6
x=7
df_http s bearer POST https://api.example.com/x' >$bad
p_run justcode command check $bad
t_has "catches an unguarded write" "$OUT" "write not guarded by the dry-run flag"

print "team commands need trust"
mkdir -p .justcode-commands
sed "s/demo/mark/; s/^df_hook PRE/touch $T:t-marker; df_hook PRE/" $HOME/.config/justcode/commands/demo >.justcode-commands/mark
p_run justcode run mark -n
t_eq "untrusted team command refused" $RC 1
t_has "untrusted team command message" "$OUT" "• mark is not trusted; review it, then run: justcode trust"
t_no "untrusted team command did not run" test -e $T:t-marker
p_run justcode command list
t_has "list shows trust state" "$OUT" "mark (NOT trusted)"
p_run zsh -c "print y | justcode trust $PWD/.justcode-commands/mark"
t_has "trust shows the content" "$OUT" "DF_CMD=mark"
p_run justcode run mark -n
t_eq "trusted team command runs" $RC 0
t_ok "trusted team command ran" test -e $T:t-marker
rm -f $T:t-marker
print -r -- '# changed' >>.justcode-commands/mark
p_run justcode run mark -n
t_eq "changed team command is blocked again" $RC 1
t_no "changed team command did not run" test -e $T:t-marker
p_run zsh -c "print y | justcode trust $PWD/.justcode-commands/mark"
t_has "trust shows the diff since last time" "$OUT" "+# changed"
p_run justcode doctor commands
t_has "doctor checks custom commands" "$OUT" "deploy-preview: follows the command contract"

print "nudge"
p_mark; p_run nudge -n
t_eq "nudge -n exits 0" $RC 0
t_eq "nudge -n sends no writes" "$(p_writes)" ""
t_has "nudge -n shows the message" "$OUT" "@bob these pull requests are waiting for your review:"
p_run env JUSTCODE_SET='NUDGE_MESSAGE=' nudge -n
t_has "an emptied message sends nothing" "$OUT" "• message: NUDGE_MESSAGE is empty"
p_run nudge -y
t_has "nudge message on the clipboard" "$(<$SHIM_STATE/clipboard)" "- Pull request 7"

print "secrets"
t_lacks "no secret value in any curl argv" "$(<$SHIM_STATE/curl.argv)" fake-secret
t_done
