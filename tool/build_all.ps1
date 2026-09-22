[CmdletBinding()]
param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Configuration = 'release',

    [string]$OutputDirectory = 'dist',

    [string]$Version,

    [string]$CertificateThumbprint,

    [switch]$SkipMsixSigning,

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
    param(
        [string]$Override
    )

    if ($Override) {
        if ($Override -notmatch '^(?<name>\d+\.\d+\.\d+)(?:\+(?<number>\d+))?$') {
            throw "Version must use semantic version format, for example 1.2.3 or 1.2.3+4: $Override"
        }

        $name = $Matches['name']
        $number = if ($Matches['number']) { [int]$Matches['number'] } else { 0 }
        return @{
            Name = $name
            Number = $number
            Package = "$name.$number"
        }
    }

    $versionLine = Get-Content (Join-Path $root 'pubspec.yaml') |
        Where-Object { $_ -match '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$' } |
        Select-Object -First 1

    if (-not $versionLine -or $versionLine -notmatch '([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?') {
        throw 'Could not read a valid version from pubspec.yaml.'
    }

    $version = $Matches[1]
    $build = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
    return @{
        Name = $version
        Number = $build
        Package = "$version.$build"
    }
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

function Get-SignTool {
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $candidate = Get-ChildItem $kitsRoot -Filter signtool.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    throw 'signtool.exe was not found. Install the Windows 10/11 SDK to sign the MSIX package.'
}

