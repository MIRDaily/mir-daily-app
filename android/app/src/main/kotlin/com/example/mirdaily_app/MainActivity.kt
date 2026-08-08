package com.example.mirdaily_app

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Vibración por Vibrator/VibratorManager directamente (no por
 * View.performHapticFeedback, que en muchos móviles Android con skins OEM
 * (Oppo/OnePlus/Realme entre otros) queda silenciado por el interruptor de
 * "vibración táctil" del sistema aunque la vibración general esté activada,
 * haciendo que HapticFeedback.lightImpact()/mediumImpact()/heavyImpact() de
 * Flutter no se note. Esta vía solo depende del interruptor general de
 * vibración (y del permiso VIBRATE, ya declarado en el manifest).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.mirdaily.app/haptics"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "vibrate" -> {
                        val ms = (call.argument<Int>("ms") ?: 20).toLong()
                        val amplitude = call.argument<Int>("amplitude") ?: 180
                        vibrate(ms, amplitude)
                        result.success(null)
                    }
                    "vibratePattern" -> {
                        val timings = (call.argument<List<Int>>("timings") ?: emptyList())
                            .map { it.toLong() }
                            .toLongArray()
                        val amplitudes = call.argument<List<Int>>("amplitudes")?.toIntArray()
                        vibratePattern(timings, amplitudes)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun vibrate(ms: Long, amplitude: Int) {
        val vibrator = getVibrator() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(ms, amplitude.coerceIn(1, 255))
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(ms)
        }
    }

    /**
     * Patrón (golpe + zumbido sostenido, etc.) para efectos más "explosivos"
     * y largos que un solo impacto — p. ej. la explosión de confeti.
     * [timings]: duración de cada tramo en ms (delay/on/off/on/...).
     * [amplitudes]: amplitud (0-255) de cada tramo; 0 = silencio. Si es null,
     * se asume ON a máxima amplitud en los tramos impares (patrón clásico
     * delay-on-off-on-...).
     */
    private fun vibratePattern(timings: LongArray, amplitudes: IntArray?) {
        if (timings.isEmpty()) return
        val vibrator = getVibrator() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val amps = amplitudes ?: IntArray(timings.size) { i -> if (i % 2 == 1) 255 else 0 }
            vibrator.vibrate(VibrationEffect.createWaveform(timings, amps, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(timings, -1)
        }
    }
}
