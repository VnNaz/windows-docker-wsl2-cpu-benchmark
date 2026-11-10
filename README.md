# Windows vs Docker Desktop (WSL 2): CPU arithmetic benchmark

This repository contains the C++ benchmark, Windows PowerShell launch scripts, Python result processing, and the accepted measurements used to compare CPU-intensive arithmetic workloads on Windows 11 and Docker Desktop (WSL 2).

## Experiment

- 8 arithmetic tests: `int_add`, `int_sub`, `int_mul`, `int_div`, `double_add`, `double_sub`, `double_mul`, `double_div`.
- Concurrent instances: 1, 8, 16, 24, 32.
- 5 independently launched groups for each test, instance count, and environment.
- 2 execution environments: Windows and Docker Desktop using WSL 2.
- Each instance performs 1,000,000,000 iterations.
- Total: 400 group runs and 6,480 accepted individual measurements.

## Requirements

Windows 11 with Docker Desktop configured for Linux containers via WSL 2, `g++` in `PATH` for Windows, PowerShell, and Python. Install plotting dependencies with:

```powershell
python -m pip install -r requirements.txt
```

## Build

Open PowerShell at the repository root:

```powershell
g++ -std=c++17 -O2 benchmark_ops.cpp -o benchmark_ops.exe
docker build -t cpu-benchmark-2026 .
```

## Run the experiment

```powershell
.\run_all_tests_v3.ps1 -Rounds 5 -Iterations 1000000000 -ResultsDir .\results_article
```

The script coordinates concurrent launches, checks completeness and start delays, retries unsuccessful groups, and writes a summary when finished. A single group can be run with `run_windows_or_docker.ps1`. Benchmark runtime and hardware-dependent results will vary by machine.

## Included measured results

- `data/raw_measurements.zip` — the 6,480 accepted per-process CSV files (extract before recomputing summaries).
- `data/session_summary.csv` — per-group summaries (400 groups).
- `data/condition_summary.csv` — results averaged across five group runs (80 configurations).
- `data/experiment_manifest.json` — original experimental parameters and hashes of the benchmark C++ source and Windows executable.
- `figures/` — generated figures for the lab report.

Records from unsuccessful launch attempts and empty stderr logs are excluded from this publication bundle. The original experiment archive is retained separately.

To recompute summaries, extract `data/raw_measurements.zip` to `data/raw_measurements/`, then run:

```powershell
python .\summarize_results.py .\data\raw_measurements
```

To regenerate the included charts from the published condition summary:

```powershell
python .\plot_chapter3.py --input .\data --output .\figures_check
```

## Methodology note

`wall_sec` measures elapsed computation time, while `cpu_sec` measures the CPU time charged to the process. Throughput in MOPS counts loop iterations per second, not instructions retired. The `int_div` loop includes a bitwise OR before unsigned integer division.
