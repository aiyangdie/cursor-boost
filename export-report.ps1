# Export Cursor diagnostic pack for community support (no passwords/tokens)
param([switch]$Quiet)

$ErrorActionPreference = 'Continue'
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$desk = [Environment]::GetFolderPath('Desktop')
if (-not $desk) { $desk = $env:USERPROFILE }
$outDir = Join-Path $desk "CursorReport-$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function W($m) { if (-not $Quiet) { Write-Output $m } }

W "Collecting diagnostics -> $outDir"

$scanner = Join-Path $Root 'log_scanner.py'
if (Test-Path $scanner) {
    python $scanner 2>$null | Out-Null
    $scan = Join-Path $env:TEMP 'cursor-boost-scan.json'
    if (Test-Path $scan) { Copy-Item $scan (Join-Path $outDir 'scan-result.json') -Force }
}

$sys = @()
$sys += "time=$stamp"
$sys += "user=$env:USERNAME"
$sys += "computer=$env:COMPUTERNAME"
$sys += "cursor_procs=$((Get-Process Cursor -EA SilentlyContinue).Count)"
$exe = "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe"
if (Test-Path $exe) { $sys += "cursor_version=$((Get-Item $exe).VersionInfo.FileVersion)" }
$vscdb = "$env:APPDATA\Cursor\User\globalStorage\state.vscdb"
if (Test-Path $vscdb) { $sys += "state_vscdb_mb=$([math]::Round((Get-Item $vscdb).Length/1MB,1))" }
$sys -join "`n" | Out-File (Join-Path $outDir 'system.txt') -Encoding utf8

$settingsPath = "$env:APPDATA\Cursor\User\settings.json"
if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw
    $raw = $raw -replace '(api[_-]?key|token|password|secret)\s*[:=]\s*"[^"]*"', '$1:"***REDACTED***"'
    $raw | Out-File (Join-Path $outDir 'settings-redacted.json') -Encoding utf8
}

$ssh = "$env:USERPROFILE\.ssh\config"
if (Test-Path $ssh) {
    Get-Content $ssh | Where-Object { $_ -notmatch 'IdentityFile|id_rsa|id_ed25519' } |
        Out-File (Join-Path $outDir 'ssh-config-redacted.txt') -Encoding utf8
}

$logRoot = "$env:APPDATA\Cursor\logs"
$errFile = Join-Path $outDir 'error-excerpts.log'
$patterns = 'error|Error|ERROR|failed|Failed|timeout|UNRESPONSIVE|EPERM|SQLITE|ECONNRESET|trial|usage limit|AppHang|hooks'
$total = 0
$maxBytes = 2000000
if (Test-Path $logRoot) {
    $sessions = Get-ChildItem $logRoot -Directory | Sort-Object Name -Descending | Select-Object -First 5
    foreach ($sess in $sessions) {
        foreach ($lf in (Get-ChildItem $sess.FullName -Recurse -Filter *.log -EA SilentlyContinue)) {
            if ($total -ge $maxBytes) { break }
            $hits = Select-String -Path $lf.FullName -Pattern $patterns -EA SilentlyContinue | Select-Object -First 80
            if ($hits) {
                Add-Content $errFile "===== $($lf.FullName) ====="
                foreach ($h in $hits) {
                    $line = $h.Line
                    if ($line.Length -gt 500) { $line = $line.Substring(0, 500) + '...' }
                    Add-Content $errFile $line
                    $total += $line.Length
                }
            }
        }
    }
}

$cat = Join-Path $env:LOCALAPPDATA 'CursorBoost\error-catalog.json'
if (Test-Path $cat) { Copy-Item $cat (Join-Path $outDir 'error-catalog.json') -Force }

$issueBody = Join-Path $env:TEMP 'cursor-boost-github-issue.md'
$readmePath = Join-Path $outDir 'readme-send-to-admin.txt'
@(
    'Cursor diagnostic pack - send to group admin'
    "Generated: $stamp"
    ''
    'Also send: 1) error screenshot with Request ID  2) this zip  3) what you were doing'
    'Files: scan-result.json, error-excerpts.log, error-catalog.json, settings-redacted.json'
    'No passwords or SSH private keys included.'
) | Out-File $readmePath -Encoding utf8
if (Test-Path $issueBody) { Copy-Item $issueBody (Join-Path $outDir 'github-issue-body.md') -Force }

$zip = Join-Path $desk "CursorReport-$stamp.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force

W "ZIP: $zip"
W "Folder: $outDir"
Start-Process explorer.exe "/select,`"$zip`""
