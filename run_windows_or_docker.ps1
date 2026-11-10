<#
PowerShell 7/Windows PowerShell 5.1: run from the directory containing benchmark_ops.exe.
Each repetition is an independently launched group (not 10 repetitions inside one process).
Examples:
  .\run_windows_or_docker.ps1 -Environment Windows -Test int_add -Count 32 -Rounds 5
  .\run_windows_or_docker.ps1 -Environment Docker  -Test int_add -Count 32 -Rounds 5
#>
param(
  [ValidateSet('Windows','Docker')][string]$Environment = 'Windows',
  [ValidateSet('int_add','int_sub','int_mul','int_div','double_add','double_sub','double_mul','double_div')][string]$Test = 'int_add',
  [ValidateRange(1,128)][int]$Count = 32,
  [ValidateRange(1,100)][int]$Rounds = 5,
  [ValidateRange(1,1000)][int]$RoundStart = 1,
  [long]$Iterations = 1000000000,
  [ValidateRange(3,300)][int]$LeadSeconds = 30,
  [string]$ResultsDir = './results'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$resolvedResults = (Resolve-Path $ResultsDir).Path
for ($rIndex=0; $rIndex -lt $Rounds; $rIndex++) {
    $round = $RoundStart + $rIndex
    if ($Iterations -lt 1) { throw "Iterations must be positive" }
    $target = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ([long]$LeadSeconds * 1000)
    $processes = @()
    Write-Host "Group $($rIndex + 1)/${Rounds}: $Environment $Test count=$Count round=$round target=$target"
    for ($i=1; $i -le $Count; $i++) {
        $stem = '{0}_{1}_n{2}_r{3}_i{4}' -f $Environment, $Test, $Count, $round, $i
        $out = Join-Path $resolvedResults "$stem.csv"
        $err = Join-Path $resolvedResults "$stem.stderr.txt"
        if ($Environment -eq 'Windows') {
            $argumentList = @($Test, [string]$Iterations, [string]$target)
            $p = Start-Process -FilePath '.\benchmark_ops.exe' -ArgumentList $argumentList -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
        } else {
            $containerName = ('cpu-bench-{0}-{1}-{2}-{3}' -f $Test, $Count, $round, $i).ToLower()
            $argumentList = @('run','--rm','--name',$containerName,'cpu-benchmark-2026',$Test,[string]$Iterations,[string]$target)
            $p = Start-Process -FilePath 'docker.exe' -ArgumentList $argumentList -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
        }
        $processes += $p
    }
    $processes | Wait-Process
    $failures = @($processes | Where-Object { $_.Refresh(); $_.ExitCode -ne 0 })
    if ($failures.Count -gt 0) { Write-Warning "$($failures.Count) process(es) exited with error. See *.stderr.txt" }
    $targetIso = [DateTimeOffset]::FromUnixTimeMilliseconds($target).ToString('o')
    Write-Host "Finished group $round (planned start $targetIso)"
}
