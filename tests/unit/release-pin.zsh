#!/usr/bin/env zsh
# The skill installs only the pinned runtime: its version and checksum must
# match plugin.json and the runtime files in this commit, or every install stops.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh
REPO=${HERE:h:h}
SKILL=$REPO/plugin/skills/i-just-want-to-code/SKILL.md

print "pinned release"
pin=${(M)${(f)"$(<$SKILL)"}:#- \*\*Pinned release.\*\**}
version=$(jq -r .version $REPO/plugin/.claude-plugin/plugin.json)
sum=$(git -C $REPO ls-files -z runtime | (cd $REPO && xargs -0 shasum -a 256) | shasum -a 256 | awk '{print $1}')
t_has "the skill pins the plugin version" "$pin" "Version \`$version\`, tag \`v$version\`"
t_has "the skill pins this commit's runtime checksum" "$pin" "\`$sum\`"

t_done
