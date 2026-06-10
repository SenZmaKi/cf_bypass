part of '../main.dart';

// ── Result Sheet ──────────────────────────────────────────────────────────────
class ResultSheet extends StatelessWidget {
  final CfBypassResult result;
  final ScrollController scrollController;
  const ResultSheet(
      {super.key, required this.result, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final ok = result.success;
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
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Icon(
                ok ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                color: ok ? _green : _red,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ok ? 'BYPASS SUCCEEDED' : 'BYPASS FAILED',
                      style: TextStyle(
                        color: ok ? _green : _red,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    if (ok)
                      Text(
                        '${result.duration?.inMilliseconds ?? 0} ms  ·  '
                        '${result.attempts} attempt${result.attempts == 1 ? '' : 's'}  ·  '
                        '${result.cookies.length} cookie${result.cookies.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                  ],
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
              if (!ok && result.error != null) ...[
                _ResultRow(
                    label: 'ERROR', value: result.error!, valueColor: _red),
                const SizedBox(height: 16),
              ],
              if (result.finalUrl != null)
                _ResultRow(label: 'FINAL URL', value: result.finalUrl!),
              if (result.userAgent != null)
                _ResultRow(
                  label: 'USER-AGENT',
                  value: result.userAgent!,
                  mono: true,
                  copyable: true,
                ),
              if (result.cfClearanceCookie != null)
                _ResultRow(
                  label: 'cf_clearance',
                  value: result.cfClearanceCookie!,
                  mono: true,
                  copyable: true,
                  accent: _amber,
                ),
              if (result.ddosCookie != null)
                _ResultRow(
                  label: '__ddg1 (DDoS-Guard)',
                  value: result.ddosCookie!,
                  mono: true,
                  copyable: true,
                  accent: _blue,
                ),
              if (result.cookies.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'ALL COOKIES',
                  style: TextStyle(
                    color: _amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...result.cookies.map((c) => _CookieLine(cookie: c)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Result Row ────────────────────────────────────────────────────────────────
class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool copyable;
  final Color? valueColor;
  final Color? accent;

  const _ResultRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.copyable = false,
    this.valueColor,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (accent != null)
                Container(
                  width: 3,
                  height: 12,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Text(
                label,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              if (copyable) ...[
                const Spacer(),
                _CopyButton(text: value),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    accent != null ? accent!.withValues(alpha: 0.3) : _border,
              ),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? _text,
                fontSize: 11,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cookie Line ───────────────────────────────────────────────────────────────
class _CookieLine extends StatelessWidget {
  final CfBrowserCookie cookie;
  const _CookieLine({required this.cookie});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cookie.name,
                        style: const TextStyle(
                          color: _amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (cookie.isSecure == true)
                          const _Chip(label: 'secure', color: _green),
                        if (cookie.isHttpOnly == true)
                          const _Chip(label: 'httpOnly', color: _blue),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  cookie.value,
                  style: const TextStyle(
                    color: _dim,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    [cookie.domain, cookie.path].join('  '),
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _CopyButton(text: '${cookie.name}=${cookie.value}'),
        ],
      ),
    );
  }
}

// ── Copy Button ───────────────────────────────────────────────────────────────
class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _copied
              ? _green.withValues(alpha: 0.15)
              : _border.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _copied ? _green.withValues(alpha: 0.4) : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 11,
              color: _copied ? _green : _muted,
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied' : 'Copy',
              style: TextStyle(
                color: _copied ? _green : _muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chip ──────────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }
}
