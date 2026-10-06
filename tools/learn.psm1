# Narzędzia do pracy z labami AWS (Terraform + SAM).
# Ładowanie:  . .\env.ps1   (konfiguracja: config.psd1, tworzy ją setup.cmd)
# Lista komend: learn-help
#
# ZASADA BEZPIECZEŃSTWA: wszystko, co tworzą laby, ma prefiks z config.psd1 (np. "learn-").
# Komendy sprzątające dotykają WYŁĄCZNIE zasobów z tym prefiksem i odmawiają dla ProtectedPatterns.

$script:Root = Split-Path -Parent $PSScriptRoot
$cfgPath = Join-Path $script:Root 'config.psd1'
if (-not (Test-Path $cfgPath)) {
    Write-Host "Brak config.psd1 - uruchom najpierw setup.cmd" -ForegroundColor Red
    $cfgPath = Join-Path $script:Root 'config.example.psd1'
}
$script:Cfg       = Import-PowerShellDataFile $cfgPath
$script:Prefix    = $script:Cfg.Prefix
$script:Profile   = $script:Cfg.Profile
$script:Region    = $script:Cfg.Region
$script:Protected = @($script:Cfg.ProtectedPatterns) | Where-Object { $_ }

$env:AWS_PROFILE = $script:Profile
$env:AWS_REGION  = $script:Region
$env:AWS_DEFAULT_REGION = $script:Region
$env:SAM_CLI_TELEMETRY = '0'

foreach ($bin in 'C:\Program Files\Amazon\AWSSAMCLI\bin', 'C:\Program Files\Amazon\AWSCLIV2') {
    if ((Test-Path $bin) -and ($env:Path -notlike "*$bin*")) { $env:Path += ";$bin" }
}

function Test-Protected([string]$name) {
    # $true, jeśli nazwa pasuje do któregoś z ProtectedPatterns (regex) z config.psd1.
    foreach ($p in $script:Protected) { if ($name -match $p) { return $true } }
    return $false
}

$venvActivate = Join-Path $script:Root '.venv\Scripts\Activate.ps1'
if (Test-Path $venvActivate) { . $venvActivate }

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

function Invoke-Native {
    # Uruchamia program i przerywa przy kodzie wyjścia != 0.
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @())
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') -> exit $LASTEXITCODE" }
}

function Get-AwsJson([string[]]$Arguments) {
    $out = & aws @Arguments --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return ($out | Out-String | ConvertFrom-Json)
}

# ---------------------------------------------------------------- sesja

function Test-LearnEnv {
    <# Sprawdza narzędzia i sesję AWS. Alias: learn-check #>
    foreach ($t in 'aws', 'terraform', 'sam', 'docker', 'python') {
        $cmd = Get-Command $t -ErrorAction SilentlyContinue
        if ($cmd) { Write-Host ("  [ok] {0,-10} {1}" -f $t, $cmd.Source) -ForegroundColor Green }
        else      { Write-Host ("  [!!] {0,-10} brak w PATH" -f $t) -ForegroundColor Red }
    }
    $id = Get-AwsJson @('sts', 'get-caller-identity')
    if ($id) {
        Write-Host "  [ok] AWS: $($id.Arn)  region=$env:AWS_REGION profile=$env:AWS_PROFILE" -ForegroundColor Green
    } else {
        Write-Host "  [!!] Brak/wygasła sesja AWS -> uruchom: learn-login" -ForegroundColor Red
    }
}

function Connect-Learn {
    <# Logowanie do AWS wg LoginMethod z config.psd1 (login / sso / keys). Alias: learn-login #>
    switch ($script:Cfg.LoginMethod) {
        'login' { Invoke-Native aws @('login', '--profile', $script:Profile) }
        'sso'   { Invoke-Native aws @('sso', 'login', '--profile', $script:Profile) }
        default { Write-Host "Profil '$($script:Profile)' używa kluczy - nic do odświeżenia. Zmiana kluczy: aws configure --profile $($script:Profile)" }
    }
}

# ---------------------------------------------------------------- tworzenie labów

