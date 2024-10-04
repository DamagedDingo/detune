<#
.SYNOPSIS
    Script to set the system time zone to "AUS Eastern Standard Time".

.DESCRIPTION
    This script sets the system time zone to "AUS Eastern Standard Time". It includes basic error handling 
    and logs the result using the `Write-IntuneLog` function.

.PARAMETER None
    No parameters are required for this script.

.EXAMPLE
    .\Set-TimeZone.ps1
    This will set the system time zone to "AUS Eastern Standard Time".

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 05/10/2024
#>

$LogFileName = "Remediations.log"
$LogComponentName = "Set-TimeZone"  # Hardcoded component name for logging
$LogFunctionPath = 'C:\ProgramData\EUC\Functions\Write-IntuneLog.ps1'

# Try to import the Write-IntuneLog function, otherwise exit with an error
try {
    . $LogFunctionPath
} catch {
    Write-Error "Failed to import Write-IntuneLog from $LogFunctionPath." -ErrorAction Stop
}

$TimeZoneId = "AUS Eastern Standard Time"

try {
    # Set the time zone
    Set-TimeZone -Id $TimeZoneId
    $OutputMessage = "Time zone successfully set to $TimeZoneId."

    # Log the result
    Write-IntuneLog -Message $OutputMessage -Severity Info -LogFileName $LogFileName -Component $LogComponentName
    Write-Output $OutputMessage

} catch {
    $ErrorMessage = "Failed to set time zone to $TimeZoneId. Error: $($_.Exception.Message)"

    # Log the error
    Write-IntuneLog -Message $ErrorMessage -Severity Error -LogFileName $LogFileName -Component $LogComponentName
    Write-Error $ErrorMessage
}
