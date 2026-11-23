# EverHealth One: Quote-to-Cash & RevOps Control Plane (Salesforce)

A portfolio Salesforce build: Zuora-shaped quoting, an async billing sync that survives failures and duplicates, operator tooling to troubleshoot it, GTM sync rules, data-quality controls, a GitHub + `sf` release process that requires rollback notes, living documentation generated from metadata, and AI-assisted development with guardrails.

> **Fictional and simulated.** Not an EverCommerce product; built without access to any EverCommerce system. **Zuora (CPQ X + Billing), HubSpot, ChurnZero, Gong, Outreach, ZoomInfo and Chili Piper are simulated:** no vendor packages. Synthetic data only: no PHI, no payment data.

## Reviewing in 5 minutes
1. **Watch** the [1:50 demo video](#demo-video) and skim the [screenshots](#screenshots).
2. **Read the design:** [architecture and ADRs](docs/STA.md) and [JD traceability](docs/PRD.md#2-jd-traceability).
3. **Read the code:** [BillingSyncService.cls](force-app/main/default/classes/BillingSyncService.cls) (async, idempotent sync with bounded retry) and [BillingEventsResource.cls](force-app/main/default/classes/BillingEventsResource.cls) (REST intake with dedupe and stale-event handling), with their `*_Test.cls` files.
4. **Check the governance:** [CI workflow](.github/workflows/ci.yml), [rollback-note check](scripts/check-rollback-note.sh), [change management](docs/CHANGE_MANAGEMENT.md), [AI log](docs/AI_LOG.md).

## What it shows
| Area | In this repo |
|---|---|
| Quote-to-cash | Zuora-shaped catalog on Product2, quote types New/Amend/Renew, discount approval, renewal Opportunities generated before term end, Amend / Renew action that pre-fills current charges (co-termed amendments) |
| Billing sync + troubleshooting | Async, idempotent sync to a stub billing adapter; Apex REST billing-event intake; **failure switch** in Custom Metadata; categorized Integration Log; bounded auto-retry; operator-only Retry Sync; **daily reconciliation** that flags silent drift vs billing |
| Configuration | Record types, layouts, validation rules, formula + roll-up fields, record-triggered / scheduled / screen flows, approval process |
| Release management | SFDX + GitHub; CI validates deploy, runs tests and Code Analyzer; **PRs without a Rollback section fail**; change-management standard |
| GTM stack | `Field_Mapping__mdt` + sync-rules matrix (direction, winning system, conflict rule, lifecycle mapping) |
| Data quality | Data Loader–format CSVs upserted on external IDs, duplicate rules, completeness score, Data Quality dashboard, bulk-op runbook |
| Living docs | Field inventory **with sensitivity labels**, flow catalog, report index, mapping matrix, all generated; CI fails if stale |
| AI-assisted dev | `CLAUDE.md` guardrails, `/impact`, `/release-notes`, `/metadata-review`, [AI log](docs/AI_LOG.md) |

Full JD traceability: [docs/PRD.md §2](docs/PRD.md#2-jd-traceability).

## Demo video
https://github.com/user-attachments/assets/ee866894-87a4-4950-841e-be9d920c431b

Full-quality file: [video/brag.mp4](video/brag.mp4) (download).

A 1:50 walkthrough of quote-to-cash, amend and renew, billing-sync recovery, data quality and release governance. Each scene names the job-description line it covers. The presenter is AI-generated and the voice is synthetic (Kokoro). The screens are real captures of the scratch org with synthetic data, and Zuora, HubSpot and ChurnZero are simulated. Built with [brag](https://github.com/latent-spaces/brag) and Hyperframes. Music: Sascha Ende, ende.app (CC BY 4.0).

## Screenshots
Synthetic data in a scratch org; Zuora is simulated.

| | |
|---|---|
| ![Q2C Sync Health dashboard](docs/screenshots/01-q2c-sync-health.jpg) **Q2C Sync Health**: every transaction by status; open failures by category | ![Retry Sync](docs/screenshots/02-retry-sync-operator.jpg) **Operator retry** of an exhausted, rate-limited sync (same idempotency key) |
| ![Amend / Renew](docs/screenshots/03-amend-renew.jpg) **Amend / Renew** from a subscription, pre-filled with current charges | ![Reconciliation mismatch](docs/screenshots/04-reconciliation-mismatch.jpg) **Reconciliation** caught a price changed "directly in Zuora" |
| ![Data Quality dashboard](docs/screenshots/05-data-quality.jpg) **Data Quality**: completeness bands | ![Quote header logo](force-app/main/default/documents/EH_Branding/EverHealth_One_Logo.png) Fictional brand used on the quote PDF |

## Architecture
```mermaid
flowchart LR
  Q["Quote accepted"] --> T["QuoteTrigger"] --> S["BillingSyncService"] --> J["Queueable (chunks of 50)"]
  J --> A{"BillingAdapter"}
  A -- "Mode = Stub" --> Z["Zuora stub (simulated)<br/>Fail_Mode: None / Timeout / RateLimit / Validation"]
  A -- "Mode = NamedCredential" --> N["callout:Zuora_Billing"]
  J --> L["Integration_Log__c<br/>idempotency key, category, attempts"]
  J --> B["Billing_Subscription__c"] --> F["Flow: Account lifecycle"]
  E["POST /billing/events"] --> R["BillingEventsResource<br/>dedupe on event key"] --> B
  L -- "Retryable" --> RS["Auto-retry every 15 min"] --> J
  L -- "Exhausted / Permanent" --> OP["Retry Sync (operator only)"] --> J
  B --> RG["Scheduled flow: Renewal Opportunity"]
```
Details: [docs/STA.md](docs/STA.md) · data model: [docs/DATA_MODEL.md](docs/DATA_MODEL.md).

## Run it
Prereqs: Salesforce CLI, a Dev Hub, Git Bash (on Windows), Python 3.
```bash
scripts/setup-org.sh eh-demo     # scratch org (30 days) -> deploy -> access -> auto-retry jobs -> demo data
sf org open -o eh-demo           # App Launcher -> "EverHealth One"
```
### Quote template (one manual step)
Quote templates can't be deployed as metadata, so build it once per org (about 5 minutes). The logo and divider images *are* in source (`documents/EH_Branding`, public Documents) and the setup script prints their URLs for your org.
1. Setup → Quote Templates → **New**: name *EverHealth One Quote*, based on *Standard Template*.
2. Header: one-column section with a **Text/Image Field**: Insert Image → Web Address → the **logo** URL; then the line "Billing: Zuora (simulated)"; then Insert Image → the **divider** URL.
3. Line items table: add **Charge Type** and **Billing Period** columns.
4. **Save** → back on the list → **Activate**.

Demo users are created by the script: **Sam Sales** (sales user, can't see or retry integration logs) and **Morgan Manager** (discount approver). Open as either with `sf org open -o <username>`.

## Quality
- 60 Apex tests, 97% org-wide coverage (positive, negative, bulk, permission), measured in the scratch org with `sf apex run test --test-level RunLocalTests --code-coverage`.
- CI runs on every push and PR: Code Analyzer (fails on severity 1–2), script self-tests (rollback-note check: 8 cases; doc generator and `/impact`: 5 cases), and a check that generated docs are current.
- The CI job that validates the deploy and runs the Apex tests in a throwaway scratch org needs a `DEVHUB_SFDX_AUTH_URL` secret. This public copy has no Dev Hub connected, so that job is skipped here and shows a warning.

## Repo map
```text
force-app/main/default/   metadata: objects, classes, triggers, flows, approval, layouts, perm sets, reports, dashboards, CMDT
scripts/                  setup-org.sh, load-demo-data.sh, send-billing-event.sh, seed/*.apex, gen_docs.py, impact.py, check-rollback-note.sh (+ tests)
data/                     Data Loader CSVs (upsert keys: *_Key__c, Billing_Charge_Id__c)
docs/                     PRD, STA, DATA_MODEL, CHANGE_MANAGEMENT, SYNC_RULES, AI_LOG, runbooks/, generated/
.claude/commands/         /impact, /release-notes, /metadata-review
.github/                  CI, rollback-note check, PR template
```

## Docs
[PRD](docs/PRD.md) · [Architecture](docs/STA.md) · [Data model](docs/DATA_MODEL.md) · [Change management](docs/CHANGE_MANAGEMENT.md) · [GTM sync rules](docs/SYNC_RULES.md) · Runbooks: [sync failure](docs/runbooks/zuora-sync-failure.md), [duplicate event](docs/runbooks/duplicate-billing-event.md), [exhausted retry](docs/runbooks/exhausted-retry.md), [rollback & bulk data](docs/runbooks/deploy-rollback-and-bulk-data.md), [reconciliation mismatch](docs/runbooks/reconciliation-mismatch.md) · Generated: [fields](docs/generated/FIELD_INVENTORY.md), [flows](docs/generated/FLOW_CATALOG.md), [reports](docs/generated/REPORT_INDEX.md), [mappings](docs/generated/MAPPING_MATRIX.md)
