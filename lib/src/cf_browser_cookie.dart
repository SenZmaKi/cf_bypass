/// A serializable cookie model for passing cookies into and out of the WebView solver.
///
/// Create instances to seed the WebView with pre-existing session cookies via
/// [CfWebView.initialCookies], and read the cookies back from
/// [CfBypassResult.cookies] once the bypass succeeds.
///
/// ```dart
/// const cookie = CfBrowserCookie(
///   name: 'session',
///   value: 'abc123',
///   domain: 'example.com',
/// );
/// ```
class CfBrowserCookie {
  /// The cookie name (e.g. `cf_clearance`, `session`).
  final String name;

  /// The raw cookie value.
  final String value;

  /// The domain the cookie is scoped to (e.g. `example.com`).
  final String domain;

  /// The path the cookie is scoped to. Defaults to `'/'`.
  final String path;

  /// Whether the cookie must only be sent over HTTPS.
  final bool? isSecure;

  /// Whether the cookie is inaccessible to JavaScript (`HttpOnly`).
  final bool? isHttpOnly;

  /// Optional expiry date. `null` means a session cookie.
  final DateTime? expires;

  const CfBrowserCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.isSecure,
    this.isHttpOnly,
    this.expires,
  });

  /// Returns the cookie in `name=value` format suitable for a `Cookie` header.
  String toCookieString() => '$name=$value';

  @override
  String toString() =>
      'BrowserCookie($name=$value, domain: $domain, path: $path)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CfBrowserCookie &&
        other.name == name &&
        other.domain == domain &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(name, domain, path);
}
