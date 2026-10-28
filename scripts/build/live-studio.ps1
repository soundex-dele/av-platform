param(
 [Parameter(Mandatory=$true)][string]$FFmpegRoot,
 [string]$FFmpegInclude='',
 [string]$VcpkgRoot=$env:VCPKG_ROOT,
 [string]$WebRTCBuild='',
 [string]$QtRoot=$env:QT_ROOT,
 [string]$QtWebRTCBuild='',
 [string]$Go='',
 [switch]$Package
)
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (!$Go) { $Go=Join-Path $workspace 'out/tools/go/bin/go.exe'; if (!(Test-Path -LiteralPath $Go)) { $Go=(Get-Command go -ErrorAction Stop).Source } }
if (!$VcpkgRoot) { throw 'Pass -VcpkgRoot or set VCPKG_ROOT.' }
if (!$QtRoot -or !(Test-Path -LiteralPath (Join-Path $QtRoot 'lib/cmake/Qt6/Qt6Config.cmake'))) { throw 'Pass -QtRoot pointing to a Qt 6.8+ MSVC installation, or set QT_ROOT.' }
if (!$WebRTCBuild) { $WebRTCBuild=Join-Path $workspace 'livekit-sdk-cpp/out/windows-x64' }
if (!$QtWebRTCBuild) {
 $candidate=Join-Path $workspace 'livekit-app/out/conference-qt-windows'
 $stamp=Join-Path $candidate 'livekit-msvc-runtime.txt'
 if ((Test-Path -LiteralPath $stamp) -and (Get-Content -LiteralPath $stamp -Raw).Trim().EndsWith('DLL')) { $QtWebRTCBuild=$candidate }
}
if (!$FFmpegInclude) { $FFmpegInclude=Join-Path $FFmpegRoot 'include' }
if (!(Test-Path -LiteralPath (Join-Path $FFmpegInclude 'libavformat/avformat.h'))) { throw 'Pass matching FFmpeg development headers with -FFmpegInclude.' }
function Checked { param([string]$Exe,[string[]]$Arguments) & $Exe @Arguments; if ($LASTEXITCODE -ne 0) { throw "$Exe failed ($LASTEXITCODE)" } }
$build=Join-Path $workspace 'livekit-app/out/live-studio-qt6'
$mediaBuild=Join-Path $workspace 'livekit-cpp/out/windows-x64'
Checked 'cmake' @('-S',(Join-Path $workspace 'livekit-cpp'),'-B',$mediaBuild,'-G','Visual Studio 17 2022','-A','x64',"-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake",'-DVCPKG_TARGET_TRIPLET=x64-windows-static',"-DWEBRTC_PREBUILT_DIR=$WebRTCBuild")
Checked 'cmake' @('--build',$mediaBuild,'--config','Release','--target','livekit-server','--parallel','2')

Push-Location (Join-Path $workspace 'livekit-server')
try { Checked $Go @('test','./...'); Checked $Go @('vet','./...'); Checked $Go @('build','-o','out/live-studio/business-api.exe','./cmd/business-api'); Checked $Go @('build','-o','out/live-studio/studio-admin.exe','./cmd/studio-admin') } finally { Pop-Location }
Push-Location (Join-Path $workspace 'livekit-app/apps/live-studio/web')
try { Checked 'npm.cmd' @('ci','--ignore-scripts'); Checked 'npm.cmd' @('run','build'); Checked 'npm.cmd' @('test') } finally { Pop-Location }
# Qt uses /MD. Keep the server's /MT prebuilt separate; build a matching WebRTC
# from source unless an explicitly matching /MD build is supplied.
Checked 'cmake' @('-S',(Join-Path $workspace 'livekit-app/apps/live-studio/desktop'),'-B',$build,'-G','Visual Studio 17 2022','-A','x64',"-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake",'-DVCPKG_TARGET_TRIPLET=x64-windows',"-DCMAKE_PREFIX_PATH=$QtRoot","-DWEBRTC_PREBUILT_DIR=$QtWebRTCBuild",'-DOPENSSL_USE_STATIC_LIBS=OFF','-DOPENSSL_MSVC_STATIC_RT=OFF',"-DLIVEKIT_FFMPEG_ROOT=$FFmpegRoot","-DLIVEKIT_FFMPEG_INCLUDE=$FFmpegInclude",'-DLIVEKIT_ENABLE_VIDEO_PLAYOUT=OFF','-DBUILD_TESTING=ON')
Checked 'cmake' @('--build',$build,'--config','Release','--target','av_live_studio','studio_widgets_tests','studio_engine_tests','studio_graph_tests','studio_media_graph_tests','studio_publisher_fixture','--parallel','2')
Checked 'ctest' @('--test-dir',$build,'-C','Release','--output-on-failure')
if ($Package) { & (Join-Path $PSScriptRoot 'package-live-studio.ps1') -FFmpegInclude $FFmpegInclude -WebRTCBuild $WebRTCBuild }
