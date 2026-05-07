# Real-device regression harness for MoonECAT.
#
# Drives the full scan -> validate -> state -> run path against a live EtherCAT
# slave on a specified network interface, captures both the progress NDJSON and
# the per-frame NicEventLog NDJSON (via `run --record`), and writes a manifest
# tagged with `real-device` so future regression runs can be cross-compared.
#
# Usage:
#   ./scripts/regression-real-device.ps1 \
#       -Interface "\Device\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}" \
#       -EsiJson "References/VT_EX_CA20_20250225.esi.json" \
#       -DeviceIndex 0 \
#       -Station 4097 \
#       -Cycles 200 -CyclePeriodUs 1000
#
# `-Interface` is optional: if omitted, the native backend will auto-pick a
# candidate via BRD probe. `-EsiJson` is required because real-device startup
# planning (state / run) must consume an ESI JSON. Default startup target is
# `op`, matching the normal `moon run cmd/main run -- --esi-json ...` path.
#
# Output layout (under -OutputRoot, default artifacts/regression-real-device):
#   <stamp>/
#     manifest.json               # tagged "real-device"
#     01-list-if.json
#     02-scan.json
#     03-validate.json
#     04-state-preop.json
#     05-state-safeop.json        (skipped if --SkipSafeOp)
#     06-run-progress.ndjson
#     07-run-recording.ndjson     # from --record (frame-level NicEventLog)
#     08-fault-summary.json
#
# Each JSON step is emitted with --json so its schema is stable. The recording
# NDJSON header carries slave_count and topology fingerprint.

param(
    [string]$Interface = "",

    [string]$Backend = "native-windows-npcap",
    [string]$Workspace = ".",
    [string]$OutputRoot = "artifacts/regression-real-device",
    [int]$TimeoutMs = 100,
    [int]$Cycles = 200,
    [int]$CyclePeriodUs = 1000,
    [int]$OutputPeriodMs = 1000,
    [int]$MaxConsecutiveTimeouts = 5,
    [string]$StartupState = "op",
    [string]$ShutdownState = "init",
    [string]$Station = "",
    [switch]$SkipSafeOp,
    # Real-device runs need an ESI JSON + device-index for startup planning.
    # Example: -EsiJson "References/VT_EX_CA20_20250225.esi.json" -DeviceIndex 0
    [Parameter(Mandatory = $true)]
    [string]$EsiJson,
    [int]$DeviceIndex = 0,
    [string]$Tag = "real-device",
    [string[]]$ExtraTags = @()
)

$ErrorActionPreference = "Stop"

function Invoke-MoonEcatStep {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [string[]]$Args,
        [Parameter(Mandatory = $true)] [string]$OutputFile
    )
    Write-Host "==> $Name"
    Write-Host (("moon " + (($Args | ForEach-Object { if ($_ -match "\s") { '"' + $_ + '"' } else { $_ } }) -join " ")))
    & moon @Args 2>&1 | Tee-Object -FilePath $OutputFile
    if ($LASTEXITCODE -ne 0) {
        throw "Step '$Name' failed with exit code $LASTEXITCODE"
    }
}

$workspacePath = Resolve-Path $Workspace
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $workspacePath (Join-Path $OutputRoot $stamp)
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

# Resolve and sanity-check the ESI JSON path before any moon invocation.
if (-not (Test-Path $EsiJson)) {
    throw "ESI JSON not found: $EsiJson"
}
$esiJsonResolved = (Resolve-Path $EsiJson).Path

$commonNativeArgs = @("--backend", $Backend, "--timeout-ms", $TimeoutMs)
if ($Interface -ne "") {
    $commonNativeArgs += @("--if", $Interface)
}
# Args added to commands that participate in startup planning (state, run).
$esiArgs = @("--esi-json", $esiJsonResolved, "--device-index", $DeviceIndex)

Invoke-MoonEcatStep -Name "list-if" `
    -Args (@("run", "cmd/main", "list-if", "--", "--backend", $Backend, "--json")) `
    -OutputFile (Join-Path $logDir "01-list-if.json")

Invoke-MoonEcatStep -Name "scan" `
    -Args (@("run", "cmd/main", "scan", "--") + $commonNativeArgs + @("--json")) `
    -OutputFile (Join-Path $logDir "02-scan.json")

Invoke-MoonEcatStep -Name "validate" `
    -Args (@("run", "cmd/main", "validate", "--") + $commonNativeArgs + @("--json")) `
    -OutputFile (Join-Path $logDir "03-validate.json")

