import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'app_colors.dart';

/// Browser location permission handling for delivery / branch lookup.
class PermissionHelper {
  PermissionHelper._();

  /// [showDialogOnDeny] false for silent splash init.
  static Future<bool> ensureLocation(
    BuildContext? context, {
    bool showDialogOnDeny = true,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (showDialogOnDeny && context != null && context.mounted) {
        final action = await _showDeniedDialog(
          context,
          title: 'Location Services Off',
          message:
              'Please turn on device location to find nearby branches and set delivery address.',
          showOpenSettings: true,
          openSettingsLabel: 'Open Location Settings',
        );
        if (action == _PermissionDialogAction.openSettings) {
          await Geolocator.openLocationSettings();
        }
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      try {
        permission = await Geolocator.requestPermission();
      } catch (_) {}
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return true;
    }

    // Smooth fallback: don't show blocking error dialogs if location is blocked in browser
    return false;
  }

  static Future<_PermissionDialogAction?> _showDeniedDialog(
    BuildContext context, {
    required String title,
    required String message,
    bool showOpenSettings = true,
    String openSettingsLabel = 'Open Settings',
  }) {
    return showDialog<_PermissionDialogAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.matteBlack,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _PermissionDialogAction.cancel),
              child: const Text(
                'Not Now',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            if (!showOpenSettings)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, _PermissionDialogAction.retry),
                child: const Text(
                  'Allow',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            if (showOpenSettings)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, _PermissionDialogAction.openSettings),
                child: Text(
                  openSettingsLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _PermissionDialogAction { cancel, retry, openSettings }
