import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../state/session.dart';

/// 时间线事件卡片：照片墙 + 正文 + 时间/地点 + 作者
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap});

  final Map<String, dynamic> event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final photos = (event['photos'] as List?) ?? [];
    final content = event['content'] as String?;
    final note = event['note'] as String?;
    final location = event['locationName'] as String?;
    final happenedAt = DateTime.tryParse((event['happenedAt'] as String?) ?? '')?.toLocal();
    final isAi = event['isAiGenerated'] == true;
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 照片墙
              if (photos.isNotEmpty)
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final path = photos[i]['filePath'] as String? ?? '';
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '$baseUrl/uploads/${path.split('/').last}',
                          width: 160,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 160,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              // 标题行：时间 + 地点
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    happenedAt != null ? DateFormat('M月d日 HH:mm').format(happenedAt) : '',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (location != null && location.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.place_outlined, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(location,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                  ],
                ],
              ),
              // 备注（用户原话）
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('「$note」', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ],
              // 正文
              if (content != null && content.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(content, maxLines: 4, overflow: TextOverflow.ellipsis),
                if (isAi) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('AI 生成',
                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('（还没有日记，点进来让 AI 写一段）',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
