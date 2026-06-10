param(
    [Parameter(Mandatory = $true)]
    [string]$PythonVersion,

    [string]$VcpkgRoot = $env:VCPKG_ROOT,
    [string]$CMakeExe = "",
    [string]$SwigExe = "",
    [string]$Generator = "",
    [string]$Architecture = "x64",
    [string]$Triplet = "x64-windows",
    [string]$BuildRoot = "",
    [switch]$SkipPythonDependencyInstall,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-ProcessPathEnvironment {
    $pathValue = $env:Path
    [Environment]::SetEnvironmentVariable("PATH", $null, "Process")
    [Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
    $env:Path = $pathValue
}

function Resolve-ToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$ExplicitPath,
        [string[]]$FallbackPaths = @()
    )

    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $ExplicitPath).Path
        }
        throw "$Name was specified but does not exist: $ExplicitPath"
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($candidate in $FallbackPaths) {
        $matches = @(Get-ChildItem -Path $candidate -ErrorAction SilentlyContinue | Sort-Object FullName)
        if ($matches.Count -gt 0) {
            return $matches[0].FullName
        }
    }

    throw "$Name was not found on PATH or in common install locations."
}

function Resolve-VcpkgRoot {
    param([string]$ExplicitRoot)

    $roots = @()
    if ($ExplicitRoot) {
        $roots += $ExplicitRoot
    }
    if ($env:VCPKG_ROOT) {
        $roots += $env:VCPKG_ROOT
    }
    $roots += @(
        "C:\vcpkg",
        (Join-Path $env:USERPROFILE "vcpkg"),
        (Join-Path $env:USERPROFILE "src\vcpkg"),
        (Join-Path $env:LOCALAPPDATA "vcpkg"),
        "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\vcpkg",
        "C:\Program Files\Microsoft Visual Studio\18\BuildTools\VC\vcpkg",
        "C:\Program Files (x86)\Microsoft Visual Studio\17\BuildTools\VC\vcpkg",
        "C:\Program Files\Microsoft Visual Studio\17\BuildTools\VC\vcpkg"
    )

    foreach ($root in $roots) {
        if (-not $root) {
            continue
        }
        $toolchain = Join-Path $root "scripts\buildsystems\vcpkg.cmake"
        if (Test-Path -LiteralPath $toolchain -PathType Leaf) {
            return (Resolve-Path -LiteralPath $root).Path
        }
    }

    throw "vcpkg root was not found. Install vcpkg or pass -VcpkgRoot pointing at a checkout with scripts\buildsystems\vcpkg.cmake."
}

function Resolve-CMakeGenerator {
    param(
        [Parameter(Mandatory = $true)][string]$CMake,
        [string]$RequestedGenerator
    )

    if ($RequestedGenerator) {
        return $RequestedGenerator
    }

    $help = & $CMake --help
    if ($LASTEXITCODE -ne 0) {
        throw "failed to query CMake generators"
    }

    foreach ($candidate in @("Visual Studio 18 2026", "Visual Studio 17 2022")) {
        if ($help -match [regex]::Escape($candidate)) {
            return $candidate
        }
    }

    throw "CMake does not list a supported Visual Studio generator."
}

function Test-OpenBlasInstalled {
    param([Parameter(Mandatory = $true)][string]$InstalledDir)

    if (-not (Test-Path -LiteralPath $InstalledDir -PathType Container)) {
        return $false
    }

    $files = @(Get-ChildItem -LiteralPath $InstalledDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "openblas|blas|lapack" })
    return $files.Count -gt 0
}

function Resolve-PyenvPython {
    param([Parameter(Mandatory = $true)][string]$Version)

    $python = Join-Path $env:USERPROFILE ".pyenv\pyenv-win\versions\$Version\python.exe"
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw "missing pyenv Python: $python"
    }
    return (Resolve-Path -LiteralPath $python).Path
}

function Invoke-LoggedNative {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [switch]$Append
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($Append) {
            & $Exe @Arguments 2>&1 | Tee-Object -FilePath $LogPath -Append
        } else {
            & $Exe @Arguments 2>&1 | Tee-Object -FilePath $LogPath
        }
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "command failed with exit code ${LASTEXITCODE}: $Exe $($Arguments -join ' ')"
    }
}

