<#
.SYNOPSIS
This script is designed to manage and update Intune dynamic groups for Windows updates based on a three-ring deployment model. It ensures the devices in each ring meet the required percentage of total devices and updates the groups accordingly. This script is intended to be run monthly.

.DESCRIPTION
The script organizes devices into three rings for staggered deployment of Windows updates:

- **Ring 0 (Test)**: This group contains manually assigned devices for testing updates before the Pilot Testing stage. 
    - **Deferral Period**: 0 days
    - **Deadline**: 0 days
    - **Grace Period**: 1 days
    - This group is manually updated.

- **Ring 1 (Pilot Testing)**: This group contains 5% of the total devices. Devices in this group receive updates early for testing purposes, allowing the Central Office EUC team to identify any issues before broader deployment. 
    - **Deferral Period**: 0 days
    - **Deadline**: 2 days
    - **Grace Period**: 2 days
  
- **Ring 2 (UAT Testing)**: This group contains 15% of the total devices. Devices in this group receive updates after the Pilot Testing group, enabling broader testing before the updates are pushed to the entire environment.
    - **Deferral Period**: 7 days
    - **Deadline**: 7 days
    - **Grace Period**: 2 days
  
- **Ring 3 (Production)**: The remaining devices that are not part of Ring 1 or Ring 2. This ring represents the full production environment that will receive updates after Ring 1 and Ring 2 testing.
    - **Deferral Period**: 30 days
    - **Deadline**: 14 days
    - **Grace Period**: 2 days

Additionally, a **Combined Test Rings** group is created to combine Ring 1 and Ring 2. This group dynamically combines the devices from both rings without nesting the groups, allowing a single group to be used as a filter or exclusion in policies. It provides an easy way to exclude the devices in both Ring 1 and Ring 2 from receiving updates targeted at Ring 3.

The exclusion group, **Exclude Test Rings**, allows you to manually exclude specific devices from being added to Ring 1 or Ring 2.

The script includes checks to ensure groups are only created if they don't already exist. It also checks for and removes devices from groups if they no longer exist in Intune.

.LINK
For more information on Windows update settings and values used in this script, refer to:
https://github.com/SkipToTheEndpoint/OpenIntuneBaseline/wiki/win-settingsguidance#windows-updates

.VERSION
1.0 - 10/10/2024

.AUTHOR
Gary Smith [EUC Administrator]

#>

[CmdletBinding()]
param ()

#region Variables
$scriptName = "Set-UpdateRingGroups"
$LogFunctionPath = "$env:ProgramData\EUC\Functions\Write-IntuneLog.ps1"

# Import the Write-IntuneLog function and stop the script if it fails
. $LogFunctionPath -ErrorAction Stop

# Set the log file path and component name script-wide
$logFilePath = "$scriptName.log"
$PSDefaultParameterValues['Write-IntuneLog:LogFileName'] = $logFilePath
$PSDefaultParameterValues['Write-IntuneLog:Component'] = "$scriptName"

# Entra app registration details
$tenantID = ''
$clientID = ''
$certificateThumbprint = ''

# Update ring percentages
$ring1Percentage = 0.05
$ring2Percentage = 0.15

# Required modules for the script
$requiredModules = @('Microsoft.Graph.DeviceManagement', 'Microsoft.Graph.Groups')

# Group names and descriptions (prefixed with 'DEV -' for testing)
$ring0GroupName = "DEV - Intune - Deployment - D - Ring 0 - Central Office"
$ring0Description = "Manually assigned group for Ring 0 testing."

$ring1GroupName = "Win - OIB - WUfB - Ring 1 - Pilot"
$ring1Description = "This group contains 5% of devices for Pilot testing. Used for early deployment of updates in the Central Office."

$ring2GroupName = "Win - OIB - WUfB - Ring 2 - UAT"
$ring2Description = "This group contains 15% of devices for UAT testing. Used for testing updates after Ring 1 in the Central Office."

