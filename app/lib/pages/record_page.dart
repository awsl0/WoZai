import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';
import 'event_page.dart';

/// 记录事件页：选照片 + 时间（可回填）+ 地点 + 备注 → 保存
class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final _picker = ImagePicker();
  final List<Uint8List> _photos = [];
  final List<String> _photoNames = [];

  DateTime _happenedAt = DateTime.now();
  final _locationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1600);
      if (files.isEmpty) return;
      for (final f in files) {
        final bytes = await f.readAsBytes();
        setState(() {
          _photos.add(bytes);
          _photoNames.add(f.name);
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择照片失败：${e.message}')));
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_happenedAt));
    if (time == null || !mounted) return;
    setState(() {
      _happenedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = await ApiClient.createEvent(
        happenedAt: _happenedAt,
        locationName: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        photoBytes: _photos,
      );
      if (!mounted) return;
      final eventId = (data['event'] as Map)['id'] as String;
      // 保存成功 → 进入事件页（可生成日记）
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => EventPage(eventId: eventId),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：${e.message}')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记录此刻')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 照片选择
            if (_photos.isEmpty)
              InkWell(
                onTap: _pickPhotos,
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('选择照片（可选多张）', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    if (i == _photos.length) {
                      return InkWell(
                        onTap: _pickPhotos,
                        child: Container(
                          width: 140,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add, color: Colors.grey),
                        ),
                      );
                    }
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_photos[i], width: 140, height: 140, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _photos.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            // 时间
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('时间'),
              subtitle: Text(
                '${_happenedAt.year}-${_happenedAt.month.toString().padLeft(2, '0')}-${_happenedAt.day.toString().padLeft(2, '0')} '
                '${_happenedAt.hour.toString().padLeft(2, '0')}:${_happenedAt.minute.toString().padLeft(2, '0')}',
              ),
              trailing: TextButton(onPressed: _pickDateTime, child: const Text('修改')),
            ),
            // 地点
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: '地点（可选）',
                prefixIcon: Icon(Icons.place_outlined),
                hintText: '如：海边公园',
              ),
            ),
            const SizedBox(height: 16),
            // 备注
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '一句话 / 主题（可选）',
                prefixIcon: Icon(Icons.edit_note),
                hintText: '如：傍晚一起在海边散步',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B81),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存并生成日记'),
            ),
          ],
        ),
      ),
    );
  }
}
