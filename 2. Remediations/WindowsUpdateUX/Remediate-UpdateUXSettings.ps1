<#
.SYNOPSIS
    Remediation script to enforce specific Windows Update UX registry settings with logging.

.DESCRIPTION
    This script ensures that the following Windows Update UX registry settings are set to their expected values:

    1. **IsContinuousInnovationOptedIn**:
       - Controls whether the device is enrolled in Continuous Innovation updates.
       - Expected Value: 1 (Enabled).

    2. **RestartNotificationsAllowed2**:
       - Controls whether users are notified about restart requirements related to Windows updates.
       - Expected Value: 1 (Enabled).

    The script logs all remediation actions to a log file using the `Write-IntuneLog` function.

.PARAMETER None
    No parameters are required for this script.

.EXAMPLE
    .\Remediate-UpdateUXSettings.ps1
    This will run the remediation process and correct any incorrect registry values.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 04/10/2024
    This script enforces compliance for Windows Update UX settings by applying the correct registry values and logs the output.
#>

$LogFileName = "Remediations.log"
$LogFunctionPath = 'C:\ProgramData\EUC\Functions\Write-IntuneLog.ps1'

# Try to import the Write-IntuneLog function, otherwise stop the script with an error
try {
    . $LogFunctionPath
} catch {
    Write-Error "Failed to import Write-IntuneLog from $LogFunctionPath" -ErrorAction Stop
}

$Path = 'HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings'

try {
    # Define the registry values and their expected values
    $RegistryValues = @(
        @{ Name = 'IsContinuousInnovationOptedIn'; Value = 1 },
        @{ Name = 'RestartNotificationsAllowed2'; Value = 1 }
    )

    $RemediationOutput = @()

    # Loop through each registry value and check/update accordingly
    foreach ($item in $RegistryValues) {
        $Name = $item.Name
        $Value = $item.Value

        # Check if the registry key exists
        if (Test-Path $Path) {
            try {
                # Get the current value (this will throw an error if the value doesn't exist)
                $currentValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
            }
            catch {
                # Value does not exist, so we handle it by creating the correct value
                $RemediationOutput += "$Name does not exist, creating with value $Value"
                New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force
                continue
            }

            # If the value exists but is incorrect, update it
            if ($currentValue -ne $Value) {
                $RemediationOutput += "Updating $Name from $currentValue to $Value"
                Set-ItemProperty -Path $Path -Name $Name -Value $Value
            } else {
                $RemediationOutput += "$Name is already set to the correct value ($Value), no action needed."
            }
        } else {
            # Key doesn't exist, create it and the value
            $RemediationOutput += "Key does not exist, creating $Name with value $Value"
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force
        }
    }

    # Join the remediation output into a single string for reporting
    $RemediationOutputString = $RemediationOutput -join "; "

    # Log the remediation actions
    Write-IntuneLog -Message "$RemediationOutputString" -Severity Info -LogFileName $LogFileName

    # Output the remediation actions
    Write-Output $RemediationOutputString
} catch {
    # Handle any unexpected script errors
    Write-IntuneLog -Message "An error occurred during remediation: $($_.Exception.Message)" -Severity Error -LogFileName $LogFileName
    Write-Error "An error occurred during remediation: $($_.Exception.Message)" -ErrorAction Stop
}
