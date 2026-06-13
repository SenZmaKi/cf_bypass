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
}
