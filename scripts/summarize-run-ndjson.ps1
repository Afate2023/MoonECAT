param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [string]$OutputPath = "",

  [switch]$PassThru
)

$ErrorActionPreference = "Stop"

function Convert-ToPlainValue {
  param(
    $Value
  )

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [string] -or $Value -is [int] -or $Value -is [long] -or
    $Value -is [double] -or $Value -is [decimal] -or $Value -is [bool]) {
    return $Value
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [pscustomobject])) {
    $items = @()
    foreach ($item in $Value) {
      $items += Convert-ToPlainValue -Value $item
    }
    return , $items
  }

  $result = [ordered]@{}
  foreach ($property in $Value.PSObject.Properties) {
    $result[$property.Name] = Convert-ToPlainValue -Value $property.Value
  }
  return $result
}

function Get-JsonRecord {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Line
  )

  $trimmed = $Line.Trim()
  if ($trimmed.Length -eq 0) {
    return $null
  }
  if (-not $trimmed.StartsWith("{")) {
    return $null
  }

  try {
    return $trimmed | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    return $null
  }
}

$resolvedInput = Resolve-Path $InputPath
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path (Split-Path -Parent $resolvedInput) "06-fault-summary.json"
}

$progressCount = 0
$parsedCount = 0
$lastProgress = $null
$lastSummary = $null
$summaryLine = $null
$lineNumber = 0

Get-Content -Path $resolvedInput | ForEach-Object {
  $lineNumber = $lineNumber + 1
  $record = Get-JsonRecord -Line $_
  if ($null -eq $record) {
    return
  }

  $parsedCount = $parsedCount + 1
  if ($record.kind -eq "run-progress") {
    $progressCount = $progressCount + 1
    $lastProgress = $record
    return
  }

  if ($record.kind -eq "run-summary") {
    $lastSummary = $record
    $summaryLine = $lineNumber
  }
}

$summary = if ($null -ne $lastSummary) { $lastSummary.summary } else { $null }
$fault = if ($null -ne $summary) { $summary.fault } else { $null }
$surface = if ($null -ne $summary) { $summary.surface } else { $null }
$telemetry = if ($null -ne $summary) {
  $summary.telemetry
}
elseif ($null -ne $lastProgress) {
  $lastProgress.telemetry
}
else {
  $null
}

$status = if ($null -eq $lastSummary) {
  "no-run-summary"
}
elseif ($null -eq $fault) {
  "completed-without-fault"
}
else {
  "fault-exit"
}

$message = switch ($status) {
  "fault-exit" { "run ended with a reported runtime fault" }
  "completed-without-fault" { "run emitted a terminal run-summary without a fault payload" }
  default { "run log has no terminal run-summary; manual stop or truncated capture is likely" }
}

$faultKind = if ($null -ne $fault) { $fault.kind } else { $null }
$finalPhase = if ($null -ne $summary) { $summary.final_phase } else { $null }
$cyclesCompleted = if ($null -ne $lastProgress) {
  $lastProgress.cycles_completed
}
elseif ($null -ne $summary) {
  $summary.cycles_ok
}
else {
  $null
}

$report = [ordered]@{
  source_file           = [string]$resolvedInput
  generated_at          = (Get-Date).ToString("o")
  status                = $status
  message               = $message
  parsed_record_count   = $parsedCount
  run_progress_count    = $progressCount
  summary_line          = $summaryLine
  fault_kind            = $faultKind
  final_phase           = $finalPhase
  last_cycles_completed = $cyclesCompleted
  telemetry             = Convert-ToPlainValue -Value $telemetry
  last_progress         = Convert-ToPlainValue -Value $lastProgress
  fault                 = Convert-ToPlainValue -Value $fault
  surface               = Convert-ToPlainValue -Value $surface
  run_summary           = Convert-ToPlainValue -Value $summary
}

$reportJson = $report | ConvertTo-Json -Depth 32
Set-Content -Path $OutputPath -Value $reportJson

Write-Host "Wrote fault summary to $OutputPath"
Write-Host "Status: $status"
if ($faultKind) {
  Write-Host "Fault kind: $faultKind"
}
if ($summaryLine) {
  Write-Host "Terminal run-summary line: $summaryLine"
}
if ($PassThru) {
  Write-Output $reportJson
}
