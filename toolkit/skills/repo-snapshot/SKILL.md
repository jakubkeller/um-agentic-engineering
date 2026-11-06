---
name: repo-snapshot
description: Use when starting work in an unfamiliar repository, or re-orienting after time away, to get a quick orientation on current state. Triggers on requests like "what's going on in this repo", "orient me", "give me a snapshot", or when the agent needs branch/status context before making changes.
metadata:
  author: um-agentic-engineering
  version: 1.0.0
---

# Repo Snapshot

Give the engineer a concise orientation to the current repository's state. This
skill is intentionally generic: it must work in any git repository, not just
this toolkit's own repo.

## Steps

1. Confirm the current directory is inside a git repository (`git rev-parse
   --is-inside-work-tree`). If it is not, say so and stop — do not guess.
2. Gather, without modifying anything:
   - Current branch and tracking status (`git status --short --branch`).
   - Uncommitted changes, staged and unstaged (`git status --short`).
   - The last 5 commits (`git log -5 --oneline`).
   - Whether a `README.md`, `CLAUDE.md`, `AGENTS.md`, or `docs/` directory
     exists at the repo root, since these usually hold onboarding context.
3. Summarize in under 10 lines:
   - Repo name (directory name) and current branch.
   - Clean vs. dirty working tree, and a one-line description of what's
     uncommitted if anything.
   - The most recent commit subject and how old it is.
   - Which onboarding docs exist, if any, and suggest opening them next.
4. Do not run any command that changes repository state (no commits, no
   checkouts, no stashing). This skill is read-only.

## Notes

- This skill is installed globally (`~/.kiro/skills/repo-snapshot/`) by the
  `um-agentic-engineering` toolkit installer and is available in every
  workspace without being committed to that workspace's own repository. See
  the toolkit's `docs/SETUP.md` for installation details.
- If the repository is large, prefer the targeted commands above over broad
  exploration — this skill is meant to be fast.
