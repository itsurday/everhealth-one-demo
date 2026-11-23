/**
 * Picks the billing adapter from Integration_Config__mdt (record Zuora_Billing).
 */
public with sharing class BillingAdapterFactory {
    public static final String CONFIG_NAME = 'Zuora_Billing';
    private static final Integer DEFAULT_TIMEOUT_MS = 10000;

    @TestVisible
    private static Integration_Config__mdt testConfig;

    /** Active billing integration config. Tests inject an in-memory record because CMDT can't be inserted. */
    public static Integration_Config__mdt config() {
        Integration_Config__mdt cfg = testConfig ?? Integration_Config__mdt.getInstance(CONFIG_NAME);
        if (cfg == null) {
            throw new BillingSyncService.BillingSyncException('Integration_Config__mdt.' + CONFIG_NAME + ' is missing.');
        }
        return cfg;
    }

    public static BillingAdapter create(Integration_Config__mdt cfg) {
        if (cfg.Mode__c == 'NamedCredential') {
            return new HttpBillingAdapter(cfg.Named_Credential__c, cfg.Timeout_Ms__c?.intValue() ?? DEFAULT_TIMEOUT_MS);
        }
        return new StubBillingAdapter(cfg.Fail_Mode__c);
    }
}
