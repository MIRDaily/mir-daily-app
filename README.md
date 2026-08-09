# mirdaily_app

MIRDaily - Aprende lo que realmente importa para el MIR.

App móvil en Flutter (Android/iOS) para preparar el examen MIR: preguntas diarias, mazos de estudio (decks), quiz con mecánica de apertura de sobres, modo Versus (partidas 1v1 en tiempo real), simulacros, electrocardiogramas (simulador + academia embebidos) y seguimiento de progreso.

La carpeta local viva sigue siendo `mirdailyapp/Version final v4`, y a partir de ahora los cambios ahí deberían acabar en commits, igual que backend y frontend. A diferencia de esos dos, este repo no tiene deploy automático — no hay tienda conectada, así que instalar sigue siendo `flutter build`/`flutter install` a mano.

## Stack

- **Flutter** (SDK `^3.10.3`), gestión de estado con `provider`.
- **Auth**: Supabase (JWT enviado como Bearer al backend).
- **API**: backend Express desplegado en Railway (`lib/core/config/app_config.dart`).
- **Realtime**: `realtime_client` (Supabase), usado por el modo Versus.
- **Motor de juego**: `flame`, para las animaciones del quiz (apertura de sobres, etc).
- **WebView**: `webview_flutter`, para las herramientas de Electros (simulador + academia) servidas como assets locales.

## Estructura

```
lib/
  core/
    config/      # AppConfig (URLs de Supabase/backend, claves públicas)
    data/        # Datos estáticos (preguntas)
    models/      # Modelos: Question, Deck, UserProfile, Analytics...
    providers/   # AuthProvider, DailyProvider, QuizProvider, UserProvider
    services/    # ApiService, AuthService, NotificationService, HapticsService...
    theme/       # Tema y system UI
  features/      # Un módulo por pantalla/funcionalidad (auth, daily, decks,
                 # quiz, versus, electros, simulacro, premium, focus, biblioteca,
                 # library, profile, results, onboarding, splash, studio, navigation)
  shared/widgets/
assets/
  images/, branding/, electros/{simulador,academia}/
test/            # Smoke tests (loading, navegación, layout, carrusel de resultados)
tools/           # make_app_icon.py
```

## Requisitos

- Flutter SDK (canal stable) — comprobar versión con `flutter --version`.
- Un dispositivo/emulador Android o iOS, o Chrome para `flutter run -d chrome`.

## Poner en marcha

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

No hay variables de entorno que configurar: las URLs de Supabase/backend y la anon key pública están en `lib/core/config/app_config.dart` (la anon key es pública por diseño de Supabase; la seguridad depende de las políticas RLS en el backend, no de ocultar esta key).

## Build / instalación manual

Sin deploy automático ni tienda conectada:

```bash
flutter build apk        # Android
flutter build ios        # iOS (requiere macOS + Xcode)
flutter install
```
