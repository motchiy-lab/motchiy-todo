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

Google OAuthのリダイレクトURIは、アプリが起動時に使う
`http://127.0.0.1:<空きポート>` です。デスクトップアプリ用クライアントでは
ループバックリダイレクトを許可してください。クライアントシークレットは
ソースコードやリポジトリへ保存しないでください。`config/google_oauth.json` は
Git管理対象外です。

`--dart-define-from-file` もビルド時に値を埋め込むため、設定を変更した場合は
必ず再ビルドしてください。スクリプトには追加のFlutter引数も渡せます。
