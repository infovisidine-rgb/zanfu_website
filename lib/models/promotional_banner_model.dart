class PromotionalBanner {
  final String id;
  final String imageUrl;
  final String type;
  final String? link;
  final String platform;
  final int order;

  const PromotionalBanner({
    required this.id,
    required this.imageUrl,
    required this.type,
    this.link,
    this.platform = '',
    this.order = 0,
  });

  String get _type => type.trim().toLowerCase();
  String get _platform => platform.trim().toLowerCase();

  /// Website / web promotional carousel banners from Firestore.
  bool get isWebsiteScrollable {
    if (_type == 'website_scrollable' ||
        _type == 'website-scrollable' ||
        _type == 'web_scrollable') {
      return true;
    }
    if (!_isScrollableType) return false;
    return _isWebsitePlatform || _platform.isEmpty;
  }

  /// Website / web sticky banners from Firestore.
  bool get isWebsiteSticky {
    if (_type == 'website_sticky' ||
        _type == 'website-sticky' ||
        _type == 'web_sticky') {
      return true;
    }
    if (!_isStickyType) return false;
    return _isWebsitePlatform || _platform.isEmpty;
  }

  bool get _isScrollableType {
    final t = _type;
    return t == 'scrollable' ||
        t == 'scroll' ||
        t == 'carousel' ||
        t == 'website_scrollable' ||
        t == 'website-scrollable' ||
        t == 'web_scrollable';
  }

  bool get _isStickyType {
    final t = _type;
    return t == 'sticky' ||
        t == 'fixed' ||
        t == 'static' ||
        t == 'website_sticky' ||
        t == 'website-sticky' ||
        t == 'web_sticky';
  }

  bool get _isWebsitePlatform {
    final p = _platform;
    return p == 'website' ||
        p == 'web' ||
        p == 'all' ||
        p.contains('website') ||
        p.contains('web');
  }

  // Kept for older call sites / logging.
  bool get isScrollable => isWebsiteScrollable;
  bool get isSticky => isWebsiteSticky;
}
