<#
.SYNOPSIS
    Detection script to check if the 'tzautoupdate' service is set to Manual and is running.

.DESCRIPTION
    This script checks if the 'tzautoupdate' service is configured to start with a manual start type (Start Type 3) 
    and is currently running. If both conditions are met, the system is considered compliant. Otherwise, it is non-compliant.

    More information can be found at:
    https://www.mrgtech.net/setting-timezone-automatically/

.PARAMETER None
    No parameters are required for this script.

.EXAMPLE
    .\Detect-tzautoupdateService.ps1
    This will check the 'tzautoupdate' service start type and status.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 05/10/2024
#>

$LogFileName = "Remediations.log"
$LogComponentName = "Detect-tzautoupdateService"  # Hardcoded component name for logging
$LogFunctionPath = 'C:\ProgramData\EUC\Functions\Write-IntuneLog.ps1'

# Try to import the Write-IntuneLog function, otherwise stop the script with an error
try {
    . $LogFunctionPath
} catch {
    Write-Error "Failed to import Write-IntuneLog from $LogFunctionPath." -ErrorAction Stop
}

try {
    $tzautoupdate = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name Start -ErrorAction Stop
    $tzautoupdateStartType = $tzautoupdate.Start
    $tzautoupdateStatus = Get-Service -Name "tzautoupdate" -ErrorAction SilentlyContinue

    if ($tzautoupdateStartType -eq 3 -and $tzautoupdateStatus.Status -eq 'Running') {
        $OutputMessage = "Compliant: 'tzautoupdate' service is set to Manual (Start Type 3) and is running."
        Write-IntuneLog -Message $OutputMessage -Severity Info -LogFileName $LogFileName -Component $LogComponentName
        Write-Output $OutputMessage
        exit 0
    }
    else {
        $OutputMessage = "Non-Compliant: 'tzautoupdate' service is not set to Manual or is not running."
        Write-IntuneLog -Message $OutputMessage -Severity Warning -LogFileName $LogFileName -Component $LogComponentName
        Write-Output $OutputMessage
        exit 1
    }
}
catch {
    $ErrorMessage = "Error: Unable to retrieve 'tzautoupdate' service information. Error: $($_.Exception.Message)"
    Write-IntuneLog -Message $ErrorMessage -Severity Error -LogFileName $LogFileName -Component $LogComponentName
    Write-Error $ErrorMessage
    exit 1
}
