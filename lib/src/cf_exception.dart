/// Base class for all exceptions thrown by the `cf_bypass` package.
///
/// Subclasses carry the URL, status code, matched indicators, and raw response
/// body so callers have full context when catching errors.
abstract class CfException implements Exception {
  /// The URL associated with this exception.
  final String url;

  /// HTTP status code of the response that triggered this exception, if known.
  final int? statusCode;

  /// Optional label for the HTTP client that made the request.
  final String? source;

  /// Human-readable description of what went wrong.
  final String message;

  /// Response headers at the time the exception was created.
  final Map<String, String> headers;

  /// Raw response body at the time the exception was created.
  final String? responseBody;

  /// HTML/header markers that were matched during detection.
  final List<String> indicators;

  const CfException({
    required this.url,
    required this.message,
    this.statusCode,
    this.source,
    this.headers = const {},
    this.responseBody,
    this.indicators = const [],
  });

  @override
  String toString() => '$runtimeType(message: $message, url: $url)';
}

/// Thrown when a CloudFlare challenge page is detected.
///
/// The challenge is potentially solvable via [CfWebView]. Use
/// [CfDetectionResult.kind] == [CfProtectionKind.challenge] to detect this
/// without throwing.
class CfProtectedException extends CfException {
  const CfProtectedException({
    required super.url,
    super.statusCode,
    super.source,
    super.headers,
    super.responseBody,
    super.indicators,
  }) : super(
          message: 'Protected by CloudFlare - challenge required',
        );
}

/// Thrown when a CloudFlare hard-block page is detected.
///
/// Hard blocks cannot be solved by a WebView challenge; they usually indicate
/// an IP or geographic ban. Use [CfDetectionResult.kind] ==
/// [CfProtectionKind.blocked] to detect this without throwing.
class CfBlockedException extends CfException {
  const CfBlockedException({
    required super.url,
    super.statusCode,
    super.source,
    super.headers,
    super.responseBody,
    super.indicators,
  }) : super(
          message: 'Blocked by CloudFlare',
        );
}

/// Thrown when the WebView solver encounters an unrecoverable error.
///
/// The [error] field holds the original exception, if any.
class CfBypassFailedException extends CfException {
  /// The underlying error that caused the bypass to fail, if available.
  final Object? error;

  const CfBypassFailedException({
    required super.url,
    super.statusCode,
    super.source,
    super.headers,
    super.responseBody,
    super.indicators,
    this.error,
    String? message,
  }) : super(
          message: message ?? 'Failed to bypass CloudFlare protection',
        );
}

/// Thrown when the [CfWebView] solver exceeds its [CfWebView.timeout].
class CfTimeoutException extends CfException {
  /// The timeout duration that was exceeded.
  final Duration timeout;

  const CfTimeoutException({
    required super.url,
    required this.timeout,
    super.statusCode,
    super.source,
    super.headers,
    super.responseBody,
    super.indicators,
  }) : super(
          message: 'CloudFlare bypass timed out',
        );
}
