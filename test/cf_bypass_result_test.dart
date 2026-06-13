import 'package:cf_bypass/cf_bypass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CfBypassResult.success', () {
    test('rejects results without a bypass cookie', () {
      expect(
        () => CfBypassResult.success(
          url: 'https://example.com',
          userAgent: 'test-agent',
          cookies: const [
            CfBrowserCookie(
              name: 'session',
              value: 'abc',
              domain: 'example.com',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects empty user-agent', () {
      expect(
        () => CfBypassResult.success(
          url: 'https://example.com',
          userAgent: '',
          cookies: const [
            CfBrowserCookie(
              name: 'cf_clearance',
              value: 'clearance-token',
              domain: 'example.com',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('extracts bypass cookie values', () {
      final result = CfBypassResult.success(
        url: 'https://example.com',
        userAgent: 'test-agent',
        cookies: const [
          CfBrowserCookie(
            name: 'cf_clearance',
            value: 'clearance-token',
            domain: 'example.com',
          ),
          CfBrowserCookie(
            name: '__ddg1',
            value: 'ddg-token',
            domain: 'example.com',
          ),
        ],
      );

      expect(result.success, isTrue);
      expect(result.cfClearanceCookie, 'clearance-token');
      expect(result.ddosCookie, 'ddg-token');
    });
  });

  group('CfCookieHelper', () {
    test('separates managed cookies from bypass proof cookies', () {
      expect(CfCookieHelper.isCloudflareManagedCookie('__cf_bm'), isTrue);
      expect(CfCookieHelper.isBypassProofCookie('__cf_bm'), isFalse);
      expect(CfCookieHelper.isManagedProtectionCookie('__cf_bm'), isTrue);
      expect(CfCookieHelper.isBypassCookie('__cf_bm'), isTrue);

      expect(CfCookieHelper.isCloudflareManagedCookie('cf_clearance'), isTrue);
      expect(CfCookieHelper.isBypassProofCookie('cf_clearance'), isTrue);
      expect(
        CfCookieHelper.isManagedProtectionCookie('cf_clearance'),
        isTrue,
      );
      expect(CfCookieHelper.isBypassCookie('cf_clearance'), isTrue);

      expect(CfCookieHelper.isDdosGuardCookie('__ddg1'), isTrue);
      expect(CfCookieHelper.isBypassProofCookie('__ddg1'), isTrue);
      expect(CfCookieHelper.isManagedProtectionCookie('__ddg1'), isTrue);
      expect(CfCookieHelper.isBypassCookie('__ddg1'), isTrue);
    });
  });

  group('CfDetector.detect', () {
    test('classifies Cloudflare 1020 access denied pages as blocked', () {
      final result = CfDetector.detect(
        const CfDetectionRequest(
          url: 'https://example.com/protected',
          statusCode: 403,
          body: '''
            <html>
              <title>Access denied</title>
              <body>
                <h1>Access denied</h1>
                <span>Cloudflare Ray ID: abc</span>
                <span>cf-error-code: 1020</span>
              </body>
            </html>
          ''',
        ),
      );

      expect(result.kind, CfProtectionKind.blocked);
      expect(result.exception, isA<CfBlockedException>());
      expect(
        result.matchedIndicators,
        contains('cloudflare-blocked-headline'),
      );
    });

    test('does not classify generic access denied pages as blocked', () {
      final result = CfDetector.detect(
        const CfDetectionRequest(
          url: 'https://example.com/protected',
          statusCode: 403,
          body: '<html><h1>Access denied</h1></html>',
        ),
      );

      expect(result.kind, CfProtectionKind.none);
    });
  });
}
