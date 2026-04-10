import 'package:cf_bypass/cf_bypass.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'pages/config_page.dart';
part 'pages/bypass_page.dart';
part 'pages/probe_section.dart';
part 'sheets/result_sheet.dart';

void main() {
  setupCfLogger();
  runApp(const CfBypassApp());
}

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg = Color(0xFF080C14);
const _surface = Color(0xFF0F1621);
const _card = Color(0xFF141B27);
const _border = Color(0xFF1E2A3D);
const _amber = Color(0xFFF59E0B);
const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _text = Color(0xFFE2E8F0);
const _dim = Color(0xFF94A3B8);
const _muted = Color(0xFF64748B);

// ── App ───────────────────────────────────────────────────────────────────────
class CfBypassApp extends StatelessWidget {
  const CfBypassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CF Bypass',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomePage(),
    );
  }

  ThemeData _buildTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _amber,
          secondary: _green,
          surface: _surface,
          error: _red,
          onSurface: _text,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _bg,
          foregroundColor: _text,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: _text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        dividerTheme:
            const DividerThemeData(color: _border, thickness: 1, space: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: _inputBorder(_border),
          enabledBorder: _inputBorder(_border),
          focusedBorder: _inputBorder(_amber, width: 1.5),
          errorBorder: _inputBorder(_red),
          focusedErrorBorder: _inputBorder(_red, width: 1.5),
          labelStyle:
              const TextStyle(color: _muted, fontSize: 11, letterSpacing: 0.3),
          hintStyle: const TextStyle(color: _muted, fontSize: 12),
          errorStyle: const TextStyle(color: _red, fontSize: 10),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _amber : _muted,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? _amber.withValues(alpha: 0.25)
                : _border,
          ),
        ),
      );

  OutlineInputBorder _inputBorder(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c, width: width),
      );
}
