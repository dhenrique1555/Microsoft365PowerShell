# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
$AdminCenterURL          = ""
$SenderEmail             = "" 
$RecipientEmail          = ""      

# --- PnP HTTP CONFIGURATION ---
# Increase default timeout to 15 minutes to prevent "copying content to a stream" drops
$env:PNP_CLIENT_TIMEOUT = 900000

# --- SCOPE & BATCHING ---
$TopSitesToScan          = 90   # Number of sites to process in this run
$SkipSites               = 10   # Number of largest sites to skip (e.g., set to 5 to get the 6th-10th largest)

# --- THRESHOLDS ---
$global:VersionThreshold = 50  
$global:WastedGBThreshold = 0.1 # Flag files where version history wastes more than 0.1 GB (approx 100 MB)
$global:SiteWarningGBThreshold = 10 # 10 GB. Flags individual sites in the summary table.

# --- AZURE STORAGE CONFIGURATION ---
$StorageAccountName      = "" # Replace with your storage account name
$ContainerName           = ""     # Replace with your blob container name
# ==============================================================================

Write-Output "Authenticating to SharePoint Admin Center via Managed Identity..."
Connect-PnPOnline -Url $AdminCenterURL -ManagedIdentity

Write-Output "Fetching $TopSitesToScan largest SharePoint sites (Skipping the top $SkipSites)..."
$TargetSites = Get-PnPTenantSite | 
    Where-Object { $_.Template -notmatch "SITEPAGEPUBLISHING|RedirectSite|AppCatalog" } |
    Sort-Object storageusagecurrent -Descending | 
    Select-Object -Skip $SkipSites -First $TopSitesToScan

# 1. Memory-Safe Generic List and Site Size Mapping
$global:BloatedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
$global:SiteSizes    = @{}