function Remove-BuildChild {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $resolvedParent = (Resolve-Path -LiteralPath $Parent).Path
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    if (-not $resolvedPath.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing to remove path outside build tree: $resolvedPath"
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

Normalize-ProcessPathEnvironment

$work = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$root = (Resolve-Path -LiteralPath (Join-Path $work "..")).Path
$src = Join-Path $root "conann-main\conann"
$buildRoot = if ($BuildRoot) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BuildRoot)
} else {
    Join-Path $work "build"
}
$build = Join-Path $buildRoot "win-py$PythonVersion"
$wheelDir = Join-Path $work "wheels\win_amd64"
$logDir = Join-Path $work "logs"
$pythonExe = Resolve-PyenvPython -Version $PythonVersion
$cmake = Resolve-ToolPath -Name "cmake" -ExplicitPath $CMakeExe -FallbackPaths @(
    "C:\Program Files\CMake\bin\cmake.exe",
    "C:\Program Files (x86)\CMake\bin\cmake.exe"
)
$swig = Resolve-ToolPath -Name "swig" -ExplicitPath $SwigExe -FallbackPaths @(
    "C:\Program Files\swigwin-*\swig.exe",
    "C:\swigwin-*\swig.exe",
    (Join-Path $env:USERPROFILE "scoop\apps\swig\current\swig.exe")
)
$resolvedVcpkgRoot = Resolve-VcpkgRoot -ExplicitRoot $VcpkgRoot
$toolchain = Join-Path $resolvedVcpkgRoot "scripts\buildsystems\vcpkg.cmake"
$generatorToUse = Resolve-CMakeGenerator -CMake $cmake -RequestedGenerator $Generator
$classicVcpkgInstalled = Join-Path $resolvedVcpkgRoot "installed\$Triplet"
$manifestDir = Join-Path $work "vcpkg"
$manifestVcpkgRoot = Join-Path $work "build\vcpkg_installed"
$manifestVcpkgInstalled = Join-Path $manifestVcpkgRoot $Triplet
$vcpkgLocalAppData = Join-Path $work "build\vcpkg_localappdata"
$vcpkgDownloads = Join-Path $work "build\vcpkg_downloads"
$vcpkgBuildtrees = Join-Path $work "build\vcpkg_buildtrees"
$vcpkgPackages = Join-Path $work "build\vcpkg_packages"
$useManifestVcpkg = -not (Test-OpenBlasInstalled -InstalledDir $classicVcpkgInstalled)
$manifestVcpkgReady = Test-OpenBlasInstalled -InstalledDir $manifestVcpkgInstalled

if ($useManifestVcpkg -and -not (Test-Path -LiteralPath (Join-Path $manifestDir "vcpkg.json") -PathType Leaf)) {
    throw "missing vcpkg manifest: $(Join-Path $manifestDir 'vcpkg.json')"
}

if ($Clean -and (Test-Path -LiteralPath $build)) {
    Remove-BuildChild -Path $build -Parent $buildRoot
}

New-Item -ItemType Directory -Force -Path $buildRoot, $build, $wheelDir, $logDir | Out-Null

$pyTag = (& $pythonExe -c "import sys; print(f'cp{sys.version_info.major}{sys.version_info.minor}')").Trim()
if ($LASTEXITCODE -ne 0) {
    throw "failed to compute CPython tag with $pythonExe"
}

Write-Host "== Python $PythonVersion ($pyTag) =="
Write-Host "Python: $pythonExe"
Write-Host "CMake:  $cmake"
Write-Host "SWIG:   $swig"
Write-Host "vcpkg:  $resolvedVcpkgRoot"
Write-Host "CMake generator: $generatorToUse"
if ($useManifestVcpkg) {
    Write-Host "vcpkg mode: manifest ($manifestDir)"
} else {
    Write-Host "vcpkg mode: classic ($classicVcpkgInstalled)"
}

if (-not $SkipPythonDependencyInstall) {
    $depLog = Join-Path $logDir "python-deps-win-py$PythonVersion.log"
    Invoke-LoggedNative -Exe $pythonExe -Arguments @("-m", "ensurepip", "--upgrade") -LogPath $depLog
    Invoke-LoggedNative -Exe $pythonExe -Arguments @("-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel", "packaging", "numpy") -LogPath $depLog -Append
}

