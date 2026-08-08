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
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      
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
        elevation: 2,
        shadowColor: AppColors.secondary.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      
      // Botones elevados
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      // Botones de texto
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
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
