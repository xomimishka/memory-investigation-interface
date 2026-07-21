param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$OutRoot = '',
    [int]$Port = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue | Out-Null

function Get-CheckGoCommand {
    $preferred = 'K:\go\go1.20.14\bin\go.exe'
    if (Test-Path -LiteralPath $preferred) {
        return $preferred
    }
    $go = Get-Command go -ErrorAction SilentlyContinue
    if ($go) {
        return $go.Source
    }
    throw 'go executable was not found in PATH and K:\go\go1.20.14\bin\go.exe was not found'
}

function New-CheckContext {
    param(
        [Parameter(Mandatory=$true)][string]$Student,
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [string]$OutRoot = ''
    )

    $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
    if ($OutRoot -eq '') {
        $OutRoot = Join-Path $repo '.check-results'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeStudent = $Student -replace '[^A-Za-z0-9_.-]', '_'
    $resultDir = Join-Path $OutRoot "${safeStudent}_${timestamp}"
    $logsDir = Join-Path $resultDir 'logs'
    $inputsDir = Join-Path $resultDir 'inputs'
    $outputsDir = Join-Path $resultDir 'outputs'
    $metaDir = Join-Path $resultDir 'meta'
    $tmpDir = Join-Path $resultDir 'tmp'
    foreach ($dir in @($resultDir, $logsDir, $inputsDir, $outputsDir, $metaDir, $tmpDir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $ctx = [ordered]@{
        Student = $Student
        RepoRoot = $repo
        ResultDir = $resultDir
        LogsDir = $logsDir
        InputsDir = $inputsDir
        OutputsDir = $outputsDir
        MetaDir = $metaDir
        TmpDir = $tmpDir
        CommandsPath = Join-Path $resultDir 'commands.jsonl'
        GoCmd = Get-CheckGoCommand
        StartedAt = (Get-Date).ToString('o')
        CommandResults = @{}
        Assessments = New-Object System.Collections.ArrayList
    }
    '' | Set-Content -LiteralPath $ctx.CommandsPath -Encoding UTF8
    return $ctx
}

function Save-CheckJson {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 40
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Invoke-CheckCommand {
    param(
        [Parameter(Mandatory=$true)]$Ctx,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Command,
        [string]$WorkingDirectory = ''
    )
    if ($WorkingDirectory -eq '') {
        $WorkingDirectory = $Ctx.RepoRoot
    }
    $safeName = $Name -replace '[^A-Za-z0-9_.-]', '_'
    $runnerPath = Join-Path $Ctx.TmpDir "$safeName.ps1"
    $logPath = Join-Path $Ctx.LogsDir "$safeName.log"
    $started = Get-Date
    $runner = @"
`$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath '$($WorkingDirectory.Replace("'", "''"))'
try {
    `$global:LASTEXITCODE = `$null
    `$Error.Clear()
    $Command
    `$exitCode = `$global:LASTEXITCODE
    if (`$null -eq `$exitCode) {
        if (`$? -and `$Error.Count -eq 0) { `$exitCode = 0 } else { `$exitCode = 1 }
    }
    exit `$exitCode
} catch {
    Write-Error `$_
    exit 1
}
"@
    Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runnerPath 2>&1
    $exitCode = $LASTEXITCODE
    $ended = Get-Date
    @(
        "name: $Name"
        "working_directory: $WorkingDirectory"
        "command:"
        $Command
        "exit_code: $exitCode"
        "started_at: $($started.ToString('o'))"
        "ended_at: $($ended.ToString('o'))"
        ""
        "output:"
        ($output | Out-String)
    ) | Set-Content -LiteralPath $logPath -Encoding UTF8

    $record = [ordered]@{
        name = $Name
        command = $Command
        working_directory = $WorkingDirectory
        exit_code = $exitCode
        started_at = $started.ToString('o')
        ended_at = $ended.ToString('o')
        duration_ms = [int](($ended - $started).TotalMilliseconds)
        log = "logs/$safeName.log"
    }
    ($record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $Ctx.CommandsPath -Encoding UTF8
    $Ctx.CommandResults[$Name] = $record
    return $record
}

function Add-FeatureAssessment {
    param(
        [Parameter(Mandatory=$true)]$Ctx,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][ValidateSet('minimum','good','excellent','engineering')][string]$Level,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Requirement,
        [Parameter(Mandatory=$true)][ValidateSet('not_implemented','partial','full')][string]$Implementation,
        [Parameter(Mandatory=$true)][ValidateSet('not_tested','nonconformant','conformant')][string]$Conformance,
        [string[]]$Evidence = @(),
        [string]$Details = ''
    )
    $item = [ordered]@{
        id = $Id
        level = $Level
        category = $Category
        requirement = $Requirement
        implementation = $Implementation
        conformance = $Conformance
        evidence = @($Evidence)
        details = $Details
    }
    $Ctx.Assessments.Add($item) | Out-Null
}

function Add-BooleanFeatureAssessment {
    param(
        [Parameter(Mandatory=$true)]$Ctx,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][ValidateSet('minimum','good','excellent','engineering')][string]$Level,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Requirement,
        [Parameter(Mandatory=$true)][bool]$Implemented,
        [Parameter(Mandatory=$true)][bool]$Conformant,
        [string[]]$Evidence = @(),
        [string]$Details = ''
    )
    $implementation = if ($Implemented) { 'full' } else { 'not_implemented' }
    $conformance = if (-not $Implemented) { 'not_tested' } elseif ($Conformant) { 'conformant' } else { 'nonconformant' }
    Add-FeatureAssessment -Ctx $Ctx -Id $Id -Level $Level -Category $Category -Requirement $Requirement -Implementation $implementation -Conformance $conformance -Evidence $Evidence -Details $Details
}

function Add-CommandFeatureAssessment {
    param(
        [Parameter(Mandatory=$true)]$Ctx,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][ValidateSet('minimum','good','excellent','engineering')][string]$Level,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Requirement,
        [Parameter(Mandatory=$true)][string]$CommandName
    )
    $has = $Ctx.CommandResults.ContainsKey($CommandName)
    $ok = $false
    if ($has) {
        $ok = ([int]$Ctx.CommandResults[$CommandName].exit_code -eq 0)
    }
    Add-BooleanFeatureAssessment -Ctx $Ctx -Id $Id -Level $Level -Category $Category -Requirement $Requirement -Implemented $has -Conformant $ok -Evidence @("logs/$CommandName.log") -Details "command=$CommandName"
}

function Invoke-HttpRequestSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][string]$Uri,
        [string]$Body = '',
        [string]$ContentType = 'application/json',
        [int]$TimeoutSec = 10
    )
    $clientHandler = New-Object System.Net.Http.HttpClientHandler
    $client = New-Object System.Net.Http.HttpClient($clientHandler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    $httpMethod = switch ($Method.ToUpperInvariant()) {
        'GET' { [System.Net.Http.HttpMethod]::Get }
        'POST' { [System.Net.Http.HttpMethod]::Post }
        'PUT' { [System.Net.Http.HttpMethod]::Put }
        'PATCH' { [System.Net.Http.HttpMethod]::new('PATCH') }
        'DELETE' { [System.Net.Http.HttpMethod]::Delete }
        default { [System.Net.Http.HttpMethod]::new($Method) }
    }
    $request = New-Object System.Net.Http.HttpRequestMessage($httpMethod, $Uri)
    if ($Method -in @('POST', 'PUT', 'PATCH')) {
        $request.Content = New-Object System.Net.Http.StringContent($Body, [System.Text.Encoding]::UTF8, $ContentType)
    }
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $headers = @{}
        foreach ($header in $response.Headers) {
            $headers[[string]$header.Key] = [string]($header.Value -join ',')
        }
        foreach ($header in $response.Content.Headers) {
            $headers[[string]$header.Key] = [string]($header.Value -join ',')
        }
        $json = $null
        try { $json = $text | ConvertFrom-Json } catch {}
        return [ordered]@{
            status_code = [int]$response.StatusCode
            headers = $headers
            body = $text
            json = $json
        }
    } finally {
        if ($request) { $request.Dispose() }
        if ($client) { $client.Dispose() }
        if ($clientHandler) { $clientHandler.Dispose() }
    }
}

