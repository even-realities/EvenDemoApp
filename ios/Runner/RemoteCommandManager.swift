import Foundation
import MediaPlayer

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
