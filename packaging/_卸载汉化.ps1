$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$dataPath = Join-Path $PSScriptRoot 'data.win'
$manifestPath = Join-Path $PSScriptRoot '汉化数据\manifest.json'
$backupPath = Join-Path $PSScriptRoot 'data.win.young-homer-zh.backup'
$swapPath = Join-Path $PSScriptRoot 'data.win.young-homer-zh.swap'

function Get-Hash([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) }
    finally { $stream.Dispose(); $sha.Dispose() }
}

try {
    if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
        throw '未找到 data.win。请在游戏根目录运行卸载脚本。'
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw '补丁数据不完整，无法确认当前文件版本。'
    }

    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $sourceHash = ([string]$manifest.source_sha256).ToLowerInvariant()
    $targetHash = ([string]$manifest.target_sha256).ToLowerInvariant()
    if ($manifest.format -ne 1 -or $sourceHash -notmatch '^[0-9a-f]{64}$' -or
        $targetHash -notmatch '^[0-9a-f]{64}$') {
        throw '补丁清单格式错误。'
    }

    $currentHash = Get-Hash $dataPath
    if ($currentHash -eq $sourceHash) {
        Write-Host '当前已是原版，无需卸载。' -ForegroundColor Green
        exit 0
    }
    if ($currentHash -ne $targetHash) {
        throw '当前 data.win 在安装汉化后又被修改。为避免丢失其他改动，卸载已取消。'
    }
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw '未找到安装时生成的原版备份，无法安全卸载。'
    }
    if ((Get-Hash $backupPath) -ne $sourceHash) {
        throw '原版备份校验失败，卸载已取消。'
    }

    if (Test-Path -LiteralPath $swapPath) { Remove-Item -LiteralPath $swapPath -Force }
    [IO.File]::Replace($backupPath, $dataPath, $swapPath)
    Remove-Item -LiteralPath $swapPath -Force
    Write-Host '汉化已卸载，原版 data.win 已恢复。' -ForegroundColor Green
}
catch {
    Write-Host "卸载失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $swapPath) { Remove-Item -LiteralPath $swapPath -Force }
}
