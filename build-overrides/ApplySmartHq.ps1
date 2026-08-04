param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

$ErrorActionPreference = 'Stop'
$payloadPath = Join-Path $PSScriptRoot 'smart-hq-overrides.b64'
$zipPath = Join-Path $env:RUNNER_TEMP 'dex-smart-hq-overrides.zip'
$extractPath = Join-Path $env:RUNNER_TEMP 'dex-smart-hq-overrides'

$base64 = (Get-Content $payloadPath -Raw).Trim()
[IO.File]::WriteAllBytes($zipPath, [Convert]::FromBase64String($base64))
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
Copy-Item (Join-Path $extractPath '*') -Destination $SourceRoot -Recurse -Force

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

Write-Host 'Smart HQ 75 source overrides applied.'
