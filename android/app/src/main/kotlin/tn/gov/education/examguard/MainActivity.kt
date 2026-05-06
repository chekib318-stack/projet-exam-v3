package tn.gov.education.examguard

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

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CH = "tn.gov.education.examguard/service"
        const val EVENT_CH  = "tn.gov.education.examguard/classic_bt"
        const val MAG_CH    = "tn.gov.education.examguard/magnetometer"
        const val MAG_POLL  = "tn.gov.education.examguard/mag_poll"
    }

    @Volatile private var eventSink: EventChannel.EventSink? = null
    private val pendingEvents = mutableListOf<Map<String, Any>>()
    private val pendingLock   = Any()
    private var scanner: UnifiedBtScanner? = null
    private var magHandler: MagnetometerHandler? = null

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
        val mHandler = MagnetometerHandler(this)
        magHandler   = mHandler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MAG_CH)
            .setStreamHandler(mHandler)

        // ── Magnetometer polling MethodChannel (backup) ───────────────────
        val pollingHandler = MagPollingHandler(mHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAG_POLL)
            .setMethodCallHandler { call, result ->
                result.success(pollingHandler.handleCall(call.method))
            }

        // ── BT MethodChannel ──────────────────────────────────────────────
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
                        scanner?.stop(); scanner = null; result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sendToFlutter(data: Map<String, Any>) {
        runOnUiThread {
            val sink = eventSink
            if (sink != null) sink.success(data)
            else synchronized(pendingLock) {
                if (pendingEvents.size < 200) pendingEvents.add(data)
            }
        }
    }

    private fun startBleService() {
        val i = Intent(this, BleService::class.java).apply { action = BleService.ACTION_START }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
        else startService(i)
    }

    private fun stopBleService() {
        startService(Intent(this, BleService::class.java).apply { action = BleService.ACTION_STOP })
    }

    override fun onDestroy() { scanner?.stop(); super.onDestroy() }
}
