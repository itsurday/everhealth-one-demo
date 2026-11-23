# AI Log

How AI (Claude Code) was used to build EverHealth One, what a human reviewed, and what it saved. Rules for AI work are in `CLAUDE.md` and docs/CHANGE_MANAGEMENT.md §7: **AI drafts, humans decide**, and AI output goes through the same PR, CI and review as anything else.

**How to read "time":** *Actual* is wall-clock from git timestamps (2026-11-22, CST). *Manual estimate* is the plan's own per-task estimate made before starting, so it's an estimate and not a measurement.

**PR numbers** (#1–#11) refer to the private build repo; this public copy starts from a single commit.

## Summary
| # | Task | Actual | Manual estimate | Human decisions and review |
|---|---|---|---|---|
| 0 | Repo, CLI, GitHub, scratch org | ~20 min | 1 h | Chose a scratch org over a Developer Edition org; kept the repo private during the build (this public repo is a cleaned-up copy) |
| 1 | Rewrite PRD / STA / Data Model around the JD | ~20 min | 2 h | Reviewed and approved the three docs |
| 2 | SFDX scaffold: 70+ fields, objects, CMDT, perm sets, layouts, CI, rollback check | ~30 min | 3 h | Reviewed and merged PR #1 |
| 3 | Billing sync Apex (TDD): 38 tests, 98% coverage | ~25 min | 4 h | Reviewed and merged PR #2 |
| 4 | Flows, approval process, retry screen | ~50 min (20 min was waiting for a scheduled run) | 2.5 h | Reviewed and merged PR #3 |
| 5 | Demo data, reports, dashboards | ~25 min | 2 h | Reviewed and merged PR #4 |
| 6 | Doc generator, `/impact`, runbooks, CLAUDE.md, README | ~15 min | 2.5 h | Reviewed and merged PR #5 |
| S1 | Stretch: Amend / Renew action (screen flow + Apex, 6 tests) | ~20 min | 1.5–2 h | Chose this stretch item (JD: amendment/renewal flows) |
| S2 | Stretch: daily reconciliation + simulated Zuora store (8 tests) | ~30 min | 1.5 h | Chose this stretch item (JD: troubleshooting the SF ↔ Zuora sync) |
| | **Total (tasks 0–S2)** | **~4 h** | **~20.5 h** | |
| V | Demo video (brag + Hyperframes): read-only org captures, script against the JD, Kokoro voiceover | ~3 h incl. renders (estimate, not timed) | ~1.5–2 days (estimate, not from the plan) | Chose the story and voice, generated the presenter images, approved the script, asked for "Every failure queued", reviewed v1 and v2 and approved v2. AI redacted the Dev Hub email from the quote-PDF capture |

## What the AI did, and what review caught
Every item below was caught by a guardrail (deploy validation, tests, Code Analyzer, project rules) or by the human, not shipped silently.

| Task | AI output | Caught / changed | How it was caught |
|---|---|---|---|
| 1 | Doc rewrite with JD traceability, 6 v1 defects fixed | Docs came out at ~68% of the original length vs a "~half" target; the human accepted them as is | Human review |
| 2 | Generated field/permission XML from the data-model spec | Business processes can't set a default stage; "View All" on a child needs it on the parent; duplicate-rule sort order clashed with standard rules | Deploy errors, fixed before commit |
| 2 | CI on Node 20 | Current `sf` CLI needs Node 22 | First CI run failed; fixed in the same PR |
| 3 | Queueable chaining guarded by `Test.isRunningTest()` | Rejected: the project's Apex rules forbid test-only branches in production code. Redesigned to one job per 50 records, no chaining | Project rules (`CLAUDE.md` / Apex standards) |
| 3 | Local variable `accepted` next to constant `ACCEPTED` | Apex is case-insensitive, so they collided | Compile error |
| 3 | Integration DML in default (system) mode | Code Analyzer flagged 18 high-severity CRUD findings; made system mode explicit and documented per class | Code Analyzer severity gate |
| 4 | Approval entry criteria using the CMDT-driven formula | Approval processes can't read Custom Metadata; threshold moved to the validation rule (still one source of truth) | Deploy error |
| 4 | Redeploy while auto-retry jobs were scheduled | Platform blocks deploys of classes used by scheduled jobs; added `Deployment.settings` and documented it as a release step | Deploy error |
| 4 | Scheduled flow time `15:10` | Interpreted in the org's timezone (Pacific), not UTC | Checked `CronTrigger.NextFireTime` |
| 5 | Seed idempotency check on `Opportunity.Description` | Long-text fields can't be filtered | Runtime error |
| 5 | Expected duplicate rules to flag the bulk-loaded duplicates | Bulk/API loads don't create Duplicate Record Sets; added a scan using the org's matching rules | Verification query |
| S2 | One class as both Schedulable and Queueable | Platform forbids it; split into the scheduled class + an inner Queueable runner | Test failure |
| 6 | `/impact` text scan | Self-test proves a same-named field on another object isn't reported | `scripts/test_docs.py` |
| V | Presenter avatar crop | Scaled ~2.5× too large, so only the face centre showed in the circle; now head-and-shoulders and sized from the real image | Human review of v1 |
| V | Billing Subscription framing | Duplicate "Subscription Number" rows were visible at ~40 s; reframed and re-rendered | AI frame check while compressing the web copy |
| V | README video link | A link to a repo `.mp4` opens the raw file view; switched to a GitHub `user-attachments` upload (under 10 MB web copy) that plays inline | Human review on GitHub |
| V | Layout-only fix for the duplicate field (df8f262) | A required field is forced back onto layouts on deploy; made `Subscription_Number__c` optional and added explicit FLS in 5 permission sets + Admin (PR #11) | Deploy to eh-demo and a retrieve of the layout; `/impact` before the change |

## Practices that kept AI output safe
- **Specs first:** PRD/STA/Data Model reviewed by the human before any metadata was generated.
- **Generated, then validated:** every generated file went through a real deploy to a scratch org before commit.
- **Tests first for Apex:** test classes written before implementations; 46 Apex tests, 98% coverage, bulk and permission cases.
- **Live verification:** each task smoke-tested in the org (sync, duplicate event via REST, renewal run, non-operator blocked), then test records deleted.
- **No secrets:** secret scan before each push; credentials only in Named/External Credentials.
- **Human gates:** the human approved the plan, chose the org strategy and publishing approach, and merged every PR.

## Reusable AI tooling in this repo
| Tool | Saves |
|---|---|
| `/impact <Object.Field>` (`scripts/impact.py`) | Manual "where is this field used?" search across flows, layouts, reports, mappings, Apex |
| `python scripts/gen_docs.py` | Hand-maintained field inventory, flow catalog, report index, mapping matrix (CI keeps them current) |
| `/release-notes` | Drafting release + rollback notes from a git range |
| `/metadata-review` | Pre-PR checklist review against project rules |
