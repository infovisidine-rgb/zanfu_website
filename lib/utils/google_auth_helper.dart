import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Google Sign-In helper supporting Popup & Redirect fallbacks for web & mobile.
class GoogleAuthHelper {
  GoogleAuthHelper._();

  /// Call this once at app startup (e.g. in main or splash screen) to handle
  /// the redirect result after browser returns from Google sign-in page.
  static Future<User?> getRedirectResult() async {
    if (!kIsWeb) return null;
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      return result.user;
    } catch (e) {
      debugPrint('GoogleAuthHelper getRedirectResult error: $e');
      return null;
    }
  }

  /// Returns the Firebase user, or null if the user cancelled.
  static Future<User?> signIn() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..setCustomParameters({'prompt': 'select_account'});

    try {
      // Primary method: Popup (works on desktop browsers)
      final result = await FirebaseAuth.instance.signInWithPopup(provider);
      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('GoogleAuthHelper signInWithPopup code: ${e.code}, msg: ${e.message}');
      // Fallback: Redirect (for mobile browsers where popups are blocked)
      if (e.code == 'popup-blocked' || e.code == 'popup-closed-by-user') {
        if (kIsWeb) {
          // signInWithRedirect causes a page reload — result is handled
          // via getRedirectResult() on the next app launch (splash screen).
          await FirebaseAuth.instance.signInWithRedirect(provider);
          // This line is never reached because page reloads above.
          return null;
        }
      }
      rethrow;
    } catch (e) {
      debugPrint('GoogleAuthHelper error: $e');
      rethrow;
    }
  }

  static Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  /// Converts Firebase Auth / Google Auth errors into user-friendly explanations.
  static String formatAuthError(dynamic e) {
    final str = e.toString().toLowerCase();
    if (str.contains('unauthorized-domain') || str.contains('unauthorized domain')) {
      return 'Domain / IP is not authorized in Firebase. Please add this domain under Firebase Console > Authentication > Settings > Authorized domains.';
    }
    if (str.contains('popup-blocked') || str.contains('popup_blocked')) {
      return 'Browser blocked the Google Sign-In popup. Please allow popups for this site.';
    }
    if (str.contains('operation-not-allowed') || str.contains('provider-disabled')) {
      return 'Google Sign-In is not enabled in Firebase Console. Please enable Google under Authentication > Sign-in method.';
    }
    if (str.contains('invalid-api-key') || str.contains('api-key-not-valid')) {
      return 'Invalid Firebase API Key. Please check your firebase_options.dart.';
    }
    if (str.contains('sign_in_canceled') || str.contains('popup-closed-by-user')) {
      return ''; // User intentionally cancelled
    }
    if (e is FirebaseAuthException && e.message != null && e.message!.isNotEmpty) {
      return e.message!;
    }
    return 'Google Sign-In failed ($e). Please try again.';
  }
}
