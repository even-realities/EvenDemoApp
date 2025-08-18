//
//  BluetoothManager.swift
//  Runner
//
//  Created by Hawk on 2024/10/23.
//

import UIKit
import Flutter

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

