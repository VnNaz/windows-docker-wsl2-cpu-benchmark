<#
Full reproducible set of 8 arithmetic operations x 5 process counts x 2
execution environments. Runs are interleaved and saved individually.
Example:
  .\run_all_tests_v3.ps1 -Rounds 5 -Iterations 1000000000 -ResultsDir .\results_article
Run from the directory containing benchmark_ops.exe and Dockerfile.
#>
param(
  [ValidateRange(1,30)][int]$Rounds = 5,
  [ValidateRange(1,100000000000)][long]$Iterations = 1000000000,
  [string]$ResultsDir = '.\results_article'
)
$ErrorActionPreference = 'Stop'
$tests = @('int_add', 'int_sub', 'int_mul', 'int_div',
           'double_add', 'double_sub', 'double_mul', 'double_div')
$counts = @(1, 8, 16, 24, 32)
$totalSessions = $tests.Count * $counts.Count * 2 * $Rounds
$completed = 0

if (-not (Test-Path .\benchmark_ops.exe)) {
    throw 'benchmark_ops.exe missing: compile the C++ source with g++ first.'
}
& docker image inspect cpu-benchmark-2026 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker image cpu-benchmark-2026 missing: run docker build first.'
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw 'Python missing from PATH.'
}
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$folder = (Resolve-Path $ResultsDir).Path
$sourceHash = (Get-FileHash .\benchmark_ops.cpp -Algorithm SHA256).Hash
$winExeHash = (Get-FileHash .\benchmark_ops.exe -Algorithm SHA256).Hash
$manifestPath = Join-Path $folder 'experiment_manifest.json'
if (Test-Path $manifestPath) {
    $old = Get-Content -Raw $manifestPath | ConvertFrom-Json
    if ($old.source_sha256 -ne $sourceHash -or
        $old.windows_exe_sha256 -ne $winExeHash -or
        [long]$old.iterations -ne $Iterations) {
        throw "Existing results use different source, executable or iterations. Choose a NEW ResultsDir."
    }
} else {
    $manifest = [ordered]@{
        started_at_utc = ([DateTimeOffset]::UtcNow.ToString('o'))
        source_sha256 = $sourceHash
        windows_exe_sha256 = $winExeHash
        iterations = $Iterations
        expected_rounds = $Rounds
        environments = @('Windows', 'Docker')
        operations = $tests
        process_counts = $counts
        note = 'One operation per process; Windows/Docker order alternates by round.'
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8
}

function Test-CompleteSession([string]$envName, [string]$testName, [int]$n, [int]$r) {
    for ($i=1; $i -le $n; $i++) {
        $name = '{0}_{1}_n{2}_r{3}_i{4}.csv' -f $envName,$testName,$n,$r,$i
        $path = Join-Path $folder $name
        if (-not (Test-Path $path)) { return $false }
        try {
            $data = @(Import-Csv -Path $path)
            if ($data.Count -ne 1) { return $false }
            if ($data[0].test -ne $testName) { return $false }
            if ([long]$data[0].iterations -ne $Iterations) { return $false }
            if ([double]::Parse($data[0].wall_sec, [Globalization.CultureInfo]::InvariantCulture) -le 0) { return $false }
            if (([long]$data[0].start_unix_ms - [long]$data[0].target_unix_ms) -gt 1000) { return $false }
        } catch { return $false }
    }
    return $true
}

foreach ($test in $tests) {
    foreach ($n in $counts) {
        for ($r=1; $r -le $Rounds; $r++) {
            # Alternate the environment order across independent sessions.
            if ($r % 2 -eq 1) { $envs = @('Windows','Docker') }
            else { $envs = @('Docker','Windows') }
            foreach ($envName in $envs) {
                $completed++
                $percent = [int](100 * ($completed - 1) / $totalSessions)
                Write-Progress -Activity 'CPU experiment' -Status "$completed/$totalSessions $test N=$n round=$r $envName" -PercentComplete $percent
                if (Test-CompleteSession $envName $test $n $r) {
                    Write-Host "SKIP complete: $envName $test N=$n round=$r"
                    continue
                }
                # Some processes may start too late due to antivirus, Docker startup or CPU contention.
                # Keep the 1000 ms quality threshold; retry the ENTIRE group with more lead time.
                $baseLead = if ($envName -eq 'Windows') {
                    if ($n -ge 32) { 45 }
                    elseif ($n -ge 24) { 35 }
                    elseif ($n -ge 16) { 25 }
                    else { 15 }
                } else {
                    if ($n -ge 32) { 90 }
                    elseif ($n -ge 24) { 60 }
                    elseif ($n -ge 16) { 40 }
                    elseif ($n -ge 8) { 20 }
                    else { 12 }
                }
                $maxAttempts = 3
                $valid = $false
                for ($attempt=1; $attempt -le $maxAttempts; $attempt++) {
                    # Archive ALL outputs from an unsuccessful group before retrying.
                    # This prevents a mixture of instance results from different attempts.
                    $invalidDir = Join-Path $folder '_invalid_attempts'
                    for ($i=1; $i -le $n; $i++) {
                        $stem = '{0}_{1}_n{2}_r{3}_i{4}' -f $envName,$test,$n,$r,$i
                        foreach ($ext in @('.csv','.stderr.txt')) {
                            $oldPath = Join-Path $folder ($stem + $ext)
                            if (Test-Path $oldPath) {
                                New-Item -ItemType Directory -Force -Path $invalidDir | Out-Null
                                $newName = $stem + '.before_attempt_' + $attempt + $ext
                                Move-Item -LiteralPath $oldPath -Destination (Join-Path $invalidDir $newName) -Force
                            }
                        }
                    }
                    $lead = [int][math]::Min(290, $baseLead * [math]::Pow(2, ($attempt - 1)))
                    Write-Host "RUN $completed/$totalSessions : $envName $test N=$n round=$r attempt=$attempt/$maxAttempts lead=${lead}s"
                    try {
                        & .\run_windows_or_docker.ps1 `
                            -Environment $envName `
                            -Test $test `
                            -Count $n `
                            -Rounds 1 `
                            -RoundStart $r `
                            -Iterations $Iterations `
                            -LeadSeconds $lead `
                            -ResultsDir $folder
                    } catch {
                        Write-Warning "Group launcher error: $($_.Exception.Message)"
                    }
                    if (Test-CompleteSession $envName $test $n $r) {
                        $valid = $true
                        break
                    }
                    # Report observed delays for troubleshooting; do not accept late starts.
                    $delays = @()
                    for ($i=1; $i -le $n; $i++) {
                        $csvName = '{0}_{1}_n{2}_r{3}_i{4}.csv' -f $envName,$test,$n,$r,$i
                        $csvPath = Join-Path $folder $csvName
                        if (Test-Path $csvPath) {
                            try {
                                $row = Import-Csv $csvPath | Select-Object -First 1
                                if ($row) { $delays += ([long]$row.start_unix_ms - [long]$row.target_unix_ms) }
                            } catch {}
                        }
                    }
                    $delayNote = ' (no readable CSV)'
                    if ($delays.Count -gt 0) {
                        $maxDelay = [long](($delays | Measure-Object -Maximum).Maximum)
                        $delayNote = " max_start_delay_ms=$maxDelay"
                    }
                    Write-Warning "Invalid or incomplete group:$delayNote; retrying if attempts remain."
                }
                if (-not $valid) {
                    throw "Group still invalid after $maxAttempts attempts: $envName $test N=$n round=$r. See $folder\_invalid_attempts and stderr."
                }
            }
        }
    }
}
Write-Progress -Activity 'CPU experiment' -Completed
& python .\summarize_results.py $folder
if ($LASTEXITCODE -ne 0) { throw 'Summarization failed' }
$dest = Join-Path (Split-Path $folder -Parent) ('cpu_results_' + (Split-Path $folder -Leaf) + '.zip')
if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Force }
Compress-Archive -Path (Join-Path $folder '*') -DestinationPath $dest -CompressionLevel Optimal
Write-Host "DONE. Send this archive: $dest"