function Test-IsJsonErrorEnvelope {
    param(
        [Parameter(Mandatory=$true)]$Response,
        [Parameter(Mandatory=$true)][int]$StatusCode,
        [Parameter(Mandatory=$true)][string]$ErrorCode
    )
    $contentType = ''
    if ($Response.headers) {
        if ($Response.headers.ContainsKey('Content-Type')) {
            $contentType = [string]$Response.headers['Content-Type']
        } elseif ($Response.headers.ContainsKey('content-type')) {
            $contentType = [string]$Response.headers['content-type']
        }
    }
    $hasJsonType = $true
    if (-not [string]::IsNullOrWhiteSpace($contentType)) {
        $hasJsonType = $contentType.ToLower().StartsWith('application/json')
    }
    $payload = $Response.json
    if (-not $payload -and -not [string]::IsNullOrWhiteSpace([string]$Response.body)) {
        try { $payload = [string]$Response.body | ConvertFrom-Json } catch {}
    }
    $hasEnvelope = $false
    if ($payload -and $payload.error -and $payload.error.code) {
        $hasEnvelope = (($payload.error.code -eq $ErrorCode) -and ([string]::IsNullOrWhiteSpace($payload.error.message) -eq $false))
    }
    return (($Response.status_code -eq $StatusCode) -and $hasJsonType -and $hasEnvelope)
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return [int]$port
}

function New-LargeDatasetFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$Count = 100000
    )
    $started = Get-Date
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($Path, $false, $utf8)
    try {
        $base = [DateTime]::Parse('2026-06-16T00:00:00Z').ToUniversalTime()
        for ($i = 0; $i -lt $Count; $i++) {
            $eventId = ('evt_large_{0:D6}' -f $i)
            $userId = ('user_{0:D3}' -f ($i % 100))
            $fileName = ('file_{0:D6}' -f $i)
            $action = if (($i % 7) -eq 0) { 'email_send' } else { 'read' }
            $destination = if (($i % 11) -eq 0) { 'external' } else { 'internal' }
            if ($i -eq 54321) {
                $eventId = 'large_target_054321'
                $userId = 'target_user'
                $fileName = 'file_large_target_054321'
                $action = 'email_send'
                $destination = 'external'
            }
            $timestamp = $base.AddSeconds($i).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $line = ('{{"event_id":"{0}","user_id":"{1}","file_name":"{2}","action":"{3}","destination_type":"{4}","timestamp":"{5}"}}' -f $eventId, $userId, $fileName, $action, $destination, $timestamp)
            $writer.WriteLine($line)
        }
        $writer.Flush()
    } finally {
        $writer.Dispose()
    }
    $ended = Get-Date
    $size = (Get-Item -LiteralPath $Path).Length
    return [ordered]@{
        count = $Count
        bytes = [int64]$size
        duration_ms = [int](($ended - $started).TotalMilliseconds)
        target_event_id = 'large_target_054321'
    }
}

function Copy-CheckPath {
    param(
        [Parameter(Mandatory=$true)]$Ctx,
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$RelativeDestination
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }
    $destination = Join-Path $Ctx.ResultDir $RelativeDestination
    $parent = Split-Path -Parent $destination
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $destination -Recurse -Force
}

