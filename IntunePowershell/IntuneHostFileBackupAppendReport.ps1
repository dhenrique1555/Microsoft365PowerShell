
# Requires Az.Storage module in Azure Automation

# --- CONFIGURATION ---
$StorageAccountName = ""
$ContainerName      = ""
$ResourceGroupName  = ""   # Replace with your RG name

# Generate timestamp for versioning
$timestamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$CombinedBlobName = "alldeviceshosts-$timestamp.csv"

# --- AUTHENTICATION ---
Connect-AzAccount -Identity   # Uses Managed Identity of Automation Account

# Get Storage Account Key
$StorageKey = ""

# Create Storage Context
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey

# --- PROCESS BLOBS ---
Write-Output "Listing blobs in container: $ContainerName"
$blobs = Get-AzStorageBlob -Container $ContainerName -Context $ctx

if (-not $blobs) {
    Write-Error "No blobs found in container."
    Exit 1
}

$allData = @()
$TempPath = "$env:TEMP\HostFiles"
if (-not (Test-Path $TempPath)) { New-Item -ItemType Directory -Path $TempPath | Out-Null }

foreach ($blob in $blobs) {
    $localFile = Join-Path $TempPath $blob.Name
    Write-Output "Downloading: $($blob.Name)"
    Get-AzStorageBlobContent -Blob $blob.Name -Container $ContainerName -Destination $localFile -Context $ctx -Force

    # Import CSV and append
    $csvContent = Import-Csv -Path $localFile
    $allData += $csvContent
}

# Combine into one CSV
$combinedFile = Join-Path $TempPath $CombinedBlobName
$allData | Export-Csv -Path $combinedFile -NoTypeInformation -Encoding UTF8

Write-Output "Uploading combined CSV back to blob storage..."
Set-AzStorageBlobContent -File $combinedFile -Container $ContainerName -Blob $CombinedBlobName -Context $ctx -Force

Write-Output "Upload successful: $CombinedBlobName"

# --- CLEANUP DOWNLOADED FILES ---
Write-Output "Cleaning up downloaded host files..."
Get-ChildItem -Path $TempPath -Filter "*.csv" | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Output "Cleanup complete."
