<#
.SYNOPSIS
    Manages uninstall data stored in Azure Table Storage by comparing registry uninstall information and performing batch operations.

.DESCRIPTION
    Retrieves 32-bit and 64-bit uninstall data from a Windows machine’s registry, using the device’s serial number as a PartitionKey. This script compares the collected data against existing entries in Azure Table Storage and processes:
    - Insertion of new data (POST)
    - Update of existing entries (MERGE)
    - Deletion of obsolete entries (DELETE)
    Batch operations minimize the number of transactions.

.PARAMETER azureStorageAccount
    Name of the Azure Storage account.

.PARAMETER azureTableName
    Name of the Azure Table to store the data.

.PARAMETER azureSasToken
    The SAS token for authenticating with the Azure Table. Starts with "?sv=" as that is whats copied out of the Azure Portal.

.PARAMETER azureTableUri
    URI for the Azure Table Storage with the specified table and token.

.PARAMETER azureBatchUri
    URI for submitting batch operations.

.NOTES
    Author: Gary Smith [EUC Administrator]
    Date: 20/10/2024
    Version: 1.1.6
    Change Log:
        - Updated variable names for clarity.
        - Added pagination handling for Get-TableData.
        - Improved verbose output for better tracking.
        - Limited the MERGE requests to applications where the version number has changed. 
#>

param (
    [string]$azureStorageAccount = "intuneremotestorage",
    [string]$azureTableName = "DemoTable1",
    [string]$azureSasToken = "?sv=2022-11-02&ss=t&srt=o&sp=rwdlacu&se=2025-10-20T15:53:00Z&st=2024-10-20T07:53:00Z&spr=https&sig=m04%2FOwBx9CS4Kqs0Nr4m639Dg5nRMMlCuApU2RmUk9U%3D",
    [string]$azureTableUri = "https://$azureStorageAccount.table.core.windows.net/$($azureTableName)$($azureSasToken)",
    [string]$azureBatchUri = "https://$azureStorageAccount.table.core.windows.net/`$batch$($azureSasToken)"
)

# Set verbose output
$VerbosePreference = "Continue"

# Get device serial number to use as PartitionKey (Groups data by device)
$partitionKey = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber

function Get-UninstallData {
    <#
.SYNOPSIS
    Retrieves uninstall information from the registry for both 32-bit and 64-bit applications.

.DESCRIPTION
    Collects data from specified uninstall registry paths and formats it into a PSCustomObject array. This data is later compared to Azure Table entries.

.PARAMETER uninstallPath
    The registry path to search for uninstall data.

.PARAMETER isWow6432Node
    A boolean indicating whether the 32-bit (WOW6432Node) registry path is being queried.

.EXAMPLE
    Get-UninstallData -uninstallPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -isWow6432Node $false

    Collects uninstall data from the 64-bit registry path.
#>
    param (
        [string]$uninstallPath,
        [bool]$isWow6432Node
    )

    Write-Verbose "[Get-UninstallData] Collecting uninstall data from registry path: $uninstallPath"
    $uninstallDataCollection = @()

    Get-ChildItem -Path $uninstallPath | ForEach-Object {
        $key = Get-ItemProperty -Path $_.PSPath
        if ($key.UninstallString) {
            $uninstallDataCollection += [pscustomobject]@{
                PartitionKey         = $partitionKey
                RowKey               = $_.PSChildName
                DisplayName          = $key.DisplayName -replace $null, ""
                DisplayVersion       = $key.DisplayVersion -replace $null, ""
                Publisher            = $key.Publisher -replace $null, ""
                UninstallString      = $key.UninstallString -replace $null, ""
                QuietUninstallString = $key.QuietUninstallString -replace $null, ""
                InstallSource        = $key.InstallSource -replace $null, ""
                InstallLocation      = $key.InstallLocation -replace $null, ""
                WOW6432Node          = $isWow6432Node
            }
        }
    }
    Write-Verbose "[Get-UninstallData] Collected $($uninstallDataCollection.Count) uninstall entries from registry path: $uninstallPath"
    return $uninstallDataCollection
}

