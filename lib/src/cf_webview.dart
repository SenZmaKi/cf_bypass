import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logging/logging.dart';

import 'cf_browser_cookie.dart';
import 'cf_bypass_result.dart';
import 'cf_exception.dart';
import 'cf_cookie_helper.dart';

/// Allows programmatic control of a running [CfWebView].
///
/// Pass an instance to [CfWebView.controller] and keep a reference in your
/// widget state. Call [retry] when [CfWebView.onLoopDetected] fires, or
/// [cancel] to abort the session at any time.
///
/// ```dart
/// final _controller = CfBypassController();
///
/// CfWebView(
///   url: 'https://example.com',
///   controller: _controller,
///   onLoopDetected: () => _controller.retry(),
/// )
/// ```
class CfBypassController {
  _CfWebViewState? _state;

  void _attach(_CfWebViewState state) => _state = state;
  void _detach() => _state = null;

  /// Clears CloudFlare cookies and reloads the page to retry the bypass.
  Future<void> retry() async => _state?._retry();

  /// Cancels the bypass session and fires [CfWebView.onCancelled].
  void cancel() => _state?._cancel();
}

/// A widget that renders an [InAppWebView] and encapsulates CloudFlare
/// challenge-solving logic.
///
/// Embed [CfWebView] in a full-screen route or a dialog when [CfDetector]
/// reports a solvable challenge. The widget handles cookie seeding, challenge
/// polling, stall detection, and timeout automatically.
///
/// When the challenge is solved, [onSuccess] is called with a [CfBypassResult]
/// containing the cookies and user-agent you need to replay the original
/// request with your own HTTP client.
///
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => CfWebView(
///       url: 'https://example.com/protected',
///       onSuccess: (result) {
///         // Wire result.cookies and result.userAgent into your HTTP client.
///       },
///     ),
///   ),
/// );
/// ```
class CfWebView extends StatefulWidget {
  /// The URL to load and solve the challenge for.
  final String url;

  /// Cookies to inject into the WebView before the first load.
  final List<CfBrowserCookie> initialCookies;

  /// Optional custom user-agent string to use for the WebView session.
  /// Ill-advised to set this since Cloudflare compares passed user agent to
  /// the one it detects in the browser fingerprint.
  final String? userAgent;

  /// How long to wait for a successful bypass before calling [onFailure].
  /// Defaults to 2 minutes.
  final Duration timeout;

  /// Optional controller for external retry/cancel control.
  final CfBypassController? controller;

  /// Number of page-load cycles without a cookie change before
  /// [onLoopDetected] is fired. Defaults to `3`.
  final int stallThreshold;

  /// When `true`, ALL cookies (not just Cloudflare ones) and the HTTP cache
  /// are wiped before each bypass run and each retry. This forces Cloudflare
  /// to see a completely fresh browser fingerprint and always run a full
  /// challenge. Defaults to `false`.
  ///
  /// Set this when you need a distinct `cf_clearance` on every invocation.
  /// If `false`, Cloudflare may re-issue the same token immediately for a
  /// fingerprint it already trusts.
  final bool clearAllDataOnInit;

  /// When `true` (default), Cloudflare-specific cookies (`cf_clearance`,
  /// `__ddg*`, etc.) are deleted before each bypass run and each retry.
  /// This prevents a stale clearance from a previous run being detected as a
  /// fresh bypass.
  ///
  /// Only meaningful when [clearAllDataOnInit] is `false`; if
  /// [clearAllDataOnInit] is `true` all cookies are wiped regardless.
  final bool clearCfCookiesOnInit;

  /// Called once the challenge is solved and cookies are ready.
  final void Function(CfBypassResult result)? onSuccess;

  /// Called when the bypass cannot be completed (timeout, error).
  final void Function(CfBypassResult result)? onFailure;

  /// Called when [CfBypassController.cancel] is invoked.
  final VoidCallback? onCancelled;

  /// Called each time a page finishes loading inside the WebView.
  final void Function(String? url)? onPageFinishedLoading;

  /// Called each time a page starts loading inside the WebView.
  final void Function(String? url)? onPageStartedLoading;

  /// Called when repeated page reloads are detected without a solved challenge.
  final VoidCallback? onLoopDetected;

  /// Called when the page title changes.
  final void Function(String title)? onTitleChanged;

  /// Called when an error occurs in the WebView.
  final void Function(Object error)? onError;

  const CfWebView({
    super.key,
    required this.url,
    this.initialCookies = const [],
    this.stallThreshold = 3,
    this.userAgent,
    this.timeout = const Duration(minutes: 2),
    this.controller,
    this.clearAllDataOnInit = false,
    this.clearCfCookiesOnInit = true,
    this.onSuccess,
    this.onFailure,
    this.onCancelled,
    this.onPageFinishedLoading,
    this.onPageStartedLoading,
    this.onLoopDetected,
    this.onTitleChanged,
    this.onError,
  });

  @override
  State<CfWebView> createState() => _CfWebViewState();
}

class _CfWebViewState extends State<CfWebView> {
  static final _log = Logger('CfWebView');

  final CookieManager _cookieManager = CookieManager.instance();

  InAppWebViewController? _webController;
  String? _oldBypassFingerprint;
  String? _lastStartedUrl;
  String? _lastFinishedUrl;
  String? _resolvedUserAgent;
  int _loopCounter = 0;
  bool _checkPassed = false;
  bool _loopDetectedFired = false;
  Timer? _checkTimer;
  Timer? _timeoutTimer;
  late DateTime _startedAt;
  bool _ready = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    widget.controller?._attach(this);
    _initialize();
  }

  @override
  void didUpdateWidget(CfWebView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._detach();
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _checkTimer?.cancel();
    _timeoutTimer?.cancel();
    widget.controller?._detach();
    super.dispose();
  }

  Future<void> _initialize() async {
    _log.fine(
        '▶ init  url=${widget.url}  timeout=${widget.timeout.inSeconds}s  '
        'stallThreshold=${widget.stallThreshold}  clearAllData=${widget.clearAllDataOnInit}  '
        'clearCfCookies=${widget.clearCfCookiesOnInit}');
    if (widget.clearAllDataOnInit) {
      await _clearAllData();
    } else if (widget.clearCfCookiesOnInit) {
      await _clearCfCookies();
    }
    await _initWebViewCookies();

    // Record the actual post-clear WebView fingerprint. If targeted cookie
    // deletion misses a scoped cookie, do not treat it as a fresh solve.
    _oldBypassFingerprint = await _getBypassFingerprint();
    _log.fine('🔎 seed fingerprint=${_oldBypassFingerprint ?? '(none)'}');

    _resolvedUserAgent = null;
    _timeoutTimer = Timer(widget.timeout, _onTimeout);

    if (mounted) setState(() => _ready = true);
  }

  void _onTimeout() {
    if (_disposed || _checkPassed) return;
    _log.warning('⏰ timeout after ${widget.timeout.inSeconds}s');
    widget.onFailure?.call(
      CfBypassResult.timeout(
        url: widget.url,
        timeout: widget.timeout,
        finalUrl: _lastStartedUrl,
        exception: CfTimeoutException(url: widget.url, timeout: widget.timeout),
        attempts: _loopCounter + 1,
      ),
    );
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        cacheEnabled: true,
        userAgent: widget.userAgent,
        thirdPartyCookiesEnabled: true,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
      );

  void _onPageStartedLoading(WebUri? url) {
    _log.fine('→ loading  ${url ?? '(null)'}');
    _lastStartedUrl = url?.toString();
    widget.onPageStartedLoading?.call(url?.toString());
  }

  void _onPageFinishedLoading(WebUri? url) {
    _log.fine('✓ finished  ${url ?? '(null)'}');
    _lastFinishedUrl = url?.toString();
    widget.onPageFinishedLoading?.call(url?.toString());
    _scheduleCheck();
  }

  void _onLoadError(WebResourceRequest request, WebResourceError error) {
    _log.warning(
        '⚠ webview error  url=${request.url}  desc=${error.description}');
    widget.onError?.call(error);
  }

  void _scheduleCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer(const Duration(milliseconds: 1000), _checkClearance);
  }

  Future<void> _checkClearance() async {
    if (_disposed || _checkPassed) return;

    final fingerprint = await _getBypassFingerprint();
    _log.fine(
        '🔍 check  fingerprint=${fingerprint ?? '(none)'}  old=${_oldBypassFingerprint ?? '(none)'}  loop=$_loopCounter');

    if (fingerprint != null && fingerprint != _oldBypassFingerprint) {
      _checkPassed = true;
      _timeoutTimer?.cancel();
      await _captureUserAgent();
      final cookies = await _exportCookies();
      final elapsed = DateTime.now().difference(_startedAt);
      _log.info(
          '✅ bypass!  cookies=${cookies.length}  duration=${elapsed.inMilliseconds}ms  ua=${_resolvedUserAgent ?? '(none)'}');
      widget.onSuccess?.call(
        CfBypassResult.success(
          url: widget.url,
          finalUrl: _lastFinishedUrl,
          userAgent: _resolvedUserAgent ?? widget.userAgent,
          cookies: cookies,
          duration: elapsed,
          attempts: _loopCounter + 1,
        ),
      );
    } else {
      _loopCounter++;
      _log.fine(
          '⏳ stall  loop=$_loopCounter / stallThreshold=${widget.stallThreshold}');
      if (_loopCounter >= widget.stallThreshold && !_loopDetectedFired) {
        _loopDetectedFired = true;
        _log.warning('🔁 loop detected — firing onLoopDetected');
        widget.onLoopDetected?.call();
      }
    }
  }

  Future<void> _retry() async {
    if (_disposed) return;
    _log.info('🔄 retry  clearing loop state');
    _loopCounter = 0;
    _checkPassed = false;
    _loopDetectedFired = false;
    _checkTimer?.cancel();
    if (widget.clearAllDataOnInit) {
      await _clearAllData();
    } else if (widget.clearCfCookiesOnInit) {
      await _clearCfCookies();
    }
    await _initWebViewCookies();
    _oldBypassFingerprint = await _getBypassFingerprint();
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.url)),
    );
  }

  void _cancel() {
    if (_disposed || _checkPassed) return;
    _log.info('✖ cancelled');
    _checkTimer?.cancel();
    _timeoutTimer?.cancel();
    widget.onCancelled?.call();
  }

  Future<String?> _getBypassFingerprint() async {
    try {
      final cookies = await _cookieManager.getCookies(url: WebUri(widget.url));
      final cfCookies = cookies
          .map((c) => CfBrowserCookie(
              name: c.name, value: c.value, domain: c.domain ?? ''))
          .toList();
      return CfCookieHelper.getBypassFingerprint(cfCookies);
    } catch (e) {
      _log.warning('⚠ error reading bypass fingerprint', e);
      return null;
    }
  }

  Future<void> _initWebViewCookies() async {
    final webUri = WebUri(widget.url);
    _log.fine('🍪 seeding ${widget.initialCookies.length} initial cookie(s)');
    for (final cookie in widget.initialCookies) {
      await _cookieManager.setCookie(
        url: webUri,
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
        isSecure: cookie.isSecure,
        isHttpOnly: cookie.isHttpOnly,
      );
    }
  }

  Future<void> _clearCfCookies() async {
    try {
      final webUri = WebUri(widget.url);
      final cookies = await _cookieManager.getCookies(url: webUri);
      final cfCookies =
          cookies.where((c) => CfCookieHelper.isBypassCookie(c.name)).toList();
      _log.fine('🍪 clearing ${cfCookies.length} CF cookie(s)');
      for (final cookie in cfCookies) {
        await _cookieManager.deleteCookie(
          url: webUri,
          name: cookie.name,
          domain: cookie.domain,
          path: cookie.path ?? '/',
        );
      }
    } catch (e) {
      _log.warning('⚠ error clearing CF cookies', e);
    }
  }

  /// Wipes ALL cookies and the HTTP cache so CF sees a completely fresh
  /// browser fingerprint. Used when [CfWebView.clearAllDataOnInit] is `true`.
  Future<void> _clearAllData() async {
    try {
      _log.fine('🗑 clearAllData — deleting all cookies + cache');
      await _cookieManager.deleteAllCookies();
    } catch (e) {
      _log.warning('⚠ error deleting all cookies', e);
    }
    try {
      await InAppWebViewController.clearAllCache();
      _log.fine('🗑 HTTP cache cleared');
    } catch (e) {
      _log.warning('⚠ error clearing cache', e);
    }
  }

  Future<void> _captureUserAgent() async {
    if (_webController == null) return;
    try {
      final value = await _webController!
          .evaluateJavascript(source: 'navigator.userAgent');
      if (value is String && value.isNotEmpty) {
        _resolvedUserAgent = value;
      } else if (value != null) {
        _resolvedUserAgent = value.toString();
      }
      _log.fine('🌐 user-agent=${_resolvedUserAgent ?? '(none)'}');
    } catch (e) {
      _log.warning('⚠ error reading user-agent', e);
    }
  }

  Future<List<CfBrowserCookie>> _exportCookies() async {
    final uri = Uri.parse(widget.url);
    final webCookies = await _cookieManager.getCookies(url: WebUri(widget.url));
    return webCookies
        .map((wc) => CfBrowserCookie(
              name: wc.name,
              value: wc.value,
              domain: wc.domain ?? uri.host,
              path: wc.path ?? '/',
              isSecure: wc.isSecure,
              isHttpOnly: wc.isHttpOnly,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: _settings,
      onWebViewCreated: (controller) => _webController = controller,
      onLoadStart: (controller, url) => _onPageStartedLoading(url),
      onLoadStop: (controller, url) => _onPageFinishedLoading(url),
      onReceivedError: (controller, request, error) =>
          _onLoadError(request, error),
      onTitleChanged: (controller, title) {
        if (title != null && !_disposed) {
          widget.onTitleChanged?.call(title);
        }
      },
    );
  }
}
