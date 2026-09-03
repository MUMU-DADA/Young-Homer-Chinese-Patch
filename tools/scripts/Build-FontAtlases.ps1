param(
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

$patchRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$catalogPath = Join-Path $patchRoot 'materials\text\translation_catalog.json'
$fontSourceRoot = Join-Path $patchRoot 'materials\fonts\source'
$originalRoot = Join-Path $patchRoot 'work\fonts-original'
$outputRoot = if ($SmokeTest) {
    Join-Path $patchRoot 'work\font-smoke-test'
} else {
    Join-Path $patchRoot 'build\font-import'
}

$fontSections = [ordered]@{
    f04_UniBlk                  = @('poem_title')
    f05_2_UniBlk_CardPower2     = @('card_title', 'ui')
    f05_UniBlk_PerfTitle        = @('card_title', 'ui')
    f06_UniReg_PerfDesc         = @('card_summary')
    f07_UniIt_PerfText          = @('card_text_level_1', 'card_text_level_2', 'card_text_level_3')
    f08_UniBold_Dialogue        = @('dialogue', 'narration', 'ui')
    f10_UniBold_UILeft          = @('dialogue', 'narration', 'ui')
    f12_UniBold_CardPolish      = @('ui')
    f13_UniBlk_NewCard          = @('narration', 'ui')
    f15_UniBold_UIPerfLevel     = @('ui')
    f16_UniIt_PerfLevelValue    = @('ui')
    f17_UniBold_UILeftCardsNum  = @('ui')
    f19_UniIt_GameSubtitle      = @('ui')
    f20_UniBold_AudienceRating  = @('ui')
    f21_UniReg_Review           = @('audience_review', 'ui')
    f22_UniBold_Review          = @('audience_review')
    f23_UniIt_Review            = @('audience_review', 'ui')
    f24_UniBold_ActionText      = @('ui', 'ui_control')
    f25_UniBold_TitleScreen     = @('ui', 'ui_control')
    f26_UniReg_TitleScreen      = @('ui', 'ui_control')
    f27_UniBold_TitleScreenMenu = @('ui')
    f28_UniIt_NoSound           = @('ui')
}

function Read-Bdf([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $glyphs = [Collections.Generic.Dictionary[int, object]]::new()
    $pixelSize = 0
    $boundingHeight = 0
    $ascent = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^PIXEL_SIZE\s+(\d+)') { $pixelSize = [int]$Matches[1]; continue }
        if ($line -match '^FONTBOUNDINGBOX\s+\d+\s+(\d+)') { $boundingHeight = [int]$Matches[1]; continue }
        if ($line -match '^FONT_ASCENT\s+(\d+)') { $ascent = [int]$Matches[1]; continue }
        if ($line -ne 'STARTCHAR .notdef' -and $line -notmatch '^STARTCHAR ') { continue }

        $encoding = -1
        $dWidth = 0
        $bbx = @(0, 0, 0, 0)
        $bitmapRows = [Collections.Generic.List[string]]::new()
        $readingBitmap = $false
        for ($i++; $i -lt $lines.Count -and $lines[$i] -ne 'ENDCHAR'; $i++) {
            $part = $lines[$i]
            if ($part -match '^ENCODING\s+(-?\d+)') { $encoding = [int]$Matches[1]; continue }
            if ($part -match '^DWIDTH\s+(-?\d+)') { $dWidth = [int]$Matches[1]; continue }
            if ($part -match '^BBX\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)') {
                $bbx = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4])
                continue
            }
            if ($part -eq 'BITMAP') { $readingBitmap = $true; continue }
            if ($readingBitmap) { $bitmapRows.Add($part.Trim()) }
        }
        if ($encoding -ge 0 -and $encoding -le 0xFFFF) {
            $glyphs[$encoding] = [pscustomobject]@{
                DWidth = $dWidth
                Width = $bbx[0]
                Height = $bbx[1]
                XOffset = $bbx[2]
                YOffset = $bbx[3]
                Rows = @($bitmapRows)
            }
        }
    }

    if ($pixelSize -eq 0 -or $boundingHeight -eq 0 -or $ascent -eq 0) {
        throw "BDF 头信息不完整：$Path"
    }
    return [pscustomobject]@{
        PixelSize = $pixelSize
        BoundingHeight = $boundingHeight
        Ascent = $ascent
        Glyphs = $glyphs
    }
}

