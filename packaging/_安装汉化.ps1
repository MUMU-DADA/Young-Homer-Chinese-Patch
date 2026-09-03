$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$dataPath = Join-Path $PSScriptRoot 'data.win'
$patchPath = Join-Path $PSScriptRoot '汉化数据\young-homer-zh.yhp'
$manifestPath = Join-Path $PSScriptRoot '汉化数据\manifest.json'
$backupPath = Join-Path $PSScriptRoot 'data.win.young-homer-zh.backup'
$tempPath = Join-Path $PSScriptRoot 'data.win.young-homer-zh.tmp'
$swapPath = Join-Path $PSScriptRoot 'data.win.young-homer-zh.swap'

Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;

public static class YhpDelta {
    [DllImport("msdelta.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ApplyDeltaW(long applyFlags, string source, string delta, string target);
}
'@

function Get-Hash([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) }
    finally { $stream.Dispose(); $sha.Dispose() }
}

try {
    if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
        throw '未找到 data.win。请把补丁完整解压到游戏根目录后再运行。'
    }
    if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw '补丁数据不完整，请重新解压汉化补丁。'
    }

    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $sourceLength = [int64]$manifest.source_bytes
    $targetLength = [int64]$manifest.target_bytes
    $sourceHash = ([string]$manifest.source_sha256).ToLowerInvariant()
    $targetHash = ([string]$manifest.target_sha256).ToLowerInvariant()
    if ($manifest.format -ne 1 -or $sourceLength -le 0 -or $targetLength -le 0 -or
        $sourceHash -notmatch '^[0-9a-f]{64}$' -or $targetHash -notmatch '^[0-9a-f]{64}$') {
        throw '补丁清单格式错误。'
    }

    $currentHash = Get-Hash $dataPath
    if ($currentHash -eq $targetHash) {
        Write-Host '汉化已经安装，无需重复操作。' -ForegroundColor Green
        exit 0
    }
    if ($currentHash -ne $sourceHash -or (Get-Item -LiteralPath $dataPath).Length -ne $sourceLength) {
        throw 'data.win 版本不匹配或已被其他补丁修改。为避免损坏游戏，安装已取消。'
    }
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        if ((Get-Hash $backupPath) -ne $sourceHash) {
            throw '现有备份文件不是原版 data.win。请先妥善处理该备份，安装已取消。'
        }
    }

    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    if (-not [YhpDelta]::ApplyDeltaW(0, $dataPath, $patchPath, $tempPath)) {
        throw "补丁应用失败，Win32 错误码：$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    if ((Get-Item -LiteralPath $tempPath).Length -ne $targetLength -or (Get-Hash $tempPath) -ne $targetHash) {
        throw '生成的汉化 data.win 校验失败，原文件未被修改。'
    }

    if (-not (Test-Path -LiteralPath $backupPath)) {
        [IO.File]::Copy($dataPath, $backupPath, $false)
    }
    if (Test-Path -LiteralPath $swapPath) { Remove-Item -LiteralPath $swapPath -Force }
    [IO.File]::Replace($tempPath, $dataPath, $swapPath)
    Remove-Item -LiteralPath $swapPath -Force
    Write-Host '汉化安装完成。原版 data.win 已安全备份。' -ForegroundColor Green
}
catch {
    Write-Host "安装失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    if (Test-Path -LiteralPath $swapPath) { Remove-Item -LiteralPath $swapPath -Force }
}
