import 'package:flutter/material.dart';

/// Breakpoints and shared layout metrics for phone / tablet / desktop web.
class ResponsiveHelper {
  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static bool isMobile(BuildContext context) => screenWidth(context) < 600;

  static bool isSmallMobile(BuildContext context) => screenWidth(context) < 390;

  static bool isTablet(BuildContext context) =>
      screenWidth(context) >= 600 && screenWidth(context) < 1100;

  static bool isDesktop(BuildContext context) => screenWidth(context) >= 1100;

  static bool isWide(BuildContext context) => !isMobile(context);

  static double fontSize(BuildContext context, double baseSize) {
    final scale = isMobile(context) ? 1.0 : (isTablet(context) ? 1.12 : 1.22);
    return baseSize * scale;
  }

  static double horizontalPadding(BuildContext context) {
    final w = screenWidth(context);
    if (w < 600) return 16.0;
    if (w < 900) return 24.0;
    if (w < 1200) return 32.0;
    return 40.0;
  }

  static double contentMaxWidth(BuildContext context) {
    if (isDesktop(context)) return 1280;
    if (isTablet(context)) return 980;
    return screenWidth(context);
  }

  /// Cart / profile / orders side panel width.
  static double cartPanelWidth(BuildContext context) {
    final w = screenWidth(context);
    final half = w * 0.42;
    // Keep room for button content when the browser window is narrowed.
    return half.clamp(300.0, 460.0);
  }

  /// Home grid: 2–4 columns max (never more than 4).
  static int homeGridColumns(BuildContext context) {
    final w = screenWidth(context);
    if (w < 520) return 2;
    if (w < 800) return 3;
    return 4;
  }

  /// Home grid spacing — tighter on phone for shorter scroll distance.
  static double homeGridMainSpacing(BuildContext context) {
    if (isMobile(context)) return 24;
    if (isTablet(context)) return 32;
    return 48;
  }

  static double homeGridCrossSpacing(BuildContext context) {
    if (isMobile(context)) return 16;
    if (isTablet(context)) return 22;
    return 28;
  }

  static double homeCategorySpacing(BuildContext context) {
    if (isMobile(context)) return 32;
    if (isTablet(context)) return 48;
    return 64;
  }

  static double homeGridImageHeightRatio(BuildContext context) {
    if (isMobile(context)) return 0.88;
    return 1.0;
  }

  /// Card height for grid cells: image + text block (avoids bottom overflow).
  static double homeGridMainAxisExtent(BuildContext context, double gridWidth) {
    final cols = homeGridColumns(context);
    final crossSpacing = homeGridCrossSpacing(context);
    final itemWidth = (gridWidth - crossSpacing * (cols - 1)) / cols;
    final imageHeight = itemWidth * homeGridImageHeightRatio(context);
    final textBlock = isMobile(context) ? 132.0 : 152.0;
    return imageHeight + textBlock;
  }

  static double homeGridChildAspectRatio(BuildContext context) {
    // Fallback only — prefer [homeGridMainAxisExtent].
    final cols = homeGridColumns(context);
    if (cols <= 2) return 0.62;
    if (cols == 3) return 0.64;
    return 0.66;
  }

  static double headerLogoHeight(BuildContext context) {
    final w = screenWidth(context);
    if (w < 390) return 44;
    if (w < 400) return 50;
    if (w < 600) return 56;
    if (w < 900) return 68;
    if (w < 1200) return 76;
    return 84;
  }

  static double headerIconCircle(BuildContext context) {
    if (isMobile(context)) return 34;
    if (isTablet(context)) return 36;
    return 38;
  }

  static double headerIconGlyph(BuildContext context) {
    if (isMobile(context)) return 24;
    if (isTablet(context)) return 25;
    return 26;
  }

  static double categoryTabFontSize(BuildContext context) {
    if (isSmallMobile(context)) return 14;
    if (isMobile(context)) return 16.5;
    if (isTablet(context)) return 18;
    return 19;
  }

  static double categoryTitleFontSize(BuildContext context) {
    if (isMobile(context)) return 24;
    if (isTablet(context)) return 28;
    return 32;
  }

  /// Same ratio on all breakpoints so one uploaded banner fits everywhere.
  /// Match upload assets to **3.5 : 1** (e.g. 1400×400).
  static double bannerAspectRatio(BuildContext context) => 3.5;

  static double stickyCategoryTabsHeight(BuildContext context) {
    if (isSmallMobile(context)) return 40;
    if (isMobile(context)) return 48;
    return 52;
  }

  static double categoryTabGap(BuildContext context) {
    if (isSmallMobile(context)) return 8;
    if (isMobile(context)) return 12;
    return 22;
  }

  static double categoryTabPillHeight(BuildContext context) {
    if (isSmallMobile(context)) return 32;
    if (isMobile(context)) return 38;
    return 40;
  }

  static double categoryTabBarPadding(BuildContext context) {
    if (isSmallMobile(context)) return 4;
    if (isMobile(context)) return 6;
    return 12;
  }
}
