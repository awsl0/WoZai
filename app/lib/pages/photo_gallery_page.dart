import 'package:flutter/material.dart';
import '../state/session.dart';
import '../utils/photo_url.dart';
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
  late final List<String> _urls = _buildUrls();

  List<String> _buildUrls() {
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return widget.photos
        .map((p) => photoUrl(baseUrl, (p['filePath'] as String? ?? '')))
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
                final url = _urls[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PhotoViewerPage(urls: _urls, initialIndex: i),
                      ),
                    );
                  },
                  child: Hero(
                    tag: 'photo-$url',
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                                  ? child
                                  : Container(
                                      color: Colors.grey.shade200,
                                      child: const Center(
                                          child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))),
                                    ),
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.grey.shade200,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image,
                                    color: Colors.grey, size: 28),
                                SizedBox(height: 2),
                                Text('加载失败',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                          ),
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