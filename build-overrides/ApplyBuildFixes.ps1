param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

Copy-Item "$PSScriptRoot/App.xaml.cs" (Join-Path $ProjectRoot 'App.xaml.cs') -Force
Copy-Item "$PSScriptRoot/TexturePolicy.cs" (Join-Path $ProjectRoot 'Services/TexturePolicy.cs') -Force
Copy-Item "$PSScriptRoot/GlobalUsings.cs" (Join-Path $ProjectRoot 'GlobalUsings.cs') -Force

$texconvPath = Join-Path $ProjectRoot 'Services/TexconvService.cs'
$texconv = Get-Content $texconvPath -Raw
$texconv = $texconv.Replace('Math.Max(1, source.Levels)', 'Math.Max(1, (int)source.Levels)')
Set-Content -Path $texconvPath -Value $texconv -Encoding utf8
