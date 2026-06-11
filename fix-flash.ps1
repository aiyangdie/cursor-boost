# Cursor flash-exit fix: kill stale processes, clear locks, restart with --disable-gpu, fix off-screen window
param([switch]$DisableGPU = $true, [switch]$Quiet, [int]$WaitSeconds = 25)

$ErrorActionPreference = 'Continue'
function W($m) { if (-not $Quiet) { Write-Output $m } }

Add-Type -Namespace Fix -Name CursorWin -MemberDefinition @'
public class Api {
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hWnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int n);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr hWnd, System.IntPtr hAfter, int x, int y, int cx, int cy, uint flags);
}
'@ -ErrorAction SilentlyContinue

W 'Killing stale Cursor processes...'
Get-Process Cursor* -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

foreach ($f in @(
    "$env:APPDATA\Cursor\User\globalStorage\storage.json.vsctmp",
    "$env:APPDATA\Cursor\code.lock"
)) {
    if (Test-Path $f) { Remove-Item $f -Force -EA SilentlyContinue; W "Removed lock: $f" }
}

$exe = "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe"
if (-not (Test-Path $exe)) { $exe = "$env:LOCALAPPDATA\Programs\Cursor\Cursor.exe" }
if (-not (Test-Path $exe)) { W 'ERROR: Cursor.exe not found'; exit 1 }

$args = @()
if ($DisableGPU) { $args += '--disable-gpu', '--disable-software-rasterizer' }
W "Starting Cursor with args: $($args -join ' ')"
Start-Process -FilePath $exe -ArgumentList $args | Out-Null

$sw = [Fix.Api]::GetSystemMetrics(0)
$sh = [Fix.Api]::GetSystemMetrics(1)
$fixed = $false
for ($i = 0; $i -lt $WaitSeconds; $i++) {
    Start-Sleep -Seconds 1
    $proc = Get-Process Cursor -EA SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $proc) { continue }
    $hwnd = $proc.MainWindowHandle
    [void][Fix.Api]::ShowWindow($hwnd, 9)
    [void][Fix.Api]::ShowWindow($hwnd, 5)
    [void][Fix.Api]::SetWindowPos($hwnd, [IntPtr]::Zero, 80, 80, [Math]::Min(1280, $sw - 100), [Math]::Min(800, $sh - 100), 0x40)
    [void][Fix.Api]::SetForegroundWindow($hwnd)
    $fixed = $true
    W "Window restored for PID $($proc.Id)"
    break
}
if ($fixed) { W 'Flash exit fix: PASS' } else { W 'Flash exit fix: started but window not confirmed' }
