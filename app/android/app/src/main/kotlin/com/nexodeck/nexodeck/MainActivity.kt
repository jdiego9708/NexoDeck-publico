package com.nexodeck.nexodeck

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Las dos piezas nativas que Flutter no cubre:
 *
 * - **MulticastLock** (Fase 4): el descubrimiento mDNS corre sobre un socket
 *   UDP multicast crudo del lado Rust (`mdns-sd`, no la API `NsdManager` de
 *   Android), y Android descarta paquetes multicast por defecto salvo que se
 *   mantenga adquirido el lock.
 * - **Accessory USB** (Fase 5-D): Android entrega el canal del cable como un
 *   `ParcelFileDescriptor`, que solo se puede abrir desde Java/Kotlin. Aca se
 *   lo abre y se manda a Dart **el numero del fd, nada mas** -- los bytes del
 *   protocolo nunca pasan por Dart, los lee Rust directo del descriptor.
 */
class MainActivity : FlutterActivity() {
    private val multicastChannelName = "com.nexodeck.nexodeck/multicast"
    private val usbChannelName = "com.nexodeck.nexodeck/usb_accessory"
    private val usbPermissionAction = "com.nexodeck.nexodeck.USB_PERMISSION"

    private var multicastLock: WifiManager.MulticastLock? = null
    private var usbChannel: MethodChannel? = null
    private var usbReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, multicastChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        acquireMulticastLock()
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        usbChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, usbChannelName).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        // Devuelve el fd del accessory ya abierto, o null si
                        // no hay cable / falta el permiso. Cuando falta, se
                        // lo pide: la respuesta llega despues por
                        // `onAccessoryAttached`, y Dart vuelve a llamar.
                        "openAccessoryFd" -> result.success(openAccessoryFd())
                        else -> result.notImplemented()
                    }
                }
            }

        registerUsbReceiver()
    }

    /**
     * Abre el accessory y **suelta** el descriptor con `detachFd()`: a partir
     * de ahi el dueño del fd es Rust, que lo cierra al terminar la sesion.
     * Cerrar el `ParcelFileDescriptor` aca (o dejar que el GC lo cierre)
     * seria un doble close sobre un fd que ya no es nuestro.
     */
    private fun openAccessoryFd(): Int? {
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val accessory = usbManager.accessoryList?.firstOrNull() ?: return null

        if (!usbManager.hasPermission(accessory)) {
            requestUsbPermission(usbManager, accessory)
            return null
        }

        val descriptor = usbManager.openAccessory(accessory) ?: return null
        return descriptor.detachFd()
    }

    private fun requestUsbPermission(usbManager: UsbManager, accessory: UsbAccessory) {
        // FLAG_IMMUTABLE es obligatorio desde API 31 y valido desde la 23;
        // el sistema no modifica este intent, asi que no hace falta mutable.
        val flags = PendingIntent.FLAG_IMMUTABLE
        val intent = Intent(usbPermissionAction).setPackage(packageName)
        val pendingIntent = PendingIntent.getBroadcast(this, 0, intent, flags)
        usbManager.requestPermission(accessory, pendingIntent)
    }

    private fun registerUsbReceiver() {
        if (usbReceiver != null) return

        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        UsbManager.ACTION_USB_ACCESSORY_ATTACHED,
                        usbPermissionAction -> usbChannel?.invokeMethod("onAccessoryAttached", null)
                        UsbManager.ACTION_USB_ACCESSORY_DETACHED ->
                            usbChannel?.invokeMethod("onAccessoryDetached", null)
                    }
                }
            }

        val filter =
            IntentFilter().apply {
                addAction(UsbManager.ACTION_USB_ACCESSORY_ATTACHED)
                addAction(UsbManager.ACTION_USB_ACCESSORY_DETACHED)
                addAction(usbPermissionAction)
            }

        // Desde API 33 hay que declarar explicitamente si el receiver es
        // exportado; el nuestro solo escucha broadcasts del sistema y del
        // propio proceso, asi que va NOT_EXPORTED.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        usbReceiver = receiver
    }

    /**
     * Con `launchMode="singleTop"`, si la app ya estaba abierta cuando la PC
     * arranco el accessory mode, el intent llega por aca en vez de por
     * `onCreate` -- sin esto, enchufar el cable con la app abierta no haria
     * nada.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == UsbManager.ACTION_USB_ACCESSORY_ATTACHED) {
            usbChannel?.invokeMethod("onAccessoryAttached", null)
        }
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifiManager.createMulticastLock("nexodeck-mdns")
        lock.setReferenceCounted(true)
        lock.acquire()
        multicastLock = lock
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseMulticastLock()
        usbReceiver?.let { runCatching { unregisterReceiver(it) } }
        usbReceiver = null
        super.onDestroy()
    }
}
