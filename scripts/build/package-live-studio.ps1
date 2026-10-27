param([string]$FFmpegInclude='', [string]$WebRTCBuild='')
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build=Join-Path $workspace 'livekit-app/out/live-studio'
$mediaBuild=Join-Path $workspace 'livekit-cpp/out/windows-x64'
if (!$WebRTCBuild) { $WebRTCBuild=Join-Path $workspace 'livekit-sdk-cpp/out/windows-x64' }
$destination=Join-Path $workspace ('out/packages/live-studio-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
 New-Item -ItemType Directory -Path $destination -Force | Out-Null
 Copy-Item -LiteralPath (Join-Path $build 'Release/av_live_studio.exe') -Destination $destination
 Get-ChildItem -LiteralPath (Join-Path $build 'Release') -Filter '*.dll' | Copy-Item -Destination $destination
 Copy-Item -LiteralPath (Join-Path $workspace 'livekit-app/apps/live-studio/README.md') -Destination $destination
 Copy-Item -LiteralPath (Join-Path $workspace 'scripts/run/live-studio-package.ps1') -Destination (Join-Path $destination 'start-services.ps1')
 $serverDestination=Join-Path $destination 'server'
 New-Item -ItemType Directory -Path $serverDestination -Force | Out-Null
 Copy-Item -LiteralPath (Join-Path $mediaBuild 'Release/livekit-server.exe') -Destination $serverDestination
 Copy-Item -LiteralPath (Join-Path $workspace 'livekit-server/out/live-studio/business-api.exe'),(Join-Path $workspace 'livekit-server/out/live-studio/studio-admin.exe') -Destination $serverDestination
 Copy-Item -LiteralPath (Join-Path $workspace 'livekit-app/apps/live-studio/web/dist') -Destination (Join-Path $serverDestination 'web') -Recurse -Force
 Copy-Item -LiteralPath (Join-Path $workspace 'docs/integration/live-studio') -Destination (Join-Path $destination 'documentation') -Recurse -Force
 $licenses=Join-Path $destination 'licenses'
 New-Item -ItemType Directory -Path $licenses -Force | Out-Null
 $licenseSources=@{
 'SDL2.txt'=(Join-Path $build '_deps/sdl2-src/LICENSE.txt')
 'ImGui.txt'=(Join-Path $WebRTCBuild '_deps/imgui-src/LICENSE.txt')
 'FFmpeg-GPLv3.txt'=$(if($FFmpegInclude){Join-Path $FFmpegInclude 'COPYING.GPLv3'}else{''})
 'WebRTC.txt'=(Join-Path $workspace 'webrtc/LICENSE')
 'SDK.txt'=(Join-Path $workspace 'livekit-sdk-cpp/LICENSE')
 }
 foreach($entry in $licenseSources.GetEnumerator()){if($entry.Value -and (Test-Path -LiteralPath $entry.Value)){Copy-Item -LiteralPath $entry.Value -Destination (Join-Path $licenses $entry.Key)}}

 Write-Host "Desktop package: $destination. See README for FFmpeg/SDL license requirements."

$manifest=Get-ChildItem -LiteralPath $destination -Recurse -File | Where-Object { $_.Extension -in '.exe','.dll' } | ForEach-Object { @{file=[System.IO.Path]::GetRelativePath($destination,$_.FullName);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} }
@{created=(Get-Date -Format o);source='uncommitted workspace build';files=@($manifest)} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -Encoding utf8NoBOM
Write-Output $destination
