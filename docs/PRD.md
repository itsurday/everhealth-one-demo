# EverHealth One — PRD

**Quote-to-Cash & RevOps Control Plane** · v2.0 · 2026-11-22 · Portfolio simulation on Salesforce

> **Positioning.** EverHealth One is a fictional portfolio project. It is not an EverCommerce product, doesn't reflect EverCommerce's internal architecture, and wasn't built with access to any EverCommerce system.
> **Simulated systems.** Zuora (CPQ X + Billing), HubSpot, ChurnZero and the other GTM tools are **simulated**. No vendor packages are installed. Every simulated component is labeled "(simulated)" in the UI and the docs.
> **Data.** Synthetic data only. No PHI, patient data, card numbers, bank details or payment tokens.

## 1. Summary
Salesforce is the hub of a Salesforce + Zuora quote-to-cash stack. EverHealth One shows how a senior admin/architect runs that hub. It covers a Zuora-shaped product catalog and quoting, an async billing sync that survives failure and duplicates, the operator tooling to troubleshoot it, GTM sync rules, data-quality controls, a GitHub/`sf` release process with mandatory rollback notes, living documentation generated from metadata, and AI-assisted development with Claude Code.

## 2. JD traceability
Source: EverHealth job posting R-106638 (Sr Salesforce Administrator / Architect).

| JD item | What the project shows |
|---|---|
| Zuora CPQ X: catalog, quote templates, pricing, amend/renew | Zuora-shaped catalog fields on Product2; native Quote Template PDF; Quote types New/Amend/Renew; discount approval; renewal Opportunity generator; (stretch) Amend/Renew screen flow |
| SF ↔ Zuora Billing sync + troubleshooting | Async sync to simulated billing → IDs/status written back; idempotent Apex REST billing-event intake; **failure switch** (live demo); Integration_Log with error categories; operator retry; sync-failure runbook; (stretch) reconciliation |
| Objects, fields, layouts, record types, VRs, formulas, Flows | Opportunity record types + layouts; validation rules; formula fields; record-triggered, scheduled and screen Flows |
| Gearset + SFDX + GitHub, CI/CD, rollbacks | SFDX repo; GitHub Actions (validate, Apex tests, Code Analyzer); rollback note required on every PR, enforced by a check; (stretch) 2nd-org promotion + rollback drill + org diff |
| Change-management standards, prod + sandboxes | `docs/CHANGE_MANAGEMENT.md`; PR template; rollback-note PR check |
| Multi-org, architecture view, downstream impact | ADRs; system-of-record boundaries; `/impact <Object.Field>` command |
| GTM stack: mappings, sync rules, lifecycle logic | `Field_Mapping__mdt`; sync-rules matrix (direction, winning system, conflict rule, lifecycle mapping) for HubSpot/ChurnZero/Gong/Outreach/ZoomInfo/Chili Piper |
| Data Loader, data-quality standards + monitoring | Data Loader–format CSVs, upsert on External IDs; duplicate/matching rules; completeness formula; Data Quality dashboard; bulk-op runbook |
| AI solutions with outcomes; Claude Code | `CLAUDE.md`; `.claude/commands/` (`/impact`, `/release-notes`, `/metadata-review`); `docs/AI_LOG.md` (task, result, time saved) |
| Living docs + rollback notes | Generator builds field inventory, Flow catalog and report index from metadata; 5 runbooks |
| Reporting / dashboards (BI as needed) | 4 dashboards; Looker/Tableau out of scope |
| Nice-to-have: Apex/SOQL | Small layered Apex, ≥85% coverage |
| Nice-to-have: healthcare / regulated data | Fictional practice-management SaaS customers; no PHI; field sensitivity labels in the field inventory |
| Nice-to-have: Salesforce CPQ / Revenue Cloud | ADR comparing it with Zuora CPQ X (no build) |

## 3. Problem
In a Salesforce + Zuora stack, revenue breaks at the seams. A quote is accepted but never reaches billing. A retried sync creates a second subscription. Renewals are missed because term dates live in another system. A field change in Salesforce silently breaks a HubSpot mapping or a report. Nobody can say what a release changed or how to undo it. The admin/architect needs a controlled pipeline from quote to billing, visibility when it fails, and governance so that many teams can change one org safely.

## 4. Goals and non-goals
**Goals**
1. Quote a Zuora-shaped catalog with approval guardrails and a branded PDF.
2. Sync accepted quotes to (simulated) billing asynchronously and idempotently, and write back IDs and status.
3. Make sync failures visible, categorized and safely retryable by an authorized operator only.
4. Generate renewals ahead of term end.
5. Define GTM sync rules and data-quality controls as reviewable artifacts.
6. Release through Git + CI with a rollback note on every change.
7. Keep documentation current by generating it from metadata.
8. Use AI (Claude Code) for real, measured development work.

