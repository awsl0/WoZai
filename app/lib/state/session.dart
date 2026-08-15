import 'package:shared_preferences/shared_preferences.dart';

/// 全局会话：后端地址、token、用户、空间。
/// 数据持久化在本地（shared_preferences），App 重启后自动恢复。
class Session {
  Session._();
  static final Session instance = Session._();

  static const _kBaseUrl = 'baseUrl';
  static const _kToken = 'token';

  String baseUrl = 'http://localhost:3000';
  String? token;
  Map<String, dynamic>? user;
  Map<String, dynamic>? space;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs?.getString(_kBaseUrl) ?? baseUrl;
    token = _prefs?.getString(_kToken);
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

  Future<void> clear() async {
    token = null;
    user = null;
    space = null;
    await _prefs?.remove(_kToken);
  }
}
