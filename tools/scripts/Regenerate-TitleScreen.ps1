param(
    [string]$PatchRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$originalPath = Join-Path $PatchRoot 'materials\images\original\Sprites\sTitleScreen_0.png'
$translatedPath = Join-Path $PatchRoot 'materials\images\translated\Sprites\sTitleScreen_0.png'
$bitmap = [Drawing.Bitmap]::new($originalPath)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceOver

try {
    # Clear only the old center title; the surrounding cards remain from the original artwork.
    $graphics.FillRectangle([Drawing.Brushes]::Black, 360, 180, 1200, 260)

    $white = [Drawing.Brushes]::White
    $titleFont = [Drawing.Font]::new('Microsoft YaHei UI', 74, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $subtitleFont = [Drawing.Font]::new('Microsoft YaHei UI', 38, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    try {
        # Use code points so Windows PowerShell 5 reads the script identically on every locale.
        $title = ([char]0x5E74) + ([char]0x8F7B) + ([char]0x8377) + ([char]0x9A6C)
        $subtitle = ([char]0x4E00) + ([char]0x4F4D) + ([char]0x8BF4) + ([char]0x4E66) + ([char]0x4EBA) + ([char]0x7684) + ([char]0x5965) + ([char]0x5FB7) + ([char]0x8D5B)
        $titleSize = $graphics.MeasureString($title, $titleFont)
        $subtitleSize = $graphics.MeasureString($subtitle, $subtitleFont)
        $graphics.DrawString($title, $titleFont, $white, (1920 - $titleSize.Width) / 2, 176)
        $graphics.DrawString($subtitle, $subtitleFont, $white, (1920 - $subtitleSize.Width) / 2, 286)
    }
    finally {
        $titleFont.Dispose()
        $subtitleFont.Dispose()
    }

    $bitmap.Save($translatedPath, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

Write-Host "已更新标题图：$translatedPath"
