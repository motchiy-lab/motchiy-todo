# Motchiy ToDo

Flutterで作成したタスク管理アプリです。Windows、Android、Linux、Webに対応しています。
メールアドレスとパスワードによる認証、およびタスク・設定の同期にはMongoDBを使うREST
APIを利用します。REST APIサーバーはこのリポジトリには含まれていないため、別途作成・
デプロイしてください。APIの仕様はOpenAPIファイルと以下の説明を参照してください。
FirebaseとGoogleログインは使用しません。

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

Linux版は実行ファイル、`data/`、`lib/` を同じディレクトリ構成に置いたまま使用します。

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
- Linux開発時: clang、CMake、Ninja、GTK 3、`libsecret-1-dev` の開発パッケージ
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

## REST APIサーバー

`server/` にGinとMongoDBを使ったAPIサーバーがあります。MongoDBへ接続し、認証、
タスク・設定のユーザー別保存を行います。メールアドレスの所有確認は行いません。
サーバーは `127.0.0.1:3000` のみにバインドし、
Cloudflare Tunnelからローカルへ転送する構成です。

Go 1.23以降とMongoDBを用意してから、`.env.example` を `.env` にコピーし、接続文字列、
32バイト以上のランダムなJWT秘密鍵を設定してください。

```powershell
Copy-Item .env.example .env
# .env に実際のMongoDB/JWT設定を書き込む
[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
Push-Location server
go mod tidy
go run .
```

APIは `http://127.0.0.1:3000/health` でヘルスチェックできます。
公開API URLを `https://api.motchiy.com` とする場合は、Cloudflare Tunnelのホスト名を
ローカルの `http://127.0.0.1:3000` に接続してください。APIはドメイン直下のパスで動作します。

ローカルサーバーへFlutterアプリから接続して試す場合:

```powershell
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

Quick Tunnelで一時的に試す場合:

```powershell
cloudflared tunnel --url http://127.0.0.1:3000
```

本番利用ではQuick Tunnelではなく、Cloudflare Zero Trustで名前付きTunnelを作成し、DNS名を
割り当てます。Tunnel設定ファイル（通常は `%USERPROFILE%\.cloudflared\config.yml`）には、
TunnelのIDとCloudflareが作成した資格情報ファイルを指定し、次のingressを設定してください。
初回セットアップでは次のコマンドを実行します。`api.motchiy.com` がCloudflare管理下に
ない場合は、ご自身のCloudflare管理下のホスト名に置き換えてください。

```powershell
cloudflared tunnel login
cloudflared tunnel create motchiy-todo
cloudflared tunnel route dns motchiy-todo api.motchiy.com
```

```yaml
tunnel: <TUNNEL-ID>
credentials-file: C:\Users\<ユーザー名>\.cloudflared\<TUNNEL-ID>.json
ingress:
  - hostname: api.motchiy.com
    service: http://127.0.0.1:3000
  - service: http_status:404
