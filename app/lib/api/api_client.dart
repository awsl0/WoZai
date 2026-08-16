import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../state/session.dart';

/// REST API 客户端：统一处理 baseUrl、鉴权、JSON、multipart。
class ApiClient {
  /// 请求 JSON 接口，返回解析后的 body（Map 或 List）。
  /// 非 2xx 抛出 [ApiException]。
  static Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final base = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && Session.instance.token != null) {
      headers['Authorization'] = 'Bearer ${Session.instance.token}';
    }

    final http.Request req = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final decoded = _decode(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    throw ApiException(res.statusCode, decoded?['error']?.toString() ?? '请求失败(${res.statusCode})');
  }

  /// 创建事件（multipart：字段 + 照片文件）
  static Future<dynamic> createEvent({
    required DateTime happenedAt,
    double? lat,
    double? lng,
    String? locationName,
    String? note,
    Map<String, dynamic>? weather,
    List<Uint8List> photoBytes = const [],
  }) async {
    final base = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/events');

    final req = http.MultipartRequest('POST', uri);
    if (Session.instance.token != null) {
      req.headers['Authorization'] = 'Bearer ${Session.instance.token}';
    }
    req.fields['happenedAt'] = happenedAt.toUtc().toIso8601String();
    if (lat != null) req.fields['lat'] = lat.toString();
    if (lng != null) req.fields['lng'] = lng.toString();
    if (locationName != null && locationName.isNotEmpty) req.fields['locationName'] = locationName;
    if (note != null && note.isNotEmpty) req.fields['note'] = note;
    if (weather != null) req.fields['weather'] = jsonEncode(weather);
    for (var i = 0; i < photoBytes.length; i++) {
      req.files.add(http.MultipartFile.fromBytes('photos', photoBytes[i], filename: 'photo$i.jpg'));
    }

    final res = await req.send();
    final body = await res.stream.bytesToString();
    final decoded = _decode(body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    throw ApiException(res.statusCode, decoded?['error']?.toString() ?? '请求失败(${res.statusCode})');
  }

  /// 下载（导出 ZIP 用），返回字节
  static Future<Uint8List> download(String path) async {
    final base = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    final headers = <String, String>{};
    if (Session.instance.token != null) {
      headers['Authorization'] = 'Bearer ${Session.instance.token}';
    }
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) throw ApiException(res.statusCode, '下载失败(${res.statusCode})');
    return res.bodyBytes;
  }

  static dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

/// 上传头像（multipart：avatar 文件）→ 返回 avatarPath
Future<String> uploadAvatar(Uint8List bytes, {String filename = 'avatar.jpg'}) async {
  final base = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base/api/auth/avatar');
  final req = http.MultipartRequest('POST', uri)
    ..headers['Authorization'] = 'Bearer ${Session.instance.token}'
    ..files.add(http.MultipartFile.fromBytes('avatar', bytes, filename: filename));
  final streamed = await req.send();
  final res = await http.Response.fromStream(streamed);
  final decoded = _decodeBody(res.body);
  if (res.statusCode >= 200 && res.statusCode < 300) {
    return (decoded?['avatarPath'] as String?) ?? '';
  }
  throw ApiException(res.statusCode, decoded?['error']?.toString() ?? '上传失败(${res.statusCode})');
}

dynamic _decodeBody(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}
