[CmdletBinding()]
param(
    [string]$PackagePath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    $distributionDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'
    if (-not (Test-Path -LiteralPath $distributionDirectory -PathType Container)) {
        throw "Distribution directory was not found: $distributionDirectory"
    }

    $package = Get-ChildItem -LiteralPath $distributionDirectory `
        -Filter 'motchiy-todo-windows-*.msix' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $package) {
        throw "No Windows MSIX package was found in $distributionDirectory"
    }
    $PackagePath = $package.FullName
}

$resolvedPackage = Resolve-Path -LiteralPath $PackagePath
if ($resolvedPackage.Provider.Name -ne 'FileSystem' -or
    [IO.Path]::GetExtension($resolvedPackage.Path) -ne '.msix') {
    throw "PackagePath must point to an MSIX file: $PackagePath"
}

Write-Host "Installing $($resolvedPackage.Path) and closing Motchiy ToDo if it is running..."
Add-AppxPackage -Path $resolvedPackage.Path -ForceApplicationShutdown -ErrorAction Stop
Write-Host 'Installation completed.'
