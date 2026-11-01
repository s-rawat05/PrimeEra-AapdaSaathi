<#
.SYNOPSIS
  Create "Start AapdaSaathi" and "Stop AapdaSaathi" shortcuts on the current user's desktop.
  Start = backend + command centre + resident web app, opens the browser, and connects a USB phone.
#>
$root = Split-Path -Parent $PSScriptRoot
$desktop = [Environment]::GetFolderPath("Desktop")
$shell = New-Object -ComObject WScript.Shell

function New-Shortcut($name, $script, $extraArgs, $style) {
  $lnk = $shell.CreateShortcut((Join-Path $desktop "$name.lnk"))
  $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $root "scripts\$script")`" $extraArgs"
  $lnk.WorkingDirectory = $root
  $lnk.WindowStyle = $style   # 1 = normal window (shows status, Ctrl+C stops), 7 = minimised
  $lnk.Description = $name
  $lnk.Save()
  Write-Host "Created $(Join-Path $desktop "$name.lnk")"
}

New-Shortcut "Start AapdaSaathi" "run_demo.ps1" "-Open -Phone" 1
New-Shortcut "Stop AapdaSaathi" "stop_demo.ps1" "" 7
