param([int]$ApiPort=8080,[int]$MediaPort=7880,[string]$DataDirectory='')
$ErrorActionPreference='Stop'
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (!$DataDirectory) { $DataDirectory=Join-Path $workspace 'out/live-studio-data' }
New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
foreach($name in @('LIVEKIT_API_KEY','LIVEKIT_API_SECRET','LIVE_STUDIO_ADMISSION_SECRET')) { if (![Environment]::GetEnvironmentVariable($name)) { throw "Set $name before running." } }
$env:LIVE_STUDIO_ADMISSION_PORT="$ApiPort"
$config=Join-Path $DataDirectory 'media.json'
$mediaConfig=@{bind='127.0.0.1';port=$MediaPort;keys=@{($env:LIVEKIT_API_KEY)=$env:LIVEKIT_API_SECRET};max_connections=256;rtc=@{port_range_start=50000;port_range_end=51999}} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($config,$mediaConfig,[System.Text.UTF8Encoding]::new($false))
$media=Join-Path $workspace 'livekit-cpp/out/windows-x64/Release/livekit-server.exe'
$business=Join-Path $workspace 'livekit-server/out/live-studio/business-api.exe'
if (!(Test-Path -LiteralPath $media) -or !(Test-Path -LiteralPath $business)) { throw 'Build the media and business servers first.' }
$mediaProcess=Start-Process -FilePath $media -ArgumentList @('--config',('"'+$config+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $DataDirectory 'media.log') -RedirectStandardError (Join-Path $DataDirectory 'media-error.log')
try {
 $web=Join-Path $workspace 'livekit-app/apps/live-studio/web/dist'
 $businessProcess=Start-Process -FilePath $business -ArgumentList @('-listen',"127.0.0.1:$ApiPort",'-db',('"'+(Join-Path $DataDirectory 'studio.sqlite')+'"'),'-live-studio','-live-studio-web',('"'+$web+'"'),'-media-api',"http://127.0.0.1:$MediaPort",'-media-url',"ws://127.0.0.1:$MediaPort") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $DataDirectory 'business.log') -RedirectStandardError (Join-Path $DataDirectory 'business-error.log')
 @{media_pid=$mediaProcess.Id;business_pid=$businessProcess.Id;viewer="http://127.0.0.1:$ApiPort/apps/live-studio/"} | ConvertTo-Json
} catch { Stop-Process -Id $mediaProcess.Id -ErrorAction SilentlyContinue; throw }