function Add-StandardEngineeringAssessments {
    param([Parameter(Mandatory=$true)]$Ctx)
    $testFiles = @(Get-ChildItem -LiteralPath $Ctx.RepoRoot -Recurse -File -Filter '*_test.go' -ErrorAction SilentlyContinue)
    $testFunctions = @($testFiles | Select-String -Pattern '^\s*func\s+Test[A-Za-z0-9_]+\s*\(' -ErrorAction SilentlyContinue)
    $benchmarkFunctions = @($testFiles | Select-String -Pattern '^\s*func\s+Benchmark[A-Za-z0-9_]+\s*\(' -ErrorAction SilentlyContinue)
    Add-BooleanFeatureAssessment -Ctx $Ctx -Id 'engineering.unit_tests_present' -Level 'engineering' -Category 'tests' -Requirement 'Go unit tests are present' -Implemented ($testFunctions.Count -gt 0) -Conformant ($testFunctions.Count -gt 0) -Evidence @('cmd/event-memory-search-api/main_test.go') -Details "tests=$($testFunctions.Count)"
    Add-BooleanFeatureAssessment -Ctx $Ctx -Id 'engineering.benchmarks_present' -Level 'engineering' -Category 'benchmarks' -Requirement 'Go benchmarks are present' -Implemented ($benchmarkFunctions.Count -gt 0) -Conformant ($benchmarkFunctions.Count -gt 0) -Evidence @('cmd/event-memory-search-api/main_test.go') -Details "benchmarks=$($benchmarkFunctions.Count)"

    foreach ($pair in @(
        @{ id = 'engineering.gofmt_runs'; cmd = 'go_fmt' ; req = 'gofmt command passes' },
        @{ id = 'engineering.go_test_passes'; cmd = 'go_test_all'; req = 'go test ./... passes' },
        @{ id = 'engineering.make_test_runs'; cmd = 'make_test'; req = 'make test passes' },
        @{ id = 'engineering.make_bench_runs'; cmd = 'make_bench'; req = 'make bench passes' },
        @{ id = 'engineering.make_demo_runs'; cmd = 'make_demo'; req = 'make demo passes' },
        @{ id = 'engineering.build_server'; cmd = 'build_api_server'; req = 'go build server passes' }
    )) {
        if ($Ctx.CommandResults.ContainsKey($pair.cmd)) {
            Add-CommandFeatureAssessment -Ctx $Ctx -Id $pair.id -Level 'engineering' -Category 'reproducibility' -Requirement $pair.req -CommandName $pair.cmd
        }
    }
    if ($Ctx.CommandResults.ContainsKey('go_test_race')) {
        Add-CommandFeatureAssessment -Ctx $Ctx -Id 'engineering.race_test_passes' -Level 'engineering' -Category 'tests' -Requirement 'go test -race ./... passes' -CommandName 'go_test_race'
    }

    $readmePath = Join-Path $Ctx.RepoRoot 'README.md'
    $readmeOk = (Test-Path -LiteralPath $readmePath) -and ((Get-Item -LiteralPath $readmePath).Length -gt 100)
    Add-BooleanFeatureAssessment -Ctx $Ctx -Id 'engineering.readme' -Level 'engineering' -Category 'documentation' -Requirement 'README.md exists and is not empty' -Implemented $readmeOk -Conformant $readmeOk -Evidence @('repo_snapshot/README.md')

    $makefilePath = Join-Path $Ctx.RepoRoot 'Makefile'
    $makefileText = if (Test-Path -LiteralPath $makefilePath) { Get-Content -LiteralPath $makefilePath -Raw } else { '' }
    foreach ($target in @('test','bench','demo','serve')) {
        $targetOk = $makefileText -match "(?m)^\s*${target}\s*:"
        Add-BooleanFeatureAssessment -Ctx $Ctx -Id "engineering.make_$target" -Level 'engineering' -Category 'reproducibility' -Requirement "Makefile has target $target" -Implemented $targetOk -Conformant $targetOk -Evidence @('repo_snapshot/Makefile')
    }

    $controlPath = Join-Path $Ctx.RepoRoot 'testdata\control'
    $controlFiles = @()
    if (Test-Path -LiteralPath $controlPath) {
        $controlFiles = @(Get-ChildItem -LiteralPath $controlPath -Recurse -File -ErrorAction SilentlyContinue)
    }
    Add-BooleanFeatureAssessment -Ctx $Ctx -Id 'engineering.control_data' -Level 'engineering' -Category 'reproducibility' -Requirement 'Fixed testdata/control set exists' -Implemented ($controlFiles.Count -gt 0) -Conformant ($controlFiles.Count -gt 0) -Evidence @($controlFiles | ForEach-Object { $_.FullName }) -Details "files=$($controlFiles.Count)"

    $solutionPath = Join-Path $Ctx.RepoRoot 'docs\reshenie.md'
    $solutionOk = (Test-Path -LiteralPath $solutionPath) -and ((Get-Item -LiteralPath $solutionPath).Length -gt 100)
    Add-BooleanFeatureAssessment -Ctx $Ctx -Id 'engineering.solution_doc' -Level 'engineering' -Category 'documentation' -Requirement 'Non-empty docs/reshenie.md exists' -Implemented $solutionOk -Conformant $solutionOk -Evidence @('repo_snapshot/docs/reshenie.md')
}

