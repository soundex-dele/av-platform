param([string]$VcpkgRoot = 'D:/vcpkg', [string]$Go = 'go', [switch]$BootstrapMedia)
$ErrorActionPreference = 'Stop'
$Workspace = Split-Path -Parent $PSScriptRoot
function Checked([scriptblock]$Command) { & $Command; if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" } }
if (-not (Get-Command $Go -ErrorAction SilentlyContinue)) {
    $LocalGo = Join-Path $Workspace 'out/tools/go/bin/go.exe'
    if (Test-Path -LiteralPath $LocalGo) { $Go = $LocalGo } else { throw 'Install Go 1.25+ or pass -Go /path/to/go.exe' }
}
$Sdk = Join-Path $Workspace 'livekit-sdk-cpp'
$SdkBuild = Join-Path $Sdk 'out/windows-x64'
$Media = Join-Path $Workspace 'livekit-cpp'
if ($BootstrapMedia) { Checked { & (Join-Path $Media 'scripts/bootstrap.ps1') -VcpkgRoot $VcpkgRoot } }
Checked { cmake -S $Sdk -B $SdkBuild -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows-static -DLIVEKIT_ENABLE_VIDEO_PLAYOUT=ON -DLIVEKIT_BUILD_REMOTE_APP=ON -DLIVEKIT_BUILD_TESTS=ON }
Checked { cmake --build $SdkBuild --config Release --target av_remote_host remote_host_fixture remote_host_render_test livekit_remote_control_tests livekit_sdk_tests livekit_media_graph_tests --parallel 4 }
Checked { cmake -S $Media -B "$Media/out/windows-x64" -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows-static "-DWEBRTC_PREBUILT_DIR=$SdkBuild" }
Checked { cmake --build "$Media/out/windows-x64" --config Release --parallel 4 }
Push-Location (Join-Path $Workspace 'livekit-server')
try { Checked { & $Go test ./... }; Checked { & $Go build -o out/livekit-business-api.exe ./cmd/business-api } } finally { Pop-Location }
Push-Location (Join-Path $Workspace 'livekit-app/web')
try { Checked { npm ci --no-audit --no-fund }; Checked { npm run build }; Checked { npm test } } finally { Pop-Location }
Checked { ctest --test-dir $SdkBuild -C Release -R '^(remote_control|remote_host_render|sdk|media_graph)$' --output-on-failure }
Checked { ctest --test-dir "$Media/out/windows-x64" -C Release --output-on-failure }
Write-Host "Built ImGui host: $SdkBuild/Release/av_remote_host.exe"
Write-Host 'Run scripts/start-remote-control.ps1 to start the services.'
