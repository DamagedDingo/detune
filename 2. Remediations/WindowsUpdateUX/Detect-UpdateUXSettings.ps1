<#
.SYNOPSIS
    Detection script to verify the Windows Update UX registry settings with logging.

.DESCRIPTION
    This script checks the Windows Update UX registry settings for the following values:
    
    1. **IsContinuousInnovationOptedIn**:
       - Expected Value: 1 (Enabled).

    2. **RestartNotificationsAllowed2**:
       - Expected Value: 1 (Enabled).
    
    The script logs the detection and compliance status to a log file using the `Write-IntuneLog` function.

.PARAMETER None
    No parameters are required for this script.

.EXAMPLE
    .\Detect-UpdateUXSettings.ps1
    This will run the detection check and log the compliance status.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 05/10/2024
#>

$LogFileName = "Remediations.log"
$LogComponentName = "Detect-UpdateUXSettings"  # Hardcoded component name for logging
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

    $Compliant = $true
    $DetectionOutput = @()

    # Loop through each registry value and check if it's compliant
    foreach ($item in $RegistryValues) {
        $Name = $item.Name
        $Value = $item.Value

        try {
            # Get the current value (this will throw an error if the value doesn't exist)
            $currentValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name

            # If the value exists but is incorrect, update it
            if ($currentValue -ne $Value) {
                $DetectionOutput += "$Name exists but is set to $currentValue, expected $Value."
                $Compliant = $false
            } else {
                $DetectionOutput += "$Name exists and is correctly set to $Value, no action needed."
            }
        }
        catch {
            # Handle the case where the key doesn't exist at all
            $DetectionOutput += "$Name does not exist."
            $Compliant = $false
        }

    }

    # Join the detection output into a single string for better reporting
    $DetectionOutputString = $DetectionOutput -join "; "

    # Log the detection results
    Write-IntuneLog -Message "$DetectionOutputString" -Severity Info -LogFileName $LogFileName -Component $LogComponentName

    # Exit with non-zero code if non-compliant, otherwise exit with 0
    if ($Compliant) {
        Write-IntuneLog -Message "System is compliant." -Severity Info -LogFileName $LogFileName -Component $LogComponentName
        exit 0
    } else {
        Write-IntuneLog -Message "System is not compliant." -Severity Warning -LogFileName $LogFileName -Component $LogComponentName
        Write-Output "$DetectionOutputString"
        exit 1
    }
} catch {
    # Handle any unexpected script errors
    Write-IntuneLog -Message "An error occurred during detection: $($_.Exception.Message)" -Severity Error -LogFileName $LogFileName -Component $LogComponentName
    Write-Error "An error occurred during detection: $($_.Exception.Message)" -ErrorAction Stop
}
