import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../constants/ai_styles.dart';

/// 事件详情页：照片 + 时间/地点 + 备注 + AI 生成/重新生成 + 编辑正文 + 删除
class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  Map<String, dynamic>? _event;
  bool _loading = true;
  String? _error;
  bool _generating = false;

  late final TextEditingController _contentCtrl;
  String _style = '温暖';
  bool _usePhotos = true;
  List<String> _customStyleNames = [];

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // 加载自定义文风（生成时可选）
      try {
        final aiData = await ApiClient.request('GET', '/api/settings/ai');
        final styles = (aiData['aiConfig']?['styles'] as List?) ?? [];
        _customStyleNames = styles.map((s) => (s as Map)['name'] as String).toList();
      } catch (_) {
        // 设置读取失败不阻塞事件加载
      }
      final data = await ApiClient.request('GET', '/api/events/${widget.eventId}');
      if (!mounted) return;
      setState(() {
        _event = data['event'] as Map<String, dynamic>;
        _contentCtrl.text = _event?['content'] as String? ?? '';
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final data = await ApiClient.request('POST', '/api/events/${widget.eventId}/generate',
          body: {'style': _style, 'usePhotos': _usePhotos});
      if (!mounted) return;
      setState(() {
        _event = data['event'] as Map<String, dynamic>;
        _contentCtrl.text = _event?['content'] as String? ?? '';
        _generating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日记已生成')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败：${e.message}')));
    }
  }

  Future<void> _saveContent() async {
    try {
      final data = await ApiClient.request('PUT', '/api/events/${widget.eventId}',
          body: {'content': _contentCtrl.text});
      if (!mounted) return;
      setState(() => _event = data['event'] as Map<String, dynamic>);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：${e.message}')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('会连同照片一起删除，且无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.request('DELETE', '/api/events/${widget.eventId}');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _event == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '加载失败'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final e = _event!;
    final photos = (e['photos'] as List?) ?? [];
    final happenedAt = DateTime.tryParse((e['happenedAt'] as String?) ?? '')?.toLocal();
    final location = e['locationName'] as String?;
    final note = e['note'] as String?;
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('事件详情'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete, tooltip: '删除'),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 照片
            if (photos.isNotEmpty)
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final path = (photos[i]['filePath'] as String?) ?? '';
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        '$baseUrl/uploads/${path.split('/').last}',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 220,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            // 时间地点
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(happenedAt != null ? DateFormat('yyyy年M月d日 HH:mm').format(happenedAt) : '',
                    style: TextStyle(color: Colors.grey.shade700)),
                if (location != null && location.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.place_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 2),
                  Text(location, style: TextStyle(color: Colors.grey.shade700)),
                ],
              ],
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('「$note」', style: TextStyle(color: Colors.grey.shade700)),
            ],
            const SizedBox(height: 16),
            // 生成区
            Row(
              children: [
                const Text('日记正文', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                DropdownButton<String>(
                  value: _style,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final name in [...presetStyleNames, ..._customStyleNames])
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (v) => setState(() => _style = v ?? '温暖'),
                ),
              ],
            ),
            if (photos.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('使用照片生成', style: TextStyle(fontSize: 14)),
                subtitle: const Text('模型不支持图片时请关闭（纯文本模式）', style: TextStyle(fontSize: 11)),
                value: _usePhotos,
                onChanged: (v) => setState(() => _usePhotos = v),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentCtrl,
              maxLines: 8,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText: '点击「生成日记」，让 AI 根据照片写一段…',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _generating ? null : _generate,
                    icon: _generating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome),
                    label: Text(e['content'] == null ? '生成日记' : '重新生成'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saveContent,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: const Text('保存修改'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (e['isAiGenerated'] == true)
              Text('此正文由 AI 生成，请核对事实（AI 可能猜测照片外的内容）',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