function New-Lab {
    <#
    .SYNOPSIS  Tworzy nowy lab: projects\NN-<name>\ z NOTES.md + terraform\ (+ sam\ z -Sam).
    .EXAMPLE   new-lab s3-trigger
    .EXAMPLE   new-lab s3-trigger -Sam          # terraform + sam
    .EXAMPLE   new-lab s3-trigger -Sam -NoTf    # tylko sam
    (wywołanie: new-lab)
    #>
    param(
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{1,40}$')][string]$Name,
        [switch]$Sam,
        [switch]$NoTf
    )
    $projects = Join-Path $script:Root 'projects'
    $nums = Get-ChildItem $projects -Directory -ErrorAction SilentlyContinue |
        Where-Object Name -match '^(\d+)-' | ForEach-Object { [int]$Matches[1] }
    $next = if ($nums) { ($nums | Measure-Object -Maximum).Maximum + 1 } else { 1 }
    $dir = Join-Path $projects ('{0:D2}-{1}' -f $next, $Name)
    New-Item -ItemType Directory -Path $dir | Out-Null

    $tpl = Join-Path $script:Root 'templates'
    Copy-Item (Join-Path $tpl 'NOTES.md') $dir
    if (-not $NoTf) { Copy-Item (Join-Path $tpl 'terraform') (Join-Path $dir 'terraform') -Recurse }
    if ($Sam)       { Copy-Item (Join-Path $tpl 'sam')       (Join-Path $dir 'sam')       -Recurse }

    # Podmiana placeholderów we wszystkich plikach tekstowych.
    $vars = [ordered]@{
        '__LAB__'     = "$script:Prefix$Name"     # pełna nazwa, np. learn-s3-trigger
        '__NAME__'    = $Name
        '__PREFIX__'  = $script:Prefix
        '__PROFILE__' = $script:Profile
        '__REGION__'  = $script:Region
        '__RUNTIME__' = $script:Cfg.PythonRuntime
    }
    Get-ChildItem $dir -Recurse -File | ForEach-Object {
        $txt = [IO.File]::ReadAllText($_.FullName)
        $new = $txt
        foreach ($k in $vars.Keys) { $new = $new.Replace($k, $vars[$k]) }
        if ($new -ne $txt) { [IO.File]::WriteAllText($_.FullName, $new, (New-Object Text.UTF8Encoding $false)) }
    }
    Write-Step "Utworzono $dir"
    Set-Location $dir
    if (-not $NoTf) {
        # init od razu - rozszerzenie Terraform w VS Code potrzebuje providera, żeby podpowiadać.
        Write-Step 'terraform init'
        Push-Location 'terraform'
        try { Invoke-Native terraform @('init', '-input=false') | Out-Null } finally { Pop-Location }
    }
}

function Resolve-LabDir([string]$sub) {
    $dir = if (Test-Path (Join-Path (Get-Location) $sub)) { Join-Path (Get-Location) $sub } else { (Get-Location).Path }
    $marker = if ($sub -eq 'terraform') { '*.tf' } else { 'template.yaml' }
    if (-not (Get-ChildItem $dir -Filter $marker -File -ErrorAction SilentlyContinue)) {
        $labs = Get-ChildItem (Join-Path $script:Root 'projects') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name
        throw ("Brak plików $marker w $dir. Przejdź do folderu labu, np.: cd projects\$($labs | Select-Object -Last 1)" +
               "`nLaby: $($labs -join ', ')")
    }
    return $dir
}

# ---------------------------------------------------------------- terraform

function Invoke-TfUp {
    <# fmt + init (jeśli trzeba) + validate + apply. Działa w .\terraform albo w bieżącym katalogu. Alias: tf-up
       -Plan  tylko plan, bez apply #>
    param([switch]$Plan, [switch]$AutoApprove)
    Push-Location (Resolve-LabDir 'terraform')
    try {
        Invoke-Native terraform @('fmt', '-recursive')
        if (-not (Test-Path '.terraform')) { Invoke-Native terraform @('init', '-upgrade') }
        Invoke-Native terraform @('validate')
        if ($Plan) { Invoke-Native terraform @('plan'); return }
        $a = @('apply'); if ($AutoApprove) { $a += '-auto-approve' }
        Invoke-Native terraform $a
    } finally { Pop-Location }
}