```

名前付きTunnelの作成後は、次のコマンドで起動します。

```powershell
cloudflared tunnel run <TUNNEL名>
```

Tunnel資格情報ファイルと `.env` は公開・共有せず、リポジトリにも追加しないでください。
Cloudflare側でもレート制限やWAFを設定し、MongoDBをインターネットへ直接公開しないでください。
認証APIの上にCloudflare Accessのブラウザー対話ログインを要求するとアプリからのAPI通信が
遮断されるため、通常はアプリ内のメールアドレス・パスワード認証とCloudflare WAFを使って保護してください。

公開環境ではAPIをHTTPSで公開し、MongoDBへのアクセスをAPIサーバーからのみに制限してください。
接続文字列と秘密鍵をソース管理・アプリ・配布アーカイブに含めず、ホスティング環境の
シークレット管理機能に保管します。DBは専用の最小権限アカウントを使い、バックアップと
復旧手順も用意します。ログイン・登録にはIPおよびアカウント単位のレート制限を
設け、Web版を配信する場合は実際の配信元だけを許可するCORSを設定してください。

### REST APIの契約

OpenAPI 3.1形式の仕様は [`openapi.yaml`](openapi.yaml) にあります。
サーバー実装やクライアント生成、API契約の確認に利用できます。

アプリに設定するベースURL配下に、次のJSON APIを実装します。認証以外のデータAPIには
すべて `Authorization: Bearer <accessToken>` を要求します。成功時のログイン応答は
`accessToken`（15分の有効期限）、`refreshToken`、`expiresIn`（秒）、`user`（`id`、
`email`、`displayName`、`photoUrl`）を含むJSONです。エラーは
`{ "message": "..." }` 形式にします。空の成功応答はHTTP 204を返します。

| Method / path | 要件 |
| --- | --- |
| `POST /auth/register` | `{ "email", "password", "displayName" }` を受け取り、メールアドレスを正規化して一意性を検証する。パスワードは12文字以上128バイト以下。ソルト付きscrypt等の適切なパスワードハッシュで保存し、登録直後にログイン応答を返す。メールアドレスの所有確認は行わない。 |
| `POST /auth/login` | `{ "email", "password" }` を検証する。資格情報不一致では認証せず、短時間の試行回数制限を適用する。 |
| `POST /auth/refresh` | `{ "refreshToken" }` を検証し、古いトークンを一度だけ使えるよう失効・ローテーションして新しいログイン応答を返す。DBにはトークンそのものではなくハッシュを保存する。 |
| `POST /auth/logout` | 認証中セッションだけを失効させる。 |
| `GET /tasks` | 認証中ユーザーの `{ "tasks": [...] }` を返す。 |
| `PUT /tasks` | `{ "tasks": [...] }` で認証中ユーザーのタスク一覧だけを置き換える。 |
| `GET /settings` | 認証中ユーザーの設定を返す。未保存時は `themeColorIndex: 0`、`themeModeIndex: 0`、`enableTabAnimations: true` を返す。 |
| `PATCH /settings` | 許可された設定項目だけを認証中ユーザーの設定へ部分更新する。 |
| `GET /health` | APIの稼働状況を返す。監視にDB接続確認が必要な場合はReadiness用の確認も実装する。 |

アクセストークンは署名・有効期限・issuer・audienceを検証し、その `sub` と有効なサーバー側
セッションからユーザーを特定します。セッション失効もデータAPIごとに反映してください。
クライアントから送られた `userId`、メールアドレス、表示名をデータ所有者の決定に使っては
いけません。タスクと設定のすべての読み書きは、認証済みユーザーIDをMongoDBクエリに含めて
実行します。ユーザーIDをリクエスト本文から選択できる設計や、全件取得後にアプリ側で
フィルターする設計は禁止です。

MongoDBにはユーザー（メールアドレス一意、パスワードハッシュ）、認証セッション
（ユーザーID、リフレッシュトークンハッシュ、有効期限、失効日時）、ユーザーごとのタスク
一覧、ユーザーごとの設定を保存します。ユーザーごとに一意なデータ所有キーを設けます。
タスクは `id`、`title`、`description`、`isCompleted`、`startDate`、`dueDate`、
`completedAt`、`hasDueDate` の項目のみを受け付け、ユーザーIDなどの余分な項目は拒否します。
設定は `themeColorIndex`（0〜5）、`themeModeIndex`（0〜2）、
`enableTabAnimations`（boolean）のみを受け付けます。

Webアプリを配信する場合、CORSでは実際の配信オリジンだけを許可し、JSONと
`Authorization` ヘッダーのpreflightを処理します。認証情報やMongoDB接続文字列を
Flutterアプリへ埋め込んではいけません。アプリに埋め込むのは公開API URLだけです。

### 認証とデータ分離

アカウント作成には表示名、メールアドレス、12文字以上のパスワードが必要です。
メールアドレスの所有確認は行わず、登録が成功するとそのままログインします。
そのため、入力したメールアドレスが本人のものかは確認されません。
パスワードはサーバーでscryptを使ってソルト付きハッシュとして保存し、ログイン時に短命な
署名付きアクセストークンと、ハッシュだけをDBへ保存するローテーション式リフレッシュ
トークンを発行します。ログアウトすると該当セッションが失効します。

各リクエストの利用者IDは検証済みアクセストークンの `sub` とサーバー上の有効な
セッションからのみ取得します。タスクや設定のAPIは、リクエスト本文にユーザーIDがあっても
受け付けず、DB検索・更新は認証済みユーザーIDに限定します。アカウント間のアクセス制御を
クライアント側の値やメールアドレスに依存させません。

登録・ログインAPIの成功応答は次の形です。

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
再読み込み時にAPIへ再送されます。以前に別の保存先を使っていた場合、そのデータは自動
移行されません。

## 配布用ビルド

リリースビルドにはデプロイ済みHTTPS APIのベースURL（例: `https://todo-api.example.com`）が必須です。
APIはドメイン直下のパスで公開します。プレースホルダーURLのままでは
ビルドできないようにしてあり、API URLはコンパイル時にアプリへ埋め込まれます。Windowsで
選択中のWindows、Android、Linux向け成果物を作る例:

