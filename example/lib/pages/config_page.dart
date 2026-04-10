part of '../main.dart';

// ── Home Page ─────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _formKey       = GlobalKey<FormState>();
  final _urlCtrl       = TextEditingController(text: 'https://nowsecure.nl');
  final _uaCtrl        = TextEditingController();
  final _timeoutCtrl   = TextEditingController(text: '120');
  int  _stallThreshold = 3;
  bool _clearAllData   = false;
  bool _clearCfCookies = true;
  final List<_CookiePair>    _cookies = [];
  final List<CfBypassResult> _history = [];

  bool            _isProbing       = false;
  _ProbeResult?   _lastProbeResult;
  CfBypassResult? _probeSession;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlCtrl.dispose();
    _uaCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  String? _validateUrl(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final uri = Uri.tryParse(v.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return 'Must be a full URL';
    if (!uri.scheme.startsWith('http')) return 'Must start with http(s)://';
    return null;
  }

  String? _validateTimeout(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null) return 'Must be a number';
    if (n < 10)  return 'Min 10s';
    if (n > 600) return 'Max 600s';
    return null;
  }

  List<CfBrowserCookie> _buildCookies() {
    final host = Uri.tryParse(_urlCtrl.text.trim())?.host ?? '';
    return _cookies
        .where((c) => c.name.trim().isNotEmpty)
        .map((c) => CfBrowserCookie(
              name: c.name.trim(),
              value: c.value.trim(),
              domain: host,
            ))
        .toList();
  }

  void _startBypass() {
    // Validate without form since we may be calling from another tab
    final urlErr     = _validateUrl(_urlCtrl.text.trim());
    final timeoutErr = _validateTimeout(_timeoutCtrl.text.trim());
    if (urlErr != null || timeoutErr != null) {
      _tabController.animateTo(0);
      _formKey.currentState?.validate();
      return;
    }
    final timeout = Duration(seconds: int.parse(_timeoutCtrl.text.trim()));
    Navigator.push<CfBypassResult>(
      context,
      MaterialPageRoute(
        builder: (_) => BypassPage(
          url:            _urlCtrl.text.trim(),
          userAgent:      _uaCtrl.text.trim().isEmpty ? null : _uaCtrl.text.trim(),
          timeout:        timeout,
          stallThreshold: _stallThreshold,
          clearAllData:   _clearAllData,
          clearCfCookies: _clearCfCookies,
          initialCookies: _buildCookies(),
        ),
      ),
    ).then((r) {
      if (r != null && mounted) {
        setState(() => _history.insert(0, r));
        _tabController.animateTo(2);
      }
    });
  }

  Future<void> _runProbe() async {
    if (_isProbing) return;
    final url = _urlCtrl.text.trim();
    if (_validateUrl(url) != null) return;

    final cookies = _probeSession?.cookies ?? [];
    final ua = _probeSession?.userAgent ??
        (_uaCtrl.text.trim().isEmpty ? null : _uaCtrl.text.trim());

    setState(() { _isProbing = true; _lastProbeResult = null; });

    final sw = Stopwatch()..start();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        headers: {
          if (ua != null) 'user-agent': ua,
          if (cookies.isNotEmpty) 'cookie': CfCookieHelper.cookiesToHeader(cookies),
        },
      ));

      final response = await dio.get<String>(url);
      sw.stop();

      final flatHeaders = <String, String>{};
      response.headers.forEach(
        (name, values) => flatHeaders[name.toLowerCase()] = values.join(', '),
      );

      final body     = response.data ?? '';
      final finalUrl = response.realUri.toString();
      final detection = CfDetector.detect(CfDetectionRequest(
        url:        finalUrl,
        statusCode: response.statusCode ?? 0,
        body:       body,
        headers:    flatHeaders,
      ));

      if (mounted) {
        setState(() {
          _isProbing = false;
          _lastProbeResult = _ProbeResult(
            url:         url,
            finalUrl:    finalUrl == url ? null : finalUrl,
            statusCode:  response.statusCode,
            detection:   detection,
            duration:    sw.elapsed,
            cookiesUsed: cookies,
            uaUsed:      ua,
          );
        });
      }
    } catch (e) {
      sw.stop();
      final msg = e is DioException ? (e.message ?? e.toString()) : e.toString();
      if (mounted) {
        setState(() {
          _isProbing = false;
          _lastProbeResult = _ProbeResult(
            url:        url,
            statusCode: null,
            detection:  null,
            duration:   sw.elapsed,
            error:      msg,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(14),
          child: Icon(Icons.shield_rounded, color: _amber, size: 20),
        ),
        title: const Text('CF BYPASS'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _amber,
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: _amber,
          unselectedLabelColor: _muted,
          dividerColor: _border,
          labelStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.4,
          ),
          tabs: const [
            Tab(text: 'BYPASS', height: 36),
            Tab(text: 'PROBE',  height: 36),
            Tab(text: 'HISTORY', height: 36),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _BypassTab(
              formKey:                 _formKey,
              urlCtrl:                 _urlCtrl,
              uaCtrl:                  _uaCtrl,
              timeoutCtrl:             _timeoutCtrl,
              stallThreshold:          _stallThreshold,
              clearAllData:            _clearAllData,
              clearCfCookies:          _clearCfCookies,
              cookies:                 _cookies,
              validateUrl:             _validateUrl,
              validateTimeout:         _validateTimeout,
              onStallChanged:          (v) => setState(() => _stallThreshold = v),
              onClearAllDataChanged:   (v) => setState(() => _clearAllData = v),
              onClearCfCookiesChanged: (v) => setState(() => _clearCfCookies = v),
              onAddCookie:             () => setState(() => _cookies.add(_CookiePair())),
              onDeleteCookie:          (i) => setState(() => _cookies.removeAt(i)),
              onLaunch:                _startBypass,
            ),
            _ProbeTab(
              urlCtrl:        _urlCtrl,
              probeSession:   _probeSession,
              hasHistory:     _history.isNotEmpty,
              isProbing:      _isProbing,
              lastResult:     _lastProbeResult,
              onPick:         () => _pushSessionPicker(context),
              onClearSession: _probeSession != null
                  ? () => setState(() => _probeSession = null)
                  : null,
              onProbe:        _runProbe,
              onShowResult:   (r) => _pushProbeSheet(context, r),
            ),
            _HistoryTab(
              history:  _history,
              onSelect: (r) => _pushResultSheet(context, r),
              onClear:  () => setState(() {
                _history.clear();
                _probeSession = null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sheets ───────────────────────────────────────────────────────────────────

  void _pushResultSheet(BuildContext ctx, CfBypassResult result) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: _border),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, sc) => ResultSheet(result: result, scrollController: sc),
      ),
    );
  }

  void _pushSessionPicker(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: _border),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, sc) => _SessionPickerSheet(
          history:        _history,
          selectedResult: _probeSession,
          onSelect: (r) {
            Navigator.pop(ctx);
            setState(() => _probeSession = r);
          },
          onClear: () {
            Navigator.pop(ctx);
            setState(() { _history.clear(); _probeSession = null; });
          },
          scrollController: sc,
        ),
      ),
    );
  }

  void _pushProbeSheet(BuildContext ctx, _ProbeResult probe) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: _border),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, sc) => _ProbeDetailSheet(
          result:          probe,
          scrollController: sc,
          onLaunchBypass:  probe.detection?.kind == CfProtectionKind.challenge
              ? () { Navigator.pop(ctx); _startBypass(); }
              : null,
        ),
      ),
    );
  }
}

