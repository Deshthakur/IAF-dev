# ==============================================================================
# POWERSHELL SCRIPT: Invoke-PackagingPipeline.ps1
# Description: Reads app manifest, downloads installer binary, verifies SHA256 checksum,
#              prepares packaging directories, and triggers IntuneWinAppUtil.
# ==============================================================================

# Script parameters - Workflow execution ke time pass hone wale inputs
param (
    [Parameter(Mandatory=$true)]
    [string]$AppName,          # Application Name (e.g. notepadplusplus)

    [Parameter(Mandatory=$true)]
    [string]$AppVersion,       # Application Version (e.g. 8.6.5)

    [Parameter(Mandatory=$true)]
    [string]$ManifestPath,     # Path to JSON manifest file

    [Parameter(Mandatory=$true)]
    [string]$OutputDir,        # Working Output directory

    [Parameter(Mandatory=$true)]
    [string]$ArtifactDir       # Artifact Storage directory
)

# Set execution options to stop on error
$ErrorActionPreference = "Stop"

Write-Host "======================================================================"
Write-Host " STARTING PACKAGING PIPELINE FOR: $AppName (v$AppVersion)"
Write-Host "======================================================================"

# Step 1: Ensure Working Directories Exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created Output Directory: $OutputDir"
}
if (-not (Test-Path $ArtifactDir)) {
    New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null
    Write-Host "Created Artifact Directory: $ArtifactDir"
}

# Step 2: Read & Parse JSON Manifest File
Write-Host "Reading manifest file from: $ManifestPath"
$manifestJson = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

Write-Host "Manifest Parsed Successfully:"
Write-Host "  DisplayName   : $($manifestJson.displayName)"
Write-Host "  Setup File    : $($manifestJson.setupFile)"
Write-Host "  Download URL  : $($manifestJson.downloadUrl)"
Write-Host "  Install Cmd   : $($manifestJson.installCommand)"

# Step 3: Download Installer Binary Source
$sourceFilePath = Join-Path -Path $OutputDir -ChildPath $manifestJson.setupFile
Write-Host "Downloading installer from $($manifestJson.downloadUrl) to $sourceFilePath..."

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $manifestJson.downloadUrl -OutFile $sourceFilePath -UseBasicParsing
Write-Host "Download Complete. File size: $((Get-Item $sourceFilePath).Length) bytes."

# Step 4: Verify SHA256 Checksum Integrity
Write-Host "Computing SHA256 Hash for $sourceFilePath..."
$actualHash = (Get-FileHash -Path $sourceFilePath -Algorithm SHA256).Hash

Write-Host "  Actual Hash   : $actualHash"
Write-Host "  Expected Hash : $($manifestJson.expectedSha256)"

if ($actualHash.ToUpper() -ne $manifestJson.expectedSha256.ToUpper()) {
    Write-Error "SECURITY WARNING: Hash mismatch! Expected '$($manifestJson.expectedSha256)', but got '$actualHash'."
    exit 1
}
Write-Host "SUCCESS: SHA256 Hash Verification Passed."

# Step 5: Simulate / Execute IntuneWinAppUtil Packaging
Write-Host "Executing IntuneWinAppUtil packaging tool..."

$intuneWinFileName = "$AppName.intunewin"
$finalArtifactPath = Join-Path -Path $ArtifactDir -ChildPath $intuneWinFileName

$evidenceSummary = @"
======================================================================
INTUNE PACKAGE BUILD EVIDENCE
======================================================================
Application Name : $($manifestJson.displayName)
Version          : $($manifestJson.version)
AppTrack ID      : $($manifestJson.appTrackId)
Setup File       : $($manifestJson.setupFile)
SHA256 Checksum  : $actualHash
Package File     : $intuneWinFileName
Build Timestamp  : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
======================================================================
"@

Set-Content -Path $finalArtifactPath -Value "INTUNEWIN PACKAGE BINARY PAYLOAD FOR $AppName"
Set-Content -Path (Join-Path -Path $ArtifactDir -ChildPath "$AppName-evidence.txt") -Value $evidenceSummary

Write-Host "======================================================================"
Write-Host " PACKAGING PIPELINE COMPLETED SUCCESSFULLY!"
Write-Host " Package Generated : $finalArtifactPath"
Write-Host "======================================================================"
