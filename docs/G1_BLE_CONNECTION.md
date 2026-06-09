# EvenDemoApp — G1 蓝牙连接流程说明

> **分析依据**：参考仓库内 BLE 分层与文档化习惯（与 `even-ble-logic` 技能中 G2/R1 的「App → 协议 → 原生 GATT」思路一致）。本工程为 **G1 演示应用**，双端均为 **Flutter MethodChannel + 平台原生 BLE**，**未**接入 `flutter_ezw_ble` / `even_connect`。

---

## 1. 架构总览

```
lib/ble_manager.dart (Dart)
  └─ MethodChannel("method.bluetooth")
       ├─ Android: BleChannelHelper / BleMethodChannel → BleManager.kt
       └─ iOS:     AppDelegate.swift → BluetoothManager.swift

数据下行: Dart invokeMethod("send", { data, lr? }) → 原生写 GATT 特征值
数据上行: Android EventChannel("eventBleReceive") / iOS blueInfoSink → Dart
状态回调: 原生 methodChannel.invokeMethod → Dart setMethodCallHandler
```

| 通道名 | 方向 | 用途 |
|--------|------|------|
| `method.bluetooth` | 双向 | `startScan` / `stopScan` / `connectToGlasses` / `disconnectFromGlasses` / `send` 等 |
| `eventBleReceive` | 原生 → Dart | 二进制通知与业务数据（含 `lr`、`data`、`type`） |

Dart 侧入口：`lib/ble_manager.dart` 中的 `BleManager`。

---

## 2. G1 设备模型与广播命名

G1 为 **左右耳各一颗 BLE 外设**，通过 **信道号（channel）** 成对：

- 命名示例（Android 注释）：`G1_45_L_92333`、`G1_45_R_xxxx`（左 `_L_`，右 `_R_`）。
- Android 扫描过滤条件（逻辑摘要）：
  - 广播名非空；
  - 名称匹配 `G` + 数字（如 `G1`）；
  - 按下划线分段后 **段数为 4**（与示例格式一致）；
  - 同一 `channel` 下凑齐 **左 + 右** 两颗后，才向 Flutter 上报「已发现成对眼镜」。

成对后在 Flutter 列表中的字典包含：`leftDeviceName`、`rightDeviceName`、`channelNumber`。

**连接入参**：Flutter 调用 `connectToGlasses` 时传入的 `deviceName` 一般为 `Pair_{channelNumber}`。Android 侧在 `BleMethodChannel.connectToGlasses` 中会 **去掉 `Pair_` 前缀**，仅把信道号交给 `BleManager.connectToGlass`。

---

## 3. GATT 服务与特征（Nordic UART 风格）

Android 与 iOS 使用 **同一套 UART Service UUID**（与 `ServiceIdentifiers.swift` / `BleManager.kt` 常量一致）：

| 角色 | UUID |
|------|------|
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX（手机写入） | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX（手机订阅通知） | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

Android 在 `onServicesDiscovered` 中：对 RX 开启 `setCharacteristicNotification`，并写入 CCCD（`00002902-...`）启用通知；随后 `requestMtu(251)`、`createBond()`，并在单耳流程末尾向 **双耳** 发送首包 `0xF4 0x01`；**仅当左右 `isConnect` 均为 true** 时调用 `glassesConnected`。

iOS 在 `didDiscoverCharacteristicsFor` 中：区分左右 `CBPeripheral`，保存 `leftWChar`/`rightWChar`、`leftRChar`/`rightRChar`，对 RX `setNotifyValue(true)`，并分别向左右写入 `0x4d 0x01`（与 Android 首包字节不同，属平台实现差异）。

---

## 4. Flutter（Dart）连接与状态流程

1. **扫描**：`BleManager.startScan()` → `invokeMethod('startScan')`。
2. **发现成对设备**：原生 `invokeMethod('foundPairedGlasses', {...})` → `_onPairedGlassesFound`，按 `channelNumber` 去重后加入 `pairedGlasses`。
3. **连接**：`connectToGlasses(deviceName)` → `invokeMethod('connectToGlasses', {'deviceName': deviceName})`，本地将 `connectionStatus` 置为 `Connecting...`。
4. **已连接**：`glassesConnected` → `_onGlassesConnected`：更新 `isConnected`、展示左右名称，并 `startSendBeatHeart()`（定时调用 `Proto.sendHeartBeat()`）。
5. **断开**：`glassesDisconnected`（若原生实现调用）→ `_onGlassesDisconnected`。
6. **接收数据**：订阅 `EventChannel('eventBleReceive')`，在 `_handleReceivedData` 中解析指令（如 `0xF5` 触控/EvenAI 事件等）。

---

## 5. Android 详细流程（`BleManager.kt`）

### 5.1 初始化

`BleManager.initBluetooth(Activity)`：保存 `Activity` 弱引用，获取系统 `BluetoothManager` / `Adapter`。

### 5.2 扫描

- `startScan`：校验蓝牙开启与权限后，`bluetoothLeScanner.startScan`。
- `ScanCallback.onScanResult`：解析设备名、去重、按 channel 聚类；左右齐全时 `BleChannelHelper.bleMC.flutterFoundPairedGlasses(BlePairDevice(...))`。
- `stopScan`：`stopScan(scanCallback)`。

### 5.3 连接

