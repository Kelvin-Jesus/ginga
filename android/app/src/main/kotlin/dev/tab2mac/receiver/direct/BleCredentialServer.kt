package dev.tab2mac.receiver.direct

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.ParcelUuid
import dev.tab2mac.receiver.AppLog
import java.util.UUID

/**
 * The §6b GATT service: the credentials characteristic (read, a fresh sealed blob per read,
 * served in pieces for long reads) and the Mac-address characteristic (write, including prepared
 * long writes). Advertised with the service UUID only (no name), balanced mode, while the direct
 * link waits for the Mac. Contents are never logged.
 */
@SuppressLint("MissingPermission") // checked in start(); requested by MainActivity
class BleCredentialServer(context: Context) : CredentialServer {
    private val context = context.applicationContext
    private val manager: BluetoothManager? = this.context.getSystemService(BluetoothManager::class.java)
    private var server: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertising: AdvertiseCallback? = null

    /** Per device: the blob being read, and a long write being assembled. */
    private val reads = HashMap<String, ByteArray>()
    private val writes = HashMap<String, ByteArray>()

    override fun start(credentials: () -> ByteArray, onAddress: (ByteArray) -> Boolean, onFailed: (String) -> Unit) {
        val granted = listOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
            .all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        if (!granted) return onFailed("Bluetooth permission not granted")
        val adapter = manager?.adapter ?: return onFailed("no Bluetooth")
        if (!adapter.isEnabled) return onFailed("Bluetooth is off")
        val advertiser = adapter.bluetoothLeAdvertiser ?: return onFailed("this tablet can't advertise over Bluetooth LE")
        this.advertiser = advertiser

        val callback = object : BluetoothGattServerCallback() {
            override fun onServiceAdded(status: Int, service: BluetoothGattService) {
                if (status != BluetoothGatt.GATT_SUCCESS) return onFailed("GATT service not added ($status)")
                startAdvertising(advertiser, onFailed)
            }

            override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
                val server = server ?: return
                if (characteristic.uuid != CREDENTIALS) {
                    server.sendResponse(device, requestId, BluetoothGatt.GATT_READ_NOT_PERMITTED, offset, null)
                    return
                }
                val blob = synchronized(reads) {
                    if (offset == 0) credentials().also { reads[device.address] = it } else reads[device.address]
                }
                if (blob == null || offset > blob.size) {
                    server.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, offset, null)
                } else {
                    server.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, blob.copyOfRange(offset, blob.size))
                }
            }

            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray?,
            ) {
                val server = server ?: return
                val bytes = value ?: ByteArray(0)
                if (characteristic.uuid != ADDRESS || offset + bytes.size > MAX_WRITE) {
                    if (responseNeeded) server.sendResponse(device, requestId, BluetoothGatt.GATT_WRITE_NOT_PERMITTED, offset, null)
                    return
                }
                val status = if (preparedWrite) {
                    synchronized(writes) {
                        val pending = writes[device.address] ?: ByteArray(0)
                        val grown = if (pending.size < offset + bytes.size) pending.copyOf(offset + bytes.size) else pending
                        bytes.copyInto(grown, offset)
                        writes[device.address] = grown
                    }
                    BluetoothGatt.GATT_SUCCESS
                } else if (offset == 0 && onAddress(bytes)) {
                    BluetoothGatt.GATT_SUCCESS
                } else {
                    BluetoothGatt.GATT_FAILURE
                }
                if (responseNeeded) server.sendResponse(device, requestId, status, offset, if (preparedWrite) bytes else null)
            }

            override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) {
                val server = server ?: return
                val pending = synchronized(writes) { writes.remove(device.address) }
                val status = if (!execute || pending == null) {
                    BluetoothGatt.GATT_SUCCESS
                } else if (onAddress(pending)) {
                    BluetoothGatt.GATT_SUCCESS
                } else {
                    BluetoothGatt.GATT_FAILURE
                }
                server.sendResponse(device, requestId, status, 0, null)
            }
        }
        val server = manager.openGattServer(context, callback) ?: return onFailed("GATT server unavailable")
        this.server = server
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(BluetoothGattCharacteristic(CREDENTIALS, BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ))
            addCharacteristic(BluetoothGattCharacteristic(ADDRESS, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE))
        }
        if (!server.addService(service)) onFailed("GATT service not added")
    }

    private fun startAdvertising(advertiser: BluetoothLeAdvertiser, onFailed: (String) -> Unit) {
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) = AppLog.i("direct.advertising")

            override fun onStartFailure(errorCode: Int) = onFailed("advertising failed ($errorCode)")
        }
        advertising = callback
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder().setIncludeDeviceName(false).addServiceUuid(ParcelUuid(SERVICE)).build()
        advertiser.startAdvertising(settings, data, callback)
    }

    override fun stop() {
        advertising?.let { callback ->
            try {
                advertiser?.stopAdvertising(callback)
            } catch (_: IllegalStateException) {
                // Bluetooth already off.
            }
        }
        advertising = null
        server?.close()
        server = null
        synchronized(reads) { reads.clear() }
        synchronized(writes) { writes.clear() }
    }

    companion object {
        val SERVICE: UUID = UUID.fromString("5432D1EC-7D1A-4F5B-9A6E-0E2A6D3C0001")
        val CREDENTIALS: UUID = UUID.fromString("5432D1EC-7D1A-4F5B-9A6E-0E2A6D3C0002")
        val ADDRESS: UUID = UUID.fromString("5432D1EC-7D1A-4F5B-9A6E-0E2A6D3C0003")

        /** An address blob is ~120 bytes; anything this large is not one. */
        private const val MAX_WRITE = 512
    }
}
