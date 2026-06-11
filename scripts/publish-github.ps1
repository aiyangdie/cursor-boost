# Publish to GitHub - RUN ONLY WHEN USER EXPLICITLY APPROVES
# Usage:
#   $env:GITHUB_TOKEN = 'ghp_xxx'   # NEVER commit token
#   powershell -ExecutionPolicy Bypass -File scripts/publish-github.ps1

param(
    [string]$Repo = 'aiyangdie/cursor-boost',
    [string]$Version = '1.4.0',
    [string]$Message = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

if (-not $env:GITHUB_TOKEN) {
    Write-Host 'Set GITHUB_TOKEN first. Do NOT save token in files.' -ForegroundColor Red
    exit 1
}

Push-Location $Root
try {
    if (-not (Test-Path '.git')) {
        git init
        git branch -M main
    }
    git add -A
    git status
    if (-not $Message) { $Message = "release: Cursor Boost v$Version" }
    git commit -m $Message 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host 'Nothing to commit or commit failed' }

    $remote = "https://$($env:GITHUB_TOKEN)@github.com/$Repo.git"
    git remote remove origin 2>$null
    git remote add origin $remote
    git push -u origin main

    Write-Host "Pushed to https://github.com/$Repo" -ForegroundColor Green
    Write-Host 'Create Release manually or: gh release create v$Version dist/CursorBoost.exe'
} finally {
    git remote set-url origin "https://github.com/$Repo.git" 2>$null
    Pop-Location
}
