import Foundation
import GameController

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
