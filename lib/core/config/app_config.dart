/// Configuración central de MIRDaily.
///
/// Misma infraestructura que la web:
///  - Auth: Supabase (JWT que se envía como Bearer al backend)
///  - API:  backend Express desplegado en Railway
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = 'https://piodbnhiwgntpjxbqqlw.supabase.co';

  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBpb2Ribmhpd2dudHBqeGJxcWx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk3OTc2NDUsImV4cCI6MjA4NTM3MzY0NX0.PTmWbzBil0IZPv_iwidP8PCcda9OXR3iWvNuiqfuEqs';

  static const String apiBaseUrl =
      'https://mir-daily-backend-production.up.railway.app';

  /// Número de preguntas del daily (lo fija el backend).
  static const int questionsPerDaily = 5;

  /// Avatares (mismo bucket de Supabase que la web). IDs válidos: 1..12.
  static const String avatarBaseUrl =
      'https://piodbnhiwgntpjxbqqlw.supabase.co/storage/v1/object/public/avatars/';

  static String avatarUrl(int id) => '$avatarBaseUrl$id.webp';

  static const List<int> avatarCatalog = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 //
  ];
}
