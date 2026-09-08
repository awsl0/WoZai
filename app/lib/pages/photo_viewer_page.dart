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
      child: Image.network(
        widget.url,
        fit: BoxFit.contain,
        key: ValueKey('img-$_tick'),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: Colors.white70)),
        errorBuilder: (_, _, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, color: Colors.white54, size: 48),
              const SizedBox(height: 8),
              const Text('图片加载失败，点击重试',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}