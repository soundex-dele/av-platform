param([int]$ApiPort=8080,[int]$MediaPort=7880,[string]$DataDirectory='', [string]$PublicMediaUrl='')
$ErrorActionPreference='Stop'
$packageRoot=$PSScriptRoot
if (!(Test-Path -LiteralPath (Join-Path $packageRoot 'server/business-api.exe'))) { throw 'Run the copy of this script inside the built package.' }
if (!$DataDirectory) { $DataDirectory=Join-Path $packageRoot 'data' }
if (!$PublicMediaUrl) { $PublicMediaUrl="ws://127.0.0.1:$MediaPort" }
foreach($name in @('LIVEKIT_API_KEY','LIVEKIT_API_SECRET','LIVE_STUDIO_ADMISSION_SECRET')) { if (![Environment]::GetEnvironmentVariable($name)) { throw "Set $name before starting the services." } }
New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
$config=Join-Path $DataDirectory 'media.json'
$keys=@{}; $keys[$env:LIVEKIT_API_KEY]=$env:LIVEKIT_API_SECRET
$mediaConfig=@{bind='127.0.0.1';port=$MediaPort;keys=$keys;max_connections=256;rtc=@{port_range_start=50000;port_range_end=51999}} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($config,$mediaConfig,[System.Text.UTF8Encoding]::new($false))
$env:LIVE_STUDIO_ADMISSION_PORT="$ApiPort"
$mediaProcess=Start-Process -FilePath (Join-Path $packageRoot 'server/livekit-server.exe') -ArgumentList @('--config',('"'+$config+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $DataDirectory 'media.log') -RedirectStandardError (Join-Path $DataDirectory 'media-error.log')
try {
 $businessProcess=Start-Process -FilePath (Join-Path $packageRoot 'server/business-api.exe') -ArgumentList @('-listen',"127.0.0.1:$ApiPort",'-db',('"'+(Join-Path $DataDirectory 'studio.sqlite')+'"'),'-live-studio','-live-studio-web',('"'+(Join-Path $packageRoot 'server/web')+'"'),'-media-api',"http://127.0.0.1:$MediaPort",'-media-url',$PublicMediaUrl) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $DataDirectory 'business.log') -RedirectStandardError (Join-Path $DataDirectory 'business-error.log')
 @{media_pid=$mediaProcess.Id;business_pid=$businessProcess.Id;viewer="http://127.0.0.1:$ApiPort/apps/live-studio/"} | ConvertTo-Json
} catch { Stop-Process -Id $mediaProcess.Id -ErrorAction SilentlyContinue; throw }
