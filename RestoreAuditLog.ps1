# 変数の設定
$baseDir = "C:\Users\baseDir\AuditRecoveryScript\Output"

# ここは復元したい監査ログの Correlation ID に置き換えてください
$correlationId = "3f7a3936-4fdc-49eb-bfd8-f249b03e3428" 

try {
    # Microsoft.Graph モジュールの存在を確認
    if (-not (Get-Module -Name Microsoft.Graph -ListAvailable)) {
        Write-Host "Microsoft.Graph モジュールが見つかりません。Install-Module Microsoft.Graph を実行してください。" -ForegroundColor Red
        exit 1
    }

    # 認証と接続（インタラクティブ認証）
    Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All"

    # Microsoft Graph からログを取得
    $rawResponse = Get-MgAuditLogDirectoryAudit -Filter "correlationId eq '$correlationId'" -All

    # JSON に変換
    $loadedData = $rawResponse | ConvertTo-Json -Depth 10

    # ログの実体を抽出
    $parsedData = $loadedData | ConvertFrom-Json -Depth 10
    $count = $parsedData.Count
    if ($count -eq 0) {
        Write-Host "--- 監査ログを取得できませんでした ---" -ForegroundColor Yellow
        return
    }

    Write-Host "--- Microsoft Graph からデータ取得完了 ---" -ForegroundColor Cyan
    Write-Host "対象の相関 ID: $($rawResponse[0].CorrelationId)" -ForegroundColor Green
    Write-Host "取得した監査ログ件数: $count 件" -ForegroundColor Green
    #Write-Host $parsedData -ForegroundColor White

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
    $oldValue = $innerObject[0].OldValue
    $newValue = $innerObject[0].NewValue

    # 出力ファイルを作成（タイムスタンプ付き、上書きを回避）
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $oldFile = Join-Path $baseDir "_01_OldValue_Before_${timestamp}.txt"
    $newFile = Join-Path $baseDir "_02_NewValue_After_${timestamp}.txt"

    # ディレクトリが存在しない場合は作成してからファイルを書き出す
    if (-not (Test-Path $baseDir)) {
    New-Item -ItemType Directory -Path $baseDir -Force
}
    $oldValue | Out-File -FilePath $oldFile -Encoding utf8
    $newValue | Out-File -FilePath $newFile -Encoding utf8

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