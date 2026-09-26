import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/promotional_banner_model.dart';

class PromotionalBannerController extends ChangeNotifier {
  static final PromotionalBannerController _instance =
      PromotionalBannerController._internal();
  factory PromotionalBannerController() => _instance;
  PromotionalBannerController._internal();

  final List<PromotionalBanner> _scrollableBanners = [];
  final List<PromotionalBanner> _stickyBanners = [];
  bool _isLoaded = false;
  bool _isLoading = false;

  List<PromotionalBanner> get scrollableBanners =>
      List.unmodifiable(_scrollableBanners);
  List<PromotionalBanner> get stickyBanners => List.unmodifiable(_stickyBanners);
  bool get isLoaded => _isLoaded;
  bool get hasScrollableBanners => _scrollableBanners.isNotEmpty;
  bool get hasStickyBanners => _stickyBanners.isNotEmpty;

  Future<void> loadBanners({bool force = false}) async {
    if (_isLoading) return;
    if (_isLoaded && !force) return;

    _isLoading = true;
    try {
      final banners = await _fetchAllBanners();

      // Prefer explicit website_* docs when present.
      final websiteScroll = banners
          .where((b) =>
              b.type.trim().toLowerCase().contains('website') &&
              b.isWebsiteScrollable)
          .toList();
      final websiteSticky = banners
          .where((b) =>
              b.type.trim().toLowerCase().contains('website') &&
              b.isWebsiteSticky)
          .toList();

      final scroll = websiteScroll.isNotEmpty
          ? websiteScroll
          : banners.where((b) => b.isWebsiteScrollable).toList();
      final sticky = websiteSticky.isNotEmpty
          ? websiteSticky
          : banners.where((b) => b.isWebsiteSticky).toList();

      scroll.sort((a, b) => a.order.compareTo(b.order));
      sticky.sort((a, b) => a.order.compareTo(b.order));

      _scrollableBanners
        ..clear()
        ..addAll(scroll);
      _stickyBanners
        ..clear()
        ..addAll(sticky);

      debugPrint(
        'PromotionalBannerController: website banners '
        '${_scrollableBanners.length} scrollable, '
        '${_stickyBanners.length} sticky (force=$force)',
      );
      for (var i = 0; i < _scrollableBanners.length; i++) {
        final b = _scrollableBanners[i];
        debugPrint(
          '  WEBSITE_SCROLLABLE[$i] id=${b.id} type=${b.type} '
          'platform=${b.platform} url=${b.imageUrl}',
        );
      }
      for (var i = 0; i < _stickyBanners.length; i++) {
        final b = _stickyBanners[i];
        debugPrint(
          '  WEBSITE_STICKY[$i] id=${b.id} type=${b.type} '
          'platform=${b.platform} url=${b.imageUrl}',
        );
      }
    } catch (e) {
      debugPrint('Error loading promotional banners: $e');
    } finally {
      _isLoading = false;
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// Clears in-memory banners so next [loadBanners] fetches fresh data.
  void invalidateCache() {
    _isLoaded = false;
    _scrollableBanners.clear();
    _stickyBanners.clear();
  }

  Future<List<PromotionalBanner>> _fetchAllBanners() async {
    final banners = <PromotionalBanner>[];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('promotional_banners')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Doc id (`scrollable` / `sticky` / `website_scrollable` …) is the
        // banner type unless the doc has its own `type` field.
        final type = (data['type'] ?? doc.id).toString().trim();
        final platform = (data['platform'] ??
                data['channel'] ??
                data['for'] ??
                data['target'] ??
                '')
            .toString()
            .trim();

        final urls = <String>[];

        final single = (data['image_url'] ?? data['imageUrl'] ?? '')
            .toString()
            .trim();
        if (single.isNotEmpty) urls.add(single);

        final multi = data['image_urls'] ?? data['imageUrls'];
        if (multi is List) {
          for (final u in multi) {
            final url = u.toString().trim();
            if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
          }
        } else if (multi is Map) {
          for (final u in multi.values) {
            final url = u.toString().trim();
            if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
          }
        }

        for (int i = 0; i < urls.length; i++) {
          banners.add(PromotionalBanner(
            id: '${doc.id}_$i',
            imageUrl: urls[i],
            type: type,
            platform: platform,
            order: i,
          ));
        }
      }
    } catch (e) {
      debugPrint('Promotional banners fetch failed: $e');
    }

    return banners;
  }
}
