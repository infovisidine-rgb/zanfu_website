import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Circular header icon that expands on hover to reveal a short label.
/// [labelOnRight] true → text slides out to the right of the icon
/// (trailing icons in a Row+Spacer naturally shift left when this grows).
class HoverExpandHeaderIcon extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color? borderColor;
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final double labelFontSize;
  final Widget? badge;
  final bool labelOnRight;
  final bool enableHoverExpand;

  const HoverExpandHeaderIcon({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor = Colors.black87,
    this.borderColor,
    this.backgroundColor,
    this.size = 38,
    this.iconSize = 20,
    this.labelFontSize = 12.5,
    this.badge,
    this.labelOnRight = true,
    this.enableHoverExpand = true,
  });

  @override
  State<HoverExpandHeaderIcon> createState() => _HoverExpandHeaderIconState();
}

class _HoverExpandHeaderIconState extends State<HoverExpandHeaderIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final expand = widget.enableHoverExpand && _hovered;
    final idleBg = widget.backgroundColor ?? Colors.transparent;
    final idleBorder = widget.borderColor ?? Colors.transparent;
    final hoverGold = expand;

    final circleBg = hoverGold ? AppColors.primary : idleBg;
    final circleBorder = hoverGold ? AppColors.primary : idleBorder;
    final glyphColor = hoverGold ? AppColors.matteBlack : widget.iconColor;
    final labelColor = hoverGold ? AppColors.matteBlack : Colors.white;

    final iconCore = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleBg,
                border: Border.all(color: circleBorder),
              ),
              child: Icon(
                widget.icon,
                color: glyphColor,
                size: widget.iconSize,
              ),
            ),
          ),
          if (widget.badge != null)
            Positioned(top: 2, right: 2, child: widget.badge!),
        ],
      ),
    );

    final label = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: widget.labelOnRight
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: expand
          ? Padding(
              padding: EdgeInsets.only(
                left: widget.labelOnRight ? 10 : 0,
                right: widget.labelOnRight ? 12 : 10,
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: labelColor,
                  fontSize: widget.labelFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );

    final rowChildren = widget.labelOnRight
        ? <Widget>[iconCore, label]
        : <Widget>[label, iconCore];

    return MouseRegion(
      onEnter: widget.enableHoverExpand
          ? (_) => setState(() => _hovered = true)
          : null,
      onExit: widget.enableHoverExpand
          ? (_) => setState(() => _hovered = false)
          : null,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: widget.size,
          padding: EdgeInsets.symmetric(horizontal: expand ? 2 : 0),
          decoration: BoxDecoration(
            color: hoverGold ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.size / 2),
            border: hoverGold
                ? Border.all(color: AppColors.primary)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: rowChildren,
          ),
        ),
      ),
    );
  }
}