function Complete-Check {
    param(
        [Parameter(Mandatory=$true)]$Ctx,
        [hashtable]$Extra = @{}
    )
    Add-StandardEngineeringAssessments -Ctx $Ctx

    Invoke-CheckCommand -Ctx $Ctx -Name 'meta_git_head' -Command "git rev-parse HEAD | Set-Content -LiteralPath '$($Ctx.MetaDir)\git_head.txt' -Encoding UTF8" | Out-Null
    Invoke-CheckCommand -Ctx $Ctx -Name 'meta_git_status' -Command "`$statusPath = '$($Ctx.MetaDir)\git_status_short.txt'; `$status = git status --short; if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }; if (`$null -eq `$status) { '' | Set-Content -LiteralPath `$statusPath -Encoding UTF8 } else { @(`$status) | Set-Content -LiteralPath `$statusPath -Encoding UTF8 }" | Out-Null
    Invoke-CheckCommand -Ctx $Ctx -Name 'meta_go_version' -Command "& '$($Ctx.GoCmd)' version | Set-Content -LiteralPath '$($Ctx.MetaDir)\go_version.txt' -Encoding UTF8" | Out-Null
    Invoke-CheckCommand -Ctx $Ctx -Name 'meta_go_env' -Command "& '$($Ctx.GoCmd)' env GOVERSION GOOS GOARCH CGO_ENABLED | Set-Content -LiteralPath '$($Ctx.MetaDir)\go_env.txt' -Encoding UTF8" | Out-Null

    foreach ($name in @('README.md', 'Makefile', 'go.mod', 'docs', 'testdata')) {
        Copy-CheckPath -Ctx $Ctx -Source (Join-Path $Ctx.RepoRoot $name) -RelativeDestination "repo_snapshot/$name"
    }

    $assessmentItems = @($Ctx.Assessments)
    $summary = [ordered]@{}
    foreach ($level in @('minimum','good','excellent','engineering')) {
        $items = @($assessmentItems | Where-Object { $_.level -eq $level })
        $summary[$level] = [ordered]@{
            total = $items.Count
            full = @($items | Where-Object { $_.implementation -eq 'full' }).Count
            partial = @($items | Where-Object { $_.implementation -eq 'partial' }).Count
            not_implemented = @($items | Where-Object { $_.implementation -eq 'not_implemented' }).Count
            conformant = @($items | Where-Object { $_.conformance -eq 'conformant' }).Count
            nonconformant = @($items | Where-Object { $_.conformance -eq 'nonconformant' }).Count
            not_tested = @($items | Where-Object { $_.conformance -eq 'not_tested' }).Count
        }
    }
    Save-CheckJson -Path (Join-Path $Ctx.ResultDir 'assessment.json') -Value ([ordered]@{
        schema_version = 1
        statuses = [ordered]@{
            implementation = @('not_implemented','partial','full')
            conformance = @('not_tested','nonconformant','conformant')
        }
        summary = $summary
        features = $assessmentItems
    })

    $manifest = [ordered]@{
        student = $Ctx.Student
        repo_root = $Ctx.RepoRoot
        started_at = $Ctx.StartedAt
        completed_at = (Get-Date).ToString('o')
        machine = [ordered]@{
            computer_name = $env:COMPUTERNAME
            user_name = $env:USERNAME
            os = (Get-CimInstance Win32_OperatingSystem).Caption
            powershell = $PSVersionTable.PSVersion.ToString()
        }
        result_dir = $Ctx.ResultDir
        commands_file = 'commands.jsonl'
        assessment_file = 'assessment.json'
        notes = $Extra
    }
    Save-CheckJson -Path (Join-Path $Ctx.ResultDir 'manifest.json') -Value $manifest

    $zipPath = "$($Ctx.ResultDir).zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $Ctx.ResultDir '*') -DestinationPath $zipPath -Force
    Write-Host "CHECK_RESULT_DIR=$($Ctx.ResultDir)"
    Write-Host "CHECK_RESULT_ZIP=$zipPath"
    return $zipPath
}

$ctx = New-CheckContext -Student 'memory_api_check' -RepoRoot $RepoRoot -OutRoot $OutRoot

Invoke-CheckCommand -Ctx $ctx -Name 'go_fmt' -Command "& '$($ctx.GoCmd)' fmt ./..." | Out-Null
Invoke-CheckCommand -Ctx $ctx -Name 'go_test_all' -Command "& '$($ctx.GoCmd)' test ./..." | Out-Null
if (Test-Path -LiteralPath (Join-Path $ctx.RepoRoot 'Makefile')) {
    Invoke-CheckCommand -Ctx $ctx -Name 'make_test' -Command 'make test' | Out-Null
    Invoke-CheckCommand -Ctx $ctx -Name 'make_bench' -Command 'make bench' | Out-Null
    Invoke-CheckCommand -Ctx $ctx -Name 'make_demo' -Command 'make demo' | Out-Null
}
$cgoEnabled = (& $ctx.GoCmd env CGO_ENABLED).Trim()
if ($cgoEnabled -eq '1') {
    Invoke-CheckCommand -Ctx $ctx -Name 'go_test_race' -Command "& '$($ctx.GoCmd)' test -race ./..." | Out-Null
}

$serverExe = Join-Path $ctx.OutputsDir 'event-memory-search-api.exe'
Invoke-CheckCommand -Ctx $ctx -Name 'build_api_server' -Command "& '$($ctx.GoCmd)' build -o '$serverExe' ./cmd/event-memory-search-api" | Out-Null

$probes = [ordered]@{}
$probes['minimum.scoring'] = [ordered]@{ implemented = $false; conformant = $false; details = ''; evidence = 'outputs/minimum_scoring.json' }
$probes['good.time_filter'] = [ordered]@{ implemented = $false; conformant = $false; details = ''; evidence = 'outputs/good_time_filter.json' }
$probes['good.nearby'] = [ordered]@{ implemented = $false; conformant = $false; details = ''; evidence = 'outputs/good_nearby.json' }
$probes['good.structured_errors'] = [ordered]@{ implemented = $false; conformant = $false; details = ''; evidence = 'outputs/good_structured_errors.json' }
$probes['excellent.large_dataset'] = [ordered]@{ implemented = $false; conformant = $false; details = ''; evidence = 'outputs/excellent_large_dataset.json' }
$probes['excellent.frontend_integration'] = [ordered]@{ implemented = $false; conformant = $false; details = ''; evidence = 'outputs/excellent_frontend_integration.json' }
$probes['excellent.error_cases'] = [ordered]@{ implemented = $false; conformant = $false; details = ''; evidence = 'outputs/excellent_error_cases.json' }

$healthImplemented = $false
$healthConformant = $false
$datasetsImplemented = $false
$datasetsConformant = $false
$searchImplemented = $false
$searchConformant = $false
$searchByIDImplemented = $false
$searchByIDConformant = $false
$contextImplemented = $false
$contextConformant = $false
$explainImplemented = $false
$explainConformant = $false

$tempDatasetsDir = Join-Path $ctx.TmpDir 'datasets'
$tempControlPath = Join-Path $tempDatasetsDir 'control.jsonl'
$tempLargePath = Join-Path $tempDatasetsDir 'large.jsonl'
$runtimePort = if ($Port -eq 0) { Get-FreeTcpPort } else { $Port }
$serverStdout = Join-Path $ctx.LogsDir 'server_stdout.log'
$serverStderr = Join-Path $ctx.LogsDir 'server_stderr.log'
$serverProc = $null

