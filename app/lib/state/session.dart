import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局会话：后端地址、token、用户、空间、主题。
/// 数据持久化在本地（shared_preferences），App 重启后自动恢复。
class Session {
  Session._();
  static final Session instance = Session._();

  static const _kBaseUrl = 'baseUrl';
  static const _kToken = 'token';
  static const _kThemeIndex = 'themeIndex';

  /// 默认后端地址：可用 --dart-define=API_BASE_URL=... 在构建时覆盖（如在线 Demo）
  String baseUrl = const String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://localhost:3000');
  String? token;
  Map<String, dynamic>? user;
  Map<String, dynamic>? space;
  int themeIndex = 0;

  /// 主题变化通知（main 用 ValueListenableBuilder 重建 MaterialApp）
  static final ValueNotifier<int> themeNotifier = ValueNotifier(0);

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs?.getString(_kBaseUrl) ?? baseUrl;
    token = _prefs?.getString(_kToken);
    themeIndex = _prefs?.getInt(_kThemeIndex) ?? 0;
    themeNotifier.value = themeIndex;
  }

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Future<void> saveBaseUrl(String url) async {
    baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    await _prefs?.setString(_kBaseUrl, baseUrl);
  }

  Future<void> setToken(String t) async {
    token = t;
    await _prefs?.setString(_kToken, t);
  }

  Future<void> setThemeIndex(int index) async {
    themeIndex = index;
    themeNotifier.value = index;
    await _prefs?.setInt(_kThemeIndex, index);
  }

  Future<void> clear() async {
    token = null;
    user = null;
    space = null;
    await _prefs?.remove(_kToken);
  }
}
