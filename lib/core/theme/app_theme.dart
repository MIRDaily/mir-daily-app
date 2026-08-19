import 'package:flutter/material.dart';

class AppColors {
  // Colores principales - MODIFICA AQUÍ PARA CAMBIAR LA PALETA
  static const Color background = Color(0xFFFAF7F4);      // Beige cálido
  static const Color primary = Color(0xFFE8A598);          // Coral suave
  static const Color secondary = Color(0xFF7D8A96);        // Azul grisáceo
  
  // Colores de superficie
  static const Color surface = Color(0xFFFFFFFF);          // Blanco
  static const Color surfaceVariant = Color(0xFFF5F0EB);   // Beige más claro
  
  // Colores de texto
  static const Color textPrimary = Color(0xFF3D4248);      // Gris oscuro
  static const Color textSecondary = Color(0xFF7D8A96);    // Azul grisáceo
  static const Color textLight = Color(0xFFADB5BD);        // Gris claro
  
  // Colores de feedback
  static const Color success = Color(0xFF8BA888);          // Verde salvia
  static const Color error = Color(0xFFC4655A);            // Coral intenso
  static const Color warning = Color(0xFFE8C598);          // Ámbar suave
  
  // Colores de navegación
  static const Color navActive = Color(0xFFE8A598);        // Coral
  static const Color navInactive = Color(0xFFADB5BD);      // Gris claro

  // Colores adicionales (portados de v11 para Biblioteca, Auth y Daily)
  static const Color primaryDark = Color(0xFFC45B4B);      // Coral intenso
  static const Color primaryHover = Color(0xFFD68C7F);
  static const Color border = Color(0xFFF0EAE6);           // Borde suave
  static const Color gold = Color(0xFFF6D87A);             // Dorado (logros)
  static const Color goldSoft = Color(0xFFF9E3A2);
  static const Color envelopeTop = Color(0xFFF08D75);      // Gradiente sobre
  static const Color envelopeBottom = Color(0xFFE87E65);
  static const Color envelopeAccent = Color(0xFFFFAB91);
  static const Color successDark = Color(0xFF6E8E6B);
  static const Color errorSoft = Color(0xFFF3D9D5);
  static const Color slate = Color(0xFF64748B);
  static const Color slateLight = Color(0xFF94A3B8);
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldLight = Color(0xFF34D399);

  // Trazo de tinta del lenguaje "sticker" de la web (ver
  // lib/shared/sticker/sticker.dart). Es el borde de las tarjetas rediseñadas.
  static const Color ink = Color(0xFF2C3E50);
  static const Color hairline = Color(0xFFEAE4E2);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Misma tipografia que la web (pesos 400/500/600/900). El 900 apunta al
      // fichero Bold, igual que en su layout.tsx, para que los titulares
      // `font-black` se vean identicos en los dos clientes.
      fontFamily: 'Lexend',
      
      // Colores principales
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),
      
      // Fondo
      scaffoldBackgroundColor: AppColors.background,
      
      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      
      // Tarjetas
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.hairline, width: 2),
        ),
      ),
      
      // Botones elevados. Llevan el trazo de tinta del lenguaje visual (ver
      // lib/shared/sticker/) para que los que quedan sueltos en diálogos y
      // estados de error no desentonen con los StickerButton. La sombra dura
      // no cabe en un ButtonStyle: la que la necesita usa StickerButton.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.ink, width: 2),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      // Botones con contorno: hacen el papel del GhostButton.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: const BorderSide(color: AppColors.hairline, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      
      // Botones de texto
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      
      // Navegación inferior
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.navActive,
        unselectedItemColor: AppColors.navInactive,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
      
      // Textos
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
        displayMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        headlineLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
