# GTM Sync Rules (simulated systems)

Policy for the operational tech stack around Salesforce. **HubSpot, ChurnZero, Gong, Outreach, ZoomInfo and Chili Piper are simulated:** no packages or live connections. The rules are real design, stored as `Field_Mapping__mdt` records and rendered in [generated/MAPPING_MATRIX.md](generated/MAPPING_MATRIX.md). Before changing a mapped field, run `/impact <Object.Field>`.

## 1. Principles
1. **One system of record per data domain.** Salesforce owns accounts, opportunities, quotes and commercial data. Zuora owns subscriptions and invoices. HubSpot owns marketing engagement until SQL. ChurnZero owns customer health.
2. **Direction is explicit** for every mapped field: Inbound, Outbound or Bidirectional.
3. **Conflicts are resolved by rule, not by "last sync wins" by accident.**
4. **Enrichment never overwrites a human edit.**
5. **Activity tools append, never update** Salesforce records.
6. **External IDs** (`HubSpot_*_Id__c`, `ChurnZero_Account_Id__c`) are the match keys. Never match on name.

## 2. Conflict rules
| Rule | Meaning | Used for |
|---|---|---|
| Source Wins | The external system's value always replaces Salesforce's | HubSpot lifecycle before SQL, ChurnZero health score, external IDs |
| Salesforce Wins | Salesforce's value always replaces the external value | Account lifecycle after SQL, owner, billing account number |
| Most Recent | The latest modified timestamp wins (both sides keep timestamps) | Lead email |
| Fill Blank Only | External value applied only when the Salesforce field is blank | ZoomInfo website/phone, HubSpot practice type |
| Append Only | Creates new activity records; never edits existing ones | Gong calls, Outreach steps, Chili Piper meetings |

## 3. Lifecycle stage mapping
| HubSpot lifecycle (Lead.`HubSpot_Lifecycle_Stage__c`) | Salesforce | Owner of the stage |
|---|---|---|
| Subscriber, Lead | Lead, Status *Open* | HubSpot |
| MQL | Lead, Status *Working* | HubSpot |
| SQL | Lead converted → Account `Lifecycle_Stage__c` = **Prospect**, Opportunity (New Business) | **Salesforce from here on** |
| Opportunity | Open Opportunity | Salesforce |
| Customer | First subscription **Active** in Zuora (simulated) → `Lifecycle_Stage__c` = **Customer** (flow `EH_Account_Lifecycle_From_Subscription`) | Salesforce (from billing) |
| Former customer | Last subscription Cancelled/Expired → **Former Customer** | Salesforce (from billing) |

Salesforce sends `Lifecycle_Stage__c` back out to HubSpot and ChurnZero (Outbound, Salesforce Wins), so marketing stops nurturing customers and ChurnZero starts tracking them.

## 4. Per system
| System | What syncs | Direction | Notes |
|---|---|---|---|
| HubSpot | Leads/contacts, lifecycle, practice type, IDs | Bidirectional | HubSpot wins until SQL; Salesforce after. Dedupe on `HubSpot_Contact_Id__c`, then email. |
| ChurnZero | Account, lifecycle, billing account number → CZ; health score → SF | Both | `ChurnZero_Health_Score__c` is read-only in SF (ADR-004). No CS objects in Salesforce. |
| Gong | Calls → Activities | Inbound | Append only; links by contact email. |
| Outreach | Sequence steps → Activities | Inbound | Append only; sequence status stays in Outreach. |
| ZoomInfo | Website, phone (firmographics) | Inbound | Fill blank only; never overwrites. |
| Chili Piper | Booked meetings → Events; routing suggestion | Inbound | Salesforce assignment rules decide the owner. |

## 5. Change rules
- Adding or changing a mapping = a `Field_Mapping__mdt` record change in a PR, with `/impact` output and a rollback note.
- Removing a mapped field requires the tool owner's sign-off first (the integration fails loudly otherwise).
- Field type changes (e.g. picklist values) on mapped fields: update the external picklist first, then Salesforce.