if ($Station -ne "") {
    Invoke-MoonEcatStep -Name "state-path-preop" `
        -Args (@("run", "cmd/main", "state", "--") + $commonNativeArgs + $esiArgs + @("--json", "--station", $Station, "--path", "--state", "preop")) `
        -OutputFile (Join-Path $logDir "04-state-preop.json")

    if (-not $SkipSafeOp) {
        Invoke-MoonEcatStep -Name "state-path-safeop" `
            -Args (@("run", "cmd/main", "state", "--") + $commonNativeArgs + $esiArgs + @("--json", "--station", $Station, "--path", "--state", "safeop")) `
            -OutputFile (Join-Path $logDir "05-state-safeop.json")
    }
}

$runProgress = Join-Path $logDir "06-run-progress.ndjson"
$runRecording = Join-Path $logDir "07-run-recording.ndjson"
$faultSummary = Join-Path $logDir "08-fault-summary.json"

$runArgs = @("run", "cmd/main", "run", "--") + $commonNativeArgs + $esiArgs + @(
    "--json", "--progress-ndjson",
    "--cycles", $Cycles, "--cycle-period-us", $CyclePeriodUs,
    "--output-period-ms", $OutputPeriodMs,
    "--max-consecutive-timeouts", $MaxConsecutiveTimeouts,
    "--startup-state", $StartupState, "--shutdown-state", $ShutdownState,
    "--record", $runRecording
)

Write-Host "==> run --record (cycles=$Cycles, period=${CyclePeriodUs}us)"
Write-Host (("moon " + (($runArgs | ForEach-Object { if ($_ -match "\s") { '"' + $_ + '"' } else { $_ } }) -join " ")))
& moon @runArgs 2>&1 | Tee-Object -FilePath $runProgress

if (Test-Path $runProgress) {
    & (Join-Path $PSScriptRoot "summarize-run-ndjson.ps1") -InputPath $runProgress -OutputPath $faultSummary
}

# Build manifest with run-summary line metadata if present.
$runSummary = $null
if (Test-Path $runProgress) {
    $lastSummary = Get-Content $runProgress | Where-Object { $_ -match '"kind"\s*:\s*"run-summary"' } | Select-Object -Last 1
    if ($lastSummary) {
        try { $runSummary = $lastSummary | ConvertFrom-Json } catch { $runSummary = $null }
    }
}

$tags = @($Tag) + $ExtraTags | Where-Object { $_ }

$manifest = [ordered]@{
    generated_at     = (Get-Date).ToString("o")
    tags             = $tags
    interface        = $Interface
    backend          = $Backend
    esi_json         = $esiJsonResolved
    device_index     = $DeviceIndex
    timeout_ms       = $TimeoutMs
    cycles_requested = $Cycles
    cycle_period_us  = $CyclePeriodUs
    startup_state    = $StartupState
    shutdown_state   = $ShutdownState
    station          = $Station
    skip_safeop      = [bool]$SkipSafeOp
    artifacts        = [ordered]@{
        list_if       = "01-list-if.json"
        scan          = "02-scan.json"
        validate      = "03-validate.json"
        state_preop   = if ($Station -ne "") { "04-state-preop.json" } else { $null }
        state_safeop  = if (($Station -ne "") -and (-not $SkipSafeOp)) { "05-state-safeop.json" } else { $null }
        run_progress  = "06-run-progress.ndjson"
        run_recording = "07-run-recording.ndjson"
        fault_summary = "08-fault-summary.json"
    }
    run_summary      = $runSummary
}
$manifestPath = Join-Path $logDir "manifest.json"
$manifest | ConvertTo-Json -Depth 12 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host ""
Write-Host "Regression artifacts ($Tag):"
Write-Host ("  manifest:      " + $manifestPath)
Write-Host ("  list-if:       " + (Join-Path $logDir "01-list-if.json"))
Write-Host ("  scan:          " + (Join-Path $logDir "02-scan.json"))
Write-Host ("  validate:      " + (Join-Path $logDir "03-validate.json"))
if ($Station -ne "") {
    Write-Host ("  state preop:   " + (Join-Path $logDir "04-state-preop.json"))
    if (-not $SkipSafeOp) {
        Write-Host ("  state safeop:  " + (Join-Path $logDir "05-state-safeop.json"))
    }
}
Write-Host ("  run progress:  " + $runProgress)
Write-Host ("  run recording: " + $runRecording)
if (Test-Path $faultSummary) {
    Write-Host ("  fault summary: " + $faultSummary)
}
Write-Host ""
Write-Host "Next step (closed-loop): scripts/replay-diff.ps1 -RegressionDir `"$logDir`""
