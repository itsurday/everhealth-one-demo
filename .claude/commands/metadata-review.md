---
description: Review changed Salesforce metadata against the CLAUDE.md rules before opening a PR
argument-hint: [base ref]  (default: origin/main)
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(python scripts/gen_docs.py --check), Bash(python scripts/impact.py:*), Read, Grep, Glob
---

Base: `$ARGUMENTS` (default `origin/main`).

Review only the files changed vs the base (`git diff --name-only <base>...HEAD` plus uncommitted changes) under `force-app/`, `scripts/` and `docs/`. Check each rule in `CLAUDE.md`:

| Check | How |
|---|---|
| New fields have `description` + `securityClassification` | read the `.field-meta.xml` |
| No PHI / payment-data fields | field names, labels, descriptions |
| Simulated systems labeled | descriptions/labels mentioning Zuora, HubSpot, ChurnZero |
| One owner per automated process | new flows/triggers vs `docs/STA.md` §4 |
| Apex: sharing declared, `without sharing` justified, no SOQL/DML in loops, no hard-coded Ids/URLs | read the classes |
| Tests added for new logic (positive, negative, bulk, permission) | `*_Test` classes |
| Access changes are intentional | permission sets/profiles diff |
| Living docs current | `python scripts/gen_docs.py --check` |
| Field changes reviewed for impact | `python scripts/impact.py` for each changed field |

Output a findings table: **Severity** (Blocker / Should fix / Nit), **File:line**, **Finding**, **Suggested fix**. End with a one-line verdict. Do not modify files; a human applies the fixes.
