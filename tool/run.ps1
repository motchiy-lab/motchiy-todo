[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ApiBaseUrl,

    [ValidateSet('windows', 'android', 'linux', 'web')]
    [string[]]$Platforms
)

$ErrorActionPreference = 'Stop'

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $output = & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
    return $output
}

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot 'run.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Missing run configuration: $configPath"
}

try {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}
catch {
    throw "Could not parse run configuration at ${configPath}: $($_.Exception.Message)"
}

if ($null -eq $config.platforms -or $config.platforms -isnot [array]) {
    throw "The platforms property in $configPath must be a JSON array."
}

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    if ($config.apiBaseUrl -isnot [string]) {
        throw "The apiBaseUrl property in $configPath must be a string."
    }
    $ApiBaseUrl = $config.apiBaseUrl
}

$parsedApiBaseUrl = $null
if (
    -not [Uri]::TryCreate($ApiBaseUrl.TrimEnd('/'), [UriKind]::Absolute, [ref]$parsedApiBaseUrl) -or
    $parsedApiBaseUrl.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($parsedApiBaseUrl.Host) -or
    $parsedApiBaseUrl.UserInfo -or
    $parsedApiBaseUrl.Query -or
    $parsedApiBaseUrl.Fragment
) {
    throw 'ApiBaseUrl must be an HTTPS URL without credentials, query, or fragment.'
}
$ApiBaseUrl = $parsedApiBaseUrl.AbsoluteUri.TrimEnd('/')

$validPlatforms = @('windows', 'android', 'linux', 'web')
$platformsToRun = if ($Platforms) { $Platforms } else { $config.platforms }
$selectedPlatforms = @()
foreach ($platform in $platformsToRun) {
    if ($platform -isnot [string] -or [string]::IsNullOrWhiteSpace($platform)) {
        throw "Platform names in $configPath must be non-empty strings."
    }

    $normalizedPlatform = $platform.Trim().ToLowerInvariant()
    if ($normalizedPlatform -notin $validPlatforms) {
        throw "Unknown platform '$platform' in $configPath. Valid platforms: $($validPlatforms -join ', ')."
    }
    if ($normalizedPlatform -in $selectedPlatforms) {
        throw "Platform '$normalizedPlatform' is listed more than once in $configPath."
    }
    $selectedPlatforms += $normalizedPlatform
}
if ($selectedPlatforms.Count -eq 0) {
    throw "No platforms are selected in $configPath."
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw 'Flutter was not found on PATH.'
}

$devicesJson = Invoke-Tool $flutter.Source @('devices', '--machine')
try {
    $devices = @($devicesJson | ConvertFrom-Json)
}
catch {
    throw "Could not parse the device list from Flutter: $($_.Exception.Message)"
}

$devicePatterns = @{
    windows = '^windows-'
    android = '^android-'
    linux   = '^linux-'
    web     = '^web-'
}

$connectedPlatforms = @()
foreach ($platform in $selectedPlatforms) {
    $platformDevices = @(
        $devices | Where-Object {
            $_.isSupported -and $_.targetPlatform -match $devicePatterns[$platform]
        }
    )
    if ($platformDevices.Count -eq 0) {
        throw "No supported $platform device is connected. Connect one and run 'flutter devices' to check it."
    }
    $connectedPlatforms += $platform
}

Write-Host "Required platforms from run.json: $($connectedPlatforms -join ', ')"
Write-Host 'Flutter will also launch every other supported connected device.'
Write-Host 'Use q to stop, r to hot reload, and R to hot restart all running devices.'
Write-Host 'Connected devices:'
foreach ($device in $devices | Where-Object { $_.isSupported }) {
    Write-Host "  $($device.name) ($($device.targetPlatform), $($device.id))"
}
$dartDefine = "--dart-define=API_BASE_URL=$ApiBaseUrl"
if ($PSCmdlet.ShouldProcess('all supported connected devices', 'Run Flutter app')) {
    & $flutter.Source run --device-id all $dartDefine
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter run failed with exit code $LASTEXITCODE."
    }
}