function Invoke-TfDown {
    <# terraform destroy -auto-approve (usuwa tylko to, co jest w state tego labu). Alias: tf-down #>
    Push-Location (Resolve-LabDir 'terraform')
    try { Invoke-Native terraform @('destroy', '-auto-approve') } finally { Pop-Location }
}

# ---------------------------------------------------------------- SAM

function Invoke-SamUp {
    <# sam validate --lint + build + deploy (konfiguracja w samconfig.toml). Alias: sam-up #>
    Push-Location (Resolve-LabDir 'sam')
    try {
        Invoke-Native sam @('validate', '--lint')
        Invoke-Native sam @('build')
        Invoke-Native sam @('deploy')
    } finally { Pop-Location }
}

function Invoke-SamDown {
    <# sam delete bez pytań (stack z samconfig.toml). Alias: sam-down #>
    Push-Location (Resolve-LabDir 'sam')
    try { Invoke-Native sam @('delete', '--no-prompts') } finally { Pop-Location }
}

function Invoke-SamLocal {
    <# Buduje i wywołuje funkcję lokalnie w Dockerze. Alias: sam-local
       new-lab tworzy events\event.json; inny event: sam-local -Event events\s3-put.json #>
    param([string]$Event = 'events\event.json', [string]$Function)
    Push-Location (Resolve-LabDir 'sam')
    try {
        Invoke-Native sam @('build')
        $a = @('local', 'invoke'); if ($Function) { $a += $Function }; $a += @('--event', $Event)
        Invoke-Native sam $a
    } finally { Pop-Location }
}

# ---------------------------------------------------------------- testy