// ── Bypass Tab ────────────────────────────────────────────────────────────────
class _BypassTab extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController urlCtrl;
  final TextEditingController uaCtrl;
  final TextEditingController timeoutCtrl;
  final int stallThreshold;
  final bool clearAllData;
  final bool clearCfCookies;
  final List<_CookiePair> cookies;
  final FormFieldValidator<String> validateUrl;
  final FormFieldValidator<String> validateTimeout;
  final ValueChanged<int>  onStallChanged;
  final ValueChanged<bool> onClearAllDataChanged;
  final ValueChanged<bool> onClearCfCookiesChanged;
  final VoidCallback       onAddCookie;
  final ValueChanged<int>  onDeleteCookie;
  final VoidCallback       onLaunch;

  const _BypassTab({
    required this.formKey,
    required this.urlCtrl,
    required this.uaCtrl,
    required this.timeoutCtrl,
    required this.stallThreshold,
    required this.clearAllData,
    required this.clearCfCookies,
    required this.cookies,
    required this.validateUrl,
    required this.validateTimeout,
    required this.onStallChanged,
    required this.onClearAllDataChanged,
    required this.onClearCfCookiesChanged,
    required this.onAddCookie,
    required this.onDeleteCookie,
    required this.onLaunch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            children: [
              // Primary input
              TextFormField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: const TextStyle(
                  fontFamily: 'monospace', color: _text, fontSize: 13,
                ),
                decoration: const InputDecoration(
                  labelText: 'Target URL',
                  hintText: 'https://example.com',
                  prefixIcon: Icon(Icons.link_rounded, size: 16, color: _muted),
                ),
                validator: validateUrl,
              ),
              const SizedBox(height: 12),

              // Options section
              _OptionsPanel(
                uaCtrl:                  uaCtrl,
                timeoutCtrl:             timeoutCtrl,
                stallThreshold:          stallThreshold,
                clearAllData:            clearAllData,
                clearCfCookies:          clearCfCookies,
                cookies:                 cookies,
                validateTimeout:         validateTimeout,
                onStallChanged:          onStallChanged,
                onClearAllDataChanged:   onClearAllDataChanged,
                onClearCfCookiesChanged: onClearCfCookiesChanged,
                onAddCookie:             onAddCookie,
                onDeleteCookie:          onDeleteCookie,
              ),
            ],
          ),
        ),

        // Sticky launch bar
        Container(
          padding: EdgeInsets.fromLTRB(
            16, 10, 16, MediaQuery.paddingOf(context).bottom + 14,
          ),
          decoration: const BoxDecoration(
            color: _bg,
            border: Border(top: BorderSide(color: _border)),
          ),
          child: _LaunchButton(onPressed: onLaunch),
        ),
      ],
    );
  }
}

