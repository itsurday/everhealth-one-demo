# Change Management Standard

How changes reach the shared Salesforce org. Applies to admins, developers and anyone using AI tools. Portfolio version of the standard; the process is the same one Gearset wraps (compare → validate → deploy → roll back), run here with `sf` CLI + GitHub Actions (ADR-007).

## 1. Environments
| Environment | What it's for | Who changes it |
|---|---|---|
| Scratch org (per feature) | Build and unit-test a change | The developer |
| CI scratch org (per PR, 1 day) | Validate deploy + all local tests | GitHub Actions only |
| Demo / "production" org | Users | Deploys from `main` only; **no direct edits** |
| Second org (promotion target) | Promotion and rollback drills | Deploys from tags |

Source of truth is `main`. Anything changed by hand in an org is drift: catch it with `sf project retrieve preview --target-org <org>` and either commit it through a PR or revert it.

## 2. Every change goes through a PR
1. Branch from `main` (`feat/…`, `fix/…`).
2. Run `/impact <Object.Field>` for every field you change; paste the result into the PR's **Impact** section.
3. Run `/metadata-review` and fix Blockers.
4. Open a PR using the template. **Required sections:** Summary, Release notes, Impact, Testing, **Rollback**.
5. CI must pass:
   - rollback-note check: a missing or placeholder `## Rollback` fails the PR
   - script self-tests and the living-docs check (`gen_docs.py --check`)
   - Code Analyzer, severity 1–2 fails
   - validate deploy with `RunLocalTests` in a fresh scratch org
6. One reviewer approves. Permission, sharing and destructive changes need the Architect.

## 3. What a good rollback note says
Concrete steps someone else can follow at 2 a.m.:
- Code/config: "Revert merge `<sha>` and redeploy `main`", or "redeploy tag `vX.Y`".
- Automation: "Deactivate flow `EH_…`" (fastest; no deploy).
- Integration: "Set `Integration_Config__mdt.Zuora_Billing.Is_Active__c` = false".
- Data: "Restore `backup/<file>.csv` by upsert on `<External Id>`".
- Destructive: what must be recreated before data can be restored.

"N/A", "TBD" and empty sections are rejected by CI.

## 4. Release
- Batch merged PRs into a release; tag `vYYYY.MM.DD`.
- `/release-notes <prev-tag>..<new-tag>` drafts notes + combined rollback; a human edits and posts them.
- Deploy the tag to the target org; smoke-test the demo script; record post-deploy steps (e.g. Quote Template, CMDT values, scheduled jobs).
- Scheduled Apex: `Deployment.settings` allows deploys while `EH Billing Auto-Retry` jobs are scheduled. Re-run `BillingRetryScheduler.scheduleEvery15Minutes()` after a fresh org build (the setup script does it).

## 5. Data changes
Bulk changes follow [runbooks/deploy-rollback-and-bulk-data.md](runbooks/deploy-rollback-and-bulk-data.md): back up → dry run → upsert on external IDs → verify → roll back from backup.

## 6. Living documentation
`docs/generated/*` is regenerated from metadata (`python scripts/gen_docs.py`) and CI fails if it's stale. So the field inventory (with sensitivity labels), flow catalog, report index and mapping matrix always match what's deployed.

## 7. AI-assisted changes
AI (Claude Code) may draft code, metadata, docs and release notes. It may not deploy, merge, change access or touch production data unless a human asks in that session (`CLAUDE.md`). AI output gets the same PR, review and CI as human work. Log notable AI tasks in `docs/AI_LOG.md`.
