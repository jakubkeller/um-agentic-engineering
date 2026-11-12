---
inclusion: always
---

# Repository Context Awareness

This workstation has the `repository-context` skill installed
(`~/.kiro/skills/repository-context/repo-context.sh`) — source-grounded
symbol/reference lookup with file:line evidence. See that skill's own
`SKILL.md` for how to use it when actually asked a symbol/reference
question. This note is only about one thing: noticing, once, when a
repository has never been indexed at all.

**Once per session** (not per repository — this is a workstation-level
fact, not a per-repo one), the first time any of this applies:

0. Run (no repo needed):
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh indexer-check
   ```
   If this fails outright (script missing), say nothing and skip the rest
   of this entirely. If it reports `ctx:indexer_available=no`, remember
   that for the rest of this session and surface it the first time you're
   about to mention `repository-context` to the user at all (step 3 below,
   or an actual lookup), by including the line it printed under
   `ctx:fix=...` verbatim. Say it once, ever, this session — not once per
   repository.

The **first** time you're about to work in a git repository this session
(not on every message, and not more than once per repository per
session):

1. Resolve the repo root: `git rev-parse --show-toplevel`. If this fails,
   you're not in a git repository — say nothing and skip the rest of this.
2. Run (read-only, never rebuilds anything on its own):
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh status "<repo-root>"
   ```
   If this fails outright (script missing — an older or partial toolkit
   install), say nothing and skip the rest of this.
3. If the output contains `ctx:cache_state=MISSING`, this repository has
   never been indexed. Prime it yourself, right then, without asking
   first:
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh rebuild "<repo-root>"
   ```
   This is bounded (capped by file count and a timeout) and safe to run
   unconditionally — worst case it reports `ctx:index_state=fallback` with
   a reason, which is a normal, expected outcome here, not an error.
   Briefly tell the user what you did in one line (e.g. "indexed this repo
   for the first time so file/symbol questions get file:line evidence" —
   or, if it fell back because no indexer is installed, fold step 0's
   install line into this same message instead of raising it separately),
   then continue with whatever was actually asked. Don't block your
   answer on this, don't ask a follow-up question about it, and don't
   mention it again this session.
4. Any other `ctx:cache_state` (`FRESH`, `STALE_REVISION`, `CORRUPT`,
   `NO_COMMITS`) — say nothing beyond step 0's one-time indexer note.
   Those states are already handled by the `repository-context` skill
   itself whenever it's actually asked a question; they don't need a
   proactive nudge, only "never indexed at all" and "no indexer available
   at all" do.

This never modifies anything inside the repository being worked in — the
rebuild only ever writes to its own cache directory under
`~/.kiro/.um-agentic-engineering/repo-context/`.
