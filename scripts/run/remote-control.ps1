param([string]$AdvertisedHost = '127.0.0.1', [int]$HttpPort = 8080, [int]$MediaPort = 7880)
$ErrorActionPreference = 'Stop'
$Workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $env:LIVEKIT_API_KEY -or $env:LIVEKIT_API_SECRET.Length -lt 24) { throw 'Set LIVEKIT_API_KEY and LIVEKIT_API_SECRET (at least 24 characters) in the service environment.' }
$RunDirectory = Join-Path $Workspace 'out/remote-run'
New-Item -ItemType Directory -Force $RunDirectory | Out-Null
$ConfigPath = Join-Path $RunDirectory 'media.json'
$Keys = @{}; $Keys[$env:LIVEKIT_API_KEY] = $env:LIVEKIT_API_SECRET
@{ bind='0.0.0.0'; port=$MediaPort; keys=$Keys; media_mode='sfu'; rtc=@{port_range_start=50000;port_range_end=50100} } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding utf8
$MediaBinary = Join-Path $Workspace 'livekit-cpp/out/windows-x64/Release/livekit-server.exe'
$BusinessBinary = Join-Path $Workspace 'livekit-server/out/livekit-business-api.exe'
foreach ($Binary in @($MediaBinary,$BusinessBinary)) { if (-not (Test-Path -LiteralPath $Binary)) { throw "Build missing: $Binary" } }
$MediaProcess=$null; $BusinessProcess=$null
try {
    $MediaProcess = Start-Process -FilePath $MediaBinary -ArgumentList @('--config', ('"'+$ConfigPath+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$RunDirectory/media.stdout.log" -RedirectStandardError "$RunDirectory/media.stderr.log"
    $BusinessArgs = @('-listen',"0.0.0.0:$HttpPort",'-db',('"'+$RunDirectory+'/state.sqlite"'),'-remote-control-web',('"'+$Workspace+'/livekit-app/apps/remote-control/web/dist"'),'-media-api',"http://127.0.0.1:$MediaPort",'-media-url',"ws://${AdvertisedHost}:$MediaPort")
    $BusinessProcess = Start-Process -FilePath $BusinessBinary -ArgumentList $BusinessArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput "$RunDirectory/business.stdout.log" -RedirectStandardError "$RunDirectory/business.stderr.log"
    Write-Host "Browser URL: http://${AdvertisedHost}:$HttpPort/apps/remote-control/`nHost service URL: http://${AdvertisedHost}:$HttpPort"
    Write-Host "Open $Workspace/livekit-app/out/remote-control-desktop/Release/av_remote_host.exe on the Windows computer to share."
    Write-Host 'Ctrl+C stops these service processes. Use HTTPS/WSS outside a trusted development LAN.'
    while (-not $MediaProcess.HasExited -and -not $BusinessProcess.HasExited) { Start-Sleep -Seconds 1 }
    throw "Service exited; see $RunDirectory"
} finally {
    foreach ($Process in @($BusinessProcess,$MediaProcess)) { if ($null -ne $Process -and -not $Process.HasExited) { $Process.Kill(); $Process.WaitForExit() } }
}
