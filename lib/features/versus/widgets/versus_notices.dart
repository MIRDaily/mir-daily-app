import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../models/versus_models.dart';

/// Avisos de conexión, en píldoras de una sola línea ancladas abajo.
///
/// Ocupan poco a propósito: aparecen justo cuando estás leyendo la pregunta y
/// no deben robarle sitio ni al enunciado ni a las opciones. Cuando no hay
/// ninguno el widget no ocupa nada y deja pasar los toques a lo que hay debajo.
class VersusNotices extends StatelessWidget {
  final List<VersusNotice> notices;

  const VersusNotices({super.key, required this.notices});

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final notice in notices)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _NoticePill(key: ValueKey(notice.id), notice: notice),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticePill extends StatefulWidget {
  final VersusNotice notice;

  const _NoticePill({super.key, required this.notice});

  @override
  State<_NoticePill> createState() => _NoticePillState();
}

class _NoticePillState extends State<_NoticePill> {
  // Arranca abajo y transparente, y sube al primer frame. Sin esto la píldora
  // aparecería de golpe en mitad de la pregunta.
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _in = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final visible = _in && !notice.leaving;

    final (IconData icon, Color color) = switch (notice.kind) {
      VersusNoticeKind.back => (Icons.wifi_rounded, AppColors.successDark),
      VersusNoticeKind.away => (Icons.wifi_off_rounded, AppColors.primaryDark),
      VersusNoticeKind.left => (Icons.logout_rounded, AppColors.textSecondary),
      VersusNoticeKind.host => (Icons.star_rounded, AppColors.primaryDark),
      VersusNoticeKind.wounded => (
          Icons.heart_broken_rounded,
          AppColors.warning
        ),
      VersusNoticeKind.down => (Icons.dangerous_rounded, AppColors.error),
    };

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 0.35),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (notice.avatarId != null) ...[
                  ClipOval(
                    child: Image.network(
                      AppConfig.avatarUrl(notice.avatarId!),
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 24,
                        height: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    notice.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
