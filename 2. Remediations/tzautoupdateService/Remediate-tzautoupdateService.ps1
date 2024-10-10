<#
.SYNOPSIS
    Remediation script to set the 'tzautoupdate' service Start Type to Manual and ensure it is running.

.DESCRIPTION
    This script ensures that the 'tzautoupdate' service is set to Manual (Start Type 3) and starts the service if it is not running.
    Logs actions and results.

    More information can be found at:
    https://www.mrgtech.net/setting-timezone-automatically/

.PARAMETER None
    No parameters are required for this script.

.EXAMPLE
    .\Remediate-tzautoupdateService.ps1
    This will set the 'tzautoupdate' service to Manual and ensure it is running.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 05/10/2024
#>

$LogFileName = "Remediations.log"
$LogComponentName = "Remediate-tzautoupdateService"  # Hardcoded component name for logging
$LogFunctionPath = 'C:\ProgramData\EUC\Functions\Write-IntuneLog.ps1'

# Try to import the Write-IntuneLog function, otherwise stop the script with an error
try {
    . $LogFunctionPath
} catch {
    Write-Error "Failed to import Write-IntuneLog from $LogFunctionPath." -ErrorAction Stop
}

try {
    # Set the service Start Type to Manual
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name Start -Value 3 -ErrorAction Stop
    $RemediationOutput = "Action: Set 'tzautoupdate' service Start Type to Manual (3)."

    $tzautoupdate = Get-Service -Name "tzautoupdate" -ErrorAction SilentlyContinue

    # Ensure the service is running
    if ($tzautoupdate.Status -ne 'Running') {
        Start-Service -Name "tzautoupdate" -ErrorAction Stop
        $RemediationOutput += " Action: Started 'tzautoupdate' service."
    } else {
        $RemediationOutput += " Info: 'tzautoupdate' service is already running."
    }

    # Log the result and output the message
    Write-IntuneLog -Message $RemediationOutput -Severity Info -LogFileName $LogFileName -Component $LogComponentName
    Write-Output $RemediationOutput
    exit 0
}
catch {
    $ErrorMessage = "Error: Remediation failed. Error: $($_.Exception.Message)"
    Write-IntuneLog -Message $ErrorMessage -Severity Error -LogFileName $LogFileName -Component $LogComponentName
    Write-Error $ErrorMessage
    exit 1
}
