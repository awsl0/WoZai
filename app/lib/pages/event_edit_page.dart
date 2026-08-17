import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../utils/weather.dart';

/// 编辑记录页：修改时间/地点/备注，增删照片（保存后同步天气）
class EventEditPage extends StatefulWidget {
  const EventEditPage({super.key, required this.eventId, required this.event});

  final String eventId;
  final Map<String, dynamic> event;

  @override
  State<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends State<EventEditPage> {
  final _picker = ImagePicker();
  late DateTime _happenedAt;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _noteCtrl;
  double? _lat;
  double? _lng;

  // 现有照片（带 id）
  late List<Map<String, dynamic>> _existingPhotos;
  // 待删除的现有照片 id
  final List<String> _deletedPhotoIds = [];
  // 新选待上传照片
  final List<Uint8List> _newPhotos = [];
  final List<String> _newPhotoNames = [];

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _happenedAt = DateTime.tryParse((e['happenedAt'] as String?) ?? '')?.toLocal() ?? DateTime.now();
    _locationCtrl = TextEditingController(text: (e['locationName'] as String?) ?? '');
    _noteCtrl = TextEditingController(text: (e['note'] as String?) ?? '');
    _lat = (e['lat'] as num?)?.toDouble();
    _lng = (e['lng'] as num?)?.toDouble();
    _existingPhotos = ((e['photos'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _happenedAt.isAfter(now) ? now : _happenedAt,
      firstDate: DateTime(1900),
      lastDate: now, // 只能选今天及之前
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_happenedAt));
    if (time == null || !mounted) return;
    setState(() {
      _happenedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _addPhotos() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1200);
      if (files.isEmpty) return;
      final total = _existingPhotos.length - _deletedPhotoIds.length + _newPhotos.length + files.length;
      if (total > 9) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('每个事件最多 9 张照片')));
        return;
      }
      for (final f in files) {
        final bytes = await f.readAsBytes();
        setState(() {
          _newPhotos.add(bytes);
          _newPhotoNames.add(f.name);
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择照片失败：${e.message}')));
    }
  }

  void _removeExisting(String photoId) {
    setState(() => _deletedPhotoIds.add(photoId));
  }

  void _removeNew(int index) {
    setState(() {
      _newPhotos.removeAt(index);
      _newPhotoNames.removeAt(index);
    });
  }

  Future<void> _save() async {
    // 防御未来时间
    if (_happenedAt.isAfter(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('时间不能晚于现在，请重新选择')));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 时间或地点变化 → 按新时间/地点重新查天气（失败不阻塞）
      Map<String, dynamic>? weather;
      final loc = _locationCtrl.text.trim();
      if (_lat != null && _lng != null) {
        weather = await fetchWeather(date: _happenedAt, lat: _lat!, lng: _lng!);
      }
      // 1) 更新字段（含天气）
      await ApiClient.request('PUT', '/api/events/${widget.eventId}', body: {
        'happenedAt': _happenedAt.toUtc().toIso8601String(),
        'locationName': loc.isEmpty ? null : loc,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'lat': _lat,
        'lng': _lng,
        if (weather != null) 'weather': weather.toString() == 'null' ? null : _weatherJson(weather),
      });
      // 2) 删除勾选的照片
      for (final pid in _deletedPhotoIds) {
        await ApiClient.deleteEventPhoto(widget.eventId, pid);
      }
      // 3) 上传新增照片
      if (_newPhotos.isNotEmpty) {
        await ApiClient.addEventPhotos(widget.eventId, _newPhotos);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：${e.message}')));
    }
  }

  String _weatherJson(Map<String, dynamic> w) {
    final buf = StringBuffer('{');
    buf.write('"code":${w['code']}');
    buf.write(',"text":"${w['text']}"');
    if (w['temp'] != null) buf.write(',"temp":"${w['temp']}"');
    buf.write('}');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final photos = <Widget>[];
    // 现有照片（未标记删除的）
    for (final p in _existingPhotos) {
      final pid = p['id'] as String? ?? '';
      if (_deletedPhotoIds.contains(pid)) continue;
      final path = (p['filePath'] as String?) ?? '';
      photos.add(Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              '$baseUrl/uploads/${path.split('/').last}',
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 100,
                height: 100,
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _removeExisting(pid),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ));
    }
    // 新选照片
    for (var i = 0; i < _newPhotos.length; i++) {
      photos.add(Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_newPhotos[i], width: 100, height: 100, fit: BoxFit.cover),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _removeNew(i),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ));
    }
    // 添加按钮
    final totalNow = _existingPhotos.length - _deletedPhotoIds.length + _newPhotos.length;
    if (totalNow < 9) {
      photos.add(GestureDetector(
        onTap: _addPhotos,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑记录'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(DateFormat('yyyy年M月d日 HH:mm').format(_happenedAt)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDateTime,
            ),
            const Divider(height: 1),
            // 地点
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: TextField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  hintText: '地点（如：外滩）',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 16),
            // 照片
            Row(
              children: [
                const Text('照片', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('$totalNow/9', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: photos),
            const SizedBox(height: 16),
            // 备注
            const Text('备注', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText: '补充说明（如心情、同行的朋友）',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
