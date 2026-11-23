@IsTest
private class RetryPolicy_Test {
    @IsTest
    static void categorizesHttpStatuses() {
        Map<Integer, String> expected = new Map<Integer, String>{
            0 => 'Network', 408 => 'Timeout', 504 => 'Timeout', 429 => 'Rate Limit',
            401 => 'Authentication', 403 => 'Authentication', 500 => 'Server', 503 => 'Server',
            400 => 'Validation', 422 => 'Validation', 302 => 'Unknown'
        };
        for (Integer status : expected.keySet()) {
            Assert.areEqual(expected.get(status), RetryPolicy.categorize(status), 'HTTP ' + status);
        }
        Assert.areEqual('Network', RetryPolicy.categorize(null), 'null status means no response');
    }

    @IsTest
    static void onlyTransientCategoriesRetry() {
        for (String c : new List<String>{ 'Timeout', 'Network', 'Rate Limit', 'Server' }) {
            Assert.isTrue(RetryPolicy.isRetryable(c), c);
        }
        for (String c : new List<String>{ 'Validation', 'Authentication', 'Unknown' }) {
            Assert.isFalse(RetryPolicy.isRetryable(c), c);
        }
    }

    @IsTest
    static void statusAfterFailureRespectsCeiling() {
        Assert.areEqual(RetryPolicy.RETRYABLE, RetryPolicy.statusAfterFailure('Rate Limit', 1, 3));
        Assert.areEqual(RetryPolicy.RETRYABLE, RetryPolicy.statusAfterFailure('Timeout', 2, 3));
        Assert.areEqual(RetryPolicy.EXHAUSTED, RetryPolicy.statusAfterFailure('Timeout', 3, 3));
        Assert.areEqual(RetryPolicy.PERMANENT, RetryPolicy.statusAfterFailure('Validation', 1, 3), 'validation never auto-retries');
    }

    @IsTest
    static void backoffDoublesPerAttempt() {
        Datetime now = Datetime.newInstanceGmt(2026, 11, 22, 12, 0, 0);
        Assert.areEqual(now.addSeconds(60), RetryPolicy.nextAttemptAt(now, 1, 60));
        Assert.areEqual(now.addSeconds(120), RetryPolicy.nextAttemptAt(now, 2, 60));
        Assert.areEqual(now.addSeconds(240), RetryPolicy.nextAttemptAt(now, 3, 60));
    }
}
