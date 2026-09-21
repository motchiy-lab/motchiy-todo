param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Configuration = 'release'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $root 'config\google_oauth.json'

if (-not (Test-Path $config)) {
    throw "Missing $config. Copy config\google_oauth.json.example and fill in the OAuth credentials."
}

Push-Location $root
try {
    flutter build windows --$Configuration --dart-define-from-file=config/google_oauth.json @args
}
finally {
    Pop-Location
}
