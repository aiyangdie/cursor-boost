# Cursor Boost Engine - unified actions for GUI
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet(
        'Diagnose','FixLive','FixFull','CleanCache','DeepClean',
        'FixHooks','FixSsh','FixSettings','CleanRoot',
        'ClearAuthCache','KillCursor','StartCursor','RestartCursor',
        'OpenLogs','OpenData','OpenInstall','OpenDownload',
        'ScanLogs','TrialLimitHelp','UsageLimitHelp','OpenSupport','OpenPricing',
        'FixLocks','FixFlashExit','FixRemote','ExportReport','SmartFix','ReloadWindowHelp',
        'OpenGitHubIssue','OpenCatalog','OpenSubmissions'
    )]
    [string]$Action,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Backup = Join-Path $Root ("backup\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$ReportPath = Join-Path $env:TEMP 'cursor-boost-action.json'

function W($msg) { if (-not $Quiet) { Write-Output $msg } }

$report = @{ action = $Action; ok = $true; lines = @(); errors = @() }
function R($line) { $report.lines += $line; W $line }

function Fix-Hooks {
    foreach ($dir in @(
        (Join-Path $env:USERPROFILE '.cursor'),
        (Join-Path $env:USERPROFILE 'Downloads\.cursor')
    )) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content (Join-Path $dir 'hooks.json') '{"version":1,"hooks":{}}' -Encoding UTF8 -NoNewline
        R "hooks OK: $dir"
    }
}

function Clean-RootWorkspaces {
    $wsBase = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
    if (-not (Test-Path $wsBase)) { return }
    Get-ChildItem $wsBase -Directory | ForEach-Object {
        $wj = Join-Path $_.FullName 'workspace.json'
        if ((Test-Path $wj) -and ((Get-Content $wj -Raw) -match '/root"')) {
            Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue
            R "removed /root cache: $($_.Name)"
        }
    }
    $storagePath = Join-Path $env:APPDATA 'Cursor\User\globalStorage\storage.json'
    if (Test-Path $storagePath) {
        $dl = Join-Path $env:USERPROFILE 'Downloads'
        $localUri = 'file:///' + ($dl -replace '\\','/') -replace ':','%3A'
        python -c @"
import json
from pathlib import Path
p=Path(r'$storagePath')
d=json.loads(p.read_text(encoding='utf-8'))
local=r'$localUri'
def ir(u): return isinstance(u,str) and 'ssh-remote' in u and u.rstrip('/').endswith('/root')
bw=d.get('backupWorkspaces',{}); bw['folders']=[f for f in bw.get('folders',[]) if not ir(f.get('folderUri',''))]; d['backupWorkspaces']=bw
pa=d.get('profileAssociations',{}); pa['workspaces']={k:v for k,v in pa.get('workspaces',{}).items() if not ir(k)}; d['profileAssociations']=pa
ws=d.get('windowsState',{}); ws['openedWindows']=[w for w in ws.get('openedWindows',[]) if not ir(w.get('folder',''))]
if ir(ws.get('lastActiveWindow',{}).get('folder','')): ws['lastActiveWindow']={'folder':local,'uiState':{}}
d['windowsState']=ws; p.write_text(json.dumps(d,ensure_ascii=False,indent=4),encoding='utf-8')
"@
        R 'storage.json: /root removed'
    }
}

