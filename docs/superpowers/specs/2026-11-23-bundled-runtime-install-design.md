# Runtime installed by Claude on approval

## Intent

justcode should be adopted by people who find it in the Claude plugin directory, and stand out there. Today a directory install brings only the skill; the skill sends the user to GitHub to clone the repository and run `install.sh` themselves ("The user installs it; Claude does not"). That is six steps and two context switches before the first `ship -n`, and it is where a new user is most likely to give up.

The owner already uses justcode daily; this work is for new users.

## Goals

- A user who installs the plugin from the directory reaches a working `justcode version` without leaving Claude: Claude fetches the runtime at the plugin's own version, shows `install.sh -n`, asks, and installs on yes.
- When the plugin is newer than the installed runtime, the skill offers the same fetch, dry run and install as an update.
- Existing users (own clone, `~/.local/share/justcode`) keep working with no action.

## Non-goals

- `justcode update` as a separate command, and a Homebrew tap: the skill-driven update covers both.
- Other items from the idea list (completion, standup, new providers, `doctor --json`, lint).
- Changing where the runtime installs (`${JUSTCODE_PREFIX:-$HOME/.local}/share/justcode`, links in `…/bin`).

## Anti-goals

- Any download or install without the user's yes for that run.
- Installing anything other than the release that matches the plugin version.
- Claude overwriting a user's own executable or editing shell startup files without a separate yes.
- Touching the runtime code (the audit fixes run in parallel on `runtime/`).

## Constraints

- **The directory requires a skill-only plugin** (owner, 2026-11-23). The commit "Move the plugin into a skill-only folder and the runtime to the repo root" moved the runtime out of `plugin/` for this reason; the runtime stays at the repo root.
- The directory scan reads the skill text and has flagged prohibitions as commands before (commit "Reword skill docs so the directory scan stops flagging prohibitions as commands"); install steps are written as conditional, user-approved steps.
- The version lives in `DF_VERSION` (`runtime/lib/justcode-lib.zsh`), `plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`. Releases are pinned by a git tag `v<version>`; none exist yet.
- `install.sh` with no terminal keeps every existing file in the bin dir and prints `• kept <path> (justcode's <name> not linked)`; a missing PATH entry prints `• add <bindir> to your PATH`.

## Approaches

- **A. Bundle the runtime inside the plugin.** Chosen first, then rejected: the directory requires a skill-only plugin, which is why the runtime was moved out the day before.
- **B. Claude fetches the tagged release from the repository and runs its `install.sh` (chosen).** No runtime change, plugin stays skill-only, the installed code is exactly the tagged release matching the plugin version. Cost: a tag per release; one network fetch, approved by the user.
- **C. Homebrew tap.** A second repository to maintain, weak on Linux/WSL, update channel separate from the plugin.

## Decided

- Claude installs the runtime after showing the dry run and getting a yes (owner).
- Existing files in the bin dir are never overwritten on the install yes; each gets its own yes (owner).
- A missing PATH entry: Claude shows the line and the file, adds it on yes (owner).
- The audit fixes land independently; this work changes no runtime file (owner ordering, kept).
- Approach B (Claude's call after A was ruled out by the directory rule; owner asked to proceed without further questions).

## Design (skill text only, plus docs)

1. **Runtime check, once per session, before any justcode step** (new `SKILL.md` §1.1):
   - Plugin version = `.version` of `<skill base>/../../.claude-plugin/plugin.json`; release tag `v<version>`.
   - Managed source = `${JUSTCODE_PREFIX:-$HOME/.local}/share/justcode-src` (a shallow clone Claude made).
   - `justcode` not found → ask to fetch (state URL, tag, folder); on yes `git clone --depth 1 --branch v<version> <repo> <src>`; then `zsh <src>/runtime/install.sh -n`, show it condensed, ask; on yes `zsh <src>/runtime/install.sh` (never `-y`).
   - Found and older than the plugin, and the managed source exists → same flow as an update: fetch the tag into the managed source, check it out, dry run, ask, install. A no is not asked again that session.
   - Found and older, no managed source (own clone) → say so and how to update it from the clone; do not reinstall.
   - Tag missing → say the release is not published yet; stop.
2. **After install:** each `• kept` line → show what the file is, ask for that file alone, `ln -sf` on yes. `• add … to your PATH` → show the line and the startup file (`~/.zshrc` for zsh, `~/.bashrc` for bash), append on yes; on no use full paths this session.
3. **§2.4 step 1** points to §1.1. **§3** notes that files added by hand under the installed runtime are replaced on reinstall.
4. **Plugin description, `plugin/README.md`, `README.md`:** Claude installs the runtime on approval; manual clone stays as the no-Claude path.
5. **Release (owner):** bump the three version fields, merge, push tag `v<version>`, then submit the new version in the directory.

## Left to the builder

- Exact wording of §1.1, keeping the scan-safe style of the rest of `SKILL.md`.
