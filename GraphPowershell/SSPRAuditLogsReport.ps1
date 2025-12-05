# --- AUTHENTICATION ---
Write-Host "Authenticating to Azure and Microsoft Graph..." -ForegroundColor Cyan
Connect-AzAccount -Identity
Connect-MgGraph -Identity


# Storage Account variables
$StorageAccountName = ""      
$ContainerName      = ""
$StorageAccountKey  = ""
$BlobName           = "SSPRAuditLogsReport.csv"      
$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
$csvPath = "$Env:temp/SSPRAuditLogsReport.csv" # Changed to .csv


# Define time range for last 24 hours
$endDate = Get-Date
$startDate = $endDate.AddHours(-24)

# Format dates to ISO 8601
$startDateTime = $startDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
$endDateTime = $endDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

# Get audit logs and expand InitiatedBy, TargetResources, and include extra fields
$reportdata = Get-MgBetaAuditLogDirectoryAudit `
    -Filter "activityDateTime ge $startDateTime and activityDateTime le $endDateTime and loggedByService eq 'SSPR'" `
    -Sort "activityDateTime desc" |
    Select-Object activityDateTime, activityDisplayName, operationType, result, resultReason, correlationId,
        @{Name='InitiatedBy_DisplayName';Expression={$_.initiatedBy.user.displayName}},
        @{Name='InitiatedBy_UPN';Expression={$_.initiatedBy.user.userPrincipalName}},
        @{Name='InitiatedBy_Id';Expression={$_.initiatedBy.user.id}},
        @{Name='InitiatedBy_IP';Expression={$_.initiatedBy.user.ipAddress}},
        @{Name='TargetResource_DisplayName';Expression={($_.targetResources | ForEach-Object {$_.displayName}) -join ', '}},
        @{Name='TargetResource_UPN';Expression={($_.targetResources | ForEach-Object {$_.userPrincipalName}) -join ', '}},
        @{Name='TargetResource_Id';Expression={($_.targetResources | ForEach-Object {$_.id}) -join ', '}}

# Export to CSV
$csvPath = "$Env:temp/SSPRAuditLogsReport.csv"
$reportData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -a

Write-Host "✅ Report exported to $csvPath"

# --- 4. Export Data to CSV (Appending rows) ---
    Write-Host "Step 4: Appending data to '$csvpath'..."
    
    # Check if the file already exists to handle the CSV header correctly
    if (Test-Path $csvPath) {
        # If file exists, append the new data without adding a new header
        $reportData | Export-Csv -Path $csvpath -Append -NoTypeInformation
    } else {
        # If file doesn't exist, create it and write the header
        $reportData | Export-Csv -Path $csvpath -NoTypeInformation
    }
    
    # --- 5. Upload Report to Azure Storage ---
    Write-Host "Step 5: Uploading updated report to Azure Storage Account '$storageAccountName'..."
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    Set-AzStorageBlobContent -File $csvpath -Container $containerName -Blob $blobName -Context $storageContext -Force
    Write-Host "Upload complete."
