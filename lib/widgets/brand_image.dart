import 'package:flutter/material.dart';

/// Brand PNG (Zanfu / Google / Visidine) from `/brand/` on web.
class BrandImage extends StatelessWidget {
  final String assetPath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final FilterQuality filterQuality;

  const BrandImage({
    super.key,
    required this.assetPath,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
  });

  String get _fileName => assetPath.split('/').last;

  String get _webUrl => '/brand/$_fileName';

  @override
  Widget build(BuildContext context) {
    return Image.network(
      _webUrl,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
    );
  }
}