if ([int]$ctx.CommandResults['build_api_server'].exit_code -eq 0) {
    New-Item -ItemType Directory -Path $tempDatasetsDir -Force | Out-Null
    $controlSource = Join-Path $ctx.RepoRoot 'testdata\datasets\control.jsonl'
    if (-not (Test-Path -LiteralPath $controlSource)) {
        $controlSource = Join-Path $ctx.RepoRoot 'testdata\control\control.jsonl'
    }
    Copy-Item -LiteralPath $controlSource -Destination $tempControlPath -Force
    $largeMeta = New-LargeDatasetFile -Path $tempLargePath -Count 100000
    Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'large_dataset_generation.json') -Value $largeMeta

    $serverArgs = @('serve', '--datasets', $tempDatasetsDir, '--addr', "127.0.0.1:$runtimePort")
    $serverProc = Start-Process -FilePath $serverExe -ArgumentList $serverArgs -WorkingDirectory $ctx.RepoRoot -RedirectStandardOutput $serverStdout -RedirectStandardError $serverStderr -PassThru -WindowStyle Hidden
    Save-CheckJson -Path (Join-Path $ctx.MetaDir 'server_process.json') -Value ([ordered]@{
        pid = $serverProc.Id
        port = $runtimePort
        args = $serverArgs
        started_at = (Get-Date).ToString('o')
    })

    $baseUrl = "http://127.0.0.1:$runtimePort"
    try {
        $ready = $false
        $deadline = (Get-Date).AddSeconds(20)
        while (-not $ready -and (Get-Date) -lt $deadline) {
            $healthResp = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/health" -TimeoutSec 2
            if ($healthResp.status_code -eq 200 -and $healthResp.json -and $healthResp.json.status -eq 'ok') {
                $ready = $true
                Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'health.json') -Value $healthResp.json
                $healthImplemented = $true
                $healthConformant = $true
                break
            }
            Start-Sleep -Milliseconds 400
        }
        if (-not $ready) { throw 'server did not become ready' }

        $datasetsResp = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/datasets" -TimeoutSec 5
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'datasets.json') -Value $datasetsResp
        $datasetsImplemented = $true
        $datasetsConformant = ($datasetsResp.status_code -eq 200 -and $datasetsResp.json -and $datasetsResp.json.datasets)

        $scoringProbe = [ordered]@{}
        $searchBody1 = @'
{"dataset_id":"control","time":{"around":"2026-06-16T10:15:00Z","tolerance":"30m"},"hints":{"user_id":"ivan","file_name":"client base","action":"email_send","destination_type":"external"},"context":{"before":"30m","after":"10m","require_nearby":[{"action":"create_archive"},{"action":"email_send"}]},"scoring":{"min_score":50,"limit":20}}
'@
        $searchResp1 = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $searchBody1 -TimeoutSec 10
        $searchImplemented = $true
        $searchConformant = ($searchResp1.status_code -eq 200 -and $searchResp1.json -and $searchResp1.json.search_id)
        $searchByIDImplemented = $searchConformant
        $contextImplemented = $searchConformant
        $explainImplemented = $searchConformant
        $first = $null
        $sorted = $true
        $minScoreOk = $true
        $matchedHintsOk = $false
        $searchByIDOk = $false
        $contextOk = $false
        $explainOk = $false
        if ($searchConformant) {
            $candidates = @($searchResp1.json.candidates)
            if ($candidates.Count -gt 0) {
                $first = $candidates[0]
                $matched = @($first.matched_hints)
                $matchedHintsOk = (
                    ($matched -contains 'user_id') -and
                    ($matched -contains 'file_name') -and
                    ($matched -contains 'action') -and
                    ($matched -contains 'destination_type')
                )
                for ($i = 1; $i -lt $candidates.Count; $i++) {
                    if ([int]$candidates[$i-1].score -lt [int]$candidates[$i].score) { $sorted = $false }
                }
                foreach ($candidate in $candidates) {
                    if ([int]$candidate.score -lt 50) { $minScoreOk = $false }
                }
                $searchByIDResp = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/search/$($searchResp1.json.search_id)" -TimeoutSec 10
                Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'search_by_id.json') -Value $searchByIDResp
                $searchByIDOk = ($searchByIDResp.status_code -eq 200 -and $searchByIDResp.json.search_id -eq $searchResp1.json.search_id)
                $searchByIDConformant = $searchByIDOk

                $eventID = [string]$first.event_id
                $contextResp = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/events/$eventID/context?dataset_id=control&before=30m&after=10m" -TimeoutSec 10
                Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'event_context.json') -Value $contextResp
                $contextOk = ($contextResp.status_code -eq 200 -and $contextResp.json.event_id -eq $eventID)
                $contextConformant = $contextOk

                $explainResp = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/search/$($searchResp1.json.search_id)/candidates/$eventID/explain" -TimeoutSec 10
                Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'explain.json') -Value $explainResp
                $sum = 0
                if ($explainResp.json -and $explainResp.json.contributions) {
                    foreach ($part in @($explainResp.json.contributions)) { $sum += [int]$part.points }
                }
                $explainOk = ($explainResp.status_code -eq 200 -and $explainResp.json.event_id -eq $eventID -and $sum -eq [int]$explainResp.json.score)
                $explainConformant = $explainOk
            }
        }
        $searchBody2 = @'
{"dataset_id":"control","hints":{"file_name":"client base"},"scoring":{"min_score":0,"limit":1}}
'@
        $searchResp2 = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $searchBody2 -TimeoutSec 10
        $limitOk = ($searchResp2.status_code -eq 200 -and @($searchResp2.json.candidates).Count -le 1)
        $scoringConformant = (
            $searchConformant -and
            $first -and
            ($first.event_id -eq 'evt_exact') -and
            ([int]$first.score -eq 100) -and
            $matchedHintsOk -and
            $sorted -and
            $minScoreOk -and
            $limitOk -and
            $searchByIDOk
        )
        $scoringProbe['search1_status'] = $searchResp1.status_code
        $scoringProbe['search2_status'] = $searchResp2.status_code
        $scoringProbe['first_event_id'] = if ($first) { $first.event_id } else { '' }
        $scoringProbe['first_score'] = if ($first) { [int]$first.score } else { -1 }
        $scoringProbe['matched_hints_ok'] = $matchedHintsOk
        $scoringProbe['sorted_score_desc'] = $sorted
        $scoringProbe['min_score_inclusive_ok'] = $minScoreOk
        $scoringProbe['limit_ok'] = $limitOk
        $scoringProbe['search_by_id_ok'] = $searchByIDOk
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'minimum_scoring.json') -Value $scoringProbe
        $probes['minimum.scoring'].implemented = $true
        $probes['minimum.scoring'].conformant = $scoringConformant
        $probes['minimum.scoring'].details = "first=$($scoringProbe.first_event_id); score=$($scoringProbe.first_score)"

        $timeProbe = [ordered]@{}
        $timeNarrowBody = @'
{"dataset_id":"control","time":{"around":"2026-06-16T10:15:00Z","tolerance":"30m"},"scoring":{"min_score":0,"limit":100}}
'@
        $timeNarrowResp = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $timeNarrowBody -TimeoutSec 10
        $timeOutsideBody = @'
{"dataset_id":"control","time":{"around":"2026-06-20T10:15:00Z","tolerance":"1m"},"scoring":{"min_score":0,"limit":20}}
'@
        $timeOutsideResp = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $timeOutsideBody -TimeoutSec 10
        $narrowIDs = @()
        $outsideIDs = @()
        if ($timeNarrowResp.json -and $timeNarrowResp.json.candidates) {
            $narrowIDs = @($timeNarrowResp.json.candidates | ForEach-Object { [string]$_.event_id })
        }
        if ($timeOutsideResp.json -and $timeOutsideResp.json.candidates) {
            $outsideIDs = @($timeOutsideResp.json.candidates | ForEach-Object { [string]$_.event_id })
        }
        $boundaryIncluded = ($narrowIDs -contains 'evt_boundary')
        $outsideExcluded = -not ($narrowIDs -contains 'evt_outside')
        $outsideFound = ($outsideIDs -contains 'evt_outside')
        $timeProbe['boundary_included'] = $boundaryIncluded
        $timeProbe['outside_excluded_in_narrow'] = $outsideExcluded
        $timeProbe['outside_found_around_outside'] = $outsideFound
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'good_time_filter.json') -Value $timeProbe
        $probes['good.time_filter'].implemented = $true
        $probes['good.time_filter'].conformant = ($timeNarrowResp.status_code -eq 200 -and $timeOutsideResp.status_code -eq 200 -and $boundaryIncluded -and $outsideExcluded -and $outsideFound)
        $probes['good.time_filter'].details = "narrow_count=$($narrowIDs.Count); outside_count=$($outsideIDs.Count)"

        $nearbyProbe = [ordered]@{}
        $nearbyGoodBody = @'
{"dataset_id":"control","time":{"around":"2026-06-16T10:15:00Z","tolerance":"1h"},"context":{"before":"30m","after":"10m","require_nearby":[{"action":"create_archive"},{"action":"email_send"}]},"scoring":{"min_score":0,"limit":20}}
'@
        $nearbyShortBody = @'
{"dataset_id":"control","time":{"around":"2026-06-16T10:15:00Z","tolerance":"1h"},"context":{"before":"5m","after":"1m","require_nearby":[{"action":"create_archive"},{"action":"email_send"}]},"scoring":{"min_score":0,"limit":20}}
'@
        $nearbyMissingBody = @'
{"dataset_id":"control","time":{"around":"2026-06-16T10:15:00Z","tolerance":"1h"},"context":{"before":"30m","after":"10m","require_nearby":[{"action":"action_missing"}]},"scoring":{"min_score":0,"limit":20}}
'@
        $nearbyGoodResp = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $nearbyGoodBody -TimeoutSec 10
        $nearbyShortResp = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $nearbyShortBody -TimeoutSec 10
        $nearbyMissingResp = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $nearbyMissingBody -TimeoutSec 10
        $goodIDs = @($nearbyGoodResp.json.candidates | ForEach-Object { [string]$_.event_id })
        $shortIDs = @($nearbyShortResp.json.candidates | ForEach-Object { [string]$_.event_id })
        $missingIDs = @($nearbyMissingResp.json.candidates | ForEach-Object { [string]$_.event_id })
        $nearbyProbe['exact_included'] = ($goodIDs -contains 'evt_exact')
        $nearbyProbe['exact_excluded_short_window'] = -not ($shortIDs -contains 'evt_exact')
        $nearbyProbe['missing_action_excludes_all'] = ($missingIDs.Count -eq 0)
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'good_nearby.json') -Value $nearbyProbe
        $probes['good.nearby'].implemented = $true
        $probes['good.nearby'].conformant = ($nearbyGoodResp.status_code -eq 200 -and $nearbyShortResp.status_code -eq 200 -and $nearbyMissingResp.status_code -eq 200 -and $nearbyProbe.exact_included -and $nearbyProbe.exact_excluded_short_window -and $nearbyProbe.missing_action_excludes_all)
        $probes['good.nearby'].details = "good=$($goodIDs.Count); short=$($shortIDs.Count); missing=$($missingIDs.Count)"

        $structuredProbe = [ordered]@{}
        $errMalformed = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body '{"dataset_id":"control"' -TimeoutSec 10
        $errMethod = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/search" -TimeoutSec 10
        $errDataset = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body '{"dataset_id":"missing","scoring":{"min_score":0,"limit":1}}' -TimeoutSec 10
        $structuredProbe['invalid_json'] = Test-IsJsonErrorEnvelope -Response $errMalformed -StatusCode 400 -ErrorCode 'invalid_json'
        $structuredProbe['method_not_allowed'] = Test-IsJsonErrorEnvelope -Response $errMethod -StatusCode 405 -ErrorCode 'method_not_allowed'
        $structuredProbe['dataset_not_found'] = Test-IsJsonErrorEnvelope -Response $errDataset -StatusCode 404 -ErrorCode 'dataset_not_found'
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'good_structured_errors.json') -Value $structuredProbe
        $probes['good.structured_errors'].implemented = $true
        $probes['good.structured_errors'].conformant = ($structuredProbe.invalid_json -and $structuredProbe.method_not_allowed -and $structuredProbe.dataset_not_found)
        $probes['good.structured_errors'].details = "invalid_json=$($structuredProbe.invalid_json); method=$($structuredProbe.method_not_allowed); dataset=$($structuredProbe.dataset_not_found)"

        $errorCasesProbe = [ordered]@{}
        $errTime = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body '{"dataset_id":"control","time":{"around":"bad-time","tolerance":"30m"},"scoring":{"min_score":0,"limit":1}}' -TimeoutSec 10
        $errTolerance = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body '{"dataset_id":"control","time":{"around":"2026-06-16T10:15:00Z","tolerance":"bad"},"scoring":{"min_score":0,"limit":1}}' -TimeoutSec 10
        $errWide = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body '{"dataset_id":"control","time":{"around":"2026-06-16T10:15:00Z","tolerance":"31d"},"scoring":{"min_score":0,"limit":1}}' -TimeoutSec 10
        $errDataset2 = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body '{"dataset_id":"missing","scoring":{"min_score":0,"limit":1}}' -TimeoutSec 10
        $errorCasesProbe['invalid_time'] = (Test-IsJsonErrorEnvelope -Response $errTime -StatusCode 400 -ErrorCode 'invalid_time') -and ($errTime.json.error.field -eq 'around')
        $errorCasesProbe['invalid_duration'] = (Test-IsJsonErrorEnvelope -Response $errTolerance -StatusCode 400 -ErrorCode 'invalid_duration') -and ($errTolerance.json.error.field -eq 'tolerance')
        $errorCasesProbe['window_too_wide'] = (Test-IsJsonErrorEnvelope -Response $errWide -StatusCode 422 -ErrorCode 'window_too_wide')
        $errorCasesProbe['dataset_not_found'] = Test-IsJsonErrorEnvelope -Response $errDataset2 -StatusCode 404 -ErrorCode 'dataset_not_found'
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'excellent_error_cases.json') -Value $errorCasesProbe
        $probes['excellent.error_cases'].implemented = $true
        $probes['excellent.error_cases'].conformant = ($errorCasesProbe.invalid_time -and $errorCasesProbe.invalid_duration -and $errorCasesProbe.window_too_wide -and $errorCasesProbe.dataset_not_found)
        $probes['excellent.error_cases'].details = "time=$($errorCasesProbe.invalid_time); duration=$($errorCasesProbe.invalid_duration); wide=$($errorCasesProbe.window_too_wide); missing=$($errorCasesProbe.dataset_not_found)"

        $largeProbe = [ordered]@{}
        $datasetsLarge = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/datasets" -TimeoutSec 10
        $largeCount = 0
        foreach ($item in @($datasetsLarge.json.datasets)) {
            if ([string]$item.dataset_id -eq 'large') { $largeCount = [int]$item.event_count }
        }
        $largeBody = @'
{"dataset_id":"large","time":{"around":"2026-06-16T10:15:00Z","tolerance":"30d"},"hints":{"user_id":"target_user","file_name":"large_target_054321","action":"email_send","destination_type":"external"},"scoring":{"min_score":100,"limit":1}}
'@
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $largeResp = Invoke-HttpRequestSafe -Method 'POST' -Uri "$baseUrl/api/search" -Body $largeBody -TimeoutSec 10
        $sw.Stop()
        $largeSearchDuration = $sw.ElapsedMilliseconds
        $largeByIDOk = $false
        if ($largeResp.status_code -eq 200 -and $largeResp.json.search_id) {
            $largeByID = Invoke-HttpRequestSafe -Method 'GET' -Uri "$baseUrl/api/search/$($largeResp.json.search_id)" -TimeoutSec 10
            $largeByIDOk = ($largeByID.status_code -eq 200 -and $largeByID.json.search_id -eq $largeResp.json.search_id)
        }
        $largeTopID = ''
        if ($largeResp.json -and $largeResp.json.candidates -and @($largeResp.json.candidates).Count -gt 0) {
            $largeTopID = [string]$largeResp.json.candidates[0].event_id
        }
        $largeProbe['event_count'] = $largeCount
        $largeProbe['search_duration_ms'] = [int]$largeSearchDuration
        $largeProbe['search_under_5s'] = ($largeSearchDuration -le 5000)
        $largeProbe['top_event_id'] = $largeTopID
        $largeProbe['search_by_id_ok'] = $largeByIDOk
        $largeProbe['large_generation'] = $largeMeta
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'excellent_large_dataset.json') -Value $largeProbe
        $probes['excellent.large_dataset'].implemented = $true
        $probes['excellent.large_dataset'].conformant = ($largeCount -eq 100000 -and $largeResp.status_code -eq 200 -and $largeTopID -eq 'large_target_054321' -and $largeProbe.search_under_5s -and $largeByIDOk)
        $probes['excellent.large_dataset'].details = "count=$largeCount; duration_ms=$largeSearchDuration; top=$largeTopID"

        $frontendOut = Join-Path $ctx.OutputsDir 'frontend_demo.json'
        Invoke-CheckCommand -Ctx $ctx -Name 'frontend_demo_runtime' -Command "& '$serverExe' demo --base-url '$baseUrl' --dataset control --out '$frontendOut'" | Out-Null
        $frontendProbe = [ordered]@{
            command_exit = [int]$ctx.CommandResults['frontend_demo_runtime'].exit_code
            status_ok = $false
            steps_ok = $false
            ids_ok = $false
        }
        if ((Test-Path -LiteralPath $frontendOut) -and $frontendProbe.command_exit -eq 0) {
            $frontendJson = Get-Content -LiteralPath $frontendOut -Raw | ConvertFrom-Json
            $stepNames = @($frontendJson.steps | ForEach-Object { [string]$_.name })
            $frontendProbe.status_ok = ($frontendJson.status -eq 'ok')
            $frontendProbe.steps_ok = (($stepNames -join ',') -eq 'datasets,search,search_by_id,context,explain')
            $frontendProbe.ids_ok = (-not [string]::IsNullOrWhiteSpace([string]$frontendJson.search_id) -and -not [string]::IsNullOrWhiteSpace([string]$frontendJson.event_id))
        }
        Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'excellent_frontend_integration.json') -Value $frontendProbe
        $probes['excellent.frontend_integration'].implemented = $true
        $probes['excellent.frontend_integration'].conformant = ($frontendProbe.command_exit -eq 0 -and $frontendProbe.status_ok -and $frontendProbe.steps_ok -and $frontendProbe.ids_ok)
        $probes['excellent.frontend_integration'].details = "status=$($frontendProbe.status_ok); steps=$($frontendProbe.steps_ok); ids=$($frontendProbe.ids_ok)"
    }
    finally {
        if ($serverProc -and -not $serverProc.HasExited) {
            Stop-Process -Id $serverProc.Id -Force
            try { Wait-Process -Id $serverProc.Id -Timeout 10 -ErrorAction SilentlyContinue } catch {}
        }
        $stopped = $true
        if ($serverProc) { $stopped = $serverProc.HasExited }
        Save-CheckJson -Path (Join-Path $ctx.MetaDir 'server_stop.json') -Value ([ordered]@{
            pid = if ($serverProc) { $serverProc.Id } else { $null }
            stopped = $stopped
            stopped_at = (Get-Date).ToString('o')
        })
    }
}

