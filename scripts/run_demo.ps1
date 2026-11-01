<#
.SYNOPSIS
  Start the AapdaSaathi demo on one Windows laptop: backend + command centre + resident app (web builds).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\run_demo.ps1
  powershell -ExecutionPolicy Bypass -File scripts\run_demo.ps1 -ApiPort 8010 -Fresh -Rebuild

.NOTES
  Requires: worker\.venv (pip install -r worker\requirements-dev.txt) and Flutter in C:\dev\flutter\bin
  (or on PATH). Uses SQLite + fictional demo data. NOTIFY_REAL_RESIDENTS stays false.
#>
param(
  [int]$ApiPort = 8000,
  [int]$DashboardPort = 8080,
  [int]$AppPort = 8081,
  [int]$EscalationSeconds = 45,
  [switch]$Fresh,     # delete the demo database first
  [switch]$Rebuild,   # rebuild both Flutter web apps for this API port
  [switch]$LiveFeed,  # poll SACHET in the background (needs internet)
  [switch]$Open,      # open the command centre and resident app in the default browser
  [switch]$Phone      # USB phone: tunnel phone:8000 -> laptop API (adb reverse) and launch the app
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$py = Join-Path $root "worker\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) { throw "Python venv missing. Run: python -m venv worker\.venv; worker\.venv\Scripts\python -m pip install -r worker\requirements-dev.txt" }
if (Test-Path "C:\dev\flutter\bin") { $env:Path = "C:\dev\flutter\bin;" + $env:Path }

$inUse = Get-NetTCPConnection -LocalPort $ApiPort -State Listen -ErrorAction SilentlyContinue
if ($inUse) { throw "Port $ApiPort is already in use (PID $($inUse.OwningProcess)). Use -ApiPort 8010." }

$db = Join-Path $root "worker\data\demo.db"
if ($Fresh -and (Test-Path $db)) { Remove-Item "$db*" -Force; Write-Host "Fresh demo database." }

$api = "http://localhost:$ApiPort"
foreach ($proj in @("dashboard", "app")) {
  $web = Join-Path $root "$proj\build\web\index.html"
  # Each web build records the API address it was compiled for; a mismatch forces a rebuild.
  $marker = Join-Path $root "$proj\build\web\.api_base"
  $builtFor = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { "" }
  if ($Rebuild -or -not (Test-Path $web) -or $builtFor -ne $api) {
    Write-Host "Building $proj for $api ..."
    Push-Location (Join-Path $root $proj)
    flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=$api | Out-Host
    $ok = $LASTEXITCODE -eq 0
    Pop-Location
    if (-not $ok) { throw "Flutter web build failed for $proj" }
    Set-Content -Path $marker -Value $api -Encoding ascii
  }
}

$env:DATABASE_URL = "sqlite+aiosqlite:///./data/demo.db"
$env:CORS_ORIGINS = "http://localhost:$DashboardPort,http://localhost:$AppPort,http://127.0.0.1:$DashboardPort,http://127.0.0.1:$AppPort"
$env:DEMO_ESCALATION_INTERVAL_SECONDS = "$EscalationSeconds"
$env:FEED_POLL_ENABLED = if ($LiveFeed) { "true" } else { "false" }
$env:NOTIFY_REAL_RESIDENTS = "false"

$jobs = @()
$jobs += Start-Process -PassThru -WindowStyle Minimized -WorkingDirectory (Join-Path $root "worker") $py `
  -ArgumentList "-m", "uvicorn", "app.main:app", "--port", "$ApiPort"
$jobs += Start-Process -PassThru -WindowStyle Minimized -WorkingDirectory (Join-Path $root "dashboard\build\web") $py `
  -ArgumentList "-m", "http.server", "$DashboardPort", "--bind", "127.0.0.1"
$jobs += Start-Process -PassThru -WindowStyle Minimized -WorkingDirectory (Join-Path $root "app\build\web") $py `
  -ArgumentList "-m", "http.server", "$AppPort", "--bind", "127.0.0.1"

Write-Host ""
Write-Host "AapdaSaathi demo running (Ctrl+C to stop):"
Write-Host "  API + docs      $api/docs"
Write-Host "  Command centre  http://localhost:$DashboardPort"
Write-Host "  Resident app    http://localhost:$AppPort"
Write-Host "  Scripted demo   $py scripts\demo_smoke.py $api --pace 3"

for ($i = 0; $i -lt 30; $i++) {
  try { Invoke-WebRequest "$api/api/v1/health" -UseBasicParsing -TimeoutSec 2 | Out-Null; break } catch { Start-Sleep -Seconds 1 }
}
if ($Phone) {
  $adb = "C:\dev\android-sdk\platform-tools\adb.exe"
  if (-not (Test-Path $adb)) { $adb = "adb" }
  # The installed app calls http://127.0.0.1:8000 on the phone; forward that to this laptop's API.
  & $adb reverse tcp:8000 tcp:$ApiPort | Out-Null
  & $adb shell monkey -p in.primeera.aapda_saathi -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
  Write-Host "  Phone           USB tunnel phone:8000 -> laptop:$ApiPort, app launched"
}
if ($Open) {
  Start-Process "http://localhost:$DashboardPort"
  Start-Process "http://localhost:$AppPort"
}
try { while ($true) { Start-Sleep -Seconds 2 } }
finally { $jobs | ForEach-Object { Stop-Process -Id $_.Id -ErrorAction SilentlyContinue } }
