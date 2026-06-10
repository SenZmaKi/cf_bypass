part of '../main.dart';

// ── Probe Result Model ────────────────────────────────────────────────────────
class _ProbeResult {
  final String url;
  final String? finalUrl;
  final int? statusCode;
  final CfDetectionResult? detection;
  final Duration duration;
  final String? error;
  final String? uaUsed;
  final List<CfBrowserCookie> cookiesUsed;

  const _ProbeResult({
    required this.url,
    required this.statusCode,
    required this.detection,
    required this.duration,
    this.finalUrl,
    this.error,
    this.uaUsed,
    this.cookiesUsed = const [],
  });

  bool get hasError => error != null;
  CfProtectionKind get kind => detection?.kind ?? CfProtectionKind.none;
}

// ── Session Picker Row ────────────────────────────────────────────────────────
class _SessionPicker extends StatelessWidget {
  final CfBypassResult? selected;
  final bool hasHistory;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _SessionPicker({
    required this.selected,
    required this.hasHistory,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final s = selected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: s != null ? _amber.withValues(alpha: 0.4) : _border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            s != null ? Icons.verified_rounded : Icons.person_off_outlined,
            size: 15,
            color: s != null ? _amber : _muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s != null ? 'Session active' : 'No session (raw request)',
                  style: TextStyle(
                    color: s != null ? _amber : _text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (s != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${s.cookies.length} cookie${s.cookies.length == 1 ? '' : 's'}'
                    '${s.userAgent != null ? '  ·  custom UA' : ''}',
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          if (s != null && onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.close_rounded, size: 13, color: _red),
              ),
            ),
          GestureDetector(
            onTap: hasHistory ? onPick : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: hasHistory
                    ? _amber.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: hasHistory ? _amber.withValues(alpha: 0.3) : _border,
                ),
              ),
              child: Text(
                s != null ? 'CHANGE' : 'PICK',
                style: TextStyle(
                  color: hasHistory ? _amber : _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Probe Button ──────────────────────────────────────────────────────────────
class _ProbeButton extends StatelessWidget {
  final bool isProbing;
  final VoidCallback onPressed;

  const _ProbeButton({required this.isProbing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: isProbing ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _blue,
          side: BorderSide(color: _blue.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1.2),
        ),
        child: isProbing
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _blue.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('PROBING…', style: TextStyle(color: _muted)),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('PROBE REQUEST'),
                ],
              ),
      ),
    );
  }
}

// ── Probe Result Card (compact, inline) ───────────────────────────────────────
class _ProbeResultCard extends StatelessWidget {
  final _ProbeResult result;
  final VoidCallback? onTap;

  const _ProbeResultCard({required this.result, this.onTap});

  (String, Color, IconData) get _meta {
    if (result.hasError) {
      return ('ERROR', _red, Icons.error_outline_rounded);
    }
    return switch (result.kind) {
      CfProtectionKind.challenge => (
          'CHALLENGE',
          _amber,
          Icons.shield_outlined
        ),
      CfProtectionKind.blocked => ('BLOCKED', _red, Icons.block_rounded),
      _ => ('CLEAN', _green, Icons.check_circle_outline_rounded),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _meta;
    final detection = result.detection;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 11, color: color),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                if (result.statusCode != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${result.statusCode}',
                    style: const TextStyle(
                      color: _dim,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${result.duration.inMilliseconds}ms',
                  style: const TextStyle(
                      color: _muted, fontSize: 11, fontFamily: 'monospace'),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: _muted),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              result.url,
              style: const TextStyle(
                  color: _dim, fontSize: 11, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
            if (result.hasError && result.error != null) ...[
              const SizedBox(height: 4),
              Text(
                result.error!,
                style: const TextStyle(color: _red, fontSize: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (detection != null &&
                detection.matchedIndicators.isNotEmpty) ...[
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: detection.matchedIndicators
                    .map((ind) => _IndicatorChip(label: ind, color: color))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Indicator Chip ────────────────────────────────────────────────────────────
class _IndicatorChip extends StatelessWidget {
  final String label;
  final Color color;

  const _IndicatorChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontFamily: 'monospace'),
      ),
    );
  }
}

// ── Probe Detail Sheet ────────────────────────────────────────────────────────
class _ProbeDetailSheet extends StatelessWidget {
  final _ProbeResult result;
  final ScrollController scrollController;
  final VoidCallback? onLaunchBypass;

  const _ProbeDetailSheet({
    required this.result,
    required this.scrollController,
    this.onLaunchBypass,
  });

  (String, Color) get _meta {
    if (result.hasError) return ('ERROR', _red);
    return switch (result.kind) {
      CfProtectionKind.challenge => ('CHALLENGE', _amber),
      CfProtectionKind.blocked => ('BLOCKED', _red),
      _ => ('CLEAN', _green),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _meta;
    final detection = result.detection;

    return Column(
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.radar_rounded, size: 18, color: _blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PROBE RESULT',
                      style: TextStyle(
                        color: _text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      '${result.duration.inMilliseconds}ms  ·  '
                      '${result.statusCode != null ? 'HTTP ${result.statusCode}' : 'No response'}',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _ResultRow(label: 'URL', value: result.url, mono: true),
              if (result.finalUrl != null && result.finalUrl != result.url)
                _ResultRow(
                    label: 'FINAL URL', value: result.finalUrl!, mono: true),
              if (result.statusCode != null)
                _ResultRow(
                    label: 'STATUS', value: '${result.statusCode}', mono: true),
              if (result.hasError && result.error != null)
                _ResultRow(
                    label: 'ERROR', value: result.error!, valueColor: _red),
              if (result.uaUsed != null)
                _ResultRow(
                  label: 'USER-AGENT USED',
                  value: result.uaUsed!,
                  mono: true,
                  copyable: true,
                ),
              if (result.cookiesUsed.isNotEmpty)
                _ResultRow(
                  label: 'COOKIES USED',
                  value:
                      '${result.cookiesUsed.length} cookie${result.cookiesUsed.length == 1 ? '' : 's'}',
                ),
              if (detection != null) ...[
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Text(
                        'DETECTION',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: Divider(height: 1)),
                    ],
                  ),
                ),
                _ResultRow(
                  label: 'KIND',
                  value: result.kind.name.toUpperCase(),
                  mono: true,
                ),
                if (detection.matchedIndicators.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MATCHED INDICATORS',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: detection.matchedIndicators
                              .map((ind) =>
                                  _IndicatorChip(label: ind, color: color))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              if (result.kind == CfProtectionKind.challenge &&
                  onLaunchBypass != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: onLaunchBypass,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _amber,
                      foregroundColor: _bg,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text(
                      'LAUNCH BYPASS',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 1.2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
