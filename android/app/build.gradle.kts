plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mirdaily_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true  // ✅ CORREGIDO: agregado "is" y "="
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // ─────────────────────────────────────────────────────────────────
        // OJO: este id lleva el sufijo `.v5` SOLO para poder tener instaladas
        // a la vez v4 y v5 en el mismo telefono y compararlas. Android
        // considera dos apps distintas dos ids distintos, y esa es la unica
        // forma de que convivan.
        //
        // ANTES DE PUBLICAR hay que quitarlo y dejar el id de siempre, o
        // saldria una app nueva en vez de una actualizacion de la existente.
        // El id "de verdad" sigue siendo com.example.mirdaily_app.
        // ─────────────────────────────────────────────────────────────────
        applicationId = "com.example.mirdaily_app.v5"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true  // ✅ CORREGIDO: agregado "="
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // R8 se ejecuta en release; sin reglas de keep rompe
            // flutter_local_notifications (Gson "Missing type parameter.").
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ CORREGIDO: paréntesis en lugar de comillas simples
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
}