function Invoke-LabTest {
    <# pytest dla bieżącego labu (szuka tests\ w terraform\ i sam\). Alias: lab-test #>
    $dirs = @('terraform', 'sam', '.') | ForEach-Object { Join-Path (Get-Location) $_ } |
        Where-Object { Test-Path (Join-Path $_ 'tests') } | Select-Object -Unique
    if (-not $dirs) { Write-Host 'Brak katalogu tests\' -ForegroundColor Yellow; return }
    foreach ($d in $dirs) {
        Write-Step "pytest w $d"
        Push-Location $d
        try { Invoke-Native python @('-m', 'pytest', '-q') } finally { Pop-Location }
    }
}

# ---------------------------------------------------------------- inwentarz / sprzątanie

function Get-LearnResources {
    <#
    .SYNOPSIS  Lista zasobów z prefiksem labów w regionie (z -All: wszystko poza ProtectedPatterns).
               Kolumna Owner: terraform / cloudformation / CONSOLE (do ręcznego usunięcia).
    Alias: aws-ls
    -All  pokaż wszystkie zasoby poza chronionymi (np. stare z konsoli bez prefiksu)
    #>
    param([switch]$All)
    $match = if ($All) { { param($n) -not (Test-Protected $n) -and $n -notmatch '^AWSServiceRole|^aws-|^/aws/lambda/aws-' } }
             else      { { param($n) $n -like "$script:Prefix*" -or $n -like "/aws/lambda/$script:Prefix*" } }
    $rows = New-Object System.Collections.Generic.List[object]
    $stk = Get-AwsJson @('cloudformation', 'list-stacks', '--stack-status-filter',
        'CREATE_COMPLETE', 'UPDATE_COMPLETE', 'ROLLBACK_COMPLETE', 'UPDATE_ROLLBACK_COMPLETE', 'CREATE_FAILED', 'DELETE_FAILED')
    $stacks = @($stk.StackSummaries | Where-Object { $_.StackName -like "$script:Prefix*" } | ForEach-Object StackName)
    $add = { param($type, $name, $tags)
        $owner = 'CONSOLE'
        if ($tags) {
            $h = @{}; foreach ($t in $tags) { if ($t.Key) { $h[$t.Key] = $t.Value } }
            if ($h['aws:cloudformation:stack-name']) { $owner = "cfn:$($h['aws:cloudformation:stack-name'])" }
            elseif ($h['ManagedBy']) { $owner = $h['ManagedBy'] }
        }
        if ($owner -eq 'CONSOLE') {
            # Np. role IAM tworzone przez CFN nie mają tagów aws:cloudformation:* - rozpoznaj po nazwie stacka.
            $short = $name -replace '^/aws/lambda/', ''
            $s = $stacks | Where-Object { $short -like "$_-*" } | Select-Object -First 1
            if ($s) { $owner = "cfn:$s" }
        }
        $rows.Add([pscustomobject]@{ Type = $type; Name = $name; Owner = $owner })
    }

    $fns = Get-AwsJson @('lambda', 'list-functions')
    foreach ($f in $fns.Functions) {
        if (& $match $f.FunctionName) {
            $t = Get-AwsJson @('lambda', 'list-tags', '--resource', $f.FunctionArn)
            $tags = if ($t) { $t.Tags.PSObject.Properties | ForEach-Object { @{ Key = $_.Name; Value = $_.Value } } }
            & $add 'lambda' $f.FunctionName $tags
        }
    }
    $roles = Get-AwsJson @('iam', 'list-roles')
    foreach ($r in $roles.Roles) {
        if (& $match $r.RoleName) {
            $t = Get-AwsJson @('iam', 'list-role-tags', '--role-name', $r.RoleName)
            & $add 'iam-role' $r.RoleName $t.Tags
        }
    }
    $lgs = Get-AwsJson @('logs', 'describe-log-groups')
    foreach ($l in $lgs.logGroups) {
        if (& $match $l.logGroupName) {
            $t = Get-AwsJson @('logs', 'list-tags-for-resource', '--resource-arn', ($l.arn -replace ':\*$', ''))
            $tags = if ($t) { $t.tags.PSObject.Properties | ForEach-Object { @{ Key = $_.Name; Value = $_.Value } } }
            & $add 'log-group' $l.logGroupName $tags
        }
    }
    $bks = Get-AwsJson @('s3api', 'list-buckets')
    foreach ($b in $bks.Buckets) {
        if (& $match $b.Name) {
            $t = Get-AwsJson @('s3api', 'get-bucket-tagging', '--bucket', $b.Name)
            & $add 's3' $b.Name $t.TagSet
        }
    }
    $qs = Get-AwsJson @('sqs', 'list-queues')
    foreach ($u in $qs.QueueUrls) {
        $n = $u.Split('/')[-1]
        if (& $match $n) {
            $t = Get-AwsJson @('sqs', 'list-queue-tags', '--queue-url', $u)
            $tags = if ($t -and $t.Tags) { $t.Tags.PSObject.Properties | ForEach-Object { @{ Key = $_.Name; Value = $_.Value } } }
            & $add 'sqs' $n $tags
        }
    }
    $tbl = Get-AwsJson @('dynamodb', 'list-tables')
    foreach ($n in $tbl.TableNames) { if (& $match $n) { & $add 'dynamodb' $n $null } }
    $sns = Get-AwsJson @('sns', 'list-topics')
    foreach ($tp in $sns.Topics) { $n = $tp.TopicArn.Split(':')[-1]; if (& $match $n) { & $add 'sns' $n $null } }
    foreach ($s in $stacks) { $rows.Add([pscustomobject]@{ Type = 'cfn-stack'; Name = $s; Owner = 'sam' }) }

    if ($rows.Count -eq 0) { Write-Host "Brak zasobów ($env:AWS_REGION). Czysto." -ForegroundColor Green; return }
    $rows | Sort-Object Owner, Type, Name | Format-Table -AutoSize
}

function Remove-ConsoleLambda {
    <#
    .SYNOPSIS  Usuwa lambdę stworzoną w konsoli RAZEM z tym, co konsola tworzy obok:
               log group /aws/lambda/<fn>, role <fn>-role-*, oraz customer-managed policy
               AWSLambdaBasicExecutionRole-* podpięte do tych ról.
    .EXAMPLE   rm-console-lambda learn-hello
    Odmawia dla funkcji zarządzanych przez terraform/CloudFormation. Alias: rm-console-lambda
    #>
    param([Parameter(Mandatory)][string]$Name, [switch]$Force)
    if (Test-Protected $Name) { throw "Odmawiam: '$Name' pasuje do ProtectedPatterns w config.psd1." }

    $fn = Get-AwsJson @('lambda', 'get-function', '--function-name', $Name)
    if ($fn -and $fn.Tags -and ($fn.Tags.ManagedBy -or $fn.Tags.'aws:cloudformation:stack-name')) {
        throw "Odmawiam: '$Name' jest zarządzana przez IaC - użyj tf-down / sam-down."
    }
    $roles = (Get-AwsJson @('iam', 'list-roles')).Roles | Where-Object { $_.RoleName -like "$Name-role-*" }
    $lg = "/aws/lambda/$Name"
    $lgExists = (Get-AwsJson @('logs', 'describe-log-groups', '--log-group-name-prefix', $lg)).logGroups |
        Where-Object logGroupName -eq $lg

    Write-Host "Do usunięcia:" -ForegroundColor Yellow
    if ($fn)       { Write-Host "  lambda     $Name" }
    if ($lgExists) { Write-Host "  log-group  $lg" }
    $policies = @{}
    foreach ($r in $roles) {
        Write-Host "  iam-role   $($r.RoleName)"
        $att = (Get-AwsJson @('iam', 'list-attached-role-policies', '--role-name', $r.RoleName)).AttachedPolicies
        $policies[$r.RoleName] = $att
        foreach ($p in $att) {
            $kind = if ($p.PolicyArn -like 'arn:aws:iam::aws:*') { 'detach (AWS managed)' } else { 'detach + delete' }
            Write-Host "    policy   $($p.PolicyName)  [$kind]"
        }
    }
    if (-not $fn -and -not $lgExists -and -not $roles) { Write-Host '  (nic nie znaleziono)'; return }
    if (-not $Force) {
        $ans = Read-Host 'Usunąć? [y/N]'
        if ($ans -ne 'y') { Write-Host 'Przerwano.'; return }
    }

    if ($fn) { Invoke-Native aws @('lambda', 'delete-function', '--function-name', $Name); Write-Step "lambda $Name" }
    if ($lgExists) { Invoke-Native aws @('logs', 'delete-log-group', '--log-group-name', $lg); Write-Step "log-group $lg" }
    foreach ($r in $roles) {
        $rn = $r.RoleName
        foreach ($p in $policies[$rn]) {
            Invoke-Native aws @('iam', 'detach-role-policy', '--role-name', $rn, '--policy-arn', $p.PolicyArn)
            if ($p.PolicyArn -notlike 'arn:aws:iam::aws:*') {
                $vers = (Get-AwsJson @('iam', 'list-policy-versions', '--policy-arn', $p.PolicyArn)).Versions |
                    Where-Object { -not $_.IsDefaultVersion }
                foreach ($v in $vers) { Invoke-Native aws @('iam', 'delete-policy-version', '--policy-arn', $p.PolicyArn, '--version-id', $v.VersionId) }
                Invoke-Native aws @('iam', 'delete-policy', '--policy-arn', $p.PolicyArn)
            }
        }
        foreach ($ip in (Get-AwsJson @('iam', 'list-role-policies', '--role-name', $rn)).PolicyNames) {
            Invoke-Native aws @('iam', 'delete-role-policy', '--role-name', $rn, '--policy-name', $ip)
        }
        Invoke-Native aws @('iam', 'delete-role', '--role-name', $rn)
        Write-Step "iam-role $rn"
    }
}

function Remove-LearnBucket {
    <# Opróżnia (łącznie z wersjami) i usuwa bucket learn-*. Alias: rm-bucket #>
    param([Parameter(Mandatory)][string]$Name, [switch]$Force)
    if ($Name -notlike "$script:Prefix*") { throw "Odmawiam: bucket musi mieć prefiks '$script:Prefix'." }
    if (-not $Force) {
        $ans = Read-Host "Opróżnić i usunąć s3://$Name ? [y/N]"
        if ($ans -ne 'y') { Write-Host 'Przerwano.'; return }
    }
    Invoke-Native aws @('s3', 'rm', "s3://$Name", '--recursive')
    # Bucket z wersjonowaniem: usuń wersje i delete markery.
    do {
        $v = Get-AwsJson @('s3api', 'list-object-versions', '--bucket', $Name, '--max-items', '500')
        $objs = @($v.Versions) + @($v.DeleteMarkers) | Where-Object { $_ } |
            ForEach-Object { @{ Key = $_.Key; VersionId = $_.VersionId } }
        if ($objs) {
            $f = New-TemporaryFile
            [IO.File]::WriteAllText($f.FullName, (@{ Objects = @($objs); Quiet = $true } | ConvertTo-Json -Depth 4 -Compress))
            Invoke-Native aws @('s3api', 'delete-objects', '--bucket', $Name, '--delete', "file://$($f.FullName)")
            Remove-Item $f
        }
    } while ($objs)
    Invoke-Native aws @('s3api', 'delete-bucket', '--bucket', $Name)
    Write-Step "s3 $Name usunięty"
}

# ---------------------------------------------------------------- logi

function Get-LambdaLogs {
    <# Ogon logów lambdy (na żywo). Alias: lambda-logs   np. lambda-logs learn-s3-trigger #>
    param([Parameter(Mandatory)][string]$Name, [string]$Since = '15m')
    & aws logs tail "/aws/lambda/$Name" --follow --since $Since --format short
}

function Invoke-Lambda {
    <# Wywołuje lambdę w AWS z eventem z pliku i pokazuje wynik. Alias: lambda-invoke
       np. lambda-invoke learn-s3-trigger events\event.json #>
    param([Parameter(Mandatory)][string]$Name, [string]$Event = 'events\event.json')
    $out = Join-Path $env:TEMP 'lambda-out.json'
    $a = @('lambda', 'invoke', '--function-name', $Name, '--log-type', 'Tail', '--query', 'LogResult', '--output', 'text')
    # Szukaj eventu w bieżącym katalogu, potem w terraform\ i sam\ labu.
    $path = @($Event, (Join-Path 'terraform' $Event), (Join-Path 'sam' $Event)) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $path) { throw "Nie znaleziono pliku eventu '$Event' (szukano też w terraform\ i sam\)." }
    Write-Host "event: $path" -ForegroundColor DarkGray
    $a += @('--payload', "fileb://$((Resolve-Path $path).Path)")
    $log = & aws @a $out
    if ($LASTEXITCODE -ne 0) { throw "lambda invoke -> exit $LASTEXITCODE" }
    Write-Host '--- log (ostatnie 4KB) ---' -ForegroundColor DarkGray
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($log)) | Write-Host -ForegroundColor DarkGray
    Write-Host '--- wynik ---' -ForegroundColor DarkGray
    Get-Content $out
}

