param(
    [Parameter(Mandatory)][string]$SourceFile,
    [Parameter(Mandatory)][string]$TargetFile,
    [Parameter(Mandatory)][string]$OutputFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class YhpDeltaBuilder {
    [StructLayout(LayoutKind.Sequential)]
    public struct DeltaInput {
        public IntPtr Start;
        public UIntPtr Size;
        [MarshalAs(UnmanagedType.Bool)] public bool Editable;
    }

    [DllImport("msdelta.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CreateDeltaW(
        long fileTypeSet,
        long setFlags,
        long resetFlags,
        string source,
        string target,
        string sourceOptions,
        string targetOptions,
        DeltaInput globalOptions,
        IntPtr targetFileTime,
        uint hashAlgId,
        string delta
    );
}
'@

$sourcePath = (Resolve-Path -LiteralPath $SourceFile).Path
$targetPath = (Resolve-Path -LiteralPath $TargetFile).Path
$outputPath = [IO.Path]::GetFullPath($OutputFile)
New-Item -ItemType Directory -Force -Path (Split-Path $outputPath -Parent) | Out-Null
if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }

$empty = [YhpDeltaBuilder+DeltaInput]::new()
$created = [YhpDeltaBuilder]::CreateDeltaW(
    1, 0, 0,
    $sourcePath, $targetPath,
    $null, $null, $empty,
    [IntPtr]::Zero, 32,
    $outputPath
)
if (-not $created) {
    throw "MSDelta 创建补丁失败，Win32 错误码：$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

$manifestPath = Join-Path (Split-Path $outputPath -Parent) 'manifest.json'
[ordered]@{
    format = 1
    source_bytes = (Get-Item -LiteralPath $sourcePath).Length
    source_sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    target_bytes = (Get-Item -LiteralPath $targetPath).Length
    target_sha256 = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8

[pscustomobject]@{
    SourceBytes = (Get-Item -LiteralPath $sourcePath).Length
    TargetBytes = (Get-Item -LiteralPath $targetPath).Length
    PatchBytes = (Get-Item -LiteralPath $outputPath).Length
    Output = $outputPath
    Manifest = $manifestPath
} | Format-List
