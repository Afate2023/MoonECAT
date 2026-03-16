param(
  [Parameter(Mandatory = $true)]
  [string]$Interface,

  [string]$Backend = "native-windows-npcap",
  [string]$Workspace = ".",
  [string]$OutputRoot = "artifacts/native-until-fault",
  [int]$TimeoutMs = 100,
  [int]$CyclePeriodUs = 1000,
  [int]$OutputPeriodMs = 1000,
  [int]$MaxConsecutiveTimeouts = 5,
  [string]$StartupState = "op",
  [string]$ShutdownState = "init",
  [string]$Station = ""
)

$ErrorActionPreference = "Stop"

function Invoke-MoonEcatStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string[]]$Args,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile
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

$commonNativeArgs = @("--backend", $Backend, "--if", $Interface, "--timeout-ms", $TimeoutMs)

Invoke-MoonEcatStep -Name "list-if" -Args (@("run", "cmd/main", "list-if", "--", "--backend", $Backend, "--json")) -OutputFile (Join-Path $logDir "01-list-if.json")
Invoke-MoonEcatStep -Name "scan" -Args (@("run", "cmd/main", "scan", "--") + $commonNativeArgs + @("--json")) -OutputFile (Join-Path $logDir "02-scan.json")
Invoke-MoonEcatStep -Name "validate" -Args (@("run", "cmd/main", "validate", "--") + $commonNativeArgs + @("--json")) -OutputFile (Join-Path $logDir "03-validate.json")

if ($Station -ne "") {
  Invoke-MoonEcatStep -Name "state-path-preop" -Args (
    @("run", "cmd/main", "state", "--") + $commonNativeArgs + @("--json", "--station", $Station, "--path", "--state", "preop")
  ) -OutputFile (Join-Path $logDir "04-state-preop.json")
}

$runOutput = Join-Path $logDir "05-run.ndjson"
Write-Host "==> run-until-fault"
Write-Host "moon run cmd/main run -- --backend $Backend --if $Interface --timeout-ms $TimeoutMs --json --progress-ndjson --until-fault --cycle-period-us $CyclePeriodUs --output-period-ms $OutputPeriodMs --max-consecutive-timeouts $MaxConsecutiveTimeouts --startup-state $StartupState --shutdown-state $ShutdownState"
Write-Host "Streaming NDJSON to $runOutput"
Write-Host "Use Ctrl+C to stop manually. Manual stop will keep progress lines but will not emit a final run-summary line."

& moon run cmd/main run -- --backend $Backend --if $Interface --timeout-ms $TimeoutMs --json --progress-ndjson --until-fault --cycle-period-us $CyclePeriodUs --output-period-ms $OutputPeriodMs --max-consecutive-timeouts $MaxConsecutiveTimeouts --startup-state $StartupState --shutdown-state $ShutdownState 2>&1 | Tee-Object -FilePath $runOutput

Write-Host ""
Write-Host "Validation artifacts:"
Write-Host ("  " + (Join-Path $logDir "01-list-if.json"))
Write-Host ("  " + (Join-Path $logDir "02-scan.json"))
Write-Host ("  " + (Join-Path $logDir "03-validate.json"))
if ($Station -ne "") {
  Write-Host ("  " + (Join-Path $logDir "04-state-preop.json"))
}
Write-Host ("  " + $runOutput)
Write-Host ""
Write-Host "Suggested checks:"
Write-Host "  1. scan/validate JSON should describe the expected bus shape before the long run starts."
Write-Host "  2. 05-run.ndjson should contain repeated kind=run-progress lines."
Write-Host "  3. If the loop exits on a runtime fault, 05-run.ndjson should end with kind=run-summary."