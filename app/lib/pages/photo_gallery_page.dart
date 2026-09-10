import 'package:flutter/material.dart';
import '../state/session.dart';
import '../utils/photo_url.dart';
import '../widgets/net_img.dart';
import 'photo_viewer_page.dart';

/// 照片墙：展示所有记录里的照片（网格），点击放大查看
class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key, required this.photos});

  /// 所有照片，元素含 filePath / eventId / happenedAt / locationName / note
  final List<Map<String, dynamic>> photos;

  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  late final List<String> _fullUrls = _buildUrls();
  late final List<String> _thumbUrls = _buildThumbUrls();

  List<String> _buildUrls() {
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return widget.photos
        .map((p) => photoUrl(baseUrl, (p['filePath'] as String? ?? '')))
        .toList();
  }

  /// 网格用缩略图（480px，服务端按需生成）——大幅减少流量和解码内存
  List<String> _buildThumbUrls() {
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return widget.photos
        .map((p) =>
            photoUrl(baseUrl, (p['filePath'] as String? ?? ''), thumbWidth: 480))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Scaffold(
      appBar: AppBar(title: Text('照片（${photos.length} 张）')),
      body: photos.isEmpty
          ? const Center(
              child: Text('还没有照片', style: TextStyle(color: Colors.grey)))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final p = photos[i];
                final thumbUrl = _thumbUrls[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PhotoViewerPage(urls: _fullUrls, initialIndex: i),
                      ),
                    );
                  },
                  child: Hero(
                    tag: 'photo-${_fullUrls[i]}',
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImg(
                          url: thumbUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 480,
                        ),
                        // 左下角：所属事件的日期/地点
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            color: Colors.black54,
                            child: Text(
                              _subtitle(p),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// 照片下的说明：日期 + 地点
  String _subtitle(Map<String, dynamic> p) {
    final parts = <String>[];
    final t = DateTime.tryParse((p['happenedAt'] as String?) ?? '')?.toLocal();
    if (t != null) parts.add('${t.month}月${t.day}日');
    final loc = p['locationName'] as String?;
    if (loc != null && loc.isNotEmpty) parts.add(loc);
    return parts.join(' ');
  }
}