# Ring 3 is the remaining devices not in Ring 1 or Ring 2. Use the below group to exclude Ring 1 and Ring 2 devices from Ring 3.
$combinedGroupName = "Win - OIB - WUfB - Combined Test Rings - Production"
$combinedGroupDescription = "This group combines Ring 1 and Ring 2 devices. It is used to exclude these devices from Ring 3."

$exclusionGroup = "Win - OIB - WUfB - Exclude from Test Rings - Production"
$exclusionGroupDescription = "This group is used to exclude certain devices from being included in the Test Rings (Ring 1 & 2) if requested."
#endregion Variables

#region Main Script
Write-IntuneLog -Message "Starting Script: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Severity "Warning"

# Install required modules
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-IntuneLog -Message "Installing module: $($module)." -Severity "Info"
        Install-Module -Name $module -Scope CurrentUser -Force -ErrorAction Stop
    } else {
        Write-IntuneLog -Message "Module $($module) is already installed." -Severity "Info"
    }
    Write-IntuneLog -Message "Importing module: $($module)." -Severity "Info"
    Import-Module $module -ErrorAction Stop
}

# Connect to Microsoft Graph
Write-IntuneLog -Message "Connecting to Microsoft Graph..." -Severity "Info"
if (Get-MgContext) {
    Write-IntuneLog -Message "Already connected to Microsoft Graph." -Severity "Info"
} else {
    Connect-MgGraph -TenantId $tenantID -ClientId $clientID -CertificateThumbprint $certificateThumbprint -ErrorAction Stop
    Write-IntuneLog -Message "Connected to Microsoft Graph successfully." -Severity "Info"
}

#region Group Management
# Check and create groups if they don't exist
$groups = @(
    @{Name=$ring0GroupName; Description=$ring0Description; Assigned=$true},
    @{Name=$ring1GroupName; Description=$ring1Description},
    @{Name=$ring2GroupName; Description=$ring2Description},
    @{Name=$combinedGroupName; Description=$combinedGroupDescription},
    @{Name=$exclusionGroup; Description=$exclusionGroupDescription}
)

foreach ($group in $groups) {
    $existingGroup = Get-MgGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
    if (-not $existingGroup) {
        Write-IntuneLog -Message "Creating group: $($group.Name)." -Severity "Info"

        if ($group.Assigned) {
            # Manually assigned group (Ring 0)
            $groupSplat = @{
                DisplayName     = $group.Name
                SecurityEnabled = $true
                MailEnabled     = $false
                MailNickname    = $group.Name -replace ' ', ''
                Description     = $group.Description
                GroupTypes      = @()
            }
        } else {
            # Dynamic group for Ring 1, Ring 2, and Combined Test Rings
            $groupSplat = @{
                DisplayName                    = $group.Name
                SecurityEnabled                = $true
                MailEnabled                    = $false
                MailNickname                   = $group.Name -replace ' ', ''
                Description                    = $group.Description
                GroupTypes                     = @("DynamicMembership")
                MembershipRule                 = "(device.deviceId -eq '')"
                MembershipRuleProcessingState  = "Paused"
            }
        }

        New-MgGroup @groupSplat
    } else {
        Write-IntuneLog -Message "Group already exists: $($group.Name)." -Severity "Info"
    }
}
#endregion Group Management

#region Device Management
# Retrieve all devices from Intune
Write-IntuneLog -Message "Retrieving all Windows devices from Intune." -Severity "Info"
$allDevices = Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq 'Windows'"
Write-IntuneLog -Message "Total Windows devices retrieved: $($allDevices.Count)" -Severity "Info"

# Retrieve the exclusion group's device IDs
$excludedDevices = (Get-MgGroupMember -GroupId $((Get-MgGroup -Filter "displayName eq '$($exclusionGroup)'").Id) | 
                        Select-Object -ExpandProperty AdditionalProperties).deviceId

#endregion Device Management

#region Ring0 Group management
# Get the existing Ring 0 group
$existingRing0Group = Get-MgGroup -Filter "displayName eq '$($ring0GroupName)'" -ErrorAction SilentlyContinue

# Retrieve the Ring 0 group's device IDs (if any are assigned)
$existingRing0Devices = (Get-MgGroupMember -GroupId $((Get-MgGroup -Filter "displayName eq '$($ring0GroupName)'").Id) | 
                        Select-Object -ExpandProperty AdditionalProperties).deviceId

