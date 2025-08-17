import CoreBluetooth
import Flutter

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BluetoothManager(channel: FlutterMethodChannel())
    
    var centralManager: CBCentralManager!
    var pairedDevices: [String: (CBPeripheral?, CBPeripheral?)] = [:]
    var connectedDevices: [String: (CBPeripheral?, CBPeripheral?)] = [:]
    var currentConnectingDeviceName: String? // Save the name of the currently connecting device
    
    var channel: FlutterMethodChannel!
    
    var blueInfoSink:FlutterEventSink!
    var blueSpeechSink:FlutterEventSink!
    
    var leftPeripheral:CBPeripheral?
    var leftUUIDStr:String?
    var rightPeripheral:CBPeripheral?
    var rightUUIDStr:String?
    
    var UARTServiceUUID:CBUUID
    var UARTRXCharacteristicUUID:CBUUID
    var UARTTXCharacteristicUUID:CBUUID
    
    var leftWChar:CBCharacteristic?
    var rightWChar:CBCharacteristic?
    var leftRChar:CBCharacteristic?
    var rightRChar:CBCharacteristic?
    
    var hasStartedSpeech = false

    init(channel: FlutterMethodChannel) {
        UARTServiceUUID          = CBUUID(string: ServiceIdentifiers.uartServiceUUIDString)
        UARTTXCharacteristicUUID = CBUUID(string: ServiceIdentifiers.uartTXCharacteristicUUIDString)
        UARTRXCharacteristicUUID = CBUUID(string: ServiceIdentifiers.uartRXCharacteristicUUIDString)
        
        super.init()
        self.channel = channel
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan(result: @escaping FlutterResult) {
        guard centralManager.state == .poweredOn else {
            result(FlutterError(code: "BluetoothOff", message: "Bluetooth is not powered on.", details: nil))
            return
        }

        centralManager.scanForPeripherals(withServices: nil, options: nil)
        result("Scanning for devices...")
    }

    func stopScan(result: @escaping FlutterResult) {
        centralManager.stopScan()
        result("Scan stopped")
    }

    func connectToDevice(deviceName: String, result: @escaping FlutterResult) {
        centralManager.stopScan()

        guard let peripheralPair = pairedDevices[deviceName] else {
            result(FlutterError(code: "DeviceNotFound", message: "Device not found", details: nil))
            return
        }

        currentConnectingDeviceName = deviceName // Save the current device being connected

        var didAttempt = false

        if let leftPeripheral = peripheralPair.0 {
            // Connect left if not already connected
            if connectedDevices[deviceName]?.0 == nil {
                centralManager.connect(leftPeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                didAttempt = true
            }
        }

        if let rightPeripheral = peripheralPair.1 {
            // Connect right if not already connected
            if connectedDevices[deviceName]?.1 == nil {
                centralManager.connect(rightPeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                didAttempt = true
            }
        }

        if didAttempt {
            result("Connecting to \(deviceName)...")
        } else {
            result(FlutterError(code: "PeripheralNotFound", message: "No peripherals available to connect", details: nil))
        }
    }

    func disconnectFromGlasses(result: @escaping FlutterResult) {
        for (_, devices) in connectedDevices {
            if let leftPeripheral = devices.0 {
                centralManager.cancelPeripheralConnection(leftPeripheral)
            }
            if let rightPeripheral = devices.1 {
                centralManager.cancelPeripheralConnection(rightPeripheral)
            }
        }
        connectedDevices.removeAll()
        result("Disconnected all devices.")
    }

    // MARK: - CBCentralManagerDelegate Methods
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name else { return }
        let components = name.components(separatedBy: "_")
        guard components.count > 1, let channelNumber = components[safe: 1] else { return }

        if name.contains("_L_") {
            pairedDevices["Pair_\(channelNumber)", default: (nil, nil)].0 = peripheral // Left device
        } else if name.contains("_R_") {
            pairedDevices["Pair_\(channelNumber)", default: (nil, nil)].1 = peripheral // Right device
        }

        if let leftPeripheral = pairedDevices["Pair_\(channelNumber)"]?.0, let rightPeripheral = pairedDevices["Pair_\(channelNumber)"]?.1 {
            let deviceInfo: [String: String] = [
                "leftDeviceName": leftPeripheral.name ?? "",
                "rightDeviceName": rightPeripheral.name ?? "",
                "channelNumber": channelNumber
            ]
            channel.invokeMethod("foundPairedGlasses", arguments: deviceInfo)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let deviceName = currentConnectingDeviceName else { return }
        guard let peripheralPair = pairedDevices[deviceName] else { return }

        if connectedDevices[deviceName] == nil {
            connectedDevices[deviceName] = (nil, nil)
        }

        if peripheralPair.0 === peripheral {
            connectedDevices[deviceName]?.0 = peripheral // Left device connected
            
            self.leftPeripheral = peripheral
            self.leftPeripheral?.delegate = self
            self.leftPeripheral?.discoverServices([UARTServiceUUID])
            
            self.leftUUIDStr = peripheral.identifier.uuidString;
            
            print("didConnect----self.leftPeripheral---------\(self.leftPeripheral)--self.leftUUIDStr----\(self.leftUUIDStr)----")
        } else if peripheralPair.1 === peripheral {
            connectedDevices[deviceName]?.1 = peripheral // Right device connected
            
            self.rightPeripheral = peripheral
            self.rightPeripheral?.delegate = self
            self.rightPeripheral?.discoverServices([UARTServiceUUID])
            
            self.rightUUIDStr = peripheral.identifier.uuidString
            
            print("didConnect----self.rightPeripheral---------\(self.rightPeripheral)---self.rightUUIDStr----\(self.rightUUIDStr)-----")
        }

        if let leftPeripheral = connectedDevices[deviceName]?.0, let rightPeripheral = connectedDevices[deviceName]?.1 {
            let connectedInfo: [String: String] = [
                "leftDeviceName": leftPeripheral.name ?? "",
                "rightDeviceName": rightPeripheral.name ?? "",
                "status": "connected"
            ]
            channel.invokeMethod("glassesConnected", arguments: connectedInfo)

            currentConnectingDeviceName = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?){
        print("\(Date()) didDisconnectPeripheral-----peripheral-----\(peripheral)--")
        
        if let error = error {
            print("Disconnect error: \(error.localizedDescription)")
        } else {
            print("Disconnected without error.")
        }
        
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("didFailToConnect peripheral: \(String(describing: peripheral.name)) error: \(String(describing: error?.localizedDescription))")
        // Optionally notify Flutter side to refresh UI/state
        channel.invokeMethod("glassesDisconnected", arguments: nil)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("peripheral------\(peripheral)-----didDiscoverServices--------")
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid .isEqual(UARTServiceUUID){
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("peripheral------\(peripheral)-----didDiscoverCharacteristicsFor----service----\(service)----")
        guard let characteristics = service.characteristics else { return }

        if service.uuid.isEqual(UARTServiceUUID){
            for characteristic in characteristics {
                if characteristic.uuid.isEqual(UARTRXCharacteristicUUID){
                    if(peripheral.identifier.uuidString == self.leftUUIDStr){
                        self.leftRChar = characteristic
                    }else if(peripheral.identifier.uuidString == self.rightUUIDStr){
                        self.rightRChar = characteristic
                    }
                } else if characteristic.uuid.isEqual(UARTTXCharacteristicUUID){
                    if(peripheral.identifier.uuidString == self.leftUUIDStr){
                        self.leftWChar = characteristic
                    }else if(peripheral.identifier.uuidString == self.rightUUIDStr){
                        self.rightWChar = characteristic
                    }
                }
            }
            
            if(peripheral.identifier.uuidString == self.leftUUIDStr){
                if(self.leftRChar != nil && self.leftWChar != nil){
                    self.leftPeripheral?.setNotifyValue(true, for: self.leftRChar!)
                  
                    self.writeData(writeData: Data([0x4d, 0x01]), lr: "L")
                }
            }else if(peripheral.identifier.uuidString == self.rightUUIDStr){
                if(self.rightRChar != nil && self.rightWChar != nil){
                    self.rightPeripheral?.setNotifyValue(true, for: self.rightRChar!)
                    self.writeData(writeData: Data([0x4d, 0x01]), lr: "R")
                }
            }
        }
    }
        
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("subscribe fail: \(error)")
            return
        }
        if characteristic.isNotifying {
            print("subscribe success")
        } else {
            print("subscribe cancel")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on.")
        case .poweredOff:
            print("Bluetooth is powered off.")
        default:
            print("Bluetooth state is unknown or unsupported.")
        }
    }
    
    
    func sendData(params:[String:Any]) {
        let flutterData = params["data"] as! FlutterStandardTypedData
        writeData(writeData: flutterData.data, lr: params["lr"] as? String)
    }
    
    func writeData(writeData: Data, cbPeripheral: CBPeripheral? = nil, lr: String? = nil) {
        if lr == "L" {
            if self.leftWChar != nil {
                self.leftPeripheral?.writeValue(writeData, for: self.leftWChar!, type: .withoutResponse)
            }
            return
        }
        if lr == "R" {
            if self.rightWChar != nil {
                self.rightPeripheral?.writeValue(writeData, for: self.rightWChar!, type: .withoutResponse)
            }
            return
        }
        
        if let leftWChar = self.leftWChar {
            self.leftPeripheral?.writeValue(writeData, for: leftWChar, type: .withoutResponse)
        } else {
            print("writeData leftWChar is nil, cannot write data to right peripheral.")
        }

        if let rightWChar = self.rightWChar {
            self.rightPeripheral?.writeValue(writeData, for: rightWChar, type: .withoutResponse)
        } else {
            print("writeData rightWChar is nil, cannot write data to right peripheral.")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("\(Date()) didWriteValueFor----characteristic---\(characteristic)---- \(error!)")
            return
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        guard error == nil else {
            print("\(Date()) didWriteValueFor----------- \(error!)")
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        //print("\(Date()) didUpdateValueFor------\(peripheral.identifier.uuidString)----\(peripheral.name)-----\(characteristic.value)--")
        let data = characteristic.value
        self.getCommandValue(data: data!,cbPeripheral: peripheral)
    }
    
    func getCommandValue(data:Data,cbPeripheral:CBPeripheral? = nil){
        let rspCommand = AG_BLE_REQ(rawValue: (data[0]))
        switch rspCommand{
            case .BLE_REQ_TRANSFER_MIC_DATA:
                 let hexString = data.map { String(format: "%02hhx", $0) }.joined()
                 let effectiveData = data.subdata(in: 2..<data.count)
                 let pcmConverter = PcmConverter()
                 var pcmData = pcmConverter.decode(effectiveData)
               
                 let inputData = pcmData as Data
                 SpeechStreamRecognizer.shared.appendPCMData(inputData)
            
                 break
            default:
                let isLeft = cbPeripheral?.identifier.uuidString == self.leftUUIDStr
                let legStr = isLeft ? "L" : "R"
                var dictionary = [String: Any]()
                dictionary["type"] = "type" // todo
                dictionary["lr"] = legStr
                dictionary["data"] = data

                self.blueInfoSink(dictionary)
                break
        }
    }
}

// Extension for safe array indexing
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
