# ================================
# Azure Automation Intune Report Export & Upload
# ================================

# --- VARIABLES TO FILL ---
$StorageAccountName = ""      
$ContainerName      = ""
$StorageAccountKey  = ""
$BlobName           = "IntuneWindowsUpdateDevicesReport.csv"      
$blobName1          = 'IntuneWindowsUpdateDevicesReportHistorical.csv'      
$ReportName         = "WUTRDeviceReport"              
$FilterQuery        = "(substringof('00000', Scope) or substringof('00001', Scope) or substringof('00002', Scope) or substringof('Undefined', Scope))"             
$TopRows            = 100                               
$SleepSeconds       = 5                              

# --- TEMP PATHS ---
$ArchiveFile    = "$Env:TEMP\\WindowsUpdateReport.zip"
$CsvDestination = "$Env:TEMP\\WindowsUpdateReport.csv"

# --- AUTHENTICATION ---
Write-Host "Authenticating to Azure and Microsoft Graph..." -ForegroundColor Cyan
Connect-AzAccount -Identity
Connect-MgGraph -Identity

# --- STORAGE CONTEXT ---
$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -storageaccountkey $storageaccountkey
# --- TRIGGER EXPORT JOB ---
$ReportsExportJobsUrl = "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs"
$ReportsExportJobsRequestBody = ConvertTo-Json @{
    reportName = $ReportName
    format     = "csv"
    filter     = $FilterQuery
    select     = @()
    orderBy    = @()
    top        = $TopRows
    skip       = 0
    search     = ""
}
Write-Host "Triggering report export job for $ReportName..." -ForegroundColor Green
$RequestReply = Invoke-MgGraphRequest -Method 'POST' -Uri $ReportsExportJobsUrl -Body $ReportsExportJobsRequestBody -ContentType "application/json"

# --- POLL UNTIL COMPLETED ---
$ExportJobData = $null
$ExportJobUri = "$ReportsExportJobsUrl/$($RequestReply.id)"
Write-Host "Polling export job status..." -ForegroundColor Green
do {
    Start-Sleep -Seconds $SleepSeconds
    $ExportJobData = Invoke-MgGraphRequest -Method 'GET' -Uri $ExportJobUri
    Write-Host "Current job status: $($ExportJobData.status)"
} while ($ExportJobData.status -ne 'completed')

# --- DOWNLOAD ZIP ---
Write-Host "Downloading report ZIP file..." -ForegroundColor Green
Invoke-WebRequest -Uri $ExportJobData.Url -OutFile $ArchiveFile

# --- EXTRACT CSV ---
Write-Host "Extracting CSV from ZIP archive..." -ForegroundColor Green
Remove-Item -Path $CsvDestination -Recurse -Confirm:$false -ErrorAction Ignore
New-Item -Path $CsvDestination -ItemType 'Directory' | Out-Null
Expand-Archive -Path $ArchiveFile -DestinationPath $CsvDestination

# --- UPLOAD Current TO AZURE BLOB ---
$CsvFilePath = Get-ChildItem -Path $CsvDestination -Filter *.csv | Select-Object -First 1
if ($CsvFilePath) {
    Write-Host "Uploading CSV to Azure Blob Storage..." -ForegroundColor Green
    Set-AzStorageBlobContent -File $CsvFilePath.FullName -Container $ContainerName -Blob $BlobName -Context $StorageContext -Force
} else {
    Write-Warning "No CSV file found in extracted archive."
}

# --- APPEND TO HISTORICAL REPORT ---
$CsvFilePath = Get-ChildItem -Path $CsvDestination -Filter *.csv | Select-Object -First 1
$HistoricalFilePath = "$Env:TEMP\\WindowsUpdateReportHistorical.csv"
$ReportDate = (Get-Date).ToString("yyyy-MM-dd")

if ($CsvFilePath) {
    # Import current report
    $CurrentData = Import-Csv -Path $CsvFilePath.FullName

    # Add ReportDate column
    $CurrentData | ForEach-Object { $_ | Add-Member -NotePropertyName "ReportDate" -NotePropertyValue $ReportDate }

    # Append or create historical file without duplicating headers
    if (Test-Path $HistoricalFilePath) {
        $CurrentData | Export-Csv -Path $HistoricalFilePath -NoTypeInformation -Append
    } else {
        $CurrentData | Export-Csv -Path $HistoricalFilePath -NoTypeInformation
    }

    # Upload historical file to Azure Blob
    Write-Host "Uploading historical report to Azure Blob Storage..." -ForegroundColor Green
    Set-AzStorageBlobContent -File $HistoricalFilePath -Container $ContainerName -Blob "IntuneWindowsUpdateDevicesReportHistorical.csv" -Context $StorageContext -Force
} else {
    Write-Warning "No CSV file found to append to historical report."
}

# --- CLEANUP ---
Write-Host "Cleaning up temporary files..." -ForegroundColor Green
Remove-Item -Path $ArchiveFile -Force -ErrorAction Ignore
Remove-Item -Path $CsvDestination -Recurse -Confirm:$false -ErrorAction Ignore

Write-Host "Script completed successfully." -ForegroundColor Cyan
