<#
.SYNOPSIS
    Builds Halo for Windows and packages it with Velopack: HaloSetup.exe, a portable zip and the
    update feed (releases.win.json + .nupkg) that the app's updater reads from GitHub Releases.

.DESCRIPTION
    1. dotnet publish: self-contained, so users don't need .NET installed.
    2. Optionally downloads the previous release from GitHub so Velopack can build delta updates.
    3. vpk pack: creates Setup.exe, the portable zip, the full (and delta) packages and the feed.
    4. Renames the installer to HaloSetup.exe.
    Output: windows/artifacts/releases (everything there is attached to the GitHub Release).

.EXAMPLE
    ./build/pack.ps1 -Version 1.2.0
.EXAMPLE
    ./build/pack.ps1 -Version 1.2.0 -PreviousReleasesFrom https://github.com/srinidhibhat45/Halo
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')]
    [string] $Version,

    [ValidateSet('win-x64', 'win-arm64')]
    [string] $Runtime = 'win-x64',

    [string] $Configuration = 'Release',

    # A GitHub repository URL; its latest release is downloaded first so delta updates can be made.
    # Uses $env:GITHUB_TOKEN when set (avoids API rate limits).
    [string] $PreviousReleasesFrom = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'src/Halo.App/Halo.App.csproj'
$icon = Join-Path $root 'src/Halo.App/Assets/Halo.ico'
$artifacts = Join-Path $root 'artifacts'
$publishDir = Join-Path $artifacts "publish-$Runtime"
$releaseDir = Join-Path $artifacts 'releases'
$toolDir = Join-Path $artifacts 'tools'

function Invoke-Checked([string] $what, [scriptblock] $command) {
    & $command
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)." }
}

# The vpk CLI must match the Velopack library the app references.
$velopackReference = ([xml](Get-Content $project)).SelectSingleNode("//PackageReference[@Include='Velopack']")
if (-not $velopackReference) { throw "Couldn't find the Velopack package version in $project." }
$velopackVersion = $velopackReference.GetAttribute('Version')

Remove-Item $publishDir, $releaseDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $releaseDir, $toolDir | Out-Null

Write-Host "Publishing Halo $Version ($Runtime, self-contained)…"
Invoke-Checked 'dotnet publish' {
    dotnet publish $project -c $Configuration -r $Runtime --self-contained true `
        -p:Version=$Version -p:DebugType=none -o $publishDir
}

Write-Host "Installing vpk $velopackVersion…"
$vpk = Join-Path $toolDir 'vpk.exe'
if (-not (Test-Path $vpk)) {
    Invoke-Checked 'Installing vpk' { dotnet tool install vpk --version $velopackVersion --tool-path $toolDir }
}

if ($PreviousReleasesFrom) {
    Write-Host 'Downloading the previous release for delta updates…'
    $download = @('download', 'github', '--repoUrl', $PreviousReleasesFrom, '--outputDir', $releaseDir)
    if ($env:GITHUB_TOKEN) { $download += @('--token', $env:GITHUB_TOKEN) }
    & $vpk @download
    # The first release has nothing to download; that is fine.
    if ($LASTEXITCODE -ne 0) { Write-Warning 'No previous release downloaded; packing without deltas.' }
}

Write-Host 'Packing with Velopack…'
Invoke-Checked 'vpk pack' {
    & $vpk pack `
        --packId Halo `
        --packVersion $Version `
        --packTitle Halo `
        --packAuthors Halo `
        --packDir $publishDir `
        --mainExe Halo.exe `
        --icon $icon `
        --runtime $Runtime `
        --outputDir $releaseDir
}

# One installer with a stable name, so releases/latest/download/HaloSetup.exe always works.
$setup = Get-ChildItem $releaseDir -Filter '*-Setup.exe' | Select-Object -First 1
if (-not $setup) { throw "vpk didn't produce a Setup.exe in $releaseDir." }
Move-Item $setup.FullName (Join-Path $releaseDir 'HaloSetup.exe') -Force

Write-Host "Done. Release files in ${releaseDir}:"
Get-ChildItem $releaseDir -File | ForEach-Object { Write-Host "  $($_.Name)" }
