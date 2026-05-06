package tn.gov.education.examguard

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ── Robust Magnetometer — EventChannel + MethodChannel polling ─────────────────
class MagnetometerHandler(private val ctx: Context) : EventChannel.StreamHandler {

    private var sm: SensorManager? = null
    private var sensor: Sensor? = null
    private var listener: SensorEventListener? = null

    // Latest values accessible via MethodChannel polling
    @Volatile var lastX = 0.0
    @Volatile var lastY = 0.0
    @Volatile var lastZ = 0.0
    @Volatile var hasData = false

    override fun onListen(args: Any?, events: EventChannel.EventSink) {
        sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager

        // Try MAGNETIC_FIELD first, fallback to MAGNETIC_FIELD_UNCALIBRATED
        sensor = sm?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
            ?: sm?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD_UNCALIBRATED)

        if (sensor == null) {
            events.error("NO_SENSOR", "No magnetometer found", null)
            return
        }

        listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val x = e.values[0].toDouble()
                val y = e.values[1].toDouble()
                val z = e.values[2].toDouble()
                lastX = x; lastY = y; lastZ = z; hasData = true
                events.success(listOf(x, y, z))
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }

        // Try multiple delays — GAME is more compatible than FASTEST
        val registered = sm?.registerListener(
            listener, sensor, SensorManager.SENSOR_DELAY_GAME)
            ?: false

        if (registered == false) {
            // Fallback: NORMAL delay
            sm?.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    override fun onCancel(args: Any?) {
        sm?.unregisterListener(listener)
        listener = null
        sm = null
        hasData = false
    }
}

// ── MethodChannel handler for polling (backup when EventChannel fails) ─────────
class MagPollingHandler(private val handler: MagnetometerHandler) {
    fun handleCall(method: String): Any? {
        return when (method) {
            "getMagData" -> if (handler.hasData) mapOf(
                "x" to handler.lastX,
                "y" to handler.lastY,
                "z" to handler.lastZ
            ) else null
            "hasMagSensor" -> handler.hasData
            else -> null
        }
    }
}
