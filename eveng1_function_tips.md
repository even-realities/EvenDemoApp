
# Even G1 Flutter App 機能解析TIPS

このドキュメントは、Even G1公式デモアプリの主要機能がどのファイルに実装されているかをまとめたものです。

## 1. Bluetooth (BLE) 通信

G1グラスとの通信の根幹を担う機能です。

- **`lib/ble_manager.dart`**
  - **役割**: BLEの接続状態（スキャン、接続、切断）を管理する高レベルなマネージャー。
  - **主要メソッド**: `startScan()`, `stopScan()`, `connectToGlasses()`
  - **ポイント**: `flutter_reactive_ble` パッケージを利用しており、ネイティブコードとの連携は `MethodChannel` を介して行われます。

- **`lib/services/ble.dart`**
  - **役割**: 実際にデータを送信するための低レベルなラッパー。
  - **主要メソッド**: `send(List<int> data)`
  - **ポイント**: `TextService` や `BmpUpdateManager` など、データを送信する他のサービスから利用されるシングルトンです。

- **`ios/Runner/BluetoothManager.swift`**
  - **役割**: iOSネイティブ側のBLEロジックを実装。Dartからの呼び出しを受け、OSのCoreBluetoothフレームワークと連携します。

## 2. テキスト表示機能

入力されたテキストをG1グラスに送信し、表示させる機能です。**手動スクロール化の改造ターゲット**です。

- **`lib/views/features/text_page.dart`**
  - **役割**: テキスト入力用のUI画面。
  - **ポイント**: `TextField` で入力された文字列を `TextService.get.startSendText()` に渡しています。

- **`lib/services/text_service.dart`**
  - **役割**: テキスト送信のコアロジック。
  - **主要メソッド**: `startSendText(String text)`
  - **ポイント**:
    - `EvenAIDataMethod.measureStringList(text)` で、テキストをG1の表示幅に合わせて行分割しています。
    - 分割した行をさらに5行ずつの「ページ」に分割しています。
    - **`Timer.periodic` を使って、ページを一定時間ごと（8秒）に自動で送信しています。** このタイマー処理を無効化し、ボタンタップなどの外部トリガーでページを送信するように変更することで、手動ページ送りが実現できます。

## 3. 画像 (BMP) 表示機能

BMP形式の画像をG1グラスに送信し、表示させる機能です。

- **`lib/controllers/bmp_update_manager.dart`**
  - **役割**: BMP画像のデータを分割し、BLEで送信するロジックを管理。
  - **主要メソッド**: `updateBmp(String lr, Uint8List image)`
  - **ポイント**: 一定のパケットサイズ（194バイト）で画像データを分割し、順次送信しています。テキストと同様にチャンクでのデータ送信を行っています。

## 4. 音声処理 (マイク入力)

マイク（G1グラス）から入力された音声を処理する機能です。

- **`ios/Runner/PcmConverter.m`**
  - **役割**: G1グラスから送られてくるLC3形式の音声データをPCM形式にデコードします。
  - **主要メソッド**: `decode:(NSData *)lc3data`
  - **ポイント**: C言語で実装された `lc3_decode` 関数を呼び出しています。

- **`ios/Runner/SpeechStreamRecognizer.swift`**
  - **役割**: デコードされたPCMデータを受け取り、iOSの `AVFoundation` フレームワークを使って音声認識などの後続処理を行います。
  - **主要メソッド**: `appendPCMData(_ pcmData: Data)`

