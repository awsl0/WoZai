import 'package:flutter/material.dart';

/// 主题定义：名称 + 种子色 + 明暗
class ThemeSpec {
  const ThemeSpec(this.name, this.seed, this.brightness, {this.icon = Icons.palette_outlined});
  final String name;
  final Color seed;
  final Brightness brightness;
  final IconData icon;
}

/// 可用的主题列表（第一项为默认）
const appThemes = [
  ThemeSpec('浪漫粉', Color(0xFFFF6B81), Brightness.light, icon: Icons.favorite_outline),
  ThemeSpec('落日橙', Color(0xFFE8843C), Brightness.light, icon: Icons.wb_sunny_outlined),
  ThemeSpec('清新绿', Color(0xFF3E9B6B), Brightness.light, icon: Icons.eco_outlined),
  ThemeSpec('静谧蓝', Color(0xFF4C6EF5), Brightness.light, icon: Icons.water_drop_outlined),
  ThemeSpec('星空夜', Color(0xFF7C4DFF), Brightness.dark, icon: Icons.nightlight_outlined),
  ThemeSpec('暖棕', Color(0xFF8D6E63), Brightness.light, icon: Icons.coffee_outlined),
];

/// 根据主题规格构建 ThemeData
ThemeData buildTheme(ThemeSpec spec) {
  final scheme = ColorScheme.fromSeed(
    seedColor: spec.seed,
    brightness: spec.brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: spec.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFFFFBFE),
    appBarTheme: AppBarTheme(
      backgroundColor: spec.brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : scheme.surface,
      centerTitle: true,
    ),
  );
}
