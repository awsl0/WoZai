import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../theme/app_themes.dart';
import '../constants/ai_styles.dart';
import '../widgets/avatar.dart';

/// 设置页：AI 配置（BYOK）+ 在一起日期 + 导出 + 后端地址 + 登出
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _baseUrlCtrl = TextEditingController(text: Session.instance.baseUrl);
  final _aiBaseUrlCtrl = TextEditingController();
  final _aiKeyCtrl = TextEditingController();
  final _aiModelCtrl = TextEditingController();
  final _aiMaxWaitCtrl = TextEditingController(text: '240');
  final _newStyleNameCtrl = TextEditingController();
  final _newStylePromptCtrl = TextEditingController();
  List<Map<String, dynamic>> _customStyles = [];

  bool _savingAi = false;
  bool _testingAi = false;
  /// 用户是否改动过 API Key（区分 masked 显示值与真实输入）
  bool _aiKeyTouched = false;
  /// 已保存 key 的掩码（如 sk-1***wq），用于输入框提示
  String? _savedKeyMasked;
  bool _exporting = false;
  bool _showStyleForm = false; // 点「添加文风」才显示输入框

  static const _presets = [
    ('通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-vl-max'),
    ('智谱', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4v-plus'),
    ('OpenAI', 'https://api.openai.com/v1', 'gpt-4o'),
  ];

  @override
  void initState() {
    super.initState();
    _loadAiConfig();
    _refreshMe(); // 进入设置页主动刷新用户/空间信息
  }

  /// 刷新当前用户与空间（解决冷启动后 user/space 为 null 的问题）
  Future<void> _refreshMe() async {
    try {
      final me = await ApiClient.request('GET', '/api/auth/me');
      if (!mounted) return;
      setState(() {
        Session.instance.user = me['user'] as Map<String, dynamic>?;
        Session.instance.space = me['space'] as Map<String, dynamic>?;
      });
    } catch (_) {
      // 网络失败时保留现有状态
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _aiBaseUrlCtrl.dispose();
    _aiKeyCtrl.dispose();
    _aiModelCtrl.dispose();
    _aiMaxWaitCtrl.dispose();
    _newStyleNameCtrl.dispose();
    _newStylePromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAiConfig() async {
    try {
      final data = await ApiClient.request('GET', '/api/settings/ai');
      if (!mounted) return;
      final cfg = data['aiConfig'] as Map<String, dynamic>?;
      setState(() {
        if (cfg != null) {
          _aiBaseUrlCtrl.text = cfg['baseUrl'] as String? ?? '';
          _aiModelCtrl.text = cfg['model'] as String? ?? '';
          _aiMaxWaitCtrl.text = (cfg['maxWaitSeconds'] as int? ?? 240).toString();
          _customStyles = (cfg['styles'] as List? ?? []).cast<Map<String, dynamic>>();
          // 已保存的 key 只显示掩码提示，不填入输入框（避免保存时把脱敏值写回覆盖真 key）
          _savedKeyMasked = (cfg['hasApiKey'] == true) ? (cfg['apiKeyMasked'] as String? ?? '') : null;
        }
      });
    } catch (_) {
      // 忽略加载失败，让用户手动填
    }
  }

  /// 测试当前 AI 配置（未改动的 key 用已保存的）
  Future<void> _testAi() async {
    setState(() => _testingAi = true);
    try {
      final r = await ApiClient.request('POST', '/api/settings/ai/test', body: {
        'baseUrl': _aiBaseUrlCtrl.text.trim(),
        if (_aiKeyTouched) 'apiKey': _aiKeyCtrl.text.trim(),
        'model': _aiModelCtrl.text.trim(),
      });
      if (!mounted) return;
      final ok = r?['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '✅ 连接成功（${r?['model'] ?? ''}）：${r?['reply'] ?? ''}'
            : '❌ 测试失败：${r?['error'] ?? '未知错误'}'),
        backgroundColor: ok ? Colors.green.shade700 : null,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 测试失败：${e.message}')));
    } finally {
      if (mounted) setState(() => _testingAi = false);
    }
  }

  Future<void> _saveAi() async {
    setState(() => _savingAi = true);
    try {
      await ApiClient.request('PUT', '/api/settings/ai', body: {
        'baseUrl': _aiBaseUrlCtrl.text.trim(),
        // 用户没输入新 key 时不传，服务器保留已保存的 key
        if (_aiKeyTouched) 'apiKey': _aiKeyCtrl.text.trim(),
        'model': _aiModelCtrl.text.trim(),
        'styles': _customStyles,
        'maxWaitSeconds': int.tryParse(_aiMaxWaitCtrl.text.trim()) ?? 240,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 配置已保存')));
      _loadAiConfig();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：${e.message}')));
    } finally {
      if (mounted) setState(() => _savingAi = false);
    }
  }

  void _addCustomStyle() {
    final name = _newStyleNameCtrl.text.trim();
    final prompt = _newStylePromptCtrl.text.trim();
    if (name.isEmpty || prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写名字和提示词')));
      return;
    }
    if (presetStyleNames.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这个名字与内置文风重名，换个名字')));
      return;
    }
    if (_customStyles.any((s) => s['name'] == name)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已有同名文风')));
      return;
    }
    setState(() {
      _customStyles.add({'name': name, 'prompt': prompt});
      _newStyleNameCtrl.clear();
      _newStylePromptCtrl.clear();
      _showStyleForm = false; // 添加完成收起表单
    });
  }

  void _removeCustomStyle(int index) {
    setState(() => _customStyles.removeAt(index));
  }

  Future<void> _setStartDate() async {
    final current = DateTime.tryParse((Session.instance.space?['startDate'] as String?) ?? '');
    final date = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    try {
      await ApiClient.request('PUT', '/api/space/start-date',
          body: {'startDate': date.toIso8601String()});
      final me = await ApiClient.request('GET', '/api/auth/me');
      Session.instance.space = me['space'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {}); // 刷新「在一起日期」显示
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('在一起日期已更新')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('设置失败：${e.message}')));
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final bytes = await ApiClient.download('/api/export');
      await _saveZip(bytes);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：${e.message}')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveZip(Uint8List bytes) async {
    final date = DateTime.now().toIso8601String().split('T').first;
    final name = 'wozai-export-$date.zip';
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      // 移动端：提示走系统分享（MVP 简化，后续接 share_plus）
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 $name（${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB），移动端保存功能待接入')),
      );
    } else {
      // Web/桌面：下载
      try {
        final bytesData = base64Encode(bytes);
        await Clipboard.setData(ClipboardData(text: bytesData));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出数据已复制到剪贴板（base64），可粘贴保存为 .zip')),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败：当前平台不支持保存文件')),
        );
      }
    }
  }

  /// DIY 纪念日（生日/毕业日等）
  List<Map<String, dynamic>> get _customDates =>
      ((Session.instance.space?['customDates'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  /// 归属标识文本（我的 / TA的 / 共同）
  String _ownerText(Map<String, dynamic> c) {
    final ownerId = c['ownerId'] as String?;
    if (ownerId == null || ownerId.isEmpty) return ''; // 共同
    if (ownerId == Session.instance.user?['id']) return '我 · ';
    return 'TA · ';
  }

  /// 能否删除该纪念日：自己的或共同的可以，对方的不可
  bool _canDelete(Map<String, dynamic> c) {
    final ownerId = c['ownerId'] as String?;
    if (ownerId == null || ownerId.isEmpty) return true; // 共同
    return ownerId == Session.instance.user?['id']; // 只有自己
  }

  /// 保存纪念日列表并刷新空间
  Future<void> _saveCustomDates(List<Map<String, dynamic>> list) async {
    try {
      await ApiClient.request('PUT', '/api/space/custom-dates',
          body: {'customDates': list});
      final me = await ApiClient.request('GET', '/api/auth/me');
      Session.instance.space = me['space'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {});
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：${e.message}')));
    }
  }

  /// 添加纪念日（名称 + 归属 + 日期）
  Future<void> _addCustomDate() async {
    final nameCtrl = TextEditingController();
    DateTime picked = DateTime.now();
    var isShared = false; // true=共同的，false=我的
    final myName = Session.instance.user?['nickname'] as String? ?? '我';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('添加纪念日'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '如：生日 / 毕业日 / 纪念日',
                ),
              ),
              const SizedBox(height: 10),
              // 归属：只能添加自己的或共同的（对方的由对方自己添加）
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: Text('$myName的'),
                    selected: !isShared,
                    onSelected: (_) => setDlg(() => isShared = false),
                  ),
                  ChoiceChip(
                    label: const Text('共同的'),
                    selected: isShared,
                    onSelected: (_) => setDlg(() => isShared = true),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text('${picked.month}月${picked.day}日'),
                trailing: TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: picked,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setDlg(() => picked = d);
                  },
                  child: const Text('选择日期'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final list = List<Map<String, dynamic>>.from(_customDates);
    list.add({
      'name': name,
      'month': picked.month,
      'day': picked.day,
      // 我的 → ownerId=自己；共同的 → null
      'ownerId': isShared ? null : Session.instance.user?['id'],
    });
    await _saveCustomDates(list);
  }

  /// 删除纪念日
  Future<void> _removeCustomDate(int index) async {
    final list = List<Map<String, dynamic>>.from(_customDates)..removeAt(index);
    await _saveCustomDates(list);
  }

  Future<void> _logout() async {
    await Session.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  /// 当前用户是否为空间创建者
  bool get _isOwner {
    final me = Session.instance.user;
    final members = Session.instance.space?['members'] as List? ?? [];
    return members.any((m) =>
        m['role'] == 'owner' && m['user']?['id'] == me?['id']);
  }

  /// 选择并上传头像
  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file == null || !mounted) return;
    try {
      final bytes = await file.readAsBytes();
      final avatarPath = await uploadAvatar(bytes);
      // 更新本地 Session（自己 + 空间成员数据）
      final u = Map<String, dynamic>.from(Session.instance.user ?? {});
      u['avatarPath'] = avatarPath;
      Session.instance.user = u;
      await _refreshMe(); // 刷新空间成员里的头像
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('头像已更新')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('头像上传失败：${e.message}')));
    }
  }

  /// 重新生成邀请码（仅创建者）
  Future<void> _regenerateCode() async {
    try {
      final data = await ApiClient.request('POST', '/api/space/invite');
      final code = data['inviteCode'] as String?;
      if (code == null || !mounted) return;
      setState(() {
        final sp = Map<String, dynamic>.from(Session.instance.space ?? {});
        sp['inviteCode'] = code;
        Session.instance.space = sp;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('邀请码已更新')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：${e.message}')));
    }
  }

  /// 输入邀请码加入空间
  Future<void> _joinSpace() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入空间'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: '6 位邀请码',
            hintText: '如：A8K2M9',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, ctrl.text.trim().toUpperCase()),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    try {
      await ApiClient.request('POST', '/api/space/join', body: {'inviteCode': code});
      // 刷新空间信息（成员/邀请码）
      final me = await ApiClient.request('GET', '/api/auth/me');
      Session.instance.space = me['space'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入空间，开始共享记录吧！')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加入失败：${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Session.instance.user;
    final space = Session.instance.space;
    final startDate = DateTime.tryParse((space?['startDate'] as String?) ?? '');
    final members = (space?['members'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 个人信息（带头像，点击换头像）
        ListTile(
          leading: Avatar(
            avatarPath: me?['avatarPath'] as String?,
            nickname: me?['nickname'] as String?,
            radius: 26,
            showCameraBadge: true,
            onTap: _pickAvatar,
          ),
          title: Text(me?['nickname'] as String? ?? '未登录'),
          subtitle: Text(me?['email'] as String? ?? ''),
          trailing: members.isNotEmpty
              ? Text('空间 ${members.length}/2 人',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
              : null,
        ),
        const Divider(),
        // 主题
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('主题', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < appThemes.length; i++)
              ChoiceChip(
                avatar: Icon(appThemes[i].icon, size: 16),
                label: Text(appThemes[i].name),
                selected: Session.instance.themeIndex == i,
                onSelected: (_) async {
                  await Session.instance.setThemeIndex(i);
                  setState(() {});
                },
              ),
          ],
        ),
        const Divider(),
        // AI 配置
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('AI 配置（两人共享，BYOK）', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final p in _presets)
              ActionChip(
                label: Text(p.$1),
                onPressed: () => setState(() {
                  _aiBaseUrlCtrl.text = p.$2;
                  _aiModelCtrl.text = p.$3;
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aiBaseUrlCtrl,
          decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://...'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aiKeyCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: _savedKeyMasked != null ? '已保存：$_savedKeyMasked（留空保持不变）' : 'sk-...',
          ),
          onChanged: (_) => _aiKeyTouched = true,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aiModelCtrl,
          decoration: const InputDecoration(labelText: '模型', hintText: 'qwen-vl-max'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aiMaxWaitCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '最大生成等待时间（秒）',
            helperText: '超过该时间未返回则报错重试，默认 240',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _savingAi ? null : _saveAi,
                icon: _savingAi
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('保存 AI 配置'),
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(width: 8),
            // 测试按钮：验证当前配置能否连通
            OutlinedButton.icon(
              onPressed: _testingAi ? null : _testAi,
              icon: _testingAi
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check, size: 18),
              label: const Text('测试'),
            ),
          ],
        ),
        const Divider(height: 32),
        // 文风
        const Text('文风（生成日记时选择）', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final name in presetStyleNames)
              Chip(
                avatar: const Icon(Icons.auto_awesome, size: 14),
                label: Text(name),
                visualDensity: VisualDensity.compact,
              ),
            // 「添加文风」按钮紧跟内置文风之后
            ActionChip(
              avatar: Icon(_showStyleForm ? Icons.close : Icons.add, size: 16),
              label: Text(_showStyleForm ? '收起' : '添加文风'),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _showStyleForm = !_showStyleForm),
            ),
          ],
        ),
        // 自定义文风：输入框（点「添加文风」才出现）
        if (_showStyleForm) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _newStyleNameCtrl,
            decoration: const InputDecoration(labelText: '自定义文风名字', hintText: '如：古诗风 / 情侣日常', isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newStylePromptCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '提示词（完全替换默认，建议含幻觉约束）',
              hintText: '如：用古诗风格写，只写照片里看到的，不编造缺失信息',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _addCustomStyle,
              icon: const Icon(Icons.check),
              label: const Text('确认添加'),
            ),
          ),
        ],
        // 自定义文风列表
        for (var i = 0; i < _customStyles.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.style_outlined, size: 20),
            title: Text(_customStyles[i]['name'] as String),
            subtitle: Text(
              (_customStyles[i]['prompt'] as String),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _removeCustomStyle(i),
            ),
          ),
        const SizedBox(height: 12),
        const Divider(height: 32),
        // 空间（两人共享）
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('空间（两人共享）', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          '记录、AI 配置、在一起日期全部共享。对方需连接到同一后端地址（当前：${Session.instance.baseUrl}）',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        // 成员列表
        for (final m in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Avatar(
              avatarPath: m['user']?['avatarPath'] as String?,
              nickname: m['user']?['nickname'] as String?,
              radius: 22,
            ),
            title: Text((m['user']?['nickname'] as String?) ??
                (m['user']?['email'] as String?) ??
                '未命名'),
            subtitle: Text(m['role'] == 'owner' ? '创建者（可生成邀请码）' : '成员'),
            trailing: (m['user']?['id'] == me?['id'])
                ? Text('我', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                : null,
          ),
        // 邀请码卡片（仅空间未满 2 人时显示）
        if (members.length < 2 && space?['inviteCode'] != null)
          Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.card_giftcard,
                          size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        members.length < 2 ? '邀请另一半加入' : '空间邀请码',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    '${space?['inviteCode']}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '对方注册登录后，在设置页输入此邀请码即可加入（6 位，区分大小写）',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                              text: space?['inviteCode'] as String? ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('邀请码已复制')));
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('复制邀请码'),
                      ),
                      if (_isOwner)
                        TextButton.icon(
                          onPressed: _regenerateCode,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('重新生成'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        // 加入空间（未满 2 人时）
        if (members.length < 2)
          OutlinedButton.icon(
            onPressed: _joinSpace,
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('输入邀请码加入空间'),
          ),
        const Divider(height: 32),
        // 在一起日期（仅双人空间显示；单用户不提供）
        if (members.length >= 2)
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('在一起日期'),
            subtitle: Text(startDate != null
                ? '${startDate.toLocal().year}年${startDate.toLocal().month}月${startDate.toLocal().day}日'
                : '未设置（设置后时间线顶部显示天数）'),
            trailing: TextButton(onPressed: _setStartDate, child: const Text('设置')),
          ),
        const Divider(height: 16),
        // 纪念日（DIY 日期：生日/毕业日/纪念日等，每年提醒）
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('纪念日（生日 / 毕业日 / 纪念日…）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: _addCustomDate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
        ),
        if (_customDates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('还没有纪念日，点「添加」记录生日、毕业日等，到时间线会每年提醒',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
        for (var i = 0; i < _customDates.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.celebration_outlined, size: 20),
            title: Text(_customDates[i]['name'] as String),
            subtitle: Text(
                '${_ownerText(_customDates[i])}${_customDates[i]['month']}月${_customDates[i]['day']}日 · 每年提醒'),
            // 只能删除自己的和共同的；对方的纪念日不可动
            trailing: _canDelete(_customDates[i])
                ? IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _removeCustomDate(i),
                  )
                : null,
          ),
        const Divider(height: 24),
        // 后端地址
        const Divider(),
        TextField(
          controller: _baseUrlCtrl,
          decoration: const InputDecoration(labelText: '后端地址', prefixIcon: Icon(Icons.dns_outlined)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            await Session.instance.saveBaseUrl(_baseUrlCtrl.text.trim());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('后端地址已保存')));
            }
          },
          child: const Text('保存后端地址'),
        ),
        const Divider(height: 32),
        // 导出
        OutlinedButton.icon(
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.archive_outlined),
          label: const Text('导出全部数据（ZIP）'),
        ),
        const SizedBox(height: 24),
        // 登出
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text('退出登录', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }
}
