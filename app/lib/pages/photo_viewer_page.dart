import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 全屏照片查看器：黑底 + 左右滑动 + 双指缩放 + 显示张数
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  /// 照片完整 URL 列表
  final List<String> urls;
  final int initialIndex;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}
class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _ctrl =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: total,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Hero(
                      tag: 'photo-${widget.urls[i]}',
                      child: PhotoViewerImage(
                        key: ValueKey('pv-${widget.urls[i]}'),
                        url: widget.urls[i],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // 顶部：关闭 + 张数
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  Text('${_index + 1} / $total',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 网络图：加载中转圈，失败提示可点击重试
class PhotoViewerImage extends StatefulWidget {
  const PhotoViewerImage({super.key, required this.url});
  final String url;
  @override
  State<PhotoViewerImage> createState() => _PhotoViewerImageState();
}

class _PhotoViewerImageState extends State<PhotoViewerImage> {
  bool _failed = false;
  int _tick = 0;

  @override
  void didUpdateWidget(covariant PhotoViewerImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _failed = false;
      _tick++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _failed
          ? () => setState(() {
                _failed = false;
                _tick++;
              })
          : null,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit: BoxFit.contain,
        key: ValueKey('img-$_tick'),
        memCacheWidth: 1600, // 限制解码尺寸（大图降采样，减少内存）
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) =>
            const Center(child: CircularProgressIndicator(color: Colors.white70)),
        errorWidget: (_, _, _) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.white54, size: 48),
              SizedBox(height: 8),
              Text('图片加载失败，点击重试',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}