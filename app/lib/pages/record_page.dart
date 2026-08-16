import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';
import '../utils/weather.dart';
import 'event_page.dart';
import 'place_picker_page.dart';

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
  PlaceResult? _place;
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
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
      initialDate: _happenedAt.isAfter(DateTime.now()) ? DateTime.now() : _happenedAt,
      firstDate: DateTime(1900),
      // 只能选今天及之前的日期，不允许记录未来的事
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_happenedAt));
    if (time == null || !mounted) return;
    setState(() {
      _happenedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickPlace() async {
    final result = await Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute(builder: (_) => const PlacePickerPage()),
    );
    if (result != null) setState(() => _place = result);
  }

  Future<void> _manualPlace() async {
    final ctrl = TextEditingController(text: _place?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入地点'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：海边公园', labelText: '地点'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) {
      setState(() => _place = PlaceResult(name: name));
    }
  }

  Future<void> _save() async {
    // 防御：即使日期选择器被绕过，也不允许保存未来时间
    if (_happenedAt.isAfter(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('时间不能晚于现在，请重新选择')));
      return;
    }
    setState(() => _saving = true);
    try {
      // 按日期+地点获取当天天气（失败不阻塞记录）
      Map<String, dynamic>? weather;
      if (_place?.lat != null && _place?.lng != null) {
        weather = await fetchWeather(
          date: _happenedAt,
          lat: _place!.lat!,
          lng: _place!.lng!,
        );
      }
      final data = await ApiClient.createEvent(
        happenedAt: _happenedAt,
        locationName: _place?.name,
        lat: _place?.lat,
        lng: _place?.lng,
        weather: weather,
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
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.place_outlined,
                    color: _place != null ? Theme.of(context).colorScheme.primary : null),
                title: Text(
                  _place != null ? _place!.name : '地点（可选）',
                  style: TextStyle(
                    color: _place != null ? null : Colors.grey.shade600,
                    fontWeight: _place != null ? FontWeight.w600 : null,
                  ),
                ),
                subtitle: _place != null && _place!.lat != null
                    ? Text(
                        '${_place!.lat!.toStringAsFixed(4)}, ${_place!.lng!.toStringAsFixed(4)} · 地图定位',
                        style: const TextStyle(fontSize: 11),
                      )
                    : _place != null
                        ? const Text('手动填写', style: TextStyle(fontSize: 11))
                        : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_place != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _place = null),
                        tooltip: '清除地点',
                      ),
                    TextButton(onPressed: _pickPlace, child: const Text('地图选点')),
                  ],
                ),
                onTap: _pickPlace,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _manualPlace,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('手动输入'),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
                backgroundColor: Theme.of(context).colorScheme.primary,
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
