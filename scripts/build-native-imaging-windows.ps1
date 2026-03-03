param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $true)]
    [string]$Configuration,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

function Write-WarnAndExit {
    param([string]$Message)
    Write-Warning "native_imaging: $Message"
    exit 0
}

function Replace-Exact {
    param(
        [string]$Content,
        [string]$Needle,
        [string]$Replacement
    )

    if ($Content.Contains($Needle)) {
        return $Content.Replace($Needle, $Replacement)
    }
    return $Content
}

try {
    if ($Configuration -ine 'Debug') {
        Write-Host "native_imaging: skipping build for configuration '$Configuration'."
        exit 0
    }

    if (!(Test-Path -LiteralPath $ProjectRoot)) {
        Write-WarnAndExit "project root does not exist: $ProjectRoot"
    }
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

    $packageConfigPath = Join-Path $ProjectRoot '.dart_tool/package_config.json'
    if (!(Test-Path -LiteralPath $packageConfigPath)) {
        Write-WarnAndExit "missing package config at $packageConfigPath"
    }

    $packageConfig = Get-Content -LiteralPath $packageConfigPath -Raw | ConvertFrom-Json
    $nativeImagingPackage = $packageConfig.packages | Where-Object { $_.name -eq 'native_imaging' } | Select-Object -First 1
    if (-not $nativeImagingPackage) {
        Write-WarnAndExit "could not resolve native_imaging package in package_config.json"
    }

    $rootUri = [string]$nativeImagingPackage.rootUri
    if ([string]::IsNullOrWhiteSpace($rootUri)) {
        Write-WarnAndExit 'native_imaging rootUri is empty'
    }

    $nativeImagingRoot = if ($rootUri.StartsWith('file:')) {
        ([System.Uri]$rootUri).LocalPath
    } else {
        Join-Path $ProjectRoot $rootUri
    }
    if (!(Test-Path -LiteralPath $nativeImagingRoot)) {
        Write-WarnAndExit "resolved native_imaging root does not exist: $nativeImagingRoot"
    }

    $nativeImagingSource = Join-Path $nativeImagingRoot 'ios/src'
    if (!(Test-Path -LiteralPath $nativeImagingSource)) {
        Write-WarnAndExit "native_imaging source dir not found: $nativeImagingSource"
    }

    $buildRoot = Join-Path $ProjectRoot 'build/native_imaging/windows_debug'
    $patchedSourceDir = Join-Path $buildRoot 'src'
    $cmakeBuildDir = Join-Path $buildRoot 'cmake_build'

    if (Test-Path -LiteralPath $patchedSourceDir) {
        Remove-Item -LiteralPath $patchedSourceDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $cmakeBuildDir) {
        Remove-Item -LiteralPath $cmakeBuildDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $patchedSourceDir -Force | Out-Null
    Copy-Item -Path (Join-Path $nativeImagingSource '*') -Destination $patchedSourceDir -Recurse

    $extraPath = Join-Path $patchedSourceDir 'extra.c'
    if (!(Test-Path -LiteralPath $extraPath)) {
        Write-WarnAndExit "expected file does not exist: $extraPath"
    }
    $extraContent = Get-Content -LiteralPath $extraPath -Raw
    $extraContent = $extraContent -replace "(?m)^\s*#include <unistd\.h>\s*(\r?\n)", ""
    Set-Content -LiteralPath $extraPath -Value $extraContent -NoNewline

    $cmakeListsPath = Join-Path $patchedSourceDir 'CMakeLists.txt'
    if (!(Test-Path -LiteralPath $cmakeListsPath)) {
        Write-WarnAndExit "expected file does not exist: $cmakeListsPath"
    }
    $cmakeContent = Get-Content -LiteralPath $cmakeListsPath -Raw

    $targetLinkOptionsBlock = @'
target_link_options(Imaging PRIVATE
    "-Wl,-z,max-page-size=16384"
)
'@
    $cmakeContent = Replace-Exact `
        -Content $cmakeContent `
        -Needle $targetLinkOptionsBlock `
        -Replacement @'
if(NOT WIN32)
target_link_options(Imaging PRIVATE
    "-Wl,-z,max-page-size=16384"
)
endif()
'@

    $targetLinkLibrariesLine = 'target_link_libraries(Imaging m)'
    $cmakeContent = Replace-Exact `
        -Content $cmakeContent `
        -Needle $targetLinkLibrariesLine `
        -Replacement @'
if(NOT WIN32)
target_link_libraries(Imaging m)
endif()
'@

    if (-not $cmakeContent.Contains('set_target_properties(Imaging PROPERTIES PREFIX "lib" OUTPUT_NAME "Imaging")')) {
        $cmakeContent += @'

if(WIN32)
set_target_properties(Imaging PROPERTIES PREFIX "lib" OUTPUT_NAME "Imaging")
endif()
'@
    }

    Set-Content -LiteralPath $cmakeListsPath -Value $cmakeContent -NoNewline

    New-Item -ItemType Directory -Path $cmakeBuildDir -Force | Out-Null
    & cmake -S $patchedSourceDir -B $cmakeBuildDir -DCMAKE_BUILD_TYPE=Debug
    & cmake --build $cmakeBuildDir --config Debug

    $dll = Get-ChildItem -Path $cmakeBuildDir -Filter 'libImaging.dll' -Recurse | Select-Object -First 1
    if (-not $dll) {
        Write-WarnAndExit "build finished but libImaging.dll was not found in $cmakeBuildDir"
    }

    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $OutputDir 'libImaging.dll') -Force
    Write-Host "native_imaging: copied libImaging.dll to $OutputDir"
} catch {
    Write-Warning "native_imaging: build failed: $($_.Exception.Message)"
    exit 0
}
