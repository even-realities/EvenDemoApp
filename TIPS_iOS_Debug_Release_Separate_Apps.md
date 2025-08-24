# iOS Debug/Release を“別アプリ”として共存させるためのTIPS

目的: 開発用(Dev)と本番用(Prod)を、同じ端末に上書きせず並べてインストールする。アイコン/表示名も切り替える。

---

## 最短サマリ（結論）

- Debug 構成と Release 構成で **Bundle ID** を分ける - Debug: `com.example.demoAiEven.dev` - Release: `com.example.demoAiEven` - 表示名は Info.plist を `$(APP_DISPLAY_NAME)` にし、構成別に値を持たせる - Debug: `Even AI (Dev)` / Release: `Even AI` - アイコンは AppIcon セットを二つ用意し、構成別に切替
  - Debug: `AppIcon-dev` / Release: `AppIcon-prod`
  - `ios/Flutter/Debug.xcconfig` と `Release.xcconfig` で切替できるようにする
- 実行（flavor 不使用）
  - 開発: `flutter run -t lib/main_dev.dart --debug -d <DEVICE_ID>`
  - 本番: `flutter run -t lib/main_prod.dart --release -d <DEVICE_ID>`

---

## 手順詳細

### 1) Bundle ID を構成別に分ける（上書き防止の要）

- Xcode → Targets: `Runner` → Build Settings → Packaging → `Product Bundle Identifier`
  - Debug: `com.example.demoAiEven.dev`
  - Release: `com.example.demoAiEven`
- Signing & Capabilities で Team を選択（Automatically manage signing ON）

### 2) 表示名を構成別に切替（任意）

- `ios/Runner/Info.plist` の `CFBundleDisplayName` を `$(APP_DISPLAY_NAME)` に設定
- Xcode → Targets: `Runner` → Build Settings → User-Defined
  - Debug: `APP_DISPLAY_NAME = Even AI (Dev)`
  - Release: `APP_DISPLAY_NAME = Even AI`

> このリポジトリでは `Info.plist` はすでに `$(APP_DISPLAY_NAME)` を参照するよう編集済みです。

### 3) アイコンを構成別に切替（CLIのみで実現）

1. launcher icons を生成
   - `flutter pub get`
   - まず **開発用画像** で生成 → AppIcon.appiconset を作る
     - `flutter pub run flutter_launcher_icons -f pubspec.yaml`（dev画像を指す設定にして実行）
   - 生成された `ios/Runner/Assets.xcassets/AppIcon.appiconset` を **AppIcon-dev** に複製
     - `cp -R ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon-dev.appiconset`
   - 次に **本番用画像** に切り替えて再生成
     - `flutter pub run flutter_launcher_icons -f pubspec.yaml`
   - 生成された `AppIcon.appiconset` を **AppIcon-prod** に複製
     - `cp -R ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon-prod.appiconset`

2. 構成ごとに使うアイコンセットを指定（xcconfig で切替）
   - `ios/Flutter/Debug.xcconfig` に追記:
     ```
     APP_ICON_SET_NAME=AppIcon-dev
     ```
   - `ios/Flutter/Release.xcconfig` に追記:
     ```
     APP_ICON_SET_NAME=AppIcon-prod
     ```
   - `ios/Runner.xcodeproj/project.pbxproj` は `ASSETCATALOG_COMPILER_APPICON_NAME = "$(APP_ICON_SET_NAME)";` になるよう編集済み（本リポジトリ対応済）

> ポイント: Box の構成毎に `ASSETCATALOG_COMPILER_APPICON_NAME` を分岐させるため、間接変数 `$(APP_ICON_SET_NAME)` を使っています。

### 4) クリーンと再インストール

- 端末から既存のアプリ（dev/prod）を一旦削除（アイコン/表示名のキャッシュ回避）
- `flutter clean`
- 実行
  - 開発: `flutter run -t lib/main_dev.dart --debug -d <DEVICE_ID>`
  - 本番: `flutter run -t lib/main_prod.dart --release -d <DEVICE_ID>`

> これでホーム画面に **2つのアイコン**（Dev/Prod）が並び、上書きされずに共存します。

---

## うまくいかない時のチェックリスト

- [ ] Debug/Release の **Bundle ID** が異なるか（`.dev` が付いているか）
- [ ] `ios/Flutter/Debug.xcconfig` / `Release.xcconfig` に `APP_ICON_SET_NAME=` が入っているか
- [ ] `Runner.xcodeproj` に `ASSETCATALOG_COMPILER_APPICON_NAME = "$(APP_ICON_SET_NAME)";` が反映されているか
- [ ] `Assets.xcassets` に `AppIcon-dev.appiconset` / `AppIcon-prod.appiconset` が存在するか
- [ ] 端末から旧アプリを削除してから再インストールしたか（アイコンキャッシュ）
- [ ] 端末がロックされていないか（起動拒否: FBSOpenApplicationErrorDomain/Locked）

---

## なぜ flavor を使わなかったのか（補足）

- Flutter の `--flavor` は **iOSのScheme** と **Build Configuration** をセットで整える必要があり、
  `Debug-<scheme>`, `Release-<scheme>`, `Profile-<scheme>` を追加しないとビルドでエラーになりがちです。
- 今回は **Debug/Release だけ** を使う運用で十分だったため、flavor を使わず、xcconfig と AppIcon セットの切替で解決しました。

> 将来的に dev/prod の Scheme を導入する場合は、上記の構成複製（`Debug-dev` など）とアイコン名割当を Scheme ベースで行えばOKです。

---

## 参考コマンド（まとめ）

```bash
# アイコン生成（dev → prod の順で複製）
flutter pub get
flutter pub run flutter_launcher_icons -f pubspec.yaml
cp -R ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon-dev.appiconset
# pubspec の image_path を prod に切替後
flutter pub run flutter_launcher_icons -f pubspec.yaml
cp -R ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon-prod.appiconset

# 構成別の割当（xcconfig で切替）
echo 'APP_ICON_SET_NAME=AppIcon-dev' >> ios/Flutter/Debug.xcconfig
echo 'APP_ICON_SET_NAME=AppIcon-prod' >> ios/Flutter/Release.xcconfig

# 実行
flutter run -t lib/main_dev.dart --debug   -d <DEVICE_ID>
flutter run -t lib/main_prod.dart --release -d <DEVICE_ID>
```

---

## メモ（Android）

- Android は `productFlavors { dev { applicationIdSuffix ".dev" } prod { } }` で上書き回避できます。
- アイコンも `flutter_launcher_icons` の flavors で切替可能です。
