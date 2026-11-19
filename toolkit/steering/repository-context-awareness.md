---
inclusion: always
---

# Repository Context Awareness

This workstation has the `repository-context` skill installed
(`~/.kiro/skills/repository-context/repo-context.sh`) — source-grounded
symbol/reference lookup with file:line evidence.

**Whenever a question needs a specific symbol, file, or code-path
location in the current repository** (e.g. "where is X defined", "what
calls Y", "what clients/classes/functions exist here", "is this file:line
still accurate"), or whether one repository actually depends on another
through a named contract (e.g. "what consumes this API", "does repo B
still call this function from repo A") — run the lookup yourself, right
then, as part of answering, regardless of how the question was phrased.
Plain conversational phrasing is enough; the user never has to type
`/repository-context` or know this skill exists:
```
bash ~/.kiro/skills/repository-context/repo-context.sh lookup "<symbol>" "<repo-root>"
bash ~/.kiro/skills/repository-context/repo-context.sh relate "<symbol>" "<provider_repo>" "<consumer_repo>"
```
Use the result's file:line evidence, `confidence` (`confirmed`/`inferred`),
and freshness flags in the answer, rather than grepping the repository
yourself and describing what you find from general reasoning. See that
skill's own `SKILL.md` for the exact output format and how to interpret
each field. This is not optional: a question that needs this kind of
grounded evidence should never be answered from an ungrounded guess when
this script can answer it directly.

Separately, this note is also about one thing: noticing, once, when a
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
5. Also in this same first-time-per-repository moment, check whether this
   repository already keeps itself current through routine Git activity:
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh hooks-status "<repo-root>"
   ```
   If this fails outright, say nothing and skip the rest of this step. If
   it reports `hooks:all_installed=no`, set it up yourself, right then,
   without asking first:
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh install-hooks "<repo-root>"
   ```
   This only ever installs a small, clearly marked, removable block into
   the repository's own `post-commit`/`post-merge`/`post-checkout` Git
   hooks (coexisting with any existing hook content, Husky included) that
   triggers a bounded, backgrounded cache refresh after routine commits,
   merges, and branch switches (never a watcher or daemon), and it never
   blocks or fails a Git operation. Fold this into the same one-line
   message as step 3 if both apply (e.g. "indexed this repo for the first
   time and set up automatic refresh after commits/merges/branch switches
   so it doesn't go stale"), or mention it on its own, once, if step 3
   didn't apply. Don't mention it again this session for this repository.
6. Also in this same first-time-per-repository moment, check whether this
   repository already publishes a context baseline after merges:
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh ci-setup-status "<repo-root>"
   ```
   This checks `azure-pipelines.yml` at the repo root by default (Azure
   DevOps's own default path). If this fails outright, say nothing and
   skip the rest of this step. If it reports `ci:publish_configured=no`,
   this is different from steps 3 and 5: don't run anything yet.
   `ci-setup` edits (or creates) a tracked, reviewed file and needs
   information nobody but the engineer has: which Azure Artifacts feed to
   publish to, and, if this repo's actual pipeline lives somewhere other
   than `azure-pipelines.yml` at the root, where that real file is. So
   ask once, in the same one-line message as the rest of this step if any
   applied this round: "this repo isn't publishing a repository-context
   baseline after merges yet, want me to wire that up? I'll need the
   Azure Artifacts feed to publish to (e.g. `YourProject/YourFeed`), and
   let me know if your pipeline file isn't `azure-pipelines.yml` at the
   repo root." If they say yes and give a feed, run:
   ```
   bash ~/.kiro/skills/repository-context/repo-context.sh ci-setup "<repo-root>" --feed "<feed>"
   ```
   adding `--pipeline-file "<path>"` if they named a different one, then
   tell them what changed, the pipeline file (created vs. updated) and
   the vendored `.ci/repository-context/repo-context.sh` ci-setup copies
   alongside it, so they can review and commit both themselves, same as
   any other code change. If they
   decline, or don't answer, drop it, don't ask again this session. If
   `ci-setup` reports `ci:status=created` for a repo that may be brand
   new, also pass along its warning that someone still has to connect
   that file as a Pipeline inside Azure DevOps itself, once, this toolkit
   can't do that part.

This never modifies anything inside the repository's tracked content on
its own: the rebuild only ever writes to its own cache directory under
`~/.kiro/.um-agentic-engineering/repo-context/`, and `install-hooks` only
ever touches the repository's own local, untracked Git hooks. `ci-setup`
(step 6) is the one exception, and it only ever runs after the engineer
explicitly says yes.
