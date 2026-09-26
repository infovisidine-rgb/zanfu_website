import 'dart:html' as html;

/// Web: only mobile / tablet UAs (rear-camera devices). Hide on laptops/desktops.
Future<bool> deviceSupportsVisidineAr() async {
  try {
    final nav = html.window.navigator;
    final ua = nav.userAgent.toLowerCase();
    final touchPoints = nav.maxTouchPoints ?? 0;

    // iPadOS desktop-mode Safari reports as Macintosh with touch
    if (ua.contains('macintosh') && touchPoints > 1) return true;

    const mobileTokens = [
      'iphone',
      'ipod',
      'ipad',
      'android',
      'mobile',
      'tablet',
      'silk/',
      'kindle',
      'playbook',
      'bb10',
      'opera mini',
      'opera mobi',
    ];
    for (final t in mobileTokens) {
      if (ua.contains(t)) return true;
    }

    return false;
  } catch (_) {
    return false;
  }
}
