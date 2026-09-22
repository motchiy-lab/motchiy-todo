## Googleログインの対応プラットフォーム

Windows版はGoogleのデスクトップOAuth（PKCE）を使って既定のブラウザで認証します。
起動時にGoogle Cloud Consoleで作成したデスクトップアプリのクライアントIDを渡します。

初回だけローカル設定ファイルを作成します。

```powershell
Copy-Item config\google_oauth.json.example config\google_oauth.json
# config\google_oauth.json に実際のクライアントIDとシークレットを入力
```

以後は次のスクリプトを使えば、認証情報を毎回入力する必要はありません。

```powershell
.\tool\run_windows.ps1
.\tool\build_windows.ps1
```

全プラットフォーム向けの成果物（MSIX、APK、LinuxのELF + `data/` を含む
TAR.GZ、WebのZIP）は、リポジトリのルートで次の1コマンドで作成できます。

```powershell
.\tool\build_all.ps1
```

成果物は `dist/` に出力されます。WindowsでLinux版も作成する場合は、WSLに
FlutterとLinuxデスクトップのビルド環境を用意してください。Linux版を省略する
場合は `.\tool\build_all.ps1 -SkipLinux` を使えます。MSIXの作成にはWindows SDK
の `makeappx.exe` が必要です。

バージョンを指定する場合は `-Version` を使います。`1.2.3+4` の形式では、
`1.2.3` がアプリバージョン、`4` がビルド番号になります。省略時は
`pubspec.yaml` の `version` を使用します。

```powershell
.\tool\build_all.ps1 -Version 1.2.3+4
```

Google OAuthのリダイレクトURIは、アプリが起動時に使う
`http://127.0.0.1:<空きポート>` です。デスクトップアプリ用クライアントでは
ループバックリダイレクトを許可してください。クライアントシークレットは
ソースコードやリポジトリへ保存しないでください。`config/google_oauth.json` は
Git管理対象外です。

`--dart-define-from-file` もビルド時に値を埋め込むため、設定を変更した場合は
必ず再ビルドしてください。スクリプトには追加のFlutter引数も渡せます。
