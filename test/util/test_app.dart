import 'package:flutter/material.dart';

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    platform: TargetPlatform.linux,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    visualDensity: VisualDensity.compact,
  );

  return base.copyWith(
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints.tightFor(height: 40),
      border: const OutlineInputBorder(
        borderSide: BorderSide(width: 1),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(width: 1),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: 18,
        fixedSize: const Size(28, 28),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      ),
    ),
  );
}

Widget testApp(Widget child) {
  return MaterialApp(
    theme: appTheme(),
    home: Scaffold(body: child),
  );
}
