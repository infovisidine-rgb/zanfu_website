import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_model.dart';
import '../services/firestore_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_haptics.dart';
import '../utils/responsive_helper.dart';
import '../controllers/cart_controller.dart';
import '../models/menu_item_model.dart';
import '../utils/device_ar_capability.dart';
import '../utils/visidine_ar_open.dart';
import '../utils/app_navigation.dart';
import '../widgets/shimmer.dart';
import '../widgets/local_cached_image.dart';
import '../widgets/discount_badge.dart';
import '../widgets/app_cart_icon.dart';
import '../widgets/hover_expand_header_icon.dart';
import '../widgets/tap_hand_click_hint.dart';
import '../widgets/visidine_brand_text.dart';

/// Hand coach shows only for the first N detail opens after install.
const String _kDetailTapHintCountKey = 'detail_list_tap_hint_count';
const int _kDetailTapHintMaxShows = 3;

class DetailScreen extends StatefulWidget {
  final FoodModel model;
  final String? initialVariation;
  final Set<String>? initialToppings;
  final int initialQuantity;
  final bool isEditing;
  final Map<String, String>? sizeModelUrls;
  /// Size key → display name from Firestore `size_model_urls.*.name`.
  final Map<String, String> sizeModelDisplayNames;
  /// Section title for size picker (Firestore `size_selection_label`).
  final String sizeSelectionLabel;
  /// Ordered keys from Firestore `deal_model_types` for size display order.
  final List<String> dealModelTypesOrder;
  final bool isDeal;
  final List<DealGroup> dealGroups;
  final List<String> dealFixedItems;
  final Map<String, int> dealModelQuantities;
  /// URL → display name from Firestore `name` fields.
  final Map<String, String> modelDisplayNames;
  final List<String>? initialDealOptions;
  /// Laptop/desktop: shown inside a large dialog instead of a full route.
  final bool asDialog;

  const DetailScreen({
    super.key, 
    required this.model,
    this.initialVariation,
    this.initialToppings,
    this.initialQuantity = 1,
    this.isEditing = false,
    this.sizeModelUrls,
    this.sizeModelDisplayNames = const {},
    this.sizeSelectionLabel = '',
    this.dealModelTypesOrder = const [],
    this.isDeal = false,
    this.dealGroups = const [],
    this.dealFixedItems = const [],
    this.dealModelQuantities = const {},
    this.modelDisplayNames = const {},
    this.initialDealOptions,
    this.asDialog = false,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();

  static Future<T?> open<T>(
    BuildContext context,
    DetailScreen Function(bool asDialog) builder,
  ) {
    // Tablet should behave like mobile (navigate screen with mobile layout).
    final wide = ResponsiveHelper.isDesktop(context);
    final page = builder(wide);
    if (!wide) {
      return Navigator.of(context).push<T>(
        MaterialPageRoute(builder: (_) => page),
      );
    }
    final size = MediaQuery.sizeOf(context);
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.cardBackground,
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width * 0.04,
            vertical: size.height * 0.025,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: size.width * 0.92,
            height: size.height * 0.94,
            child: page,
          ),
        );
      },
    );
  }
}

class _BoxCornersMiniLoader extends StatefulWidget {
  final double size;

  const _BoxCornersMiniLoader({required this.size});

  @override
  State<_BoxCornersMiniLoader> createState() => _BoxCornersMiniLoaderState();
}

class _BoxCornersMiniLoaderState extends State<_BoxCornersMiniLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final squareSize = widget.size * 0.55;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: squareSize,
            height: squareSize,
            child: Image.asset(
              'assets/icon_square.png',
              fit: BoxFit.contain,
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Forward-only: continuous forward spins (no pause).
              final t = _controller.value;

              // 1 second = 2 spins (continuous linear rotation).
              const spinsPerCycle = 1.5;
              final angleZ = spinsPerCycle * 2 * math.pi * t;

              // Front/back feel using Z phase (no backward direction change).
              final angleY = math.sin(angleZ) * 0.55;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..rotateZ(angleZ)
                  ..rotateY(angleY),
                child: child,
              );
            },
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Image.asset(
                'assets/logo_corners.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelViewerWithCornersLoader extends StatefulWidget {
  final String src;
  final String alt;
  final VoidCallback? onLoaded;

  const _ModelViewerWithCornersLoader({
    required this.src,
    required this.alt,
    this.onLoaded,
  });

  @override
  State<_ModelViewerWithCornersLoader> createState() =>
      _ModelViewerWithCornersLoaderState();
}

