import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../pages/place_picker_page.dart';

/// 定位工具：获取手机当前位置 → 逆地理编码成中文地点名
/// 失败返回 null（不阻塞记录，用户可手动选择/输入）
Future<PlaceResult?> locateCurrent() async {
  try {
    // 1) 定位服务可用？
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    // 2) 权限（Android 6+ 需要运行时授权）
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }
    // 3) 获取坐标（最多等 12 秒）
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    // 4) 逆地理编码（OpenStreetMap Nominatim，免费无需 key）
    final name = await reverseGeocode(pos.latitude, pos.longitude);
    if (name == null) return null;
    return PlaceResult(name: name, lat: pos.latitude, lng: pos.longitude);
  } catch (_) {
    return null;
  }
}

/// 坐标 → 中文地名（Photon/OSM，免费无需 key：优先道路/街道，其次 POI/区/市）
Future<String?> reverseGeocode(double lat, double lng) async {
  final uri = Uri.parse(
      'https://photon.komoot.io/reverse?lon=$lng&lat=$lat&limit=1');
  try {
    final res = await http.get(uri, headers: {
      'User-Agent': 'WoZaiApp/1.2 (lazy-diary-app)',
    }).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final features = (data['features'] as List?) ?? [];
    if (features.isEmpty) return null;
    final p = ((features.first as Map)['properties'] as Map?) ?? {};
    // 优先道路（外滩/南京东路这种适合日记定位），其次 POI 名称、区、市
    final name = (p['street'] ??
            p['name'] ??
            p['district'] ??
            p['city'] ??
            p['state'])
        ?.toString()
        .trim();
    if (name == null || name.isEmpty) return null;
    return name.length > 20 ? (p['district'] ?? p['city'])?.toString() ?? name : name;
  } catch (_) {
    return null;
  }
}
