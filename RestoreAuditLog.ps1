<#
  .SYNOPSIS
  条件付きアクセス ポリシーの変更に伴い分割記録された監査ログを結合・復元し、変更前後の差分を確認します。

  .DESCRIPTION
  Microsoft Graph API を使用して、指定した相関 ID に紐づく分割された監査ログを取得し、
  シーケンス番号順に結合・復元します。復元したデータから条件付きアクセス ポリシーの
  変更前 (OldValue) と変更後 (NewValue) を抽出し、アプリケーションの追加・削除の差分を表示します。

  .PARAMETER CorrelationId
  復元したい監査ログの相関 ID を指定します。

  .PARAMETER TenantId
  接続先のテナント ID を指定します。ゲスト ユーザーで実行する場合はテナント ID の指定が必要です。

  .PARAMETER BaseDir
  結果ファイルの出力先フォルダーのパスを指定します。既定値はスクリプトと同階層の Output フォルダーです。

  .PARAMETER Depth
  ConvertTo-Json / ConvertFrom-Json の深さを指定します。既定値は 10 です。
  取得したデータの構造が深い場合は、より大きな値を指定してください。

  .EXAMPLE
  .\AuditLogRecovery.ps1 -CorrelationId "3f7a3936-4fdc-49eb-bfd8-f249b03e3428"

  .EXAMPLE
  .\AuditLogRecovery.ps1 -CorrelationId "3f7a3936-4fdc-49eb-bfd8-f249b03e3428" -TenantId "contoso.onmicrosoft.com"

  .EXAMPLE
  .\AuditLogRecovery.ps1 -CorrelationId "3f7a3936-4fdc-49eb-bfd8-f249b03e3428" -TenantId "contoso.onmicrosoft.com" -BaseDir "C:\Temp\Output" -Depth 10
#>

Param(
    [Parameter(ValueFromPipeline = $true, mandatory = $true)][String]$CorrelationId,
    [Parameter(ValueFromPipeline = $true, mandatory = $false)][String]$TenantId,
    [Parameter(ValueFromPipeline = $true, mandatory = $false)][String]$BaseDir = (Join-Path $PSScriptRoot "Output"),
    [Parameter(ValueFromPipeline = $true, mandatory = $false)][Int]$Depth = 10
)

