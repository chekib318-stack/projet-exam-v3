package tn.gov.education.examguard

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper

@SuppressLint("MissingPermission")
class UnifiedBtScanner(
    private val context: Context,
    private val onDevice: (Map<String, Any>) -> Unit
) {
    private val adapter = BluetoothAdapter.getDefaultAdapter()
    private val mainH   = Handler(Looper.getMainLooper())
    private var running = false

    private var discoveryReceiver: BroadcastReceiver? = null
    private var bleCallback: ScanCallback? = null

    // GATT only for ALREADY-BONDED devices (no pairing dialog)
    private val gatts = mutableMapOf<String, BluetoothGatt>()

    fun start() {
        if (adapter == null || !adapter.isEnabled || running) return
        running = true
        startGattOnBondedOnly()  // safe — already paired
        startClassicDiscovery()  // RSSI from ACTION_FOUND only, no GATT
        startBleScan()           // RSSI from advertisements only, no GATT
    }

    // ── Bonded devices: GATT is OK (already paired, no dialog) ──────────────
    private fun startGattOnBondedOnly() {
        mainH.post {
            try {
                val bonded = adapter.bondedDevices ?: return@post
                for (dev in bonded) {
                    startGattRssi(dev)  // safe — already bonded
                }
            } catch (_: Exception) {}
        }
    }

    // ── BLE scan: use advertisement RSSI only, NO connectGatt ───────────────
    private fun startBleScan() {
        try {
            val scanner = adapter.bluetoothLeScanner ?: return
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setReportDelay(0)
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .build()

            bleCallback = object : ScanCallback() {
                override fun onScanResult(cbType: Int, result: ScanResult) {
                    if (!running) return
                    val rssi = result.rssi
                    if (rssi == 0 || rssi < -105) return
                    val name = try { result.device.name } catch (_: Exception) { null }
                        ?: result.scanRecord?.deviceName ?: ""
                    val addr = try { result.device.address } catch (_: Exception) { return }
                    val uuids = result.scanRecord?.serviceUuids
                        ?.map { it.toString().lowercase() }?.toSet() ?: emptySet()
                    // ✅ Send RSSI directly — NO connectGatt call here
                    send(addr, name, rssi, 0, "ble", classifyBle(name, uuids))
                }
                override fun onScanFailed(errorCode: Int) {}
            }
            scanner.startScan(null, settings, bleCallback!!)
        } catch (_: Exception) {}
    }

    // ── Classic discovery: use ACTION_FOUND RSSI only, NO connectGatt ───────
    private fun startClassicDiscovery() {
        discoveryReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val dev = getDevice(intent) ?: return
                        val rssi = intent.getShortExtra(
                            BluetoothDevice.EXTRA_RSSI, (-80).toShort()).toInt()
                        val name = try { dev.name ?: "" } catch (_: Exception) { "" }
                        val addr = try { dev.address ?: return } catch (_: Exception) { return }
                        val cls  = try { dev.bluetoothClass?.majorDeviceClass ?: 0 }
                                   catch (_: Exception) { 0 }
                        // ✅ Send RSSI directly — NO connectGatt call here
                        send(addr, name, rssi, cls, "discovery")
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        if (running) mainH.postDelayed({
                            try { adapter.startDiscovery() } catch (_: Exception) {}
                        }, 2000)
                    }
                }
            }
        }
        try {
            context.registerReceiver(discoveryReceiver, IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            })
            adapter.startDiscovery()
        } catch (_: Exception) {}
    }

    // ── GATT RSSI — ONLY for bonded devices (no pairing dialog triggered) ───
    private fun startGattRssi(device: BluetoothDevice) {
        val addr = try { device.address ?: return } catch (_: Exception) { return }
        if (gatts.containsKey(addr)) return

        try {
            val cb = object : BluetoothGattCallback() {
                override fun onConnectionStateChange(
                    gatt: BluetoothGatt, status: Int, newState: Int
                ) {
                    when (newState) {
                        BluetoothProfile.STATE_CONNECTED    -> scheduleRead(gatt, addr)
                        BluetoothProfile.STATE_DISCONNECTED -> {
                            gatts.remove(addr)
                            try { gatt.close() } catch (_: Exception) {}
                            // Send "gone" so Flutter removes the device
                            onDevice(mapOf("address" to addr, "name" to "",
                                "rssi" to 0, "major" to 0,
                                "type" to "gone", "protocol" to "gone"))
                            // Retry once after 6s
                            mainH.postDelayed({
                                if (running && !gatts.containsKey(addr))
                                    startGattRssi(device)
                            }, 6000)
                        }
                    }
                }

                override fun onReadRemoteRssi(
                    gatt: BluetoothGatt, rssi: Int, status: Int
                ) {
                    if (status == BluetoothGatt.GATT_SUCCESS && running) {
                        val name = try { device.name ?: "" } catch (_: Exception) { "" }
                        val cls  = try { device.bluetoothClass?.majorDeviceClass ?: 0 }
                                   catch (_: Exception) { 0 }
                        send(addr, name, rssi, cls, "gatt_rssi")
                        scheduleRead(gatt, addr)
                    }
                }
            }

            val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                device.connectGatt(context, false, cb, BluetoothDevice.TRANSPORT_AUTO)
            else
                device.connectGatt(context, false, cb)

            if (gatt != null) gatts[addr] = gatt
        } catch (_: Exception) {}
    }

    private fun scheduleRead(gatt: BluetoothGatt, addr: String) {
        mainH.postDelayed({
            if (running && gatts.containsKey(addr)) {
                try { gatt.readRemoteRssi() } catch (_: Exception) {}
            }
        }, 800)
    }

    fun stop() {
        running = false
        mainH.removeCallbacksAndMessages(null)
        try { adapter?.cancelDiscovery() } catch (_: Exception) {}
        try { discoveryReceiver?.let { context.unregisterReceiver(it) } }
            catch (_: Exception) {}
        try { adapter?.bluetoothLeScanner?.stopScan(bleCallback) }
            catch (_: Exception) {}
        for ((_, g) in gatts) {
            try { g.disconnect(); g.close() } catch (_: Exception) {}
        }
        gatts.clear()
        discoveryReceiver = null
        bleCallback = null
    }

    private fun send(
        addr: String, name: String, rssi: Int, major: Int,
        protocol: String, typeOverride: String? = null
    ) {
        val type = typeOverride ?: classifyMajor(major, name)
        onDevice(mapOf("address" to addr, "name" to name, "rssi" to rssi,
            "major" to major, "type" to type, "protocol" to protocol))
    }

    private fun getDevice(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            intent.getParcelableExtra(
                BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        else @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

    private fun classifyBle(name: String, uuids: Set<String>): String {
        val n = name.lowercase()
        val audioUuids = listOf("0000110b","0000111e","00001108","0000110a","0000111f")
        if (uuids.any { u -> audioUuids.any { p -> u.startsWith(p) } }) return "earbuds"
        if (n.contains("buds")    || n.contains("airpod") || n.contains("earbud") ||
            n.contains("headset") || n.contains("jabra")  || n.contains("bose")   ||
            n.contains("headphone")|| n.contains("jbl")   || n.contains("sony wf")||
            n.contains("galaxy buds")) return "earbuds"
        if (n.contains("watch") || n.contains("band") || n.contains("amazfit"))
            return "watch"
        if (n.contains("glass")) return "glasses"
        return "unknown"
    }

    private fun classifyMajor(major: Int, name: String): String {
        val n = name.lowercase()
        if (n.contains("airpods") || n.contains("buds") || n.contains("earbud") ||
            n.contains("headset") || n.contains("jabra") || n.contains("headphone") ||
            n.contains("bose")    || n.contains("jbl")) return "earbuds"
        if (n.contains("watch") || n.contains("band")) return "watch"
        if (n.contains("glass")) return "glasses"
        return when (major) {
            0x0200 -> "phone"; 0x0400 -> "earbuds"
            0x0100 -> "computer"; 0x0700 -> "watch"
            else   -> "unknown"
        }
    }
}
