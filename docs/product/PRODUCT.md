# Dit Giff — product

Product decisions in brief. Not the reasoning archive.

## What it is

A native macOS app that turns the diff between a branch and its base into a review
you can defend. You pick the branch and base branch; the app builds the diff
locally and can use AI to explain a hunk on demand, flag what looks incidental or
out of scope, and surface the decisions a reviewer would ask "why?" about.

One line: the local MR preview that should exist and does not.

## Why it exists

An earlier product (Mellon) asked the user to leave where they already work. It did
not stick — not even for the author, who was the target user.

The rule that came out of that: do not build anything that requires changing where
the user works. Build a layer around the current flow that adds value without asking
for migration. References: Maestri (canvas over agent terminals) and Wispr Flow
(dictation). Minimal surface, no migration, attached to something high frequency.

## The problem

With agents, implementation got cheap: a one-week feature can land in a few hours.
What remains is review — reading what the agent wrote so you can open the MR with
confidence. In one real case: 95% done in two hours, four days to open the MR,
blocked by the fear that a reviewer would ask "why that decision?" and there would
be no good answer.

Review value is human and cannot be outsourced to another agent. You need to
understand what you ship, and reading the agent's code is how you learn. So the
product does not review for you. It helps you read and understand faster, and
leaves you ready to defend each decision.

## Value pillars

1. **Better review UI than GitLab**, with or without AI. Organizes the change,
   collapses noise, makes macro navigation painless.
2. **AI that works from the diff**, without requiring anything beyond it. Explains
   a hunk on demand, flags incidental / out-of-scope / accidental edits, and raises
   the decisions a reviewer would question.
3. **Optional reference.** A spec, ticket, or one-line intent — when provided —
   sharpens answers. Never required.

## Connection principles (zero friction)

- **Local.** Reads git on the machine. The pain lives in the diff, and the diff
  lives in git, not on the website. GitLab and GitHub are free because the source
  is git.
- **Uses credentials the machine already has** (SSH keys, git config). No repo
  setup.
- **Read-only.** AI does not write code. No write permission on the repo.
- **Bring your own AI.** Uses the subscription the user already has, calling Claude
  Code headless. No new API key to manage.

## Decided

- **Stack:** Swift / native macOS. Personal product, usable from day one, deliberate
  craft and learning choice.
- **Read-only and BYO-AI via Claude Code headless.** Proved by spike.
- **Scope in one sentence.** One job: turn branch-against-base into a defensible
  review. "Open any repo, browse any code" is out of scope.
- **Context for AI:** neither pasted diff alone nor the whole project. The agent
  gets read-only git scoped to `diff`, `show`, `log`, `status`, `merge-base`,
  `ls-files` — nothing else — and fetches what it needs. Large diffs do not fit
  reliably in a prompt budget; pasting the patch breaks on the MRs that matter
  most.

## Still open

- How findings are presented: as clues, never verdicts, to keep the human in the
  loop and preserve learning.
- Where the one-line intent comes from: typed by the user, or inferred from branch
  name / commits / MR title.

## Anti-goals

- Not a workspace, file tree browser, or place something has to live.
- AI does not write code or open the MR for you.
- Nothing that requires spec-first workflow to be useful.
