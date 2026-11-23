"""Self-test for eh_metadata, gen_docs and impact. Run: python scripts/test_docs.py"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_docs  # noqa: E402
import impact  # noqa: E402

NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'
FILES = {
    "objects/Billing_Subscription__c/fields/Status__c.field-meta.xml":
        f"<CustomField {NS}><fullName>Status__c</fullName><label>Status</label><type>Picklist</type>"
        "<securityClassification>Internal</securityClassification><description>Zuora-shaped</description></CustomField>",
    "objects/Integration_Log__c/fields/Status__c.field-meta.xml":
        f"<CustomField {NS}><fullName>Status__c</fullName><label>Status</label><type>Picklist</type>"
        "<securityClassification>Restricted</securityClassification><complianceGroup>PII</complianceGroup></CustomField>",
    "flows/Sub_Flow.flow-meta.xml":
        f"<Flow {NS}><label>Sub Flow</label><processType>AutoLaunchedFlow</processType><description>Watches status</description>"
        "<start><object>Billing_Subscription__c</object><triggerType>RecordAfterSave</triggerType><recordTriggerType>Update</recordTriggerType></start>"
        "<status>Active</status><decisions><leftValueReference>$Record.Status__c</leftValueReference></decisions></Flow>",
    "layouts/Integration_Log__c-Log Layout.layout-meta.xml": f"<Layout {NS}><field>Status__c</field></Layout>",
    "layouts/Billing_Subscription__c-Sub Layout.layout-meta.xml": f"<Layout {NS}><field>Status__c</field></Layout>",
    "reports/EH_Reports/Logs.report-meta.xml":
        f"<Report {NS}><name>Logs</name><reportType>EH_Logs__c</reportType><groupingsDown><field>Integration_Log__c$Status__c</field></groupingsDown></Report>",
    "customMetadata/Field_Mapping.CZ_Status.md-meta.xml":
        f"<CustomMetadata {NS}><label>x</label><values><field>System__c</field><value>ChurnZero</value></values>"
        "<values><field>SF_Object__c</field><value>Billing_Subscription__c</value></values>"
        "<values><field>SF_Field__c</field><value>Status__c</value></values></CustomMetadata>",
}


class DocsAndImpactTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        for rel, body in FILES.items():
            path = os.path.join(self.tmp.name, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write('<?xml version="1.0" encoding="UTF-8"?>\n' + body)

    def tearDown(self):
        self.tmp.cleanup()

    def test_impact_matches_only_the_right_object(self):
        hits = {(kind, comp) for kind, comp, _, _ in impact.find("Billing_Subscription__c", "Status__c", self.tmp.name)}
        self.assertIn(("Field definition", "Status__c"), hits)
        self.assertIn(("Flow", "Sub_Flow"), hits)
        self.assertIn(("Page layout", "Billing_Subscription__c-Sub Layout"), hits)
        self.assertIn(("GTM field mapping", "Field_Mapping.CZ_Status"), hits)
        self.assertNotIn(("Page layout", "Integration_Log__c-Log Layout"), hits, "same field name on another object")
        self.assertFalse(any(kind == "Report" for kind, _ in hits), "report groups the other object's Status__c")

    def test_impact_rejects_bad_input(self):
        self.assertEqual(2, impact.main(["not-a-field"]))
        self.assertIn("External systems affected", impact.render("Billing_Subscription__c", "Status__c",
                                                                  impact.find("Billing_Subscription__c", "Status__c", self.tmp.name)))

    def test_field_inventory_shows_sensitivity_and_compliance(self):
        doc = gen_docs.field_inventory(self.tmp.name)
        self.assertIn("| `Status__c` | Status | Picklist | Restricted | PII |", doc)
        self.assertIn("## Billing_Subscription__c", doc)

    def test_flow_catalog_and_mapping_matrix(self):
        self.assertIn("| `Sub_Flow` | RecordAfterSave Update | Billing_Subscription__c | Active | Watches status |", gen_docs.flow_catalog(self.tmp.name))
        self.assertIn("| ChurnZero | Billing_Subscription__c.Status__c |", gen_docs.mapping_matrix(self.tmp.name))

    def test_output_is_deterministic(self):
        self.assertEqual(gen_docs.render_all(self.tmp.name), gen_docs.render_all(self.tmp.name))


if __name__ == "__main__":
    unittest.main()