function New-GetHeaders {
    Write-Verbose "[New-GetHeaders] Generating headers for Azure Table request"
    $gmtTime = (Get-Date).ToUniversalTime().toString('R')
    $headers = @{
        'x-ms-date' = $gmtTime;
        Accept      = 'application/json;odata=nometadata'
    }
    Write-Verbose "[New-GetHeaders] Headers successfully generated"
    return $headers
}

function New-BatchHeaders {
    param (
        [string]$batchBoundary
    )
    Write-Verbose "[New-BatchHeaders] Creating headers for batch operation"
    $batchHeaders = @{
        "x-ms-date"             = (Get-Date).ToUniversalTime().ToString("R")
        "x-ms-version"          = "2013-08-15"
        "Content-Type"          = "multipart/mixed; boundary=$batchBoundary"
        "DataServiceVersion"    = "3.0"
        "Accept-Charset"        = "UTF-8"
        "MaxDataServiceVersion" = "3.0;NetFx"
        "Connection"            = "Keep-Alive"
    }
    Write-Verbose "[New-BatchHeaders] Headers successfully created for batch boundary $($batchBoundary)"
    return $batchHeaders
}

function Split-ApplicationsIntoBatches {
    param (
        [Object[]]$applications,
        [int]$maxEntitiesPerBatch = 100,
        [int]$maxBatchSize = 4MB
    )
    Write-Verbose "[Split-ApplicationsIntoBatches] Splitting $($applications.Count) applications into batches"

    $batches = @()
    $batchEntities = @()
    $batchSize = 0

    foreach ($application in $applications) {
        $jsonData = $application | ConvertTo-Json -Depth 10
        $entitySize = [System.Text.Encoding]::UTF8.GetByteCount($jsonData)

        if ($batchEntities.Count -ge $maxEntitiesPerBatch -or ($batchSize + $entitySize) -gt $maxBatchSize) {
            $batches += [PSCustomObject]@{Entities = $batchEntities; Size = $batchSize }
            $batchEntities = @()
            $batchSize = 0
        }

        $batchEntities += $application
        $batchSize += $entitySize
    }

    if ($batchEntities.Count -gt 0) {
        $batches += [PSCustomObject]@{Entities = $batchEntities; Size = $batchSize }
    }
    Write-Verbose "[Split-ApplicationsIntoBatches] Created $($batches.Count) batches for processing"
    return $batches
}

function Get-TableData {
    param (
        [string]$azureTableName,
        [string]$azureStorageAccount,
        [string]$azureSasToken,
        [string]$partitionKey,
        [hashtable]$headers
    )

    Write-Verbose "[Get-TableData] Querying Azure Table Storage"
    $azureTableUri = "https://$azureStorageAccount.table.core.windows.net/${azureTableName}${azureSasToken}"
    $allAzureEntries = @()
    $nextPartitionKey = $null
    $nextRowKey = $null

    do {
        $queryUri = $azureTableUri
        if ($nextPartitionKey -and $nextRowKey) {
            $queryUri = "$azureTableUri&NextPartitionKey=$nextPartitionKey&NextRowKey=$nextRowKey"
        }

        try {
            if ($partitionKey) {
                $filter = "PartitionKey eq '$partitionKey'"
                $response = Invoke-WebRequest -Uri "$queryUri&\`$filter=$filter" -Headers $headers -Method Get
            } else {
                $response = Invoke-WebRequest -Uri $queryUri -Headers $headers -Method Get
            }

            $currentData = ($response.Content | ConvertFrom-Json).value
            $allAzureEntries += $currentData

            $nextPartitionKey = $response.Headers['x-ms-continuation-nextpartitionkey']
            $nextRowKey = $response.Headers['x-ms-continuation-nextrowkey']

            Write-Verbose "[Get-TableData] Retrieved $($currentData.Count) entries from current page"
            if ($nextPartitionKey -and $nextRowKey) {
                Write-Verbose "[Get-TableData] Continuing to next page with NextPartitionKey: $nextPartitionKey, NextRowKey: $nextRowKey"
            }

        } catch {
            Write-Error "[Get-TableData] Error getting data from the table: $_"
        }

    } while ($nextPartitionKey -and $nextRowKey)

    Write-Verbose "[Get-TableData] Retrieved all pages of data"
    return $allAzureEntries
}