$configureLog = Join-Path $logDir "configure-win-py$PythonVersion.log"
$cmakeArgs = @(
    "-S", $src,
    "-B", $build,
    "-G", $generatorToUse,
    "-A", $Architecture,
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
    "-DVCPKG_TARGET_TRIPLET=$Triplet",
    "-DBLA_VENDOR=OpenBLAS",
    "-DFAISS_ENABLE_GPU=OFF",
    "-DFAISS_ENABLE_PYTHON=ON",
    "-DFAISS_ENABLE_C_API=OFF",
    "-DFAISS_ENABLE_RAFT=OFF",
    "-DCONANN_ENABLE_EXTRAS=OFF",
    "-DBUILD_TESTING=OFF",
    "-DFAISS_OPT_LEVEL=avx2",
    "-DPython_EXECUTABLE=$pythonExe",
    "-DPython3_EXECUTABLE=$pythonExe",
    "-DPython_FIND_STRATEGY=LOCATION",
    "-DSWIG_EXECUTABLE=$swig"
)
if ($useManifestVcpkg) {
    $openblasReleaseLib = Join-Path $manifestVcpkgInstalled "lib\openblas.lib"
    $lapackReleaseLib = Join-Path $manifestVcpkgInstalled "lib\lapack.lib"
    $cmakeArgs += @(
        "-DVCPKG_INSTALLED_DIR=$manifestVcpkgRoot",
        "-DBLAS_LIBRARIES=$openblasReleaseLib",
        "-DLAPACK_LIBRARIES=$lapackReleaseLib"
    )
    if (-not $manifestVcpkgReady) {
        $cmakeArgs += @(
            "-DVCPKG_MANIFEST_MODE=ON",
            "-DVCPKG_MANIFEST_DIR=$manifestDir",
            "-DVCPKG_MANIFEST_INSTALL=ON",
            "-DVCPKG_INSTALL_OPTIONS=--downloads-root=$vcpkgDownloads;--x-buildtrees-root=$vcpkgBuildtrees;--x-packages-root=$vcpkgPackages"
        )
    }
} else {
    $openblasReleaseLib = Join-Path $classicVcpkgInstalled "lib\openblas.lib"
    $lapackReleaseLib = Join-Path $classicVcpkgInstalled "lib\lapack.lib"
    if (Test-Path -LiteralPath $openblasReleaseLib -PathType Leaf) {
        $cmakeArgs += "-DBLAS_LIBRARIES=$openblasReleaseLib"
    }
    if (Test-Path -LiteralPath $lapackReleaseLib -PathType Leaf) {
        $cmakeArgs += "-DLAPACK_LIBRARIES=$lapackReleaseLib"
    }
}
if ($useManifestVcpkg -and -not $manifestVcpkgReady) {
    New-Item -ItemType Directory -Force -Path $vcpkgLocalAppData, $vcpkgDownloads, $vcpkgBuildtrees, $vcpkgPackages | Out-Null
    $oldLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $vcpkgLocalAppData
        Invoke-LoggedNative -Exe $cmake -Arguments $cmakeArgs -LogPath $configureLog
    }
    finally {
        $env:LOCALAPPDATA = $oldLocalAppData
    }
} else {
    Invoke-LoggedNative -Exe $cmake -Arguments $cmakeArgs -LogPath $configureLog
}

$buildLog = Join-Path $logDir "build-win-py$PythonVersion.log"
Invoke-LoggedNative -Exe $cmake -Arguments @("--build", $build, "--config", "Release", "--target", "swigfaiss_avx2") -LogPath $buildLog

$pyBuild = Join-Path $build "faiss\python"
$releaseDir = Join-Path $pyBuild "Release"
if (-not (Test-Path -LiteralPath (Join-Path $pyBuild "setup.py") -PathType Leaf)) {
    throw "missing generated Python package directory: $pyBuild"
}

$vcpkgInstalled = if ($useManifestVcpkg) { $manifestVcpkgInstalled } else { $classicVcpkgInstalled }
$vcpkgBin = Join-Path $vcpkgInstalled "bin"
if (Test-Path -LiteralPath $vcpkgBin -PathType Container) {
    New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
    $nativeDlls = @(Get-ChildItem -LiteralPath $vcpkgBin -Filter "*.dll" -File)
    foreach ($dll in $nativeDlls) {
        Copy-Item -LiteralPath $dll.FullName -Destination $releaseDir -Force
    }
}

Remove-BuildChild -Path (Join-Path $pyBuild "build") -Parent $pyBuild
Remove-BuildChild -Path (Join-Path $pyBuild "dist") -Parent $pyBuild
Remove-BuildChild -Path (Join-Path $pyBuild "faiss") -Parent $pyBuild
Remove-BuildChild -Path (Join-Path $pyBuild "faiss.egg-info") -Parent $pyBuild

$packageLog = Join-Path $logDir "package-win-py$PythonVersion.log"
Push-Location $pyBuild
try {
    Invoke-LoggedNative -Exe $pythonExe -Arguments @("setup.py", "bdist_wheel") -LogPath $packageLog

    $distDir = Join-Path $pyBuild "dist"
    $builtWheels = @(Get-ChildItem -LiteralPath $distDir -Filter "*.whl" -File)
    if ($builtWheels.Count -eq 0) {
        throw "setup.py did not produce a wheel in $distDir"
    }

    foreach ($builtWheel in $builtWheels) {
        Invoke-LoggedNative -Exe $pythonExe -Arguments @(
            "-m", "wheel", "tags", "--remove",
            "--python-tag", $pyTag,
            "--abi-tag", $pyTag,
            "--platform-tag", "win_amd64",
            $builtWheel.FullName
        ) -LogPath $packageLog -Append
    }

    Get-ChildItem -LiteralPath $distDir -Filter "*py3-none-any.whl" -File -ErrorAction SilentlyContinue | Remove-Item -Force
    $finalWheels = @(Get-ChildItem -LiteralPath $distDir -Filter "conann-0.1.1-$pyTag-$pyTag-win_amd64.whl" -File)
    if ($finalWheels.Count -eq 0) {
        throw "retagged wheel was not produced for $pyTag"
    }

    foreach ($wheel in $finalWheels) {
        Copy-Item -LiteralPath $wheel.FullName -Destination $wheelDir -Force
        Write-Host "built wheel: $(Join-Path $wheelDir $wheel.Name)"
    }
}
finally {
    Pop-Location
}
