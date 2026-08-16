import 'package:flutter/material.dart';
import '../state/session.dart';

/// 通用头像：有 avatarPath 显示图片，否则显示昵称首字。
/// 可带相机角标（点击换头像）。
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.avatarPath,
    this.nickname,
    this.radius = 22,
    this.showCameraBadge = false,
    this.onTap,
    this.light = false,
  });

  final String? avatarPath;
  final String? nickname;
  final double radius;
  final bool showCameraBadge;
  final VoidCallback? onTap;

  /// 在彩色/渐变背景上使用白色系（如主页顶部卡片）
  final bool light;

  @override
  Widget build(BuildContext context) {
    final name = (nickname == null || nickname!.isEmpty) ? '?' : nickname!;
    final baseUrl = Session.instance.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final path = avatarPath;

    Widget content;
    if (path != null && path.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          '$baseUrl/uploads/${path.split('/').last}',
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _InitialAvatar(name: name, radius: radius, light: light),
        ),
      );
    } else {
      content = _InitialAvatar(name: name, radius: radius, light: light);
    }

    if (showCameraBadge || onTap != null) {
      content = InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            if (showCameraBadge)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).colorScheme.surface, width: 2),
                  ),
                  child: const Icon(Icons.photo_camera,
                      size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      );
    }
    return content;
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar(
      {required this.name, required this.radius, this.light = false});
  final String name;
  final double radius;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.25)
            : scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        name.characters.first,
        style: TextStyle(
          color: light ? Colors.white : scheme.primary,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
