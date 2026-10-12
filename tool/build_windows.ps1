param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Configuration = 'release'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

Push-Location $root
try {
    flutter build windows --$Configuration @args
}
finally {
    Pop-Location
}