# Filter out excluded devices and Ring 0 devices from $remainingDevices based on the device ID
$remainingDevices = $allDevices | Where-Object { $_.AzureAdDeviceId -notin $excludedDevices }
if ($existingRing0Devices) {
    $remainingDevices = $remainingDevices | Where-Object { $_.AzureAdDeviceId -notin $existingRing0Devices }
}

#endregion Ring0 Group management

#region Ring1 Group management

# Retrieve the Ring 1 group's device IDs
$existingRing1Devices = (Get-MgGroupMember -GroupId $((Get-MgGroup -Filter "displayName eq '$($ring1GroupName)'").Id) | 
                        Select-Object -ExpandProperty AdditionalProperties).deviceId

if ($existingRing1Devices) {
    # Identify stale devices
    $staleRing1Devices = $existingRing1Devices | Where-Object { $_ -notin $allDevices.AzureAdDeviceId }
    
    if ($staleRing1Devices.Count -gt 0) {
        foreach ($staleDevice in $staleRing1Devices) {
            Write-IntuneLog -Message "Stale device detected: $($staleDevice) in Ring 1." -Severity "Warning"
        }
    } else {
        Write-IntuneLog -Message "No stale devices found in Ring 1." -Severity "Info"
    }
} else {
    Write-IntuneLog -Message "No existing devices found in Ring 1." -Severity "Info"
    $staleRing1Devices = @()
}

# Calculate Ring 1 device count based on all devices minus existing devices
$ring1DeviceCount = [math]::Ceiling(($allDevices.Count * $ring1Percentage) - ($existingRing1Devices.Count - $staleRing1Devices.Count))
Write-IntuneLog -Message "Ensuring $($ring1DeviceCount) additional devices in Ring 1." -Severity "Info"

# Check if we need to add any devices
if ($ring1DeviceCount -gt 0) {
    # Select devices for Ring 1, ensuring they aren't in the exclusion group
    $selectedRing1Devices = $remainingDevices | Sort-Object { Get-Random } | Select-Object -First $ring1DeviceCount
    
    # Wrap device IDs in quotes for the membership rule
    $ring1QuotedDeviceIds = $selectedRing1Devices.AzureAdDeviceId | ForEach-Object { "'$_'" }
    $ring1Query = "device.deviceId -in [$(Join-String -InputObject $ring1QuotedDeviceIds -Separator ',')]"

    # Ensure Ring 1 group exists and update if changes are required
    $existingRing1Group = Get-MgGroup -Filter "displayName eq '$($ring1GroupName)'" -ErrorAction SilentlyContinue
    if ($existingRing1Group -and $existingRing1Group.MembershipRule -ne $ring1Query) {
        try {
            Write-IntuneLog -Message "Updating membership rule for Ring 1 group: $($ring1GroupName)." -Severity "Warning"
            Write-IntuneLog -Message "Current Membership Rule: $ring1Query" -Severity "Info"
            Update-MgGroup -GroupId $($existingRing1Group.Id) -MembershipRule $ring1Query -MembershipRuleProcessingState "On"
            Write-IntuneLog -Message "Updated membership rule for Ring 1 group: $($ring1GroupName)" -Severity "Info"
        } catch {
            Write-IntuneLog -Message "Error updating Ring 1 group: $_" -Severity "Error"
            throw $_
        }
    } else {
        Write-IntuneLog -Message "No changes required for Ring 1 group." -Severity "Info"
    }
} else {
    Write-IntuneLog -Message "Ring 1 already has the correct number of devices. No changes needed." -Severity "Info"
}
#endregion Ring1 Group management

#region Ring2 Group management
# Retrieve the Ring 2 group's device IDs
$existingRing2Devices = (Get-MgGroupMember -GroupId $((Get-MgGroup -Filter "displayName eq '$($ring2GroupName)'").Id) | 
                        Select-Object -ExpandProperty AdditionalProperties).deviceId

