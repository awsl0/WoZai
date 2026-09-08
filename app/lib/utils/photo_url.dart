/// 把后端 photo.filePath 转成完整可访问的图片 URL。
/// 兼容三种历史格式：
///  - "uploads/xxx.jpg"          → baseUrl/uploads/xxx.jpg
///  - "http(s)://.../xxx.jpg"    → 原样
///  - "xxx.jpg" / "/xxx.jpg"     → baseUrl/uploads/xxx.jpg
String photoUrl(String baseUrl, String filePath) {
  final fp = filePath.trim();
  if (fp.startsWith('http://') || fp.startsWith('https://')) return fp;
  final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final last = fp.split('/').last;
  if (last.isEmpty) return '';
  return '$cleanBase/uploads/$last';
}