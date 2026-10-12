$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

Push-Location $root
try {
    flutter run -d windows @args
}
finally {
    Pop-Location
}
