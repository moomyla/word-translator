# 由 translator.ahk 调用,不需要手动运行。
# 用法: powershell -File translate.ps1 <输入文本文件> <输出结果文件>

param(
    [Parameter(Mandatory = $true)][string]$InputFile,
    [Parameter(Mandatory = $true)][string]$OutputFile
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.ini"

function Get-IniValue {
    param([string]$Path, [string]$Section, [string]$Key)
    $inSection = $false
    foreach ($line in Get-Content -Path $Path) {
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') {
            $inSection = ($matches[1] -eq $Section)
            continue
        }
        if ($inSection -and $trim -match '^([^=;]+)=(.*)$') {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            if ($k -eq $Key) { return $v }
        }
    }
    return $null
}

try {
    if (-not (Test-Path $configPath)) {
        "[错误] 找不到 config.ini,请先从 config.example.ini 复制一份并填入 API Key" |
            Out-File -FilePath $OutputFile -Encoding utf8
        exit 1
    }

    $apiKey = Get-IniValue -Path $configPath -Section "api" -Key "key"
    $model = Get-IniValue -Path $configPath -Section "api" -Key "model"
    if ([string]::IsNullOrWhiteSpace($model)) { $model = "claude-haiku-4-5-20251001" }

    if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq "YOUR_ANTHROPIC_API_KEY_HERE") {
        "[错误] 还没有在 config.ini 里填写 API Key" | Out-File -FilePath $OutputFile -Encoding utf8
        exit 1
    }

    $text = Get-Content -Path $InputFile -Raw -Encoding UTF8
    if ($null -eq $text) { $text = "" }
    $text = $text.Trim()

    if ([string]::IsNullOrWhiteSpace($text)) {
        "" | Out-File -FilePath $OutputFile -Encoding utf8
        exit 0
    }

    if ($text.Length -le 20) {
        $systemPrompt = "你是词典助手。给出这个词或短语准确的翻译,如果是单词可以附上简明释义或词性,不超过两行。只输出翻译结果本身,不要任何解释、前缀、引号或 Markdown 标记。"
    }
    else {
        $systemPrompt = "把下面的内容在中文和英文之间自动判断方向并翻译(中文原文译成英文,英文或其他语言原文译成中文)。只输出翻译结果本身,不要任何解释、前缀或 Markdown 标记。"
    }

    $bodyObj = @{
        model      = $model
        max_tokens = 1024
        system     = $systemPrompt
        messages   = @(
            @{ role = "user"; content = $text }
        )
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 5
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    $headers = @{
        "x-api-key"         = $apiKey
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }

    # 用 Invoke-WebRequest + 手动按 UTF-8 解码原始字节,
    # 绕开 Windows PowerShell 5.1 的一个老问题:
    # 当响应没有显式声明 charset=utf-8 时,Invoke-RestMethod 会用错误的旧编码解析正文,
    # 导致中文变成"重复编码"的乱码。
    $webResponse = Invoke-WebRequest -Uri "https://api.anthropic.com/v1/messages" `
        -Method Post -Headers $headers -Body $bodyBytes -UseBasicParsing

    $rawStream = $webResponse.RawContentStream
    $rawStream.Position = 0
    $reader = New-Object System.IO.StreamReader($rawStream, [System.Text.Encoding]::UTF8)
    $jsonText = $reader.ReadToEnd()
    $reader.Dispose()

    $responseObj = $jsonText | ConvertFrom-Json
    $result = $responseObj.content[0].text
    $result | Out-File -FilePath $OutputFile -Encoding utf8
}
catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        $msg = $_.ErrorDetails.Message
    }
    "[翻译出错] $msg" | Out-File -FilePath $OutputFile -Encoding utf8
    exit 1
}
