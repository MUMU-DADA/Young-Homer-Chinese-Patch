param(
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$patchRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$gameRoot = Split-Path $patchRoot -Parent
$dataPath = Join-Path $gameRoot 'data.win'
$catalogPath = Join-Path $patchRoot 'materials\text\translation_catalog.json'
$allStringsPath = Join-Path $patchRoot 'work\all-strings.json'
$imageOriginalRoot = Join-Path $patchRoot 'materials\images\original\Sprites'
$imageTranslatedRoot = Join-Path $patchRoot 'materials\images\translated\Sprites'
$utmt = Join-Path $patchRoot 'tools\utmt\UndertaleModCli.exe'
$importStrings = Join-Path $patchRoot 'tools\utmt\Scripts\Resource Importers\ImportAllStringsJSON.csx'
$importFonts = Join-Path $patchRoot 'tools\utmt\Scripts\Resource Importers\ImportFonts.csx'
$importGraphics = Join-Path $patchRoot 'tools\utmt\Scripts\Resource Importers\ImportGraphics.csx'
$buildRoot = Join-Path $patchRoot 'build'

foreach ($required in @($dataPath, $catalogPath, $allStringsPath, $utmt)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "缺少输入：$required" }
}

function Get-Sha256Text([string]$Text) {
    $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Assert-Translation([object]$Entry) {
    if ([string]::IsNullOrWhiteSpace($Entry.translation)) {
        throw "尚未翻译：$($Entry.key)"
    }
    if ((Get-Sha256Text $Entry.source) -ne $Entry.source_sha256) {
        throw "原文校验失败：$($Entry.key)"
    }

    $sourcePlaceholders = @([regex]::Matches($Entry.source, '\{\d+\}') | ForEach-Object Value | Sort-Object)
    $targetPlaceholders = @([regex]::Matches($Entry.translation, '\{\d+\}') | ForEach-Object Value | Sort-Object)
    if (($sourcePlaceholders -join '|') -ne ($targetPlaceholders -join '|')) {
        throw "占位符不一致：$($Entry.key)"
    }

    if ('line_breaks' -in $Entry.constraints -and $Entry.section -notlike 'card_text_level_*' -and $Entry.section -ne 'card_summary') {
        $sourceBreaks = @([regex]::Matches($Entry.source, "`r`n")).Count
        $targetBreaks = @([regex]::Matches($Entry.translation, "`r`n")).Count
        if ($sourceBreaks -ne $targetBreaks) {
            throw "CRLF 换行数量不一致：$($Entry.key)"
        }
    }
    if ('edge_whitespace' -in $Entry.constraints) {
        $sourceLead = [regex]::Match($Entry.source, '^\s*').Value
        $targetLead = [regex]::Match($Entry.translation, '^\s*').Value
        $sourceTail = [regex]::Match($Entry.source, '\s*$').Value
        $targetTail = [regex]::Match($Entry.translation, '\s*$').Value
        if ($sourceLead -ne $targetLead -or $sourceTail -ne $targetTail) {
            throw "首尾空白不一致：$($Entry.key)"
        }
    }
    if ($Entry.speaker -and $Entry.translation -notmatch '^.+\r\n\r\n') {
        throw "说话人标题或空行格式缺失：$($Entry.key)"
    }
}

function Add-CardLineBreaks([string]$Text, [int]$MaxChars = 44) {
    $trailing = $Text.EndsWith("`r`n")
    $body = if ($trailing) { $Text.Substring(0, $Text.Length - 2) } else { $Text }
    $lines = [Collections.Generic.List[string]]::new()
    while ($body.Length -gt 0) {
        if ($body.Length -le $MaxChars) {
            $lines.Add($body)
            break
        }
        $cut = $MaxChars
        $punctuation = [regex]::Matches($body.Substring(0, $cut), '[，。！？；：、]')
        if ($punctuation.Count -gt 0) { $cut = $punctuation[$punctuation.Count - 1].Index + 1 }
        $lines.Add($body.Substring(0, $cut))
        $body = $body.Substring($cut)
    }
    $result = $lines -join "`r`n"
    if ($trailing) { $result += "`r`n" }
    return $result
}

function Assert-TranslatedImages {
    Add-Type -AssemblyName System.Drawing
    foreach ($name in @('sTitleScreen_0.png', 'sOpeningCard_0.png', 'sCredits_0.png')) {
        $original = Join-Path $imageOriginalRoot $name
        $translated = Join-Path $imageTranslatedRoot $name
        if (-not (Test-Path -LiteralPath $translated)) { throw "缺少汉化图片：$name" }
        if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $translated -Algorithm SHA256).Hash) {
            throw "汉化图片仍与原图相同：$name"
        }
        $a = [Drawing.Image]::FromFile($original)
        $b = [Drawing.Image]::FromFile($translated)
        try {
            if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height) {
                throw "汉化图片尺寸错误：$name（应为 $($a.Width)x$($a.Height)）"
            }
        }
        finally { $a.Dispose(); $b.Dispose() }
    }
}

