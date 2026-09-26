import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_colors.dart';

class NetworkHelper {
  /// True if device has a network interface (wifi/mobile/ethernet).
  /// Note: this can be true on "limited" networks with no real data.
  static Future<bool> hasConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// True when packets can actually reach the internet.
  ///
  /// Uses several probes because some mobile packages block Google
  /// "social"/check domains while still allowing Firebase / other HTTPS.
  /// Limited / captive networks (linked, no real data) still fail all probes.
  static Future<bool> hasInternetAccess() async {
    if (!await hasConnectivity()) return false;

    final results = await Future.wait([
      _probeGoogle204(),
      _probeCloudflare(),
      _probeFirebase(),
    ]);
    return results.any((ok) => ok);
  }

  /// Classic captive-portal check — 204 = real internet.
  static Future<bool> _probeGoogle204() async {
    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 204) return true;
    } catch (_) {}

    try {
      final response = await http
          .head(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 204) return true;
    } catch (_) {}

    return false;
  }

  /// Non-Google probe — works on packages that throttle/block Google checks.
  static Future<bool> _probeCloudflare() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 4));
      // Any HTTP response means TLS + routing works (not a dead limited link).
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// What this app actually needs — if Firestore host is reachable, proceed.
  static Future<bool> _probeFirebase() async {
    try {
      final response = await http
          .get(Uri.parse('https://firestore.googleapis.com/'))
          .timeout(const Duration(seconds: 4));
      // 404/4xx still means the host answered over the internet.
      return response.statusCode > 0;
    } catch (_) {
      return false;
    }
  }

  /// Shows a no-internet dialog.
  /// Returns `true` if internet came back while open, or user tapped Try Again.
  /// Returns `false` if user tapped OK.
  /// Dialog auto-closes when connectivity is restored.
  static Future<bool> showNoInternetDialog(
    BuildContext context, {
    String title = 'No Internet',
    String message =
        'No internet connection. Please turn on internet and try again.',
    bool showRetryButton = false,
  }) async {
    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _NoInternetDialog(
          title: title,
          message: message,
          showRetryButton: showRetryButton,
        );
      },
    );

    return result ?? false;
  }
}

class _NoInternetDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool showRetryButton;

  const _NoInternetDialog({
    required this.title,
    required this.message,
    required this.showRetryButton,
  });

  @override
  State<_NoInternetDialog> createState() => _NoInternetDialogState();
}

class _NoInternetDialogState extends State<_NoInternetDialog> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _subscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    // Also check current state in case internet returned before listen fired
    _checkNow();
  }

  Future<void> _checkNow() async {
    final online = await NetworkHelper.hasConnectivity();
    if (online) _closeWithResult(true);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) _closeWithResult(true);
  }

  void _closeWithResult(bool result) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.matteBlack,
        ),
      ),
      content: Text(
        widget.message,
        style: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: Colors.black87,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _closeWithResult(false),
          child: const Text(
            'OK',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ),
        if (widget.showRetryButton)
          TextButton(
            onPressed: () => _closeWithResult(true),
            child: const Text(
              'Try Again',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}