function Fix-Settings {
    $settingsPath = Join-Path $env:APPDATA 'Cursor\User\settings.json'
    if (-not (Test-Path $settingsPath)) { $settingsPath | Out-Null; '{}' | Set-Content $settingsPath }
    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    if ($raw.StartsWith([char]0xFEFF)) { $raw = $raw.Substring(1) }
    $settings = $raw | ConvertFrom-Json
    if (-not $settings.'remote.SSH.remotePlatform') {
        $settings | Add-Member -NotePropertyName 'remote.SSH.remotePlatform' -NotePropertyValue (@{}) -Force
    }
    foreach ($h in @('8.137.58.96','120.26.44.193','49.232.48.193','115.190.23.142','121.4.102.119','121.40.222.49','211.154.17.5','myserver')) {
        $settings.'remote.SSH.remotePlatform'.$h = 'linux'
    }
    $kv = @{
        'remote.SSH.connectTimeout'=120; 'remote.SSH.useLocalServer'=$false
        'cursor.general.disableHttp2'=$true; 'cursor.agent.enabled'=$true
        'remote.SSH.showLoginTerminal'=$true; 'remote.SSH.enableDynamicForwarding'=$true
        'remote.SSH.enableRemoteCommand'=$true; 'remote.SSH.useExecServer'=$false
        'remote.SSH.allowLocalServerDownload'=$true; 'remote.SSH.localServerDownload'='auto'
        'remote.SSH.logLevel'='info'
    }
    foreach ($k in $kv.Keys) { $settings | Add-Member -NotePropertyName $k -NotePropertyValue $kv[$k] -Force }
    if ($settings.PSObject.Properties.Name -contains 'remote.SSH.serverInstallPath') {
        $settings.PSObject.Properties.Remove('remote.SSH.serverInstallPath')
    }
    $settings | ConvertTo-Json -Depth 8 | Set-Content $settingsPath -Encoding UTF8
    R 'settings.json updated'
}

function Fix-SshConfig {
    $tpl = Join-Path $Root 'ssh-config.template'
    $cfg = Join-Path $env:USERPROFILE '.ssh\config'
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    if (Test-Path $tpl) { Copy-Item $tpl $cfg -Force; R 'ssh config: password login enabled' }
}

function Fix-Locks {
    $p = Get-Process Cursor -EA SilentlyContinue
    if ($p) {
        $p | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep -Seconds 2
        R 'Cursor closed before lock cleanup'
    }
    foreach ($f in @(
        (Join-Path $env:APPDATA 'Cursor\User\globalStorage\storage.json.vsctmp'),
        (Join-Path $env:APPDATA 'Cursor\code.lock')
    )) {
        if (Test-Path $f) {
            Remove-Item $f -Force -EA SilentlyContinue
            R "removed lock: $f"
        }
    }
    foreach ($root in @(
        (Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'),
        (Join-Path $env:APPDATA 'Cursor\User\globalStorage')
    )) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Recurse -Include '*.lock','state.vscdb-journal' -EA SilentlyContinue |
            ForEach-Object {
                Remove-Item $_.FullName -Force -EA SilentlyContinue
                R "removed: $($_.Name)"
            }
    }
    R 'Lock files cleared'
}

function Clear-AuthCache {
    $roaming = Join-Path $env:APPDATA 'Cursor'
    foreach ($name in @('Network','Session Storage','Local Storage','WebStorage')) {
        $p = Join-Path $roaming $name
        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force -EA SilentlyContinue
            R "cleared auth: $name"
        }
    }
}

New-Item -ItemType Directory -Force -Path $Backup | Out-Null