# Calculate and update Ring 2, excluding Ring 1 and exclusion group
$remainingDevices = $remainingDevices | Where-Object { $_.AzureAdDeviceId -notin $selectedRing1Devices.AzureAdDeviceId }
if ($existingRing2Devices) {
    $staleRing2Devices = $existingRing2Devices | Where-Object { $_ -notin $allDevices.AzureAdDeviceId }
    foreach ($staleDevice in $staleRing2Devices) {
        Write-IntuneLog -Message "Stale device detected: $($staleDevice) in Ring 2." -Severity "Warning"
    }
}

# Calculate Ring 2 device count based on all devices minus existing devices
$ring2DeviceCount = [math]::Ceiling(($allDevices.Count * $ring2Percentage) - ($existingRing2Devices.Count - $staleRing2Devices.Count))
Write-IntuneLog -Message "Ensuring $($ring2DeviceCount) additional devices in Ring 2." -Severity "Info"

# Check if we need to add any devices
if ($ring2DeviceCount -gt 0) {
    # Select devices for Ring 2, ensuring they aren't in Ring 1 or the exclusion group
    $selectedRing2Devices = $remainingDevices | Sort-Object { Get-Random } | Select-Object -First $ring2DeviceCount

    # Wrap device IDs in quotes for the membership rule
    $ring2QuotedDeviceIds = $selectedRing2Devices.AzureAdDeviceId | ForEach-Object { "'$_'" }
    $ring2Query = "device.deviceId -in [$(Join-String -InputObject $ring2QuotedDeviceIds -Separator ',')]"

    # Ensure Ring 2 group exists and update if changes are required
    $existingRing2Group = Get-MgGroup -Filter "displayName eq '$($ring2GroupName)'" -ErrorAction SilentlyContinue
    if ($existingRing2Group -and $existingRing2Group.MembershipRule -ne $ring2Query) {
        try {
            Write-IntuneLog -Message "Updating membership rule for Ring 2 group: $($ring2GroupName)." -Severity "Warning"
            Write-IntuneLog -Message "Current Membership Rule: $ring2Query" -Severity "Info"
            Update-MgGroup -GroupId $($existingRing2Group.Id) -MembershipRule $ring2Query -MembershipRuleProcessingState "On"
            Write-IntuneLog -Message "Updated membership rule for Ring 2 group: $($ring2GroupName)" -Severity "Info"
        } catch {
            Write-IntuneLog -Message "Error updating Ring 2 group: $_" -Severity "Error"
            throw $_
        }
    } else {
        Write-IntuneLog -Message "No changes required for Ring 2 group." -Severity "Info"
    }
} else {
    Write-IntuneLog -Message "Ring 2 already has the correct number of devices. No changes needed." -Severity "Info"
}
#endregion Ring2 Group management

#region Combined Test Rings Group management
# Update combined group for Ring 0, Ring 1, and Ring 2
$existingCombinedGroup = Get-MgGroup -Filter "displayName eq '$($combinedGroupName)'"
$combinedQuery = "device.memberOf -any (group.objectId -in ['$($existingRing0Group.Id)','$($existingRing1Group.Id)','$($existingRing2Group.Id)'])"

If ($existingCombinedGroup.MembershipRule -ne $combinedQuery -or $existingCombinedGroup.MembershipRuleProcessingState -ne "On") {
    Write-IntuneLog -Message "Updating membership rule for Combined Test Rings group." -Severity "Warning"
    Write-IntuneLog -Message "Current Membership Rule: $($existingGroup.MembershipRule)" -Severity "Info"
    Update-MgGroup -GroupId $($existingCombinedGroup.Id) -MembershipRule $combinedQuery -MembershipRuleProcessingState "On"
    Write-IntuneLog -Message "New Membership Rule: $($combinedQuery)" -Severity "Info"
    Write-IntuneLog -Message "Updated membership rule for Combined Test Rings group." -Severity "Info"
} else {
    Write-IntuneLog -Message "Combined Test Rings group is already up to date." -Severity "Info"
}
#endregion Combined Test Rings Group management

Write-IntuneLog -Message "Device assignment to update rings completed." -Severity "Info"

#endregion Main Script
