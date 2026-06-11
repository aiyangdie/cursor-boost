# Cursor 一键修复：SSH /root 缓存、hooks、设置、性能缓存
# 加 -NoRestart 则不关闭 Cursor（等同 fix-live.ps1 + 清缓存）
param([switch]$NoRestart)
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$Backup = Join-Path $Root ("backup\fix-all-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $Backup | Out-Null

function Log($msg, $c='White') { Write-Host $msg -ForegroundColor $c }

Log ""
Log "========== Cursor 一键修复 ==========" Cyan

# 0) 关闭 Cursor（-NoRestart 时跳过）
if (-not $NoRestart) {
  $procs = Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue
  if ($procs) {
    Log "关闭 $($procs.Count) 个 Cursor 进程..." Yellow
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
  }
} else {
  Log "保持 Cursor 运行（NoRestart）" DarkGray
}

$fixed = @()

# 1) hooks.json
foreach ($dir in @(
  (Join-Path $env:USERPROFILE '.cursor'),
  (Join-Path $env:USERPROFILE 'Downloads\.cursor')
)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $hooks = Join-Path $dir 'hooks.json'
  Set-Content -Path $hooks -Value '{"version":1,"hooks":{}}' -Encoding UTF8 -NoNewline
  $fixed += "hooks: $hooks"
}

# 2) 清除所有打开 /root 的 workspace 缓存（Agent 报错主因）
$wsBase = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
if (Test-Path $wsBase) {
  Get-ChildItem $wsBase -Directory | ForEach-Object {
    $wj = Join-Path $_.FullName 'workspace.json'
    if (-not (Test-Path $wj)) { return }
    $raw = Get-Content $wj -Raw -Encoding UTF8
    if ($raw -match '/root"') {
      Copy-Item $_.FullName (Join-Path $Backup ("ws-" + $_.Name)) -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
      $fixed += "removed /root workspace: $($_.Name)"
    }
  }
}

# 3) 清理 storage.json 里记住的 /root 窗口（避免重启又打开 /root）
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

def is_root_remote(uri):
    if not uri or not isinstance(uri, str):
        return False
    return 'ssh-remote' in uri and uri.rstrip('/').endswith('/root')

bw = data.get('backupWorkspaces', {})
bw['folders'] = [f for f in bw.get('folders', []) if not is_root_remote(f.get('folderUri', ''))]
data['backupWorkspaces'] = bw

pa = data.get('profileAssociations', {})
ws = pa.get('workspaces', {})
pa['workspaces'] = {k: v for k, v in ws.items() if not is_root_remote(k)}
data['profileAssociations'] = pa

ws_state = data.get('windowsState', {})
opened = [w for w in ws_state.get('openedWindows', []) if not is_root_remote(w.get('folder', ''))]
ws_state['openedWindows'] = opened
last = ws_state.get('lastActiveWindow', {})
if is_root_remote(last.get('folder', '')):
    ws_state['lastActiveWindow'] = {
        'folder': local,
        'backupPath': last.get('backupPath', ''),
        'uiState': last.get('uiState', {}),
    }
data['windowsState'] = ws_state
p.write_text(json.dumps(data, ensure_ascii=False, indent=4), encoding='utf-8')
print('storage.json cleaned')
"@
  $fixed += 'storage.json: removed /root window memory'
}

# 4) settings.json - password SSH + stability
$settingsPath = Join-Path $env:APPDATA 'Cursor\User\settings.json'
$settings = @{}
if (Test-Path $settingsPath) {
  Copy-Item $settingsPath (Join-Path $Backup 'settings.json.bak') -Force
  $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
if (-not $settings.'remote.SSH.remotePlatform') {
  $settings | Add-Member -NotePropertyName 'remote.SSH.remotePlatform' -NotePropertyValue (@{}) -Force
}
$linuxHosts = @(
  '8.137.58.96','120.26.44.193','49.232.48.193','115.190.23.142',
  '121.4.102.119','121.40.222.49','211.154.17.5','myserver'
)
foreach ($h in $linuxHosts) { $settings.'remote.SSH.remotePlatform'.$h = 'linux' }
$kv = @{
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
foreach ($k in $kv.Keys) {
  $settings | Add-Member -NotePropertyName $k -NotePropertyValue $kv[$k] -Force
}
# Remove invalid keys if present
@('remote.SSH.serverInstallPath') | ForEach-Object {
  if ($settings.PSObject.Properties.Name -contains $_) {
    $settings.PSObject.Properties.Remove($_)
  }
}
$settings | ConvertTo-Json -Depth 8 | Set-Content $settingsPath -Encoding UTF8
$fixed += 'settings.json updated (password SSH)'

# 4b) SSH config - enable password login for all hosts
$sshDir = Join-Path $env:USERPROFILE '.ssh'
$sshConfig = Join-Path $sshDir 'config'
$sshTemplate = Join-Path $Root 'ssh-config.template'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
if (Test-Path $sshConfig) {
  Copy-Item $sshConfig (Join-Path $Backup 'ssh-config.bak') -Force
}
if (Test-Path $sshTemplate) {
  Copy-Item $sshTemplate $sshConfig -Force
  $fixed += 'ssh config: password login enabled, ports fixed'
}

# 5) 性能缓存（NoRestart 时跳过，避免开着 Cursor 删缓存）
if (-not $NoRestart) {
  & (Join-Path $Root 'boost.ps1') -Quiet | Out-Null
  $fixed += 'cache cleaned (boost.ps1)'
} else {
  $fixed += 'cache skip (Cursor running)'
}

Log ""
Log "========== 修复完成 ==========" Green
foreach ($f in $fixed) { Log "  [OK] $f" DarkGray }
Log ""
Log "备份: $Backup" DarkGray
Log ""
Log "下一步:" Yellow
Log "  1. 打开 Cursor -> Remote-SSH -> 选服务器"
Log "  2. 底部会弹出【终端】，在里面输入 root 密码（密码登录）"
Log "  3. 连上后打开具体项目目录，不要打开 /root"
Log "  4. Agent 云端报错: Sign out -> Sign in"
Log "  5. 远程 hooks: fix-remote.bat root@你的IP"
Log ""
