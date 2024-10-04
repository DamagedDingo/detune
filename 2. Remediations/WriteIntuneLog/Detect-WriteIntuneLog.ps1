<#
.SYNOPSIS
    Detection script to check the existence and version of the Write-IntuneLog.ps1 function file.

.DESCRIPTION
    This script checks if the Write-IntuneLog.ps1 file exists at the specified location and verifies if the version matches the expected version.

.PARAMETER None

.EXAMPLE
    .\Detect-WriteIntuneLog.ps1

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 04/10/2024
#>

$FunctionFilePath = 'C:\ProgramData\EUC\Functions\Write-IntuneLog.ps1'
$ExpectedVersion = 'Version: 1.3'
$Compliant = $true
$DetectionOutput = @()

# Check if the function file exists
if (Test-Path $FunctionFilePath) {
    $FileContent = Get-Content -Path $FunctionFilePath -Raw
    
    # Check if the version exists in the content
    if ($FileContent -match [regex]::Escape($ExpectedVersion)) {
        Write-Output "Write-IntuneLog function version is correct."
    } else {
        $DetectionOutput += "Write-IntuneLog function version is incorrect or missing."
        $Compliant = $false
    }
} else {
    $DetectionOutput += "Write-IntuneLog.ps1 does not exist."
    $Compliant = $false
}

# Join the detection output into a single string
$DetectionOutputString = $DetectionOutput -join "; "

# Output results
if ($Compliant) {
    Write-Output "System is compliant."
    exit 0
} else {
    Write-Output "$DetectionOutputString"
    exit 1
}
