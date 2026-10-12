# Motchiy ToDo

Flutterで作成したタスク管理アプリです。Windows、Android、Linux、Webに対応しています。
認証とデータ同期には設定可能なREST APIを利用します。APIサーバーは利用者が用意し、
Googleログインの検証とユーザーごとのデータ分離を行います。

## ダウンロードして利用する

リリースページから利用する環境の成果物をダウンロードしてください。

| 環境 | ファイル | 利用方法 |
| --- | --- | --- |
| Windows | `.msix` | MSIXをインストールして起動 |
| Android | `.apk` | APKを端末へ転送してインストール |
| Linux | `.tar.gz` | 展開してELFバイナリを実行 |
| Web | `.zip` | 各自でビルド |

Windows/Linux版は、設定の「タスクトレイに格納する」を有効にすると、ウィンドウを
閉じてもアプリを終了せず、システムトレイのメニューから再表示または終了できます。
また、「OSとともに起動する」を有効にすると、サインイン時にアプリを起動できます。

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

## REST APIの設定と契約

APIの接続先は `lib/config/api_config.dart` の `apiBaseUrl` で指定します。
初期値は未設定を示す `https://api.example.com` です。実際のAPIをデプロイしてから、
HTTPSのベースURLに置き換えてアプリをビルドしてください。開発時は `localhost` と
`127.0.0.1` のHTTPも利用できます。同ファイルの `googleOAuthClientId` には公開可能な
Google OAuth WebクライアントIDを設定し、APIサーバー側でもそのIDを許可 audience として
設定してください。このアプリにはクライアントシークレットを含めません。

APIはGoogle IDトークンを検証し、以降のリクエストをAPI発行のBearerトークンで認証します。
デスクトップ版はAPIが開始するブラウザ認証とPKCEを利用し、APIサーバー側にGoogle OAuthの
Webクライアントシークレットを保管してください。Android、iOS、Web版ではGoogle
Sign-Inから取得したIDトークンをAPIへ送ります。APIは署名、発行者、有効期限、および
許可済みのクライアント audience を必ず検証してください。すべてのデータエンドポイントは
BearerトークンのユーザーIDでデータ範囲を決定し、クライアント指定のユーザーIDを信頼して
はいけません。Web版を使う場合、アプリの配信元からのCORS preflightとJSON、
`Authorization` ヘッダーを許可してください。

実装されているAPI契約は次のとおりです。すべてJSONを使用し、エラー応答は
`{ "message": "..." }` とします。

| Method | Path | Request / response |
| --- | --- | --- |
| POST | `/auth/google` | `{ "idToken": "..." }` を受け取り、ログイン応答を返す |
| POST | `/auth/google/desktop/start` | `{ "redirectUri": "http://127.0.0.1:<port>/callback", "state": "...", "codeChallenge": "...", "codeChallengeMethod": "S256", "forceAccountSelection": false }` を受け取り、`{ "authorizationUrl": "https://..." }` を返す |
| POST | `/auth/google/desktop/exchange` | `{ "code": "...", "codeVerifier": "...", "redirectUri": "http://127.0.0.1:<port>/callback" }` を受け取り、ログイン応答を返す |
| POST | `/auth/refresh` | `{ "refreshToken": "..." }` を受け取り、新しいログイン応答を返す |
| POST | `/auth/logout` | 現在のBearerトークンを失効させる |
| GET | `/tasks` | `{ "tasks": [...] }` を返す |
| PUT | `/tasks` | `{ "tasks": [...] }` でログイン中ユーザーの全タスクを置き換える |
| GET | `/settings` | ログイン中ユーザーの設定オブジェクトを返す |
| PATCH | `/settings` | 指定された設定項目を部分更新する |

ログイン、更新APIの成功応答は次の形です。

```json
{
  "accessToken": "API access token",
  "refreshToken": "API refresh token",
  "expiresIn": 900,
  "user": {
    "id": "server-owned user id",
    "email": "user@example.com",
    "displayName": "User",
    "photoUrl": null
  }
}
```

タスクは `id`、`title`、`description`、`isCompleted`、`startDate`、`dueDate`、
`completedAt`、`hasDueDate` を持つオブジェクトです。設定には
`themeColorIndex`、`themeModeIndex`、`enableTabAnimations` を使用します。
端末内のタスクキャッシュはユーザーごとに保存され、未同期の変更は次回の起動または
再読み込み時にAPIへ再送されます。以前の
Firebase/Firestore上のデータは自動移行されないため、必要な場合は別途エクスポートして
API側へ移行してください。

## 起動と個別ビルド

Windowsで起動する場合:

```powershell
.\tool\run_windows.ps1
```

個別にビルドする場合:

```powershell
.\tool\build_windows.ps1
flutter build apk --release
flutter build web --release
```

Linux版はLinux環境で次のようにビルドできます。

```bash
flutter build linux --release
```

## プラットフォームを選択したビルド

ビルドするプラットフォームは `tool/build_platforms.json` で選択できます。
`platforms` 配列に `windows`、`android`、`linux`、`web` のうち必要なものを指定してください。
初期設定では全プラットフォームをビルドします。たとえばWindowsとAndroidだけにする場合:

```json
{
  "platforms": [
    "windows",
    "android"
  ]
}
```

WindowsのPowerShellから、設定されたプラットフォームをまとめてビルドできます。

```powershell
.\tool\build_all.ps1
```

成果物は `dist/` に出力されます。Windows版を選択する場合は、Windows SDKの
`makeappx.exe` がMSIX作成に必要です。Linux版を選択する場合は、Windows上ではWSLに
Linux用Flutterをインストールし、`/home/motchiy/development/flutter/bin/flutter` で
実行できる状態にしてください。`-SkipLinux` を指定すると、設定ファイルでLinuxが
選択されていてもその実行ではLinux版を省略できます。

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
lib/config/ API接続先設定
```

## ライセンス

このプロジェクトは [MIT License](LICENSE) の下で公開しています。

このプロジェクトが使用しているFlutter、Dartなどの依存ライブラリには、
それぞれのライセンスが適用されます。再配布時は各依存ライブラリのライセンスも
確認してください。
