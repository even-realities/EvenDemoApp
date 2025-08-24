import Foundation
import AVFoundation

#if canImport(FluidAudio)
import FluidAudio
#endif

/// Thin wrapper around FluidAudio's VadManager.
/// - Accepts PCM Int16 (16kHz mono) Data and feeds 512-sample chunks to the VAD.
@available(iOS 13.0, *)
final class FluidVADManagerWrapper {
    static let shared = FluidVADManagerWrapper()
    private init() {}

    // Ring buffer for incoming Int16 samples (16kHz mono)
    private var int16Buffer: [Int16] = []

    #if canImport(FluidAudio)
    @available(iOS 17.0, *)
    private var vad: VadManager?
    #endif

    /// Returns true if FluidAudio is available and OS meets minimum.
    private var isAvailable: Bool {
        #if canImport(FluidAudio)
        if #available(iOS 17.0, *) { return true }
        #endif
        return false
    }

    /// Initialize VAD (downloads model on first run). Safe to call multiple times.
    @discardableResult
    func initializeIfNeeded() async -> Bool {
        guard isAvailable else { return false }
        #if canImport(FluidAudio)
        if #available(iOS 17.0, *) {
            if vad == nil {
                let cfg = VadConfig(
                    threshold: 0.445,
                    chunkSize: 512,
                    sampleRate: 16000,
                    adaptiveThreshold: true,
                    enableSNRFiltering: true,
                    computeUnits: .cpuAndNeuralEngine
                )
                let m = VadManager(config: cfg)
                do {
                    try await m.initialize()
                    self.vad = m
                } catch {
                    print("FluidVAD initialize error: \(error)")
                    return false
                }
            }
            return vad != nil
        }
        #endif
        return false
    }

    /// Feed PCM Int16(16k) samples. Calls back per 512-sample frame with (probability, isVoiceActive).
    func appendPCM(_ data: Data, onResult: @escaping (_ probability: Float, _ active: Bool) -> Void) {
        guard isAvailable else { return }
        // Accumulate Int16 samples
        let count = data.count / MemoryLayout<Int16>.size
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.bindMemory(to: Int16.self).baseAddress {
                int16Buffer.append(contentsOf: UnsafeBufferPointer(start: base, count: count))
            }
        }
        // Drain in 512-sample frames
        while int16Buffer.count >= 512 {
            let frame = Array(int16Buffer.prefix(512))
            int16Buffer.removeFirst(512)
            // Convert to Float32 normalized [-1,1]
            var floats = [Float](repeating: 0, count: 512)
            for i in 0..<512 { floats[i] = Float(frame[i]) / 32768.0 }
            #if canImport(FluidAudio)
            if #available(iOS 17.0, *), let vad {
                Task.detached { [floats] in
                    do {
                        let res = try await vad.processChunk(floats)
                        onResult(res.probability, res.isVoiceActive)
                    } catch {
                        // On error, treat as silence
                        onResult(0.0, false)
                    }
                }
            }
            #endif
        }
    }
}