```powershell
.\tool\build.ps1 -ApiBaseUrl https://todo-api.example.com
```

既定ではMSIX、APK、Linux tar.gzを `dist/` に作成します。`tool/build_platforms.json` の
`platforms` 配列で対象を選びます。Windows MSIXは開発用自己署名証明書で署名され、
`motchiy-todo-publisher.cer` が出力されます。受け取る側はインストール前に発行者証明書を
信頼する必要があります。広く配布する場合は、Windows署名証明書を用意してください。
Android APKは現在のGradle設定により開発用署名で作成されます。直接配布・試用はできますが、
Google Playや継続的な本番アップデートには専用のリリース署名鍵と本番用アプリIDを設定して
ください。署名鍵は安全にバックアップし、リポジトリや配布物に含めないでください。

Windows用Flutterバンドルだけを作る場合:

```powershell
.\tool\build.ps1 -ApiBaseUrl https://todo-api.example.com
```

APKまたはWeb版をFlutterから個別にビルドする場合は、同じAPI URLを渡してください。

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://todo-api.example.com
flutter build web --release --dart-define=API_BASE_URL=https://todo-api.example.com
```

たとえばベースURLが `https://todo-api.example.com` の場合、アプリは
`https://todo-api.example.com/auth/login` や
`https://todo-api.example.com/tasks` に接続します。サーバー側またはリバース
プロキシ側でも、これらのパスでAPIを受け付けるようにしてください。Linux版もLinux/WSLに
Flutter環境を用意してAPI URL付きでビルドできます。各配布物の接続先を変えるには、API URLを
指定し直して再ビルドが必要です。

## プラットフォームを選択したビルド

ビルドするプラットフォームは `tool/build_platforms.json` で選択できます。
`platforms` 配列に `windows`、`android`、`linux`、`web` のうち必要なものを指定してください。
初期設定ではWindows、Android、Linuxをビルドします。たとえばWindowsとAndroidだけに
する場合は次のように設定します。一時的にコマンドラインで対象を上書きする場合は
`-Platforms windows,android` のようにも指定できます。

```json
{
  "platforms": [
    "windows",
    "android"
  ]
}
```

WindowsのPowerShellから、設定されたプラットフォームをまとめてビルドできます。出力先は
既定で `dist/` です。スクリプトは既存成果物を削除しないため、空の出力先を指定するか、
内容を確認したうえで `-CleanOutputDirectory` を明示してください。

```powershell
.\tool\build_all.ps1 `
  -ApiBaseUrl https://todo-api.example.com `
  -OutputDirectory dist\release-2.0.0
```

成果物は `dist/` に出力されます。Windows版を選択する場合は、Windows SDKの
`makeappx.exe` がMSIX作成に必要です。Linux版を選択する場合は、Windows上ではWSLに
Linux用Flutterをインストールし、`/home/motchiy/development/flutter/bin/flutter` で
実行できる状態にしてください。`-SkipLinux` を指定すると、設定ファイルでLinuxが
選択されていてもその実行ではLinux版を省略できます。

```powershell
.\tool\build_all.ps1 `
  -ApiBaseUrl https://todo-api.example.com `
  -OutputDirectory dist\release-2.0.0 `
  -SkipLinux
```

バージョンを指定する場合は `-Version` を使います。`1.2.3+4` の形式では、
`1.2.3` がアプリバージョン、`4` がビルド番号です。省略時は `pubspec.yaml` の
`version` を使用します。

```powershell
.\tool\build_all.ps1 `
  -ApiBaseUrl https://todo-api.example.com `
  -OutputDirectory dist\release-1.2.3 `
  -Version 1.2.3+4
```

追加のFlutter引数は、スクリプトの末尾へ渡せます。

```powershell
.\tool\build_all.ps1 `
  -ApiBaseUrl https://todo-api.example.com `
  -OutputDirectory dist\release-2.0.0 `
  -SkipLinux --verbose
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