function Format-ChangeSet {
    param (
        [string]$method,
        [string]$changesetBoundary,
        [string]$azureStorageAccount,
        [string]$azureTableName,
        [array]$application
    )

    Write-Verbose "[Format-ChangeSet] Formatting changeset for method $method and application $($application.RowKey)"
    
    $rowKey = $application.RowKey
    $partitionKey = $application.PartitionKey
    $jsonData = $application | Select -ExcludeProperty Method | ConvertTo-Json -Depth 10 -Compress
    
    switch ($method) {
        POST { 
            $changeSetText = "--$changesetBoundary`r`n"
            $changeSetText += "Content-Type: application/http`r`n"
            $changeSetText += "Content-Transfer-Encoding: binary`r`n"
            $changeSetText += "`r`n"
            $changeSetText += "$method https://$azureStorageAccount.table.core.windows.net/$azureTableName HTTP/1.1`r`n"
            $changeSetText += "Content-Type: application/json`r`n"
            $changeSetText += "Accept: application/json;odata=minimalmetadata`r`n"
            $changeSetText += "Prefer: return-no-content`r`n"
            $changeSetText += "DataServiceVersion: 3.0`r`n"
            $changeSetText += "`r`n"
            $changeSetText += "$jsonData`r`n"
            $changeSetText += "`r`n"
        }
        MERGE {
            $changeSetText = "--$changesetBoundary`r`n"
            $changeSetText += "Content-Type: application/http`r`n"
            $changeSetText += "Content-Transfer-Encoding: binary`r`n"
            $changeSetText += "`r`n"
            $changeSetText += "$method https://$azureStorageAccount.table.core.windows.net/$azureTableName(PartitionKey='$partitionKey', RowKey='$rowKey') HTTP/1.1`r`n"
            $changeSetText += "Content-Type: application/json`r`n"
            $changeSetText += "Accept: application/json;odata=minimalmetadata`r`n"
            $changeSetText += "Prefer: return-no-content`r`n"
            $changeSetText += "DataServiceVersion: 3.0`r`n"
            $changeSetText += "`r`n"
            $changeSetText += "$jsonData`r`n"
            $changeSetText += "`r`n"
        }
        DELETE {
            $changeSetText = "--$changesetBoundary`r`n"
            $changeSetText += "Content-Type: application/http`r`n"
            $changeSetText += "Content-Transfer-Encoding: binary`r`n"
            $changeSetText += "`r`n"
            $changeSetText += "$method https://$azureStorageAccount.table.core.windows.net/$azureTableName(PartitionKey='$partitionKey', RowKey='$rowKey') HTTP/1.1`r`n"
            $changeSetText += "Content-Type: application/json`r`n"
            $changeSetText += "Accept: application/json;odata=minimalmetadata`r`n"
            $changeSetText += "Prefer: return-no-content`r`n"
            $changeSetText += "DataServiceVersion: 3.0`r`n"
            $changeSetText += "if-match: *`r`n"
            $changeSetText += "`r`n"
        }
    }

    Write-Verbose "[Format-ChangeSet] Changeset formatted successfully"
    return [string]$changeSetText
}

function Format-BatchTransaction {
    param (
        [array[]]$changeSets,
        [string]$batchBoundary,
        [string]$changesetBoundary
    )

    $entitiesProcessed = 0
    $batchBody = "--$batchBoundary`r`n"
    $batchBody += "Content-Type: multipart/mixed; boundary=$changesetBoundary`r`n`r`n"
    $batchBody += "`r`n"

    foreach ($changeSet in $changeSets) {
        $entitiesProcessed++
        $batchBody += "$changeSet"
    }

    $batchBody += "--$changesetBoundary--`r`n"
    $batchBody += "--$batchBoundary--`r`n"

    Write-Verbose "[Format-BatchTransaction] Sending batch request with $entitiesProcessed entities"
    return $batchBody
}

