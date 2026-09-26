import 'package:flutter/material.dart';

class CircularHeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color? borderColor;
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final Widget? badge;

  const CircularHeaderIcon({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor = Colors.black87,
    this.borderColor,
    this.backgroundColor,
    this.size = 38,
    this.iconSize = 20,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: backgroundColor ?? Colors.transparent,
                  border: Border.all(
                    color: borderColor ?? Colors.transparent,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: iconSize),
              ),
            ),
            if (badge != null) Positioned(top: 2, right: 2, child: badge!),
          ],
        ),
      ),
    );
  }
}
