<#
.SYNOPSIS
  Przygotowuje środowisko po sklonowaniu repo: narzędzia, konto AWS, config.psd1, .venv, VS Code.
  Uruchamiaj przez setup.cmd (omija blokadę skryptów na świeżym Windowsie).

.EXAMPLE
  .\setup.cmd                         # interaktywnie
  .\setup.cmd -Reconfigure            # zmień konto/region/prefiks
  .\setup.cmd -Yes -AwsProfile dev -Region eu-west-1   # bez pytań (wartości domyślne)
#>
[CmdletBinding()]
param(
    [string]$AwsProfile,
    [string]$Region,
    [ValidateSet('login', 'sso', 'keys')][string]$LoginMethod,
    [string]$Prefix,
    [string[]]$ProtectedPatterns,
    [switch]$Reconfigure,   # pytaj o konfigurację, nawet jeśli config.psd1 istnieje
    [switch]$SkipInstall,   # nie instaluj niczego przez winget
    [switch]$Yes            # przyjmij wartości domyślne bez pytania
)

# 'Continue', bo w PowerShell 5.1 przy 'Stop' każde wyjście stderr z aws/git rzuca wyjątkiem. Błędy krytyczne rzucamy jawnie.
$ErrorActionPreference = 'Continue'
# setup.cmd (-File) przekazuje "a,b" jako jeden napis - rozdziel.
if ($ProtectedPatterns) { $ProtectedPatterns = @($ProtectedPatterns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$Root    = $PSScriptRoot
$CfgPath = Join-Path $Root 'config.psd1'
$Example = Import-PowerShellDataFile (Join-Path $Root 'config.example.psd1')
$PyVer   = ($Example.PythonRuntime -replace '^python', '')   # np. 3.14

function Step([string]$m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }

function Ask([string]$question, [string]$default) {
    if ($Yes) { return $default }
    $suffix = if ($default) { " [$default]" } else { '' }
    $a = Read-Host "  $question$suffix"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default }
    return $a.Trim()
}
function Confirm([string]$question, [bool]$default = $true) {
    if ($Yes) { return $default }
    $hint = if ($default) { 'T/n' } else { 't/N' }
    $a = Read-Host "  $question [$hint]"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default }
    return ($a -match '^[tTyY]')
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
    foreach ($bin in 'C:\Program Files\Amazon\AWSCLIV2', 'C:\Program Files\Amazon\AWSSAMCLI\bin') {
        if ((Test-Path $bin) -and ($env:Path -notlike "*$bin*")) { $env:Path += ";$bin" }
    }
}

# ------------------------------------------------------------------ 1. narzędzia

$Tools = @(
    @{ Name = 'git';       Winget = 'Git.Git';                Min = '2.0';    Required = $true
       Version = { (git --version) -replace '[^\d.]', '' -replace '\.$', '' } }
    @{ Name = 'aws';       Winget = 'Amazon.AWSCLI';          Min = '2.32.0'; Required = $true
       Version = { if ((aws --version 2>&1 | Out-String) -match 'aws-cli/([\d.]+)') { $Matches[1] } } }
    @{ Name = 'terraform'; Winget = 'Hashicorp.Terraform';    Min = '1.10.0'; Required = $true
       Version = { if ((terraform version 2>&1 | Out-String) -match 'Terraform v([\d.]+)') { $Matches[1] } } }
    @{ Name = "python $PyVer"; Winget = "Python.Python.$PyVer"; Min = $PyVer; Required = $true
       Version = { if ((py "-$PyVer" --version 2>&1 | Out-String) -match 'Python ([\d.]+)') { $Matches[1] } } }
    @{ Name = 'sam';       Winget = 'Amazon.SAM-CLI';         Min = '1.100';  Required = $false
       Why = 'SAM CLI (laby z -Sam)'
       Version = { if ((sam --version 2>&1 | Out-String) -match 'version ([\d.]+)') { $Matches[1] } } }
    @{ Name = 'docker';    Winget = 'Docker.DockerDesktop';   Min = '20.0';   Required = $false
       Why = 'Docker Desktop (sam-local; duża instalacja, wymaga restartu)'; DefaultNo = $true
       Version = { if ((docker --version 2>&1 | Out-String) -match 'version ([\d.]+)') { $Matches[1] } } }
)

function Get-ToolVersion($t) {
    try { $v = & $t.Version 2>$null } catch { $v = $null }
    if ($v) { return [version]($v -replace '^(\d+\.\d+(\.\d+)?).*', '$1') }
    return $null
}

