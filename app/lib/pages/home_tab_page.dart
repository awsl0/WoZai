import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../utils/calendar.dart';
import '../utils/weather.dart';
import '../widgets/avatar.dart';
import '../widgets/event_card.dart';
import 'event_page.dart';

/// 主页：在一起天数 + 下一个纪念日 + 统计 + 最近记录
class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key, this.onViewAll});

  /// “查看全部”点击回调（切到时间线 tab）
  final VoidCallback? onViewAll;

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;
  bool _unauthorized = false; // 401 未登录时显示「去登录」

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.request('GET', '/api/events');
      final events = (data['events'] as List).cast<Map<String, dynamic>>();
      final me = await ApiClient.request('GET', '/api/auth/me');
      Session.instance.user = me['user'] as Map<String, dynamic>?; // 冷启动后刷新用户
      Session.instance.space = me['space'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _unauthorized = e.statusCode == 401;
        _loading = false;
      });
    }
  }

  /// 空间里的另一半（非当前用户）
  Map<String, dynamic>? get _partner {
    final members = Session.instance.space?['members'] as List? ?? [];
    final meId = Session.instance.user?['id'];
    for (final m in members) {
      if (m['user']?['id'] != meId) return m as Map<String, dynamic>?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final space = Session.instance.space;
    final together = togetherText(space);
    final me = Session.instance.user;
    final startDate = DateTime.tryParse((space?['startDate'] as String?) ?? '')?.toLocal();
    final upcoming = nextUpcoming(DateTime.now(), startDate,
        customDates: displayCustomDates(
            (space?['customDates'] as List?) ?? const [],
            me,
            space?['members'] as List? ?? const []));

    // 统计
    final placeNames = _events
        .map((e) => e['locationName'] as String?)
        .where((n) => n != null && n.isNotEmpty)
        .toSet();
    final photoCount = _events.fold<int>(0, (sum, e) => sum + ((e['photos'] as List?)?.length ?? 0));
    final recent = _events.take(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('WoZai'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // 在一起天数大卡片：左侧原格式文字 · 右侧双头像 + 丘比特/月老动画
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  // 左侧：原格式（爱心 + 在一起 + 纪念日 + 日期）
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // 有另一半：一大一小两个红心依偎；单人：单个红心
                            if (_partner != null)
                              SizedBox(
                                width: 30,
                                height: 24,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: 2,
                                      top: 1,
                                      child: const Icon(Icons.favorite,
                                          color: Color(0xFFD81B60),
                                          size: 20),
                                    ),
                                    Positioned(
                                      left: 16,
                                      top: 13,
                                      child: const Icon(Icons.favorite,
                                          color: Color(0xFFC2185B),
                                          size: 12),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const Icon(Icons.favorite,
                                  color: Color(0xFFD81B60), size: 20),
                            const SizedBox(width: 6),
                            // FittedBox 自适应缩放：任何屏幕宽度/字体大小都完整显示不截断
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  together ??
                                      (me?['nickname'] as String? ?? '我的记录'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            upcoming != null
                                ? '还有 ${upcoming.daysLeft} 天 · ${upcoming.name}'
                                : '记录每一天',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('yyyy年M月d日').format(DateTime.now()),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 右侧：有另一半 → 双头像 + 丘比特射爱心；单人 → 只显示自己头像
                  if (_partner != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Avatar(
                          avatarPath: me?['avatarPath'] as String?,
                          nickname: me?['nickname'] as String?,
                          radius: 20,
                          light: true,
                        ),
                        const SizedBox(width: 3),
                        SizedBox(
                          width: 42,
                          height: 46,
                          child: _LoveAnimator(hasPartner: true),
                        ),
                        const SizedBox(width: 3),
                        Avatar(
                          avatarPath: _partner?['user']?['avatarPath'] as String?,
                          nickname: _partner?['user']?['nickname'] as String?,
                          radius: 20,
                          light: true,
                        ),
                      ],
                    )
                  else
                    Avatar(
                      avatarPath: me?['avatarPath'] as String?,
                      nickname: me?['nickname'] as String?,
                      radius: 20,
                      light: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 统计
            Row(
              children: [
                _StatCard(icon: Icons.event_note, value: '${_events.length}', label: '记录'),
                const SizedBox(width: 10),
                _StatCard(icon: Icons.place_outlined, value: '${placeNames.length}', label: '去过的地方'),
                const SizedBox(width: 10),
                _StatCard(icon: Icons.photo_outlined, value: '$photoCount', label: '照片'),
              ],
            ),
            if (_loading && _events.isEmpty) ...[
              const SizedBox(height: 32),
              const Center(child: CircularProgressIndicator()),
            ] else if (_error != null && _events.isEmpty) ...[
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    if (_unauthorized)
                      FilledButton(
                        onPressed: () {
                          Session.instance.clear();
                          Navigator.of(context).pushNamedAndRemoveUntil(
                              '/login', (route) => false);
                        },
                        child: const Text('去登录'),
                      )
                    else
                      FilledButton(onPressed: _refresh, child: const Text('重试')),
                  ],
                ),
              ),
            ] else if (_events.isEmpty) ...[
              const SizedBox(height: 48),
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.photo_camera_outlined, size: 56, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('还没有记录，点右下角「记录此刻」开始吧', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              const Text('最近记录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              for (final e in recent)
                EventCard(event: e, onTap: () => _openEvent(e)),
              if (_events.length > 3)
                Center(
                  child: TextButton(
                    onPressed: widget.onViewAll,
                    child: const Text('查看全部 →'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _openEvent(Map<String, dynamic> event) async {
    final refreshed = await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventPage(eventId: event['id'] as String),
    ));
    if (refreshed == true) _refresh();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: primary, size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

/// 丘比特往两边射爱心：前 3 秒射向左、后 3 秒射向右，循环
class _LoveAnimator extends StatefulWidget {
  const _LoveAnimator({this.hasPartner = true});
  final bool hasPartner;
  @override
  State<_LoveAnimator> createState() => _LoveAnimatorState();
}

class _LoveAnimatorState extends State<_LoveAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 6))
    ..repeat();
  late final Animation<double> _t =
      CurvedAnimation(parent: _ctrl, curve: Curves.linear);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _t.value;
        final toLeft = t < 0.5; // 前 3 秒射向左、后 3 秒射向右
        final seg = toLeft ? t / 0.5 : (t - 0.5) / 0.5; // 段内进度 0→1
        final opacity = seg < 0.12
            ? seg / 0.12
            : (seg > 0.88 ? (1 - seg) / 0.12 : 1.0);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 丘比特（弓箭）；射向右时镜像
            Transform.flip(
              flipX: !toLeft,
              child: const Text('🏹', style: TextStyle(fontSize: 18)),
            ),
            // 有另一半：爱心从中间射向目标侧（在 42px 宽内飞行，不溢出遮挡左侧文字）
            if (widget.hasPartner)
              Positioned(
                left: toLeft ? 21 - seg * 13 : 21 + seg * 13,
                top: 5 + math.sin(seg * math.pi * 2) * 4,
                child: Opacity(
                  opacity: opacity,
                  child: const Text('❤️', style: TextStyle(fontSize: 12)),
                ),
              ),
            // 无另一半：爱心原地跳动等待
            if (!widget.hasPartner)
              Positioned(
                left: 15,
                top: 7 + math.sin(seg * math.pi * 4) * 3,
                child: Opacity(
                  opacity: 0.4 + 0.6 * (0.5 + 0.5 * math.sin(seg * math.pi * 2)),
                  child: const Text('💘', style: TextStyle(fontSize: 12)),
                ),
              ),
          ],
        );
      },
    );
  }
}
