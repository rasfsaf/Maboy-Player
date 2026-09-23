# Packages a portable Windows player: maboy.exe, its DLLs, and Flutter data.
# No source tree, agent files, cookies, or local account data.
[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$ReleaseDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $ProjectRoot "client\build\windows\x64\runner\Release"
}
if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    throw "Windows release directory not found: $ReleaseDir"
}

$exe = Join-Path $ReleaseDir "maboy.exe"
if (-not (Test-Path -LiteralPath $exe)) {
    throw "maboy.exe not found in $ReleaseDir"
}

Push-Location $ProjectRoot
try {
    $describe = (git describe --tags --always --dirty 2>$null)
    if (-not $describe) { $describe = Get-Date -Format "yyyyMMdd-HHmmss" }
} finally {
    Pop-Location
}
$stamp = ($describe -replace '[^A-Za-z0-9._-]', '-')
$when = Get-Date -Format "yyyyMMdd-HHmmss"
$zipPath = Join-Path $ProjectRoot "maboy.zip"
$pendingZip = Join-Path $ProjectRoot "maboy-pending-$([System.Guid]::NewGuid().ToString('N')).zip"
$backupZip = Join-Path $ProjectRoot "maboy-backup-$([System.Guid]::NewGuid().ToString('N')).zip"

$stageRoot = Join-Path $env:TEMP "maboy-portable-$stamp-$when"
$stage = Join-Path $stageRoot "maboy"
if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Copy-Item -LiteralPath $exe -Destination (Join-Path $stage "maboy.exe") -Force
Get-ChildItem -LiteralPath $ReleaseDir -File | Where-Object {
    $_.Extension -in @(".dll", ".json")
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stage $_.Name) -Force
}

$dataSrc = Join-Path $ReleaseDir "data"
if (-not (Test-Path -LiteralPath $dataSrc)) {
    Remove-Item $stageRoot -Recurse -Force
    throw "Flutter data directory not found: $dataSrc"
}
Copy-Item -LiteralPath $dataSrc -Destination (Join-Path $stage "data") -Recurse -Force

$junk = @(Get-ChildItem -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(cookies\.txt|\.env|AGENTS\.md|key\.properties)$' -or
    $_.Name -match '^\.(claude|agents|git)' -or
    $_.Extension -in @(".jks", ".keystore", ".pem", ".p12", ".pdb", ".lib", ".exp", ".db", ".md")
})
foreach ($item in $junk) {
    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

$left = @(Get-ChildItem -LiteralPath $stage -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(cookies\.txt|AGENTS\.md)$' -or $_.Extension -eq ".db"
})
if ($left.Count -gt 0) {
    Remove-Item $stageRoot -Recurse -Force
    throw "Refusing to share portable zip: personal or junk files remain"
}

try {
    Compress-Archive -Path $stage -DestinationPath $pendingZip -CompressionLevel Optimal -ErrorAction Stop
    if (Test-Path -LiteralPath $zipPath) {
        [System.IO.File]::Replace($pendingZip, $zipPath, $backupZip)
    } else {
        [System.IO.File]::Move($pendingZip, $zipPath)
    }
} finally {
    if (Test-Path -LiteralPath $pendingZip) { Remove-Item -LiteralPath $pendingZip -Force }
    if (Test-Path -LiteralPath $backupZip) { Remove-Item -LiteralPath $backupZip -Force }
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
}

$zip = Get-Item -LiteralPath $zipPath
# Remove legacy versioned portable archives only after maboy.zip exists.
Get-ChildItem -LiteralPath $ProjectRoot -File -Filter "maboy-portable-*.zip" |
    Where-Object { -not [string]::Equals($_.FullName, $zip.FullName, [System.StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
        Write-Host "[+] Removed old portable zip: $($_.Name)"
    }

Get-ChildItem -LiteralPath $ProjectRoot -File -Filter "maboy-src-*.zip" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Output $zip.FullName
Write-Host "[OK] Portable player zip: $($zip.FullName) ($([math]::Round($zip.Length / 1MB, 2)) MB)"
