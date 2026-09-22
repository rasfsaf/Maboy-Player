[CmdletBinding()]
param(
    [ValidateSet("all", "windows", "android")]
    [string]$Platform = "all",

    [switch]$UpdateIcons = $true,

    [switch]$Clean = $false
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClientDir = Join-Path $ScriptDir "client"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Maboy Player - Build System             " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Locate Flutter executable
$FlutterCmd = $null
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    $FlutterCmd = "flutter"
} elseif (Test-Path "C:\src\flutter\bin\flutter.bat") {
    $FlutterCmd = "C:\src\flutter\bin\flutter.bat"
} else {
    Write-Error "Flutter SDK not found! Please ensure Flutter is installed at C:\src\flutter or in PATH."
    exit 1
}

Write-Host "[+] Using Flutter: $FlutterCmd" -ForegroundColor Green

# 2. Update icons if requested
if ($UpdateIcons) {
    Write-Host "`n[+] Generating application icons for Windows and Android..." -ForegroundColor Yellow
    $GeneratorScript = Join-Path $ClientDir "tool\generate_icons.py"
    if (Test-Path $GeneratorScript) {
        python $GeneratorScript
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Icon generation failed with code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    } else {
        Write-Error "Icon generator script not found at $GeneratorScript"
        exit 1
    }
}

# 3. Clean if requested
if ($Clean) {
    Write-Host "`n[+] Cleaning build cache..." -ForegroundColor Yellow
    Push-Location $ClientDir
    try {
        & $FlutterCmd clean
    } finally {
        Pop-Location
    }
}

# 4. Auto-bump version code in pubspec.yaml to prevent Android update conflicts
$PubspecPath = Join-Path $ClientDir "pubspec.yaml"
if (Test-Path $PubspecPath) {
    $PubspecContent = Get-Content $PubspecPath -Raw
    if ($PubspecContent -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
        $VersionName = $Matches[1]
        $NewVersionCode = [int]$Matches[2] + 1
        $NewVersion = "$VersionName+$NewVersionCode"
        $PubspecContent = $PubspecContent -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $NewVersion"
        Set-Content -Path $PubspecPath -Value $PubspecContent -NoNewline
        Write-Host "`n[+] Auto-bumped application version to $NewVersion (versionCode=$NewVersionCode)" -ForegroundColor Green
    }
}

# 5. Resolve dependencies
Write-Host "`n[+] Resolving Flutter dependencies..." -ForegroundColor Yellow
Push-Location $ClientDir
try {
    & $FlutterCmd pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Error "flutter pub get failed with code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}

# 5. Build Windows
if ($Platform -eq "all" -or $Platform -eq "windows") {
    Write-Host "`n[+] Building Windows Release (maboy.exe)..." -ForegroundColor Yellow
    # MSVC cannot replace an executable that is still running from the build
    # directory. Stop only Maboy instances whose resolved paths belong to this
    # workspace; never terminate an unrelated process by name alone.
    $WorkspacePath = [System.IO.Path]::GetFullPath($ScriptDir)
    $RunningWorkspaceMaboy = Get-Process -Name "maboy" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $ProcessPath = [System.IO.Path]::GetFullPath($_.Path)
            $ProcessPath.StartsWith($WorkspacePath, [System.StringComparison]::OrdinalIgnoreCase)
        } catch {
            $false
        }
    }
    if ($RunningWorkspaceMaboy) {
        Write-Host "[!] Closing Maboy instances from this workspace before linking..." -ForegroundColor Yellow
        $RunningWorkspaceMaboy | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }
    Push-Location $ClientDir
    try {
        & $FlutterCmd build windows --release
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Windows build failed with code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }

    $WinReleaseDir = Join-Path $ClientDir "build\windows\x64\runner\Release"
    $ExeSrc = Join-Path $WinReleaseDir "maboy.exe"
    if (Test-Path $ExeSrc) {
        Write-Host "[+] Deploying Windows binaries to project root..." -ForegroundColor Green
        $RunningProcesses = Get-Process -Name "maboy" -ErrorAction SilentlyContinue
        if ($RunningProcesses) {
            Write-Host "[!] Closing running maboy.exe instances to allow file replacement..." -ForegroundColor Yellow
            $RunningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
        Copy-Item -Path $ExeSrc -Destination (Join-Path $ScriptDir "maboy.exe") -Force
        Copy-Item -Path (Join-Path $WinReleaseDir "*.dll") -Destination $ScriptDir -Force -ErrorAction SilentlyContinue
        
        $DataSrc = Join-Path $WinReleaseDir "data"
        $DataDest = Join-Path $ScriptDir "data"
        if (Test-Path $DataSrc) {
            if (-not (Test-Path $DataDest)) {
                New-Item -ItemType Directory -Path $DataDest | Out-Null
            }
            Copy-Item -Path "$DataSrc\*" -Destination $DataDest -Recurse -Force
        }
        # Refresh Explorer icon cache if possible
        Start-Process -FilePath "ie4uinit.exe" -ArgumentList "-show" -ErrorAction SilentlyContinue
        Write-Host "[OK] Windows release updated: $(Join-Path $ScriptDir 'maboy.exe')" -ForegroundColor Green
    } else {
        Write-Error "Windows release executable not found at $ExeSrc"
        exit 1
    }
}

