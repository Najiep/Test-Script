param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

$ErrorActionPreference = 'Stop'
$zipPath = Join-Path $env:RUNNER_TEMP 'dex-smart-hq-overrides.zip'
$extractPath = Join-Path $env:RUNNER_TEMP 'dex-smart-hq-overrides'

$firstPart = Join-Path $PSScriptRoot 'smart-hq-parts/part-00.b64'
$remainingParts = Get-ChildItem (Join-Path $PSScriptRoot 'smart-hq-chunks/chunk-*.b64') | Sort-Object Name
if (-not (Test-Path $firstPart)) { throw 'Smart HQ payload part 00 is missing.' }
if ($remainingParts.Count -ne 9) { throw "Expected 9 Smart HQ payload chunks, found $($remainingParts.Count)." }

$partTexts = @((Get-Content $firstPart -Raw).Trim())
$partTexts += $remainingParts | ForEach-Object { (Get-Content $_.FullName -Raw).Trim() }
$base64 = $partTexts -join ''
if ($base64.Length -ne 45520) { throw "Smart HQ payload length mismatch: $($base64.Length)." }

$textHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($base64))).ToLowerInvariant()
if ($textHash -ne 'b90d84b5fddff4dbadddb41eab1e159e2df23318367e2b9f402c138f0b458188') {
    throw "Smart HQ payload checksum mismatch: $textHash"
}

[IO.File]::WriteAllBytes($zipPath, [Convert]::FromBase64String($base64))
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($zipHash -ne 'a4f24942095442ca8e2e93ba131b0b87f1f00f81f372db007fa270fa7b721fb3') {
    throw "Smart HQ archive checksum mismatch: $zipHash"
}

if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
Copy-Item (Join-Path $extractPath '*') -Destination $SourceRoot -Recurse -Force

# GlobalUsings.cs already provides the WPF MessageBox alias in the base build fixes.
$mainWindowPath = Join-Path $SourceRoot 'DexClothingOptimizer/MainWindow.xaml.cs'
$mainWindowText = Get-Content $mainWindowPath -Raw
$mainWindowText = $mainWindowText.Replace("using MessageBox = System.Windows.MessageBox;`r`n", '')
$mainWindowText = $mainWindowText.Replace("using MessageBox = System.Windows.MessageBox;`n", '')
Set-Content -Path $mainWindowPath -Value $mainWindowText -Encoding utf8

# CodeWalker TextureData is an object in the compatible ToolKitV dependency, not a byte array.
# Validate non-null payload without assuming a Length property.
$ytdOptimizerPath = Join-Path $SourceRoot 'DexClothingOptimizer/Services/YtdOptimizer.cs'
$ytdOptimizerText = Get-Content $ytdOptimizerPath -Raw
$ytdOptimizerText = $ytdOptimizerText.Replace(' || actualTexture.Data.Length == 0', '')
Set-Content -Path $ytdOptimizerPath -Value $ytdOptimizerText -Encoding utf8

$required = @(
    'DexClothingOptimizer/DexClothingOptimizer.csproj',
    'DexClothingOptimizer/MainWindow.xaml',
    'DexClothingOptimizer/MainWindow.xaml.cs',
    'DexClothingOptimizer/Services/TextureQualityAnalyzer.cs',
    'DexClothingOptimizer/Services/TexconvService.cs',
    'DexClothingOptimizer/Services/YtdOptimizer.cs'
)
foreach ($relative in $required) {
    if (-not (Test-Path (Join-Path $SourceRoot $relative))) {
        throw "Smart HQ override is missing required file: $relative"
    }
}

Write-Host "Smart HQ 75 source overrides applied and verified: $zipHash"
