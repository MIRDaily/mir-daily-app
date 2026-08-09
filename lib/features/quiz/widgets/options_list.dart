import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/question.dart';

class OptionsList extends StatelessWidget {
  final Question question;
  final int? selectedIndex;
  final bool hasAnswered;
  final Function(int) onSelect;

  const OptionsList({
    super.key,
    required this.question,
    required this.selectedIndex,
    required this.hasAnswered,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        question.options.length,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _OptionItem(
            letter: question.getOptionLetter(index),
            text: question.options[index],
            isSelected: selectedIndex == index,
            isCorrect: question.correctIndex == index,
            hasAnswered: hasAnswered,
            onTap: () => onSelect(index),
          ),
        ),
      ),
    );
  }
}

class _OptionItem extends StatelessWidget {
  final String letter;
  final String text;
  final bool isSelected;
  final bool isCorrect;
  final bool hasAnswered;
  final VoidCallback onTap;

  const _OptionItem({
    required this.letter,
    required this.text,
    required this.isSelected,
    required this.isCorrect,
    required this.hasAnswered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor = AppColors.surface;
    Color borderColor = AppColors.surfaceVariant;
    Color letterBgColor = AppColors.surfaceVariant;
    Color letterColor = AppColors.textSecondary;
    Color textColor = AppColors.textPrimary;

    if (hasAnswered) {
      if (isCorrect) {
        backgroundColor = AppColors.success.withValues(alpha: 0.1);
        borderColor = AppColors.success;
        letterBgColor = AppColors.success;
        letterColor = Colors.white;
      } else if (isSelected && !isCorrect) {
        backgroundColor = AppColors.error.withValues(alpha: 0.1);
        borderColor = AppColors.error;
        letterBgColor = AppColors.error;
        letterColor = Colors.white;
      }
    } else if (isSelected) {
      backgroundColor = AppColors.primary.withValues(alpha: 0.1);
      borderColor = AppColors.primary;
      letterBgColor = AppColors.primary;
      letterColor = Colors.white;
    }

    return GestureDetector(
      onTap: hasAnswered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: letterBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: letterColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: textColor,
                  ),
                ),
              ),
            ),
            if (hasAnswered) ...[
              const SizedBox(width: 8),
              Icon(
                isCorrect
                    ? Icons.check_circle
                    : (isSelected ? Icons.cancel : null),
                color: isCorrect ? AppColors.success : AppColors.error,
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
