package com.haam.haam_remote

import android.Manifest
import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Lets the phone act as a Bluetooth keyboard with TV keys (Android's HID
 * device profile, Android 9+), so the TV can be controlled without Wi-Fi.
 *
 * This is only a bridge: the report descriptor, the key table and the
 * reports are built in Dart (lib/src/bluetooth/), where they are tested.
 */
@SuppressLint("MissingPermission") // every entry point checks hasPermission() first
class BluetoothHidBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methods = MethodChannel(messenger, "haam/bluetooth_hid")
    private val events = EventChannel(messenger, "haam/bluetooth_hid/events")
    private val main = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingEnable: MethodChannel.Result? = null
    private val session: HidSession? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && adapter != null) HidSession() else null

    private val bondReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
            val device = deviceExtra(intent) ?: return
            val state = when (intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)) {
                BluetoothDevice.BOND_BONDED -> "bonded"
                BluetoothDevice.BOND_BONDING -> "bonding"
                else -> "none"
            }
            emit(mapOf("type" to "bond", "state" to state, "address" to device.address))
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(bondReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            activity.registerReceiver(bondReceiver, filter)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            handle(call, result)
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("argument", e.message, null)
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                mapOf(
                    "supported" to (session != null),
                    "enabled" to (adapter?.isEnabled == true),
                    "permission" to hasPermission(),
                    "registered" to (session?.registered == true),
                    "connected" to session?.connected?.address,
                    "phoneName" to (if (hasPermission()) adapter?.name else null),
                ),
            )
            "requestPermission" -> requestPermission(result)
            "requestEnable" -> requestEnable(result)
            "register" -> {
                val s = session ?: return result.success(false)
                if (!hasPermission()) return result.error("permission", "Bluetooth permission missing", null)
                s.register(call.argument<String>("name") ?: "Phone remote", call.argument<ByteArray>("descriptor")!!, result)
            }
            "unregister" -> {
                session?.unregister()
                result.success(null)
            }
            "pair" -> {
                if (!hasPermission()) return result.error("permission", "Bluetooth permission missing", null)
                val device = adapter!!.getRemoteDevice(call.argument<String>("address")!!.uppercase())
                result.success(
                    when {
                        device.bondState == BluetoothDevice.BOND_BONDED -> "bonded"
                        device.bondState == BluetoothDevice.BOND_BONDING -> "bonding"
                        device.createBond() -> "bonding"
                        else -> "failed"
                    },
                )
            }
            "connect" -> {
                val s = session ?: return result.success(false)
                if (!hasPermission()) return result.error("permission", "Bluetooth permission missing", null)
                result.success(s.connect(adapter!!.getRemoteDevice(call.argument<String>("address")!!.uppercase())))
            }
            "disconnect" -> {
                session?.disconnect()
                result.success(null)
            }
            "send" -> {
                val s = session ?: return result.success(false)
                result.success(s.send(call.argument<Int>("id")!!, call.argument<ByteArray>("data")!!))
            }
            "bondedDevices" -> {
                if (!hasPermission()) return result.success(emptyList<Map<String, String>>())
                result.success(
                    adapter?.bondedDevices.orEmpty().map { mapOf("name" to (it.name ?: it.address), "address" to it.address) },
                )
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- events

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    // ----------------------------------------------- permission and enabling

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) return result.success(true)
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST_PERMISSION)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_PERMISSION) return
        pendingPermission?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        pendingPermission = null
    }

    private fun requestEnable(result: MethodChannel.Result) {
        if (adapter == null) return result.success(false)
        if (adapter.isEnabled) return result.success(true)
        if (!hasPermission()) return result.error("permission", "Bluetooth permission missing", null)
        pendingEnable?.success(false)
        pendingEnable = result
        @Suppress("DEPRECATION")
        activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != REQUEST_ENABLE) return
        pendingEnable?.success(resultCode == Activity.RESULT_OK || adapter?.isEnabled == true)
        pendingEnable = null
    }

    fun dispose() {
        try {
            activity.unregisterReceiver(bondReceiver)
        } catch (e: IllegalArgumentException) {
            // Was not registered.
        }
        try {
            session?.close()
        } catch (e: SecurityException) {
            // Permission was revoked; the system drops the registration anyway.
        }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    private fun deviceExtra(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    // ------------------------------------------------------- the HID device

    @TargetApi(Build.VERSION_CODES.P)
    private inner class HidSession {
        private val executor: ExecutorService = Executors.newSingleThreadExecutor()
        private var proxy: BluetoothHidDevice? = null
        private var sdp: BluetoothHidDeviceAppSdpSettings? = null
        private var pendingRegister: MethodChannel.Result? = null
        var registered = false
            private set
        var connected: BluetoothDevice? = null
            private set

        private val callback = object : BluetoothHidDevice.Callback() {
            override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
                main.post {
                    this@HidSession.registered = registered
                    if (!registered) connected = null
                    pendingRegister?.success(registered)
                    pendingRegister = null
                    sink?.success(mapOf("type" to "app", "registered" to registered))
                }
            }

            override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
                main.post {
                    when (state) {
                        BluetoothProfile.STATE_CONNECTED -> connected = device
                        BluetoothProfile.STATE_DISCONNECTED ->
                            if (connected?.address == device.address) connected = null
                    }
                    val name = when (state) {
                        BluetoothProfile.STATE_CONNECTED -> "connected"
                        BluetoothProfile.STATE_CONNECTING -> "connecting"
                        BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
                        else -> "disconnected"
                    }
                    sink?.success(mapOf("type" to "connection", "state" to name, "address" to device.address))
                }
            }

            override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
                // Hosts may poll the current state: nothing is pressed.
                proxy?.replyReport(device, type, id, ByteArray(if (id.toInt() == 1) 8 else 2))
            }

            override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) {
                proxy?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
            }
        }

        fun register(name: String, descriptor: ByteArray, result: MethodChannel.Result) {
            if (registered) return result.success(true)
            pendingRegister?.success(false)
            pendingRegister = result
            sdp = BluetoothHidDeviceAppSdpSettings(
                name,
                "Remote control for the TV",
                "HAAM Remote",
                BluetoothHidDevice.SUBCLASS1_KEYBOARD,
                descriptor,
            )
            val existing = proxy
            if (existing != null) {
                registerWith(existing)
                return
            }
            val ok = adapter!!.getProfileProxy(
                activity,
                object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(profile: Int, p: BluetoothProfile) {
                        val hid = p as BluetoothHidDevice
                        proxy = hid
                        registerWith(hid)
                    }

                    override fun onServiceDisconnected(profile: Int) {
                        proxy = null
                        registered = false
                        connected = null
                        sink?.success(mapOf("type" to "app", "registered" to false))
                    }
                },
                BluetoothProfile.HID_DEVICE,
            )
            if (!ok) {
                pendingRegister?.success(false)
                pendingRegister = null
            }
        }

        private fun registerWith(hid: BluetoothHidDevice) {
            val settings = sdp ?: return
            if (!hid.registerApp(settings, null, null, executor, callback)) {
                pendingRegister?.success(false)
                pendingRegister = null
            }
            // Otherwise onAppStatusChanged completes the call.
        }

        fun unregister() {
            proxy?.unregisterApp()
            registered = false
            connected = null
        }

        fun connect(device: BluetoothDevice): Boolean = proxy?.connect(device) == true

        fun disconnect() {
            val device = connected ?: return
            proxy?.disconnect(device)
        }

        fun send(id: Int, data: ByteArray): Boolean {
            val device = connected ?: return false
            return proxy?.sendReport(device, id, data) == true
        }

        fun close() {
            unregister()
            proxy?.let { adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, it) }
            proxy = null
            executor.shutdown()
        }
    }

    private companion object {
        const val REQUEST_PERMISSION = 4711
        const val REQUEST_ENABLE = 4712
    }
}