class _ModelViewerWithCornersLoaderState
    extends State<_ModelViewerWithCornersLoader> {
  bool _loading = true;
  bool _loadNotified = false;

  @override
  void initState() {
    super.initState();
    // Safety fallback: ensure spinner disappears after 6 seconds max
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (mounted && _loading) setState(() => _loading = false);
    });
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || _loadNotified) return;
      _loadNotified = true;
      widget.onLoaded?.call();
    });
  }

  void _onModelLoaded() {
    if (mounted && _loading) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewerId = 'detail_mvp_${widget.src.hashCode}';

    return Stack(
      children: [
        ModelViewer(
          id: viewerId,
          src: widget.src,
          alt: widget.alt,
          ar: false,
          autoRotate: true,
          cameraControls: true,
          backgroundColor: Colors.transparent,
          minCameraOrbit: 'auto 0deg auto',
          maxCameraOrbit: 'auto 90deg auto',
          debugLogging: false,
          relatedCss: '''
#default-progress-bar,
#default-progress-bar .bar,
.slot.progress-bar,
.progress-bar,
::part(progress-bar),
slot[name="progress-bar"] {
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
}
model-viewer,
:host,
html, body {
  border: none !important;
  outline: none !important;
  background: transparent !important;
  box-shadow: none !important;
}
''',
          javascriptChannels: {
            JavascriptChannel(
              'ModelViewerLoadChannel',
              onMessageReceived: (message) {
                _onModelLoaded();
              },
            ),
          },
          relatedJs: '''
(function () {
  function attach() {
    var viewer = document.getElementById("$viewerId");
    if (!viewer) { setTimeout(attach, 50); return; }
    function notify() {
      if (window.ModelViewerLoadChannel && window.ModelViewerLoadChannel.postMessage) {
        window.ModelViewerLoadChannel.postMessage("loaded");
      }
    }
    if (viewer.loaded) {
      notify();
    } else {
      viewer.addEventListener("load", notify, { once: true });
      viewer.addEventListener("error", notify, { once: true });
    }
  }
  attach();
})();
''',
        ),
        if (_loading)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: AppColors.scaffoldBackground,
                child: const Center(
                  child: _BoxCornersMiniLoader(size: 56),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailScreenState extends State<DetailScreen>
    with TickerProviderStateMixin {
  int _quantity = 1;
  String? _selectedVariation;
  double _selectedPriceValue = 0;
  List<Map<String, dynamic>> _variations = [];
  final Set<String> _selectedToppings = {};
  final CartController _cart = CartController();
  final Map<int, String> _selectedGroupOptions = {};
  /// Tracks which deal-choice groups the user actually tapped.
  /// Default options may be prefilled for UI, but we don't want to treat
  /// them as "selected" for AR bottom bar names.
  final Set<int> _touchedDealGroupIndices = {};
  Future<String>? _modelSrcFuture;
  String? _activeModelUrl;
  bool _hasTappedItem = false;
  /// Which deal row owns the eye (avoids duplicate eyes when URLs repeat).
  int? _previewGroupIndex;
  bool _previewIsFixedItem = false;
  String _description = '';
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _modelDownloaded = false;
  bool _isRetryingModel = false;

  final GlobalKey _modelAreaKey = GlobalKey();
  final GlobalKey _hintTargetKey = GlobalKey();
  final GlobalKey _bodyStackKey = GlobalKey();
  late final AnimationController _flyHandCtrl;
  late final AnimationController _vdFoldCtrl;
  Offset? _handStartGlobal;
  Offset? _handEndGlobal;
  bool _handFlying = false;
  bool _vdPulseRunning = false;
  /// False on web laptops / desktops — Visidine hidden (no camera AR).
  bool _deviceSupportsAr = false;
  bool _handArrived = false;
  bool _vdPulsePlayed = false;
  bool _modelFullscreenOpen = false;
  double _topOverscrollAcc = 0;
  /// True only after scroll has fully settled at the top — next NEW pull can open fullscreen.
  bool _settledAtTopReady = false;

  bool get _listTapHintVisible => !_hasTappedItem;

  bool get _needsListTapHint {
    if (widget.isDeal) {
      return widget.dealGroups.any((g) => g.options.isNotEmpty) ||
          widget.dealFixedItems.isNotEmpty;
    }
    return _variations.length > 1;
  }

  /// First tappable model row in deal choice groups.
  bool _shouldShowDealTapHintOnChoice(int gIndex, int optionIndex) {
    if (!_listTapHintVisible || !widget.isDeal) return false;
    for (var g = 0; g < widget.dealGroups.length; g++) {
      if (widget.dealGroups[g].options.isEmpty) continue;
      return g == gIndex && optionIndex == 0;
    }
    return false;
  }

  /// First fixed item only when there are no choice options.
  bool _shouldShowDealTapHintOnFixed(int index) {
    if (!_listTapHintVisible || !widget.isDeal) return false;
    final hasChoice =
        widget.dealGroups.any((g) => g.options.isNotEmpty);
    if (hasChoice) return false;
    return index == 0;
  }

  /// First size when item has multiple sizes (non-deal).
  bool _shouldShowSizeTapHint(int index) {
    if (!_listTapHintVisible || widget.isDeal) return false;
    return _variations.length > 1 && index == 0;
  }

  Widget _itemNameWithTapHint({
    required String text,
    required TextStyle style,
    required bool showHint,
  }) {
    return Stack(
      key: showHint ? _hintTargetKey : null,
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        Text(text, style: style),
        if (showHint && _handArrived)
          const Positioned(
            left: 18,
            top: 2,
            child: IgnorePointer(child: TapHandClickHint()),
          ),
      ],
    );
  }

  String _cleanModelNameFromUrl(String url) {
    // Prefer Firestore `name` stored next to the URL.
    final key = url.trim();
    final fromMap = widget.modelDisplayNames[key]?.trim();
    if (fromMap != null && fromMap.isNotEmpty) return fromMap;

    final norm = key
        .split('/')
        .last
        .split('?')
        .first
        .replaceAll('.glb', '')
        .replaceAll('.usdz', '')
        .replaceAll('-optimized', '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    if (norm.isNotEmpty) {
      final byNorm = widget.modelDisplayNames['norm:$norm']?.trim();
      if (byNorm != null && byNorm.isNotEmpty) return byNorm;

      for (final e in widget.modelDisplayNames.entries) {
        if (e.key.startsWith('norm:')) continue;
        final en = e.key
            .split('/')
            .last
            .split('?')
            .first
            .replaceAll('.glb', '')
            .replaceAll('.usdz', '')
            .replaceAll('-optimized', '')
            .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
            .toLowerCase();
        if (en == norm && e.value.trim().isNotEmpty) return e.value.trim();
      }
      for (final g in widget.dealGroups) {
        for (final o in g.options) {
          if (o.hasFirestoreName && o.name.trim().isNotEmpty) {
            final on = o.url
                .split('/')
                .last
                .split('?')
                .first
                .replaceAll('.glb', '')
                .replaceAll('.usdz', '')
                .replaceAll('-optimized', '')
                .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                .toLowerCase();
            if (o.url == key || on == norm) return o.name.trim();
          }
        }
      }
    }

    // Legacy fallback only when Firestore name is missing.
    final filename = url.split('/').last.split('?').first
        .replaceAll('.glb', '')
        .replaceAll('.usdz', '')
        .replaceAll('-optimized', '')
        .replaceAll('.', ' ');
    final pattern = RegExp(r'(?<=[a-z])(?=[A-Z])');
    String name = filename.split(pattern).join(' ');
    name = name.replaceAll('BBq', 'BBQ').replaceAll('bbq', 'BBQ');
    
    // Capitalize first letters of words
    name = name.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
    
    return name;
  }

  @override
  void initState() {
    super.initState();
    _flyHandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    );
    _vdFoldCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
      value: 1.0,
    );
    _quantity = widget.initialQuantity;
    _parseVariations();
    _description = widget.model.description;
    if (_description.isEmpty) {
      _loadDescription();
    }
    deviceSupportsVisidineAr().then((ok) {
      if (!mounted) return;
      if (_deviceSupportsAr == ok) return;
      setState(() => _deviceSupportsAr = ok);
      if (ok) _playViewByVisidinePulse();
    });
    
    if (widget.initialVariation != null) {
      _selectedVariation = widget.initialVariation;
      final v = _variations.firstWhere(
        (val) => val['name'] == _selectedVariation,
        orElse: () => _variations.isNotEmpty ? _variations[0] : {'price': 0.0},
      );
      _selectedPriceValue = v['price'];
    } else if (_variations.isNotEmpty) {
      _selectedVariation = _variations[0]['name'];
      _selectedPriceValue = _variations[0]['price'];
    }
    
    if (widget.initialToppings != null) {
      _selectedToppings.addAll(widget.initialToppings!);
    }

    if (widget.isDeal) {
      for (int i = 0; i < widget.dealGroups.length; i++) {
        final group = widget.dealGroups[i];
        if (widget.initialDealOptions != null && widget.initialDealOptions!.length > i) {
          final savedName = widget.initialDealOptions![i];
          final matchingUrl = group.itemUrls.firstWhere(
            (url) =>
                group.nameForUrl(url) == savedName ||
                _cleanModelNameFromUrl(url) == savedName,
            orElse: () => group.itemUrls.isNotEmpty ? group.itemUrls.first : "",
          );
          _selectedGroupOptions[i] = matchingUrl;
        } else if (group.itemUrls.isNotEmpty) {
          _selectedGroupOptions[i] = group.itemUrls.first;
        }
      }
      // Do not set _activeModelUrl yet — top shows deal image until user taps a row.
    }

    _reloadModelSrc();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runListTapCoachSequence();
    });
  }

  /// Starts (or restarts) model download for ModelViewer.
  void _reloadModelSrc() {
    _modelDownloaded = false;
    _modelSrcFuture = _getModelSrc().then((src) {
      // Mobile: base64 data URL. Web: direct https URL.
      if (src.startsWith('data:') ||
          src.startsWith('http://') ||
          src.startsWith('https://')) {
        _modelDownloaded = true;
      }
      return src;
    });
  }

  bool _isUsableModelSrc(String src) {
    final s = src.trim();
    if (s.isEmpty) return false;
    if (s.startsWith('data:')) return true;
    if (s.startsWith('http://') || s.startsWith('https://')) return true;
    return FoodModel.isGlbOrUsdzUrl(s);
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hasNet = results.any((r) => r != ConnectivityResult.none);
    if (!hasNet || _modelDownloaded || _isRetryingModel || !mounted) return;

    final path = _activeModelUrl ?? widget.model.path;
    if (!FoodModel.isGlbOrUsdzUrl(path)) return;
    if (!path.startsWith('http://') && !path.startsWith('https://')) return;

    _isRetryingModel = true;
    debugPrint('DetailScreen: internet restored — retrying 3D model download');
    setState(() => _reloadModelSrc());
    try {
      await _modelSrcFuture;
    } finally {
      _isRetryingModel = false;
    }
  }

  Future<void> _playDealContentPeekHint() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_scrollController.hasClients) return;

    // Wait a frame so layout (groups / fixed items) has final height.
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted || !_scrollController.hasClients) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;

    // Scroll far enough for THIS deal's full lower content to be visible.
    await _scrollController.animateTo(
      maxExtent,
      duration: Duration(
        milliseconds: (500 + maxExtent * 1.2).clamp(600, 1600).round(),
      ),
      curve: Curves.easeInOut,
    );

    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted || !_scrollController.hasClients) return;

    await _scrollController.animateTo(
      0,
      duration: Duration(
        milliseconds: (500 + maxExtent * 1.2).clamp(600, 1600).round(),
      ),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _runListTapCoachSequence() async {
    if (!_needsListTapHint) return;

    // After install: only first 3 eligible detail opens get the hand gesture.
    final prefs = await SharedPreferences.getInstance();
    final shownCount = prefs.getInt(_kDetailTapHintCountKey) ?? 0;
    if (shownCount >= _kDetailTapHintMaxShows) return;
    await prefs.setInt(_kDetailTapHintCountKey, shownCount + 1);

    if (widget.isDeal) {
      await _playDealContentPeekHint();
    } else {
      await Future.delayed(const Duration(milliseconds: 900));
    }
    if (!mounted || _hasTappedItem) return;
    await _startFlyHandCoach();
  }

  Future<void> _startFlyHandCoach() async {
    if (!mounted || _hasTappedItem || _handFlying || _handArrived) return;

    // Keep scroll near top so the model container stays visible as the start point.
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted || _hasTappedItem) return;

    final modelBox =
        _modelAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox =
        _hintTargetKey.currentContext?.findRenderObject() as RenderBox?;
    if (modelBox == null ||
        targetBox == null ||
        !modelBox.hasSize ||
        !targetBox.hasSize) {
      // Fallback: just show local bounce on text.
      if (mounted) setState(() => _handArrived = true);
      return;
    }

    final modelOrigin = modelBox.localToGlobal(Offset.zero);
    final targetOrigin = targetBox.localToGlobal(Offset.zero);

    // Start slightly below mid of the model container.
    _handStartGlobal = Offset(
      modelOrigin.dx + modelBox.size.width * 0.42,
      modelOrigin.dy + modelBox.size.height * 0.62,
    );
    // Land over the model text.
    _handEndGlobal = Offset(
      targetOrigin.dx + 18,
      targetOrigin.dy + 4,
    );

    setState(() => _handFlying = true);
    await _flyHandCtrl.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _handFlying = false;
      _handArrived = true;
    });

    // After landing, gently reveal the text row if it was below the fold.
    final targetCtx = _hintTargetKey.currentContext;
    if (targetCtx != null && mounted && !_hasTappedItem) {
      await Scrollable.ensureVisible(
        targetCtx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.65,
      );
    }
  }

  Widget _buildFlyingHandOverlay() {
    if (!_handFlying ||
        _handStartGlobal == null ||
        _handEndGlobal == null ||
        _hasTappedItem) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _flyHandCtrl,
      builder: (context, _) {
        final stackBox =
            _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
        if (stackBox == null || !stackBox.hasSize) {
          return const SizedBox.shrink();
        }
        final t = Curves.easeInOutCubic.transform(_flyHandCtrl.value);
        final global = Offset.lerp(_handStartGlobal!, _handEndGlobal!, t)!;
        final local = stackBox.globalToLocal(global);
        // Bigger near model → smaller as it reaches the text.
        final scale = 1.85 - (0.9 * t);
        return Positioned(
          left: local.dx,
          top: local.dy,
          child: IgnorePointer(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: Icon(
                Icons.pan_tool_alt_rounded,
                size: 30,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _scrollController.dispose();
    _flyHandCtrl.dispose();
    _vdFoldCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDescription() async {
    final desc = FirestoreService.getCachedDescriptionForProduct(widget.model.name);
    if (desc != null && desc.isNotEmpty && mounted) {
      setState(() => _description = desc);
    }
  }

  Future<String> _getModelSrc() async {
    String modelPath = _activeModelUrl ?? widget.model.path;
    if (_activeModelUrl == null && _selectedVariation != null) {
      final resolved = FirestoreService.resolveSizeModelUrl(
        widget.sizeModelUrls,
        _selectedVariation,
      );
      if (resolved != null && resolved.isNotEmpty) {
        modelPath = resolved;
      }
    }

    if (modelPath.startsWith('http://') || modelPath.startsWith('https://')) {
      return await FirestoreService.downloadAndCacheModelUrl(modelPath);
    }
    // No local asset GLB fallback — models come from Firebase only.
    return modelPath;
  }

  String _sizeSectionTitle() {
    final label = widget.sizeSelectionLabel.trim();
    if (label.isNotEmpty) return label;
    return 'Variation';
  }



  String _expandSizeName(String name) {
    switch (name.trim().toUpperCase()) {
      case 'M': return 'Medium';
      case 'L': return 'Large';
      case 'S': return 'Small';
      default: return name;
    }
  }

  int _dealQtyFor(String itemUrl) {
    final direct = widget.dealModelQuantities[itemUrl];
    if (direct != null) return direct;
    final norm = FoodMenuItem.normalizeModelKeyPublic(itemUrl);
    if (norm.isEmpty) return 1;
    for (final e in widget.dealModelQuantities.entries) {
      if (FoodMenuItem.normalizeModelKeyPublic(e.key) == norm) return e.value;
    }
    return 1;
  }

  /// Small eye on the row whose 3D model is currently previewed above.
  Widget _modelPreviewEye() {
    return Icon(
      Icons.visibility_outlined,
      size: 16,
      color: AppColors.primary,
    );
  }

  /// Deal: eye only while a 3D model is on top, and only on that exact row.
  bool _showEyeOnDealChoice(int groupIndex, String optionUrl) {
    if (!widget.isDeal || !_hasTappedItem) return false;
    if (_previewIsFixedItem) return false;
    if (_previewGroupIndex != groupIndex) return false;
    return _activeModelUrl == optionUrl;
  }

  bool _showEyeOnDealFixed(String itemUrl) {
    if (!widget.isDeal || !_hasTappedItem) return false;
    if (!_previewIsFixedItem) return false;
    return _activeModelUrl == itemUrl;
  }

  void _parseVariations() {
    final priceStr = widget.model.price;
    if (priceStr.contains('|')) {
      final parts = priceStr.split('|');
      for (var part in parts) {
        final cleanPart = part.trim();
        // Expected format per part (example variants):
        // - "S 590"
        // - "Medium 2 890"
        // - "Small 1 450.5"
        // Logic: "name" can contain digits/spaces, and the *last* number is the price.
        final match = RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*$').firstMatch(cleanPart);
        if (match != null) {
          var rawName = match.group(1)!.trim();
          // Remove currency tokens if admin format includes them in the name part.
          rawName = rawName
              .replaceAll(RegExp(r'\b(Rs|PKR)\b', caseSensitive: false), '')
              .trim();
          final expandedName = _expandSizeName(rawName);
          final price = double.parse(match.group(2)!);
          _variations.add({'name': expandedName, 'price': price});
        }
      }
    } else {
      final match = RegExp(r'(\d+)').firstMatch(priceStr);
      if (match != null) {
        _variations.add({
          'name': 'Regular',
          'price': double.parse(match.group(1)!),
        });
      }
    }

    // Prefer order from Firestore `deal_model_types`, then `size_model_urls`.
    var order = widget.dealModelTypesOrder;
    var sizeUrls = widget.sizeModelUrls ?? const <String, String>{};
    if (order.isEmpty || sizeUrls.isEmpty) {
      final cached = FirestoreService.findCachedProductByName(widget.model.name);
      if (cached != null) {
        if (order.isEmpty) order = cached.dealModelTypesOrder;
        if (sizeUrls.isEmpty) sizeUrls = cached.sizeModelUrls;
      }
    }
    FoodMenuItem.sortVariationsByModelTypesOrder(
      _variations,
      dealModelTypesOrder: order,
      sizeModelUrls: sizeUrls,
    );
  }

  double get _toppingsPrice {
    return _selectedToppings.length * 210.0;
  }

  double get _discountedSelectedPrice =>
      widget.model.discountedFrom(_selectedPriceValue);

  double get _discountAmountOnSelected =>
      widget.model.discountAmountFrom(_selectedPriceValue);

  double get _totalItemPrice => _discountedSelectedPrice + _toppingsPrice;
  double get _totalPrice => _totalItemPrice * _quantity;

  void _showAddToCartToast(BuildContext context) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayEntry = OverlayEntry(
      builder: (context) {
        final wide = MediaQuery.sizeOf(context).width >= 600;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 8,
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 16 : 14,
                  vertical: wide ? 10 : 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.onPrimary,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppColors.onPrimary,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isEditing
                          ? "Item has been updated"
                          : "Item has been added to cart",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: wide ? 14 : 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  Future<void> _playViewByVisidinePulse() async {
    // Deals (and items): reveal label only once per detail visit.
    if (!mounted || !_deviceSupportsAr || _vdPulseRunning || _vdPulsePlayed) {
      return;
    }
    _vdPulseRunning = true;
    _vdPulsePlayed = true;
    try {
      if (_vdFoldCtrl.value < 1.0) {
        await _vdFoldCtrl.animateTo(
          1.0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
      // Slow open so text is easy to read.
      await _vdFoldCtrl.animateTo(
        0.0,
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
      );
      // Hold fully expanded longer.
      await Future<void>.delayed(const Duration(milliseconds: 2800));
      if (!mounted) return;
      // Slow close back to circular logo.
      await _vdFoldCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeInOutCubic,
      );
    } finally {
      _vdPulseRunning = false;
    }
  }

  Future<void> _openViewByVisidine() async {
    final List<FoodModel> arModels = [];
    if (widget.isDeal) {
      final String dealName = widget.model.name;

      int itemQtyFor(String url) {
        final q = widget.dealModelQuantities[url];
        if (q != null && q > 0) return q.clamp(1, 50);
        final key = url.split('/').last.split('?').first.toLowerCase();
        for (final e in widget.dealModelQuantities.entries) {
          final ek = e.key.split('/').last.split('?').first.toLowerCase();
          if (ek == key && e.value > 0) return e.value.clamp(1, 50);
        }
        return 1;
      }

      void addDealUrl(String url) {
        // Choice options may be image paths (jpg/png) — never place those in AR.
        if (!FoodModel.isGlbOrUsdzUrl(url)) return;
        final resolved = FirestoreService.resolveFoodModel(
          url,
          dealGroupName: dealName,
        );
        if (resolved == null) return;
        if (!FoodModel.isGlbOrUsdzUrl(resolved.path)) return;
        final copies = itemQtyFor(url);
        for (int i = 0; i < copies; i++) {
          arModels.add(resolved.copyWith(arQuantity: 1));
        }
      }

      final groupIndices = _selectedGroupOptions.keys.toList()..sort();
      for (final gIndex in groupIndices) {
        final url = _selectedGroupOptions[gIndex];
        if (url == null || url.isEmpty) continue;
        addDealUrl(url);
      }
      for (final url in widget.dealFixedItems) {
        addDealUrl(url);
      }
    } else {
      final sizeUrl = FirestoreService.resolveSizeModelUrl(
        widget.sizeModelUrls,
        _selectedVariation,
      );
      final path = (sizeUrl != null && sizeUrl.isNotEmpty)
          ? sizeUrl
          : widget.model.path;
      if (!FoodModel.isGlbOrUsdzUrl(path)) return;
      arModels.add(
        widget.model.copyWith(
          path: path,
          sizeLabel: _selectedVariation,
          arQuantity: _quantity.clamp(1, 50),
        ),
      );
    }

    final List<FoodModel> modelsToPlace = [];
    if (widget.isDeal) {
      final orderQty = _quantity.clamp(1, 50);
      for (int i = 0; i < orderQty; i++) {
        modelsToPlace.addAll(arModels);
      }
    } else {
      for (final m in arModels) {
        final qty = m.arQuantity.clamp(1, 50);
        for (int i = 0; i < qty; i++) {
          modelsToPlace.add(m.copyWith(arQuantity: 1));
        }
      }
    }

    final List<FoodModel> displayModels = [];
    if (widget.isDeal) {
      final orderQty = _quantity.clamp(1, 50);
      final counts = <String, int>{};
      final samples = <String, FoodModel>{};
      for (final m in arModels) {
        final String cleanedKey = (m.path.trim().isNotEmpty
                ? _cleanModelNameFromUrl(m.path)
                : m.name)
            .trim();
        if (cleanedKey.isEmpty) continue;

        counts[cleanedKey] = (counts[cleanedKey] ?? 0) + 1;
        samples[cleanedKey] = m.copyWith(name: cleanedKey);
      }
      for (final entry in samples.entries) {
        displayModels.add(
          entry.value.copyWith(
            arQuantity: (counts[entry.key]! * orderQty).clamp(1, 50),
          ),
        );
      }
    } else {
      displayModels.addAll(arModels);
    }

    if (modelsToPlace.isEmpty) return;
    await openVisidineAr(
      context,
      dealModels: modelsToPlace,
      displayModels: displayModels,
    );
  }

  Widget _buildViewByVisidineButton() {
    // Original fold animation: logo left, brand text expands to the right.
    const double size = 42;
    const double expandedWidth = 118;

    return AnimatedBuilder(
      animation: _vdFoldCtrl,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_vdFoldCtrl.value);
        final width = size + (expandedWidth - size) * (1 - t);
        // Text folds inward (width + fade + slight horizontal tuck).
        final textFactor = Curves.easeIn.transform(1 - t).clamp(0.0, 1.0);
        final textOpacity = (1 - t * 1.4).clamp(0.0, 1.0);

        return GestureDetector(
          onTap: _openViewByVisidine,
          child: Container(
            width: width,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.matteBlack,
              borderRadius: BorderRadius.circular(size / 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/visidine_logo.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: textFactor,
                    child: Opacity(
                      opacity: textOpacity,
                      child: Transform.translate(
                        offset: Offset(-6 * t, 0),
                        child: Transform(
                          alignment: Alignment.centerLeft,
                          transform: Matrix4.diagonal3Values(
                            math.max(0.001, 1 - t * 0.55),
                            1,
                            1,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8, right: 10),
                            child: VisidineBrandText(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _pinnedModelHeight(bool show3D, {double? overrideHeight}) {
    if (overrideHeight != null) return overrideHeight;
    // Fixed size — must NOT grow when the lower sheet is scrolled.
    return 400;
  }

  Widget _buildCircularChromeButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = AppColors.primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.matteBlack,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  Future<void> _openModelFullscreen() async {
    if (_modelFullscreenOpen) return;
    _topOverscrollAcc = 0;
    _settledAtTopReady = false;
    setState(() => _modelFullscreenOpen = true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close model',
      barrierColor: AppColors.matteBlack.withOpacity(0.98),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) > 280) {
                        Navigator.of(ctx).pop();
                      }
                    },
                    child: Center(
                      child: FutureBuilder<String>(
                        future: _modelSrcFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: _BoxCornersMiniLoader(size: 56),
                            );
                          }
                          final modelSrc = snapshot.data ?? '';
                          if (!_isUsableModelSrc(modelSrc)) {
                            return const Center(
                              child: _BoxCornersMiniLoader(size: 56),
                            );
                          }
                          return _ModelViewerWithCornersLoader(
                            src: modelSrc,
                            alt: widget.model.name,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 16,
                  child: _buildCircularChromeButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        );
      },
    );
    if (mounted) setState(() => _modelFullscreenOpen = false);
  }

  /// Fullscreen only after sheet has already finished scrolling to the top,
  /// then a *new* upward pull. Normal scrolling to the top must complete first.
  bool _handleTopPullToFullscreen(ScrollNotification n, bool show3D) {
    if (!show3D || _modelFullscreenOpen || !_scrollController.hasClients) {
      return false;
    }

    final metrics = n.metrics;
    final atTop = metrics.pixels <= (metrics.minScrollExtent + 0.5);

    // Left the top — cancel any pending fullscreen gesture.
    if (!atTop) {
      _settledAtTopReady = false;
      _topOverscrollAcc = 0;
      return false;
    }

    // Scroll fully finished at top → now ready for a separate new pull.
    if (n is ScrollEndNotification) {
      _settledAtTopReady = true;
      _topOverscrollAcc = 0;
      return false;
    }

    // Same gesture that arrived at top must NOT open fullscreen.
    if (!_settledAtTopReady) {
      _topOverscrollAcc = 0;
      return false;
    }

    // New finger drag past the top edge → open model fullscreen.
    if (n is OverscrollNotification &&
        n.overscroll < 0 &&
        n.dragDetails != null) {
      _topOverscrollAcc += -n.overscroll;
      if (_topOverscrollAcc >= 56) {
        _topOverscrollAcc = 0;
        _settledAtTopReady = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openModelFullscreen();
        });
      }
    }
    return false;
  }

  Widget _buildModelMedia(bool show3D) {
    // Keep detail model mounted even while fullscreen overlay is open.
    if (show3D) {
      return FutureBuilder<String>(
        future: _modelSrcFuture,
        builder: (context, snapshot) {
          final shimmer = ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Center(child: _BoxCornersMiniLoader(size: 56)),
            ),
          );
          if (snapshot.connectionState == ConnectionState.waiting) {
            return shimmer;
          }
          final modelSrc = snapshot.data ?? '';
          if (!_isUsableModelSrc(modelSrc)) {
            return shimmer;
          }
          return _ModelViewerWithCornersLoader(
            src: modelSrc,
            alt: widget.model.name,
            onLoaded: _playViewByVisidinePulse,
          );
        },
      );
    }

    // Deal choice without .glb → show that option's image path.
    final previewImage = (widget.isDeal &&
            _hasTappedItem &&
            _activeModelUrl != null &&
            _activeModelUrl!.trim().isNotEmpty &&
            !FoodModel.isGlbOrUsdzUrl(_activeModelUrl))
        ? _activeModelUrl!.trim()
        : widget.model.imagePath;

    if (previewImage.startsWith('http://') ||
        previewImage.startsWith('https://')) {
      return LocalCachedImage(
        imageUrl: previewImage,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        placeholder: const Shimmer.rectangular(
          width: double.infinity,
          height: 400,
        ),
        errorWidget: const Center(
          child: Icon(Icons.fastfood_outlined, color: Colors.grey, size: 64),
        ),
      );
    }
    if (previewImage.isEmpty) {
      return const Center(
        child: Icon(Icons.fastfood_outlined, color: Colors.grey, size: 64),
      );
    }
    return Image.asset(previewImage, fit: BoxFit.contain);
  }

  /// Deal may still open AR when fixed/.glb choices exist, even if the
  /// current preview is a non-model image (e.g. drink photo).
  bool get _canOpenVisidine {
    if (!_deviceSupportsAr) return false;
    if (!widget.isDeal) {
      return widget.model.is3DAvailable ||
          FoodModel.isGlbOrUsdzUrl(
            FirestoreService.resolveSizeModelUrl(
                  widget.sizeModelUrls,
                  _selectedVariation,
                ) ??
                '',
          );
    }
    for (final url in widget.dealFixedItems) {
      if (FoodModel.isGlbOrUsdzUrl(url)) return true;
    }
    for (final url in _selectedGroupOptions.values) {
      if (FoodModel.isGlbOrUsdzUrl(url)) return true;
    }
    return FoodModel.isGlbOrUsdzUrl(widget.model.path);
  }

  /// Same trailing inset as AppBar cart (`margin: right 12`) so heart /
  /// Visidine sit in one vertical column under the cart icon.
  static const double _trailingIconInset = 12;

  Widget _buildPinnedModelHero({
    required bool show3D,
    double? overrideHeight,
    bool desktopSplit = false,
  }) {
    // Must cover the sheet's top radius so rounded corners don't
    // reveal the lighter AR stage color underneath.
    final sheetOverlap = desktopSplit ? 0.0 : 28.0;
    final height = _pinnedModelHeight(show3D, overrideHeight: overrideHeight);

    return Container(
      key: _modelAreaKey,
      height: height,
      width: double.infinity,
      // Same as scaffold / body stack behind the details sheet.
      color: AppColors.cardBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                desktopSplit ? 24 : 0,
                desktopSplit ? 16 : 8,
                desktopSplit ? 24 : 0,
                sheetOverlap + (desktopSplit ? 16 : 8),
              ),
              child: _buildModelMedia(show3D),
            ),
          ),
          if (_canOpenVisidine)
            Positioned(
              bottom: sheetOverlap + 6,
              // Visidine is 42 wide vs cart/heart 36 — offset so centers match.
              right: _trailingIconInset - 3,
              child: _buildViewByVisidineButton(),
            ),
          if (show3D)
            Positioned(
              top: 16,
              right: _trailingIconInset,
              child: _buildCircularChromeButton(
                icon: Icons.fullscreen_rounded,
                iconColor: AppColors.textPrimary,
                onTap: () {
                  AppHaptics.selection();
                  _openModelFullscreen();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailsSheet({required bool desktopSplit}) {
    return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(desktopSplit ? 0.0 : 28.0),
                    topRight: Radius.circular(desktopSplit ? 0.0 : 28.0),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                      child: ColoredBox(
                        color: AppColors.matteBlack,
                        child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  const SizedBox(height: 8),
                  Text(
                    widget.model.name,
                    style: TextStyle(
                      fontSize: desktopSplit ? 28 : 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  if (_description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _description,
                      style: TextStyle(
                        fontSize: desktopSplit ? 15 : 12,
                        color: Colors.white,
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (widget.model.hasDiscount && _selectedPriceValue > 0) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          "Rs ${_discountedSelectedPrice.toInt()}",
                          style: TextStyle(
                            fontSize: desktopSplit ? 20 : 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Rs ${_selectedPriceValue.toInt()}",
                          style: TextStyle(
                            fontSize: desktopSplit ? 13 : 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const Spacer(),
                        DiscountBadge(
                          label: widget.model.isPercentDiscount
                              ? '${widget.model.discountValue.toInt()}% OFF'
                              : 'Rs ${_discountAmountOnSelected.toInt()} OFF',
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      "Rs ${_selectedPriceValue.toInt()}",
                      style: TextStyle(
                        fontSize: desktopSplit ? 20 : 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Deal Choice Groups first, then included/static items below
                  if (widget.isDeal && widget.dealGroups.isNotEmpty) ...[
                    ...List.generate(widget.dealGroups.length, (gIndex) {
                      final group = widget.dealGroups[gIndex];
                      final groupTitle =
                          group.title.trim().isNotEmpty ? group.title.trim() : 'Select One';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  groupTitle,
                                  style: TextStyle(
                                    fontSize: desktopSplit ? 13 : 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: AppColors.flameGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  "REQUIRED",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children: group.options.asMap().entries.map((entry) {
                              final optionIndex = entry.key;
                              final option = entry.value;
                              final optionUrl = option.url;
                              final optionName = option.name.trim().isNotEmpty
                                  ? option.name.trim()
                                  : _cleanModelNameFromUrl(optionUrl);
                              final isSelected = _selectedGroupOptions[gIndex] == optionUrl;
                              final showTapHint = _shouldShowDealTapHintOnChoice(
                                gIndex,
                                optionIndex,
                              );

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (isSelected && _activeModelUrl == optionUrl && _previewGroupIndex == gIndex) return;
                                  AppHaptics.selection();
                                  setState(() {
                                    _selectedGroupOptions[gIndex] = optionUrl;
                                    _touchedDealGroupIndices.add(gIndex);
                                    _activeModelUrl = optionUrl;
                                    _hasTappedItem = true;
                                    _previewGroupIndex = gIndex;
                                    _previewIsFixedItem = false;
                                    if (FoodModel.isGlbOrUsdzUrl(optionUrl)) {
                                      _reloadModelSrc();
                                    }
                                  });
                                },
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 17,
                                          height: 17,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: isSelected
                                              ? Center(
                                                  child: Container(
                                                    width: 9,
                                                    height: 9,
                                                    decoration: const BoxDecoration(
                                                      color: AppColors.primary,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _itemNameWithTapHint(
                                            text: optionName,
                                            showHint: showTapHint,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                        if (_showEyeOnDealChoice(gIndex, optionUrl)) ...[
                                          const SizedBox(width: 8),
                                          _modelPreviewEye(),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.divider,
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }),
                  ],

                  // Included / static items below choice groups
                  if (widget.isDeal && widget.dealFixedItems.isNotEmpty) ...[
                    const Text(
                      "Included in deal",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...widget.dealFixedItems.asMap().entries.map((entry) {
                      final fixedIndex = entry.key;
                      final itemUrl = entry.value;
                      final itemName = _cleanModelNameFromUrl(itemUrl);
                      final itemQty = _dealQtyFor(itemUrl);
                      final showTapHint = _shouldShowDealTapHintOnFixed(fixedIndex);

                      return GestureDetector(
                        onTap: () {
                          if (_activeModelUrl == itemUrl && _previewIsFixedItem) return;
                          AppHaptics.selection();
                          setState(() {
                            _activeModelUrl = itemUrl;
                            _hasTappedItem = true;
                            _previewIsFixedItem = true;
                            _previewGroupIndex = null;
                            if (FoodModel.isGlbOrUsdzUrl(itemUrl)) {
                              _reloadModelSrc();
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            children: [
                              Container(
                                width: 17,
                                height: 17,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _itemNameWithTapHint(
                                  text: itemQty > 1 ? "$itemQty $itemName" : itemName,
                                  showHint: showTapHint,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              if (_showEyeOnDealFixed(itemUrl)) ...[
                                const SizedBox(width: 8),
                                _modelPreviewEye(),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  if (_variations.length > 1) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _sizeSectionTitle(),
                          style: TextStyle(
                            fontSize: desktopSplit ? 14 : 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: AppColors.flameGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "REQUIRED",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    ..._variations.asMap().entries.map((entry) {
                      final vIndex = entry.key;
                      final v = entry.value;
                      final isSelected = _selectedVariation == v['name'];
                      final sizeName = v['name']?.toString() ?? '';
                      final showTapHint = _shouldShowSizeTapHint(vIndex);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (isSelected) return;
                          AppHaptics.selection();
                          setState(() {
                            _selectedVariation = v['name'];
                            _selectedPriceValue = v['price'];
                            _activeModelUrl = null;
                            _hasTappedItem = true;
                            _reloadModelSrc();
                          });
                        },
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 17,
                                  height: 17,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Center(
                                          child: Container(
                                            width: 9,
                                            height: 9,
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _itemNameWithTapHint(
                                    text: sizeName,
                                    showHint: showTapHint,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                if (isSelected) ...[
                                  _modelPreviewEye(),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  "Rs ${widget.model.discountedFrom((v['price'] as double)).toInt()}",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 24),
                  ],

                  const SizedBox(height: 120),
                        ],
                      ),
                    ),
                  ],
                ),
                      ),
                    ),
                  ],
                ),
              );
  }


  void _onAddOrUpdatePressed() {
    if (_selectedVariation == null && !widget.isDeal) return;
    List<String>? dealOptions;
    if (widget.isDeal) {
      dealOptions = [];
      final groupIndices = _selectedGroupOptions.keys.toList()..sort();
      for (final gIndex in groupIndices) {
        final url = _selectedGroupOptions[gIndex];
        if (url == null || url.isEmpty) continue;
        dealOptions.add(_cleanModelNameFromUrl(url));
      }
    }

    if (widget.isEditing) {
      _cart.updateItem(
        widget.model,
        widget.initialVariation,
        widget.initialToppings ?? {},
        _selectedVariation,
        _selectedToppings,
        _quantity,
        oldDealOptions: widget.initialDealOptions,
        newDealOptions: dealOptions,
      );
    } else {
      _cart.addToCart(
        widget.model,
        variation: _selectedVariation,
        toppings: _selectedToppings,
        dealOptions: dealOptions,
        quantity: _quantity,
      );
    }
    _showAddToCartToast(context);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
    setState(() {});
  }

  Widget _buildQtyAddCartBar({required bool desktop}) {
    final tablet = ResponsiveHelper.isTablet(context);
    final qtyW = desktop ? 96.0 : (tablet ? 84.0 : 110.0);
    final addButton = InkWell(
      onTap: (_selectedVariation == null && !widget.isDeal)
          ? null
          : _onAddOrUpdatePressed,
      child: Opacity(
        opacity: (_selectedVariation == null && !widget.isDeal) ? 0.6 : 1.0,
        child: Container(
          height: 46,
          width: desktop
              ? 210
              : (tablet ? 160 : null),
          decoration: BoxDecoration(
            gradient: AppColors.flameGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isEditing ? 'UPDATE ' : 'ADD ',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                Text(
                  'Rs ${_totalPrice.toInt()}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final qty = Container(
      height: 46,
      width: qtyW,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, color: AppColors.textPrimary, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
            onPressed: () {
              if (_quantity > 1) setState(() => _quantity--);
            },
          ),
          Text(
            "$_quantity",
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textPrimary, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
            onPressed: () => setState(() => _quantity++),
          ),
        ],
      ),
    );

    if (desktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          qty,
          const SizedBox(width: 10),
          addButton,
        ],
      );
    }

    if (tablet) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          qty,
          const SizedBox(width: 8),
          addButton,
        ],
      );
    }

    return Row(
      children: [
        qty,
        const SizedBox(width: 12),
        Expanded(child: addButton),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final show3D = widget.isDeal
        ? (_hasTappedItem && FoodModel.isGlbOrUsdzUrl(_activeModelUrl))
        : widget.model.is3DAvailable;
    final wide = ResponsiveHelper.isDesktop(context);

    final headerBg =
        widget.asDialog ? AppColors.matteBlack : AppColors.cardBackground;

    return Scaffold(
      backgroundColor: headerBg,
      appBar: AppBar(
        backgroundColor: headerBg,
        elevation: 0,
        toolbarHeight: 56,
        centerTitle: true,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actionsPadding: EdgeInsets.zero,
        automaticallyImplyLeading: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: headerBg,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: widget.asDialog
            ? IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        // Title only — no location subtitle
        title: Text(
          widget.isEditing ? "Edit Item" : "Choose Item",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: _trailingIconInset),
            child: AnimatedBuilder(
              animation: _cart,
              builder: (context, _) {
                final badge = _cart.totalItemsCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '${_cart.totalItemsCount}',
                          style: const TextStyle(
                            color: AppColors.matteBlack,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : null;

                if (wide) {
                  return HoverExpandHeaderIcon(
                    icon: AppCartIcons.outlined,
                    label: 'Cart',
                    iconColor: AppColors.textPrimary,
                    size: 38,
                    iconSize: 20,
                    labelFontSize: 14,
                    backgroundColor: Colors.transparent,
                    borderColor: AppColors.border,
                    labelOnRight: true,
                    badge: badge,
                    onTap: () {
                      AppNavigation.openCart(context);
                      // Refresh badge after panel closes
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted) setState(() {});
                      });
                    },
                  );
                }

                return GestureDetector(
                  onTap: () {
                    AppNavigation.openCart(context);
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) setState(() {});
                    });
                  },
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Stack(
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.border,
                                width: 1.5,
                              ),
                            ),
                            child: const AppCartIcon(
                              color: AppColors.textPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                        if (badge != null)
                          Positioned(top: 0, right: 0, child: badge),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: ColoredBox(
        color: AppColors.cardBackground,
        child: Stack(
        key: _bodyStackKey,
        children: [
          if (wide)
            LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildPinnedModelHero(
                        show3D: show3D,
                        overrideHeight: constraints.maxHeight,
                        desktopSplit: true,
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(
                            MediaQuery.textScalerOf(context).scale(1.0) * 1.05,
                          ),
                        ),
                        child: ColoredBox(
                          color: AppColors.matteBlack,
                          child: Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  physics: const ClampingScrollPhysics(
                                    parent: AlwaysScrollableScrollPhysics(),
                                  ),
                                  child: _buildDetailsSheet(desktopSplit: true),
                                ),
                              ),
                              SafeArea(
                                top: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                                  child: _buildQtyAddCartBar(desktop: true),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          else
            NotificationListener<ScrollNotification>(
              onNotification: (n) => _handleTopPullToFullscreen(n, show3D),
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _pinnedModelHeight(show3D) - 28,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: _pinnedModelHeight(show3D),
                        child: _buildPinnedModelHero(
                          show3D: show3D,
                          ),
                      ),
                    ),
                    _buildDetailsSheet(desktopSplit: false),
                  ],
                ),
              ),
            ),
          _buildFlyingHandOverlay(),
        ],
      ),
      ),
      bottomNavigationBar: wide
          ? null
          : ColoredBox(
              color: AppColors.matteBlack,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
                  child: _buildQtyAddCartBar(desktop: false),
                ),
              ),
            ),
    );
  }
}
