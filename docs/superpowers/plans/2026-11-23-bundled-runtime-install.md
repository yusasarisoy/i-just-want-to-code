# Runtime Install by Claude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The skill fetches the runtime release matching the plugin version, shows `install.sh -n`, and installs it on the user's yes; it offers the same as an update when the plugin is newer.

**Architecture:** Skill text and docs only. The plugin stays skill-only (directory rule); the runtime stays in `runtime/`; releases are pinned by tag `v<version>`.

**Tech Stack:** Markdown skill, zsh runtime (unchanged), git.

**Spec:** `docs/superpowers/specs/2026-11-23-bundled-runtime-install-design.md`

## Global Constraints

- No file under `runtime/` or `tests/` changes (audit fixes run in parallel there).
- Managed source: `${JUSTCODE_PREFIX:-$HOME/.local}/share/justcode-src`; tag `v<plugin version>`; repo `https://github.com/yusasarisoy/i-just-want-to-code.git`.
- Every fetch and install needs its own yes; never `install.sh -y`.
- `claude plugin validate --strict` and `--profile directory` stay clean.
- No commits without the owner's order.

## Review Focus

- Release tag not pushed yet → Claude stops and says so (sandbox check, Task 2).
- `justcode` found but from the user's own clone → no reinstall (sandbox check).
- Existing foreign `ship` in the bin dir → kept and reported (sandbox check).
- Path with a space in `JUSTCODE_PREFIX` → commands quoted (skill text review).
- Scan flags the new text as commands → rerun validate with the directory profile.

---

### Task 1: Skill, description, READMEs

**Files:** `plugin/skills/i-just-want-to-code/SKILL.md` (§1.1 new, §2.4 step 1, §3), `plugin/.claude-plugin/plugin.json` (description), `plugin/README.md`, `README.md` (install).

- [ ] Write §1.1 per spec Design 1-2; replace §2.4 step 1; add the §3 note.
- [ ] Update the description and both READMEs.
- [ ] `claude plugin validate --strict . && claude plugin validate --strict --profile directory .` → pass.

### Task 2: Sandbox check of the commands the skill names

- [ ] In the scratchpad: make a local bare copy of this repo with tag `v9.9.9`, run the §1.1 commands against it with a temp `HOME`/`JUSTCODE_PREFIX` (path with a space): clone by tag, `install.sh -n` writes nothing, install without a terminal keeps a foreign `ship`, `justcode version` works, missing tag fails cleanly, update by fetching a second tag.
- [ ] `zsh tests/run.zsh` → TOTAL fail 0 (unchanged runtime).

### Task 3: Release (owner)

- [ ] Bump the three version fields, merge, push tag `v<version>`, check the directory Review tab, Submit latest version → Request publishing.
