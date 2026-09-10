/// 把后端 photo.filePath 转成完整可访问的图片 URL。
/// 兼容三种历史格式：
///  - "uploads/xxx.jpg"          → baseUrl/uploads/xxx.jpg
///  - "http(s)://.../xxx.jpg"    → 原样
///  - "xxx.jpg" / "/xxx.jpg"     → baseUrl/uploads/xxx.jpg
/// [thumbWidth] 非空时返回服务端缩略图地址（按需生成 + 缓存，列表/照片墙用）
String photoUrl(String baseUrl, String filePath, {int? thumbWidth}) {
  final fp = filePath.trim();
  final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
  if (fp.startsWith('http://') || fp.startsWith('https://')) {
    if (thumbWidth == null) return fp;
    // 远端完整 URL 不做缩略（交给原服务）
    return fp;
  }
  final last = fp.split('/').last;
  if (last.isEmpty) return '';
  if (thumbWidth != null) return '$cleanBase/thumb/$last?w=$thumbWidth';
  return '$cleanBase/uploads/$last';
}