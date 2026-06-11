# Sync issues.json from GitHub (community updates)
param([string]$Repo = 'aiyangdie/cursor-boost', [string]$Branch = 'main')

$Root = Split-Path $PSScriptRoot -Parent
$dest = Join-Path $Root 'issues.json'
$url = "https://raw.githubusercontent.com/$Repo/$Branch/issues.json"
Write-Host "Fetching $url"
try {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Write-Host "Updated: $dest" -ForegroundColor Green
} catch {
    Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
