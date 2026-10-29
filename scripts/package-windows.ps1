$ErrorActionPreference = "Stop"

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RootDir

cargo build --release --locked --bin devcloud-app --bin devcloud-agent

$DistDir = Join-Path $RootDir "dist\windows-x86_64"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
Copy-Item "target\release\devcloud-app.exe" (Join-Path $DistDir "DevCloud.exe") -Force
Copy-Item "target\release\devcloud-agent.exe" (Join-Path $DistDir "devcloud-agent.exe") -Force
@"
DevCloud for Windows

Run DevCloud.exe to open the local desktop inventory app.
The companion devcloud-agent.exe provides the command-line scanner.
"@ | Set-Content -Encoding utf8 (Join-Path $DistDir "README.txt")

$Archive = Join-Path $RootDir "dist\DevCloud-windows-x86_64.zip"
Compress-Archive -Path (Join-Path $DistDir "*") -DestinationPath $Archive -Force
