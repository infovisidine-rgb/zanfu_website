import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/disk_cache.dart';

/// Resolves on-disk catalog image path (same layout as [LocalCachedImage]).
class ImageCacheHelper {
  ImageCacheHelper._();

  static String cacheKeyForUrl(String imageUrl) {
    final cleanUrl = imageUrl.split('?').first;
    final hash = imageUrl.hashCode.abs().toString();
    final fileExtension = cleanUrl.split('.').last;
    final extension = fileExtension.length > 4 ? 'png' : fileExtension;
    final safeName = cleanUrl.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'cached_images/${safeName}_$hash.$extension';
  }

  static Future<Uint8List?> cachedBytesForUrl(String imageUrl) async {
    if (imageUrl.isEmpty) return null;
    try {
      final bytes = await DiskCache.readBytes(cacheKeyForUrl(imageUrl));
      if (bytes != null && bytes.isNotEmpty) {
        return Uint8List.fromList(bytes);
      }
    } catch (e) {
      debugPrint('ImageCacheHelper: $e');
    }
    return null;
  }
}

class LocalCachedImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;
  /// When true: only show image if already on disk — never download.
  final bool cacheOnly;

  const LocalCachedImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    required this.placeholder,
    required this.errorWidget,
    this.cacheOnly = false,
  }) : super(key: key);

  @override
  State<LocalCachedImage> createState() => _LocalCachedImageState();
}

class _LocalCachedImageState extends State<LocalCachedImage> {
  Uint8List? _bytes;
  bool _useNetwork = false;
  bool _emptyUrl = false;
  bool _isRetrying = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _checkAndLoadImage();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  @override
  void didUpdateWidget(LocalCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _bytes = null;
      _useNetwork = false;
      _emptyUrl = false;
      _checkAndLoadImage();
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (widget.cacheOnly) return;
    final hasNet = results.any((r) => r != ConnectivityResult.none);
    if (!hasNet || _bytes != null || _useNetwork || _isRetrying || !mounted) {
      return;
    }
    if (widget.imageUrl.isEmpty) return;

    _isRetrying = true;
    debugPrint(
      'LocalCachedImage: internet restored — retrying download for ${widget.imageUrl}',
    );
    try {
      await _checkAndLoadImage();
    } finally {
      _isRetrying = false;
    }
  }

  Future<void> _checkAndLoadImage() async {
    if (widget.imageUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _emptyUrl = true;
          _bytes = null;
          _useNetwork = false;
        });
      }
      return;
    }

    if (widget.cacheOnly) {
      if (mounted) {
        setState(() {
          _emptyUrl = true;
          _useNetwork = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _useNetwork = true;
        _emptyUrl = false;
        _bytes = null;
      });
    }
  }

  Future<void> _onDecodeFailed() async {
    if (widget.cacheOnly) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _emptyUrl = true;
        _useNetwork = false;
      });
      return;
    }
    debugPrint('LocalCachedImage: decode failed, removing corrupt cache');
    try {
      await DiskCache.writeBytes(
        ImageCacheHelper.cacheKeyForUrl(widget.imageUrl),
        const [],
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _bytes = null;
      _useNetwork = false;
    });
    if (!_isRetrying) {
      _isRetrying = true;
      try {
        await _checkAndLoadImage();
      } finally {
        _isRetrying = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_useNetwork && widget.imageUrl.isNotEmpty) {
      return Image.network(
        widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          if (frame == null) return widget.placeholder;
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          if (widget.cacheOnly) return widget.errorWidget;
          return widget.placeholder;
        },
      );
    }

    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          if (widget.cacheOnly) {
            return widget.errorWidget;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onDecodeFailed();
          });
          return widget.placeholder;
        },
      );
    }

    if (_emptyUrl) {
      return widget.cacheOnly ? widget.errorWidget : widget.placeholder;
    }

    return widget.cacheOnly ? widget.errorWidget : widget.placeholder;
  }
}
