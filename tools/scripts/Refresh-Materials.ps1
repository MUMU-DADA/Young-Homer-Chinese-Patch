$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$patchRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dataPath = Join-Path (Split-Path $patchRoot -Parent) 'data.win'
$workRoot = Join-Path $patchRoot 'work'
$dumpRoot = Join-Path $workRoot 'utmt-dump'
$stringsPath = Join-Path $workRoot 'all-strings.json'
$fontsRoot = Join-Path $workRoot 'fonts-original'
$imageOriginalRoot = Join-Path $patchRoot 'materials\images\original\Sprites'
$utmt = Join-Path $patchRoot 'tools\utmt\UndertaleModCli.exe'
$exportStrings = Join-Path $patchRoot 'tools\utmt\Scripts\Resource Exporters\ExportAllStringsJSON.csx'
$exportFonts = Join-Path $patchRoot 'tools\utmt\Scripts\Resource Exporters\ExportAllFonts.csx'

foreach ($required in @($dataPath, $utmt, $exportStrings, $exportFonts)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "缺少输入：$required" }
}
New-Item -ItemType Directory -Force -Path $workRoot, $dumpRoot, $fontsRoot, $imageOriginalRoot | Out-Null

& $utmt dump $dataPath --output $dumpRoot --code UMT_DUMP_ALL --strings --sprites --textures
if ($LASTEXITCODE -ne 0) { throw '完整资源提取失败。' }
@($stringsPath) | & $utmt load $dataPath --scripts $exportStrings
if ($LASTEXITCODE -ne 0) { throw 'JSON 字符串提取失败。' }
@($fontsRoot) | & $utmt load $dataPath --scripts $exportFonts
if ($LASTEXITCODE -ne 0) { throw '原字体提取失败。' }

& (Join-Path $PSScriptRoot 'New-TranslationCatalog.ps1')
& (Join-Path $PSScriptRoot 'Apply-TranslationMap.ps1')
foreach ($name in @('sTitleScreen_0.png', 'sOpeningCard_0.png', 'sCredits_0.png')) {
    Copy-Item -LiteralPath (Join-Path $dumpRoot "Sprites\$name") -Destination $imageOriginalRoot -Force
}
& (Join-Path $PSScriptRoot 'Translate-Images.ps1')
Write-Host '汉化材料已刷新。' -ForegroundColor Green