// ── Options Panel (flat) ──────────────────────────────────────────────────────
class _OptionsPanel extends StatelessWidget {
  final TextEditingController uaCtrl;
  final TextEditingController timeoutCtrl;
  final int stallThreshold;
  final bool clearAllData;
  final bool clearCfCookies;
  final List<_CookiePair> cookies;
  final FormFieldValidator<String> validateTimeout;
  final ValueChanged<int>  onStallChanged;
  final ValueChanged<bool> onClearAllDataChanged;
  final ValueChanged<bool> onClearCfCookiesChanged;
  final VoidCallback       onAddCookie;
  final ValueChanged<int>  onDeleteCookie;

  const _OptionsPanel({
    required this.uaCtrl,
    required this.timeoutCtrl,
    required this.stallThreshold,
    required this.clearAllData,
    required this.clearCfCookies,
    required this.cookies,
    required this.validateTimeout,
    required this.onStallChanged,
    required this.onClearAllDataChanged,
    required this.onClearCfCookiesChanged,
    required this.onAddCookie,
    required this.onDeleteCookie,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 13, color: _muted),
              SizedBox(width: 6),
              Text(
                'OPTIONS',
                style: TextStyle(
                  color: _muted, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1.5,
                ),
              ),
              SizedBox(width: 8),
              Expanded(child: Divider(height: 1)),
            ],
          ),
        ),

        // User-Agent
        TextFormField(
          controller: uaCtrl,
          autocorrect: false,
          style: const TextStyle(
            fontFamily: 'monospace', color: _text, fontSize: 12,
          ),
          decoration: const InputDecoration(
            labelText: 'User-Agent (leave blank for WebView default)',
            prefixIcon: Icon(Icons.web_rounded, size: 16, color: _muted),
          ),
        ),
        const SizedBox(height: 12),

        // Timeout + Stall side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: timeoutCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                style: const TextStyle(
                  fontFamily: 'monospace', color: _text, fontSize: 13,
                ),
                decoration: const InputDecoration(
                  labelText: 'Timeout (seconds)',
                  prefixIcon: Icon(Icons.timer_rounded, size: 16, color: _muted),
                ),
                validator: validateTimeout,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stepper(
                label: 'Stall Threshold',
                value: stallThreshold,
                min: 1,
                max: 20,
                onChanged: onStallChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Toggles
        _ToggleRow(
          label:    'Clear CF cookies on init',
          sublabel: 'Removes stale cf_clearance and __ddg* before each run.',
          value:    clearCfCookies,
          onChanged: onClearCfCookiesChanged,
        ),
        const SizedBox(height: 8),
        _ToggleRow(
          label:    'Clear all browser data on init',
          sublabel: 'Wipes all cookies and cache to force a fresh CF challenge.',
          value:    clearAllData,
          onChanged: onClearAllDataChanged,
        ),
        const SizedBox(height: 14),

        // Initial cookies sub-section
        Row(
          children: [
            const Text(
              'INITIAL COOKIES',
              style: TextStyle(
                color: _muted, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Divider(height: 1)),
            const SizedBox(width: 8),
            _AmberTextButton(label: '+ ADD', onTap: onAddCookie),
          ],
        ),
        const SizedBox(height: 8),
        if (cookies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                'No initial cookies.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          )
        else
          ...cookies.asMap().entries.map(
            (e) => _CookieRow(
              pair:     e.value,
              onDelete: () => onDeleteCookie(e.key),
            ),
          ),
      ],
    );
  }
}

