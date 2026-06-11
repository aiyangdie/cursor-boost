# Cursor Boost - SAFE cleanup (only when Cursor is fully closed)
param(
    [switch]$Deep,
    [switch]$Quiet,
    [switch]$DiagnoseOnly,
    [switch]$Force  # skip confirmation when called from trusted launcher
)

$ErrorActionPreference = 'Continue'

function Log($msg, $color = 'White') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

$roaming = Join-Path $env:APPDATA 'Cursor'
$local = Join-Path $env:LOCALAPPDATA 'Cursor'
$backup = Join-Path $PSScriptRoot ("backup\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))

$report = @{
    killed       = 0
    freedBytes   = 0
    fixedHooks   = 0
    clearedLocks = 0
    clearedDirs  = @()
    errors       = @()
    warnings     = @()
    diagnose     = @()
}

function Remove-DirSafe($path) {
    if (-not (Test-Path $path)) { return 0 }
    try {
        $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
        $sz = 0
        if ($files) { $sz = ($files | Measure-Object Length -Sum).Sum }
        Remove-Item $path -Recurse -Force -ErrorAction Stop
        return [long]$sz
    } catch {
        $report.errors += "$path : $($_.Exception.Message)"
        return 0
    }
}

# ---------- DIAGNOSE ----------
$procCount = @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue).Count
$report.diagnose += "Cursor processes: $procCount (recommend <= 12, you have $procCount)"

$hookChecks = @(
    (Join-Path $env:USERPROFILE '.cursor\hooks.json'),
    (Join-Path $env:USERPROFILE 'Downloads\.cursor\hooks.json')
)
foreach ($hp in $hookChecks) {
    if (-not (Test-Path $hp)) {
        $report.diagnose += "MISSING local hooks: $hp"
    } else {
        try {
            $null = Get-Content $hp -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.diagnose += "OK local hooks: $hp"
        } catch {
            $report.diagnose += "BROKEN local hooks: $hp"
        }
    }
}

$mainLog = Get-ChildItem (Join-Path $roaming 'logs') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($mainLog) {
    $rootHits = Select-String -Path (Join-Path $mainLog.FullName 'main.log') -Pattern '\\root\\\.cursor' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($rootHits) {
        $report.warnings += "SSH opened /root workspace - causes Agent errors. Open real project path instead."
        $report.diagnose += "FOUND /root path errors in latest main.log"
    }
}

if ($procCount -gt 15) {
    $report.warnings += "Too many Cursor processes ($procCount). Close extra windows before cleanup."
}

Log ""
Log "========== Cursor Boost ==========" Cyan
foreach ($d in $report.diagnose) { Log "  $d" DarkGray }
foreach ($w in $report.warnings) { Log "  WARN: $w" Yellow }

if ($DiagnoseOnly) {
    $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $env:TEMP 'cursor-boost-last.json') -Encoding UTF8
    return $report
}

# ---------- SAFETY: must close Cursor first ----------
if ($procCount -gt 0) {
    $msg = "Cursor is still running ($procCount processes). Cleanup MUST run after full exit."
    Log ""
    Log $msg Red
    Log "Close ALL Cursor windows, check Task Manager, then run again." Yellow
    Log "Running cleanup while Cursor is open can cause brief glitches (cache half-deleted)." Yellow
    $report.errors += $msg
    $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $env:TEMP 'cursor-boost-last.json') -Encoding UTF8
    exit 2
}

New-Item -ItemType Directory -Force -Path $backup | Out-Null

# ---------- FIX local hooks only (never touch remote /root) ----------
$hookDirs = @(
    (Join-Path $env:USERPROFILE '.cursor'),
    (Join-Path $env:USERPROFILE 'Downloads\.cursor')
)
foreach ($dir in $hookDirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $hooks = Join-Path $dir 'hooks.json'
    $ok = $false
    if (Test-Path $hooks) {
        try {
            $null = Get-Content $hooks -Raw -Encoding UTF8 | ConvertFrom-Json
            $ok = $true
        } catch {
            Copy-Item $hooks (Join-Path $backup 'hooks-broken.json') -Force -ErrorAction SilentlyContinue
            Remove-Item $hooks -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $ok) {
        Set-Content -Path $hooks -Value '{"version":1,"hooks":{}}' -Encoding UTF8 -NoNewline
        $report.fixedHooks++
    }
}

# ---------- CLEAR caches (safe only when Cursor closed) ----------
$cacheDirs = @(
    'Cache', 'Code Cache', 'GPUCache', 'CachedData', 'CachedProfilesData',
    'DawnGraphiteCache', 'DawnWebGPUCache', 'blob_storage', 'Network',
    'Service Worker', 'Session Storage', 'IndexedDB', 'WebStorage',
    'Partitions', 'sentry', 'Crashpad', 'Backups'
)
foreach ($name in $cacheDirs) {
    $p = Join-Path $roaming $name
    $sz = Remove-DirSafe $p
    if ($sz -gt 0) {
        $report.freedBytes += $sz
        $report.clearedDirs += $name
    }
}

if (Test-Path $local) {
    foreach ($name in @('Cache', 'Code Cache', 'GPUCache', 'CachedData')) {
        $report.freedBytes += (Remove-DirSafe (Join-Path $local $name))
    }
}

$logs = Join-Path $roaming 'logs'
if (Test-Path $logs) {
    $days = if ($Deep) { 0 } else { 1 }
    $cutoff = (Get-Date).AddDays(-$days)
    Get-ChildItem $logs -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object { $report.freedBytes += (Remove-DirSafe $_.FullName) }
}

# lock files - only when Cursor is closed
$lockRoots = @(
    (Join-Path $roaming 'User\workspaceStorage'),
    (Join-Path $roaming 'User\globalStorage')
)
foreach ($root in $lockRoots) {
    if (-not (Test-Path $root)) { continue }
    foreach ($pat in @('*.lock', 'state.vscdb-journal')) {
        Get-ChildItem $root -Recurse -Filter $pat -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                $report.clearedLocks++
            }
    }
}

# settings.json - backup first, only add missing keys (do not rewrite every time)
$settingsPath = Join-Path $roaming 'User\settings.json'
if (Test-Path $settingsPath) {
    try {
        Copy-Item $settingsPath (Join-Path $backup 'settings.json.bak') -Force
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $changed = $false
        foreach ($kv in @(
            @{ n = 'remote.SSH.connectTimeout'; v = 60 },
            @{ n = 'cursor.general.disableHttp2'; v = $true },
            @{ n = 'remote.SSH.useLocalServer'; v = $false }
        )) {
            $prop = $settings.PSObject.Properties[$kv.n]
            if (-not $prop) {
                $settings | Add-Member -NotePropertyName $kv.n -NotePropertyValue $kv.v -Force
                $changed = $true
            }
        }
        if ($changed) {
            $settings | ConvertTo-Json -Depth 8 | Set-Content $settingsPath -Encoding UTF8
        }
    } catch {
        $report.errors += "settings.json: $($_.Exception.Message)"
    }
}

$report.freedMB = [math]::Round($report.freedBytes / 1MB, 1)
$reportPath = Join-Path $env:TEMP 'cursor-boost-last.json'
$report | ConvertTo-Json -Depth 5 | Set-Content $reportPath -Encoding UTF8

Log ""
Log "========== Done ==========" Cyan
Log ("Freed: " + $report.freedMB + " MB | Locks: " + $report.clearedLocks + " | Hooks fixed: " + $report.fixedHooks) Green
if ($report.errors.Count) { Log ("Errors: " + $report.errors.Count) Yellow }
Log "You can reopen Cursor now." Cyan
Log ""

return $report
