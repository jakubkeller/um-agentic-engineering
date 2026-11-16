---
inclusion: always
---

# Cross-Repository Dependency Awareness

The `repository-context` skill can confirm, with real evidence, that a
specific function/symbol defined in one repository is actually used by
another (`relate`), and can list every such confirmed relationship a given
repository is already known to be part of (`relations-for`). See that
skill's own `SKILL.md`. This note is about one thing only: an engineer
should never have to think to ask whether a cross-repo dependency exists.
State it outright, unprompted, the same way `repository-context-awareness.md`
already surfaces an un-indexed repo without being asked.

**Every time** (not once per session: this check is specific to what's
about to change, not a one-time workstation fact) you are about to modify,
remove, or rename the **definition** of an existing function, method,
endpoint handler, or other named symbol in a repository, not when writing
brand-new code that never existed before:

1. Resolve the repo root: `git rev-parse --show-toplevel`. If this fails,
   say nothing and skip the rest of this.
2. Run (read-only, never rebuilds anything, never reaches a network):
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh relations-for "<repo-root>" "<symbol-being-changed>"
   ```
   If this fails outright (script missing), say nothing and skip the rest
   of this.
3. For each line starting `REL role=provider ... status=supported`, a
   different repository was previously confirmed to depend on this exact
   symbol. State that to the engineer outright, as a fact, before
   proceeding with the change: never phrase it as a question, never wait
   to be asked, and never block the edit on it. For example: "Heads up:
   `<counterpart_repo>` depends on `<symbol>`. You'll need to update it
   too." If `own_state=stale` or `counterpart_state=stale` on that line,
   also say that the relationship was last confirmed against an older
   commit on one side and may need rechecking (re-run `relate` for current
   evidence), rather than presenting it as still certainly true.
4. Lines with `status=unknown`, or no output at all (`rel:count=0`), mean
   there is no *confirmed* relationship on record for this symbol. Say
   nothing. Inventing a dependency that was never actually confirmed is
   explicitly against `repository-context`'s own rules, and silence here
   is the correct, expected outcome, not a gap to apologize for.
5. This only resurfaces a relationship that a prior `relate` call already
   confirmed for this exact symbol and repo pair. It is not automatic
   discovery of unknown dependencies across the organization, not a full
   downstream-impact analysis, and not a graph crawl. If no one has ever
   run `relate` for this symbol before, there is nothing to surface yet,
   and that's expected, not a defect.

This never modifies anything inside any repository. `relations-for` only
ever reads from its own cache directory under
`~/.kiro/.um-agentic-engineering/repo-relations/`.
