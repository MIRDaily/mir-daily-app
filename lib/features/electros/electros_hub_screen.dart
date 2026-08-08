import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';
import 'electro_web_view.dart';

/// Sub-hub de Electros dentro de Biblioteca: da acceso al simulador de ECG de
/// 12 derivaciones y a la Academia (aprendizaje guiado). Cada uno abre su
/// herramienta web embebida.
class ElectrosHubScreen extends StatelessWidget {
  const ElectrosHubScreen({super.key});

  void _openSimulador(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ElectroWebView(
        title: 'Simulador de ECG',
        assetPrefix: 'assets/electros/simulador',
      ),
    ));
  }

  void _openAcademia(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ElectroWebView(
        title: 'Academia ECG',
        assetPrefix: 'assets/electros/academia',
        onOpenSimulador: () => _openSimulador(context),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Electros')),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            const SlideFadeIn(
              child: Text(
                'Electrocardiografía',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const SlideFadeIn(
              delay: Duration(milliseconds: 100),
              child: Text(
                'Aprende a leer un ECG y practica con trazos realistas de 12 derivaciones.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 22),
            SlideFadeIn(
              delay: const Duration(milliseconds: 160),
              beginOffset: const Offset(0, 0.12),
              child: _ElectroCard(
                title: 'Academia ECG',
                subtitle:
                    'Aprende paso a paso: de la mecánica eléctrica del corazón a los algoritmos diagnósticos, con animaciones interactivas.',
                icon: Icons.school_rounded,
                gradient: const [Color(0xFFE8A598), Color(0xFFD68C7F)],
                tag: 'APRENDE',
                onTap: () => _openAcademia(context),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 230),
              beginOffset: const Offset(0, 0.12),
              child: _ElectroCard(
                title: 'Simulador de ECG',
                subtitle:
                    'Monitor animado y ECG de 12 derivaciones para estudiar los principales diagnósticos, con modo examen.',
                icon: Icons.monitor_heart_rounded,
                gradient: const [Color(0xFF6E8E6B), Color(0xFF8BA888)],
                tag: '12 DERIVACIONES',
                onTap: () => _openSimulador(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElectroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String tag;
  final VoidCallback onTap;

  const _ElectroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: gradient.first.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: gradient.first.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            color: gradient.first,
                            fontWeight: FontWeight.w800,
                            fontSize: 8,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.textLight, size: 16),
          ],
        ),
      ),
    );
  }
}