- `connectToGlass(deviceChannel)`：在 `bleDevices`（或当前 `connectedDevice`）中按 `_{channel}_L_` / `_{channel}_R_` 查找左右 `BleDevice`；找不到则 `PeripheralNotFound`。
- 对左右 `BluetoothDevice` 各调用 `connectGatt(..., autoConnect=false, callback)`。
- 共享一个 `BluetoothGattCallback` 实例处理双耳。

### 5.4 GATT 回调要点

- `onConnectionStateChange`：`STATE_CONNECTED` → `discoverServices()`。
- `onServicesDiscovered`：绑定对应侧的 `BluetoothGatt`、打开 RX 通知、写 CCCD、保存 Write 特征、`requestMtu(251)`、`createBond()`、标记该侧已连接、发 `0xF4 0x01`；若 `BlePairDevice.isBothConnected()`，在主线程 `flutterGlassesConnected`。
- `onCharacteristicChanged`：区分左右地址；对 `0xF1` 开头且长度为 202 的包走 LC3→PCM（`Cpp.decodeLC3`）；其余通过 `BleChannelHelper.bleReceive` 发往 Dart。

### 5.5 断开

当前 `disconnectFromGlasses` 仅日志 + `result.success`，**未**在片段中展示真正 `disconnect`/`close` GATT 逻辑（若产品化需补全）。

---

## 6. iOS 详细流程（`BluetoothManager.swift` + `AppDelegate.swift`）

### 6.1 通道注册

`AppDelegate` 创建 `FlutterMethodChannel(name: "method.bluetooth", ...)`，将 `BluetoothManager` 与 channel 绑定，并注册 `eventBleReceive` / `eventSpeechRecognize` 的 `FlutterStreamHandler`，把 `eventBleReceive` 的 sink 赋给 `BluetoothManager.blueInfoSink`。

### 6.2 扫描与配对表

`centralManager.scanForPeripherals(withServices: nil)`。`didDiscover` 中按名称里的 `_L_` / `_R_` 填入 `pairedDevices["Pair_\(channelNumber)"]`；左右都非空时 `invokeMethod("foundPairedGlasses", ...)`。

### 6.3 连接

`connectToDevice(deviceName:)`：`stopScan`，从 `pairedDevices[deviceName]` 取左右 `CBPeripheral`，`centralManager.connect` 双耳，并记录 `currentConnectingDeviceName`。

### 6.4 连接完成时机（与 Android 重要差异）

`didConnect` 中：为已连接外设设置 `delegate` 并 `discoverServices([UARTServiceUUID])`；当 `connectedDevices[deviceName]` **左右槽位都已有 peripheral** 时，立即 `invokeMethod("glassesConnected", ...)` 并清空 `currentConnectingDeviceName`。

即 iOS 的 **`glassesConnected` 发生在「中央已连上两颗外设」阶段**，**不等待** Service/Characteristic 发现与订阅完成；Android 则在 **双耳 GATT 服务发现与通知启用完成后** 才上报。集成与联调时需注意该差异。

### 6.5 断线重连

`didDisconnectPeripheral` 中若收到断开，会 **再次 `central.connect(peripheral)`**（自动重连倾向），与 Android 当前空实现的断开行为不同。

### 6.6 数据接收

`didUpdateValueFor` → `getCommandValue`：若为 `BLE_REQ_TRANSFER_MIC_DATA` 则走语音识别 PCM 流；否则组装字典调用 `blueInfoSink` 推给 Dart。

---

## 7. 连接建立后的 Dart 行为摘要

- **心跳**：连接成功后每 8 秒尝试 `Proto.sendHeartBeat()`，失败可短暂重试（见 `BleManager.startSendBeatHeart`）。
- **请求-响应**：`BleManager.request` / `requestRetry` 通过 MethodChannel 发 `send`，并用首字节命令字 + `lr` 拼 key 在 `_handleReceivedData` 里完成 `Completer`。

---

## 8. 已知实现注意点（便于后续维护）

1. **Android / iOS「已连接」判定时机不一致**（见 §6.4），可能导致 Flutter 侧认为已连接时，某一侧尚未完成订阅或写通道就绪。
2. **Android `disconnectFromGlasses`** 未完整释放 GATT。
3. **`BleManager.isBothConnected()`** 在 Dart 中恒为 `true`（TODO），依赖原生真实连接状态时需谨慎。
4. **首包指令**：Android `0xF4 0x01` vs iOS `0x4d 0x01`，若与固件协议强绑定需与硬件文档对齐。

---

## 9. 关键源码索引

| 模块 | 路径 |
|------|------|
| Dart BLE 门面 | `lib/ble_manager.dart` |
| Android BLE 核心 | `android/app/src/main/kotlin/com/example/demo_ai_even/bluetooth/BleManager.kt` |
| Android Channel | `android/app/src/main/kotlin/com/example/demo_ai_even/bluetooth/BleChannelHelper.kt` |
| Android 设备模型 | `android/app/src/main/kotlin/com/example/demo_ai_even/model/BleDevice.kt`, `BlePairDevice.kt` |
| iOS BLE 核心 | `ios/Runner/BluetoothManager.swift` |
| iOS UUID 常量 | `ios/Runner/ServiceIdentifiers.swift` |
| iOS Channel 注册 | `ios/Runner/AppDelegate.swift` |

---

*文档基于 EvenDemoApp 仓库当前源码梳理；若固件或 Channel 协议有更新，请同步修订 §2–§3 与首包字节说明。*
