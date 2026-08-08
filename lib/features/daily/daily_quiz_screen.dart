import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/providers/daily_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/goo_fission_loader.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/zoomable_image.dart';
import '../results/results_screen.dart';

/// Quiz del daily: 5 preguntas SIN feedback inmediato (como la web).
/// El usuario elige una opción y avanza; las respuestas correctas y la
/// explicación solo se muestran después, en el carrusel de resultados.
class DailyQuizScreen extends StatefulWidget {
  const DailyQuizScreen({super.key});

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen> {
  int? _selectedOption;
  late DateTime _questionStart;
  Timer? _ticker;
  int _elapsedSeconds = 0;

  static const _optionLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

  @override
  void initState() {
    super.initState();
    _startQuestionTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DailyProvider>().startQuiz();
    });
  }

  void _startQuestionTimer() {
    _questionStart = DateTime.now();
    _elapsedSeconds = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds =
              DateTime.now().difference(_questionStart).inSeconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _continue() async {
    // En el daily es obligatorio elegir una opción: no se avanza sin marcar.
    if (_selectedOption == null) return;
    final daily = context.read<DailyProvider>();
    final timeSpent =
        DateTime.now().difference(_questionStart).inSeconds.clamp(1, 3600);

    final wasLast = daily.answerCurrent(
      selectedIndex: _selectedOption,
      timeSpent: timeSpent,
    );

    if (!wasLast) {
      setState(() {
        _selectedOption = null;
      });
      _startQuestionTimer();
      return;
    }

    // Última pregunta: enviar al backend.
    _ticker?.cancel();
    final ok = await daily.submit();
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, _, _) => const ResultsScreen(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(daily.error ?? 'Error al enviar respuestas'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Reintentar',
            textColor: Colors.white,
            onPressed: _continue,
          ),
        ),
      );
    }
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('¿Abandonar el daily?'),
        content: const Text(
          'Si sales ahora perderás el progreso de este sobre y no podrás volver a abrirlo hoy desde aquí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir jugando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final daily = context.watch<DailyProvider>();
    final question = daily.currentQuestion;

    if (daily.status == DailyStatus.submitting) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: GooFissionLoader(size: 170, label: 'Corrigiendo tu daily...'),
        ),
      );
    }

    if (question == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: GooFissionLoader(size: 150)),
      );
    }

    final index = daily.currentIndex;
    final total = daily.questions.length;
    final isLast = index == total - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(index, total),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.25, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: SingleChildScrollView(
                    key: ValueKey(question.id),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _questionCard(question),
                        const SizedBox(height: 20),
                        ..._options(question),
                      ],
                    ),
                  ),
                ),
              ),
              _bottomPanel(isLast),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(int index, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              if (await _confirmExit() && mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textLight, size: 28),
          ),
          // Barra de progreso segmentada
          Expanded(
            child: Row(
              children: List.generate(total, (i) {
                final done = i < index;
                final active = i == index;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    height: active ? 12 : 9,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: (done || active)
                          ? AppColors.primary
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 14),
          // Cronómetro
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${(_elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(_elapsedSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(DailyQuestion question) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.textSecondary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (question.subject != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      question.subject!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (question.year != null)
                Text(
                  'MIR ${question.year}',
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            question.statement,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (question.hasImage && question.imageUrl != null) ...[
            const SizedBox(height: 14),
            ZoomableImage(url: question.imageUrl!),
          ],
        ],
      ),
    );
  }

  /// Opciones SIN revelar la correcta: solo se resalta la elegida en coral.
  List<Widget> _options(DailyQuestion question) {
    final widgets = <Widget>[];
    for (var i = 0; i < question.options.length; i++) {
      final selected = _selectedOption == i;

      final border = selected ? AppColors.primary : AppColors.border;
      final background = selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : AppColors.surface;
      final letterBg = selected ? AppColors.primary : AppColors.surfaceVariant;
      final letterFg = selected ? Colors.white : AppColors.textSecondary;

      widgets.add(
        SlideFadeIn(
          delay: Duration(milliseconds: 60 * i),
          beginOffset: const Offset(0, 0.25),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              onTap: () => setState(() {
                _selectedOption = i;
              }),
              pressedScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border, width: 2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: letterBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _optionLetters[i],
                        style: TextStyle(
                          color: letterFg,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          question.options[i],
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _bottomPanel(bool isLast) {
    final enabled = _selectedOption != null;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textSecondary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Pressable(
              onTap: enabled ? _continue : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 56,
            decoration: BoxDecoration(
              color: enabled ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(18),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              isLast ? 'FINALIZAR' : 'CONTINUAR',
              style: TextStyle(
                color: enabled ? Colors.white : AppColors.textLight,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }
}
