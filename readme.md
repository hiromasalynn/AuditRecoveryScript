# Recover split audit logs for Conditional Access policy changes

Shows how to recover and compare split audit log entries for Conditional Access policy changes using PowerShell and Microsoft Graph API

PowerShell スクリプトにて、条件付きアクセス ポリシーの変更に伴い分割記録された監査ログを結合・復元し、変更前後の差分を確認する方法を紹介します。

> こちらで紹介するサンプル スクリプトについては、あくまでもサンプルの情報となります。
> 運用環境でそのまま利用されることは想定しておらず、ご利用の際には、十分な検証作業を実施をお願いします。
> 執筆時点以降のクラウド サービスの動作変更に伴い、大幅な改変が必要となることがあります。
> (本情報の執筆時点でテスト環境における検証作業は実施していますが、動作を保証するものではありません)

> また、サンプルについてのサポート サービスの提供はしておりません。
> 恐れ入りますが、スクリプトを利用したことで生じる影響、スクリプトの改変や、スクリプトの動作に関するご質問については、 Azure 技術サポートにて受け付けることができない場合があります。
> サンプル スクリプトが動作しない場合などは、 Github Issue やプル リクエストでのレポートをお願いいたします。

## 監査ログの分割について

条件付きアクセス ポリシーを変更すると、Microsoft Entra ID の監査ログに変更内容が記録されます。しかし、変更内容のデータ量が大きい場合、1 件の監査ログ エントリに収まらず、`AdditionalDetails` フィールド内の `seq` (シーケンス番号) と `b` (データ本体) に分割して記録される場合があります。

本スクリプトでは、分割された監査ログを相関 ID (Correlation ID) をキーとして Microsoft Graph API で取得し、シーケンス番号順に結合・復元します。さらに、復元したデータから条件付きアクセス ポリシーの変更前 (OldValue) と変更後 (NewValue) を抽出し、対象アプリケーションの追加・削除の差分を表示します。

## 1. 事前準備

### Microsoft Graph PowerShell SDK のインストール

Microsoft Graph PowerShell SDK をインストールします。ローカル管理者権限で PowerShell を起動し、以下のコマンドを実行します。

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

既にインストール済みの場合は、以下のコマンドでバージョンを確認できます。

```powershell
Get-InstalledModule -Name Microsoft.Graph | Select-Object Name, Version
```

古いバージョンを利用している場合には、Update-Module コマンドで最新版に更新ください。

```powershell
Update-Module -Name Microsoft.Graph
```

### 必要なアクセス許可

スクリプト実行時にブラウザーが起動し、インタラクティブ認証が開始されます。サインインするアカウントには、監査ログの読み取り権限を持つロール (グローバル閲覧者、セキュリティ閲覧者、レポート閲覧者など) が必要です。

スクリプトは以下のスコープを要求します。

- `AuditLog.Read.All`
- `Directory.Read.All`

> サインインするアカウントは対象テナントの**メンバー ユーザー**をご利用ください。ゲスト ユーザーで実行する場合は、`-TenantId` パラメーターで対象テナントを明示的に指定する必要があります。

### 相関 ID の確認

復元したい監査ログの相関 ID を事前に確認しておきます。Microsoft Entra 管理センター > [監視と正常性] > [監査ログ] から該当のログ エントリを開き、[相関 ID] フィールドの値を控えておきます。

## 2. スクリプトの実行

[スクリプト一式](https://github.com/jpazureid/audit-log-recovery/archive/refs/heads/main.zip) をダウンロードし、任意の場所 (以下では C:\AuditLogRecovery) に展開します。

PowerShell を起動し、相関 ID を引数に指定してスクリプトを実行します。

```powershell
.\AuditLogRecovery.ps1 -CorrelationId "3f7a3936-4fdc-49eb-bfd8-f249b03e3428"
```

実行するとブラウザーが起動し、Microsoft Entra ID への認証が開始されます。監査ログの読み取り権限を持つアカウントでサインインしてください。初回実行時には `AuditLog.Read.All` および `Directory.Read.All` のアクセス許可への同意が求められますので、[承諾] をクリックします。

### パラメーター

| パラメーター | 必須 | 既定値 | 説明 |
|-------------|------|--------|------|
| `-CorrelationId` | はい | — | 復元したい監査ログの相関 ID |
| `-TenantId` | いいえ | — | 接続先のテナント ID。ゲスト ユーザーで実行する場合に指定 |
| `-BaseDir` | いいえ | スクリプトと同階層の `Output` フォルダー | 結果ファイルの出力先フォルダーのパス |
| `-Depth` | いいえ | `10` | ConvertTo-Json の深さ。データ構造が深い場合はより大きな値を指定 |

ゲスト ユーザーで実行する場合や、出力先・JSON の深さを変更する場合は以下のように指定します。

```powershell
.\AuditLogRecovery.ps1 -CorrelationId "3f7a3936-4fdc-49eb-bfd8-f249b03e3428" -TenantId "contoso.onmicrosoft.com"
```

```powershell
.\AuditLogRecovery.ps1 -CorrelationId "3f7a3936-4fdc-49eb-bfd8-f249b03e3428" -TenantId "contoso.onmicrosoft.com" -BaseDir "C:\Temp\Output" -Depth 10
```

### 実行結果

スクリプトを実行すると、以下のような出力が表示されます。

```text
--- Microsoft Graph からデータ取得完了 ---
対象の相関 ID: 3f7a3936-4fdc-49eb-bfd8-f249b03e3428
取得した監査ログ件数: 5 件

--- 結合した監査ログ (一部表示) ---
--- 先頭 1000 文字 ---
{"targetUpdatedProperties":"[{\"Name\":\"PolicyDetail\",\"OldValue\":...
--- 中間を省略... (全体: 12345 文字) ---
--- 末尾 1000 文字 ---
...Applications":["Office365"]}]}}

--- アプリケーションの変更点 ---
REMOVED: 00000012-0000-0000-c000-000000000000
ADDED  : 00000003-0000-0ff1-ce00-000000000000

    Directory: C:\Temp

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d----            4/6/2026 12:57 PM                Output

--- エクスポート完了 ---
旧値ファイル保存先: C:\AuditLogRecovery\Output\_01_OldValue_Before_20260406_143025.txt
新値ファイル保存先: C:\AuditLogRecovery\Output\_02_NewValue_After_20260406_143025.txt
すべての処理が正常に完了しました。
```

## 出力ファイル

スクリプトの実行が完了すると、`-BaseDir` で指定したフォルダー (既定ではスクリプトと同階層の `Output` フォルダー) に以下の 2 つのファイルが出力されます。

| ファイル名 | 内容 |
|-----------|------|
| `_01_OldValue_Before_<タイムスタンプ>.txt` | 変更前の条件付きアクセス ポリシー設定 (JSON 形式) |
| `_02_NewValue_After_<タイムスタンプ>.txt` | 変更後の条件付きアクセス ポリシー設定 (JSON 形式) |

これらのファイルを比較することで、条件付きアクセス ポリシーの変更内容の全体像を確認できます。

## 補足: アプリケーション ID の確認

コンソール出力およびファイルに含まれるアプリケーションの値はアプリケーション ID (GUID) で表示されます。アプリケーション名を確認するには、Microsoft Entra 管理センターの [エンタープライズ アプリケーション] で該当の ID を検索するか、以下のコマンドで確認いただけます。

```powershell
Get-MgServicePrincipal -Filter "appId eq '<アプリケーション ID>'"
```