function Send-BatchTransaction {
    param (
        [string]$batchBody,
        [string]$azureBatchUri,
        [hashtable]$headers
    )

    try {
        Write-Verbose "[Send-BatchTransaction] Sending batch transaction to Azure Table Storage"
        $response = Invoke-WebRequest -Uri $azureBatchUri -Method Post -Headers $headers -Body $batchBody
        Write-Verbose "[Send-BatchTransaction] Batch transaction sent successfully, status code: $($response.StatusCode)"
        return $response
    } catch {
        Write-Error "[Send-BatchTransaction] Error sending batch transaction: $_"
    }
}

# Main script
Write-Verbose "[Main] Starting script execution"

$registryPaths = @(
    @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; IsWow6432Node = $false },
    @{Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"; IsWow6432Node = $true }
)

Write-Verbose "[Main] Starting to collect uninstall data from registry"
$uninstallKeysCollection = foreach ($registryPath in $registryPaths) {
    Get-UninstallData -uninstallPath $registryPath.Path -isWow6432Node $registryPath.IsWow6432Node
}
$uninstallKeysCollection = $uninstallKeysCollection
Write-Verbose "[Main] Uninstall data collection completed with $($uninstallKeysCollection.Count) entries"

Write-Verbose "[Main] Retrieving existing entries from Azure table"
$headers = New-GetHeaders
$azureEntriesByPartition = Get-TableData -azureTableName $azureTableName -azureStorageAccount $azureStorageAccount -azureSasToken $azureSasToken -partitionKey $partitionKey -headers $headers

if (-not $azureEntriesByPartition) {
    Write-Verbose "[Main] No existing entries found in the table for PartitionKey: $partitionKey"
    $azureEntriesByPartition = @() # Stops errors on compare-object
}

Write-Verbose "[Main] Comparing uninstall data with existing entries"
$allEntriesToProcess = @()

foreach ($uninstall in $uninstallKeysCollection) {
    if ($azureEntriesByPartition | Where-Object { $_.RowKey -eq $uninstall.RowKey -and $_.Version -ne $uninstall.Version }) {
        $allEntriesToProcess += $uninstall | Add-Member -MemberType NoteProperty -Name Method -Value "MERGE" -Force -PassThru
    } elseif (-not ($azureEntriesByPartition | Where-Object { $_.RowKey -eq $uninstall.RowKey })) {
        $allEntriesToProcess += $uninstall | Add-Member -MemberType NoteProperty -Name Method -Value "POST" -Force -PassThru
    }
}

foreach ($entry in $azureEntriesByPartition) {
    if (-not ($uninstallKeysCollection | Where-Object { $_.RowKey -eq $entry.RowKey })) {
        $allEntriesToProcess += $entry | Add-Member -MemberType NoteProperty -Name Method -Value "DELETE" -Force -PassThru
    }
}

Write-Verbose "[Main] Data comparison completed, found $($allEntriesToProcess.Count) entries to process"

$batchCollection = Split-ApplicationsIntoBatches -applications $allEntriesToProcess
Write-Verbose "[Main] Starting batch processing with $($batchCollection.Count) batches"

foreach ($batch in $batchCollection) {
    Write-Verbose "[Main] Processing batch with $($batch.Entities.Count) entities"

    $batchBoundary = "batch_" + [guid]::NewGuid().ToString()
    $changesetBoundary = "changeset_" + [guid]::NewGuid().ToString()
    $headers = New-BatchHeaders -batchBoundary $batchBoundary

    $bodyChangeSet = @()
    foreach ($application in $batch.Entities) {
        $bodyChangeSet += Format-ChangeSet -method $application.Method -changesetBoundary $changesetBoundary -azureStorageAccount $azureStorageAccount -azureTableName $azureTableName -application $application
    }
    $completeBatchTransaction = Format-BatchTransaction -changeSets $bodyChangeSet -batchBoundary $batchBoundary -changesetBoundary $changesetBoundary
    $response = Send-BatchTransaction -batchBody $completeBatchTransaction -azureBatchUri $azureBatchUri -headers $headers
    $response
}

Write-Verbose "[Main] Script execution completed"
