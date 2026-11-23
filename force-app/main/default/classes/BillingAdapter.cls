/**
 * Seam between Salesforce and the billing system (Zuora, simulated in this project).
 * BillingAdapterFactory picks the implementation from Integration_Config__mdt.Mode__c, so callers never change.
 */
public abstract class BillingAdapter {
    /** One quote line as the billing system sees it (Zuora-shaped charge). */
    public class Line {
        public String chargeId;
        public String productName;
        public String chargeType;
        public String billingPeriod;
        public Decimal quantity;
        public Decimal unitPrice;
        public Decimal discountPercent;
    }

    /** Create-subscription request. No payment data by design. */
    public class Request {
        public String idempotencyKey;
        public Id quoteId;
        public String quoteNumber;
        public String quoteType;
        public Id accountId;
        public String accountName;
        public String billingAccountNumber;
        public Integer termMonths;
        public Date termStartDate;
        public List<Line> lines = new List<Line>();
    }

    /** Result of a billing call. httpStatus 0 means no response (network/timeout). */
    public class Response {
        public Boolean success = false;
        public Integer httpStatus;
        public String errorMessage;
        public String accountNumber;
        public String subscriptionNumber;
        public Integer version;
        public String status;
        public Date termStartDate;
        public Date termEndDate;
        public Decimal mrr;
    }

    /** Creates (or idempotently returns) the subscription for a quote. Must not throw for HTTP/business errors. */
    public abstract Response createSubscription(Request request);

    /** Billing's current view of these subscriptions, keyed by subscription number (missing = not in billing). Used by reconciliation. */
    public abstract Map<String, Response> getSubscriptions(Set<String> subscriptionNumbers);

    /** Called after the sync's own DML (callouts must happen before any DML). The stub persists its simulated state here. */
    public virtual void commitWork() {
        return;
    }

    /** Monthly recurring revenue: recurring lines only, normalized to one month, after discount. */
    public static Decimal monthlyRecurring(List<Line> lines) {
        Decimal total = 0;
        for (Line l : lines) {
            if (l.chargeType != 'Recurring') {
                continue;
            }
            Decimal months = l.billingPeriod == 'Annual' ? 12 : (l.billingPeriod == 'Quarter' ? 3 : 1);
            Decimal discount = l.discountPercent ?? 0;
            total += (l.quantity * l.unitPrice * (1 - discount / 100)) / months;
        }
        return total.setScale(2);
    }
}
