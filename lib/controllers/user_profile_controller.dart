import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/network_helper.dart';

/// Local-first user profile (name / phone / email only — no saved addresses).
/// - Show from local when available
/// - Fetch Firebase only when local cache missing for this uid
/// - If local missing + offline → wait until online, then fetch
/// - Writes always update local + Firebase together
class UserProfileController extends ChangeNotifier {
  static final UserProfileController _instance =
      UserProfileController._internal();
  factory UserProfileController() => _instance;
  UserProfileController._internal();

  static const String _prefsPrefix = 'user_profile_v1_';

  String userName = "Loading...";
  String userPhone = "Loading...";
  String userEmail = "";

  bool _loaded = false;
  String? _loadedUid;
  Future<void>? _loadFuture;

  /// True while waiting on Firebase because local cache is empty.
  bool waitingForRemote = false;

  bool get isLoaded => _loaded;

  /// Already in memory for current user — UI can show without spinner.
  bool get hasReadyData {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && _loaded && _loadedUid == uid;
  }

  /// Load profile: local first; Firebase only if local empty.
  Future<void> ensureLoaded({bool forceFirebaseIfEmpty = true}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _setGuest();
      return Future.value();
    }
    if (_loaded && _loadedUid == uid) {
      return Future.value();
    }
    _loadFuture ??= _doLoad(forceFirebaseIfEmpty: forceFirebaseIfEmpty);
    return _loadFuture!.whenComplete(() => _loadFuture = null);
  }

  /// Kept for callers that previously used live listeners.
  void startListening() {
    ensureLoaded();
  }

  Future<void> _waitUntilOnline() async {
    if (await NetworkHelper.hasConnectivity()) return;

    final completer = Completer<void>();
    StreamSubscription<List<ConnectivityResult>>? sub;
    sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && !completer.isCompleted) {
        completer.complete();
      }
    });

    while (!completer.isCompleted) {
      if (await NetworkHelper.hasConnectivity()) {
        if (!completer.isCompleted) completer.complete();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    await sub.cancel();
    await completer.future;
  }

  Future<void> _doLoad({required bool forceFirebaseIfEmpty}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _setGuest();
      return;
    }

    try {
      final fromLocal = await _readLocal(user.uid);
      if (fromLocal != null) {
        _applyMap(fromLocal, fallbackUser: user);
        waitingForRemote = false;
        _loaded = true;
        _loadedUid = user.uid;
        notifyListeners();
        debugPrint(
          'UserProfileController: loaded from LOCAL (name=$userName)',
        );
        return;
      }

      if (!forceFirebaseIfEmpty) {
        _applyMap({}, fallbackUser: user);
        waitingForRemote = false;
        _loaded = true;
        _loadedUid = user.uid;
        notifyListeners();
        return;
      }

      // Local missing → need Firebase. Spinner until online + success.
      waitingForRemote = true;
      notifyListeners();
      debugPrint(
        'UserProfileController: no local cache — waiting for internet if needed',
      );

      while (true) {
        await _waitUntilOnline();
        try {
          debugPrint('UserProfileController: fetching Firebase once');
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final data = doc.data() ?? <String, dynamic>{};
          _applyMap(data, fallbackUser: user);
          await _writeLocal(user.uid);
          waitingForRemote = false;
          _loaded = true;
          _loadedUid = user.uid;
          notifyListeners();
          debugPrint('UserProfileController: Firebase → LOCAL saved');
          return;
        } catch (e) {
          debugPrint(
            'UserProfileController: Firebase fetch failed, will retry: $e',
          );
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } catch (e) {
      debugPrint('UserProfileController: load error: $e');
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final local = await _readLocal(user.uid);
        if (local != null) {
          _applyMap(local, fallbackUser: user);
          waitingForRemote = false;
          _loaded = true;
          _loadedUid = user.uid;
          notifyListeners();
          return;
        }
      } else {
        _setGuest();
      }
    }
  }

  void _setGuest() {
    userName = "Guest User";
    userPhone = "";
    userEmail = "";
    waitingForRemote = false;
    _loaded = true;
    _loadedUid = null;
    notifyListeners();
  }

  void _applyMap(Map<String, dynamic> data, {required User fallbackUser}) {
    userName =
        (data['name'] as String?)?.trim().isNotEmpty == true
            ? (data['name'] as String).trim()
            : (fallbackUser.displayName ?? "User");
    userPhone = (data['phone'] as String?) ?? "";
    userEmail =
        (data['email'] as String?)?.trim().isNotEmpty == true
            ? (data['email'] as String).trim()
            : (fallbackUser.email ?? "");
  }

  Future<Map<String, dynamic>?> _readLocal(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefsPrefix$uid');
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) return map;
      if (map is Map) return Map<String, dynamic>.from(map);
    } catch (e) {
      debugPrint('UserProfileController: local decode error: $e');
    }
    return null;
  }

  Future<void> _writeLocal(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'name': userName,
      'phone': userPhone,
      'email': userEmail,
    };
    await prefs.setString('$_prefsPrefix$uid', jsonEncode(map));
  }

  /// Update name / phone / email only — addresses are not stored.
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? email,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await ensureLoaded();

    if (name != null) userName = name;
    if (phone != null) userPhone = phone;
    if (email != null) userEmail = email;

    await _writeLocal(user.uid);
    notifyListeners();

    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
    };
    if (payload.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('UserProfileController: Firebase update error: $e');
    }
  }

  Future<void> saveAfterRegistration({
    required String uid,
    required String name,
    required String email,
    required String phone,
    String address = '',
  }) async {
    userName = name;
    userEmail = email;
    userPhone = phone;
    waitingForRemote = false;
    _loaded = true;
    _loadedUid = uid;
    await _writeLocal(uid);
    notifyListeners();
  }

  void resetSession() {
    _loaded = false;
    _loadedUid = null;
    _loadFuture = null;
    waitingForRemote = false;
    userName = "Loading...";
    userPhone = "Loading...";
    userEmail = "";
    notifyListeners();
  }
}
