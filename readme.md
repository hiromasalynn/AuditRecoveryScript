# Readme

## 概要
このスクリプトは Microsoft Graph API を使用して、特定の相関 ID に関連する監査ログを取得し、変更前後の値を抽出してファイルに保存します。  

## 前提条件
- PowerShell 7.0 以上
- Microsoft Graph PowerShell SDK がインストール済み（スクリプト実行時に自動チェック）
  ```powershell
  Install-Module Microsoft.Graph
  ```
- Entra ID の適切な権限を持つアカウント（AuditLog.Read.All, Directory.Read.All）

## セットアップ

### 1. 相関 ID の設定
スクリプトの `$correlationId` を復元したい監査ログの相関 ID に変更してください：

```powershell
$correlationId = "3f7a3936-4fdc-49eb-bfd8-f249b03e3428"  # ← ここを実際の ID に更新
```

### 2. 出力ディレクトリの確認
必要に応じて `$baseDir` を変更してください：

```powershell
$baseDir = "C:\Users\baseDir\AuditRecoveryScript\Output"
```

## 実行方法

### PowerShell で実行
```powershell
cd "C:\Users\hongchanglin\OneDrive - Microsoft\デスクトップ\VSCode\AuditRecoveryScript"
.\RestoreAuditLog.ps1
```

### 初回実行時
- ブラウザが開き、Entra ID でのログインを求められます
- 認証後、スクリプトが自動で実行されます
- モジュール未インストール時はエラーメッセージが表示されます

## 出力ファイル

スクリプト実行後、以下のファイルが生成されます（タイムスタンプ付きで上書き防止）：

| ファイル名 | 内容 |
|-----------|------|
| `_01_OldValue_Before_YYYYMMDD_HHMMSS.txt` | 変更前の値 |
| `_02_NewValue_After_YYYYMMDD_HHMMSS.txt` | 変更後の値 |

## 注意事項
- 監査ログが見つからない場合、「監査ログを取得できませんでした」と表示され終了します
- エラーが発生した場合は詳細メッセージとスタックトレースが表示されます
- 出力ディレクトリが存在しない場合は自動作成されます
- ログの結合データはコンソールで一部表示されます（長大な場合は先頭/末尾のみ）

## トラブルシューティング

| 問題 | 解決方法 |
|------|---------|
| 認証エラーが発生 | Entra ID アカウントの権限を確認してください |
| ログが見つからない | 相関 ID が正しいか確認してください |
| ファイル保存エラー | 出力ディレクトリの書き込み権限を確認してください |