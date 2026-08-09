import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/question.dart';

class ExplanationCard extends StatefulWidget {
  final Question question;
  final bool isCorrect;
  final VoidCallback onSaveToDecK;
  final Function(String) onSetDifficulty;
  final String? currentDifficulty;
  final bool showDifficultyButtons;

  const ExplanationCard({
    super.key,
    required this.question,
    required this.isCorrect,
    required this.onSaveToDecK,
    required this.onSetDifficulty,
    this.currentDifficulty,
    this.showDifficultyButtons = true,
  });

  @override
  State<ExplanationCard> createState() => _ExplanationCardState();
}

class _ExplanationCardState extends State<ExplanationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: widget.isCorrect
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isCorrect ? AppColors.success : AppColors.error,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.isCorrect ? Icons.check_circle : Icons.cancel,
                    color: widget.isCorrect ? AppColors.success : AppColors.error,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isCorrect ? '¡Correcto!' : 'Incorrecto',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: widget.isCorrect ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ),
                  if (widget.showDifficultyButtons) ...[
                    _buildDifficultyButton('easy', AppColors.success, Icons.sentiment_satisfied),
                    const SizedBox(width: 4),
                    _buildDifficultyButton('medium', AppColors.warning, Icons.sentiment_neutral),
                    const SizedBox(width: 4),
                    _buildDifficultyButton('hard', AppColors.error, Icons.sentiment_dissatisfied),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    onPressed: widget.onSaveToDecK,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    color: AppColors.secondary,
                    tooltip: 'Guardar en mazo',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!widget.isCorrect) ...[
                Text(
                  'Respuesta correcta: ${widget.question.getOptionLetter(widget.question.correctIndex)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Explicación',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.question.explanation,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyButton(String difficulty, Color color, IconData icon) {
    final isSelected = widget.currentDifficulty == difficulty;
    
    return GestureDetector(
      onTap: () => widget.onSetDifficulty(difficulty),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          color: isSelected ? color : AppColors.textLight,
          size: 22,
        ),
      ),
    );
  }
}
