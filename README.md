# um-agentic-engineering

A shared [Kiro](https://kiro.dev) toolkit: skills and steering that install
once per workstation and are then available from every repository, without
copying anything into those repositories.

## Install

```sh
git clone git@github.com:jakubkeller/um-agentic-engineering.git
cd um-agentic-engineering
./install.sh
```

Day-to-day, once set up: `agentic-eng install|update|version|rollback|uninstall`.
See [docs/SETUP.md](docs/SETUP.md) for prerequisites, verification, and
uninstall, and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
for common failure recovery.

## Usage

Once installed, both skills are available from Kiro's chat in **any**
repository — nothing to import or configure per-repo:

- `/repo-snapshot` — summarizes the current repo: branch, status, recent
  commits.
- `repository-context` — ask a natural-language question about the
  codebase (e.g. "where is `calculate_discount` defined?", "what
  references `OrderValidator`?") and Kiro matches it to this skill.
  Answers include file:line evidence, the indexed commit, whether the
  working tree is dirty/stale, and whether each result is
  `confidence=confirmed` (a verified definition) or `confidence=inferred`
  (a text match) — see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
  for what those mean. Works with no setup; install
  [Universal Ctags](https://ctags.io) for more `confirmed` results (see
  [docs/SETUP.md](docs/SETUP.md)). The same skill also answers a narrow
  cross-repository question — "what consumes this API?", "does repo B
  still call this function from repo A?" — for one named symbol across two
  given repositories, with source evidence from both sides, reported as
  `unknown` rather than invented when it isn't actually there.

Both skills are read-only. **Unverified:** whether Kiro invokes a skill
purely from conversational phrasing (vs. a typed `/command`) hasn't been
confirmed against the real IDE from this repo's own dev environment — see
`docs/SETUP.md`'s Verify section.

You shouldn't need to discover `repository-context` yourself the first
time: a steering file (`toolkit/steering/repository-context-awareness.md`)
tells every agent to notice, once per repository per session, when a repo
has never been indexed, and index it itself right then with a one-line
heads-up — rather than waiting to be asked a question that needs it.

## Layout

- `toolkit/` — the global, installable content (skills, steering, reserved
  agents). See [toolkit/README.md](toolkit/README.md).
- `agentic-eng` — the CLI: install/update/version/rollback/uninstall.
- `install.sh` — day-zero bootstrap wrapper (`agentic-eng` can't be on PATH
  before it's ever been run once); just calls `agentic-eng install`.
- `scripts/smoke-test.sh` — repeatable, automated, fully-offline verification.
- `scripts/repo-context-smoke-test.sh` — same, for the `repository-context`
  skill's `repo-context.sh`.
- `docs/` — setup, troubleshooting, and the PBIs this toolkit was built from.

## Why

Kiro's documented global discovery paths (`~/.kiro/skills/`,
`~/.kiro/steering/`) make a shared toolkit possible without any Kiro-side
install feature beyond "files in the right place." This repo is that place,
versioned and installed with one idempotent command.
