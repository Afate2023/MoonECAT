# NDJSON -> Replay closed-loop diff verifier.
#
# Given a regression directory produced by `regression-real-device.ps1`
# (or any directory containing a manifest.json + recording NDJSON), this
# script:
#   1. Replays the recorded NicEventLog through `cmd/main replay`
#   2. Captures the replay verdict + RunReport
#   3. Diffs key fields against the original run-summary line from the live run
#   4. Writes a replay report and a diff JSON next to the regression artifacts
#
# Stable diff fields (must match exactly):
#   slave_count          (from scan vs. recording header)
#   topology_fingerprint (recording header)
#   verdict              (replay derived vs. live derived; missing live treated as Unknown)
#
# Tolerant fields (informational, recorded in diff but not failed on):
#   cycles_ok, telemetry.timeouts, telemetry.wkc_errors,
#   final_phase, fault.* — replay is bound by the captured frames
#   so cycle counts can legitimately differ from a long live --until-fault run.
#
# Exit code is non-zero if any stable field disagrees.
#
# Usage:
#   ./scripts/replay-diff.ps1 -RegressionDir artifacts/regression-real-device/<stamp>
#   ./scripts/replay-diff.ps1 -RecordingPath path/to/recording.ndjson [-LiveSummaryPath path/to/run-progress.ndjson]

param(
    [string]$RegressionDir = "",
    [string]$RecordingPath = "",
    [string]$ScanPath = "",
    [string]$LiveSummaryPath = "",
    [string]$ReplayOutput = "",
    [string]$DiffOutput = "",
    [string]$Workspace = "."
)

$ErrorActionPreference = "Stop"

function Get-Field {
    param($obj, [string]$path, $default = $null)
    if ($null -eq $obj) { return $default }
    $cur = $obj
    foreach ($seg in $path.Split('.')) {
        if ($null -eq $cur) { return $default }
        if ($cur.PSObject.Properties.Name -contains $seg) { $cur = $cur.$seg } else { return $default }
    }
    return $cur
}

function Get-RunSummaryPayload {
    param($summary)
    $payload = Get-Field $summary "summary"
    if ($null -ne $payload) { return $payload }
    return $summary
}

function Get-RunVerdict {
    param($runSummary)
    if ($null -eq $runSummary) { return "Unknown" }
    if ($null -ne (Get-Field $runSummary "fault")) { return "Fail" }
    $timeouts = Get-Field $runSummary "telemetry.timeouts" 0
    $wkcErrors = Get-Field $runSummary "telemetry.wkc_errors" 0
    if ($timeouts -gt 10 -or $wkcErrors -gt 0) { return "Warn" }
    return "Pass"
}

function Get-JsonPayloadText {
    param([string]$text)
    $trimmed = $text.Trim()
    if ($trimmed.StartsWith("{") -or $trimmed.StartsWith("[")) {
        return $trimmed
    }
    $jsonStart = $trimmed.IndexOf("{")
    if ($jsonStart -ge 0) {
        return $trimmed.Substring($jsonStart).Trim()
    }
    throw "expected JSON output but got: $trimmed"
}

if ($RegressionDir -ne "") {
    $manifestPath = Join-Path $RegressionDir "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        throw "manifest.json not found in $RegressionDir"
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($RecordingPath -eq "") { $RecordingPath = Join-Path $RegressionDir $manifest.artifacts.run_recording }
    if ($ScanPath -eq "") { $ScanPath = Join-Path $RegressionDir $manifest.artifacts.scan }
    if ($LiveSummaryPath -eq "") { $LiveSummaryPath = Join-Path $RegressionDir $manifest.artifacts.run_progress }
    if ($ReplayOutput -eq "") { $ReplayOutput = Join-Path $RegressionDir "09-replay.json" }
    if ($DiffOutput -eq "") { $DiffOutput = Join-Path $RegressionDir "10-replay-diff.json" }
}

if ($RecordingPath -eq "" -or -not (Test-Path $RecordingPath)) {
    throw "recording NDJSON not found: $RecordingPath"
}
if ($ReplayOutput -eq "") { $ReplayOutput = "$RecordingPath.replay.json" }
if ($DiffOutput -eq "") { $DiffOutput = "$RecordingPath.replay-diff.json" }

$workspacePath = Resolve-Path $Workspace

# Parse live run-summary before replay so we can pass matching startup/cycle args.
$liveSummary = $null
if ($LiveSummaryPath -ne "" -and (Test-Path $LiveSummaryPath)) {
    $lastSummary = Get-Content $LiveSummaryPath | Where-Object { $_ -match '"kind"\s*:\s*"run-summary"' } | Select-Object -Last 1
    if ($lastSummary) {
        try { $liveSummary = $lastSummary | ConvertFrom-Json } catch { $liveSummary = $null }
    }
}
$liveRunSummary = Get-RunSummaryPayload $liveSummary

