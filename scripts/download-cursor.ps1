# Record installed Cursor version for release notes (does not redistribute installer)
$exe = "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe"
$out = Join-Path $PSScriptRoot '..\releases\cursor-version.txt'
$rel = Join-Path $PSScriptRoot '..\releases'
New-Item -ItemType Directory -Force -Path $rel | Out-Null
if (Test-Path $exe) {
    $v = (Get-Item $exe).VersionInfo.FileVersion
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm') | Cursor $v | $exe"
    Add-Content $out $line
    Write-Host "Recorded: $line"
} else {
    Write-Host "Cursor not installed. Open https://www.cursor.com/download"
    Start-Process 'https://www.cursor.com/download'
}