foreach ($Site in $TargetSites) {
    # Start the execution timer for this specific site
    $SiteTimer = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Capture site size for the summary report
    $SiteSizeGB = [math]::Round($Site.storageusagecurrent / 1024, 2)
    $global:SiteSizes[$Site.Title] = $SiteSizeGB

    Write-Output "Scanning Site: $($Site.Url) (Size: $SiteSizeGB GB)"
    
    try {
        Connect-PnPOnline -Url $Site.Url -ManagedIdentity
        $Libraries = Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 -and $_.Hidden -eq $false }

        foreach ($Library in $Libraries) {
            
            # 2. Streaming Batch Processor (PageSize lowered to 25 to prevent CSOM Stack Overflow)
            $null = Get-PnPListItem -List $Library.Title -PageSize 25 -Fields "FileLeafRef","FileRef","_UIVersionString","SMTotalSize","File_x0020_Size","FSObjType" -ScriptBlock {                
                param($items)
                
                foreach ($Item in $items) {
                    # Filter out folders (FSObjType = 0) locally to avoid Parameter Set collision
                    if ($Item["FSObjType"] -eq 0 -and $null -ne $Item["_UIVersionString"]) {
                        
                        $VersionNum = [int][math]::Floor([decimal]$Item["_UIVersionString"])
                        
                        if ($VersionNum -gt 1) {
                            
                            # 3. Safe Object Unwrapping: Get TOTAL Size (File + History) in GB
                            $TotalSizeGB = 0
                            if ($null -ne $Item["SMTotalSize"]) {
                                $RawTotal = $Item["SMTotalSize"]
                                $TotalBytes = if ($RawTotal.GetType().Name -eq "FieldLookupValue") { [double]$RawTotal.LookupId } else { [double]$RawTotal }
                                $TotalSizeGB = [math]::Round(($TotalBytes / 1GB), 2)
                            }

                            # 4. Safe Object Unwrapping: Get CURRENT Size (Just the active file) in GB
                            $CurrentSizeGB = 0
                            if ($null -ne $Item["File_x0020_Size"]) {
                                $RawCurrent = $Item["File_x0020_Size"]
                                $CurrentBytes = if ($RawCurrent.GetType().Name -eq "FieldLookupValue") { [double]$RawCurrent.LookupId } else { [double]$RawCurrent }
                                $CurrentSizeGB = [math]::Round(($CurrentBytes / 1GB), 2)
                            }

                            # 5. The "Pure Math" Bloat Calculation
                            $WastedSpaceGB = $TotalSizeGB - $CurrentSizeGB
                            if ($WastedSpaceGB -lt 0) { $WastedSpaceGB = 0 }

                            # 6. Dual-Threshold Trigger
                            if ($VersionNum -ge $global:VersionThreshold -or $WastedSpaceGB -ge $global:WastedGBThreshold) {
                                
                                $global:BloatedFiles.Add([PSCustomObject]@{
                                    SiteName           = $Site.Title
                                    LibraryName        = $Library.Title
                                    FileName           = $Item["FileLeafRef"]
                                    TotalVersions      = $VersionNum
                                    CurrentFileSizeGB  = $CurrentSizeGB
                                    WastedSpaceGB      = $WastedSpaceGB
                                    TotalStorageUsedGB = $TotalSizeGB
                                    FilePath           = $Item["FileRef"]
                                })
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Output "Failed to complete library scan on site $($Site.Url). Error: $($_.Exception.Message)"
    }
    
    # 7. Manual Garbage Collection
    [System.GC]::Collect()

    # 8. Stop and log the timer
    $SiteTimer.Stop()
    Write-Output "Finished Site: $($Site.Url) in $($SiteTimer.Elapsed.TotalMinutes.ToString('0.00')) minutes."
    Write-Output "------------------------------------------------------"
}

Connect-PnPOnline -Url $AdminCenterURL -ManagedIdentity

if ($global:BloatedFiles.Count -gt 0) {
    
    $SortedFiles = $global:BloatedFiles | Sort-Object WastedSpaceGB -Descending
    Write-Output "Found $($SortedFiles.Count) files matching version bloat criteria. Generating reports..."
    
    # -------------------------------------------------------------------------
    # SITE-LEVEL SUMMARY CALCULATION (With Threshold Flagging)
    # -------------------------------------------------------------------------
    $SiteSummary = $SortedFiles | Group-Object SiteName | ForEach-Object {
        $TotalWasted  = [math]::Round(($_.Group | Measure-Object WastedSpaceGB -Sum).Sum, 2)
        $TotalStorage = [math]::Round(($_.Group | Measure-Object TotalStorageUsedGB -Sum).Sum, 2)
        $SiteStorage  = $global:SiteSizes[$_.Name]
        
        # Flag the site if it exceeds the configured threshold
        $StatusFlag = if ($TotalWasted -ge $global:SiteWarningGBThreshold) { "🚩 HIGH BLOAT" } else { "OK" }
        
        [PSCustomObject]@{
            SiteName           = $_.Name
            FileCount          = $_.Count
            TotalWastedGB      = $TotalWasted
            BloatedFilesSizeGB = $TotalStorage
            SiteTotalStorageGB = $SiteStorage
            Status             = $StatusFlag
        }
    } | Sort-Object TotalWastedGB -Descending

    # --- ADD GRAND TOTAL ROW TO SITE SUMMARY ---
    $SummaryTotalRow = [PSCustomObject]@{
        SiteName           = "GRAND TOTAL"
        FileCount          = ($SiteSummary | Measure-Object FileCount -Sum).Sum
        TotalWastedGB      = [math]::Round(($SiteSummary | Measure-Object TotalWastedGB -Sum).Sum, 2)
        BloatedFilesSizeGB = [math]::Round(($SiteSummary | Measure-Object BloatedFilesSizeGB -Sum).Sum, 2)
        SiteTotalStorageGB = [math]::Round(($SiteSummary | Measure-Object SiteTotalStorageGB -Sum).Sum, 2)
        Status             = "--"
    }
    $SiteSummaryForHtml = @($SiteSummary) + $SummaryTotalRow

    # -------------------------------------------------------------------------
    # CSV GENERATION (With Total Row)
    # -------------------------------------------------------------------------
    $GrandTotalWasted = [math]::Round(($SortedFiles | Measure-Object WastedSpaceGB -Sum).Sum, 2)
    
    $TotalRow = [PSCustomObject]@{
        SiteName           = "GRAND TOTAL"
        LibraryName        = "--"
        FileName           = "--"
        TotalVersions      = "--"
        CurrentFileSizeGB  = "--"
        WastedSpaceGB      = $GrandTotalWasted
        TotalStorageUsedGB = [math]::Round(($SortedFiles | Measure-Object TotalStorageUsedGB -Sum).Sum, 2)
        FilePath           = "--"
    }

    $ReportDate = Get-Date -Format 'yyyyMMdd'
    $BlobName   = "VersionBloatReport_$ReportDate.csv"
    
    $CsvString = ($SortedFiles + $TotalRow) | ConvertTo-Csv -NoTypeInformation | Out-String
    $CsvBytes  = [System.Text.Encoding]::UTF8.GetBytes($CsvString)
    $CsvBase64 = [Convert]::ToBase64String($CsvBytes)

    # -------------------------------------------------------------------------
    # AZURE STORAGE ACCOUNT UPLOAD
    # -------------------------------------------------------------------------
    try {
        Write-Output "Authenticating to Azure to upload report to Storage Account..."
        Connect-AzAccount -Identity | Out-Null
        
        $TempFilePath = Join-Path $env:TEMP $BlobName
        $CsvString | Out-File -FilePath $TempFilePath -Encoding utf8 -Force
        
        Write-Output "Uploading $BlobName to container '$ContainerName'..."
        $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
        Set-AzStorageBlobContent -File $TempFilePath -Container $ContainerName -Blob $BlobName -Context $StorageContext -Force | Out-Null
        
        Write-Output "Successfully saved report to Azure Storage."
    }
    catch {
        Write-Output "WARNING: Failed to upload to Azure Storage. Error: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $TempFilePath) { Remove-Item -Path $TempFilePath -Force }
    }

    # -------------------------------------------------------------------------
    # HTML EMAIL GENERATION & GRAPH API SEND
    # -------------------------------------------------------------------------
    
    # Generate HTML and inject bold/shading for the Grand Total row
    $SummaryTableHtml = $SiteSummaryForHtml | ConvertTo-Html -Fragment
    $SummaryTableHtml = $SummaryTableHtml -replace "<tr><td>GRAND TOTAL</td>", "<tr style='font-weight:bold; background-color:#e9ecef;'><td>GRAND TOTAL</td>"

    $OffenderTableHtml = $SortedFiles | Select-Object -First 50 | ConvertTo-Html -Fragment
    
    $HtmlBody = @"
    <style>
        table{border-collapse:collapse;width:100%;font-family:Arial,sans-serif;margin-bottom:20px;}
        th,td{border:1px solid #dddddd;text-align:left;padding:8px;}
        th{background-color:#f2f2f2;}
        .summary-header{color:#2c3e50; border-bottom: 2px solid #2c3e50; padding-bottom: 4px;}
    </style>
    <h2>Version History Bloat Report</h2>
    <p>Scanned <strong>$TopSitesToScan sites</strong> (Skipped the top $SkipSites largest sites).</p>

    <h3 class="summary-header">Site Resource Summary (in GB)</h3>
    $SummaryTableHtml

    <h3 class="summary-header">Top 50 File Offenders (By Waste)</h3>
    <p><em>The full list of $($SortedFiles.Count) files (with Grand Totals) is attached to this email and saved to Azure Storage.</em></p>
    $OffenderTableHtml
"@

    $MailPayload = @{
        message = @{
            subject      = "Weekly Report: SharePoint Version History Bloat ($($SortedFiles.Count) files flagged)"
            body         = @{ contentType = "HTML"; content = $HtmlBody }
            toRecipients = @( @{ emailAddress = @{ address = $RecipientEmail } } )
            attachments  = @(
                @{
                    "@odata.type" = "#microsoft.graph.fileAttachment"
                    name          = $BlobName
                    contentType   = "text/csv"
                    contentBytes  = $CsvBase64
                }
            )
        }
    }

    Write-Output "Sending email via Graph API with CSV attachment..."
    Invoke-PnPGraphMethod -Method Post -Url "v1.0/users/$SenderEmail/sendMail" -Content $MailPayload
    Write-Output "Email report sent successfully to $RecipientEmail."

} else {
    Write-Output "No files found exceeding thresholds. Skipping email and Storage upload."
}
