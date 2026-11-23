/**
 * HTTP adapter for a billing endpoint reached through a Named Credential (Zuora_Billing).
 * Not used in the demo (Mode__c = Stub). Mapping to Zuora's real API payloads is out of scope;
 * this shows the production seam: Named Credential, idempotency header, no response bodies in logs.
 */
public with sharing class HttpBillingAdapter extends BillingAdapter {
    private final String namedCredential;
    private final Integer timeoutMs;

    public HttpBillingAdapter(String namedCredential, Integer timeoutMs) {
        this.namedCredential = namedCredential;
        this.timeoutMs = timeoutMs;
    }

    public override Response createSubscription(Request request) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + namedCredential + '/v1/subscriptions');
        req.setMethod('POST');
        req.setTimeout(timeoutMs);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Idempotency-Key', request.idempotencyKey);
        req.setBody(JSON.serialize(request));

        Response res = new Response();
        try {
            HttpResponse http = new Http().send(req);
            res.httpStatus = http.getStatusCode();
            if (res.httpStatus >= 200 && res.httpStatus < 300) {
                Response parsed = (Response) JSON.deserialize(http.getBody(), Response.class);
                parsed.success = true;
                parsed.httpStatus = res.httpStatus;
                return parsed;
            }
            res.errorMessage = 'HTTP ' + res.httpStatus + ' from billing'; // body withheld: may contain sensitive data
        } catch (CalloutException e) {
            res.httpStatus = 0;
            res.errorMessage = e.getMessage();
        }
        return res;
    }

    /** GET billing's view of the subscriptions. Throws on failure so reconciliation never mistakes an outage for "missing". */
    public override Map<String, Response> getSubscriptions(Set<String> subscriptionNumbers) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + namedCredential + '/v1/subscriptions?numbers='
            + EncodingUtil.urlEncode(String.join(new List<String>(subscriptionNumbers), ','), 'UTF-8'));
        req.setMethod('GET');
        req.setTimeout(timeoutMs);
        HttpResponse http = new Http().send(req);
        if (http.getStatusCode() != 200) {
            throw new BillingSyncService.BillingSyncException('Billing lookup failed: HTTP ' + http.getStatusCode());
        }
        Map<String, Response> out = new Map<String, Response>();
        for (Response r : (List<Response>) JSON.deserialize(http.getBody(), List<Response>.class)) {
            r.success = true;
            out.put(r.subscriptionNumber, r);
        }
        return out;
    }
}
