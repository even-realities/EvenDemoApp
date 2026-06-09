# EvenDemoApp — G1 Bluetooth Connection Flow

> **How this doc was written**: Same layering style as the `even-ble-logic` skill (G2/R1): **App → protocol → native GATT**. This repo is a **G1 demo**: both platforms use **Flutter `MethodChannel` + native BLE**. It does **not** use `flutter_ezw_ble` or `even_connect`.

> Chinese version: [G1_BLE_CONNECTION.md](G1_BLE_CONNECTION.md)

---

## 1. Architecture overview

```
lib/ble_manager.dart (Dart)
  └─ MethodChannel("method.bluetooth")
       ├─ Android: BleChannelHelper / BleMethodChannel → BleManager.kt
       └─ iOS:     AppDelegate.swift → BluetoothManager.swift

Downlink: Dart invokeMethod("send", { data, lr? }) → native GATT write
Uplink:   Android EventChannel("eventBleReceive") / iOS blueInfoSink → Dart
Status:   native methodChannel.invokeMethod → Dart setMethodCallHandler
```

| Channel | Direction | Purpose |
|---------|-----------|---------|
| `method.bluetooth` | Bidirectional | `startScan`, `stopScan`, `connectToGlasses`, `disconnectFromGlasses`, `send`, etc. |
| `eventBleReceive` | Native → Dart | Binary notifications and app payloads (`lr`, `data`, `type`) |

Dart entry point: `BleManager` in `lib/ble_manager.dart`.

---

## 2. G1 device model and advertising names

G1 uses **two BLE peripherals (left and right)** paired by a **channel number**:

- Example names (from Android comments): `G1_45_L_92333`, `G1_45_R_xxxx` (left contains `_L_`, right `_R_`).
- Android scan filter (summary):
  - Non-empty advertised name;
  - Name matches `G` + digit(s) (e.g. `G1`);
  - Split by `_` yields **four** segments (matches the sample shape);
  - Only after **both** left and right exist for the same `channel` does native code notify Flutter of a **paired** set.

The map sent to Flutter includes: `leftDeviceName`, `rightDeviceName`, `channelNumber`.

**Connect argument**: Flutter usually passes `deviceName` as `Pair_{channelNumber}`. On Android, `BleMethodChannel.connectToGlasses` **strips the `Pair_` prefix** and passes only the channel string into `BleManager.connectToGlass`.

---

## 3. GATT service and characteristics (Nordic UART-style)

Android and iOS share the **same UART service UUIDs** (constants in `ServiceIdentifiers.swift` and `BleManager.kt`):

| Role | UUID |
|------|------|
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX (phone writes) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX (phone enables notify) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

**Android** (`onServicesDiscovered`): enable notify on RX, write the CCCD (`00002902-...`), then `requestMtu(251)`, `createBond()`, send an initial `0xF4 0x01` to **both** ears at the end of that ear’s setup path; call `glassesConnected` only when **both** `isConnect` flags are true.

**iOS** (`didDiscoverCharacteristicsFor`): bind left/right `CBPeripheral`, hold `leftWChar`/`rightWChar` and `leftRChar`/`rightRChar`, `setNotifyValue(true)` on RX, then write `0x4d 0x01` per side (different first bytes from Android—platform implementation drift).

---

## 4. Flutter (Dart) connection and state flow

1. **Scan**: `BleManager.startScan()` → `invokeMethod('startScan')`.
2. **Paired set found**: native `invokeMethod('foundPairedGlasses', {...})` → `_onPairedGlassesFound`; dedupe by `channelNumber` into `pairedGlasses`.
3. **Connect**: `connectToGlasses(deviceName)` → `invokeMethod('connectToGlasses', {'deviceName': deviceName})`; set local `connectionStatus` to `Connecting...`.
4. **Connected**: `glassesConnected` → `_onGlassesConnected`: set `isConnected`, show left/right names, `startSendBeatHeart()` (periodic `Proto.sendHeartBeat()`).
5. **Disconnected**: `glassesDisconnected` (when native invokes it) → `_onGlassesDisconnected`.
6. **Receive**: listen on `EventChannel('eventBleReceive')`; `_handleReceivedData` parses commands (e.g. `0xF5` touchpad / EvenAI events).

---

## 5. Android details (`BleManager.kt`)

### 5.1 Init

`BleManager.initBluetooth(Activity)`: weak reference to `Activity`, obtain `BluetoothManager` / `Adapter`.

### 5.2 Scan

- `startScan`: after BT on + permission checks, `bluetoothLeScanner.startScan`.
- `ScanCallback.onScanResult`: parse name, dedupe, group by channel; when left+right exist, `BleChannelHelper.bleMC.flutterFoundPairedGlasses(BlePairDevice(...))`.
- `stopScan`: `stopScan(scanCallback)`.