// ── Probe Tab ─────────────────────────────────────────────────────────────────
class _ProbeTab extends StatelessWidget {
  final TextEditingController urlCtrl;
  final CfBypassResult? probeSession;
  final bool            hasHistory;
  final bool            isProbing;
  final _ProbeResult?   lastResult;
  final VoidCallback    onPick;
  final VoidCallback?   onClearSession;
  final VoidCallback    onProbe;
  final ValueChanged<_ProbeResult> onShowResult;

  const _ProbeTab({
    required this.urlCtrl,
    required this.probeSession,
    required this.hasHistory,
    required this.isProbing,
    required this.lastResult,
    required this.onPick,
    this.onClearSession,
    required this.onProbe,
    required this.onShowResult,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // URL display (sourced from Bypass tab)
        ListenableBuilder(
          listenable: urlCtrl,
          builder: (_, __) {
            final url = urlCtrl.text.trim();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 13, color: _muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      url.isEmpty ? 'No URL set — enter one in the Bypass tab' : url,
                      style: TextStyle(
                        color: url.isEmpty ? _muted : _dim,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        _SessionPicker(
          selected:   probeSession,
          hasHistory: hasHistory,
          onPick:     onPick,
          onClear:    onClearSession,
        ),
        const SizedBox(height: 10),

        _ProbeButton(isProbing: isProbing, onPressed: onProbe),

        if (lastResult != null) ...[
          const SizedBox(height: 12),
          _ProbeResultCard(
            result: lastResult!,
            onTap: () => onShowResult(lastResult!),
          ),
        ],
      ],
    );
  }
}

// ── History Tab ───────────────────────────────────────────────────────────────
class _HistoryTab extends StatelessWidget {
  final List<CfBypassResult>      history;
  final ValueChanged<CfBypassResult> onSelect;
  final VoidCallback              onClear;

  const _HistoryTab({
    required this.history,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 44, color: _border),
            SizedBox(height: 12),
            Text(
              'No runs yet',
              style: TextStyle(
                color: _dim, fontSize: 14, fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Bypass results will appear here.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                '${history.length} run${history.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: _muted, fontSize: 11, fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _AmberTextButton(label: 'CLEAR ALL', onTap: onClear),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ResultSummaryCard(
              result: history[i],
              onTap:  () => onSelect(history[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Session Picker Sheet ──────────────────────────────────────────────────────
class _SessionPickerSheet extends StatelessWidget {
  final List<CfBypassResult>      history;
  final void Function(CfBypassResult) onSelect;
  final VoidCallback              onClear;
  final ScrollController          scrollController;
  final CfBypassResult?           selectedResult;

  const _SessionPickerSheet({
    required this.history,
    required this.onSelect,
    required this.onClear,
    required this.scrollController,
    this.selectedResult,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _border, borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 14, color: _amber),
              const SizedBox(width: 8),
              Text(
                'SELECT SESSION  •  ${history.length}',
                style: const TextStyle(
                  color: _amber, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                child: const Text(
                  'CLEAR ALL',
                  style: TextStyle(
                    color: _red, fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ResultSummaryCard(
              result:   history[i],
              selected: history[i] == selectedResult,
              onTap:    () => onSelect(history[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Result Summary Card ───────────────────────────────────────────────────────
class _ResultSummaryCard extends StatelessWidget {
  final CfBypassResult result;
  final VoidCallback   onTap;
  final bool           selected;

  const _ResultSummaryCard({
    required this.result,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final ok = result.success;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _amber : (ok ? _green : _red).withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: ok ? _green : _red,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ok ? 'Bypass succeeded' : 'Bypass failed',
                    style: TextStyle(
                      color: ok ? _green : _red,
                      fontSize: 12, fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ok
                        ? '${result.cookies.length} cookies  ·  '
                          '${result.duration?.inSeconds ?? 0}s  ·  '
                          '${result.attempts} attempt${result.attempts == 1 ? '' : 's'}'
                        : result.error ?? 'Unknown error',
                    style: const TextStyle(color: _muted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            selected
                ? const Icon(Icons.check_circle_rounded, color: _amber, size: 18)
                : const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Form Widgets ──────────────────────────────────────────────────────────────
class _Stepper extends StatelessWidget {
  final String           label;
  final int              value;
  final int              min;
  final int              max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepBtn(
                icon:    Icons.remove,
                enabled: value > min,
                onTap:   () => onChanged(value - 1),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  color: _amber, fontSize: 20,
                  fontWeight: FontWeight.w700, fontFamily: 'monospace',
                ),
              ),
              _StepBtn(
                icon:    Icons.add,
                enabled: value < max,
                onTap:   () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData     icon;
  final bool         enabled;
  final VoidCallback onTap;

  const _StepBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: enabled ? _border : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16, color: enabled ? _text : _muted),
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _LaunchButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _amber,
          foregroundColor: _bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1.2,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_rounded, size: 18),
            SizedBox(width: 8),
            Text('LAUNCH BYPASS'),
          ],
        ),
      ),
    );
  }
}

class _AmberTextButton extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _AmberTextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: _amber, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Cookie Editor ─────────────────────────────────────────────────────────────
class _CookiePair {
  String name  = '';
  String value = '';
}

class _CookieRow extends StatefulWidget {
  final _CookiePair  pair;
  final VoidCallback onDelete;
  const _CookieRow({required this.pair, required this.onDelete});

  @override
  State<_CookieRow> createState() => _CookieRowState();
}

class _CookieRowState extends State<_CookieRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _valueCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.pair.name)
      ..addListener(() => widget.pair.name = _nameCtrl.text);
    _valueCtrl = TextEditingController(text: widget.pair.value)
      ..addListener(() => widget.pair.value = _valueCtrl.text);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: _nameCtrl,
              autocorrect: false,
              style: const TextStyle(
                fontFamily: 'monospace', color: _text, fontSize: 12,
              ),
              decoration: const InputDecoration(
                hintText: 'name',
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              validator: (v) =>
                  v != null && v.isNotEmpty && v.contains(RegExp(r'[\s=;,]'))
                      ? 'Invalid char'
                      : null,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('=', style: TextStyle(color: _muted, fontFamily: 'monospace')),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: _valueCtrl,
              autocorrect: false,
              style: const TextStyle(
                fontFamily: 'monospace', color: _text, fontSize: 12,
              ),
              decoration: const InputDecoration(
                hintText: 'value',
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: widget.onDelete,
            child: Container(
              width: 30, height: 36,
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: _red),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Toggle Row ────────────────────────────────────────────────────────────────
class _ToggleRow extends StatelessWidget {
  final String            label;
  final String?           sublabel;
  final bool              value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: value ? _amber.withValues(alpha: 0.4) : _border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: value ? _amber : _text,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
                if (sublabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      sublabel!,
                      style: const TextStyle(color: _muted, fontSize: 10, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
