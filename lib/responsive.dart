import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Responsive utility class for adaptive UI across all device sizes
/// Usage: final r = Responsive(context); then use r.wp(50) for 50% of width
class Responsive {
  final BuildContext context;
  late final double screenWidth;
  late final double screenHeight;
  late final double shortestSide;
  late final double longestSide;
  late final bool isTablet;
  late final bool isPhone;
  late final bool isLandscape;
  late final double textScale;
  late final double _baseWidth;
  late final double _baseHeight;

  // Design base dimensions (standard phone size for reference)
  static const double _designWidth = 375.0;
  static const double _designHeight = 812.0;

  Responsive(this.context) {
    final mediaQuery = MediaQuery.of(context);
    screenWidth = mediaQuery.size.width;
    screenHeight = mediaQuery.size.height;
    shortestSide = math.min(screenWidth, screenHeight);
    longestSide = math.max(screenWidth, screenHeight);
    isLandscape = screenWidth > screenHeight;
    isTablet = shortestSide >= 600;
    isPhone = shortestSide < 600;

    // Calculate scale factors
    _baseWidth = screenWidth / _designWidth;
    _baseHeight = screenHeight / _designHeight;

    // Text scale: blend of width and height scaling, clamped for readability
    textScale = (((_baseWidth + _baseHeight) / 2) * 0.9).clamp(0.8, 1.4);
  }

  /// Width percentage (0-100)
  double wp(double percent) => screenWidth * (percent / 100);

  /// Height percentage (0-100)
  double hp(double percent) => screenHeight * (percent / 100);

  /// Scale a value based on screen width ratio to design width
  double sw(double value) => value * _baseWidth;

  /// Scale a value based on screen height ratio to design height
  double sh(double value) => value * _baseHeight;

  /// Scale value using the smaller dimension (safer for both orientations)
  double scale(double value) => value * math.min(_baseWidth, _baseHeight);

  /// Adaptive scale - uses average of width/height scaling
  double adaptive(double value) => value * ((_baseWidth + _baseHeight) / 2);

  /// Font size scaling - ensures readable text on all devices
  double fontSize(double size) => (size * textScale).clamp(size * 0.7, size * 1.5);

  /// Icon size scaling
  double iconSize(double size) => scale(size).clamp(size * 0.7, size * 1.8);

  /// Padding/margin scaling
  double spacing(double value) => scale(value).clamp(value * 0.5, value * 2.0);

  /// Border radius scaling
  double radius(double value) => scale(value).clamp(value * 0.5, value * 2.0);

  /// Returns appropriate value based on device type
  T device<T>({required T phone, required T tablet}) => isTablet ? tablet : phone;

  /// Returns value based on orientation
  T orientation<T>({required T portrait, required T landscape}) =>
      isLandscape ? landscape : portrait;

  /// Responsive EdgeInsets
  EdgeInsets padding({
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? right,
    double? top,
    double? bottom,
  }) {
    if (all != null) {
      return EdgeInsets.all(spacing(all));
    }
    return EdgeInsets.only(
      left: spacing(left ?? horizontal ?? 0),
      right: spacing(right ?? horizontal ?? 0),
      top: spacing(top ?? vertical ?? 0),
      bottom: spacing(bottom ?? vertical ?? 0),
    );
  }

  /// Responsive SizedBox for width
  SizedBox gapW(double width) => SizedBox(width: spacing(width));

  /// Responsive SizedBox for height
  SizedBox gapH(double height) => SizedBox(height: spacing(height));

  /// Get responsive lesson card dimensions
  Size get lessonCardSize {
    if (isTablet) {
      return Size(wp(35).clamp(280, 400), hp(55).clamp(350, 500));
    }
    // Phone: scale based on available space
    double cardWidth = wp(75).clamp(260, 340);
    double cardHeight = hp(50).clamp(320, 450);
    return Size(cardWidth, cardHeight);
  }

  /// Get responsive bubble size for bubble.dart
  double get bubbleSize {
    double baseSize = shortestSide * 0.62;
    return baseSize.clamp(260, 480);
  }

  /// Get responsive progress circle size
  double get progressCircleSize {
    double baseSize = shortestSide * 0.32;
    return baseSize.clamp(140, 240);
  }

  /// Get responsive slot size for survival mode
  Size get survivalSlotSize {
    double width = sw(40).clamp(32, 55);
    double height = sh(48).clamp(40, 65);
    return Size(width, height);
  }

  /// Get responsive ball radius for game mode
  double get gameBallRadius {
    // Larger balls for better readability of long words
    double radius = shortestSide * 0.18;
    return radius.clamp(75, 130);
  }

  /// Chart heights for statistics
  double get chartHeight {
    return hp(35).clamp(200, 400);
  }

  /// Donut chart height
  double get donutHeight {
    return hp(28).clamp(180, 300);
  }

  /// Heatmap cell size
  double get heatmapSize {
    return sw(28).clamp(20, 40);
  }
}

/// Extension for easy access to Responsive in widgets
extension ResponsiveExtension on BuildContext {
  Responsive get responsive => Responsive(this);
}

/// Responsive text widget that automatically scales
class ResponsiveText extends StatelessWidget {
  final String text;
  final double baseSize;
  final FontWeight? fontWeight;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? letterSpacing;
  final TextStyle? style;

  const ResponsiveText(
    this.text, {
    super.key,
    required this.baseSize,
    this.fontWeight,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.letterSpacing,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: (style ?? const TextStyle()).copyWith(
        fontSize: r.fontSize(baseSize),
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      ),
    );
  }
}

/// Responsive container that adapts its size
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? widthPercent;
  final double? heightPercent;
  final double? minWidth;
  final double? maxWidth;
  final double? minHeight;
  final double? maxHeight;
  final BoxDecoration? decoration;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final AlignmentGeometry? alignment;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.widthPercent,
    this.heightPercent,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.decoration,
    this.padding,
    this.margin,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);

    double? width = widthPercent != null ? r.wp(widthPercent!) : null;
    double? height = heightPercent != null ? r.hp(heightPercent!) : null;

    if (width != null) {
      if (minWidth != null) width = math.max(width, minWidth!);
      if (maxWidth != null) width = math.min(width, maxWidth!);
    }

    if (height != null) {
      if (minHeight != null) height = math.max(height, minHeight!);
      if (maxHeight != null) height = math.min(height, maxHeight!);
    }

    return Container(
      width: width,
      height: height,
      decoration: decoration,
      padding: padding,
      margin: margin,
      alignment: alignment,
      child: child,
    );
  }
}
