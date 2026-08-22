# KSPlayer demo deploy script: download latest CI IPA -> sign (zsign) -> install (tidevice).
#
# Requirements:
#   - GitHub token: set $env:GITHUB_TOKEN or edit TOKEN below (or read from repo SKILL.md)
#   - tidevice:     python -m pip install tidevice
#   - zsign:        Tools/Deploy/zsign/zsign.exe (downloaded already)
#   - Signing identity (for the sign step): Tools/Deploy/certs/:
#         *.p12  +  *.mobileprovision  (password in $env:SIGN_PASSWORD or -SignPassword)
#       If no certs are present, the script downloads + installs the UNSIGNED ipa,
#       which the device will reject — you must sign via 爱思助手 in that case.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File Tools\Deploy\deploy.ps1                    # latest green run
#   powershell -ExecutionPolicy Bypass -File Tools\Deploy\deploy.ps1 -Commit <sha>     # specific commit
#   powershell -ExecutionPolicy Bypass -File Tools\Deploy\deploy.ps1 -SkipSign         # skip signing (unsignable -> 爱思助手)
#   powershell -ExecutionPolicy Bypass -File Tools\Deploy\deploy.ps1 -SkipInstall      # only download+sign

param(
    [string]$Commit = "",
    [string]$SignPassword = "",
    [switch]$SkipSign,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$Repo = "826944520/KSPlayer"
$DeployDir = Join-Path $PSScriptRoot "."
$Downloads = Join-Path $DeployDir "downloads"
$CertsDir = Join-Path $DeployDir "certs"
New-Item -ItemType Directory -Path $Downloads -Force | Out-Null

# ---- token ----
$token = $env:GITHUB_TOKEN
if (-not $token) {
    $sk = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) "SKILL.md") -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "^ghp_" } | Select-Object -First 1
    if ($sk) { $token = $sk.Trim() }
}
if (-not $token) { throw "No GitHub token: set env GITHUB_TOKEN or put ghp_* line in SKILL.md" }
$headers = @{ Authorization = "Bearer $token"; "User-Agent" = "KSPlayer-deploy"; Accept = "application/vnd.github+json" }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- 1. find the run ----
$base = "https://api.github.com/repos/$Repo"
if ($Commit) {
    $runs = (Invoke-RestMethod -Uri "$base/actions/runs?per_page=30" -Headers $headers).workflow_runs
    $run = $runs | Where-Object { $_.head_sha -eq $Commit } | Select-Object -First 1
    if (-not $run) { throw "No run found for commit $Commit" }
} else {
    $runs = (Invoke-RestMethod -Uri "$base/actions/runs?per_page=10" -Headers $headers).workflow_runs
    $run = $runs | Where-Object { $_.conclusion -eq "success" -and $_.name -eq "build" } | Select-Object -First 1
    if (-not $run) { throw "No successful build run found" }
}
Write-Host "[1/5] run #$($run.id) commit=$($run.head_sha.Substring(0,7)) conclusion=$($run.conclusion)"

# ---- 2. download artifact ----
$artifacts = (Invoke-RestMethod -Uri "$base/actions/runs/$($run.id)/artifacts" -Headers $headers).artifacts
$art = $artifacts | Where-Object { $_.name -eq "DemoApp-unsigned-ipa" } | Select-Object -First 1
if (-not $art) { throw "Artifact DemoApp-unsigned-ipa not found in run $($run.id)" }
$zipPath = Join-Path $Downloads "demo-ipa-$($run.id).zip"
Write-Host "[2/5] downloading artifact ($([math]::Round($art.size_in_bytes/1MB,1)) MB)"
# Use the artifact-scoped URL: the run-scoped one 404s for runs that were
# re-run (GitHub quirk) even though the artifact itself is fine.
Invoke-WebRequest -Uri "$base/actions/artifacts/$($art.id)/zip" -Headers $headers -OutFile $zipPath -UseBasicParsing -MaximumRedirection 5

# ---- 3. extract the .ipa ----
$ipaDir = Join-Path $Downloads "ipa-$($run.id)"
if (Test-Path $ipaDir) { Remove-Item $ipaDir -Recurse -Force }
New-Item -ItemType Directory -Path $ipaDir -Force | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $ipaDir -Force
$ipa = Get-ChildItem $ipaDir -Recurse -Filter "*.ipa" | Select-Object -First 1
if (-not $ipa) { throw "No .ipa inside artifact" }
Write-Host "[3/5] extracted $($ipa.FullName) ($([math]::Round($ipa.Length/1MB,1)) MB)"

# ---- 4. sign ----
$signedIpa = $ipa.FullName
if (-not $SkipSign) {
    $key = Get-ChildItem $CertsDir -Filter "key.pem" -ErrorAction SilentlyContinue | Select-Object -First 1
    $cert = Get-ChildItem $CertsDir -Filter "cert.pem" -ErrorAction SilentlyContinue | Select-Object -First 1
    $p12 = Get-ChildItem $CertsDir -Filter "*.p12" -ErrorAction SilentlyContinue | Select-Object -First 1
    $prov = Get-ChildItem $CertsDir -Filter "*.mobileprovision" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($key -and $cert -and $prov) {
        $outIpa = Join-Path $Downloads "DemoApp-signed-$($run.id).ipa"
        Write-Host "[4/5] signing with $($key.Name) + $($cert.Name) + $($prov.Name) ..."
        $zsign = Join-Path $DeployDir "zsign\zsign.exe"
        & $zsign -k $key.FullName -c $cert.FullName -m $prov.FullName -o $outIpa $ipa.FullName
        if ($LASTEXITCODE -ne 0) { throw "zsign failed (exit $LASTEXITCODE)" }
        $signedIpa = $outIpa
        Write-Host "      signed -> $outIpa"
    } elseif ($p12 -and $prov) {
        $password = if ($SignPassword) { $SignPassword } else { $env:SIGN_PASSWORD }
        $outIpa = Join-Path $Downloads "DemoApp-signed-$($run.id).ipa"
        Write-Host "[4/5] signing with $($p12.Name) + $($prov.Name) ..."
        $zsign = Join-Path $DeployDir "zsign\zsign.exe"
        $argsList = @("-k", $p12.FullName)
        if ($password) { $argsList += @("-p", $password) }
        $argsList += @("-m", $prov.FullName, "-o", $outIpa, $ipa.FullName)
        & $zsign $argsList
        if ($LASTEXITCODE -ne 0) { throw "zsign failed (exit $LASTEXITCODE)" }
        $signedIpa = $outIpa
        Write-Host "      signed -> $outIpa"
    } else {
        Write-Warning "No signing identity in $CertsDir (need key.pem+cert.pem+profile.mobileprovision, or *.p12+*.mobileprovision). Run Tools\Deploy\provision.py all first, or install the UNSIGNED ipa via 爱思助手."
    }
} else {
    Write-Warning "[4/5] -SkipSign given"
}

# ---- 5. install ----
if (-not $SkipInstall) {
    Write-Host "[5/5] installing via tidevice ..."
    python -m tidevice install $signedIpa
    if ($LASTEXITCODE -ne 0) { throw "tidevice install failed (exit $LASTEXITCODE)" }
    Write-Host "DONE. Launch DemoApp on the device and check logs at http://127.0.0.1:7777/"
} else {
    Write-Host "[5/5] -SkipInstall given — signed ipa at: $signedIpa"
}
