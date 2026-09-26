import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final ShapeBorder shapeBorder;

  const Shimmer.rectangular({
    super.key,
    required this.width,
    required this.height,
    this.shapeBorder = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  });

  const Shimmer.circular({
    super.key,
    required this.width,
    required this.height,
    this.shapeBorder = const CircleBorder(),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dark-theme shimmer aligned with matte / card surfaces.
    const base = AppColors.cardBackground; // #1C1C1E
    const highlight = AppColors.surfaceElevated; // #242426
    const edge = AppColors.border; // #2E2E30

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: ShapeDecoration(
            shape: widget.shapeBorder,
            gradient: LinearGradient(
              colors: const [
                base,
                edge,
                highlight,
                edge,
                base,
              ],
              stops: const [
                0.0,
                0.35,
                0.5,
                0.65,
                1.0,
              ],
              begin: Alignment(-1.0 + _controller.value * 2.0, -0.3),
              end: Alignment(1.0 + _controller.value * 2.0, 0.3),
            ),
          ),
        );
      },
    );
  }
}
