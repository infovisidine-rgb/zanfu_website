import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class FlameGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final Widget? trailing;
  final Color labelColor;

  const FlameGradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.height = 42,
    this.borderRadius = 8,
    this.margin,
    this.trailing,
    this.labelColor = AppColors.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        gradient: AppColors.flameGradient,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: labelColor,
                    letterSpacing: 0.8,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
