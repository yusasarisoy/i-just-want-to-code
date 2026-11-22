#!/usr/bin/env zsh
# Pure string helpers: status map, ticket keys, templates, separators, remotes.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../runtime}
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX"); cd $HOME
source $DF_ROOT/lib/justcode-lib.zsh

print "status map"
STATUS_MAP=( 'feature/*' 'In Review' 'bugfix/*' 'Ready for Test' )
STATUS_ON_SHIP='Code Review'
t_eq "feature glob" "$(df_status_for_branch feature/ABC-1-x)" "In Review"
t_eq "bugfix glob" "$(df_status_for_branch bugfix/ABC-2)" "Ready for Test"
t_eq "fallback to STATUS_ON_SHIP" "$(df_status_for_branch alice/ABC-3)" "Code Review"
STATUS_MAP=()
t_eq "empty map falls back" "$(df_status_for_branch feature/x)" "Code Review"

print "ticket keys"
t_eq "feature/ABC-12-x" "$(df_ticket_from_branch feature/ABC-12-x)" ABC-12
t_eq "lowercase linear branch" "$(df_ticket_from_branch alice/eng-42-y)" ENG-42
t_eq "fix-typo has no key" "$(df_ticket_from_branch fix-typo)" ''
t_no "fix-typo returns failure" df_ticket_from_branch fix-typo
TICKET_PREFIX=abc
t_eq "bare number uses TICKET_PREFIX" "$(df_ticket_key 123)" ABC-123
t_eq "full key upper-cased" "$(df_ticket_key eng-7)" ENG-7
TICKET_PREFIX=''
t_no "bare number without prefix fails" df_ticket_key 123

print "templates"
t_eq "fill url and title" "$(df_fill '{title}: {url}' url https://git.example.com/pr/1 title Login)" "Login: https://git.example.com/pr/1"
t_eq "unknown placeholder kept" "$(df_fill '{nope} {url}' url u)" "{nope} u"
t_eq "repeated placeholder" "$(df_fill '{a}{a}' a x)" xx
SHIP_MESSAGE=custom
t_eq "default template with set value has no stray brace" "${SHIP_MESSAGE:-"{url}"}" custom
t_eq "default template with unset value" "${UNSET_MESSAGE:-"{url}"}" "{url}"
t_eq "the buggy form appends a brace (why the rule exists)" "${SHIP_MESSAGE:-{url}}" "custom}"

print "ticket separator"
TICKET_SEPARATOR='***'
f=$HOME/drafts.txt
print -r -- $'First title\nline one\n\n***\nSecond title\n**\n* not a separator\n***\n\n' >$f
df_split_tickets $f
t_eq "two tickets split on a literal ***" ${#DF_T_TITLES} 2
t_eq "first title" "$DF_T_TITLES[1]" "First title"
t_eq "first description" "$DF_T_DESCS[1]" "line one"
t_eq "glob-like lines stay in the description" "$DF_T_DESCS[2]" $'**\n* not a separator'
TICKET_SEPARATOR='---8<---'
print -r -- $'Only one\nbody' >$f
df_split_tickets $f
t_eq "file without separator is one ticket" ${#DF_T_TITLES} 1

print "remotes"
t_eq "https remote" "$(df_parse_remote https://git.example.com/alice/myapp.git)" "git.example.com alice/myapp"
t_eq "https remote with port" "$(df_parse_remote https://git.example.com:8443/team/sub/myapp)" "git.example.com:8443 team/sub/myapp"
t_eq "scp-style remote" "$(df_parse_remote git@git.example.com:alice/myapp.git)" "git.example.com alice/myapp"
t_eq "ssh:// remote with port 2222" "$(df_parse_remote ssh://git@git.example.com:2222/alice/myapp.git)" "git.example.com alice/myapp"
t_no "local path is not a remote" df_parse_remote /srv/repos/myapp.git
t_eq "provider from host" "$(df_detect_code_provider gitlab.example.com)" gitlab

rm -rf $HOME
t_done
