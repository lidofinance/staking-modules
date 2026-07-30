---
name: gh-update-pr-description
description: Update the current-branch GitHub PR title, description, and labels with gh CLI using this repository's PR template. Use when asked to inspect template/labels and apply concise PR metadata updates.
---

# GitHub PR Description Updater

## Overview

Use this workflow to update current-branch PR metadata with `gh`. Start from the repository PR template, keep the description short and precise, and verify final PR title/body/labels after editing.

## 1) Resolve PR And Auth

- Run `gh auth status`; if unauthenticated, ask user to run `gh auth login`.
- Run `gh pr view --json number,url,title,headRefName,baseRefName,body,labels` to resolve the PR tied to the checked-out branch.
- If the branch has no PR, stop and tell the user.

## 2) Inspect Template And Labels

- Read `.github/PULL_REQUEST_TEMPLATE.md`.
- List repository labels with `gh label list --limit 200 --json name --jq '.[].name'`.
- Compare current PR labels from `gh pr view` against label names from `gh label list`.

## 3) Draft Title And PR Body

- Update title only if needed to better match scope and outcome. Keep the original title if looks manually written.
- Start PR body from template exactly.
- Replace `` `TBD` `` in `## Description` with a short, precise bullet list:
  - Keep it to 2-5 bullets.
  - Keep one sentence per bullet.
  - Avoid long paragraphs and filler.
- Keep checklist booleans coherent:
  - Do not check both mutually exclusive sub-options.
  - Keep unknown items unchecked instead of guessing.
  - Mark "Appropriate PR labels applied" checked only after labels are actually set.
- If tests/docs intent is unclear, ask the user before setting those checklist items.

## 4) Apply Changes With gh

- Write final body to a temp file.
- Title if needed: `gh pr edit <number> --title "<new-title>"`.
- Body: `gh pr edit <number> --body-file <file>`.
- Add labels: `gh pr edit <number> --add-label "label-a,label-b"`.
- Remove labels: `gh pr edit <number> --remove-label "label-x,label-y"`.

## 5) Verify And Report

- Verify final PR metadata: `gh pr view <number> --json url,title,body,labels`.
- Report PR URL, PR number, final title, final labels, and checklist state.
- If blocked, report exact failing command and error text.
