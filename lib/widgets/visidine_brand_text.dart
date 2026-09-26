import 'package:flutter/material.dart';

/// "VISIDINE" wordmark for in-app buttons (all white).
class VisidineBrandText extends StatelessWidget {
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final double height;

  static const letters = <(String, Color)>[
    ('V', Colors.white),
    ('I', Colors.white),
    ('S', Colors.white),
    ('I', Colors.white),
    ('D', Colors.white),
    ('I', Colors.white),
    ('N', Colors.white),
    ('E', Colors.white),
  ];

  const VisidineBrandText({
    super.key,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w900,
    this.letterSpacing = 1.2,
    this.height = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (final (letter, color) in letters)
            TextSpan(
              text: letter,
              style: TextStyle(color: color),
            ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
      ),
    );
  }
}
