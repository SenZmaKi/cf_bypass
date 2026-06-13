import 'cf_exception.dart';
import 'cf_cookie_helper.dart';
import 'cf_browser_cookie.dart';

/// The result of a [CfWebView] bypass operation.
///
/// Inspect [success] first, then use [cookies], [userAgent], and
/// [cfClearanceCookie] to wire the solved browser session into your own HTTP
/// client.
///
/// ```dart
/// CfWebView(
///   url: 'https://example.com',
///   onSuccess: (result) async {
///     if (result.success) {
///       print(result.userAgent);
///       print(result.cfClearanceCookie);
///     }
///     return replayOriginalRequest(result);
///   },
/// )
/// ```
class CfBypassResult {
  /// `true` if the bypass completed successfully and usable cookies were
  /// obtained; `false` if the bypass timed out or encountered an error.
  final bool success;

  /// The original URL that was passed to [CfWebView].
  final String url;

  /// The last URL the WebView navigated to, which may differ from [url] after
  /// redirects.
  final String? finalUrl;

  /// Human-readable error message when [success] is `false`.
  final String? error;

  /// Typed exception that caused the failure, when available.
  final CfException? exception;

  /// Value of the `cf_clearance` cookie, or `null` if not present.
  final String? cfClearanceCookie;

  /// Value of the primary DDoS-Guard cookie (`__ddg1`), or `null` if not present.
  final String? ddosCookie;

  /// The browser user-agent string captured from the WebView after the
  /// challenge was solved.
  final String? userAgent;

  /// All cookies present in the WebView at the time the bypass succeeded.
  final List<CfBrowserCookie> cookies;

  /// How long the bypass took from start to completion.
  final Duration? duration;

  /// Number of page-load cycles that occurred before the challenge was solved.
  final int attempts;

  const CfBypassResult({
    required this.success,
    required this.url,
    this.finalUrl,
    this.error,
    this.exception,
    this.cfClearanceCookie,
    this.ddosCookie,
    this.userAgent,
    this.cookies = const [],
    this.duration,
    this.attempts = 1,
  });

  /// Creates a successful [CfBypassResult] from raw cookie and user-agent data.
  ///
  /// Automatically extracts [cfClearanceCookie] and [ddosCookie] from
  /// [cookies]. Throws [ArgumentError] when [userAgent] is empty or [cookies]
  /// does not contain a `cf_clearance` or `__ddg*` cookie.
  factory CfBypassResult.success({
    required String url,
    String? finalUrl,
    required String userAgent,
    List<CfBrowserCookie> cookies = const [],
    Duration? duration,
    int attempts = 1,
  }) {
    if (userAgent.isEmpty) {
      throw ArgumentError.value(
        userAgent,
        'userAgent',
        'Successful bypass results require a non-empty user-agent.',
      );
    }
    if (CfCookieHelper.getBypassFingerprint(cookies) == null) {
      throw ArgumentError.value(
        cookies,
        'cookies',
        'Successful bypass results require a cf_clearance or __ddg* cookie.',
      );
    }
    return CfBypassResult(
      success: true,
      url: url,
      finalUrl: finalUrl,
      cfClearanceCookie: CfCookieHelper.getCfClearanceCookie(cookies),
      ddosCookie: CfCookieHelper.getDdosCookie(cookies),
      userAgent: userAgent,
      cookies: cookies,
      duration: duration,
      attempts: attempts,
    );
  }

  /// Creates a failed [CfBypassResult] with an [error] message and optional
  /// typed [exception].
  factory CfBypassResult.failure({
    required String url,
    required String error,
    String? finalUrl,
    CfException? exception,
    String? userAgent,
    List<CfBrowserCookie> cookies = const [],
    Duration? duration,
    int attempts = 1,
  }) {
    return CfBypassResult(
      success: false,
      url: url,
      finalUrl: finalUrl,
      error: error,
      exception: exception,
      cfClearanceCookie: CfCookieHelper.getCfClearanceCookie(cookies),
      ddosCookie: CfCookieHelper.getDdosCookie(cookies),
      userAgent: userAgent,
      cookies: cookies,
      duration: duration,
      attempts: attempts,
    );
  }

  /// Creates a failed [CfBypassResult] that represents a timeout.
  factory CfBypassResult.timeout({
    required String url,
    required Duration timeout,
    String? finalUrl,
    CfException? exception,
    int attempts = 1,
  }) {
    return CfBypassResult.failure(
      url: url,
      finalUrl: finalUrl,
      error: 'Bypass timed out after ${timeout.inSeconds}s',
      exception: exception,
      duration: timeout,
      attempts: attempts,
    );
  }

  @override
  String toString() =>
      'CfBypassResult(success: $success, url: $url, cookies: ${cookies.length})';
}
