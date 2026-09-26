import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Light grey hand + fingertip click pulse (coach / tap hint).
class TapHandClickHint extends StatefulWidget {
  const TapHandClickHint({super.key});

  @override
  State<TapHandClickHint> createState() => _TapHandClickHintState();
}

class _TapHandClickHintState extends State<TapHandClickHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..repeat(reverse: true);

    _press = Tween<double>(begin: 0, end: 3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 0 = finger up, 1 = pressed — drive the click ripple at the tip.
        final t = _controller.value;
        final rippleSize = 5.0 + (14.0 * t);
        final rippleOpacity = (0.55 * t).clamp(0.0, 0.55);

        return Transform.translate(
          offset: Offset(0, _press.value),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topLeft,
              children: [
                Transform.scale(
                  scale: _scale.value,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.pan_tool_alt_rounded,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                ),
                // Ripple centered on the fingertip of pan_tool_alt (~top-center).
                Positioned(
                  left: 11 - rippleSize / 2,
                  top: 1.5 - rippleSize / 2,
                  child: Opacity(
                    opacity: rippleOpacity,
                    child: Container(
                      width: rippleSize,
                      height: rippleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.textSecondary.withValues(alpha: 0.28),
                        border: Border.all(
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 9.5,
                  top: 0,
                  child: Opacity(
                    opacity: (0.85 * t).clamp(0.0, 0.85),
                    child: Container(
                      width: 3.5,
                      height: 3.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.textSecondary,
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
}
