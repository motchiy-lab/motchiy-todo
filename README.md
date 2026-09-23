# Motchiy ToDo

Flutterで作成したタスク管理アプリです。Windows、Android、Linux、Webに対応しています。
タスクと認証にはFirebaseを利用し、WindowsではGoogleのデスクトップOAuth（PKCE）で
ログインします。

## ダウンロードして利用する

リリースページから利用する環境の成果物をダウンロードしてください。

| 環境 | ファイル | 利用方法 |
| --- | --- | --- |
| Windows | `.msix` | MSIXをインストールして起動 |
| Android | `.apk` | APKを端末へ転送してインストール |
| Linux | `.tar.gz` | 展開してELFバイナリを実行 |
| Web | `.zip` | 展開した内容をWebサーバーへ配置 |

### Windows

MSIXはWindows 10/11向けです。`tool\build_all.ps1` は初回ビルド時に開発用の
自己署名証明書を現在のユーザーの証明書ストアへ作成し、MSIXへ署名します。
成果物には公開証明書 `motchiy-todo-publisher.cer` も出力されるため、インストール
する各Windows端末でこのファイルを「現在のユーザー > 信頼されたルート証明機関」に
インポートしてからMSIXをインストールしてください。証明書を更新する場合は、
`-CertificateThumbprint <拇印>` で既存の秘密鍵付き証明書を指定できます。
署名を省略する場合だけ `-SkipMsixSigning` を指定します。

### Android

端末の設定で、利用するファイルマネージャーまたはブラウザに「不明なアプリの
インストール」を許可してからAPKをインストールしてください。Google Play経由の
アプリではないため、端末のセキュリティポリシーによってはインストールできない
場合があります。

### Linux

Linux版は実行ファイルと `data/` を同じディレクトリに置いたまま使用します。

```bash
tar -xzf motchiy-todo-linux-<version>.tar.gz
cd <展開先>
./motchiy_todo
```

実行に必要なGTKなどの共有ライブラリがディストリビューションにない場合は、
ディストリビューションのパッケージマネージャーで追加してください。

### Web

ZIPを展開し、`index.html` を含むファイル一式を静的ファイルとして配信します。
ローカルファイルとして直接開くより、Webサーバー経由で配信することを推奨します。

## 開発環境

以下をインストールしてください。

- Flutter stable（Dartを含む）
- Git
- Windows開発時: Visual Studio with Desktop development with C++
- Android開発時: Android StudioとAndroid SDK
- Linux開発時: clang、CMake、Ninja、GTK 3開発パッケージ
- Web開発時: ChromeまたはChromium

Flutterの対応バージョンは、`pubspec.yaml` のSDK制約を満たすものを使用してください。
環境を確認します。

```bash
flutter doctor -v
flutter config --enable-linux-desktop
```

依存関係を取得します。

```bash
flutter pub get
```

## FirebaseとGoogle OAuthの設定

このリポジトリにはOAuthの実値を保存しません。開発または自分でビルドしたアプリで
Googleログインを使うには、まず設定ファイルを作成します。

```powershell
Copy-Item config\google_oauth.json.example config\google_oauth.json
```

`config/google_oauth.json` にGoogle Cloud Consoleで作成したデスクトップアプリの
クライアントIDを設定してください。このファイルはGit管理対象外です。デスクトップ
アプリは公開クライアントとしてPKCEを使用するため、クライアントシークレットは設定
しません。
Google OAuthのリダイレクトURIには、アプリが使用する次のループバック形式を許可します。

```text
http://127.0.0.1:<空きポート>
```

クライアントIDは `--dart-define-from-file` でビルド成果物へ埋め込まれますが、
クライアントシークレットは成果物へ含めないでください。変更後は必ず再ビルドして
ください。

## 起動と個別ビルド

Windowsで起動する場合:

```powershell
.\tool\run_windows.ps1
```

個別にビルドする場合:

```powershell
.\tool\build_windows.ps1
flutter build apk --release --dart-define-from-file=config/google_oauth.json
flutter build web --release --dart-define-from-file=config/google_oauth.json
```

Linux版はLinux環境で次のようにビルドできます。

```bash
flutter build linux --release \
  --dart-define-from-file=config/google_oauth.json
```

## 全プラットフォーム向けのビルド

WindowsのPowerShellから、次の1コマンドでMSIX、APK、LinuxのELFと `data/` を含む
TAR.GZ、WebのZIPを作成できます。

```powershell
.\tool\build_all.ps1
```

成果物は `dist/` に出力されます。Windows SDKの `makeappx.exe` がMSIX作成に必要です。
Windows上でLinux版も作成する場合は、WSLにLinux用Flutterをインストールし、
`/home/motchiy/development/flutter/bin/flutter` で実行できる状態にしてください。
Linux版を省略する場合は次を使用します。

```powershell
.\tool\build_all.ps1 -SkipLinux
```

バージョンを指定する場合は `-Version` を使います。`1.2.3+4` の形式では、
`1.2.3` がアプリバージョン、`4` がビルド番号です。省略時は `pubspec.yaml` の
`version` を使用します。

```powershell
.\tool\build_all.ps1 -Version 1.2.3+4
```

追加のFlutter引数は、スクリプトの末尾へ渡せます。

```powershell
.\tool\build_all.ps1 -SkipLinux --verbose
```

## テストと静的解析

```bash
flutter analyze
flutter test
```

## ディレクトリ

```text
lib/       アプリ本体
android/   Android固有設定
linux/     Linux固有設定
web/       Web固有設定
windows/   Windows固有設定
tool/      起動・ビルド用PowerShellスクリプト
config/    OAuth設定のサンプル
```

## ライセンス

このプロジェクトは [MIT License](LICENSE) の下で公開しています。

このプロジェクトが使用しているFlutter、Dart、Firebaseなどの依存ライブラリには、
それぞれのライセンスが適用されます。再配布時は各依存ライブラリのライセンスも
確認してください。