### 5.3 Connect

- `connectToGlass(deviceChannel)`: resolve left/right `BleDevice` in `bleDevices` (or current `connectedDevice`) using `_{channel}_L_` / `_{channel}_R_`; else `PeripheralNotFound`.
- `connectGatt` on each `BluetoothDevice` with `autoConnect=false`, shared `BluetoothGattCallback`.

### 5.4 GATT callback highlights

- `onConnectionStateChange`: on `STATE_CONNECTED`, `discoverServices()`.
- `onServicesDiscovered`: attach `BluetoothGatt`, enable RX notify, write CCCD, cache write char, `requestMtu(251)`, `createBond()`, mark side connected, send `0xF4 0x01`; if `BlePairDevice.isBothConnected()`, invoke `flutterGlassesConnected` on the UI thread.
- `onCharacteristicChanged`: infer L/R by address; `0xF1` + length 202 → LC3→PCM via `Cpp.decodeLC3`; else `BleChannelHelper.bleReceive` to Dart.

### 5.5 Disconnect

`disconnectFromGlasses` currently only logs and returns success—**no** full GATT disconnect/close path (fill in for production).

---

## 6. iOS details (`BluetoothManager.swift`, `AppDelegate.swift`)

### 6.1 Channel wiring

`AppDelegate` creates `FlutterMethodChannel(name: "method.bluetooth", ...)`, binds `BluetoothManager`, registers `FlutterStreamHandler` for `eventBleReceive` / `eventSpeechRecognize`, assigns the receive sink to `BluetoothManager.blueInfoSink`.

### 6.2 Scan and pairing map

`centralManager.scanForPeripherals(withServices: nil)`. In `didDiscover`, `_L_` / `_R_` populate `pairedDevices["Pair_\(channelNumber)"]`; when both slots are set, `invokeMethod("foundPairedGlasses", ...)`.

### 6.3 Connect

`connectToDevice(deviceName:)`: `stopScan`, read left/right `CBPeripheral` from `pairedDevices[deviceName]`, `centralManager.connect` both, store `currentConnectingDeviceName`.

### 6.4 When “connected” fires (important vs Android)

In `didConnect`: set peripheral delegate and `discoverServices([UARTServiceUUID])`; when **both** slots in `connectedDevices[deviceName]` hold a peripheral, immediately `invokeMethod("glassesConnected", ...)` and clear `currentConnectingDeviceName`.

So on iOS, **`glassesConnected` fires after the central links both peripherals**, **without waiting** for service/characteristic discovery or notify setup. Android fires **after** both sides finish GATT discovery and notify enablement. Plan integration tests around this gap.

### 6.5 Disconnect / reconnect

`didDisconnectPeripheral` calls **`central.connect(peripheral)` again** (reconnect bias), unlike Android’s minimal disconnect stub.

### 6.6 Receive path

`didUpdateValueFor` → `getCommandValue`: `BLE_REQ_TRANSFER_MIC_DATA` goes to speech PCM pipeline; otherwise build a map and call `blueInfoSink` for Dart.

---

## 7. Post-connect Dart behavior

- **Heartbeat**: after connect, every 8s `Proto.sendHeartBeat()` with short retries (`BleManager.startSendBeatHeart`).
- **Request/response**: `BleManager.request` / `requestRetry` sends via `send` on the method channel; first-byte command + `lr` key completes `Completer`s in `_handleReceivedData`.

---

## 8. Known implementation caveats

1. **Mismatched “connected” timing** between Android and iOS (§6.4): Flutter may think both sides are ready before iOS finishes GATT setup.
2. **Android `disconnectFromGlasses`** does not fully tear down GATT.
3. **`BleManager.isBothConnected()`** is hard-coded `true` in Dart (TODO)—unsafe if you rely on real link state.
4. **First packet bytes**: Android `0xF4 0x01` vs iOS `0x4d 0x01`—align with firmware docs if the protocol is strict.

---

## 9. Source index

| Area | Path |
|------|------|
| Dart BLE facade | `lib/ble_manager.dart` |
| Android BLE core | `android/app/src/main/kotlin/com/example/demo_ai_even/bluetooth/BleManager.kt` |
| Android channel | `android/app/src/main/kotlin/com/example/demo_ai_even/bluetooth/BleChannelHelper.kt` |
| Android models | `android/app/src/main/kotlin/com/example/demo_ai_even/model/BleDevice.kt`, `BlePairDevice.kt` |
| iOS BLE core | `ios/Runner/BluetoothManager.swift` |
| iOS UUID constants | `ios/Runner/ServiceIdentifiers.swift` |
| iOS channel registration | `ios/Runner/AppDelegate.swift` |

---

*Derived from the current EvenDemoApp source tree. Update §2–§3 and first-byte notes if firmware or channel contracts change.*
