# Toolkit content

Everything under this directory (`toolkit/`) is **global toolkit content**:
it gets resolved from the latest approved release tag and copied by
`../agentic-eng` (bootstrapped via `../install.sh` on first run) into the
engineer's home directory (`~/.kiro/`), where Kiro discovers it from any
workspace. Nothing in here is specific to this repository.

Everything *outside* `toolkit/` in this repo (`docs/`, `scripts/`, this
repo's own README, etc.) is **repository-owned project context** — material
about developing and maintaining the toolkit itself. It is never installed
onto a workstation.

## Categories

- **`skills/`** — one directory per skill, each containing a `SKILL.md`
  (Kiro's required format: YAML frontmatter with `name` + `description`,
  then markdown instructions). Installed to `~/.kiro/skills/<name>/`.
  Contains the sample skill for this PBI, `repo-snapshot`, and
  `repository-context` (source-grounded symbol/reference lookup, including
  across two different repositories via `relate`/`relate-status`: a
  provider/consumer dependency check for one named symbol, not
  organization-wide discovery). `relations-for` then lists every such
  confirmed relationship a given repository is already part of, which is
  what lets an agent notice a known dependency on its own instead of
  needing to be asked. A
  skill's folder may also hold a companion deterministic script alongside
  its `SKILL.md` (see `repository-context/repo-context.sh`) when its logic
  needs to be testable, not just prose a Kiro agent follows — `agentic-eng`
  copies and caches a skill's whole folder, so this needs no installer
  changes. Every skill here must also pass `agentic-eng`'s pre-activation
  validation (frontmatter `name:` matches the folder, non-empty
  `description:`) or a release shipping it will be rejected, not silently
  installed.
- **`steering/`** — shared instruction files (Kiro "steering" docs) that
  should apply across every repository an engineer works in. Installed to
  `~/.kiro/steering/`. Contains `repository-context-awareness.md`
  (`inclusion: always`), which tells every agent to check, once per
  repository per session, whether that repository has ever been indexed by
  `repository-context` and, if not, index it itself right then rather
  than waiting to be asked; it also checks once per session (workstation
  level, not per-repo) whether Universal Ctags is installed at all and, if
  not, states the exact install command up front rather than only
  reporting that results are degraded. Also contains
  `cross-repo-dependency-awareness.md` (`inclusion: always`), which tells
  every agent to check, every time it's about to change an existing
  symbol's definition, whether another repository was already confirmed
  (via `relate`) to depend on it, and mention that unprompted rather than
  leaving the engineer to think to ask. (Separately, `agentic-eng` itself
  *generates* `~/.kiro/steering/um-agentic-engineering-status.md` at
  install/update/rollback time to record the installed version in every
  agent's context: that file isn't shipped from here, it's synthesized.)
- **`agents/`** — reserved for shared custom agent definitions. Kiro's
  global discovery mechanism for custom agents has not been verified (unlike
  skills and steering, which Kiro's docs explicitly document as reading from
  `~/.kiro/skills/` and `~/.kiro/steering/`), so `agentic-eng` does not
  install anything from this directory yet. Do not add content here until
  that mechanism is confirmed — see `docs/TROUBLESHOOTING.md`.

## Naming convention

Pick skill and steering file names that are unlikely to collide with an
engineer's own personal skills (which live in the same global directories).
Prefixing with context (e.g. `repo-snapshot` rather than `snapshot`) is
encouraged but not enforced by tooling.
