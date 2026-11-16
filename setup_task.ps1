$TaskName = "StravaFitnessSync"
$ScriptPath = "c:\Users\My PC\strava-fitness-analytics\run_sync.bat"
$WorkingDirectory = "c:\Users\My PC\strava-fitness-analytics"

# Define Action
$Action = New-ScheduledTaskAction -Execute $ScriptPath -WorkingDirectory $WorkingDirectory

# Define Trigger (Runs every 8 hours: 12:00 AM, 8:00 AM, 4:00 PM)
$Trigger = New-ScheduledTaskTrigger -Once -At 12:00AM -RepetitionInterval (New-TimeSpan -Hours 8)

# Define Settings (Allow execution on demand, run if missed, don't stop if on battery)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Register or update task (kept disabled by default since Cloud Scheduler is primary)
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Sync Strava activities and Google Fit steps to BigQuery (Local Fallback)"
Disable-ScheduledTask -TaskName $TaskName

Write-Host "✅ Scheduled Task '$TaskName' registered successfully in standby/disabled mode as a local backup (Google Cloud Scheduler handles primary orchestration)."
