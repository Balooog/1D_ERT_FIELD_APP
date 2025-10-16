import 'package:flutter/material.dart';

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
  );

  return base.copyWith(
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        iconSize: WidgetStatePropertyAll<double>(18),
        padding: WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll<Size>(Size(28, 28)),
        fixedSize: WidgetStatePropertyAll<Size>(Size(28, 28)),
        visualDensity: VisualDensity(horizontal: -4, vertical: -4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    menuButtonTheme: const MenuButtonThemeData(
      style: ButtonStyle(
        padding: WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll<Size>(Size(28, 28)),
        fixedSize: WidgetStatePropertyAll<Size>(Size(28, 28)),
        visualDensity: VisualDensity(horizontal: -4, vertical: -4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}
