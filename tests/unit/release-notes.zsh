#!/usr/bin/env zsh
# release-notes helpers: ticket keys in text, groups by type, markdown layout.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../runtime}
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX"); cd $HOME
source $DF_ROOT/lib/justcode-lib.zsh
source $DF_ROOT/lib/reports.zsh

print "ticket keys"
t_eq "every key, once, in order" "$(df_rn_keys 'ABC-1 fix; refs abc-2 and ABC-1')" $'ABC-1\nABC-2'
t_eq "a merge subject names its branch" "$(df_rn_keys 'Merge pull request #12 from alice/feature/ENG-42-x')" ENG-42
t_eq "no key, nothing" "$(df_rn_keys 'Bump the version')" ''
TICKET_KEY_REGEX='#[0-9]+'
t_eq "the key regex is the user's" "$(df_rn_keys 'Fix #12 and #13')" $'#12\n#13'
TICKET_KEY_REGEX='[A-Za-z][A-Za-z0-9]+-[0-9]+'

print "groups"
t_eq "Story is a feature" "$(df_rn_group Story)" Features
t_eq "types match without case" "$(df_rn_group bug)" Fixes
t_eq "anything else falls to the catch-all" "$(df_rn_group Task)" Other
t_eq "no type falls to the catch-all" "$(df_rn_group '')" Other
RELEASE_NOTES_GROUPS=(New 'Story,Feature*' Repaired 'Bug,Defect')
RELEASE_NOTES_NO_TICKET_GROUP=Misc
t_eq "user groups and globs" "$(df_rn_group 'Feature request')" New
t_eq "second glob of a group" "$(df_rn_group Defect)" Repaired
t_eq "no match goes to the no-ticket group" "$(df_rn_group Chore)" Misc

print "markdown"
RELEASE_NOTES_GROUPS=(Features 'Story' Fixes 'Bug' Other '*') RELEASE_NOTES_NO_TICKET_GROUP=Other
RELEASE_NOTES_HEADER='## {to}' RELEASE_NOTES_GROUP_HEADER='### {group}'
items='[{"group":"Other","line":"- Bump"},{"group":"Fixes","line":"- ABC-2 Crash"},{"group":"Features","line":"- ABC-1 Login"}]'
t_eq "groups in configured order, blank line between" "$(df_rn_render v1 v2 $items)" "## v2

### Features
- ABC-1 Login

### Fixes
- ABC-2 Crash

### Other
- Bump"
t_lacks "an empty group is left out" "$(df_rn_render v1 v2 '[{"group":"Other","line":"- Bump"}]')" Features
RELEASE_NOTES_HEADER=''
t_eq "an emptied header is left out" "$(df_rn_render v1 v2 '[{"group":"Other","line":"- x"}]')" $'### Other\n- x'
RELEASE_NOTES_GROUP_HEADER=''
t_eq "emptied group headers too" "$(df_rn_render v1 v2 '[{"group":"Other","line":"- x"}]')" "- x"
RELEASE_NOTES_GROUP_HEADER='### {group}'
t_has "a group not in the list still shows" "$(df_rn_render v1 v2 '[{"group":"Docs","line":"- d"}]')" "### Docs"
RELEASE_NOTES_HEADER='## {to}'
t_eq "nothing to say, not even the header" "$(df_rn_render v1 v2 '[]')" ""

rm -rf $HOME
t_done
