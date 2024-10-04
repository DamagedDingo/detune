<#
.SYNOPSIS
    Detection script to check if today's system uptime has already been logged.

.DESCRIPTION
    This script checks if the latest entry in 'uptime.log' is from the current date. If the latest entry is not from today, 
    it triggers the remediation by exiting with code 1.

.PARAMETER None
    No parameters are required for this script.

.EXAMPLE
    .\Detect-LogSystemUptime.ps1
    This will check if today's uptime has been logged.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 05/10/2024
#>

$LogFileName = "uptime.log"
$LogFilePath = "C:\ProgramData\EUC\Logs\$LogFileName"
$LogComponentName = "Detect-LogSystemUptime"  # Hardcoded component name for logging
$LogFunctionPath = 'C:\ProgramData\EUC\Functions\Write-IntuneLog.ps1'

# Try to import the Write-IntuneLog function, otherwise stop the script with an error
try {
    . $LogFunctionPath
} catch {
    Write-Error "Failed to import Write-IntuneLog from $LogFunctionPath." -ErrorAction Stop
}

$today = (Get-Date).ToString("yyyy-MM-dd")

# Check if the log file exists
if (Test-Path $LogFilePath) {
    $logEntries = Get-Content -Path $LogFilePath

    # Get the latest log entry (last line of the file)
    $latestLogEntry = $logEntries | Select-Object -Last 1

    # Check if the latest entry contains today's date
    if ($latestLogEntry -match $today) {
        $DetectionOutput = "Compliant: System uptime has already been logged today."
        Write-IntuneLog -Message $DetectionOutput -Severity Info -LogFileName "Remediations.log" -Component $LogComponentName
        Write-Output "$(($latestLogEntry -split " - ")[1])"
        exit 0  # Compliant, so exit with code 0
    } else {
        $DetectionOutput = "Non-Compliant: Latest uptime log entry is not from today. Triggering remediation."
        Write-IntuneLog -Message $DetectionOutput -Severity Warning -LogFileName "Remediations.log" -Component $LogComponentName
        Write-Output $DetectionOutput
        exit 1  # Non-compliant, so exit with code 1 to trigger remediation
    }
}
else {
    $DetectionOutput = "Non-Compliant: No log file found. Triggering remediation."
    Write-IntuneLog -Message $DetectionOutput -Severity Warning -LogFileName "Remediations.log" -Component $LogComponentName
    Write-Output $DetectionOutput
    exit 1  # Non-compliant, so exit with code 1 to trigger remediation
}