$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$allStrings = @((Get-Content -Raw -LiteralPath $allStringsPath | ConvertFrom-Json).Strings)
$sourceHash = (Get-FileHash -LiteralPath $dataPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceHash -ne $catalog.source_data_sha256) { throw 'data.win 与提取材料时的版本不一致。' }
if ($allStrings.Count -ne $catalog.source_string_count) { throw '原始 STRG 数量不一致。' }

$translatedStrings = @($allStrings)
if (-not $SmokeTest) {
    foreach ($entry in $catalog.entries) {
        Assert-Translation $entry
        if ($allStrings[$entry.id] -ne $entry.source) { throw "STRG 原文不一致：$($entry.key)" }
        $translatedStrings[$entry.id] = if ($entry.section -like 'card_text_level_*') {
            Add-CardLineBreaks $entry.translation 44
        } elseif ($entry.section -eq 'card_summary') {
            Add-CardLineBreaks $entry.translation 24
        } else {
            $entry.translation
        }
    }
    & (Join-Path $PSScriptRoot 'Regenerate-TitleScreen.ps1')
    Assert-TranslatedImages
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
$stringsImportPath = Join-Path $buildRoot 'strings-import.json'
[ordered]@{ Strings = $translatedStrings } |
    ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath $stringsImportPath -Encoding utf8

if ($SmokeTest) {
    & (Join-Path $PSScriptRoot 'Build-FontAtlases.ps1') -SmokeTest
    $fontRoot = Join-Path $patchRoot 'work\font-smoke-test'
    $imageRoot = Split-Path $imageOriginalRoot -Parent
    $localizedData = Join-Path $patchRoot 'work\smoke-full-data.win'
} else {
    & (Join-Path $PSScriptRoot 'Build-FontAtlases.ps1')
    $fontRoot = Join-Path $buildRoot 'font-import'
    $imageRoot = Split-Path $imageTranslatedRoot -Parent
    $localizedData = Join-Path $buildRoot 'data.zh-Hans.win'
}

$stringsData = Join-Path $buildRoot 'data.strings.win'
$fontsData = Join-Path $buildRoot 'data.fonts.win'
@($stringsImportPath) | & $utmt load $dataPath --scripts $importStrings --output $stringsData --overwrite
if ($LASTEXITCODE -ne 0) { throw 'UndertaleModTool 字符串写入失败。' }
@($fontRoot) | & $utmt load $stringsData --scripts $importFonts --output $fontsData --overwrite
if ($LASTEXITCODE -ne 0) { throw 'UndertaleModTool 字体写入失败。' }
@('y', $imageRoot) | & $utmt load $fontsData --scripts $importGraphics --output $localizedData --overwrite
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $localizedData)) {
    throw 'UndertaleModTool 图片写入失败。'
}
& $utmt info $localizedData | Out-Host
if ($LASTEXITCODE -ne 0) { throw '生成的 data.win 无法重新读取。' }

if ($SmokeTest) {
    Write-Host "准备流程自检通过：$localizedData" -ForegroundColor Green
    exit 0
}

$stageRoot = Join-Path $buildRoot 'package-root'
$resolvedPatchRoot = [IO.Path]::GetFullPath($patchRoot).TrimEnd('\') + '\'
$resolvedStageRoot = [IO.Path]::GetFullPath($stageRoot)
if (-not $resolvedStageRoot.StartsWith($resolvedPatchRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw '打包暂存目录越界。'
}
if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot '汉化数据') | Out-Null
Copy-Item -LiteralPath (Join-Path $patchRoot 'packaging\安装汉化.cmd') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $patchRoot 'packaging\卸载汉化.cmd') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $patchRoot 'packaging\_安装汉化.ps1') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $patchRoot 'packaging\_卸载汉化.ps1') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $patchRoot 'packaging\玩家说明.txt') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $patchRoot 'materials\fonts\source\OFL-fusion-pixel-12px.txt') -Destination (Join-Path $stageRoot '汉化数据\字体许可证.txt')

$payloadPath = Join-Path $stageRoot '汉化数据\young-homer-zh.yhp'
& (Join-Path $PSScriptRoot 'New-YhpPatch.ps1') -SourceFile $dataPath -TargetFile $localizedData -OutputFile $payloadPath

$zipPath = Join-Path $buildRoot 'Young-Homer-Chinese-Patch.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "汉化补丁已生成：$zipPath" -ForegroundColor Green
