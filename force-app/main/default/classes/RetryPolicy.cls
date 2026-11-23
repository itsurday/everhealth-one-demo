/**
 * Retry rules for billing sync (STA §3.4): categorize a failure, decide whether it auto-retries, and when.
 */
public with sharing class RetryPolicy {
    public static final String RETRYABLE = 'Retryable Failure';
    public static final String PERMANENT = 'Permanent Failure';
    public static final String EXHAUSTED = 'Exhausted';
    private static final Set<String> RETRYABLE_CATEGORIES = new Set<String>{ 'Timeout', 'Network', 'Rate Limit', 'Server' };

    /** Maps an HTTP status to an Integration_Log__c.Error_Category__c value. 0/null = no response. */
    public static String categorize(Integer httpStatus) {
        if (httpStatus == null || httpStatus == 0) {
            return 'Network';
        }
        if (httpStatus == 408 || httpStatus == 504) {
            return 'Timeout';
        }
        if (httpStatus == 429) {
            return 'Rate Limit';
        }
        if (httpStatus == 401 || httpStatus == 403) {
            return 'Authentication';
        }
        if (httpStatus >= 500) {
            return 'Server';
        }
        return httpStatus >= 400 ? 'Validation' : 'Unknown';
    }

    public static Boolean isRetryable(String category) {
        return RETRYABLE_CATEGORIES.contains(category);
    }

    /** Status after a failed attempt: retryable until the ceiling, then Exhausted; non-transient errors are Permanent. */
    public static String statusAfterFailure(String category, Integer attempts, Integer maxAttempts) {
        if (!isRetryable(category)) {
            return PERMANENT;
        }
        return attempts >= maxAttempts ? EXHAUSTED : RETRYABLE;
    }

    /** Exponential backoff: base x 2^(attempt-1). */
    public static Datetime nextAttemptAt(Datetime now, Integer attempts, Integer baseSeconds) {
        return now.addSeconds(baseSeconds * Integer.valueOf(Math.pow(2, attempts - 1)));
    }
}
