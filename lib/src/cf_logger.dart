import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

export 'package:logging/logging.dart' show Logger, Level;

/// Convenience extensions on [Logger] that attach structured metadata to log
/// records without requiring callers to format strings manually.
extension LoggerExtensions on Logger {
  /// Logs [message] at [Level.SEVERE] with optional [error], [stackTrace], and
  /// arbitrary [metadata].
  void severeWithMetadata(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final msg = '$message (error: $error, stacktrace: $stackTrace, metadata: $metadata)';
    severe(msg);
  }

  /// Logs [message] at [Level.FINE] with optional [metadata].
  void fineWithMetadata(Object? message, {Map<String, dynamic>? metadata}) {
    fine('$message (metadata: $metadata)');
  }

  /// Logs [message] at [Level.INFO] with optional [metadata].
  void infoWithMetadata(Object? message, {Map<String, dynamic>? metadata}) {
    info('$message (metadata: $metadata)');
  }

  /// Logs [message] at [Level.WARNING] with optional [metadata].
  void warningWithMetadata(Object? message, {Map<String, dynamic>? metadata}) {
    warning('$message (metadata: $metadata)');
  }
}

String _colorForLevel(Level level) => switch (level) {
      Level.SEVERE  => '❌ \x1B[31m',
      Level.WARNING => '⚠️  \x1B[33m',
      Level.FINE    => '✅ \x1B[32m',
      _             => '\x1B[37m',
    };

/// Sets up the root [Logger] to print to the Flutter debug console.
///
/// Only active when [kDebugMode] is true. Call once at app startup, e.g. in
/// `main()` before `runApp()`.
void setupCfLogger({Level level = Level.ALL, bool enabled = kDebugMode}) {
  if (!enabled) return;
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    const reset = '\x1B[0m';
    final color = _colorForLevel(record.level);
    final prefix = '${record.level.name} [${record.loggerName}]:';
    for (final line in record.message.split('\n')) {
      debugPrint('$color$prefix $line$reset');
    }
  });
}