# 6. Build Android
if ($Platform -eq "all" -or $Platform -eq "android") {
    # Ensure libmpv.so binaries are present for Android
    Write-Host "`n[+] Ensuring libmpv.so binaries are present for Android..." -ForegroundColor Yellow
    $mpvAbis = @{
        "arm64-v8a"  = @{ url = "https://github.com/ales-drnz/mpv_audio_kit/releases/download/libmpv-r13/libmpv_android-arm64-v8a.so"; sha = "c96e671c6d4c96fe1be53e13606b8cd9aaac4088e70e7db7512ead3c7af0dc68" }
        "armeabi-v7a" = @{ url = "https://github.com/ales-drnz/mpv_audio_kit/releases/download/libmpv-r13/libmpv_android-armeabi-v7a.so"; sha = "569038adb078b1d9932f3cba6c03af30603a8fe7d9c9f7f8560b2eee5e64bf44" }
        "x86_64"     = @{ url = "https://github.com/ales-drnz/mpv_audio_kit/releases/download/libmpv-r13/libmpv_android-x86_64.so"; sha = "fceebe1b88003ee24b5c27d147e0f15750654a31c204de077e3f5ad564315803" }
    }
    $jniBase = Join-Path $ClientDir "android\app\src\main\jniLibs"
    $pubJniBase = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\mpv_audio_kit-0.4.6\android\src\main\jniLibs"
    foreach ($abi in $mpvAbis.Keys) {
        $abiDir = Join-Path $jniBase $abi
        if (-not (Test-Path $abiDir)) { New-Item -ItemType Directory -Path $abiDir -Force | Out-Null }
        $target = Join-Path $abiDir "libmpv.so"
        $info = $mpvAbis[$abi]
        $needDownload = $true
        if (Test-Path $target) {
            $hash = (Get-FileHash $target -Algorithm SHA256).Hash.ToLower()
            if ($hash -eq $info.sha) { $needDownload = $false }
        }
        if ($needDownload) {
            Write-Host "    Downloading libmpv.so for $abi..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $info.url -OutFile $target
            $hash = (Get-FileHash $target -Algorithm SHA256).Hash.ToLower()
            if ($hash -ne $info.sha) {
                Remove-Item $target -Force
                throw "Hash mismatch for $abi"
            }
        }
    }
    if (Test-Path (Split-Path -Parent $pubJniBase)) {
        Copy-Item -Path "$jniBase\*" -Destination $pubJniBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[OK] libmpv.so binaries verified for Android ABIs." -ForegroundColor Green

    Write-Host "`n[+] Building Android Release APK (maboy.apk)..." -ForegroundColor Yellow
    Push-Location $ClientDir
    try {
        & $FlutterCmd build apk --release
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Android build failed with code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }

    $ApkSrc = Join-Path $ClientDir "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $ApkSrc) {
        $ApkDest = Join-Path $ScriptDir "maboy.apk"
        Copy-Item -Path $ApkSrc -Destination $ApkDest -Force
        Write-Host "[OK] Android release APK updated: $ApkDest" -ForegroundColor Green
    } else {
        Write-Error "Android APK not found at $ApkSrc"
        exit 1
    }
}

# 7. Clean up intermediate build caches to protect disk space
Write-Host "`n[+] Cleaning intermediate build cache to protect disk space..." -ForegroundColor Yellow
$IntermediatesToClean = @(
    (Join-Path $ClientDir "build\app\intermediates"),
    (Join-Path $ClientDir "build\windows\x64\runner\intermediates"),
    (Join-Path $ClientDir "build\windows\x64\flutter\intermediates")
)
foreach ($dir in $IntermediatesToClean) {
    if (Test-Path $dir) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Get-ChildItem -Path $ScriptDir -Directory -Recurse -Filter "__pycache__" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $ScriptDir -File -Recurse -Include "*.pyc", "*.pyo" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "[OK] Intermediate cache cleared." -ForegroundColor Green

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host " Build Finished Successfully!           " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Get-ChildItem -Path $ScriptDir -File | Where-Object { $_.Name -in @("maboy.exe", "maboy.apk") } | Select-Object Name, Length, LastWriteTime