Step 'Narzędzia'
Update-SessionPath
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
foreach ($t in $Tools) {
    $v = Get-ToolVersion $t
    $min = [version]$t.Min
    if ($v -and $v -ge $min) { Ok "$($t.Name) $v"; continue }

    $state = if ($v) { "za stara wersja $v (wymagana >= $min)" } else { 'brak' }
    Warn "$($t.Name): $state"
    if ($SkipInstall) { continue }
    if (-not $hasWinget) { Warn "Brak winget - zainstaluj ręcznie: $($t.Winget)"; continue }

    $want = if ($t.Required) { Confirm "Zainstalować/zaktualizować $($t.Name) przez winget?" $true }
            else { Confirm "Opcjonalnie: $($t.Why). Zainstalować?" (-not $t.DefaultNo) }
    if (-not $want) { continue }

    $verb = if ($v) { 'upgrade' } else { 'install' }
    & winget $verb --id $t.Winget -e --silent --accept-package-agreements --accept-source-agreements
    Update-SessionPath
    $v = Get-ToolVersion $t
    if ($v) { Ok "$($t.Name) $v" } else { Warn "$($t.Name): po instalacji nadal niewidoczne - otwórz nowy terminal i uruchom setup ponownie" }
}

$missing = $Tools | Where-Object { $_.Required -and -not (Get-ToolVersion $_) }
if ($missing) {
    throw "Brak wymaganych narzędzi: $(($missing | ForEach-Object Name) -join ', '). Zainstaluj i uruchom setup ponownie."
}

# ------------------------------------------------------------------ 2. polityka skryptów

Step 'PowerShell execution policy'
# Pomijamy zakres Process (setup.cmd ustawia tam Bypass) - liczy się to, co dostanie zwykły terminal.
$effective = 'Restricted'
foreach ($scope in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
    $p = Get-ExecutionPolicy -Scope $scope
    if ("$p" -ne 'Undefined') { $effective = "$p"; break }
}
if ($effective -in 'Restricted', 'AllSigned') {
    Warn "Polityka: $effective - skrypty .ps1 (env.ps1) nie uruchomią się w zwykłym terminalu."
    if (Confirm 'Ustawić RemoteSigned dla bieżącego użytkownika?' $true) {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Ok 'CurrentUser = RemoteSigned'
    }
} else { Ok $effective }

# ------------------------------------------------------------------ 3. konto AWS / config.psd1

function Get-LoginMethod([string]$p) {
    if (& aws configure get login_session --profile $p 2>$null) { return 'login' }
    if ((& aws configure get sso_session --profile $p 2>$null) -or (& aws configure get sso_start_url --profile $p 2>$null)) { return 'sso' }
    return 'keys'
}
function Invoke-Login([string]$p, [string]$method) {
    switch ($method) {
        'login' { & aws login --profile $p }
        'sso'   { & aws sso login --profile $p }
        'keys'  { Warn "Klucze dla '$p' nie działają - popraw: aws configure --profile $p" }
    }
}
function Get-Identity([string]$p) {
    $out = & aws sts get-caller-identity --profile $p --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Out-String | ConvertFrom-Json) }
    return $null
}

Step 'Konto AWS'
$cfg = $null
if ((Test-Path $CfgPath) -and -not $Reconfigure) {
    $cfg = Import-PowerShellDataFile $CfgPath
    Write-Host "  Istniejący config.psd1: profil=$($cfg.Profile) region=$($cfg.Region) prefiks=$($cfg.Prefix)"
    if (-not (Confirm 'Zostawić tę konfigurację?' $true)) { $cfg = $null }
}

if (-not $cfg) {
    # --- profil
    $profiles = @(& aws configure list-profiles 2>$null | Where-Object { $_ })
    if (-not $AwsProfile) {
        if ($profiles) {
            Write-Host '  Profile w ~/.aws/config:'
            for ($i = 0; $i -lt $profiles.Count; $i++) { Write-Host "    $($i + 1)) $($profiles[$i])" }
            Write-Host '    n) nowy profil'
            $pick = Ask 'Wybierz profil' '1'
            if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $profiles.Count) { $AwsProfile = $profiles[[int]$pick - 1] }
            elseif ($pick -ne 'n') { $AwsProfile = $pick }
        }
        if (-not $AwsProfile) { $AwsProfile = Ask 'Nazwa nowego profilu' 'learn' }
    }

    # --- metoda logowania / konfiguracja nowego profilu
    if ($profiles -notcontains $AwsProfile) {
        if (-not $LoginMethod) {
            Write-Host @'
  Jak logujesz się do AWS?
    1) aws login - login i hasło do konsoli AWS (użytkownik IAM lub root), bez kluczy  [zalecane na prywatnym koncie]
    2) sso       - IAM Identity Center (typowe w firmie)
    3) keys      - access key + secret key użytkownika IAM
