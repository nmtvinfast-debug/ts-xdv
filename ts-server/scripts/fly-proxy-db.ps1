param(
  [string]$DbApp = "ts-xdv-db",
  [int]$LocalPort = 15432,
  [int]$RemotePort = 5432
)

Write-Host "==> Ensuring DB machine is started..." -ForegroundColor Cyan
flyctl machine list -a $DbApp | Out-Null

try {
  $machineId = (flyctl machine list -a $DbApp --json | ConvertFrom-Json)[0].id
  if ($null -ne $machineId) {
    flyctl machine start $machineId -a $DbApp | Out-Null
  }
} catch {
  Write-Host "Could not auto-start DB machine. Start it in Fly dashboard or run: flyctl machine start <id> -a $DbApp" -ForegroundColor Yellow
}

Write-Host "==> Starting proxy localhost:$LocalPort -> $DbApp:$RemotePort" -ForegroundColor Cyan
Write-Host "Stop with Ctrl+C" -ForegroundColor DarkGray
flyctl proxy ${LocalPort}:${RemotePort} -a $DbApp