**Non-goals**
- Rebuilding billing, invoicing, payments, tax or revenue recognition. Zuora owns these.
- Customer health, risk or success planning. ChurnZero owns these (see backlog).
- Live vendor integrations or managed packages.
- Storing PHI or payment data.
- AI taking autonomous financial, access or customer-facing actions.

## 5. Personas
| Persona | Needs |
|---|---|
| Sales Rep | Build quotes from the catalog; submit for approval; generate the PDF |
| Sales Manager | Approve discounts; see pipeline and renewals |
| Billing / RevOps Analyst | See subscription status and sync state; read-only on billing data |
| Integration Operator | Diagnose failed syncs; retry within limits |
| Salesforce Admin / Architect | Own the data model, automation, releases, docs and data quality |

## 6. Requirements
**P0** = must ship for the demo. **P1** = stretch, built in plan order only if P0 is done.

### Q2C — Quote-to-cash
| ID | Requirement | Pri | Acceptance |
|---|---|:-:|---|
| Q2C-01 | Zuora-shaped catalog on Product2 | P0 | Products carry Charge Type, Charge Model, Billing Period and a unique charge ID |
| Q2C-02 | Opportunity record types New Business / Amendment / Renewal | P0 | Each has its own layout and stage path |
| Q2C-03 | Quote with `Quote_Type__c` New/Amend/Renew | P0 | Type defaults from the Opportunity record type |
| Q2C-04 | Discount approval | P0 | Max line discount above the `Q2C_Setting__mdt` threshold requires manager approval before acceptance |
| Q2C-05 | Quote PDF from a native Quote Template | P0 | PDF shows charge type and billing period per line |
| Q2C-06 | Renewal Opportunity generator | P0 | Scheduled Flow creates exactly one Renewal Opp per subscription term, N days before term end |
| Q2C-07 | Amend/Renew screen flow from a subscription | P1 (built) | Pre-fills an Amendment/Renewal Opp + Quote from current recurring charges; amendments co-term to the term end |

### SYNC — Billing sync and troubleshooting
| ID | Requirement | Pri | Acceptance |
|---|---|:-:|---|
| SYNC-01 | Async sync on Quote acceptance | P0 | Save never waits on billing; a Queueable sends the quote and writes back account/subscription numbers |
| SYNC-02 | Idempotent billing-event intake | P0 | Apex REST `/billing/events`; the same `External_Event_Key__c` sent twice is processed once and the duplicate is logged |
| SYNC-03 | Integration_Log for every attempt | P0 | Direction, event type, correlation ID, status, attempt count, HTTP status, error category, sanitized error |
| SYNC-04 | Failure switch | P0 | `Integration_Config__mdt.Fail_Mode__c` (None/Timeout/RateLimit/Validation) makes the stub fail on demand |
| SYNC-05 | Bounded retry | P0 | Retryable categories retry up to `Max_Attempts__c` with the same idempotency key; Validation never auto-retries |
| SYNC-06 | Operator-only retry | P0 | Screen flow is usable only with the `EH_Retry_Integration` custom permission; others are blocked and can't see error details |
| SYNC-07 | Reconciliation | P1 (built) | Daily compare of SF vs billing (simulated Zuora store) flags each mismatch on Integration_Log |

### GTM — Operational stack
| ID | Requirement | Pri | Acceptance |
|---|---|:-:|---|
| GTM-01 | Field mappings as metadata | P0 | `Field_Mapping__mdt` rows per system/field: direction, winning system, conflict rule |
| GTM-02 | Sync-rules matrix | P0 | `docs/SYNC_RULES.md` covers HubSpot, ChurnZero, Gong, Outreach, ZoomInfo, Chili Piper, incl. lifecycle-stage mapping |

### DQ — Data quality and bulk data
| ID | Requirement | Pri | Acceptance |
|---|---|:-:|---|
| DQ-01 | Data Loader–format seed CSVs | P0 | Upsert on External IDs; reloading changes nothing |
| DQ-02 | Duplicate + matching rules | P0 | Account and Contact duplicates are alerted on create |
| DQ-03 | Completeness score | P0 | Formula on Account; Data Quality dashboard lists gaps |
| DQ-04 | Bulk-op runbook | P0 | Back up → upsert → verify → roll back from backup |

### REL — Release and change management
| ID | Requirement | Pri | Acceptance |
|---|---|:-:|---|
| REL-01 | SFDX source in GitHub | P0 | All metadata in source format; no secrets |
| REL-02 | CI on every PR | P0 | Validate deploy + Apex tests + Code Analyzer must pass |
| REL-03 | Rollback note required | P0 | A PR without a filled "Rollback" section fails a check |
| REL-04 | Change-management standard | P0 | `docs/CHANGE_MANAGEMENT.md`: environments, review, release windows, rollback |
| REL-05 | 2nd-org promotion + rollback drill | P1 | Promote with `sf`, roll back, show org diff |