$largeRemoved = $false
if (Test-Path -LiteralPath $tempDatasetsDir) {
    Remove-Item -LiteralPath $tempDatasetsDir -Recurse -Force
    $largeRemoved = -not (Test-Path -LiteralPath $tempLargePath)
}
Save-CheckJson -Path (Join-Path $ctx.OutputsDir 'cleanup.json') -Value ([ordered]@{
    runtime_port = $runtimePort
    temp_datasets_removed = -not (Test-Path -LiteralPath $tempDatasetsDir)
    large_removed = $largeRemoved
})

Add-BooleanFeatureAssessment -Ctx $ctx -Id 'minimum.health' -Level 'minimum' -Category 'api' -Requirement 'Backend starts and answers /api/health' -Implemented $healthImplemented -Conformant $healthConformant -Evidence @('outputs/health.json')
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'minimum.datasets' -Level 'minimum' -Category 'api' -Requirement 'GET /api/datasets returns datasets' -Implemented $datasetsImplemented -Conformant $datasetsConformant -Evidence @('outputs/datasets.json')
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'minimum.search' -Level 'minimum' -Category 'api' -Requirement 'POST /api/search returns candidates' -Implemented $searchImplemented -Conformant $searchConformant -Evidence @('outputs/minimum_scoring.json')
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'minimum.scoring' -Level 'minimum' -Category 'algorithm' -Requirement 'Runtime scoring validates order, matched_hints, limit and min_score' -Implemented $probes['minimum.scoring'].implemented -Conformant $probes['minimum.scoring'].conformant -Evidence @($probes['minimum.scoring'].evidence) -Details $probes['minimum.scoring'].details

