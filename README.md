# motchiy_todo

A new Flutter project.

## Googleログインの対応プラットフォーム

Windows版はGoogleのデスクトップOAuth（PKCE）を使って既定のブラウザで認証します。
起動時にGoogle Cloud Consoleで作成したデスクトップアプリのクライアントIDを渡します。

```powershell
flutter run -d windows `
  --dart-define=GOOGLE_DESKTOP_CLIENT_ID=your-client-id.apps.googleusercontent.com `
  --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=your-client-secret
```

Google OAuthのリダイレクトURIは、アプリが起動時に使う
`http://127.0.0.1:<空きポート>` です。デスクトップアプリ用クライアントでは
ループバックリダイレクトを許可してください。クライアントシークレットは
ソースコードやリポジトリへ保存しないでください。

`--dart-define` はビルド時に埋め込まれるため、引数を追加した後は既存のexeを
起動せず、必ず再ビルドしてください。
