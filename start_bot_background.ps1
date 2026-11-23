# ==============================================================================
# Script: start_bot_background.ps1
# Description: Starts the Strava AI Coach Telegram Bot in background and ensures
#              no duplicate processes are running.
# ==============================================================================

$ProjectDir = "c:\Users\My PC\strava-fitness-analytics"
$PythonExe  = "C:\Users\My PC\AppData\Local\Python\pythoncore-3.14-64\python.exe"
$Script     = "$ProjectDir\telegram_bot.py"
$OutLog     = "$ProjectDir\telegram_bot_out.log"
$ErrLog     = "$ProjectDir\telegram_bot_err.log"

# Stop existing bot processes to avoid conflict
$existing = Get-CimInstance Win32_Process -Filter "CommandLine like '%telegram_bot.py%'"
if ($existing) {
    Write-Host "Stopping existing telegram_bot process(es)..."
    $existing | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Write-Host "Launching Strava AI Coach Telegram Bot in background..."
Start-Process -FilePath $PythonExe `
              -ArgumentList "`"$Script`"" `
              -WorkingDirectory $ProjectDir `
              -RedirectStandardOutput $OutLog `
              -RedirectStandardError $ErrLog `
              -WindowStyle Hidden

Start-Sleep -Seconds 2
$running = Get-CimInstance Win32_Process -Filter "CommandLine like '%telegram_bot.py%'"
if ($running) {
    Write-Host "✅ Telegram Bot successfully started in background! PID: $($running.ProcessId)"
    Write-Host "Output log: $OutLog"
    Write-Host "Error log:  $ErrLog"
} else {
    Write-Host "❌ Failed to start bot. Check $ErrLog for details."
}
