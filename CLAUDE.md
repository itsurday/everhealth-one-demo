# CLAUDE.md — EverHealth One

Instructions for Claude Code in this repo. Humans: this is also the short version of our conventions.

## What this is
Portfolio Salesforce project: Quote-to-Cash & RevOps control plane. **Zuora, HubSpot, ChurnZero and the other GTM tools are simulated** (in-org stub, documented mappings). Synthetic data only. Specs: `docs/PRD.md`, `docs/STA.md`, `docs/DATA_MODEL.md`.

## Guardrails (non-negotiable)
- **AI drafts, humans decide.** Never deploy to an org, merge, push, change permissions, or edit data without the human asking in this session.
- **No secrets** in source, logs, CMDT or docs. Credentials live only in Named/External Credentials. Never print auth URLs or tokens.
- **No PHI, no payment data.** Don't add fields for patient data, card/bank details, tokens or invoice amounts.
- **Label simulations.** Anything standing in for Zuora/HubSpot/ChurnZero says "(simulated)".
- **One owner per automated process** (table in `docs/STA.md` §4). Don't add a Flow and Apex on the same object/event without updating that table.
- **Every PR has a `## Rollback` section** (CI blocks it otherwise).

## Conventions
- Prefix: `EH_` for flows, permission sets, approval processes, duplicate rules, reports/dashboards.
- Apex layers: Trigger (no logic) → `*TriggerHandler` → `*Service` → `*Selector` (all SOQL). `*Queueable`, `*Resource` (REST), `*_Test` + `TestDataFactory`.
- Sharing: `with sharing` by default; `inherited sharing` for selectors; `without sharing` only with a comment saying why. Integration code uses explicit `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE`.
- No SOQL/DML in loops. No hard-coded Ids/URLs. Config in Custom Metadata (`Integration_Config__mdt`, `Q2C_Setting__mdt`, `Field_Mapping__mdt`).
- New custom fields: `description`, `securityClassification` (and `complianceGroup` when relevant).
- Tests: positive, negative, bulk (≥120), permission (`System.runAs`). Org-wide coverage ≥ 85%. Never branch on `Test.isRunningTest()`.

## Commands
| Command | Use it for |
|---|---|
| `/impact <Object.Field>` | Before changing a field: every Flow, VR, layout, report, mapping and Apex that uses it |
| `/release-notes [from..to]` | Draft release notes + rollback notes from the git diff |
| `/metadata-review` | Review changed metadata against the rules above before opening a PR |

## Everyday scripts
```bash
scripts/setup-org.sh [alias]            # scratch org -> deploy -> access -> auto-retry -> demo data
scripts/load-demo-data.sh [alias]       # idempotent demo data (CSV upserts + seed)
python scripts/gen_docs.py              # regenerate docs/generated/* (CI checks they're current)
python scripts/impact.py Account.Lifecycle_Stage__c
sf apex run test --test-level RunLocalTests --code-coverage --wait 20
sf code-analyzer run --workspace force-app --severity-threshold 2
```
Git Bash on Windows: prefix REST calls with `MSYS_NO_PATHCONV=1` so `/services/...` isn't rewritten to a Windows path.

## Logging AI work
After an AI-assisted task, add a row to `docs/AI_LOG.md`: what was asked, what the AI produced, what the human reviewed or changed, time saved (estimate, say so).
