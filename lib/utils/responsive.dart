import 'package:flutter/material.dart';

class Responsive {
  static double screenWidth(BuildContext context) => MediaQuery.of(context).size.width;
  static double screenHeight(BuildContext context) => MediaQuery.of(context).size.height;
  
  // Screen size breakpoints
  static bool isSmallPhone(BuildContext context) => screenWidth(context) < 360;
  static bool isPhone(BuildContext context) => screenWidth(context) < 600;
  static bool isTablet(BuildContext context) => screenWidth(context) >= 600 && screenWidth(context) < 900;
  static bool isDesktop(BuildContext context) => screenWidth(context) >= 900;
  
  // Responsive padding
  static double horizontalPadding(BuildContext context) {
    final width = screenWidth(context);
    if (width < 360) return 16;
    if (width < 600) return 20;
    if (width < 900) return 32;
    return 48;
  }
  
  // Responsive font sizes
  static double fontSize(BuildContext context, double baseSize) {
    final width = screenWidth(context);
    if (width < 360) return baseSize * 0.85;
    if (width < 400) return baseSize * 0.92;
    return baseSize;
  }
  
  // Responsive icon sizes
  static double iconSize(BuildContext context, double baseSize) {
    final width = screenWidth(context);
    if (width < 360) return baseSize * 0.8;
    if (width < 400) return baseSize * 0.9;
    return baseSize;
  }
  
  // Responsive container width (for cards, inputs, etc.)
  static double containerWidth(BuildContext context, {double maxWidth = 500}) {
    final width = screenWidth(context);
    if (width < maxWidth + 40) return width - 40;
    return maxWidth;
  }
  
  // Grid column count based on screen width
  static int gridColumns(BuildContext context) {
    final width = screenWidth(context);
    if (width < 400) return 2;
    if (width < 600) return 2;
    if (width < 900) return 3;
    return 4;
  }
  
  // Responsive spacing
  static double spacing(BuildContext context, double baseSpacing) {
    final width = screenWidth(context);
    if (width < 360) return baseSpacing * 0.75;
    if (width < 400) return baseSpacing * 0.85;
    return baseSpacing;
  }
}
