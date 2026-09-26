import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Shared elevated bottom CTA used on cart, checkout, map confirm, etc.
class AppBottomActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final double? width;
  final double height;

  const AppBottomActionButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.width,
    this.height = 50,
  });

  /// Comfortable CTA width on wide layouts (not full bleed).
  static double preferredWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 340;
    if (w >= 600) return 300;
    return w - 48;
  }

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: AppColors.flameGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.onPrimary,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize:
                            MediaQuery.sizeOf(context).width < 390 ? 12.5 : 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.onPrimary,
                        letterSpacing:
                            MediaQuery.sizeOf(context).width < 390 ? 0.4 : 1,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );

    if (width != null) return child;
    return child;
  }
}