try {
    # Microsoft.Graph モジュールの存在を確認
    if (-not (Get-Module -Name Microsoft.Graph -ListAvailable)) {
        Write-Host "Microsoft.Graph モジュールが見つかりません。Install-Module Microsoft.Graph を実行してください。" -ForegroundColor Red
        exit 1
    }

    # 認証と接続（インタラクティブ認証）
    if ($TenantId) {
        Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All" -TenantId $TenantId
    }
    else {
        Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All"
    }

    # Microsoft Graph からログを取得
    $rawResponse = Get-MgAuditLogDirectoryAudit -Filter "correlationId eq '$CorrelationId'" -All

    # JSON に変換
    $loadedData = $rawResponse | ConvertTo-Json -Depth $Depth

    # ログの実体を抽出
    $parsedData = $loadedData | ConvertFrom-Json -Depth $Depth
    $count = $parsedData.Count
    if ($count -eq 0) {
        Write-Host "--- 監査ログを取得できませんでした ---" -ForegroundColor Yellow
        return
    }

    Write-Host "--- Microsoft Graph からデータ取得完了 ---" -ForegroundColor Cyan
    Write-Host "対象の相関 ID: $($rawResponse[0].CorrelationId)" -ForegroundColor Green
    Write-Host "取得した監査ログ件数: $count 件" -ForegroundColor Green

    # AdditionalDetails から seq フィールドを抽出して再構成
    $extractedDetails = $parsedData | ForEach-Object {
        $details = @{}
        foreach ($item in $_.AdditionalDetails) {
            $details[$item.Key] = $item.Value
        }
        $details
    }

    # seq でソートしてデータを結合
    $fullBlob = ($extractedDetails | Sort-Object { [int]$_.seq } | ForEach-Object { $_.b }) -join ""

    Write-Host "`n--- 結合した監査ログ (一部表示) ---" -ForegroundColor Cyan
    $maxPreviewChars = 2000
    if ($fullBlob.Length -le $maxPreviewChars) {
        Write-Host $fullBlob -ForegroundColor White
    }
    else {
        $head = $fullBlob.Substring(0, [Math]::Min(1000, $fullBlob.Length))
        $tail = $fullBlob.Substring([Math]::Max(0, $fullBlob.Length - 1000))
        Write-Host "--- 先頭 1000 文字 ---" -ForegroundColor DarkGray
        Write-Host $head -ForegroundColor White
        Write-Host "--- 中間を省略... (全体: $($fullBlob.Length) 文字) ---" -ForegroundColor DarkGray
        Write-Host "--- 末尾 1000 文字 ---" -ForegroundColor DarkGray
        Write-Host $tail -ForegroundColor White
    }

    # JSON をパース（外側）
    $restoredObject = $fullBlob | ConvertFrom-Json

    # 埋め込まれた JSON をパース（内側）
    $innerJsonString = $restoredObject.targetUpdatedProperties
    $innerObject = $innerJsonString | ConvertFrom-Json 

    # 値を抽出
    $oldValue = $innerObject[0].OldValue | ConvertFrom-Json
    $newValue = $innerObject[0].NewValue | ConvertFrom-Json

    # アプリケーションのリストをソートしてから出力（順序の違いを回避）
    $oldApps = $oldValue.Conditions.Applications.Include[0].Applications | Sort-Object
    $newApps = $newValue.Conditions.Applications.Include[0].Applications | Sort-Object

    $oldValue.Conditions.Applications.Include[0].Applications = $oldApps
    $newValue.Conditions.Applications.Include[0].Applications = $newApps

    # 旧値と新値を比較
    $diff = Compare-Object `
            -ReferenceObject $oldApps `
            -DifferenceObject $newApps `

    Write-Host "`n--- アプリケーションの変更点 ---" -ForegroundColor Cyan

    foreach ($item in $diff) {
        switch ($item.SideIndicator) {
            '<=' {
                Write-Host "REMOVED: $($item.InputObject)" -ForegroundColor Red
            }
            '=>' {
                Write-Host "ADDED  : $($item.InputObject)" -ForegroundColor Green
            }
        }
    }
    
    # 出力ファイルを作成（タイムスタンプ付き、上書きを回避）
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $oldFile = Join-Path $BaseDir "_01_OldValue_Before_${timestamp}.txt"
    $newFile = Join-Path $BaseDir "_02_NewValue_After_${timestamp}.txt"

    # ディレクトリが存在しない場合は作成してからファイルを書き出す
    if (-not (Test-Path $BaseDir)) {
        New-Item -ItemType Directory -Path $BaseDir -Force
    }
    
    # JSON をファイルに保存
    $oldValue | ConvertTo-Json -Depth $Depth | Out-File -FilePath $oldFile -Encoding utf8
    $newValue | ConvertTo-Json -Depth $Depth | Out-File -FilePath $newFile -Encoding utf8

    # 完了レポート
    Write-Host "`n--- エクスポート完了 ---" -ForegroundColor Cyan
    Write-Host "旧値ファイル保存先: $oldFile" -ForegroundColor Gray
    Write-Host "新値ファイル保存先: $newFile" -ForegroundColor Yellow
    Write-Host "すべての処理が正常に完了しました。" -ForegroundColor Green
}
catch {
    Write-Host "エラーが発生しました：" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "詳細スタックトレース：" -ForegroundColor DarkRed
    Write-Host $_.Exception.StackTrace -ForegroundColor DarkRed
    exit 1
}
finally {
    # Microsoft Graph から切断
    Disconnect-MgGraph
}
