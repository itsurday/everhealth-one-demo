/**
 * Helpers for Integration_Log__c: idempotency keys, correlation ids, payload hashes and sanitized errors.
 * Rule: never store raw bodies, tokens, secrets or payment data in a log.
 */
public with sharing class IntegrationLogService {
    private static final Integer MAX_ERROR_LENGTH = 255;
    private static final Pattern SECRET = Pattern.compile(
        '(?i)(bearer\\s+[A-Za-z0-9._~+/=-]+|(password|token|secret|api[_-]?key)\\s*[=:]\\s*\\S+)'
    );

    /** "<Category>: <message>" with secrets redacted, whitespace collapsed, max 255 chars. */
    public static String sanitize(String category, String message) {
        String msg = String.isBlank(message) ? 'No detail' : SECRET.matcher(message).replaceAll('[REDACTED]');
        msg = msg.normalizeSpace();
        return (category + ': ' + msg).abbreviate(MAX_ERROR_LENGTH);
    }

    /** SHA-256 hex of the payload, for correlation without storing it. */
    public static String hash(String payload) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(payload ?? '')));
    }

    public static String newCorrelationId() {
        return UUID.randomUUID().toString();
    }

    /** Idempotency key for the outbound sync of one quote; retries reuse it. */
    public static String quoteSyncKey(Id quoteId) {
        return 'SF:QUOTE_SYNC:' + quoteId;
    }
}