function Get-MsixCertificate {
    param(
        [string]$Thumbprint
    )

    $certificate = if ($Thumbprint) {
        Get-ChildItem "Cert:\CurrentUser\My\$($Thumbprint.Replace(' ', ''))" -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -eq 'CN=Motchiy' -and $_.HasPrivateKey } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
    }

    if ($certificate -and $certificate.Subject -eq 'CN=Motchiy' -and $certificate.HasPrivateKey) {
        return $certificate
    }

    if ($Thumbprint) {
        throw "Signing certificate was not found in Cert:\CurrentUser\My or has no private key: $Thumbprint"
    }

    Write-Host 'Creating a development MSIX signing certificate in the current user certificate store...'
    $certificate = New-SelfSignedCertificate `
        -Type Custom `
        -Subject 'CN=Motchiy' `
        -KeyUsage DigitalSignature `
        -FriendlyName 'Motchiy Todo MSIX' `
        -CertStoreLocation 'Cert:\CurrentUser\My'

    $temporaryCertificate = Join-Path $env:TEMP "motchiy-todo-$($certificate.Thumbprint).cer"
    try {
        Export-Certificate -Cert $certificate -FilePath $temporaryCertificate -Force | Out-Null
        & certutil.exe -user -addstore Root $temporaryCertificate | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Could not trust the generated signing certificate: certutil.exe exited with $LASTEXITCODE."
        }
    }
    finally {
        if (Test-Path $temporaryCertificate) {
            Remove-Item $temporaryCertificate -Force
        }
    }

    return $certificate
}

function Invoke-MsixSigning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MsixPath,
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $signTool = Get-SignTool
    Invoke-Tool $signTool @(
        'sign', '/fd', 'SHA256', '/sha1', $Certificate.Thumbprint,
        '/tr', 'http://timestamp.digicert.com', '/td', 'SHA256', $MsixPath
    )
    Invoke-Tool $signTool @('verify', '/pa', '/v', $MsixPath)

    Export-Certificate -Cert $Certificate -FilePath (Join-Path $OutputDirectory 'motchiy-todo-publisher.cer') -Force | Out-Null
    Write-Host "MSIX signed with certificate $($Certificate.Thumbprint)."
    Write-Host 'Trust motchiy-todo-publisher.cer on each installation machine before installing the MSIX.'
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
        $graphics.DrawIcon($icon, (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)))
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

        $windowsPath = [IO.Path]::GetFullPath($root)
        if ($windowsPath -notmatch '^([A-Za-z]):\\(.+)$') {
            throw "Could not translate the repository path for WSL: $windowsPath"
        }

        $wslRoot = "/mnt/$($Matches[1].ToLower())/$($Matches[2] -replace '\\', '/')"
        $wslConfig = "$wslRoot/config/google_oauth.json"
        $escapedRoot = $wslRoot.Replace("'", "'\''")
        $escapedConfig = $wslConfig.Replace("'", "'\''")
        $linuxFlutter = '/home/motchiy/development/flutter/bin/flutter'
        Invoke-Tool $wsl.Source @('bash', '-lc', "test -x '$linuxFlutter' || { echo 'WSL Flutter was not found at $linuxFlutter. Install Flutter in WSL.' >&2; exit 1; }; cd '$escapedRoot' && '$linuxFlutter' pub get")
        $flutterCommand = "cd '$escapedRoot' && '$linuxFlutter' build linux --$Configuration --build-name='$buildVersion.Name' --build-number='$buildVersion.Number' --dart-define-from-file='$escapedConfig'"
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

function Invoke-FlutterPubGet {
    Invoke-Tool 'flutter' @('pub', 'get')
}

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config\google_oauth.json'
$outputPath = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
$buildVersion = Get-Version $Version

if (-not (Test-Path $configPath)) {
    throw "Missing $configPath. Copy config\google_oauth.json.example and fill in the OAuth credentials."
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
Get-ChildItem $outputPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

Push-Location $root
try {
    $flutterDefine = "--dart-define-from-file=config/google_oauth.json"

    Write-Host 'Building Windows bundle...'
    Invoke-FlutterPubGet
    $flutterVersionArgs = @('--build-name', $buildVersion.Name, '--build-number', "$($buildVersion.Number)")
    $windowsArgs = @('build', 'windows', "--$Configuration") + $flutterVersionArgs + @($flutterDefine) + $FlutterArgs
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
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         IgnorableNamespaces="uap">
  <Identity Name="motchiy.todo" Publisher="CN=Motchiy" Version="$($buildVersion.Package)" />
  <Properties>
    <DisplayName>Motchiy ToDo</DisplayName>
    <PublisherDisplayName>Motchiy</PublisherDisplayName>
    <Description>Motchiy ToDo</Description>
    <Logo>logo-150.png</Logo>
  </Properties>
  <Resources><Resource Language="ja-jp" /></Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Applications>
    <Application Id="MotchiyToDo" Executable="motchiy_todo.exe">
      <uap:VisualElements AppListEntry="none" DisplayName="Motchiy ToDo" Description="Motchiy ToDo" BackgroundColor="#FFFFFF" Square150x150Logo="logo-150.png" Square44x44Logo="logo-44.png" />
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="internetClient" />
  </Capabilities>
</Package>
"@ | Set-Content (Join-Path $msixStaging 'AppxManifest.xml') -Encoding UTF8

        $makeAppx = Get-MakeAppx
        $msixPath = Join-Path $outputPath "motchiy-todo-windows-$($buildVersion.Package).msix"
        Invoke-Tool $makeAppx @('pack', '/d', $msixStaging, '/p', $msixPath, '/o')

        if (-not $SkipMsixSigning) {
            $certificate = Get-MsixCertificate $CertificateThumbprint
            Invoke-MsixSigning $msixPath $certificate $outputPath
        }
    }
    finally {
        if (Test-Path $msixStaging) {
            Remove-Item $msixStaging -Recurse -Force
        }
    }

    Write-Host 'Building Android APK...'
    Invoke-FlutterPubGet
    Invoke-Tool 'flutter' (@('build', 'apk', "--$Configuration") + $flutterVersionArgs + @($flutterDefine) + $FlutterArgs)
    $apk = Join-Path $root "build\app\outputs\flutter-apk\app-$Configuration.apk"
    if (-not (Test-Path $apk)) {
        throw "APK was not found: $apk"
    }
    Copy-Item $apk (Join-Path $outputPath "motchiy-todo-android-$($buildVersion.Package).apk") -Force

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
            $tarPath = Join-Path $outputPath "motchiy-todo-linux-$($buildVersion.Package).tar.gz"
            Invoke-Tool 'tar.exe' @('-czf', $tarPath, '-C', $linuxStaging, 'motchiy_todo', 'data')
        }
        finally {
            if (Test-Path $linuxStaging) {
                Remove-Item $linuxStaging -Recurse -Force
            }
        }
    }

    Write-Host 'Building web bundle...'
    Invoke-FlutterPubGet
    Invoke-Tool 'flutter' (@('build', 'web', "--$Configuration") + $flutterVersionArgs + @($flutterDefine) + $FlutterArgs)
    $webBundle = Join-Path $root 'build\web'
    if (-not (Test-Path $webBundle)) {
        throw "Web bundle was not found: $webBundle"
    }
    Compress-Archive -Path (Join-Path $webBundle '*') -DestinationPath (Join-Path $outputPath "motchiy-todo-web-$($buildVersion.Package).zip") -Force

    Write-Host "Build completed: $outputPath"
}
finally {
    Pop-Location
}
