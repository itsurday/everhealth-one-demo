---
description: Downstream impact of a Salesforce field before you change it (Flows, VRs, layouts, reports, GTM mappings, Apex)
argument-hint: <Object.Field>  e.g. Account.Lifecycle_Stage__c
allowed-tools: Bash(python scripts/impact.py:*), Read, Grep
---

Field to analyze: `$ARGUMENTS`

1. Run `python scripts/impact.py $ARGUMENTS` and read its output. It is a text scan of `force-app`; treat "Apex (possible)" hits as leads, and open those files to confirm.
2. Write a short impact brief:
   - **What uses it**: the components grouped by type (keep the file links).
   - **Who is affected**: user-facing pieces (layouts, reports, dashboards), automation (flows, approval, Apex), and **external systems** from `GTM field mapping` hits (HubSpot / ChurnZero etc., simulated). Name the conflict rule from `docs/generated/MAPPING_MATRIX.md`.
   - **Risk**: Low / Medium / High, with one line why (e.g. a flow writes it; an external system reads it; it drives a VR).
   - **Test plan**: the Apex test classes and manual checks to run.
   - **Rollback note draft**: ready to paste into the PR's `## Rollback` section.
3. Do not edit any files and do not touch an org. A human decides on the change.
