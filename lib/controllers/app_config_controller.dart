import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class AppConfigController extends ChangeNotifier {
  static final AppConfigController _instance = AppConfigController._internal();
  factory AppConfigController() => _instance;
  AppConfigController._internal();

  String _customerSupportNumber = '';
  bool _isLoaded = false;
  bool _isLoading = false;

  String get customerSupportNumber => _customerSupportNumber;
  bool get isLoaded => _isLoaded;
  bool get hasSupportNumber => _customerSupportNumber.trim().isNotEmpty;

  Future<void> loadConfig({bool force = false}) async {
    if (_isLoading) return;
    if (_isLoaded && !force && hasSupportNumber) return;

    _isLoading = true;
    try {
      // Primary: customer support / contact / number
      final candidates = <(String, String)>[
        ('customer support', 'contact'),
        ('customerSupport', 'contact'),
        ('customer_support', 'contact'),
        ('Customer Support', 'contact'),
        ('CustomerSupport', 'contact'),
      ];

      for (final path in candidates) {
        final number = await _fetchNumberFromDoc(path.$1, path.$2);
        if (number.isNotEmpty) {
          _customerSupportNumber = number;
          break;
        }
      }

      // Nested map fallback on same docs: contact.number inside another doc
      if (_customerSupportNumber.trim().isEmpty) {
        for (final collection in [
          'customer support',
          'customerSupport',
          'customer_support',
        ]) {
          final snap = await FirebaseFirestore.instance.collection(collection).limit(5).get();
          for (final doc in snap.docs) {
            final extracted = _extractPhone(doc.data());
            if (extracted.isNotEmpty) {
              _customerSupportNumber = extracted;
              break;
            }
          }
          if (_customerSupportNumber.trim().isNotEmpty) break;
        }
      }
    } catch (e) {
      debugPrint('Error loading customer support number: $e');
    } finally {
      _isLoading = false;
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<String> _fetchNumberFromDoc(String collection, String docId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .get();
      if (!doc.exists || doc.data() == null) return '';
      return _extractPhone(doc.data()!);
    } catch (e) {
      debugPrint('Support number fetch failed for $collection/$docId: $e');
      return '';
    }
  }

  String _extractPhone(Map<String, dynamic> data) {
    // Direct fields
    final direct = data['phone_number'] ??
        data['phoneNumber'] ??
        data['number'] ??
        data['phone'] ??
        data['contactNumber'] ??
        data['contact_number'] ??
        data['customerSupportNumber'] ??
        data['supportNumber'] ??
        data['supportPhone'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }

    // Nested: contact.phone_number / contact.number
    final contact = data['contact'];
    if (contact is Map) {
      final nested = contact['phone_number'] ??
          contact['phoneNumber'] ??
          contact['number'] ??
          contact['phone'] ??
          contact['contactNumber'] ??
          contact['supportNumber'];
      if (nested != null && nested.toString().trim().isNotEmpty) {
        return nested.toString().trim();
      }
    }

    return '';
  }

  Future<bool> dialCustomerSupport() async {
    if (!hasSupportNumber) {
      await loadConfig(force: true);
    }

    final number = _customerSupportNumber.trim();
    if (number.isEmpty) return false;

    final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return false;

    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      return await launchUrl(uri);
    } catch (e) {
      debugPrint('Error dialing support number: $e');
      return false;
    }
  }
}
