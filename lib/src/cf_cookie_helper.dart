import 'cf_browser_cookie.dart';

/// Utility helpers for identifying and extracting CloudFlare and DDoS-Guard
/// cookies from a [CfBrowserCookie] list.
///
/// All methods are static; this class cannot be instantiated.
class CfCookieHelper {
  CfCookieHelper._();

  static const String _cfClearanceName = 'cf_clearance';
  static const String _ddosGuardPrefix = '__ddg';

  /// Returns `true` if [name] is a CloudFlare-managed cookie
  /// (prefixed with `cf_`, `_cf`, or `__cf`).
  static bool isCloudflareManagedCookie(String name) {
    return name.startsWith('cf_') ||
        name.startsWith('_cf') ||
        name.startsWith('__cf');
  }

  /// Deprecated spelling kept for compatibility.
  static bool isCloudFlareCookie(String name) {
    return isCloudflareManagedCookie(name);
  }

  /// Returns `true` if [name] is a DDoS-Guard cookie (prefixed with `__ddg`).
  static bool isDdosGuardCookie(String name) {
    return name.toLowerCase().startsWith(_ddosGuardPrefix);
  }

  /// Returns `true` if [name] proves a solved bypass for this package.
  static bool isBypassProofCookie(String name) {
    return name == _cfClearanceName || isDdosGuardCookie(name);
  }

  /// Returns `true` if [name] is managed by CloudFlare or DDoS-Guard.
  ///
  /// This broad helper identifies ownership, not proof that a bypass succeeded.
  static bool isManagedProtectionCookie(String name) {
    return isCloudflareManagedCookie(name) || isDdosGuardCookie(name);
  }

  /// Ambiguous legacy name kept for compatibility.
  static bool isBypassCookie(String name) {
    return isManagedProtectionCookie(name);
  }

  /// Returns the value of the `cf_clearance` cookie, or null if absent.
  static String? getCfClearanceCookie(Iterable<CfBrowserCookie> cookies) {
    for (final cookie in cookies) {
      if (cookie.name == _cfClearanceName) return cookie.value;
    }
    return null;
  }

  /// Returns the value of the primary DDoS-Guard cookie (`__ddg1`),
  /// or the first `__ddg*` cookie found, or null if none are present.
  static String? getDdosCookie(Iterable<CfBrowserCookie> cookies) {
    String? fallback;
    for (final cookie in cookies) {
      if (!isDdosGuardCookie(cookie.name)) continue;
      if (cookie.name.toLowerCase() == '__ddg1') return cookie.value;
      fallback ??= cookie.value;
    }
    return fallback;
  }

  /// Composite fingerprint used internally for stall detection.
  /// Returns a stable string combining CF clearance and DDoS tokens,
  /// or null if neither is present.
  static String? getBypassFingerprint(Iterable<CfBrowserCookie> cookies) {
    final cf = getCfClearanceCookie(cookies);
    final ddos = getDdosCookie(cookies);
    if (cf == null && ddos == null) return null;
    return 'cf=${cf ?? ''};ddg=${ddos ?? ''}';
  }

  /// Formats [cookies] into a single `Cookie` header value (`name=value` pairs
  /// joined by `'; '`).
  static String cookiesToHeader(Iterable<CfBrowserCookie> cookies) {
    return cookies.map((cookie) => cookie.toCookieString()).join('; ');
  }
}