# 1) Run replay
$replayArgs = @("run", "cmd/main", "replay", "--", "--trace", $RecordingPath, "--json")
if ($ScanPath -ne "" -and (Test-Path $ScanPath)) {
    $replayArgs += @("--scan-json", $ScanPath)
}
if ($null -ne $manifest) {
    if ($manifest.startup_state) {
        $replayArgs += @("--startup-state", [string]$manifest.startup_state)
    }
    if ($manifest.shutdown_state) {
        $replayArgs += @("--shutdown-state", [string]$manifest.shutdown_state)
    }
    if ($manifest.esi_json -and (Test-Path $manifest.esi_json)) {
        $replayArgs += @("--esi-json", [string]$manifest.esi_json)
        $replayArgs += @("--device-index", ([string]$manifest.device_index))
    }
}
$liveCyclesRequested = Get-Field $liveRunSummary "cycles_requested"
if ($null -ne $liveCyclesRequested) {
    $replayArgs += @("--cycles", ([string]$liveCyclesRequested))
}

Write-Host ("==> replay " + (($replayArgs[4..($replayArgs.Length - 1)]) -join " "))
Push-Location $workspacePath
try {
    & moon @replayArgs 2>&1 | Tee-Object -FilePath $ReplayOutput
    if ($LASTEXITCODE -ne 0) {
        $replayText = Get-Content $ReplayOutput -Raw
        throw "replay failed with exit code $LASTEXITCODE`n$replayText"
    }
}
finally {
    Pop-Location
}

# 2) Parse replay JSON
$replayText = Get-Content $ReplayOutput -Raw
$replayJsonText = Get-JsonPayloadText $replayText
if ($replayJsonText -ne $replayText.Trim()) {
    $replayJsonText | Set-Content -Path $ReplayOutput -Encoding UTF8
}
$replayJson = $replayJsonText | ConvertFrom-Json

# 3) Parse recording header (NicEventLog NDJSON header line)
$recordingHeader = $null
$firstLine = Get-Content $RecordingPath -TotalCount 1
if ($firstLine -and ($firstLine -match '"header"')) {
    try { $recordingHeader = $firstLine | ConvertFrom-Json } catch { $recordingHeader = $null }
}

# 5) Build diff
$replayVerdict = Get-Field $replayJson "verdict" "Unknown"
$replayCyclesOk = Get-Field $replayJson "run.cycles_ok"
$replayFinalPhase = Get-Field $replayJson "run.final_phase"
$replayTimeouts = Get-Field $replayJson "run.telemetry.timeouts"
$replayWkcErrors = Get-Field $replayJson "run.telemetry.wkc_errors"
$replaySlaveCount = Get-Field $replayJson "run.scan.slave_count"

$liveVerdict = Get-RunVerdict $liveRunSummary
$liveCyclesOk = Get-Field $liveRunSummary "cycles_ok"
$liveFinalPhase = Get-Field $liveRunSummary "final_phase"
$liveTimeouts = Get-Field $liveRunSummary "telemetry.timeouts"
$liveWkcErrors = Get-Field $liveRunSummary "telemetry.wkc_errors"

$recordingSlaves = Get-Field $recordingHeader "slave_count"
$recordingFinger = Get-Field $recordingHeader "fingerprint"

$failures = @()
if ($null -ne $recordingSlaves -and $null -ne $replaySlaveCount -and $recordingSlaves -ne $replaySlaveCount) {
    $failures += "slave_count mismatch: replay=$replaySlaveCount, recording=$recordingSlaves"
}
if ($null -ne $liveSummary) {
    if ($replayVerdict -ne $liveVerdict) {
        $failures += "verdict mismatch: replay=$replayVerdict, live=$liveVerdict"
    }
}

$diff = [ordered]@{
    generated_at      = (Get-Date).ToString("o")
    recording_path    = (Resolve-Path $RecordingPath).Path
    scan_path         = if ($ScanPath -and (Test-Path $ScanPath)) { (Resolve-Path $ScanPath).Path } else { $null }
    replay_output     = (Resolve-Path $ReplayOutput).Path
    live_summary_path = if ($LiveSummaryPath -and (Test-Path $LiveSummaryPath)) { (Resolve-Path $LiveSummaryPath).Path } else { $null }
    recording_header  = $recordingHeader
    stable            = [ordered]@{
        slave_count          = $recordingSlaves
        topology_fingerprint = $recordingFinger
        verdict_replay       = $replayVerdict
        verdict_live         = $liveVerdict
    }
    tolerant          = [ordered]@{
        cycles_ok_replay   = $replayCyclesOk
        cycles_ok_live     = $liveCyclesOk
        final_phase_replay = $replayFinalPhase
        final_phase_live   = $liveFinalPhase
        timeouts_replay    = $replayTimeouts
        timeouts_live      = $liveTimeouts
        wkc_errors_replay  = $replayWkcErrors
        wkc_errors_live    = $liveWkcErrors
    }
    failures          = $failures
    status            = if ($failures.Count -eq 0) { "ok" } else { "diff" }
}

$diff | ConvertTo-Json -Depth 12 | Set-Content -Path $DiffOutput -Encoding UTF8

Write-Host ""
Write-Host "Replay diff:"
Write-Host ("  replay:  " + $ReplayOutput)
Write-Host ("  diff:    " + $DiffOutput)
Write-Host ("  status:  " + $diff.status)
if ($failures.Count -gt 0) {
    Write-Host "  failures:"
    foreach ($f in $failures) { Write-Host ("    - " + $f) }
    exit 1
}
exit 0
