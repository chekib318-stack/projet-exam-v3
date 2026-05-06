package tn.gov.education.examguard

// ALL imports must be at the top of the file in Kotlin
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ── Main Activity ─────────────────────────────────────────────────────────────
class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CH = "tn.gov.education.examguard/service"
        const val EVENT_CH  = "tn.gov.education.examguard/classic_bt"
        const val MAG_CH    = "tn.gov.education.examguard/magnetometer"
    }

    @Volatile private var eventSink: EventChannel.EventSink? = null
    private val pendingEvents = mutableListOf<Map<String, Any>>()
    private val pendingLock   = Any()
    private var scanner: UnifiedBtScanner? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── BT EventChannel ───────────────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CH)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    synchronized(pendingLock) {
                        for (ev in pendingEvents) sink?.success(ev)
                        pendingEvents.clear()
                    }
                }
                override fun onCancel(args: Any?) { eventSink = null }
            })

        // ── Magnetometer EventChannel ─────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MAG_CH)
            .setStreamHandler(MagnetometerHandler(this))

        // ── MethodChannel ─────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CH)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> { startBleService(); result.success(null) }
                    "stopService"  -> { stopBleService();  result.success(null) }
                    "startScan"    -> {
                        scanner?.stop()
                        scanner = UnifiedBtScanner(this, ::sendToFlutter)
                        scanner?.start()
                        result.success(null)
                    }
                    "stopScan" -> {
                        scanner?.stop()
                        scanner = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sendToFlutter(data: Map<String, Any>) {
        runOnUiThread {
            val sink = eventSink
            if (sink != null) {
                sink.success(data)
            } else {
                synchronized(pendingLock) {
                    if (pendingEvents.size < 200) pendingEvents.add(data)
                }
            }
        }
    }

    private fun startBleService() {
        val i = Intent(this, BleService::class.java).apply { action = BleService.ACTION_START }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
        else startService(i)
    }

    private fun stopBleService() {
        val i = Intent(this, BleService::class.java).apply { action = BleService.ACTION_STOP }
        startService(i)
    }

    override fun onDestroy() {
        scanner?.stop()
        super.onDestroy()
    }
}

// ── Magnetometer Handler — reads TYPE_MAGNETIC_FIELD sensor at max speed ──────
class MagnetometerHandler(private val ctx: Context) : EventChannel.StreamHandler {

    private var sensorManager: SensorManager? = null
    private var sensor: Sensor? = null
    private var listener: SensorEventListener? = null

    override fun onListen(args: Any?, events: EventChannel.EventSink) {
        sensorManager = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

        if (sensor == null) {
            events.error("NO_SENSOR", "Magnetometer not available on this device", null)
            return
        }

        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                // Send [x, y, z] in µT to Flutter
                events.success(listOf(
                    event.values[0].toDouble(),
                    event.values[1].toDouble(),
                    event.values[2].toDouble()
                ))
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        // SENSOR_DELAY_FASTEST ≈ 50 Hz — sufficient for audio-frequency detection
        sensorManager?.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_FASTEST)
    }

    override fun onCancel(args: Any?) {
        sensorManager?.unregisterListener(listener)
        listener = null
        sensorManager = null
    }
}
