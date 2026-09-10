import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 统一的网络图片组件：
///  - 磁盘 + 内存双层缓存（二次打开秒开，不再重复下载）
///  - memCacheWidth 解码降采样（大幅降低内存占用与卡顿）
///  - 统一的加载中/失败样式
class NetImg extends StatelessWidget {
  const NetImg({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
    this.borderRadius,
    this.brokenIconSize = 28,
    this.brokenText,
    this.errorFallback,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BorderRadius? borderRadius;
  final double brokenIconSize;
  final String? brokenText;

  /// 自定义加载失败时的回退组件（如头像用首字母）
  final Widget? errorFallback;

  @override
  Widget build(BuildContext context) {
    final img = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, _) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (_, _, _) =>
          errorFallback ??
          Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image,
                    color: Colors.grey, size: brokenIconSize),
                if (brokenText != null) ...[
                  const SizedBox(height: 2),
                  Text(brokenText!,
                      style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ],
            ),
          ),
    );
    if (borderRadius == null) return img;
    return ClipRRect(borderRadius: borderRadius!, child: img);
  }
}
