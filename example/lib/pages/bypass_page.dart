part of '../main.dart';

// ── Bypass Page ───────────────────────────────────────────────────────────────
enum _BypassState { loading, solving, success, failed, cancelled }

class _LogEntry {
  final DateTime time;
  final String message;
  final IconData icon;
  final Color color;
  _LogEntry({required this.message, required this.icon, required this.color})
      : time = DateTime.now();
}

class BypassPage extends StatefulWidget {
  final String url;
  final String? userAgent;
  final Duration timeout;
  final int stallThreshold;
  final bool clearAllData;
  final bool clearCfCookies;
  final List<CfBrowserCookie> initialCookies;

  const BypassPage({
    super.key,
    required this.url,
    this.userAgent,
    required this.timeout,
    required this.stallThreshold,
    this.clearAllData = false,
    this.clearCfCookies = true,
    required this.initialCookies,
  });

  @override
  State<BypassPage> createState() => _BypassPageState();
}

class _BypassPageState extends State<BypassPage> {
  final _controller = CfBypassController();
  final _logs = <_LogEntry>[];

  _BypassState _state = _BypassState.loading;
  String _pageTitle = 'Connecting…';
  bool _loopDetected = false;
  bool _showLog = false;
  CfBypassResult? _result;

  void _log(String msg, {required IconData icon, required Color color}) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, _LogEntry(message: msg, icon: icon, color: color));
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  // ── CfWebView callbacks ──────────────────────────────────────────────────

  void _onSuccess(CfBypassResult result) {
    _log(
      'Bypass succeeded · ${result.cookies.length} cookies · '
      '${result.duration?.inSeconds ?? 0}s · ${result.attempts} attempt(s)',
      icon: Icons.check_circle_rounded,
      color: _green,
    );
    if (!mounted) return;
    setState(() {
      _state = _BypassState.success;
      _result = result;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.pop(context, result);
    });
  }

  void _onFailure(CfBypassResult result) {
    _log(
      'Bypass failed: ${result.error ?? 'Unknown error'}',
      icon: Icons.error_rounded,
      color: _red,
    );
    if (!mounted) return;
    setState(() {
      _state = _BypassState.failed;
      _result = result;
    });
  }

  void _onCancelled() {
    _log('Cancelled by user', icon: Icons.cancel_rounded, color: _muted);
    if (mounted) Navigator.pop(context);
  }

  void _onPageStartedLoading(String? url) {
    _log('→ ${url ?? '…'}', icon: Icons.arrow_forward_rounded, color: _blue);
    if (mounted &&
        _state != _BypassState.success &&
        _state != _BypassState.failed) {
      setState(() => _state = _BypassState.loading);
    }
  }

  void _onPageFinishedLoading(String? url) {
    _log('✓ ${url ?? '…'}', icon: Icons.done_rounded, color: _dim);
    if (mounted && _state == _BypassState.loading) {
      setState(() => _state = _BypassState.solving);
    }
  }

  void _onTitleChanged(String title) {
    _log('Title: $title', icon: Icons.title_rounded, color: _dim);
    if (mounted) setState(() => _pageTitle = title);
  }

  void _onLoopDetected() {
    _log(
      'Loop detected — ${widget.stallThreshold} loads with no cookie change. '
      'Use Retry to clear CF cookies and reload.',
      icon: Icons.loop_rounded,
      color: _amber,
    );
    if (mounted) setState(() => _loopDetected = true);
  }

  bool _onError(Object error) {
    _log('WebView error: $error',
        icon: Icons.warning_amber_rounded, color: _red);
    return true;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _retry() {
    if (!mounted) return;
    setState(() {
      _loopDetected = false;
      _state = _BypassState.loading;
    });
    _log('Retrying — cleared CF cookies',
        icon: Icons.refresh_rounded, color: _amber);
    _controller.retry();
  }

  void _closeOrCancel() {
    if (_state == _BypassState.failed || _state == _BypassState.cancelled) {
      Navigator.pop(context, _result);
    } else {
      _controller.cancel();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          tooltip: _state == _BypassState.failed ? 'Close' : 'Cancel',
          onPressed: _closeOrCancel,
        ),
        title: Text(
          _pageTitle,
          style: const TextStyle(fontSize: 12, color: _dim, letterSpacing: 0),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          if (_loopDetected)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20, color: _amber),
              tooltip: 'Retry bypass',
              onPressed: _retry,
            ),
          IconButton(
            icon: Icon(
              Icons.terminal_rounded,
              size: 20,
              color: _showLog ? _amber : _muted,
            ),
            tooltip: 'Event log',
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _ProgressBar(state: _state),
        ),
      ),
      body: Stack(
        children: [
          CfWebView(
            url: widget.url,
            controller: _controller,
            userAgent: widget.userAgent,
            timeout: widget.timeout,
            stallThreshold: widget.stallThreshold,
            clearAllDataOnInit: widget.clearAllData,
            clearCfCookiesOnInit: widget.clearCfCookies,
            initialCookies: widget.initialCookies,
            onSuccess: _onSuccess,
            onFailure: _onFailure,
            onCancelled: _onCancelled,
            onPageStartedLoading: _onPageStartedLoading,
            onPageFinishedLoading: _onPageFinishedLoading,
            onTitleChanged: _onTitleChanged,
            onLoopDetected: _onLoopDetected,
            onError: _onError,
          ),
          if (_state == _BypassState.success || _state == _BypassState.failed)
            _StatusBanner(state: _state, result: _result!),
          if (_showLog) _EventLogOverlay(logs: _logs),
        ],
      ),
    );
  }
}

// ── Progress Bar ──────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final _BypassState state;
  const _ProgressBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, frac) = switch (state) {
      _BypassState.loading => (_blue, 0.35),
      _BypassState.solving => (_amber, 0.70),
      _BypassState.success => (_green, 1.00),
      _BypassState.failed => (_red, 1.00),
      _BypassState.cancelled => (_muted, 0.00),
    };

    return LayoutBuilder(
      builder: (_, c) => AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        height: 3,
        width: c.maxWidth * frac,
        alignment: Alignment.centerLeft,
        color: color,
      ),
    );
  }
}

// ── Status Banner ─────────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final _BypassState state;
  final CfBypassResult result;
  const _StatusBanner({required this.state, required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = state == _BypassState.success;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (ok ? _green : _red).withValues(alpha: 0.12),
          border: Border(
            bottom:
                BorderSide(color: (ok ? _green : _red).withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: ok ? _green : _red,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok
                    ? 'Challenge solved · ${result.cookies.length} cookies captured'
                    : result.error ?? 'Bypass failed',
                style: TextStyle(
                  color: ok ? _green : _red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Event Log Overlay ─────────────────────────────────────────────────────────
class _EventLogOverlay extends StatelessWidget {
  final List<_LogEntry> logs;
  const _EventLogOverlay({required this.logs});

  String _ts(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: _bg.withValues(alpha: 0.96),
          border: const Border(top: BorderSide(color: _border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.terminal_rounded, size: 11, color: _amber),
                  const SizedBox(width: 6),
                  Text(
                    'EVENT LOG  •  ${logs.length} entries',
                    style: const TextStyle(
                      color: _amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No events yet.',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: logs.length,
                      itemBuilder: (_, i) {
                        final e = logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ts(e.time),
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(e.icon, size: 11, color: e.color),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.message,
                                  style: TextStyle(
                                    color: e.color,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