Add-BooleanFeatureAssessment -Ctx $ctx -Id 'good.search_by_id' -Level 'good' -Category 'api' -Requirement 'GET /api/search/{search_id} returns stored result' -Implemented $searchByIDImplemented -Conformant $searchByIDConformant -Evidence @('outputs/search_by_id.json')
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'good.context' -Level 'good' -Category 'api' -Requirement 'GET /api/events/{event_id}/context returns context' -Implemented $contextImplemented -Conformant $contextConformant -Evidence @('outputs/event_context.json')
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'good.explain' -Level 'good' -Category 'api' -Requirement 'Explain returns score contributions with exact sum' -Implemented $explainImplemented -Conformant $explainConformant -Evidence @('outputs/explain.json')
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'good.time_filter' -Level 'good' -Category 'algorithm' -Requirement 'Runtime time filter validates boundary, around and outside event' -Implemented $probes['good.time_filter'].implemented -Conformant $probes['good.time_filter'].conformant -Evidence @($probes['good.time_filter'].evidence) -Details $probes['good.time_filter'].details
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'good.nearby' -Level 'good' -Category 'algorithm' -Requirement 'Runtime nearby checks all required rules and windows' -Implemented $probes['good.nearby'].implemented -Conformant $probes['good.nearby'].conformant -Evidence @($probes['good.nearby'].evidence) -Details $probes['good.nearby'].details
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'good.structured_errors' -Level 'good' -Category 'api' -Requirement 'Runtime structured errors return code/message/field and JSON content type' -Implemented $probes['good.structured_errors'].implemented -Conformant $probes['good.structured_errors'].conformant -Evidence @($probes['good.structured_errors'].evidence) -Details $probes['good.structured_errors'].details
$apiDocsPath = Join-Path $ctx.RepoRoot 'docs\api.md'
$apiDocsOk = (Test-Path -LiteralPath $apiDocsPath) -and ((Get-Item -LiteralPath $apiDocsPath).Length -gt 64)
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'good.api_docs' -Level 'good' -Category 'documentation' -Requirement 'API documentation artifact exists' -Implemented $apiDocsOk -Conformant $apiDocsOk -Evidence @('docs/api.md')

