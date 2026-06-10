param(
    [string[]]$PythonVersions = @("3.10.11", "3.11.9", "3.12.10", "3.13.13", "3.14.5"),
    [string]$VcpkgRoot = $env:VCPKG_ROOT,
    [string]$Triplet = "x64-windows"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-PyenvPython {
    param([Parameter(Mandatory = $true)][string]$Version)

    $python = Join-Path $env:USERPROFILE ".pyenv\pyenv-win\versions\$Version\python.exe"
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw "missing pyenv Python: $python"
    }
    return (Resolve-Path -LiteralPath $python).Path
}

function Resolve-OptionalVcpkgBin {
    param([string]$ExplicitRoot, [string]$TargetTriplet)

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
        $bin = Join-Path $root "installed\$TargetTriplet\bin"
        if (Test-Path -LiteralPath $bin -PathType Container) {
            return (Resolve-Path -LiteralPath $bin).Path
        }
    }

    return $null
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
            & $Exe @Arguments *>> $LogPath
        } else {
            & $Exe @Arguments *> $LogPath
        }
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    return $LASTEXITCODE
}

$work = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$root = (Resolve-Path -LiteralPath (Join-Path $work "..")).Path
$wheelDir = Join-Path $work "wheels\win_amd64"
$venvDir = Join-Path $env:TEMP "conann_wheel_smoke_windows"
$targetDir = "C:\conann_verify_target"
$fallbackTempDir = "C:\conann_verify_tmp"
$resultDir = Join-Path $work "results\wheel_smoke_windows"
$csv = Join-Path $work "results\wheel_smoke_windows_matrix.csv"
$smokeScript = Join-Path $work "scripts\smoke_conann_wheel.py"
$vcpkgBin = Resolve-OptionalVcpkgBin -ExplicitRoot $VcpkgRoot -TargetTriplet $Triplet
$runId = Get-Date -Format "yyyyMMddHHmmss"

New-Item -ItemType Directory -Force -Path $venvDir, $targetDir, $fallbackTempDir, $resultDir, (Split-Path -Parent $csv) | Out-Null

$rows = @()

foreach ($version in $PythonVersions) {
    $pythonExe = Resolve-PyenvPython -Version $version
    $pyTag = (& $pythonExe -c "import sys; print(f'cp{sys.version_info.major}{sys.version_info.minor}')").Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "failed to compute CPython tag with $pythonExe"
    }

    $wheel = Get-ChildItem -LiteralPath $wheelDir -Filter "conann-0.1.1-$pyTag-$pyTag-win_amd64.whl" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $venv = Join-Path $venvDir "win-py$version-$runId"
    $venvPython = Join-Path $venv "Scripts\python.exe"
    $target = Join-Path $targetDir "win-py$version-$runId"
    $out = Join-Path $resultDir "py$version.json"
    $log = Join-Path $resultDir "py$version.log"

    if (-not $wheel) {
        $rows += [pscustomobject]@{
            python = $version
            wheel = ""
            install_ok = $false
            smoke_ok = $false
            notes = "missing wheel"
        }
        continue
    }

    "" | Set-Content -LiteralPath $log -Encoding UTF8

    $venvExit = Invoke-LoggedNative -Exe $pythonExe -Arguments @("-m", "venv", "--system-site-packages", $venv) -LogPath $log
    if ($venvExit -ne 0 -or -not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        $oldTemp = $env:TEMP
        $oldTmp = $env:TMP
        try {
            $env:TEMP = $fallbackTempDir
            $env:TMP = $fallbackTempDir
            $targetInstallExit = Invoke-LoggedNative -Exe $pythonExe -Arguments @(
                "-m", "pip", "install", "--target", $target, "--force-reinstall", "--no-deps", "--no-index", $wheel.FullName
            ) -LogPath $log -Append
        }
        finally {
            $env:TEMP = $oldTemp
            $env:TMP = $oldTmp
        }
        if ($targetInstallExit -ne 0) {
            $rows += [pscustomobject]@{
                python = $version
                wheel = $wheel.Name
                install_ok = $false
                smoke_ok = $false
                notes = "target install failed after venv creation failed"
            }
            continue
        }

        $oldPythonPath = $env:PYTHONPATH
        $oldPath = $env:PATH
        try {
            $env:PYTHONPATH = if ($oldPythonPath) { "$target;$oldPythonPath" } else { $target }
            if ($vcpkgBin) {
                $env:PATH = "$vcpkgBin;$oldPath"
            }
            $smokeExit = Invoke-LoggedNative -Exe $pythonExe -Arguments @($smokeScript, "--python-version", $version, "--out", $out) -LogPath $log -Append
        }
        finally {
            $env:PYTHONPATH = $oldPythonPath
            $env:PATH = $oldPath
        }

        $rows += [pscustomobject]@{
            python = $version
            wheel = $wheel.Name
            install_ok = $true
            smoke_ok = ($smokeExit -eq 0)
            notes = if ($smokeExit -eq 0) { "ok (target install; venv ensurepip failed)" } else { "smoke failed after target install" }
        }
        continue
    }

    $installExit = Invoke-LoggedNative -Exe $venvPython -Arguments @(
        "-m", "pip", "install", "--force-reinstall", "--no-deps", "--no-index", $wheel.FullName
    ) -LogPath $log -Append

    if ($installExit -ne 0) {
        $rows += [pscustomobject]@{
            python = $version
            wheel = $wheel.Name
            install_ok = $false
            smoke_ok = $false
            notes = "install failed"
        }
        continue
    }

    $oldPath = $env:PATH
    try {
        if ($vcpkgBin) {
            $env:PATH = "$vcpkgBin;$oldPath"
        }
        $smokeExit = Invoke-LoggedNative -Exe $venvPython -Arguments @($smokeScript, "--python-version", $version, "--out", $out) -LogPath $log -Append
    }
    finally {
        $env:PATH = $oldPath
    }

    if ($smokeExit -eq 0) {
        $rows += [pscustomobject]@{
            python = $version
            wheel = $wheel.Name
            install_ok = $true
            smoke_ok = $true
            notes = "ok"
        }
    } else {
        $rows += [pscustomobject]@{
            python = $version
            wheel = $wheel.Name
            install_ok = $true
            smoke_ok = $false
            notes = "smoke failed"
        }
    }
}

$rows | Export-Csv -LiteralPath $csv -NoTypeInformation
Get-Content -LiteralPath $csv

$failedRows = @($rows | Where-Object { -not $_.install_ok -or -not $_.smoke_ok })
if ($failedRows.Count -gt 0) {
    exit 1
}
