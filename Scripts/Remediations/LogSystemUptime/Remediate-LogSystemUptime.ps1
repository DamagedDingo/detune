<#
.SYNOPSIS
    Remediation script to get the system uptime and log it.

.DESCRIPTION
    This script calculates the system uptime (in days) and writes the result to 'uptime.log' with the current date.

.PARAMETER None
    No parameters are required for this script.

.EXAMPLE
    .\Remediate-LogSystemUptime.ps1
    This will get the system uptime and log the result in 'uptime.log'.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 05/10/2024
#>

$LogFileName = "uptime.log"
$LogFilePath = "C:\ProgramData\EUC\Logs\$LogFileName"
$LogComponentName = "Remediate-LogSystemUptime"  # Hardcoded component name for logging
$LogFunctionPath = 'C:\ProgramData\EUC\Functions\Write-IntuneLog.ps1'

# Try to import the Write-IntuneLog function, otherwise stop the script with an error
try {
    . $LogFunctionPath
} catch {
    Write-Error "Failed to import Write-IntuneLog from $LogFunctionPath." -ErrorAction Stop
}

# Calculate system uptime
$uptimeSpan = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptimeInDays = (Get-Date) - $uptimeSpan
$uptimeDays = [math]::Round($uptimeInDays.TotalDays, 2)

$logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Uptime: $uptimeDays days"

# Ensure log directory exists
if (-not (Test-Path -Path (Split-Path $LogFilePath))) {
    New-Item -Path (Split-Path $LogFilePath) -ItemType Directory -Force | Out-Null
}

# Write the uptime to the log
Add-Content -Path $LogFilePath -Value $logEntry
$RemediationOutput = "Uptime: $uptimeDays days."

# Log the result in Write-IntuneLog
Write-IntuneLog -Message $RemediationOutput -Severity Info -LogFileName "Remediations.log" -Component $LogComponentName

Write-Output "$RemediationOutput"
exit 0