'@
            $LoginMethod = @{ '1' = 'login'; '2' = 'sso'; '3' = 'keys' }[(Ask 'Wybór' '1')]
        }
        switch ($LoginMethod) {
            'login' { & aws login --profile $AwsProfile }
            'sso'   { & aws configure sso --profile $AwsProfile }
            'keys'  { & aws configure --profile $AwsProfile }
        }
    } elseif (-not $LoginMethod) {
        $LoginMethod = Get-LoginMethod $AwsProfile
    }

    # --- region
    if (-not $Region) {
        $profRegion = & aws configure get region --profile $AwsProfile 2>$null
        $Region = Ask 'Region' $(if ($profRegion) { $profRegion } else { $Example.Region })
    }
    & aws configure set region $Region --profile $AwsProfile

    # --- weryfikacja sesji
    $id = Get-Identity $AwsProfile
    if (-not $id) {
        Warn 'Brak ważnej sesji - logowanie...'
        Invoke-Login $AwsProfile $LoginMethod
        $id = Get-Identity $AwsProfile
    }
    if (-not $id) { throw "Nie udało się zalogować profilem '$AwsProfile'. Sprawdź: aws sts get-caller-identity --profile $AwsProfile" }
    Ok "Konto $($id.Account) jako $($id.Arn)"

    # --- prefiks
    if (-not $Prefix) {
        do { $Prefix = Ask 'Prefiks zasobów labów (małe litery, kończy się "-")' $Example.Prefix }
        until ($Prefix -match '^[a-z][a-z0-9-]{0,15}-$')
    }

    # --- chronione zasoby (inne projekty na tym koncie)
    if ($null -eq $ProtectedPatterns) {
        $env:AWS_PROFILE = $AwsProfile; $env:AWS_REGION = $Region
        $names = @()
        $names += & aws lambda list-functions --query 'Functions[].FunctionName' --output text 2>$null
        $names += & aws s3api list-buckets --query 'Buckets[].Name' --output text 2>$null
        $names = ($names -split '\s+') | Where-Object { $_ -and $_ -notlike "$Prefix*" -and $_ -notlike 'aws-*' }
        if ($names) {
            Write-Host "  Na koncie są już zasoby spoza labów ($($names.Count)), np.:"
            $names | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" }
            Write-Host '  Podaj wzorce (regex, po przecinku), których narzędzia mają nigdy nie ruszać, np. ^myproject-,^prod-'
            $ans = Ask 'ProtectedPatterns' ''
        } else {
            Ok 'Konto bez innych lambd/bucketów'
            $ans = ''
        }
        $ProtectedPatterns = @($ans -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $cfg = @{
        Profile = $AwsProfile; Region = $Region; LoginMethod = $LoginMethod; Prefix = $Prefix
        ProtectedPatterns = $ProtectedPatterns; PythonRuntime = $Example.PythonRuntime
    }
    $patterns = ($cfg.ProtectedPatterns | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    $content = @"
# Lokalna konfiguracja (poza gitem). Wzór: config.example.psd1. Zmiana: setup.cmd -Reconfigure albo edycja ręczna.
@{
    Profile           = '$($cfg.Profile)'
    Region            = '$($cfg.Region)'
    LoginMethod       = '$($cfg.LoginMethod)'
    Prefix            = '$($cfg.Prefix)'
    ProtectedPatterns = @($patterns)
    PythonRuntime     = '$($cfg.PythonRuntime)'
}
"@
    [IO.File]::WriteAllText($CfgPath, $content, (New-Object Text.UTF8Encoding $true))
    Ok "Zapisano config.psd1"
} else {
    $id = Get-Identity $cfg.Profile
    if (-not $id) { Invoke-Login $cfg.Profile $cfg.LoginMethod; $id = Get-Identity $cfg.Profile }
    if ($id) { Ok "Konto $($id.Account) jako $($id.Arn)" } else { Warn "Brak sesji AWS - po setupie: learn-login" }
}

# ------------------------------------------------------------------ 4. Python venv

Step "Python .venv ($PyVer)"
$venvPy = Join-Path $Root '.venv\Scripts\python.exe'
if (Test-Path $venvPy) {
    $cur = & $venvPy -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"
    if ($cur -ne $PyVer) {
        Warn ".venv ma Pythona $cur - tworzę od nowa"
        Remove-Item (Join-Path $Root '.venv') -Recurse -Force
    }
}
if (-not (Test-Path $venvPy)) { & py "-$PyVer" -m venv (Join-Path $Root '.venv') }
& $venvPy -m pip install -q --upgrade pip
& $venvPy -m pip install -q -r (Join-Path $Root 'requirements-dev.txt')
if ($LASTEXITCODE -ne 0) { throw 'pip install nie powiódł się' }
Ok '.venv + requirements-dev.txt'

# ------------------------------------------------------------------ 5. VS Code

Step 'VS Code'
if (Get-Command code -ErrorAction SilentlyContinue) {
    $installed = & code --list-extensions
    foreach ($ext in 'hashicorp.terraform', 'ms-python.python') {
        if ($installed -contains $ext) { Ok $ext } else { & code --install-extension $ext --force | Out-Null; Ok "$ext (zainstalowane)" }
    }
    if ($installed -contains '4ops.terraform') { Warn 'Rozszerzenie 4ops.terraform koliduje z hashicorp.terraform - wyłącz je w VS Code' }
} else { Warn 'Brak VS Code w PATH - pomijam rozszerzenia (opcjonalne)' }

# ------------------------------------------------------------------ 6. podsumowanie

Step 'Gotowe'
Import-Module (Join-Path $Root 'tools\learn.psm1') -Force -DisableNameChecking
Test-LearnEnv
Write-Host @"

Dalej:
  * VS Code: otwórz folder repo -> nowy terminal (Ctrl+Shift+``) ładuje wszystko sam
  * inny terminal:  . .\env.ps1
  * learn-help      lista komend
  * new-lab hello   pierwszy lab
"@
