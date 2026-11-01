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
  [switch]$Phone,     # USB phone: tunnel phone:8000 -> laptop API (adb reverse) and launch the app
  [switch]$Public     # publish via a Cloudflare quick tunnel: one https://*.trycloudflare.com link
                      # (command centre at /, resident app at /app/). Fictional demo data only.
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$py = Join-Path $root "worker\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) { throw "Python venv missing. Run: python -m venv worker\.venv; worker\.venv\Scripts\python -m pip install -r worker\requirements-dev.txt" }
if (Test-Path "C:\dev\flutter\bin") { $env:Path = "C:\dev\flutter\bin;" + $env:Path }

$inUse = Get-NetTCPConnection -LocalPort $ApiPort -State Listen -ErrorAction SilentlyContinue
if ($inUse) {
  $owners = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*--port $ApiPort*" } |
    ForEach-Object { "    PID $($_.ProcessId): $($_.CommandLine)" }
  Write-Host "Port $ApiPort is already in use - another server is running:" -ForegroundColor Red
  $owners | Select-Object -First 4 | ForEach-Object { Write-Host $_ }
  Write-Host "Close that window (or run 'Stop AapdaSaathi'), make sure nothing restarts it, then start again."
  Write-Host "Press Enter to close."; [void][Console]::ReadLine(); exit 1
}

$db = Join-Path $root "worker\data\demo.db"
if ($Fresh -and (Test-Path $db)) { Remove-Item "$db*" -Force; Write-Host "Fresh demo database." }

$api = "http://localhost:$ApiPort"

# Each web build records the API address it was compiled for; a mismatch forces a rebuild.
function Build-Web($proj, $outDir, $apiBase, $baseHref) {
  $out = Join-Path $root "$proj\$outDir"
  $marker = Join-Path $out ".api_base"
  $builtFor = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { "" }
  if ($Rebuild -or -not (Test-Path (Join-Path $out "index.html")) -or $builtFor -ne $apiBase) {
    Write-Host "Building $proj ($outDir) for $apiBase ..."
    Push-Location (Join-Path $root $proj)
    flutter build web --release --no-wasm-dry-run --base-href $baseHref "--dart-define=API_BASE_URL=$apiBase" -o $outDir | Out-Host
    $ok = $LASTEXITCODE -eq 0
    Pop-Location
    if (-not $ok) { throw "Flutter web build failed for $proj" }
    Set-Content -Path $marker -Value $apiBase -Encoding ascii
  }
  return $out
}
Build-Web "dashboard" "build\web" $api "/" | Out-Null
Build-Web "app" "build\web" $api "/" | Out-Null
if ($Public) {
  # Served by the API itself, so they call the address they were opened from.
  $env:WEB_DASHBOARD_DIR = Build-Web "dashboard" "build\web_public" "same-origin" "/"
  $env:WEB_APP_DIR = Build-Web "app" "build\web_public" "same-origin" "/app/"
}

$env:DATABASE_URL = "sqlite+aiosqlite:///./data/demo.db"
$env:CORS_ORIGINS = "http://localhost:$DashboardPort,http://localhost:$AppPort,http://127.0.0.1:$DashboardPort,http://127.0.0.1:$AppPort"
$env:DEMO_ESCALATION_INTERVAL_SECONDS = "$EscalationSeconds"
$env:FEED_POLL_ENABLED = if ($LiveFeed) { "true" } else { "false" }
$env:NOTIFY_REAL_RESIDENTS = "false"

$uvicornArgs = @("-m", "uvicorn", "app.main:app", "--port", "$ApiPort")
# Behind the local tunnel, trust X-Forwarded-For from 127.0.0.1 only, so rate limits apply per visitor.
if ($Public) { $uvicornArgs += @("--proxy-headers", "--forwarded-allow-ips", "127.0.0.1") }
$jobs = @()
$jobs += Start-Process -PassThru -WindowStyle Minimized -WorkingDirectory (Join-Path $root "worker") $py `
  -ArgumentList $uvicornArgs
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

# From here on any failure still stops every process this script started (no orphaned servers).
try {
$publicFile = Join-Path $root "worker\data\public_url.txt"
if (Test-Path $publicFile) { Remove-Item $publicFile -Force }
$healthy = $false
for ($i = 0; $i -lt 60 -and -not $healthy; $i++) {
  # 127.0.0.1, not localhost: Windows PowerShell resolves localhost to IPv6 ::1 first, where uvicorn isn't listening.
  try { Invoke-WebRequest "http://127.0.0.1:$ApiPort/api/v1/health" -UseBasicParsing -TimeoutSec 2 | Out-Null; $healthy = $true }
  catch { Start-Sleep -Seconds 1 }
}
if (-not $healthy) { throw "The API did not start on port $ApiPort (is another server using it?)" }
$publicUrl = $null
if ($Public) {
  $cf = "C:\dev\cloudflared\cloudflared.exe"
  if (-not (Test-Path $cf)) { $cf = "cloudflared" }
  $cfLog = Join-Path $root "worker\data\cloudflared.log"
  if (Test-Path $cfLog) { Remove-Item $cfLog -Force }
  $jobs += Start-Process -PassThru -WindowStyle Minimized $cf `
    -ArgumentList "tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:$ApiPort", "--logfile", "`"$cfLog`""
  for ($i = 0; $i -lt 60 -and -not $publicUrl; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $cfLog) {
      $m = Select-String -Path $cfLog -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" | Select-Object -First 1
      if ($m) { $publicUrl = $m.Matches[0].Value }
    }
  }
  if ($publicUrl) {
    Set-Content -Path $publicFile -Value $publicUrl -Encoding ascii
    Write-Host ""
    Write-Host "  PUBLIC LINK     $publicUrl            (command centre)"
    Write-Host "                  $publicUrl/app/       (resident app)"
    Write-Host "                  Works while this window stays open. Fictional demo data only."
  } else {
    Write-Host "  PUBLIC LINK     tunnel did not start - see $cfLog" -ForegroundColor Yellow
  }
}
if ($Phone) {
  # Optional and never fatal: adb writes to stderr (e.g. "no devices"), which Windows PowerShell 5.1
  # would otherwise turn into a terminating error under $ErrorActionPreference = "Stop".
  $adb = "C:\dev\android-sdk\platform-tools\adb.exe"
  if (-not (Test-Path $adb)) { $adb = "adb" }
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $state = (& $adb get-state 2>$null | Out-String).Trim()
  if ($state -eq "device") {
    # The installed app calls http://127.0.0.1:8000 on the phone; forward that to this laptop's API.
    & $adb reverse tcp:8000 tcp:$ApiPort 2>$null | Out-Null
    & $adb shell monkey -p in.primeera.aapda_saathi -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
    Write-Host "  Phone           USB tunnel phone:8000 -> laptop:$ApiPort, app launched"
  } else {
    Write-Host "  Phone           not connected (plug in USB with debugging on, then restart)" -ForegroundColor Yellow
  }
  $ErrorActionPreference = $prev
}
if ($Open) {
  if ($publicUrl) { Start-Process $publicUrl } else { Start-Process "http://localhost:$DashboardPort" }
  Start-Process "http://localhost:$AppPort"
}
while ($true) { Start-Sleep -Seconds 2 }
}
catch {
  Write-Host ""
  Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Press Enter to close."; [void][Console]::ReadLine()
}
finally { $jobs | ForEach-Object { Stop-Process -Id $_.Id -ErrorAction SilentlyContinue } }
