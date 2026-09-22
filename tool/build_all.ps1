[CmdletBinding()]
param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Configuration = 'release',

    [string]$OutputDirectory = 'dist',

    [switch]$SkipLinux,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Get-Version {
    $versionLine = Get-Content (Join-Path $root 'pubspec.yaml') |
        Where-Object { $_ -match '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$' } |
        Select-Object -First 1

    if (-not $versionLine -or $versionLine -notmatch '([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?') {
        throw 'Could not read a valid version from pubspec.yaml.'
    }

    $version = $Matches[1]
    $build = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
    return "$version.$build"
}

function Get-MakeAppx {
    $command = Get-Command makeappx.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $candidate = Get-ChildItem $kitsRoot -Filter makeappx.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    throw 'makeappx.exe was not found. Install the Windows 10/11 SDK to create the MSIX package.'
}

function New-MsixLogo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IconPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [int]$Size
    )

    Add-Type -AssemblyName System.Drawing
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($IconPath)
    if (-not $icon) {
        throw "Could not load the Windows application icon: $IconPath"
    }

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.DrawIcon($icon, 0, 0, $Size, $Size)
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $icon.Dispose()
    }
}

function Invoke-LinuxBuild {
    $linuxArgs = @('build', 'linux', "--$Configuration", "--dart-define-from-file=$configPath")
    if ($FlutterArgs) {
        $linuxArgs += $FlutterArgs
    }

    if ($env:OS -eq 'Windows_NT') {
        $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wsl) {
            throw 'Linux build requires WSL on Windows. Install WSL with a Flutter/Linux toolchain, or run this script on Linux.'
        }

        $wslRoot = (& $wsl.Source wslpath -a $root).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslRoot)) {
            throw 'Could not translate the repository path for WSL.'
        }

        $wslConfig = (& $wsl.Source wslpath -a $configPath).Trim()
        $escapedRoot = $wslRoot.Replace("'", "'\''")
        $escapedConfig = $wslConfig.Replace("'", "'\''")
        $flutterCommand = "cd '$escapedRoot' && flutter build linux --$Configuration --dart-define-from-file='$escapedConfig'"
        if ($FlutterArgs) {
            $flutterCommand += ' ' + (($FlutterArgs | ForEach-Object {
                "'" + $_.Replace("'", "'\''") + "'"
            }) -join ' ')
        }

        Invoke-Tool $wsl.Source @('bash', '-lc', $flutterCommand)
        return
    }

    Invoke-Tool 'flutter' $linuxArgs
}

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config\google_oauth.json'
$outputPath = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
$version = Get-Version

if (-not (Test-Path $configPath)) {
    throw "Missing $configPath. Copy config\google_oauth.json.example and fill in the OAuth credentials."
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
Get-ChildItem $outputPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

Push-Location $root
try {
    $flutterDefine = "--dart-define-from-file=config/google_oauth.json"

    Write-Host 'Building Windows bundle...'
    $windowsArgs = @('build', 'windows', "--$Configuration", $flutterDefine) + $FlutterArgs
    Invoke-Tool 'flutter' $windowsArgs

    $windowsBundle = Join-Path $root "build\windows\x64\runner\$($Configuration.Substring(0, 1).ToUpper() + $Configuration.Substring(1))"
    if (-not (Test-Path $windowsBundle)) {
        throw "Windows bundle was not found: $windowsBundle"
    }

    Write-Host 'Creating MSIX...'
    $msixStaging = Join-Path $env:TEMP "motchiy-todo-msix-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $msixStaging -Force | Out-Null
    try {
        Copy-Item (Join-Path $windowsBundle '*') $msixStaging -Recurse -Force
        $logo = Join-Path $root 'windows\runner\resources\app_icon.ico'
        New-MsixLogo $logo (Join-Path $msixStaging 'logo-150.png') 150
        New-MsixLogo $logo (Join-Path $msixStaging 'logo-44.png') 44
        @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10">
  <Identity Name="motchiy.todo" Publisher="CN=Motchiy" Version="$version" />
  <Properties>
    <DisplayName>Motchiy ToDo</DisplayName>
    <PublisherDisplayName>Motchiy</PublisherDisplayName>
    <Description>Motchiy ToDo</Description>
    <Logo>logo-150.png</Logo>
  </Properties>
  <Resources><Resource Language="ja-jp" /></Resources>
  <Applications>
    <Application Id="MotchiyToDo" Executable="motchiy_todo.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements AppListEntry="none" DisplayName="Motchiy ToDo" Description="Motchiy ToDo" Square150x150Logo="logo-150.png" Square44x44Logo="logo-44.png" />
    </Application>
  </Applications>
  <Capabilities><Capability Name="internetClient" /></Capabilities>
</Package>
"@ | Set-Content (Join-Path $msixStaging 'AppxManifest.xml') -Encoding UTF8

        $makeAppx = Get-MakeAppx
        $msixPath = Join-Path $outputPath "motchiy-todo-windows-$version.msix"
        Invoke-Tool $makeAppx @('pack', '/d', $msixStaging, '/p', $msixPath, '/o')
    }
    finally {
        if (Test-Path $msixStaging) {
            Remove-Item $msixStaging -Recurse -Force
        }
    }

    Write-Host 'Building Android APK...'
    Invoke-Tool 'flutter' (@('build', 'apk', "--$Configuration", $flutterDefine) + $FlutterArgs)
    $apk = Join-Path $root "build\app\outputs\flutter-apk\app-$Configuration.apk"
    if (-not (Test-Path $apk)) {
        throw "APK was not found: $apk"
    }
    Copy-Item $apk (Join-Path $outputPath "motchiy-todo-android-$version.apk") -Force

    if (-not $SkipLinux) {
        Write-Host 'Building Linux bundle...'
        Invoke-LinuxBuild
        $linuxConfiguration = $Configuration.Substring(0, 1).ToLower() + $Configuration.Substring(1)
        $linuxBundle = Join-Path $root "build\linux\x64\$linuxConfiguration\bundle"
        if (-not (Test-Path $linuxBundle)) {
            throw "Linux bundle was not found: $linuxBundle"
        }

        $linuxStaging = Join-Path $env:TEMP "motchiy-todo-linux-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $linuxStaging -Force | Out-Null
        try {
            Copy-Item (Join-Path $linuxBundle '*') $linuxStaging -Recurse -Force
            $tarPath = Join-Path $outputPath "motchiy-todo-linux-$version.tar.gz"
            Invoke-Tool 'tar.exe' @('-czf', $tarPath, '-C', $linuxStaging, 'motchiy_todo', 'data')
        }
        finally {
            if (Test-Path $linuxStaging) {
                Remove-Item $linuxStaging -Recurse -Force
            }
        }
    }

    Write-Host 'Building web bundle...'
    Invoke-Tool 'flutter' (@('build', 'web', "--$Configuration", $flutterDefine) + $FlutterArgs)
    $webBundle = Join-Path $root 'build\web'
    if (-not (Test-Path $webBundle)) {
        throw "Web bundle was not found: $webBundle"
    }
    Compress-Archive -Path (Join-Path $webBundle '*') -DestinationPath (Join-Path $outputPath "motchiy-todo-web-$version.zip") -Force

    Write-Host "Build completed: $outputPath"
}
finally {
    Pop-Location
}
