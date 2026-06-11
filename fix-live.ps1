# 热修复：不关闭 Cursor，修复 SSH 密码登录 + /root 问题
param([switch]$Quiet)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$Backup = Join-Path $Root ("backup\fix-live-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $Backup | Out-Null

function Log($msg, $c='White') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $c } }

Log ""
Log "========== Cursor 热修复（不重启）==========" Cyan

$procCount = @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue).Count
Log "Cursor 进程: $procCount （保持运行）" DarkGray

$fixed = @()

# 1) hooks
foreach ($dir in @(
  (Join-Path $env:USERPROFILE '.cursor'),
  (Join-Path $env:USERPROFILE 'Downloads\.cursor')
)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Set-Content (Join-Path $dir 'hooks.json') -Value '{"version":1,"hooks":{}}' -Encoding UTF8 -NoNewline
  $fixed += "hooks OK: $dir"
}

# 2) remove /root workspace cache
$wsBase = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
if (Test-Path $wsBase) {
  Get-ChildItem $wsBase -Directory | ForEach-Object {
    $wj = Join-Path $_.FullName 'workspace.json'
    if ((Test-Path $wj) -and ((Get-Content $wj -Raw) -match '/root"')) {
      Copy-Item $_.FullName (Join-Path $Backup ("ws-" + $_.Name)) -Recurse -Force -EA SilentlyContinue
      Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue
      $fixed += "removed /root ws: $($_.Name)"
    }
  }
}

# 3) storage.json - remove /root window memory
$storagePath = Join-Path $env:APPDATA 'Cursor\User\globalStorage\storage.json'
if (Test-Path $storagePath) {
  Copy-Item $storagePath (Join-Path $Backup 'storage.json.bak') -Force
  $dl = Join-Path $env:USERPROFILE 'Downloads'
  $localUri = 'file:///' + ($dl -replace '\\','/') -replace ':','%3A'
  python -c @"
import json
from pathlib import Path
p = Path(r'$storagePath')
data = json.loads(p.read_text(encoding='utf-8'))
local = r'$localUri'

def is_root(u):
    return isinstance(u, str) and 'ssh-remote' in u and u.rstrip('/').endswith('/root')

bw = data.get('backupWorkspaces', {})
bw['folders'] = [f for f in bw.get('folders', []) if not is_root(f.get('folderUri', ''))]
data['backupWorkspaces'] = bw
pa = data.get('profileAssociations', {})
pa['workspaces'] = {k: v for k, v in pa.get('workspaces', {}).items() if not is_root(k)}
data['profileAssociations'] = pa
ws = data.get('windowsState', {})
ws['openedWindows'] = [w for w in ws.get('openedWindows', []) if not is_root(w.get('folder', ''))]
if is_root(ws.get('lastActiveWindow', {}).get('folder', '')):
    ws['lastActiveWindow'] = {'folder': local, 'uiState': ws.get('lastActiveWindow', {}).get('uiState', {})}
data['windowsState'] = ws
p.write_text(json.dumps(data, ensure_ascii=False, indent=4), encoding='utf-8')
print('storage.json OK')
"@
  $fixed += 'storage.json: /root removed'
}

# 4) settings.json - password SSH
$settingsPath = Join-Path $env:APPDATA 'Cursor\User\settings.json'
Copy-Item $settingsPath (Join-Path $Backup 'settings.json.bak') -Force -EA SilentlyContinue
$settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $settings.'remote.SSH.remotePlatform') {
  $settings | Add-Member -NotePropertyName 'remote.SSH.remotePlatform' -NotePropertyValue (@{}) -Force
}
foreach ($h in @('8.137.58.96','120.26.44.193','49.232.48.193','115.190.23.142','121.4.102.119','121.40.222.49','211.154.17.5','myserver')) {
  $settings.'remote.SSH.remotePlatform'.$h = 'linux'
}
$kv = [ordered]@{
  'remote.SSH.connectTimeout' = 120
  'remote.SSH.useLocalServer' = $false
  'cursor.general.disableHttp2' = $true
  'cursor.agent.enabled' = $true
  'remote.SSH.showLoginTerminal' = $true
  'remote.SSH.enableDynamicForwarding' = $true
  'remote.SSH.enableRemoteCommand' = $true
  'remote.SSH.useExecServer' = $false
  'remote.SSH.allowLocalServerDownload' = $true
  'remote.SSH.localServerDownload' = 'auto'
  'remote.SSH.logLevel' = 'info'
}
foreach ($k in $kv.Keys) { $settings | Add-Member -NotePropertyName $k -NotePropertyValue $kv[$k] -Force }
if ($settings.PSObject.Properties.Name -contains 'remote.SSH.serverInstallPath') {
  $settings.PSObject.Properties.Remove('remote.SSH.serverInstallPath')
}
$settings | ConvertTo-Json -Depth 8 | Set-Content $settingsPath -Encoding UTF8
$fixed += 'settings.json: password SSH'

# 5) ssh config
$sshTemplate = Join-Path $Root 'ssh-config.template'
$sshConfig = Join-Path $env:USERPROFILE '.ssh\config'
if (Test-Path $sshTemplate) {
  Copy-Item $sshConfig (Join-Path $Backup 'ssh-config.bak') -Force -EA SilentlyContinue
  Copy-Item $sshTemplate $sshConfig -Force
  $fixed += 'ssh config: password login'
}

Log ""
Log "========== 完成 ==========" Green
foreach ($f in $fixed) { Log "  $f" DarkGray }
Log ""
Log "In Cursor: Ctrl+Shift+P -> Reload Window" Yellow
Log "Then Remote-SSH connect, type password in terminal" Yellow
Log ""
