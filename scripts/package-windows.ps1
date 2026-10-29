$ErrorActionPreference = "Stop"

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RootDir

cargo build --release --locked --bin continuity-app --bin continuity-agent

$DistDir = Join-Path $RootDir "dist\windows-x86_64"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
Copy-Item "target\release\continuity-app.exe" (Join-Path $DistDir "Continuity.exe") -Force
Copy-Item "target\release\continuity-agent.exe" (Join-Path $DistDir "continuity-agent.exe") -Force
@"
Continuity for Windows

Run Continuity.exe to open the local desktop inventory app.
The companion continuity-agent.exe provides the command-line scanner.
"@ | Set-Content -Encoding utf8 (Join-Path $DistDir "README.txt")

$Archive = Join-Path $RootDir "dist\Continuity-windows-x86_64.zip"
Compress-Archive -Path (Join-Path $DistDir "*") -DestinationPath $Archive -Force
