param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Configuration = 'release',

    [string]$ApiBaseUrl
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    throw 'ApiBaseUrl is required. Pass the deployed HTTPS API URL with -ApiBaseUrl.'
}
$parsedApiBaseUrl = $null
if (
    -not [Uri]::TryCreate($ApiBaseUrl.TrimEnd('/'), [UriKind]::Absolute, [ref]$parsedApiBaseUrl) -or
    $parsedApiBaseUrl.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($parsedApiBaseUrl.Host) -or
    $parsedApiBaseUrl.AbsolutePath -ne '/' -or
    $parsedApiBaseUrl.UserInfo -or
    $parsedApiBaseUrl.Query -or
    $parsedApiBaseUrl.Fragment
) {
    throw 'ApiBaseUrl must be an HTTPS origin URL without a path, credentials, query, or fragment.'
}
$ApiBaseUrl = $parsedApiBaseUrl.AbsoluteUri.TrimEnd('/')

Push-Location $root
try {
    flutter build windows --$Configuration "--dart-define=API_BASE_URL=$ApiBaseUrl" @args
}
finally {
    Pop-Location
}
