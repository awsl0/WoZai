import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../state/session.dart';

/// 登录/注册页：首次配置后端地址 + 邮箱密码登录或注册
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController(text: Session.instance.baseUrl);

  bool _registerMode = false;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nicknameCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Session.instance.saveBaseUrl(_baseUrlCtrl.text.trim());
      final data = _registerMode
          ? await ApiClient.request('POST', '/api/auth/register', auth: false, body: {
              'email': _emailCtrl.text.trim(),
              'password': _passwordCtrl.text,
              if (_nicknameCtrl.text.trim().isNotEmpty) 'nickname': _nicknameCtrl.text.trim(),
            })
          : await ApiClient.request('POST', '/api/auth/login', auth: false, body: {
              'email': _emailCtrl.text.trim(),
              'password': _passwordCtrl.text,
            });

      await Session.instance.setToken(data['token'] as String);
      await _loadProfile();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('无法连接服务器：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile() async {
    final me = await ApiClient.request('GET', '/api/auth/me');
    Session.instance.user = me['user'] as Map<String, dynamic>?;
    Session.instance.space = me['space'] as Map<String, dynamic>?;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.favorite, size: 64, color: Color(0xFFFF6B81)),
                  const SizedBox(height: 8),
                  Text('WoZai', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  Text('拍张照，AI 帮你写日记', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _baseUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: '后端地址',
                      hintText: 'http://服务器IP:3000',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v == null || !v.contains('@') ? '请输入正确的邮箱' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    validator: (v) => v == null || v.length < 6 ? '密码至少 6 位' : null,
                  ),
                  if (_registerMode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nicknameCtrl,
                      decoration: const InputDecoration(
                        labelText: '昵称（可选）',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B81),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_registerMode ? '注册并开始' : '登录'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _registerMode = !_registerMode),
                    child: Text(_registerMode ? '已有账号？去登录' : '没有账号？注册一个'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