function Get-NextPowerOfTwo([int]$Value) {
    $result = 1
    while ($result -lt $Value) { $result *= 2 }
    return $result
}

function Get-OriginalFontInfo([string]$FontName) {
    $csvPath = Join-Path $originalRoot "glyphs_$FontName.csv"
    $pngPath = Join-Path $originalRoot "$FontName.png"
    if (-not (Test-Path -LiteralPath $csvPath) -or -not (Test-Path -LiteralPath $pngPath)) {
        throw "缺少原字体导出：$FontName"
    }

    $lines = Get-Content -LiteralPath $csvPath
    $header = $lines[0]
    $a = $lines | Select-Object -Skip 1 | Where-Object { $_ -match '^65;' } | Select-Object -First 1
    $parts = $a -split ';'
    $bitmap = [Drawing.Bitmap]::FromFile($pngPath)
    try {
        $minY = [int]$parts[4]
        $maxY = -1
        for ($y = 0; $y -lt [int]$parts[4]; $y++) {
            for ($x = 0; $x -lt [int]$parts[3]; $x++) {
                if ($bitmap.GetPixel(([int]$parts[1]) + $x, ([int]$parts[2]) + $y).A -gt 0) {
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }
    }
    finally {
        $bitmap.Dispose()
    }

    return [pscustomobject]@{
        Header = $header
        CellHeight = [int]$parts[4]
        InkHeight = $maxY - $minY + 1
    }
}

function Get-Characters([object[]]$Entries, [string[]]$Sections) {
    $characters = [Collections.Generic.HashSet[int]]::new()
    foreach ($code in 32..126) { [void]$characters.Add($code) }
    [void]$characters.Add(9647)

    $selected = if ($SmokeTest) {
        @('中文汉化补丁：荷马、俄瑞斯、缪斯与奥德修斯。《故事》！？')
    } else {
        @($Entries | Where-Object { $_.section -in $Sections } | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_.translation)) {
                throw "尚未翻译：$($_.key)"
            }
            $_.translation
        })
    }

    foreach ($text in $selected) {
        foreach ($character in $text.ToCharArray()) {
            if ($character -eq "`r" -or $character -eq "`n") { continue }
            if ([char]::IsSurrogate($character)) {
                throw '译文包含 U+FFFF 以上字符；当前 GameMaker 字体格式不支持。'
            }
            [void]$characters.Add([int]$character)
        }
    }
    return @($characters | Sort-Object)
}

