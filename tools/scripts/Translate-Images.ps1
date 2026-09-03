$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$original = Join-Path $root 'materials\images\original\Sprites'
$translated = Join-Path $root 'materials\images\translated\Sprites'
New-Item -ItemType Directory -Force -Path $translated | Out-Null

function New-Canvas([string]$name) {
    $input = [Drawing.Bitmap]::new((Join-Path $original $name))
    $output = [Drawing.Bitmap]::new($input.Width, $input.Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($output)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear([Drawing.Color]::Black)
    return [pscustomobject]@{ Input = $input; Output = $output; Graphics = $graphics }
}

function Draw-Border([Drawing.Graphics]$g, [int]$width, [int]$height) {
    $outer = [Drawing.Pen]::new([Drawing.Color]::White, 6)
    $inner = [Drawing.Pen]::new([Drawing.Color]::White, 2)
    try {
        $g.DrawRectangle($outer, 14, 14, $width - 28, $height - 28)
        $g.DrawRectangle($inner, 24, 24, $width - 48, $height - 48)
    } finally { $outer.Dispose(); $inner.Dispose() }
}

function Draw-Centered([Drawing.Graphics]$g, [string]$text, [Drawing.Font]$font, [float]$y, [float]$width, [Drawing.StringFormat]$format, [Drawing.Brush]$brush) {
    $g.DrawString($text, $font, $brush, [Drawing.RectangleF]::new(30, $y, $width - 60, $font.GetHeight($g) + 18), $format)
}

# Title screen: keep the original 1920x1080 contract while replacing every baked card caption.
$title = New-Canvas 'sTitleScreen_0.png'
try {
    Draw-Border $title.Graphics $title.Output.Width $title.Output.Height
    $center = [Drawing.StringFormat]::new()
    $center.Alignment = [Drawing.StringAlignment]::Center
    $center.LineAlignment = [Drawing.StringAlignment]::Center
    $white = [Drawing.Brushes]::White
    $titleFont = [Drawing.Font]::new('Microsoft YaHei UI', 82, [Drawing.FontStyle]::Bold)
    $subtitleFont = [Drawing.Font]::new('Microsoft YaHei UI', 42, [Drawing.FontStyle]::Regular)
    try {
        Draw-Centered $title.Graphics '年轻荷马' $titleFont 350 1920 $center $white
        Draw-Centered $title.Graphics '一位说书人的奥德赛' $subtitleFont 485 1920 $center $white
    } finally { $titleFont.Dispose(); $subtitleFont.Dispose(); $center.Dispose() }
    $title.Output.Save((Join-Path $translated 'sTitleScreen_0.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $title.Graphics.Dispose(); $title.Input.Dispose(); $title.Output.Dispose() }

# Opening card: preserve the illustration and replace only the baked prompt.
$opening = New-Canvas 'sOpeningCard_0.png'
try {
    $opening.Graphics.DrawImage($opening.Input, 0, 0)
    $opening.Graphics.FillRectangle(([Drawing.Brushes]::Black), 430, 620, 1060, 150)
    $center = [Drawing.StringFormat]::new()
    $center.Alignment = [Drawing.StringAlignment]::Center
    $center.LineAlignment = [Drawing.StringAlignment]::Center
    $font = [Drawing.Font]::new('Microsoft YaHei UI', 42, [Drawing.FontStyle]::Regular)
    try { Draw-Centered $opening.Graphics '按任意键继续' $font 650 1920 $center ([Drawing.Brushes]::White) }
    finally { $font.Dispose(); $center.Dispose() }
    $opening.Output.Save((Join-Path $translated 'sOpeningCard_0.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $opening.Graphics.Dispose(); $opening.Input.Dispose(); $opening.Output.Dispose() }

# Credits: names and font/library names remain as credits; all labels and descriptions are Chinese.
$credits = New-Canvas 'sCredits_0.png'
try {
    $g = $credits.Graphics
    Draw-Border $g $credits.Output.Width $credits.Output.Height
    $header = [Drawing.Font]::new('Microsoft YaHei UI', 42, [Drawing.FontStyle]::Bold)
    $body = [Drawing.Font]::new('Microsoft YaHei UI', 28, [Drawing.FontStyle]::Regular)
    $bold = [Drawing.Font]::new('Microsoft YaHei UI', 29, [Drawing.FontStyle]::Bold)
    $small = [Drawing.Font]::new('Microsoft YaHei UI', 24, [Drawing.FontStyle]::Regular)
    $center = [Drawing.StringFormat]::new()
    $center.Alignment = [Drawing.StringAlignment]::Center
    $center.LineAlignment = [Drawing.StringAlignment]::Center
    $left = [Drawing.StringFormat]::new()
    $left.Alignment = [Drawing.StringAlignment]::Near
    $left.LineAlignment = [Drawing.StringAlignment]::Center
    try {
        $g.FillRectangle(([Drawing.Brushes]::White), 210, 105, 660, 75)
        $g.FillRectangle(([Drawing.Brushes]::White), 1050, 105, 660, 75)
        $g.DrawString('诗篇', $header, ([Drawing.Brushes]::Black), [Drawing.RectangleF]::new(210, 105, 660, 75), $center)
        $g.DrawString('游戏', $header, ([Drawing.Brushes]::Black), [Drawing.RectangleF]::new(1050, 105, 660, 75), $center)
        $g.DrawString('《奥德赛》', $body, ([Drawing.Brushes]::White), 300, 250)
        $g.DrawString('HOMER', $bold, ([Drawing.Brushes]::White), 300, 320)
        $g.DrawString('III 级卡牌译文由', $body, ([Drawing.Brushes]::White), 300, 430)
        $g.DrawString('SAMUEL BUTLER', $bold, ([Drawing.Brushes]::White), 300, 505)
        $g.DrawString('字体', $body, ([Drawing.Brushes]::White), 250, 770)
        $g.DrawString('Pixelify Sans', $bold, ([Drawing.Brushes]::White), 250, 830)
        $g.DrawString('Unibody 8 Pro', $bold, ([Drawing.Brushes]::White), 250, 885)
        $g.DrawString('输入库', $body, ([Drawing.Brushes]::White), 600, 770)
        $g.DrawString('JUJU ADAMS,', $bold, ([Drawing.Brushes]::White), 600, 830)
        $g.DrawString('ALYNNE KEITH,', $bold, ([Drawing.Brushes]::White), 600, 885)
        $g.DrawString('以及朋友们', $bold, ([Drawing.Brushes]::White), 600, 940)
        $g.DrawString('游戏故事、插画与导演', $body, ([Drawing.Brushes]::White), [Drawing.RectangleF]::new(1120, 220, 620, 55), $left)
        $g.DrawString('THE VOICE OF NICK', $bold, ([Drawing.Brushes]::White), 1120, 290)
        $g.DrawString('I、II 级卡牌撰写', $body, ([Drawing.Brushes]::White), [Drawing.RectangleF]::new(1120, 420, 620, 55), $left)
        $g.DrawString('THE VOICE OF NICK', $bold, ([Drawing.Brushes]::White), 1120, 490)
        $g.DrawString('最初于 2023 年为冒险诗歌大赛创作', $small, ([Drawing.Brushes]::White), 1120, 640)
        $g.DrawString('耗时 18 天', $small, ([Drawing.Brushes]::White), 1120, 680)
        $g.DrawString('2026 年以新插画重制', $small, ([Drawing.Brushes]::White), 1120, 805)
        $g.DrawString('并加入手柄支持', $small, ([Drawing.Brushes]::White), 1120, 845)
    } finally { $header.Dispose(); $body.Dispose(); $bold.Dispose(); $small.Dispose(); $center.Dispose(); $left.Dispose() }
    $credits.Output.Save((Join-Path $translated 'sCredits_0.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $credits.Graphics.Dispose(); $credits.Input.Dispose(); $credits.Output.Dispose() }

Write-Host '已生成三张汉化图片。'
