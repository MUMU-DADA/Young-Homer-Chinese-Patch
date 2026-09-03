$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$patchRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$workRoot = Join-Path $patchRoot 'work'
$stringsPath = Join-Path $workRoot 'all-strings.json'
$codeRoot = Join-Path $workRoot 'utmt-dump\CodeEntries'
$outputRoot = Join-Path $patchRoot 'materials\text'
$outputPath = Join-Path $outputRoot 'translation_catalog.json'
$gameDataPath = Join-Path (Split-Path $patchRoot -Parent) 'data.win'

foreach ($required in @($stringsPath, $codeRoot, $gameDataPath)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "缺少输入：$required"
    }
}

function Get-Sha256Text([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-Section([string]$File, [string]$Usage, [string]$Text) {
    if ($File -eq 'gml_GlobalScript_scrReviews.gml') { return 'audience_review' }
    if ($File -eq 'gml_GlobalScript_scrActionPromptText.gml') { return 'ui_control' }
    if ($File -match '^gml_Object_o?c\d+_.+_Create_0\.gml$') {
        if ($Usage -match '\bcardName\b') { return 'card_title' }
        if ($Usage -match '\bcardDesc\b') { return 'card_summary' }
        if ($Usage -match '\btextLv1\b') { return 'card_text_level_1' }
        if ($Usage -match '\btextLv2\b') { return 'card_text_level_2' }
        if ($Usage -match '\btextLv3\b') { return 'card_text_level_3' }
        return 'card_text'
    }
    if ($Usage -match '\bpoemName\[') { return 'poem_title' }
    if ($Text -match '^(HOMER|ORESTES|EMCEE)\s*\r\n\r\n') { return 'dialogue' }
    if ($File -match '^gml_Object_oSc\d+') {
        if ($File -match '_Draw_0\.gml$' -or $File -match 'TitleScreen') { return 'ui' }
        return 'narration'
    }
    if ($File -match '^gml_Object_') { return 'ui' }
    return 'game_text'
}

$allStrings = @((Get-Content -Raw -LiteralPath $stringsPath | ConvertFrom-Json).Strings)
$idsByText = [Collections.Generic.Dictionary[string, Collections.Generic.List[int]]]::new(
    [StringComparer]::Ordinal
)
for ($id = 0; $id -lt $allStrings.Count; $id++) {
    $value = [string]$allStrings[$id]
    if (-not $idsByText.ContainsKey($value)) {
        $idsByText[$value] = [Collections.Generic.List[int]]::new()
    }
    $idsByText[$value].Add($id)
}

$contextsById = @{}
$excludedFiles = @(
    'gml_GlobalScript_scrInputDevicesCheck.gml',
    'gml_GlobalScript_scrSceneChanges.gml',
    'gml_GlobalScript_scrCardVisuals.gml'
)
$technicalValues = @('Instances', 'Cards', 'Border', 'I', 'II', 'III', 'A', 'B', 'X')
$deviceKeys = @('keyboard', 'playstation', 'xbox', 'switch')
$unmatched = [Collections.Generic.List[object]]::new()

$files = Get-ChildItem -LiteralPath $codeRoot -Filter '*.gml' | Where-Object {
    ($_.Name -like 'gml_Object_*' -or
     ($_.Name -like 'gml_GlobalScript_*' -and $_.Name -notmatch '^gml_GlobalScript_(?:__)?Input|^gml_GlobalScript_input')) -and
    $_.Name -notmatch 'TEST|TEMPLATE|DEBUG' -and
    $_.Name -notin $excludedFiles
} | Sort-Object Name

foreach ($file in $files) {
    $source = Get-Content -Raw -LiteralPath $file.FullName
    $lineArray = $source -split "`n"
    $matches = [regex]::Matches(
        $source,
        '"(?:\\.|[^"\\])*"',
        [Text.RegularExpressions.RegexOptions]::Singleline
    )

    foreach ($match in $matches) {
        try {
            $text = [Text.Json.JsonSerializer]::Deserialize([string]$match.Value, [type][string])
        }
        catch {
            continue
        }

        if ($text -notmatch '[A-Za-z]') { continue }
        $line = 1 + [regex]::Matches($source.Substring(0, $match.Index), "`n").Count
        $usage = $lineArray[$line - 1].Trim()
        if ($text -in $technicalValues) { continue }
        if ($file.Name -eq 'gml_GlobalScript_scrActionPromptText.gml' -and $text -in $deviceKeys) { continue }
        if ($usage -match '\bshow_debug_message\s*\(') { continue }

        if ($match.Index -gt 0 -and $source[$match.Index - 1] -eq '$') {
            $placeholder = 0
            $text = [regex]::Replace($text, '\{[^{}]+\}', {
                param($m)
                $result = "{$placeholder}"
                $script:placeholder++
                return $result
            })
        }
        if ($text -match '^[+-]?\{\d+\}$') { continue }

        if (-not $idsByText.ContainsKey($text)) {
            $unmatched.Add([ordered]@{ file = $file.Name; line = $line; text = $text })
            continue
        }

        foreach ($id in $idsByText[$text]) {
            if (-not $contextsById.ContainsKey($id)) {
                $contextsById[$id] = [Collections.Generic.List[object]]::new()
            }
            $contextsById[$id].Add([ordered]@{
                file = $file.Name
                line = $line
                usage = $usage
            })
        }
    }
}

$entries = [Collections.Generic.List[object]]::new()
foreach ($id in @($contextsById.Keys | Sort-Object)) {
    $source = [string]$allStrings[$id]
    $contexts = @($contextsById[$id])
    $section = Get-Section $contexts[0].file $contexts[0].usage $source
    $speaker = $null
    if ($source -match '^(HOMER|ORESTES|EMCEE)\s*\r\n\r\n') {
        $speaker = $Matches[1]
    }

    $constraints = [Collections.Generic.List[string]]::new()
    if ($source -match '\{\d+\}') { $constraints.Add('placeholders') }
    if ($source.Contains("`r`n")) { $constraints.Add('line_breaks') }
    if ($source -match '^\s|\s$') { $constraints.Add('edge_whitespace') }
    if ($source -in @('A', 'B', 'X')) { $constraints.Add('button_symbol') }

    $entries.Add([ordered]@{
        id = [int]$id
        key = 'str_{0:D4}' -f [int]$id
        section = $section
        speaker = $speaker
        source = $source
        translation = ''
        constraints = @($constraints)
        contexts = $contexts
        source_sha256 = Get-Sha256Text $source
    })
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$catalog = [ordered]@{
    schema = 1
    game = "Young Homer: A Storyteller's Odyssey"
    source_language = 'en'
    target_language = 'zh-Hans'
    source_data_sha256 = (Get-FileHash -LiteralPath $gameDataPath -Algorithm SHA256).Hash.ToLowerInvariant()
    source_string_count = $allStrings.Count
    translatable_count = $entries.Count
    note = '只填写 translation；不得修改 id、source、source_sha256、constraints 或 contexts。'
    entries = $entries
}
$catalog | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding utf8

Write-Host "已生成：$outputPath"
Write-Host "待翻译条目：$($entries.Count) / 原始字符串：$($allStrings.Count)"
if ($unmatched.Count -gt 0) {
    Write-Warning "有 $($unmatched.Count) 个反编译字符串无法映射到 STRG；它们多为反编译器重建表达式。"
    $unmatched | ConvertTo-Json -Depth 4
}