function Write-FontAtlas(
    [string]$FontName,
    [object]$Bdf,
    [int[]]$Characters,
    [object]$Original
) {
    $missing = @($Characters | Where-Object { -not $Bdf.Glyphs.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        $display = ($missing | Select-Object -First 20 | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ', '
        throw "$FontName 的源字体缺字：$display"
    }

    $scale = [Math]::Max(1, [Math]::Round($Original.InkHeight / $Bdf.PixelSize))
    while (($Bdf.BoundingHeight * $scale) -gt $Original.CellHeight) { $scale-- }
    if ($scale -lt 1) { throw "$FontName 无法容纳 BDF 字形" }

    $padding = 2
    $items = foreach ($code in $Characters) {
        $glyph = $Bdf.Glyphs[$code]
        [pscustomobject]@{
            Code = $code
            Glyph = $glyph
            Width = [Math]::Max(1, $glyph.Width * $scale)
        }
    }
    $area = ($items | ForEach-Object { ($_.Width + $padding) * ($Original.CellHeight + $padding) } | Measure-Object -Sum).Sum
    $atlasWidth = [Math]::Min(2048, [Math]::Max(256, (Get-NextPowerOfTwo ([int][Math]::Ceiling([Math]::Sqrt($area))))))

    do {
        $x = $padding
        $y = $padding
        $placements = [Collections.Generic.List[object]]::new()
        foreach ($item in $items) {
            if ($x + $item.Width + $padding -gt $atlasWidth) {
                $x = $padding
                $y += $Original.CellHeight + $padding
            }
            $placements.Add([pscustomobject]@{ Item = $item; X = $x; Y = $y })
            $x += $item.Width + $padding
        }
        $neededHeight = $y + $Original.CellHeight + $padding
        if ($neededHeight -le 2048) { break }
        if ($atlasWidth -ge 2048) { throw "$FontName 的字形超过单张 2048x2048 纹理容量" }
        $atlasWidth *= 2
    } while ($true)

    $atlasHeight = [Math]::Max(64, (Get-NextPowerOfTwo $neededHeight))
    $bitmap = [Drawing.Bitmap]::new($atlasWidth, $atlasHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $csv = [Collections.Generic.List[string]]::new()
        $csv.Add($Original.Header)
        $topPadding = [Math]::Floor(($Original.CellHeight - ($Bdf.BoundingHeight * $scale)) / 2)
        $baseline = $topPadding + ($Bdf.Ascent * $scale)

        foreach ($placement in $placements) {
            $item = $placement.Item
            $glyph = $item.Glyph
            $glyphTop = $baseline - (($glyph.YOffset + $glyph.Height) * $scale)
            for ($row = 0; $row -lt $glyph.Rows.Count; $row++) {
                $hex = $glyph.Rows[$row]
                if ([string]::IsNullOrEmpty($hex)) { continue }
                $bits = [Convert]::ToUInt64($hex, 16)
                $bitCount = $hex.Length * 4
                for ($column = 0; $column -lt $glyph.Width; $column++) {
                    $bit = $bitCount - 1 - $column
                    if (($bits -band ([uint64]1 -shl $bit)) -ne 0) {
                        $graphics.FillRectangle(
                            $brush,
                            $placement.X + ($column * $scale),
                            $placement.Y + $glyphTop + ($row * $scale),
                            $scale,
                            $scale
                        )
                    }
                }
            }

            $csv.Add((
                '{0};{1};{2};{3};{4};{5};{6}' -f
                $item.Code,
                $placement.X,
                $placement.Y,
                $item.Width,
                $Original.CellHeight,
                ($glyph.DWidth * $scale),
                ($glyph.XOffset * $scale)
            ))
        }

        $bitmap.Save((Join-Path $outputRoot "$FontName.png"), [Drawing.Imaging.ImageFormat]::Png)
        $csv | Set-Content -LiteralPath (Join-Path $outputRoot "glyphs_$FontName.csv") -Encoding utf8
    }
    finally {
        $brush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    [pscustomobject]@{
        Font = $FontName
        Glyphs = $Characters.Count
        Scale = $scale
        Atlas = "${atlasWidth}x${atlasHeight}"
    }
}

foreach ($required in @($catalogPath, $fontSourceRoot, $originalRoot)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "缺少输入：$required" }
}

$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$bdf10 = Read-Bdf (Join-Path $fontSourceRoot 'fusion-pixel-10px-proportional-zh_hans.bdf')
$bdf12 = Read-Bdf (Join-Path $fontSourceRoot 'fusion-pixel-12px-proportional-zh_hans.bdf')
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

# ponytail: one regular bitmap source covers every game style; add separate weights only if visual QA proves necessary.
$results = foreach ($font in $fontSections.Keys) {
    $original = Get-OriginalFontInfo $font
    $bdf = if ($original.InkHeight -lt 24) { $bdf10 } else { $bdf12 }
    $characters = Get-Characters $catalog.entries $fontSections[$font]
    Write-FontAtlas $font $bdf $characters $original
}
$results | Format-Table -AutoSize
Write-Host "已生成字体导入目录：$outputRoot"
