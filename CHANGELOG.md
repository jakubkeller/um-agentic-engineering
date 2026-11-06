# Changelog

## 1.0.0

Initial release.

- Established the repo layout: `toolkit/` (global, installable content —
  `skills/`, `steering/`, `agents/`) separated from repo-owned project
  context (`docs/`, `scripts/`).
- `install.sh`: idempotent installer copying `toolkit/skills/` and
  `toolkit/steering/` into Kiro's documented global discovery paths
  (`~/.kiro/skills/`, `~/.kiro/steering/`). Tracks what it installs in a
  manifest so re-installs, updates, and uninstalls never touch files it
  didn't create, and failures leave no partial/misleading install behind.
- Sample skill: `repo-snapshot`, a read-only repo-orientation skill that
  demonstrates the toolkit working identically across unrelated repos.
- `scripts/smoke-test.sh`: automated, repeatable checks for fresh install,
  idempotent re-install, unrelated-file preservation, uninstall, and
  failure-path behavior — run against throwaway temp homes, never the real
  `~/.kiro`.
- `docs/SETUP.md` and `docs/TROUBLESHOOTING.md`.
