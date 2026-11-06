# Changelog

Nothing in this repo has been tagged/released yet — there is no approved
`vX.Y.Z` release, so there's no version number to attach to any of this
until a maintainer cuts the first one. Everything below is accumulated,
unreleased work (PBI 297784 + PBI 297785).

## Unreleased

- Established the repo layout: `toolkit/` (global, installable content —
  `skills/`, `steering/`, `agents/`) separated from repo-owned project
  context (`docs/`, `scripts/`).
- Sample skill: `repo-snapshot`, a read-only repo-orientation skill that
  demonstrates the toolkit working identically across unrelated repos.
- `agentic-eng`: the CLI — `install`, `update`, `version`, `rollback`,
  `uninstall`. `install.sh` is a thin day-zero bootstrap wrapper
  (`agentic-eng` can't be on PATH before it's ever been run once) that just
  calls `agentic-eng install`.
- Releases are resolved from git tags (`vX.Y.Z`, highest wins via git's own
  version-aware sort) via a persistent, tool-managed local clone at
  `~/.kiro/.um-agentic-engineering/source/` — never an arbitrary branch/HEAD,
  and never by checking out/mutating the engineer's own working clone.
  **Known gap:** no tags exist yet; `install`/`update` correctly fail until a
  maintainer publishes the first one.
- New release content is staged and validated (its `VERSION` matches the
  tag, every skill's frontmatter matches its folder, has a description,
  steering frontmatter is well-formed) before activation; a failing release
  is rejected and the previously-installed release is left untouched.
  Activation itself builds each artifact at a temp path and renames it into
  place.
- A bounded local cache (`~/.kiro/.um-agentic-engineering/releases/`, exactly
  `current` + `previous` via atomically-swapped symlinks) makes `rollback`
  work with zero network access, with an integrity check before restoring.
- `agentic-eng install`/`update` self-copy to
  `~/.kiro/.um-agentic-engineering/bin/` and print a one-time PATH
  instruction, so later commands work from anywhere without needing the
  original clone to still exist.
- A generated (not shipped) steering file,
  `~/.kiro/steering/um-agentic-engineering-status.md`, records the installed
  version in every agent's context; removed on uninstall.
- `scripts/smoke-test.sh`: fully offline, using disposable local git
  fixtures (never the real GitHub remote) to exercise install, idempotent
  re-install, unrelated-file preservation, update, a rejected/broken update,
  rollback (including offline), version reporting (including
  simulated-offline), uninstall, the `install.sh` bootstrap path, and a
  clean failure when the release source is unreachable.
- `docs/SETUP.md` and `docs/TROUBLESHOOTING.md`.
