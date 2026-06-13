import 'cf_exception.dart';

/// Describes the kind of CloudFlare protection detected on a response.
enum CfProtectionKind {
  /// No CloudFlare protection detected.
  none,

  /// A solvable challenge page was detected (JavaScript challenge, Turnstile,
  /// or DDoS-Guard check).
  challenge,

  /// The request was hard-blocked by CloudFlare (access denied, firewall rule).
  blocked,
}

/// The input data from your HTTP client that [CfDetector.detect] inspects.
///
/// Populate this from whatever HTTP library you use before passing it to
/// [CfDetector.detect].
///
/// ```dart
/// final request = CfDetectionRequest(
///   url: 'https://example.com/page',
///   statusCode: 403,
///   body: responseBody,
///   headers: responseHeaders,
/// );
/// ```
class CfDetectionRequest {
  /// The URL that produced this response.
  final String url;

  /// HTTP status code of the response (e.g. `403`, `503`).
  final int statusCode;

  /// Raw response body. Detection relies on HTML marker strings found here.
  final String? body;

  /// Response headers. Currently used for context; reserved for future
  /// header-based indicators.
  final Map<String, String> headers;

  /// Optional label for the request source (e.g. `'dio'`, `'http'`).
  /// Stored on any thrown exception for debugging.
  final String? source;

  const CfDetectionRequest({
    required this.url,
    required this.statusCode,
    this.body,
    this.headers = const {},
    this.source,
  });
}

/// Result of a [CfDetector.detect] call.
///
/// Check [isProtected] first. If true, [kind] tells you whether it is a
/// solvable [CfProtectionKind.challenge] or a hard [CfProtectionKind.blocked].
/// The [exception] field provides a typed exception ready to be thrown or
/// logged.
///
/// ```dart
/// final result = CfDetector.detect(request);
/// if (result.isProtected) {
///   print(result.kind);           // CfProtectionKind.challenge
///   print(result.matchedIndicators); // ['challenge-form', 'cf-turnstile']
///   throw result.exception!;
/// }
/// ```
class CfDetectionResult {
  /// The URL that was inspected.
  final String url;

  /// HTTP status code of the inspected response.
  final int statusCode;

  /// The kind of protection detected, or [CfProtectionKind.none].
  final CfProtectionKind kind;

  /// A typed exception describing the protection, or `null` when
  /// [isProtected] is `false`.
  final CfException? exception;

  /// The individual HTML/header markers that matched during detection.
  /// Empty when [isProtected] is `false`.
  final List<String> matchedIndicators;

  const CfDetectionResult({
    required this.url,
    required this.statusCode,
    required this.kind,
    this.exception,
    this.matchedIndicators = const [],
  });

  /// `true` when any CloudFlare or DDoS-Guard protection was detected.
  bool get isProtected => kind != CfProtectionKind.none;
}

/// Inspects caller-supplied HTTP response data for CloudFlare protection.
///
/// This class is purely static and performs no network I/O. Feed it the
/// response data from your own HTTP client and it will classify the response.
///
/// ```dart
/// final result = CfDetector.detect(
///   CfDetectionRequest(
///     url: 'https://example.com/protected',
///     statusCode: 403,
///     body: responseHtml,
///   ),
/// );
///
/// if (result.isProtected) {
///   // Launch CfWebView to solve, or handle the block.
/// }
/// ```
class CfDetector {
  CfDetector._();

  static const int _httpForbidden = 403;
  static const int _httpUnavailable = 503;

  /// Inspects [request] and returns a [CfDetectionResult] classifying the
  /// response as [CfProtectionKind.none], [CfProtectionKind.challenge], or
  /// [CfProtectionKind.blocked].
  ///
  /// Detection only triggers on HTTP `403` and `503` responses. A non-empty
  /// [CfDetectionRequest.body] is required; without it the result is always
  /// [CfProtectionKind.none].
  static CfDetectionResult detect(CfDetectionRequest request) {
    if (request.statusCode != _httpForbidden &&
        request.statusCode != _httpUnavailable) {
      return CfDetectionResult(
        url: request.url,
        statusCode: request.statusCode,
        kind: CfProtectionKind.none,
      );
    }

    final body = request.body ?? '';
    if (body.isEmpty) {
      return CfDetectionResult(
        url: request.url,
        statusCode: request.statusCode,
        kind: CfProtectionKind.none,
      );
    }

    final lowerBody = body.toLowerCase();
    final indicators = <String>[];

    if (lowerBody.contains('ddos-guard') ||
        lowerBody.contains('/.well-known/ddos-guard/') ||
        lowerBody.contains('check.ddos-guard.net')) {
      indicators.add('ddos-guard-marker');
    }

    final hasCloudflareContext = lowerBody.contains('cloudflare') ||
        lowerBody.contains('cdn-cgi') ||
        lowerBody.contains('cf-ray') ||
        lowerBody.contains('cf-error') ||
        lowerBody.contains('challenges.cloudflare.com');

    if (lowerBody.contains('data-translate="blocked_why_headline"') ||
        lowerBody.contains('cf-error-code: 1020') ||
        lowerBody.contains('error code: 1020') ||
        (hasCloudflareContext &&
            (lowerBody.contains('access denied') ||
                lowerBody.contains('you have been blocked')))) {
      indicators.add('cloudflare-blocked-headline');
    }

    if (body.contains('id="challenge-error-title"')) {
      indicators.add('challenge-error-title');
    }
    if (body.contains('id="challenge-error-text"')) {
      indicators.add('challenge-error-text');
    }
    if (body.contains('id="challenge-form"')) {
      indicators.add('challenge-form');
    }
    if (body.contains('class="cf-turnstile"')) {
      indicators.add('cf-turnstile');
    }
    if (body.contains('Just a moment') && body.contains('Enable JavaScript')) {
      indicators.add('javascript-challenge');
    }
    if (body.contains('challenges.cloudflare.com') ||
        body.contains('cdn-cgi/challenge-platform')) {
      indicators.add('challenge-platform');
    }

    if (indicators.contains('cloudflare-blocked-headline')) {
      return CfDetectionResult(
        url: request.url,
        statusCode: request.statusCode,
        kind: CfProtectionKind.blocked,
        exception: CfBlockedException(
          url: request.url,
          statusCode: request.statusCode,
          source: request.source,
          headers: request.headers,
          responseBody: body,
          indicators: indicators,
        ),
        matchedIndicators: indicators,
      );
    }

    if (indicators.isNotEmpty) {
      return CfDetectionResult(
        url: request.url,
        statusCode: request.statusCode,
        kind: CfProtectionKind.challenge,
        exception: CfProtectedException(
          url: request.url,
          statusCode: request.statusCode,
          source: request.source,
          headers: request.headers,
          responseBody: body,
          indicators: indicators,
        ),
        matchedIndicators: indicators,
      );
    }

    return CfDetectionResult(
      url: request.url,
      statusCode: request.statusCode,
      kind: CfProtectionKind.none,
    );
  }
}
