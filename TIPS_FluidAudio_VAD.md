# FluidAudio で Silero VAD を iOS に組み込む（モデル同梱なし）

## 目的
- SwiftPM の `FluidAudio` を追加し、初回起動時にモデルを自動ダウンロードして Silero VAD を利用する
- 16 kHz / mono / 512 samples(Float32) のチャンクで `VadManager.processChunk` を呼ぶ
- iOS 17+ / async-await 前提

## 変更点（このプロジェクトで行うこと）
- SwiftPM: `https://github.com/FluidInference/FluidAudio.git` （from: 0.3.0）を追加し、`FluidAudio` をリンク
- Info.plist: `NSMicrophoneUsageDescription` を追加（既に追加済みであればOK）
- 既存の PCM フロー（LC3 → PCM Int16）後に、16k/mono/512 に整形して VAD を挿入

## 初期化例（Swift）
```swift
import FluidAudio

let vadManager = VadManager(config: VadConfig(
    threshold: 0.445,
    chunkSize: 512,
    sampleRate: 16000,
    adaptiveThreshold: true,
    enableSNRFiltering: true,
    computeUnits: .cpuAndNeuralEngine
))

try await vadManager.initialize() // 初回のみ自動でCore MLモデルをDL
```

## 推論例（512サンプル毎）
```swift
// pcmFloat32 は長さ512の Float32 配列
let result = try await vadManager.processChunk(pcmFloat32)
print(result.probability, result.isVoiceActive)
```

## 既存パイプラインへの組み込みポイント
- `SpeechStreamRecognizer.appendPCMData(_:)` の LC3 → PCM 変換後に、
  - 16kHz/mono/Int16 → Float32 正規化（/32768）
  - 512サンプルごとに `processChunk` を await で呼ぶ
  - `isVoiceActive` が true の間だけ SFSpeech へ `append` する（無音で止める）

## パラメータの目安
- `threshold`: 0.3–0.6（初期 0.445）
- `chunkSize`: 512（32 ms）
- `sampleRate`: 16000
- `adaptiveThreshold`: true（環境適応）
- `enableSNRFiltering`: true（騒音に強く）

## 注意
- 初回起動時はネットワーク必須（自動DL）。以後はキャッシュから利用
- 厳密なオフライン起動を求める場合は、後で `.mlmodelc` 同梱に切り替え
- 予期せぬブロッキングを避けるため、VAD は専用 `Task` / `DispatchQueue` で処理し、UIは `@MainActor` で更新