switch ($Action) {
    'Diagnose' {
        $n = @(Get-Process Cursor -EA SilentlyContinue).Count
        R "Cursor processes: $n (recommend <= 12)"
        foreach ($hp in @("$env:USERPROFILE\.cursor\hooks.json","$env:USERPROFILE\Downloads\.cursor\hooks.json")) {
            if (-not (Test-Path $hp)) { R "MISSING: $hp" }
            else { try { $null = Get-Content $hp -Raw | ConvertFrom-Json; R "OK: $hp" } catch { R "BROKEN: $hp" } }
        }
        $gs = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
        if (Test-Path $gs) { R ("state.vscdb: " + [math]::Round((Get-Item $gs).Length/1MB,1) + " MB") }
        $rootCount = 0
        $ws = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
        if (Test-Path $ws) {
            Get-ChildItem $ws -Directory | ForEach-Object {
                $wj = Join-Path $_.FullName 'workspace.json'
                if ((Test-Path $wj) -and ((Get-Content $wj -Raw) -match '/root"')) { $rootCount++ }
            }
        }
        if ($rootCount -gt 0) { R "WARN: $rootCount /root workspace caches (use Clean Root)" }
        else { R "OK: no /root workspace cache" }
    }
    'FixLive' {
        Fix-Hooks; Clean-RootWorkspaces; Fix-Settings; Fix-SshConfig
        R 'Done. Use Reload Window in Cursor (Ctrl+Shift+P)'
    }
    'FixFull' {
        $p = Get-Process Cursor -EA SilentlyContinue
        if ($p) { $p | Stop-Process -Force -EA SilentlyContinue; Start-Sleep 2; R "Cursor closed" }
        Fix-Hooks; Clean-RootWorkspaces; Fix-Settings; Fix-SshConfig
        & (Join-Path $Root 'boost.ps1') -Quiet | Out-Null
        R 'Full fix done. Reopen Cursor.'
    }
    'CleanCache' {
        $p = Get-Process Cursor -EA SilentlyContinue
        if ($p) { $report.ok = $false; $report.errors += 'Close Cursor first'; R 'ERROR: Close Cursor first!' }
        else {
            $r = & (Join-Path $Root 'boost.ps1') -Quiet
            R ("Freed ~$($r.freedMB) MB, locks $($r.clearedLocks)")
        }
    }
    'DeepClean' {
        $p = Get-Process Cursor -EA SilentlyContinue
        if ($p) { $p | Stop-Process -Force -EA SilentlyContinue; Start-Sleep 2 }
        & (Join-Path $Root 'boost.ps1') -Deep -Quiet | Out-Null
        R 'Deep clean done'
    }
    'FixHooks' { Fix-Hooks; R 'hooks fixed' }
    'FixSsh' { Fix-SshConfig; R 'ssh fixed' }
    'FixSettings' { Fix-Settings; R 'settings fixed' }
    'CleanRoot' { Clean-RootWorkspaces; R 'root workspaces cleaned' }
    'ClearAuthCache' {
        $p = Get-Process Cursor -EA SilentlyContinue
        if ($p) { $p | Stop-Process -Force -EA SilentlyContinue; Start-Sleep 2; R 'Cursor closed for auth clear' }
        Clear-AuthCache; Fix-Settings
        R 'Auth cache cleared. Sign in again when opening Cursor.'
    }
    'KillCursor' {
        $p = Get-Process Cursor -EA SilentlyContinue
        if ($p) { $p | Stop-Process -Force; R "Killed $($p.Count) processes" } else { R 'Cursor not running' }
    }
    'StartCursor' {
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'
        if (Test-Path $exe) { Start-Process $exe; R 'Cursor started' } else { $report.ok=$false; R 'Cursor.exe not found' }
    }
    'RestartCursor' {
        Get-Process Cursor -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep 2
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'
        if (Test-Path $exe) { Start-Process $exe; R 'Cursor restarted' }
        else { $report.ok=$false; R 'Cursor.exe not found' }
    }
    'OpenLogs' { Start-Process explorer.exe (Join-Path $env:APPDATA 'Cursor\logs') }
    'OpenData' { Start-Process explorer.exe (Join-Path $env:APPDATA 'Cursor') }
    'OpenInstall' {
        $d = Join-Path $env:LOCALAPPDATA 'Programs\cursor'
        if (Test-Path $d) { Start-Process explorer.exe $d } else { Start-Process 'https://www.cursor.com/download' }
    }
    'OpenDownload' { Start-Process 'https://www.cursor.com/download' }
    'OpenPricing' { Start-Process 'https://www.cursor.com/pricing' }
    'OpenSupport' { Start-Process 'https://cursor.com/contact' }
    'TrialLimitHelp' {
        R '=== Too many free trials ==='
        R 'SERVER-SIDE machine limit. Cache clear cannot bypass.'
        R '1) Upgrade Pro  2) Contact support + Request ID  3) Sign in Pro account'
        Start-Process 'https://www.cursor.com/pricing'
    }
    'UsageLimitHelp' {
        R '=== Agent usage limit ==='
        R 'This account monthly Agent quota is used up (not the same as trial machine limit).'
        R '1) Wait for quota reset  2) Upgrade Pro  3) Sign in another account with quota'
        Start-Process 'https://www.cursor.com/pricing'
    }
    'FixLocks' { Fix-Locks; R 'locks fixed' }
    'FixFlashExit' {
        $flash = Join-Path $Root 'fix-flash.ps1'
        if (Test-Path $flash) {
            & $flash -DisableGPU -Quiet | ForEach-Object { R $_ }
            R 'Flash exit fix done'
        } else { $report.ok=$false; R 'fix-flash.ps1 not found' }
    }
    'FixRemote' {
        $bat = Join-Path $Root 'fix-remote.bat'
        if (Test-Path $bat) {
            Start-Process 'cmd.exe' -ArgumentList '/k', "cd /d `"$Root`" && fix-remote.bat"
            R 'Opened remote SSH fix window - enter password when prompted'
            R 'Default host: root@121.40.222.49 port 22'
        } else { $report.ok=$false; R 'fix-remote.bat not found' }
    }
    'ExportReport' {
        $exp = Join-Path $Root 'export-report.ps1'
        if (Test-Path $exp) {
            & $exp -Quiet | ForEach-Object { R $_ }
            R 'Diagnostic ZIP created on Desktop - send to group admin'
        } else { $report.ok=$false; R 'export-report.ps1 not found' }
    }
    'ReloadWindowHelp' {
        R 'In Cursor press: Ctrl+Shift+P'
        R 'Type: Reload Window -> Enter'
        R 'This reloads extensions WITHOUT full quit (try before restart)'
    }
    'SmartFix' {
        R '=== Smart fix (minimize restart) ==='
        $hotActions = @()
        $needRestart = @()
        $manual = @()
        $scanPath = Join-Path $env:TEMP 'cursor-boost-scan.json'
        if (-not (Test-Path $scanPath)) {
            $scanner = Join-Path $Root 'log_scanner.py'
            if (Test-Path $scanner) { python $scanner 2>$null | Out-Null }
        }
        if (Test-Path $scanPath) {
            $s = Get-Content $scanPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($i in $s.issues) {
                $fa = $i.fix_action
                if ($i.manual_only -or $fa -in @('TrialLimitHelp','UsageLimitHelp')) {
                    $manual += $i.title
                } elseif ($fa -in @('RestartCursor','FixFull','CleanCache','DeepClean','ClearAuthCache','FixFlashExit','FixLocks')) {
                    $needRestart += $i.title
                } else {
                    $hotActions += $fa
                }
            }
        }
        $hotActions = $hotActions | Select-Object -Unique
        if ($hotActions.Count -eq 0) { $hotActions = @('FixLive') }
        R ("Hot-fix actions: $($hotActions -join ', ')")
        Fix-Hooks
        Clean-RootWorkspaces
        Fix-Settings
        Fix-SshConfig
        R 'Hot fix applied (hooks/settings/ssh/root)'
        if ($manual.Count) { R ("MANUAL ONLY: $($manual -join '; ')") }
        if ($needRestart.Count) {
            R ("Still may need restart for: $($needRestart -join '; ')")
            R 'Try Reload Window first (Ctrl+Shift+P)'
        } else {
            R 'No full restart required for detected issues'
        }
        R 'Next: Ctrl+Shift+P -> Reload Window'
    }
    'OpenGitHubIssue' {
        Start-Process 'https://github.com/aiyangdie/cursor-boost/issues/new?template=cursor-error.yml'
        R 'Opened GitHub new issue page (paste exported zip + screenshot)'
    }
    'OpenCatalog' {
        $cat = Join-Path $env:LOCALAPPDATA 'CursorBoost\error-catalog.json'
        if (Test-Path $cat) { Start-Process explorer.exe "/select,`"$cat`""; R "Catalog: $cat" }
        else { R 'Catalog empty - run scan first' }
    }
    'OpenSubmissions' {
        $sub = Join-Path $env:LOCALAPPDATA 'CursorBoost\submissions'
        New-Item -ItemType Directory -Force -Path $sub | Out-Null
        Start-Process explorer.exe $sub
        R "Submissions folder: $sub"
    }
    'ScanLogs' {
        $scanner = Join-Path $Root 'log_scanner.py'
        if (Test-Path $scanner) {
            python $scanner | Out-Null
            $scanOut = Join-Path $env:TEMP 'cursor-boost-scan.json'
            if (Test-Path $scanOut) {
                $s = Get-Content $scanOut -Raw -Encoding UTF8 | ConvertFrom-Json
                R ("Scanned logs. Issues found: $($s.issue_count)")
                R ("Cursor processes: $($s.cursor_processes)")
                R ("Latest log: $($s.latest_log_session)")
                foreach ($i in $s.issues) { R ("  [!] $($i.title)") }
            }
        } else { $report.ok=$false; R 'log_scanner.py not found' }
    }
}

$report | ConvertTo-Json -Depth 4 | Set-Content $ReportPath -Encoding UTF8
if (-not $report.ok) { exit 1 }
