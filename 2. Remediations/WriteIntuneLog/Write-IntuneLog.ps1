<#
.SYNOPSIS
    Platform script to create the Write-IntuneLog function and ensure it is available early in the Autopilot process.

.DESCRIPTION
    This script ensures the Write-IntuneLog.ps1 file is created in C:\ProgramData\EUC\Functions with the correct function content.
    It is designed to be run as part of the Autopilot Device Preparation profile, ensuring the logging function is available as soon as possible for other scripts.

.PARAMETER None

.EXAMPLE
    .\Create-WriteIntuneLog.ps1
    This will create the Write-IntuneLog.ps1 function file and ensure it is saved in the correct path.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 05/10/2024
#>

$FunctionDirectory = 'C:\ProgramData\EUC\Functions'
$FunctionFileName = 'Write-IntuneLog.ps1'
$FunctionFilePath = Join-Path -Path $FunctionDirectory -ChildPath $FunctionFileName

# Ensure the function directory exists, otherwise create it
if (-not (Test-Path -Path $FunctionDirectory)) {
    New-Item -Path $FunctionDirectory -ItemType Directory -Force | Out-Null
    Write-Output "Created directory: $FunctionDirectory"
}

# Read the entire script into a variable
$currentScript = Get-Content -Path $MyInvocation.MyCommand.Path -Raw

# Find the position of the **last** "#!ENDOFSCRIPT!#" marker and extract everything after it
$Marker = "#!ENDOFSCRIPT!#"
$FunctionStartIndex = $currentScript.LastIndexOf($Marker) + $Marker.Length
$FunctionContent = $currentScript.Substring($FunctionStartIndex).Trim()

# Create the Write-IntuneLog.ps1 file with the extracted content
Set-Content -Path $FunctionFilePath -Value $FunctionContent -Force
Write-Output "Write-IntuneLog.ps1 has been created or updated."

# The actual Write-IntuneLog function
#!ENDOFSCRIPT!#
Function Write-IntuneLog {
    <#
    .SYNOPSIS
        Writes log entries in CMTrace format to a specified log file with automatic archiving.

    .DESCRIPTION
        The Write-IntuneLog function is designed to log messages in a CMTrace-compatible format.
        The log file automatically archives itself when it exceeds 5MB, keeping a maximum of 5 archives.
        The component name can be passed as a parameter but will be dynamically determined from the calling script if not provided.

    .PARAMETER Message
        The log message to be recorded.

    .PARAMETER Severity
        The severity level of the message. Options are: Info, Warning, Error.

    .PARAMETER LogFileName
        The name of the log file. Default is "EUC_System_Log.log".

    .PARAMETER Component
        Optional component name for logging. If not provided, the calling script name will be used.

    .EXAMPLE
        Write-IntuneLog -Message "This is an informational log entry." -Severity Info

    .NOTES
        Version: 1.4
        Author: Gary Smith [EUC Administrator]
        Date: 05/10/2024
        Revision: Hardcoded component name for consistent logging with Intune.
                  Intune renames scripts so cannot use dynamic component names in remediations.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message, 
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Severity = 'Info',
        [string]$LogFileName = "EUC_System_Log.log",
        [string]$Component = $null  # Component name for logging, dynamically determined if not provided. Should be script or function name.
    )
    
    # Convert Severity string to a number for logging
    $SeverityNumber = switch ($Severity) {
        'Info' { 1 }
        'Warning' { 2 }
        'Error' { 3 }
    }
    
    # Set log path and max log size
    $LogPath = "C:\ProgramData\EUC\Logs\"
    $LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
    $MaxLogSizeBytes = 5MB
    $MaxArchivedLogs = 5
    
    # Ensure log directory exists
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Archive the log if it exceeds the maximum size
    if (Test-Path $LogFile) {
        $logFileSize = (Get-Item $LogFile).Length
        if ($logFileSize -gt $MaxLogSizeBytes) {
            $ArchivedLogName = "$($LogFileName)_archived_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
            Rename-Item -Path $LogFile -NewName (Join-Path -Path $LogPath -ChildPath $ArchivedLogName) | Out-Null
    
            # Remove oldest logs if more than 5 archived logs exist
            $archivedLogs = Get-ChildItem -Path $LogPath -Filter "$($LogFileName)_archived_*.log" |
            Sort-Object LastWriteTime
    
            if ($archivedLogs.Count -gt $MaxArchivedLogs) {
                $logsToRemove = $archivedLogs | Select-Object -First ($archivedLogs.Count - $MaxArchivedLogs)
                Remove-Item -Path $logsToRemove.FullName -Force | Out-Null
            }
    
            # Create a new empty log file after archiving
            New-Item -Path $LogFile -ItemType File | Out-Null
        }
    }

    # Dynamically calculate the component name if it's not provided
    if (-not $Component) {
        $Component = if ($MyInvocation.PSCommandPath) {
            [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.PSCommandPath)
        }
        else {
            "Console"
        }
    }
    
    # Construct the CMTrace-compatible log string for CMPowerLogViewer
    $LogTimePlusBias = (Get-Date).ToString('HH:mm:ss.fffzzz')
    $LogDate = (Get-Date).ToString('yyyy-MM-dd')
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    
    $CMTraceLogString = "<![LOG[$Message]LOG]!>" + `
        "<time=`"$LogTimePlusBias`" " + `
        "date=`"$LogDate`" " + `
        "component=`"$Component`" " + `
        "context=`"$CurrentUser`" " + `
        "type=`"$SeverityNumber`" " + `
        "thread=`"$PID`" " + `
        "file=`"$Component`">"
    
    # Append the CMTrace log string to the log file
    Add-Content -Path $LogFile -Value $CMTraceLogString
}
