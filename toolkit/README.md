# Toolkit content

Everything under this directory (`toolkit/`) is **global toolkit content**:
it gets copied by `../install.sh` into the engineer's home directory
(`~/.kiro/`), where Kiro discovers it from any workspace. Nothing in here is
specific to this repository.

Everything *outside* `toolkit/` in this repo (`docs/`, `scripts/`, this
repo's own README, etc.) is **repository-owned project context** — material
about developing and maintaining the toolkit itself. It is never installed
onto a workstation.

## Categories

- **`skills/`** — one directory per skill, each containing a `SKILL.md`
  (Kiro's required format: YAML frontmatter with `name` + `description`,
  then markdown instructions). Installed to `~/.kiro/skills/<name>/`.
  Contains the sample skill for this PBI: `repo-snapshot`.
- **`steering/`** — shared instruction files (Kiro "steering" docs) that
  should apply across every repository an engineer works in. Installed to
  `~/.kiro/steering/`. Currently empty (reserved) — no cross-repo steering
  content has been identified as broadly applicable yet.
- **`agents/`** — reserved for shared custom agent definitions. Kiro's
  global discovery mechanism for custom agents has not been verified (unlike
  skills and steering, which Kiro's docs explicitly document as reading from
  `~/.kiro/skills/` and `~/.kiro/steering/`), so `install.sh` does not install
  anything from this directory yet. Do not add content here until that
  mechanism is confirmed — see `docs/TROUBLESHOOTING.md`.

## Naming convention

Pick skill and steering file names that are unlikely to collide with an
engineer's own personal skills (which live in the same global directories).
Prefixing with context (e.g. `repo-snapshot` rather than `snapshot`) is
encouraged but not enforced by tooling.
