import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class FlameIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const FlameIcon({super.key, required this.icon, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => AppColors.flameGradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Icon(icon, size: size),
    );
  }
}
