param(
    [string[]]$PythonVersions = @("3.10.11", "3.11.9", "3.12.10", "3.13.13", "3.14.5"),
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

$script = Join-Path $PSScriptRoot "build_one_python_windows.ps1"
$expandedPythonVersions = @(
    foreach ($entry in $PythonVersions) {
        foreach ($version in ($entry -split ",")) {
            $trimmed = $version.Trim()
            if ($trimmed) {
                $trimmed
            }
        }
    }
)

foreach ($version in $expandedPythonVersions) {
    $params = @{
        PythonVersion = $version
        Architecture = $Architecture
        Triplet = $Triplet
    }

    if ($Generator) {
        $params.Generator = $Generator
    }
    if ($VcpkgRoot) {
        $params.VcpkgRoot = $VcpkgRoot
    }
    if ($CMakeExe) {
        $params.CMakeExe = $CMakeExe
    }
    if ($SwigExe) {
        $params.SwigExe = $SwigExe
    }
    if ($BuildRoot) {
        $params.BuildRoot = $BuildRoot
    }
    if ($SkipPythonDependencyInstall) {
        $params.SkipPythonDependencyInstall = $true
    }
    if ($Clean) {
        $params.Clean = $true
    }

    & $script @params
}
