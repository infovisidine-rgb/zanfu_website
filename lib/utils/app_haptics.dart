import 'package:flutter/services.dart';

/// Single place for app tap haptics — nav, selection, etc. all use this.
class AppHaptics {
  AppHaptics._();

  /// Same feel for bottom navigation and choose-item selection taps.
  static Future<void> selection() => HapticFeedback.heavyImpact();
}
