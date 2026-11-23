@IsTest
private class IntegrationLogService_Test {
    @IsTest
    static void sanitizeRedactsSecretsAndPrefixesCategory() {
        String out = IntegrationLogService.sanitize('Authentication', 'Rejected Bearer abc.DEF-123 and password=hunter2 token: xyz');
        Assert.isTrue(out.startsWith('Authentication: '), out);
        Assert.isFalse(out.contains('abc.DEF-123'), out);
        Assert.isFalse(out.contains('hunter2'), out);
        Assert.isFalse(out.contains('xyz'), out);
        Assert.isTrue(out.contains('[REDACTED]'), out);
    }

    @IsTest
    static void sanitizeTruncatesAndHandlesBlank() {
        Assert.isTrue(IntegrationLogService.sanitize('Server', 'x'.repeat(5000)).length() <= 255);
        Assert.areEqual('Unknown: No detail', IntegrationLogService.sanitize('Unknown', null));
    }

    @IsTest
    static void hashIsStableSha256Hex() {
        String h = IntegrationLogService.hash('{"a":1}');
        Assert.areEqual(64, h.length());
        Assert.areEqual(h, IntegrationLogService.hash('{"a":1}'));
        Assert.areNotEqual(h, IntegrationLogService.hash('{"a":2}'));
    }

    @IsTest
    static void keysAndCorrelationIds() {
        Id fakeQuoteId = '0Q0000000000001AAA';
        Assert.areEqual('SF:QUOTE_SYNC:' + fakeQuoteId, IntegrationLogService.quoteSyncKey(fakeQuoteId));
        Assert.areNotEqual(IntegrationLogService.newCorrelationId(), IntegrationLogService.newCorrelationId());
    }
}
