param(
    [string]$Catalog = (Join-Path $PSScriptRoot '..\..\materials\text\translation_catalog.json'),
    [string]$MapFile = (Join-Path $PSScriptRoot '..\..\materials\text\manual_translations.tsv')
)

$catalogObject = Get-Content -Raw -LiteralPath $Catalog | ConvertFrom-Json
$translations = @{}
foreach ($line in Get-Content -LiteralPath $MapFile -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2) { throw "Invalid translation map line: $line" }
    $value = $parts[1].Replace('\r', "`r").Replace('\n', "`n")
    $translations[[int]$parts[0]] = $value
}

$updated = 0
foreach ($entry in $catalogObject.entries) {
    if (-not $translations.ContainsKey([int]$entry.id)) { continue }
    $source = [string]$entry.source
    $value = [string]$translations[[int]$entry.id]
    if ($entry.constraints -contains 'edge_whitespace') {
        $prefix = [regex]::Match($source, '^\s*').Value
        $suffix = [regex]::Match($source, '\s*$').Value
        $value = $prefix + $value.Trim() + $suffix
    }
    $entry.translation = $value
    $updated++
}

$catalogObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Catalog -Encoding UTF8
Write-Output "Updated $updated entries from $($translations.Count) map rows."
