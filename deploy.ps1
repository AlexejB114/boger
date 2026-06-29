# deploy.ps1 — Build & deploy boger.io via FTPS
# Reads credentials from .env (gitignored)

$envFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Error ".env nicht gefunden. Kopiere .env.example zu .env und trage das Passwort ein."
    exit 1
}

# Parse .env
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
    }
}

$host_   = $env:FTPS_HOST
$port    = $env:FTPS_PORT
$user    = $env:FTPS_USER
$pass    = $env:FTPS_PASS
$remote  = "/httpdocs"
$local   = Join-Path $PSScriptRoot "dist"

Write-Host "Building..." -ForegroundColor Cyan
npm run build --prefix $PSScriptRoot
if ($LASTEXITCODE -ne 0) { Write-Error "Build fehlgeschlagen"; exit 1 }

# Sync dist/ → httpdocs/ lokal (für WebStorm-Deployment-Fallback)
$httpdocs = Join-Path $PSScriptRoot "httpdocs"
Get-ChildItem $httpdocs -File    | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $httpdocs -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$local\*" -Destination $httpdocs -Recurse -Force

Write-Host "Uploading to $host_$remote ..." -ForegroundColor Cyan

# curl FTPS upload (rekursiv via file list)
$files = Get-ChildItem $local -Recurse -File
foreach ($file in $files) {
    $rel      = $file.FullName.Substring($local.Length).Replace('\', '/')
    $remPath  = "$remote$rel"
    $remDir   = ($remPath | Split-Path -Parent).Replace('\', '/')

    # Create remote directory (silently ignore if exists)
    curl.exe --silent --ftp-create-dirs --ftp-ssl --insecure `
        -u "${user}:${pass}" `
        "ftp://${host_}:${port}${remDir}/" --quote "NOOP" 2>$null | Out-Null

    # Upload file
    $result = curl.exe --silent --show-error --ftp-ssl --insecure `
        -u "${user}:${pass}" `
        -T $file.FullName `
        "ftp://${host_}:${port}${remPath}" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ $rel" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $rel — $result" -ForegroundColor Red
    }
}

Write-Host "`nDeploy abgeschlossen! https://$host_" -ForegroundColor Green
