import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../theme/app_themes.dart';

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
  final _customPromptCtrl = TextEditingController();
  String _style = 'warm';

  bool _savingAi = false;
  bool _exporting = false;

  static const _presets = [
    ('通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-vl-max'),
    ('智谱', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4v-plus'),
    ('OpenAI', 'https://api.openai.com/v1', 'gpt-4o'),
  ];

  @override
  void initState() {
    super.initState();
    _loadAiConfig();
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _aiBaseUrlCtrl.dispose();
    _aiKeyCtrl.dispose();
    _aiModelCtrl.dispose();
    _customPromptCtrl.dispose();
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
          _style = cfg['style'] as String? ?? 'warm';
          _customPromptCtrl.text = cfg['customPrompt'] as String? ?? '';
          if (cfg['hasApiKey'] == true) _aiKeyCtrl.text = cfg['apiKeyMasked'] as String? ?? '';
        }
      });
    } catch (_) {
      // 忽略加载失败，让用户手动填
    }
  }

  Future<void> _saveAi() async {
    setState(() => _savingAi = true);
    try {
      await ApiClient.request('PUT', '/api/settings/ai', body: {
        'baseUrl': _aiBaseUrlCtrl.text.trim(),
        'apiKey': _aiKeyCtrl.text.trim(),
        'model': _aiModelCtrl.text.trim(),
        'style': _style,
        'customPrompt': _customPromptCtrl.text.trim(),
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

  Future<void> _setStartDate() async {
    final current = DateTime.tryParse((Session.instance.space?['startDate'] as String?) ?? '');
    final date = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    try {
      await ApiClient.request('PUT', '/api/space/start-date',
          body: {'startDate': date.toIso8601String()});
      final me = await ApiClient.request('GET', '/api/auth/me');
      Session.instance.space = me['space'] as Map<String, dynamic>?;
      if (!mounted) return;
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

  Future<void> _logout() async {
    await Session.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
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
        // 个人信息
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text((me?['nickname'] as String? ?? '我').characters.first),
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
          decoration: const InputDecoration(labelText: 'API Key', hintText: 'sk-...'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _aiModelCtrl,
                decoration: const InputDecoration(labelText: '模型', hintText: 'qwen-vl-max'),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _style,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'warm', child: Text('温暖日常')),
                DropdownMenuItem(value: 'literary', child: Text('文艺')),
              ],
              onChanged: (v) => setState(() => _style = v ?? 'warm'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 自定义提示词（可选，非空时替换默认 system prompt）
        TextField(
          controller: _customPromptCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '自定义提示词（可选）',
            hintText: '留空使用默认。填写后完全替换默认提示词，建议包含：只描述照片可见事实、推测用“大概/也许”、不编造缺失信息',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _savingAi ? null : _saveAi,
          icon: _savingAi
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('保存 AI 配置'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
        ),
        const Divider(height: 32),
        // 在一起日期
        ListTile(
          leading: const Icon(Icons.favorite_outline),
          title: const Text('在一起日期'),
          subtitle: Text(startDate != null
              ? '${startDate.toLocal().year}年${startDate.toLocal().month}月${startDate.toLocal().day}日'
              : '未设置（设置后时间线顶部显示天数）'),
          trailing: TextButton(onPressed: _setStartDate, child: const Text('设置')),
        ),
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
