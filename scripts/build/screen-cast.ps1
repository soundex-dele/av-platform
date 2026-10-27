param([string]$VcpkgRoot = 'D:/vcpkg', [string]$Go = 'go', [switch]$BootstrapMedia)
$ErrorActionPreference = 'Stop'
$Workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Checked([scriptblock]$Command) { & $Command; if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" } }
if (-not (Get-Command $Go -ErrorAction SilentlyContinue)) {
    $LocalGo = Join-Path $Workspace 'out/tools/go/bin/go.exe'
    if (Test-Path -LiteralPath $LocalGo) { $Go = $LocalGo } else { throw 'Install Go 1.25+ or pass -Go /path/to/go.exe' }
}
$Sdk = Join-Path $Workspace 'livekit-sdk-cpp'
$SdkBuild = Join-Path $Sdk 'out/windows-x64'
$Media = Join-Path $Workspace 'livekit-cpp'
if ($BootstrapMedia) { Checked { & (Join-Path $Media 'scripts/bootstrap.ps1') -VcpkgRoot $VcpkgRoot } }
Checked { cmake -S $Sdk -B $SdkBuild -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows-static -DLIVEKIT_BUILD_RTC=ON -DLIVEKIT_BUILD_PLAYER=OFF -DWEBRTC_PREBUILT_DIR= -DLIVEKIT_ENABLE_VIDEO_PLAYOUT=ON -DLIVEKIT_BUILD_TESTS=ON }
Checked { cmake --build $SdkBuild --config Release --target livekit_screen_capture_tests livekit_remote_control_tests livekit_sdk_tests livekit_media_graph_tests --parallel 4 }
$App = Join-Path $Workspace 'livekit-app'
$CachedSources = @()
foreach ($Dependency in @('imgui','ixwebsocket','protobuf','sdl2')) {
    $Source = Join-Path $SdkBuild "_deps/$Dependency-src"
    if (Test-Path -LiteralPath $Source) { $CachedSources += "-DFETCHCONTENT_SOURCE_DIR_$($Dependency.ToUpper())=$Source" }
}
$AppBuild = Join-Path $App 'out/screen-cast-desktop'
Checked { cmake -S (Join-Path $App 'apps/screen-cast/desktop') -B $AppBuild -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows-static "-DWEBRTC_PREBUILT_DIR=$SdkBuild" @CachedSources -DBUILD_TESTING=ON -DLIVEKIT_BUILD_PLAYER=OFF }
Checked { cmake --build $AppBuild --config Release --parallel 4 }
Checked { cmake -S $Media -B "$Media/out/windows-x64" -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows-static "-DWEBRTC_PREBUILT_DIR=$SdkBuild" }
Checked { cmake --build "$Media/out/windows-x64" --config Release --parallel 4 }
Push-Location (Join-Path $Workspace 'livekit-server')
try { Checked { & $Go test ./... }; Checked { & $Go build -o out/livekit-business-api.exe ./cmd/business-api } } finally { Pop-Location }
Push-Location (Join-Path $Workspace 'livekit-app/apps/screen-cast/web')
try { Checked { npm ci --no-audit --no-fund }; Checked { npm run build }; Checked { npm test } } finally { Pop-Location }
Checked { ctest --test-dir $SdkBuild -C Release -R '^(screen_capture|remote_control|sdk|media_graph)$' --output-on-failure }
Checked { ctest --test-dir "$Media/out/windows-x64" -C Release --output-on-failure }
Checked { ctest --test-dir $AppBuild -C Release --output-on-failure }
Write-Host "Built ImGui host: $AppBuild/Release/av_screen_cast.exe"
Write-Host 'Run scripts/run/screen-cast.ps1 to start the services.'
