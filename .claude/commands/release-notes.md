---
description: Draft release notes and rollback notes from the git diff between two refs
argument-hint: [from..to]  (default: last tag..HEAD, or origin/main..HEAD if there are no tags)
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git describe:*), Bash(git tag:*), Bash(python scripts/impact.py:*), Read
---

Range: `$ARGUMENTS`

1. Resolve the range. If empty, use `$(git describe --tags --abbrev=0)..HEAD`; if there are no tags, `origin/main..HEAD`.
2. Collect `git log --oneline <range>` and `git diff --stat <range> -- force-app docs scripts`.
3. Group changed metadata by type: objects/fields, validation rules, flows, approval processes, Apex, permission sets/profiles, layouts, reports/dashboards, CMDT, settings. Flag **destructive** changes (deleted files) and **access** changes (permission sets, profiles, sharing) explicitly.
4. For each changed custom field, run `python scripts/impact.py <Object.Field>` and list the external mappings it touches.
5. Output Markdown with these sections:
   - `## Release notes`: 3–8 plain-language bullets for admins and users.
   - `## Changed components`: the grouped table.
   - `## Impact`: access changes, destructive changes, external systems.
   - `## Post-deploy steps`: manual steps (e.g. Quote Template, scheduled jobs, CMDT values).
   - `## Rollback`: concrete steps per change type (revert + redeploy tag, deactivate flow, restore data from backup CSV, re-schedule jobs).
6. This is a draft for a human to review. Don't create tags, commits or files.