function Show-LearnHelp {
    @'
  learn-check              narzędzia + sesja AWS
  learn-login              zaloguj profil AWS z config.psd1

  new-lab <name> [-Sam] [-NoTf]   nowy lab w projects\NN-<name>\ (cd do niego)

  tf-up [-Plan] [-AutoApprove]    fmt, init, validate, apply   (.\terraform)
  tf-down                          destroy -auto-approve
  sam-up                           validate --lint, build, deploy (.\sam)
  sam-down                         sam delete --no-prompts
  sam-local [-Event f.json]        build + local invoke (Docker)
  lab-test                         pytest dla labu

  aws-ls [-All]                    zasoby learn-* + kto nimi zarządza (CONSOLE = do usunięcia)
  rm-console-lambda <fn>           usuń lambdę z konsoli + rola + policy + log group
  rm-bucket <name>                 opróżnij i usuń bucket learn-*
  lambda-invoke <fn> [event.json]  wywołanie w AWS + log + wynik
  lambda-logs <fn>                 logs tail --follow
'@ | Write-Host
}

Set-Alias learn-check       Test-LearnEnv
Set-Alias learn-login       Connect-Learn
Set-Alias learn-help        Show-LearnHelp
Set-Alias tf-up             Invoke-TfUp
Set-Alias tf-down           Invoke-TfDown
Set-Alias sam-up            Invoke-SamUp
Set-Alias sam-down          Invoke-SamDown
Set-Alias sam-local         Invoke-SamLocal
Set-Alias lab-test          Invoke-LabTest
Set-Alias aws-ls            Get-LearnResources
Set-Alias rm-console-lambda Remove-ConsoleLambda
Set-Alias rm-bucket         Remove-LearnBucket
Set-Alias lambda-logs       Get-LambdaLogs
Set-Alias lambda-invoke     Invoke-Lambda

Export-ModuleMember -Function * -Alias *