Add-BooleanFeatureAssessment -Ctx $ctx -Id 'excellent.large_dataset' -Level 'excellent' -Category 'performance' -Requirement 'Runtime 100000 dataset search and search-by-id pass under time budget' -Implemented $probes['excellent.large_dataset'].implemented -Conformant $probes['excellent.large_dataset'].conformant -Evidence @($probes['excellent.large_dataset'].evidence, 'outputs/large_dataset_generation.json') -Details $probes['excellent.large_dataset'].details
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'excellent.frontend_integration' -Level 'excellent' -Category 'integration' -Requirement 'Demo CLI runs five real API steps with consistent IDs' -Implemented $probes['excellent.frontend_integration'].implemented -Conformant $probes['excellent.frontend_integration'].conformant -Evidence @($probes['excellent.frontend_integration'].evidence, 'outputs/frontend_demo.json', 'logs/frontend_demo_runtime.log') -Details $probes['excellent.frontend_integration'].details
Add-BooleanFeatureAssessment -Ctx $ctx -Id 'excellent.error_cases' -Level 'excellent' -Category 'api' -Requirement 'Runtime invalid time/duration/window/missing dataset checks pass' -Implemented $probes['excellent.error_cases'].implemented -Conformant $probes['excellent.error_cases'].conformant -Evidence @($probes['excellent.error_cases'].evidence) -Details $probes['excellent.error_cases'].details

Complete-Check -Ctx $ctx -Extra @{
    runtime_port = $runtimePort
    expected_api = @('/api/health','/api/datasets','POST /api/search','GET /api/search/{search_id}','GET /api/events/{event_id}/context','GET /api/search/{search_id}/candidates/{event_id}/explain')
    probe_files = @('outputs/minimum_scoring.json','outputs/good_time_filter.json','outputs/good_nearby.json','outputs/good_structured_errors.json','outputs/excellent_large_dataset.json','outputs/excellent_frontend_integration.json','outputs/excellent_error_cases.json')
}


