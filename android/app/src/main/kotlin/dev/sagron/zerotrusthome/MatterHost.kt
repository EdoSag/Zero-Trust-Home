package dev.sagron.zerotrusthome

/**
 * What [MatterPlugin] needs from the screen: things only an activity can
 * ask the person. Each answers once, on the main thread.
 */
interface MatterHost {
    /** True when the app may scan for and connect to Bluetooth devices. */
    fun allowBluetooth(done: (Boolean) -> Unit)

    /** True when the person turned Bluetooth on. */
    fun turnOnBluetooth(done: (Boolean) -> Unit)

    /** The text of a scanned QR code, or null when the person went back. */
    fun scanQrCode(done: (String?) -> Unit)
}
