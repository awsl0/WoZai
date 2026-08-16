import 'dart:convert';
import 'package:http/http.dart' as http;

/// 天气描述（Open-Meteo weather_code → 中文 + emoji）
String weatherTextOf(int code) {
  switch (code) {
    case 0:
      return '☀️ 晴';
    case 1:
      return '🌤️ 晴间多云';
    case 2:
      return '⛅ 多云';
    case 3:
      return '☁️ 阴';
    case 45:
    case 48:
      return '🌫️ 雾';
    case 51:
    case 53:
    case 55:
      return '🌦️ 毛毛雨';
    case 56:
    case 57:
      return '🌧️ 冻毛毛雨';
    case 61:
    case 63:
    case 65:
      return '🌧️ 雨';
    case 66:
    case 67:
      return '🌧️ 冻雨';
    case 71:
    case 73:
    case 75:
      return '❄️ 雪';
    case 77:
      return '❄️ 雪粒';
    case 80:
    case 81:
    case 82:
      return '🌦️ 阵雨';
    case 85:
    case 86:
      return '❄️ 阵雪';
    case 95:
    case 96:
    case 99:
      return '⛈️ 雷雨';
    default:
      return '🌡️';
  }
}

/// 按日期 + 坐标获取当天天气（Open-Meteo，无需 API key）
/// 返回 { code, text, temp }，失败返回 null（不阻塞记录）
Future<Map<String, dynamic>?> fetchWeather({
  required DateTime date,
  required double lat,
  required double lng,
}) async {
  final day =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lng'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min'
      '&timezone=auto&start_date=$day&end_date=$day');
  try {
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final daily = data['daily'] as Map<String, dynamic>?;
    if (daily == null) return null;
    final codes = (daily['weather_code'] as List?) ?? [];
    final tmax = (daily['temperature_2m_max'] as List?) ?? [];
    final tmin = (daily['temperature_2m_min'] as List?) ?? [];
    if (codes.isEmpty) return null;
    final code = (codes[0] as num).toInt();
    final maxT = tmax.isNotEmpty ? (tmax[0] as num).round() : null;
    final minT = tmin.isNotEmpty ? (tmin[0] as num).round() : null;
    final temp = maxT != null && minT != null
        ? '$minT°~$maxT°'
        : (maxT != null ? '$maxT°' : null);
    return {'code': code, 'text': weatherTextOf(code), 'temp': temp};
  } catch (_) {
    return null;
  }
}

/// 把 DIY 纪念日按归属拼成显示名（ownerId=自己 → 我的X；ownerId=对方 → 对方昵称的X；null → X 共同）
List<Map<String, dynamic>> displayCustomDates(
  List<dynamic> raw,
  Map<String, dynamic>? me,
  List<dynamic> members,
) {
  String? partnerName;
  for (final m in members) {
    final u = (m as Map)['user'] as Map?;
    if (u?['id'] != me?['id']) {
      partnerName = (u?['nickname'] as String?) ??
          (u?['email'] as String?)?.split('@').first;
      break;
    }
  }
  final myName = (me?['nickname'] as String?) ?? '我';
  return raw.map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    final name = m['name'] as String? ?? '纪念日';
    final ownerId = m['ownerId'] as String?;
    if (ownerId != null && ownerId.isNotEmpty && ownerId == me?['id']) {
      m['name'] = '$myName的$name';
    } else if (ownerId != null && ownerId.isNotEmpty) {
      m['name'] = '${partnerName ?? 'TA'}的$name';
    }
    // ownerId 为空 = 共同，保持原名（如"相识纪念日"）
    return m;
  }).toList();
}
