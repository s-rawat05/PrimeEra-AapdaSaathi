<#
.SYNOPSIS
  Stop an AapdaSaathi demo started by scripts\run_demo.ps1 (API, both static web servers, launcher window).
  Only processes running this project's Python virtualenv are touched.
#>
$root = Split-Path -Parent $PSScriptRoot
$py = Join-Path $root "worker\.venv\Scripts\python.exe"
$procs = Get-CimInstance Win32_Process | Where-Object {
  ($_.CommandLine -like "*$py*" -and ($_.CommandLine -like "*uvicorn app.main:app*" -or $_.CommandLine -like "*http.server*")) -or
  ($_.CommandLine -like "*run_demo.ps1*" -and $_.ProcessId -ne $PID)
}
if (-not $procs) { Write-Host "AapdaSaathi is not running."; return }
foreach ($p in $procs) {
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  Write-Host "Stopped $($p.Name) (PID $($p.ProcessId))"
}
