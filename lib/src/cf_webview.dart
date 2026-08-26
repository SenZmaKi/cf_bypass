import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logging/logging.dart';

import 'cf_browser_cookie.dart';
import 'cf_bypass_result.dart';
import 'cf_exception.dart';
import 'cf_cookie_helper.dart';

/// Handles a WebView load error and decides whether [CfWebView] should retry.
///
/// Return `true` to clear configured cookies and reload [CfWebView.url].
/// Return `false` to keep the current session running until it succeeds,
/// times out, is cancelled, or is retried manually.
typedef CfWebViewErrorCallback = FutureOr<bool> Function(Object error);

/// The outcome of validating a candidate bypass result.
enum CfWebViewSuccessDecision {
  /// The candidate is valid and the bypass is complete.
  accept,

  /// The candidate is invalid, but the WebView should clear its state and try
  /// the challenge again.
  retry,

  /// The candidate is invalid and the caller has handled the terminal failure.
  reject,
}

/// Validates a candidate bypass result before [CfWebView] reports completion.
///
/// Return [CfWebViewSuccessDecision.accept] once your app has verified the
/// captured cookies and user-agent can access the protected resource. Return
/// [CfWebViewSuccessDecision.retry] to clear configured cookies and retry the
/// challenge. Return [CfWebViewSuccessDecision.reject] when validation has
/// failed terminally and the caller has handled that failure. Throwing from the
/// callback reports a failed bypass through [CfWebView.onFailure].
typedef CfWebViewSuccessCallback = FutureOr<CfWebViewSuccessDecision> Function(
    CfBypassResult result);

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
/// When bypass-looking cookies are captured, [onSuccess] is called with a
/// [CfBypassResult] containing the cookies and user-agent. Return an explicit
/// [CfWebViewSuccessDecision] after verifying whether those artifacts can
/// replay the protected request.
///
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => CfWebView(
///       url: 'https://example.com/protected',
///       onSuccess: (result) async {
///         final verified = await replayOriginalRequest(result);
///         if (!verified) return CfWebViewSuccessDecision.retry;
///         Navigator.pop(context, result);
///         return CfWebViewSuccessDecision.accept;
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

  /// Required validator called once bypass-looking cookies are captured.
  ///
  /// Return [CfWebViewSuccessDecision.accept] only after validating the result
  /// against your protected resource. Return
  /// [CfWebViewSuccessDecision.retry] to retry the bypass, or
  /// [CfWebViewSuccessDecision.reject] when the caller has handled a terminal
  /// validation failure. Throwing from this callback reports a failed bypass
  /// through [onFailure].
  final CfWebViewSuccessCallback onSuccess;

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

  /// Called after a main-frame WebView load error.
  ///
  /// This is useful for app-specific network handling. For example, callers
  /// can inspect the platform WebView error and retry only for offline, DNS,
  /// or timeout failures. Subresource errors are ignored by this retry hook.
  ///
  /// Return `true` to clear configured cookies and reload [url]. Return
  /// `false` to keep waiting for a successful solve, manual retry, cancel, or
  /// timeout.
  final CfWebViewErrorCallback? onError;

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
    required this.onSuccess,
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
  static Future<WebViewEnvironment>? _windowsEnvironment;

  late final CookieManager _cookieManager;
  final Set<String> _rejectedBypassFingerprints = {};
  final Set<String> _visitedUrls = {};

  WebViewEnvironment? _webViewEnvironment;
  InAppWebViewController? _webController;
  String? _oldBypassFingerprint;
  String? _lastStartedUrl;
  String? _lastFinishedUrl;
  String? _lastNavigatedUrl;
  String? _resolvedUserAgent;
  int _loopCounter = 0;
  bool _loopDetectedFired = false;
  Timer? _checkTimer;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  late DateTime _startedAt;
  int _attemptId = 0;
  bool _ready = false;
  bool _disposed = false;
  bool _completed = false;
  bool _clearanceCheckInProgress = false;
  bool _successValidationInProgress = false;
  bool _errorRetryInProgress = false;
  bool _seedFingerprintValidated = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _recordNavigation(WebUri(widget.url));
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
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    widget.controller?._detach();
    super.dispose();
  }

  Future<void> _initialize() async {
    final attemptId = _beginAttempt();
    _log.fine(
      '▶ init  url=${widget.url}  timeout=${widget.timeout.inSeconds}s  '
      'stallThreshold=${widget.stallThreshold}  clearAllData=${widget.clearAllDataOnInit}  '
      'clearCfCookies=${widget.clearCfCookiesOnInit}',
    );
    await _initializeBrowserEnvironment();
    if (!_isCurrentAttempt(attemptId)) return;
    if (widget.clearAllDataOnInit) {
      await _clearAllData();
    } else if (widget.clearCfCookiesOnInit) {
      await _clearCfCookies();
    }
    await _initWebViewCookies();
    if (!_isCurrentAttempt(attemptId)) return;

    // Record the actual post-clear WebView fingerprint. If targeted cookie
    // deletion misses a scoped cookie, do not treat it as a fresh solve.
    _oldBypassFingerprint = await _getBypassFingerprint();
    if (!_isCurrentAttempt(attemptId)) return;
    _log.fine('🔎 seed bypass cookie present=${_oldBypassFingerprint != null}');

    _resolvedUserAgent = null;
    _startPolling(attemptId);

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _initializeBrowserEnvironment() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      _cookieManager = CookieManager.instance();
      return;
    }

    final environment =
        await (_windowsEnvironment ??= WebViewEnvironment.create());
    _webViewEnvironment = environment;
    _cookieManager = CookieManager.instance(
      webViewEnvironment: environment,
    );
    _log.fine(
      '🪟 Windows WebView and cookie manager bound to environment '
      '${environment.id}',
    );
  }

  int _beginAttempt() {
    final attemptId = ++_attemptId;
    _startedAt = DateTime.now();
    _loopCounter = 0;
    _completed = false;
    _clearanceCheckInProgress = false;
    _successValidationInProgress = false;
    _loopDetectedFired = false;
    _seedFingerprintValidated = false;
    _checkTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(widget.timeout, () => _onTimeout(attemptId));
    return attemptId;
  }

  bool _isCurrentAttempt(int attemptId) {
    return !_disposed && attemptId == _attemptId;
  }

  void _stopAttemptTimers() {
    _checkTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    _timeoutTimer?.cancel();
  }

  void _onTimeout(int attemptId) {
    if (!_isCurrentAttempt(attemptId) || _completed) return;
    _completed = true;
    _stopAttemptTimers();
    _log.warning('⏰ timeout after ${widget.timeout.inSeconds}s');
    widget.onFailure?.call(
      CfBypassResult.timeout(
        url: widget.url,
        timeout: widget.timeout,
        finalUrl: _resolvedFinalUrl,
        exception: CfTimeoutException(url: widget.url, timeout: widget.timeout),
        attempts: _loopCounter + 1,
      ),
    );
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        cacheEnabled: true,
        darkMode: MediaQuery.platformBrightnessOf(context) == Brightness.dark,
        userAgent: widget.userAgent,
        thirdPartyCookiesEnabled: true,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
      );

  void _onPageStartedLoading(WebUri? url) {
    _log.fine('→ loading  ${url ?? '(null)'}');
    _lastStartedUrl = url?.toString();
    _recordNavigation(url);
    _startPolling(_attemptId);
    widget.onPageStartedLoading?.call(url?.toString());
  }

  void _onPageFinishedLoading(WebUri? url) {
    _log.fine('✓ finished  ${url ?? '(null)'}');
    _lastFinishedUrl = url?.toString();
    _recordNavigation(url);
    widget.onPageFinishedLoading?.call(url?.toString());
    _scheduleCheck(_attemptId);
  }

  Future<void> _onLoadError(
    WebResourceRequest request,
    WebResourceError error,
  ) async {
    _log.warning(
      '⚠ webview error  url=${request.url}  desc=${error.description}',
    );

    if (request.isForMainFrame == false ||
        widget.onError == null ||
        _disposed ||
        _completed ||
        _errorRetryInProgress) {
      return;
    }

    _errorRetryInProgress = true;
    try {
      final shouldRetry = await widget.onError!(error);
      if (shouldRetry && !_disposed && !_completed) {
        _log.info('🔄 retry requested after webview error');
        await _retry();
      }
    } catch (e) {
      _log.warning('⚠ error retry callback failed', e);
    } finally {
      _errorRetryInProgress = false;
    }
  }

  void _scheduleCheck(int attemptId) {
    if (!_isCurrentAttempt(attemptId) || _completed) return;
    _checkTimer?.cancel();
    _checkTimer = Timer(
      const Duration(milliseconds: 1000),
      () => _checkClearance(attemptId, countStall: true),
    );
  }

  void _startPolling(int attemptId) {
    if (!_isCurrentAttempt(attemptId) || _completed || _pollTimer != null) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isCurrentAttempt(attemptId) || _completed) {
        timer.cancel();
        if (identical(_pollTimer, timer)) _pollTimer = null;
        return;
      }
      _checkClearance(attemptId, countStall: false);
    });
  }

  Future<void> _checkClearance(
    int attemptId, {
    required bool countStall,
  }) async {
    if (!_isCurrentAttempt(attemptId) ||
        _completed ||
        _clearanceCheckInProgress ||
        _successValidationInProgress) {
      return;
    }

    _clearanceCheckInProgress = true;
    final fingerprint = await _getBypassFingerprint();
    if (!_isCurrentAttempt(attemptId) || _completed) {
      _clearanceCheckInProgress = false;
      return;
    }
    _log.fine(
      '🔍 check  bypassCookiePresent=${fingerprint != null}  '
      'bypassCookieChanged=${fingerprint != null && fingerprint != _oldBypassFingerprint}  '
      'loop=$_loopCounter',
    );

    final isChangedFingerprint =
        fingerprint != null && fingerprint != _oldBypassFingerprint;
    final shouldValidateSeedFingerprint = fingerprint != null &&
        fingerprint == _oldBypassFingerprint &&
        !_seedFingerprintValidated;
    final shouldValidateFingerprint =
        (isChangedFingerprint || shouldValidateSeedFingerprint) &&
            !_rejectedBypassFingerprints.contains(fingerprint);

    if (shouldValidateFingerprint) {
      if (shouldValidateSeedFingerprint) _seedFingerprintValidated = true;
      try {
        await _captureUserAgent();
        if (!_isCurrentAttempt(attemptId) || _completed) return;
        final userAgent = _resolvedUserAgent ?? widget.userAgent;
        if (userAgent == null || userAgent.isEmpty) {
          _fail(
            attemptId,
            'Could not read WebView user-agent',
            CfBypassFailedException(
              url: widget.url,
              message: 'Could not read WebView user-agent',
            ),
          );
          return;
        }
        final cookies = await _exportCookies();
        if (!_isCurrentAttempt(attemptId) || _completed) return;
        final elapsed = DateTime.now().difference(_startedAt);
        final result = CfBypassResult.success(
          url: widget.url,
          finalUrl: _resolvedFinalUrl,
          userAgent: userAgent,
          cookies: cookies,
          duration: elapsed,
          attempts: _loopCounter + 1,
        );
        final candidateKind =
            isChangedFingerprint ? 'changed fingerprint' : 'seed fingerprint';
        _log.info(
          '✅ bypass candidate ($candidateKind)  cookies=${cookies.length}  '
          'duration=${elapsed.inMilliseconds}ms  hasUserAgent=${userAgent.isNotEmpty}',
        );
        await _validateSuccess(result, attemptId);
      } catch (e) {
        _fail(
          attemptId,
          'Could not capture bypass result: $e',
          CfBypassFailedException(
            url: widget.url,
            message: 'Could not capture bypass result',
            error: e,
          ),
        );
      }
    } else if (fingerprint != null &&
        _rejectedBypassFingerprints.contains(fingerprint)) {
      _log.fine('🚫 rejected bypass fingerprint ignored');
      if (countStall) _countRejectedFingerprintStall(attemptId);
    } else if (countStall) {
      _countStall();
    }
    if (_isCurrentAttempt(attemptId) && !_completed) {
      _clearanceCheckInProgress = false;
    }
  }

  void _countStall() {
    _loopCounter++;
    _log.fine(
      '⏳ stall  loop=$_loopCounter / stallThreshold=${widget.stallThreshold}',
    );
    if (_loopCounter >= widget.stallThreshold && !_loopDetectedFired) {
      _loopDetectedFired = true;
      _log.warning('🔁 loop detected — firing onLoopDetected');
      widget.onLoopDetected?.call();
    }
  }

  void _countRejectedFingerprintStall(int attemptId) {
    _loopCounter++;
    _log.fine(
      '⏳ rejected fingerprint stall  loop=$_loopCounter / stallThreshold=${widget.stallThreshold}',
    );
    if (_loopCounter < widget.stallThreshold || _loopDetectedFired) return;
    _loopDetectedFired = true;
    _fail(
      attemptId,
      'Bypass fingerprint was rejected by validation and did not change.',
      CfBypassFailedException(
        url: widget.url,
        message: 'Rejected bypass fingerprint did not change',
      ),
    );
  }

  Future<void> _retry() async {
    if (_disposed) return;
    final attemptId = _beginAttempt();
    _log.info('🔄 retry  clearing loop state');
    if (widget.clearAllDataOnInit) {
      await _clearAllData();
    } else if (widget.clearCfCookiesOnInit) {
      await _clearCfCookies();
    }
    await _initWebViewCookies();
    if (!_isCurrentAttempt(attemptId)) return;
    _oldBypassFingerprint = await _getBypassFingerprint();
    if (!_isCurrentAttempt(attemptId)) return;
    _startPolling(attemptId);
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.url)),
    );
  }

  void _cancel() {
    if (_disposed || _completed) return;
    _completed = true;
    _log.info('✖ cancelled');
    _stopAttemptTimers();
    widget.onCancelled?.call();
  }

  Future<String?> _getBypassFingerprint() async {
    try {
      return CfCookieHelper.getBypassFingerprint(await _readSessionCookies());
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
      var clearedCount = 0;
      for (final webUri in _cookieUrls) {
        final cookies = await _cookieManager.getCookies(url: webUri);
        for (final cookie in cookies.where(
          (cookie) => CfCookieHelper.isManagedProtectionCookie(cookie.name),
        )) {
          await _cookieManager.deleteCookie(
            url: webUri,
            name: cookie.name,
            domain: cookie.domain,
            path: cookie.path ?? '/',
          );
          clearedCount++;
        }
      }
      _log.fine('🍪 clearing $clearedCount CF cookie(s)');
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _log.fine('🗑 HTTP cache clearing unsupported on Windows');
    } else {
      try {
        await InAppWebViewController.clearAllCache();
        _log.fine('🗑 HTTP cache cleared');
      } catch (e) {
        _log.warning('⚠ error clearing cache', e);
      }
    }
  }

  Future<void> _captureUserAgent() async {
    if (_webController == null) return;
    try {
      final value = await _webController!.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      if (value is String && value.isNotEmpty) {
        _resolvedUserAgent = value;
      } else if (value != null) {
        _resolvedUserAgent = value.toString();
      }
      _log.fine(
        '🌐 user-agent captured=${_resolvedUserAgent?.isNotEmpty == true}',
      );
    } catch (e) {
      _log.warning('⚠ error reading user-agent', e);
    }
  }

  Future<List<CfBrowserCookie>> _exportCookies() async {
    return _readSessionCookies();
  }

  String get _resolvedFinalUrl =>
      _lastNavigatedUrl ?? _lastFinishedUrl ?? _lastStartedUrl ?? widget.url;

  Iterable<WebUri> get _cookieUrls sync* {
    final finalUrl = _lastNavigatedUrl;
    if (finalUrl != null) yield WebUri(finalUrl);
    for (final url in _visitedUrls) {
      if (url != finalUrl) yield WebUri(url);
    }
  }

  void _recordNavigation(WebUri? url) {
    if (url == null) return;
    final uri = Uri.tryParse(url.toString());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    final normalized = uri.replace(fragment: '').toString();
    _visitedUrls.add(normalized);
    _lastNavigatedUrl = normalized;
  }

  Future<List<CfBrowserCookie>> _readSessionCookies() async {
    final cookiesByScope = <String, CfBrowserCookie>{};
    for (final webUri in _cookieUrls) {
      final fallbackHost = Uri.parse(webUri.toString()).host;
      final cookies = await _cookieManager.getCookies(
        url: webUri,
        webViewController: _webController,
      );
      for (final cookie in cookies) {
        final browserCookie = CfBrowserCookie(
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain ?? fallbackHost,
          path: cookie.path ?? '/',
          isSecure: cookie.isSecure,
          isHttpOnly: cookie.isHttpOnly,
        );
        final scope =
            '${browserCookie.name}\u0000${browserCookie.domain}\u0000${browserCookie.path}';
        cookiesByScope.putIfAbsent(scope, () => browserCookie);
      }
    }
    return cookiesByScope.values.toList(growable: false);
  }

  Future<void> _validateSuccess(CfBypassResult result, int attemptId) async {
    if (!_isCurrentAttempt(attemptId) || _completed) return;

    _successValidationInProgress = true;
    try {
      final decision = await widget.onSuccess(result);
      if (!_isCurrentAttempt(attemptId) || _completed) return;

      switch (decision) {
        case CfWebViewSuccessDecision.accept:
          _completed = true;
          _stopAttemptTimers();
          _log.info('✅ bypass accepted by success validator');
          return;
        case CfWebViewSuccessDecision.reject:
          _completed = true;
          _stopAttemptTimers();
          _log.warning('⚠ bypass rejected by success validator');
          return;
        case CfWebViewSuccessDecision.retry:
          _log.info('🔄 bypass candidate rejected by success validator');
          final fingerprint = CfCookieHelper.getBypassFingerprint(
            result.cookies,
          );
          if (fingerprint != null) {
            _rejectedBypassFingerprints.add(fingerprint);
          }
          await _retry();
      }
    } catch (e) {
      _fail(
        attemptId,
        'Success validation failed: $e',
        CfBypassFailedException(
          url: widget.url,
          message: 'Success validation failed',
          error: e,
        ),
      );
    } finally {
      if (_isCurrentAttempt(attemptId) && !_completed) {
        _successValidationInProgress = false;
      }
    }
  }

  void _fail(int attemptId, String error, CfException exception) {
    if (!_isCurrentAttempt(attemptId) || _completed) return;
    _completed = true;
    _stopAttemptTimers();
    _log.warning('⚠ bypass failed: $error');
    widget.onFailure?.call(
      CfBypassResult.failure(
        url: widget.url,
        finalUrl: _resolvedFinalUrl,
        error: error,
        exception: exception,
        userAgent: _resolvedUserAgent ?? widget.userAgent,
        duration: DateTime.now().difference(_startedAt),
        attempts: _loopCounter + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();

    return InAppWebView(
      webViewEnvironment: _webViewEnvironment,
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: _settings,
      onWebViewCreated: (controller) {
        _webController = controller;
        _startPolling(_attemptId);
      },
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
