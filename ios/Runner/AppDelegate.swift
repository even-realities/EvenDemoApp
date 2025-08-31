//
//  BluetoothManager.swift
//  Runner
//
//  Created by Hawk on 2024/10/23.
//

import UIKit
import Flutter
import GameController
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var blueInstance = BluetoothManager.shared

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
 
        GeneratedPluginRegistrant.register(with: self)
        let controller = window?.rootViewController as! FlutterViewController
        let messenger : FlutterBinaryMessenger = window?.rootViewController as! FlutterBinaryMessenger
        let channel = FlutterMethodChannel(name: "method.bluetooth", binaryMessenger: controller.binaryMessenger)
        
        blueInstance = BluetoothManager(channel: channel)

        // Set method call handler for Flutter channel
        channel.setMethodCallHandler { [weak self] (call, result) in
            print("AppDelegate----call----\(call)----\(call.method)---------")
            guard let self = self else { return }

            switch call.method {
            case "startScan":
                self.blueInstance.startScan(result: result)
            case "stopScan":
                self.blueInstance.stopScan(result: result)
            case "connectToGlasses":
                if let args = call.arguments as? [String: Any], let deviceName = args["deviceName"] as? String {
                    self.blueInstance.connectToDevice(deviceName: deviceName, result: result)
                } else {
                    result(FlutterError(code: "InvalidArguments", message: "Invalid arguments", details: nil))
                }
            case "disconnectFromGlasses":
                self.blueInstance.disconnectFromGlasses(result: result)
            case "send":
                let params = call.arguments as? [String : Any]
                self.blueInstance.sendData(params: params!)
                result(nil)
            case "startEvenAI":
                // todo dynamic language
                SpeechStreamRecognizer.shared.startRecognition(identifier: "EN")
                result(nil)
            case "stopEvenAI":
                SpeechStreamRecognizer.shared.stopRecognition()
                result(nil)
            case "setVADEnabled":
                if let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool {
                    if #available(iOS 13.0, *) {
                        SpeechStreamRecognizer.isVADEnabled = enabled
                    }
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
     
        let scheduleEvent = FlutterEventChannel(name: "eventBleReceive", binaryMessenger: messenger)
        scheduleEvent.setStreamHandler(self)
        
        let eventSpeechRecognizeEvent = FlutterEventChannel(name: "eventSpeechRecognize", binaryMessenger: messenger)
        eventSpeechRecognizeEvent.setStreamHandler(self)

        // Game Controller event channel
        let controllerEvent = FlutterEventChannel(name: "eventController", binaryMessenger: messenger)
        controllerEvent.setStreamHandler(self)
        ControllerManager.shared.start()

        // Remote Command Center (audio controller) event channel
        let remoteEvent = FlutterEventChannel(name: "eventRemote", binaryMessenger: messenger)
        remoteEvent.setStreamHandler(self)
        RemoteCommandManager.shared.start()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

// MARK: - FlutterStreamHandler
extension AppDelegate : FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    
       if (arguments as? String == "eventBleStatus"){
            //self.blueInstance.blueStatusSink = events
        } else if (arguments as? String == "eventBleReceive") {
            self.blueInstance.blueInfoSink = events
        } else if (arguments as? String == "eventSpeechRecognize") {
            BluetoothManager.shared.blueSpeechSink = events
      } else if (arguments as? String == "eventController") {
          ControllerManager.shared.controllerSink = events
      } else if (arguments as? String == "eventRemote") {
          RemoteCommandManager.shared.remoteSink = events
        } else {
            // TODO
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}


// MARK: - ControllerManager (inlined)
class ControllerManager {
    static let shared = ControllerManager()
    private init() {}

    var controllerSink: FlutterEventSink?

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )

        GCController.startWirelessControllerDiscovery(completionHandler: nil)

        for controller in GCController.controllers() {
            setupHandler(controller: controller)
        }
    }

    @objc private func controllerConnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        setupHandler(controller: controller)
        sendEvent(["type": "controller", "event": "connected", "vendorName": controller.vendorName ?? "unknown"])    
    }

    @objc private func controllerDisconnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        sendEvent(["type": "controller", "event": "disconnected", "vendorName": controller.vendorName ?? "unknown"])    
    }

    private func setupHandler(controller: GCController) {
        controller.controllerPausedHandler = { [weak self] _ in
            self?.sendEvent(["type": "controller", "control": "pauseButton", "pressed": true])
        }

        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, element in
            guard let self = self else { return }
            var control: String?
            var pressed = false

            if let button = element as? GCControllerButtonInput {
                pressed = button.isPressed
                switch button {
                case gamepad.buttonA: control = "buttonA"
                case gamepad.buttonB: control = "buttonB"
                case gamepad.buttonX: control = "buttonX"
                case gamepad.buttonY: control = "buttonY"
                case gamepad.leftShoulder: control = "leftShoulder"
                case gamepad.rightShoulder: control = "rightShoulder"
                case gamepad.leftTrigger: control = "leftTrigger"
                case gamepad.rightTrigger: control = "rightTrigger"
                default: break
                }
            } else if let dpad = element as? GCControllerDirectionPad {
                let threshold: Float = 0.5
                if abs(dpad.xAxis.value) > abs(dpad.yAxis.value) {
                    if dpad.xAxis.value > threshold { control = "dpadRight"; pressed = true }
                    else if dpad.xAxis.value < -threshold { control = "dpadLeft"; pressed = true }
                } else {
                    if dpad.yAxis.value > threshold { control = "dpadUp"; pressed = true }
                    else if dpad.yAxis.value < -threshold { control = "dpadDown"; pressed = true }
                }
            }

            if let control = control, pressed {
                self.sendEvent(["type": "controller", "control": control, "pressed": pressed])
            }
        }
    }

    private func sendEvent(_ dict: [String: Any]) {
        controllerSink?(dict)
    }
}

// MARK: - RemoteCommandManager (inlined)
class RemoteCommandManager {
    static let shared = RemoteCommandManager()
    private init() {}
    
    var remoteSink: FlutterEventSink?

    func start() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.sendEvent(["type": "remote", "control": "play"]) ; return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.sendEvent(["type": "remote", "control": "pause"]) ; return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.sendEvent(["type": "remote", "control": "togglePlayPause"]) ; return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.sendEvent(["type": "remote", "control": "nextTrack"]) ; return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.sendEvent(["type": "remote", "control": "previousTrack"]) ; return .success
        }
    }

    private func sendEvent(_ dict: [String: Any]) {
        remoteSink?(dict)
    }
}