### DOC — Living documentation
| ID | Requirement | Pri | Acceptance |
|---|---|:-:|---|
| DOC-01 | Generated docs | P0 | Script writes `FIELD_INVENTORY.md` (with sensitivity labels), `FLOW_CATALOG.md`, `REPORT_INDEX.md` from metadata |
| DOC-02 | Runbooks | P0 | Sync failure, duplicate event, exhausted retry, deploy rollback + bulk-data op |

### AI — AI-assisted development
| ID | Requirement | Pri | Acceptance |
|---|---|:-:|---|
| AI-01 | Claude Code project setup | P0 | `CLAUDE.md` with conventions and guardrails |
| AI-02 | Custom commands | P0 | `/impact <Object.Field>` lists every Flow, VR, layout, report and mapping using a field; `/release-notes`; `/metadata-review` |
| AI-03 | AI log | P0 | `docs/AI_LOG.md`: task, result, time saved, human review |
| AI-04 | AI sync triage | P1 | Bedrock or Claude API suggests a cause/fix for a failed sync; a human must review it. Only if model access is already approved |

## 7. System boundaries
| Domain | System of record | Salesforce role |
|---|---|---|
| Accounts, Contacts, Leads, Opportunities, Quotes | Salesforce | Owner |
| Product catalog (commercial view) | Salesforce (mirrors Zuora catalog shape) | Owner for quoting |
| Subscriptions, invoices, payments | Zuora (simulated) | Read-mostly summary in `Billing_Subscription__c`; no payment data |
| Marketing lifecycle | HubSpot (simulated) | Receives MQL → owns from SQL onward (see SYNC_RULES) |
| Customer health / CS | ChurnZero (simulated) | Receives health score as read-only field |
| Integration delivery state | Salesforce `Integration_Log__c` | Owner |

## 8. Non-functional requirements
| Area | Requirement |
|---|---|
| Reliability | Tolerates duplicate delivery and transient failure; retries bounded |
| Performance | No callouts in save transactions; no SOQL/DML in loops |
| Security | Least privilege via permission sets; secrets only in Named/External Credentials; sanitized logs |
| Privacy | No PHI or payment data; field sensitivity labels on every custom field |
| Maintainability | Declarative first; one owner per automated process; config in Custom Metadata |
| Testability | Apex ≥85% coverage; positive, negative, bulk and failure paths |

## 9. Dashboards
1. **Pipeline & Quotes**: pipeline by stage and record type, quotes awaiting approval.
2. **Q2C Sync Health**: logs by status and error category, open retryable failures, exhausted retries.
3. **Renewals Due**: renewal Opps by term-end month, subscriptions without a renewal.
4. **Data Quality**: Accounts by completeness band, missing critical fields, duplicate alerts.

Numbers come from synthetic data and aren't benchmarks.

## 10. Success measures
| JD area | Measured by |
|---|---|
| Q2C | Quote → approval → PDF → accepted runs in the demo without manual fixes |
| Sync troubleshooting | Failure switch → categorized log → operator retry succeeds; duplicate event processed once |
| Governance | A PR without a rollback note is blocked; CI green on main |
| Architecture / impact | `/impact Account.Lifecycle_Stage__c` returns every dependent component |
| Data quality | Re-running the seed upsert creates 0 new records; duplicate rule fires |
| AI outcomes | AI_LOG records each AI-assisted task with time saved and review notes |
| Code quality | Apex coverage ≥85%; Code Analyzer has no high-severity findings |

## 11. Demo script (5 min)
1. Opp (New Business) → Quote with Zuora-shaped products → discount triggers approval → Quote PDF from template.
2. Accept Quote → async sync → `Billing_Subscription__c` gets the subscription number.
3. Send the same billing event twice → processed once (Integration_Log shows the duplicate).
4. Flip `Fail_Mode__c` to RateLimit → sync fails → categorized log → operator retries; a non-operator user can't.
5. Renewal Opportunity generated before term end.
6. Data Quality dashboard + duplicate rule.
7. In the repo: `/impact Account.Lifecycle_Stage__c`, generated field inventory with sensitivity labels, a PR blocked for a missing rollback note, AI_LOG.

## 12. Backlog (cut from v1, with reasons)
| Item | Reason |
|---|---|
| Customer_Health, Customer_Risk, Success_Plan, Success_Action, Usage_Snapshot, Health_Score_Config | ChurnZero owns customer health and CS workflows; duplicating them in Salesforce creates two sources of truth |
| Onboarding_Project / Onboarding_Task | Not in the JD; not part of quote-to-cash |
| Renewal_Work | Replaced by Renewal Opportunities (record type), the standard Q2C pattern |
| Handoff | Not in the JD |
| HubSpot/ChurnZero live mock intake, hosted mock (Cloudflare Worker) | Time; the in-org stub proves the same patterns |

## 13. Risks
| Risk | Mitigation |
|---|---|
| Simulation mistaken for real Zuora/Gearset depth | Label every simulation; talk about patterns, not product depth |
| Standard Quote features blocked in Developer Edition | Enable early; fall back to a custom Quote object only if blocked |
| Duplicate or retried events create duplicates | Unique keys + idempotent services + bounded retry |
