# ===========================================================================
# Reglas R8/ProGuard para el build de release.
#
# flutter_local_notifications usa Gson para (de)serializar las notificaciones
# programadas guardadas en SharedPreferences. R8, al minificar, borra las
# firmas genéricas (Signature) y los TypeToken anónimos, lo que provoca el
# crash "Missing type parameter." al reprogramar/cancelar notificaciones
# (ScheduledNotificationBootReceiver, cancel, etc.).
#
# Mantener las firmas genéricas + las clases de Gson y del plugin lo resuelve.
# ===========================================================================

# Conserva la información de tipos genéricos (imprescindible para Gson TypeToken).
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Plugin de notificaciones locales (usa Gson vía reflexión).
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Gson y sus TypeToken (no obfuscar ni eliminar).
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.gson.**
