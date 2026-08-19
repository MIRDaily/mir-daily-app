import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';

class _LibrarySubject {
  final String id;
  final String name;
  final String description;
  final int progress; // 0..100
  final int topicsDone;
  final int totalTopics;
  final String type; // BÁSICA | MÉDICA | QUIRÚRGICA
  final IconData icon;

  const _LibrarySubject(this.id, this.name, this.description, this.progress,
      this.topicsDone, this.totalTopics, this.type, this.icon);
}

/// Biblioteca de asignaturas — mismo catálogo que la web (/library).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _filter = 'TODAS';

  // Catálogo portado de LIBRARY_SUBJECT_OVERVIEWS (src/mocks/library.ts)
  static const _subjects = [
    _LibrarySubject('repasos-mir', 'Repasos MIR',
        'Síntesis anual y estrategia final', 48, 1, 3, 'BÁSICA',
        Icons.school_rounded),
    _LibrarySubject('bioestadistica', 'Bioestadística',
        'Metodología de investigación', 100, 10, 10, 'BÁSICA',
        Icons.analytics_rounded),
    _LibrarySubject('bioetica', 'Bioética y legislación',
        'Marco legal y ético', 37, 3, 8, 'BÁSICA', Icons.gavel_rounded),
    _LibrarySubject('cardiologia', 'Cardiología', 'Alta rentabilidad MIR',
        72, 18, 25, 'MÉDICA', Icons.favorite_rounded),
    _LibrarySubject('cirugia-general', 'Cirugía General y Digestivo',
        'Patología quirúrgica digestiva', 40, 12, 30, 'QUIRÚRGICA',
        Icons.medical_services_rounded),
    _LibrarySubject('trauma', 'Cirugía Ortopédica y Trauma',
        'Huesos, articulaciones y fracturas', 22, 5, 22, 'QUIRÚRGICA',
        Icons.accessibility_new_rounded),
    _LibrarySubject('cirugia-plastica', 'Cirugía Plástica',
        'Quemados y reconstructiva', 0, 0, 5, 'QUIRÚRGICA',
        Icons.face_retouching_natural_rounded),
    _LibrarySubject('dermatologia', 'Dermatología', 'Piel y anexos cutáneos',
        65, 11, 17, 'MÉDICA', Icons.back_hand_rounded),
    _LibrarySubject('endocrino', 'Endocrinología', 'Hormonas y metabolismo',
        58, 7, 12, 'MÉDICA', Icons.monitor_weight_rounded),
    _LibrarySubject('farmacologia', 'Farmacología',
        'Principios terapéuticos', 45, 9, 20, 'BÁSICA',
        Icons.medication_rounded),
    _LibrarySubject('ginecologia', 'Ginecología y Obstetricia',
        'Salud de la mujer', 74, 17, 23, 'QUIRÚRGICA',
        Icons.pregnant_woman_rounded),
    _LibrarySubject('hematologia', 'Hematología', 'Sangre y hemostasia', 62,
        13, 21, 'MÉDICA', Icons.bloodtype_rounded),
    _LibrarySubject('inmunologia', 'Inmunología',
        'Respuesta inmune y autoinmunidad', 29, 5, 17, 'BÁSICA',
        Icons.biotech_rounded),
    _LibrarySubject('nefrologia', 'Nefrología', 'Riñón y vías urinarias',
        75, 15, 20, 'MÉDICA', Icons.water_drop_rounded),
    _LibrarySubject('neurologia', 'Neurología',
        'Sistema nervioso y sentidos', 54, 15, 28, 'MÉDICA',
        Icons.psychology_rounded),
    _LibrarySubject('pediatria', 'Pediatría', 'Desarrollo y neonatología',
        91, 20, 22, 'MÉDICA', Icons.child_care_rounded),
  ];

  static const _filters = ['TODAS', 'BÁSICA', 'MÉDICA', 'QUIRÚRGICA'];

  Color _typeColor(String type) => switch (type) {
        'BÁSICA' => const Color(0xFF7D8A96),
        'MÉDICA' => AppColors.primaryDark,
        'QUIRÚRGICA' => const Color(0xFF6E8E6B),
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filter == 'TODAS'
        ? _subjects
        : _subjects.where((s) => s.type == _filter).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StickerHero(
                    badge: 'Temario',
                    badgeIcon: Icons.menu_book_rounded,
                    title: 'Apuntes',
                    subtitle:
                        '${_subjects.length} asignaturas actualizadas con IA predictiva.',
                    accent: const Color(0xFF7D8A96),
                  ),
                  const SizedBox(height: 22),
                  SlideFadeIn(
                    delay: const Duration(milliseconds: 180),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filters.map((f) {
                          final active = f == _filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Pressable(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _filter = f);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active ? kInk : Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: active ? kInk : kHairline,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  f,
                                  style: TextStyle(
                                    color: active ? Colors.white : kMuted,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => SlideFadeIn(
                  key: ValueKey('${_filter}_${filtered[i].id}'),
                  delay: Duration(milliseconds: 60 * (i % 8)),
                  beginOffset: const Offset(0, 0.15),
                  child: _subjectCard(filtered[i]),
                ),
                childCount: filtered.length,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _subjectCard(_LibrarySubject subject) {
    final typeColor = _typeColor(subject.type);
    final complete = subject.progress >= 100;

    return Pressable(
      onTap: () {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${subject.name}: los temas se abren en la web por ahora 📚'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.textPrimary,
          ),
        );
      },
      pressedScale: 0.96,
      child: StickerCard(
        depth: 4,
        radius: 20,
        padding: const EdgeInsets.all(14),
        // Cartulina rayada: es temario, y la trama lo dice sin escribirlo.
        texture: ruledPaper(step: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: typeColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kInk, width: 2),
                    boxShadow: inkShadow(2),
                  ),
                  child: Icon(subject.icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                if (complete)
                  const Icon(Icons.workspace_premium_rounded,
                      color: AppColors.gold, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subject.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kInk,
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subject.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.3,
              ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                subject.type,
                style: TextStyle(
                  color: typeColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 8.5,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Barra de progreso animada
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: subject.progress / 100),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation(
                          complete ? AppColors.gold : AppColors.success,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${subject.topicsDone}/${subject.totalTopics} temas · ${(value * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
