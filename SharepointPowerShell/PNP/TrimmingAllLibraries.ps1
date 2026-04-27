# Add one or multiple site URLs to this array
$siteUrls = @(



)

$exportPath = "$env:TEMP\SPO_MultiSite_Handoff_.csv"
$clientId = "58e57837-f5c6-4558-8cff-df7b45d77624"
$tenantRootUrl = ""
$adminUrl = ""
$allSiteLists = @()

# ==========================================
# AUTHENTICATE ONCE (Seed the Token Cache)
# ==========================================
Write-Host "Authenticating interactively ONCE to seed the token cache..." -ForegroundColor Yellow
Connect-PnPOnline -Url $tenantRootUrl -TenantAdminUrl $adminUrl -Interactive -ClientId $clientId


# ==========================================
# LOOP SILENTLY (Riding the Cached Token)
# ==========================================
foreach ($siteUrl in $siteUrls) {
    Write-Host "Connecting to PnP for: $siteUrl" -ForegroundColor Cyan
    
    # Connect using the same connection string. Because we didn't disconnect, it uses the cached token silently.
    Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $clientId
    
    # Fetch lists and filter ONLY for visible Document Libraries (BaseTemplate 101)
    $lists = Get-PnPList | Where-Object { $_.Hidden -eq $false -and $_.BaseTemplate -eq 101 }
    
    foreach ($list in $lists) {
        $allSiteLists += [PSCustomObject]@{
            SiteUrl   = $siteUrl
            ListTitle = $list.Title
        }
    }
    
    # CRITICAL: Do NOT put Disconnect-PnPOnline here! It will wipe the cache.
}

# Cleanly disconnect only after the entire loop is finished
Disconnect-PnPOnline

# Export the master list to a single CSV
$allSiteLists | Export-Csv -Path $exportPath -NoTypeInformation -Force

Write-Host "`nSuccessfully saved data for $($siteUrls.Count) site(s)." -ForegroundColor Green
Write-Host "Filtered exclusively for Document Libraries." -ForegroundColor Yellow
Write-Host "Please close this window and open a fresh PowerShell session for Step 2." -ForegroundColor Cyan

#### New Window - PS 5.1
$adminUrl = ""
$importPath = "$env:TEMP\SPO_MultiSite_Handoff_.csv"
$resultsCsvPath = "$env:TEMP\SPO_BatchDelete_Results.csv"

# Safety check
if (-not (Test-Path $importPath)) {
    Write-Host "Error: Cannot find $importPath. Did Step 1 complete successfully?" -ForegroundColor Red
    return
}

$listData = Import-Csv -Path $importPath

Write-Host "Connecting to SPO Admin... (Please sign in)" -ForegroundColor Cyan
Connect-SPOService -Url $adminUrl

# ==========================================
# PHASE 1: Queue the Jobs & Initialize Tracking
# ==========================================
Write-Host "`nQueueing Batch Deletion Jobs..." -ForegroundColor Cyan
$trackedJobs = @()

foreach ($row in $listData) {
    try {
        Write-Host "Queueing: $($row.ListTitle) on $($row.SiteUrl)" -ForegroundColor DarkGray
        
        # Queue the job
        New-SPOListFileVersionBatchDeleteJob -Site $row.SiteUrl -List $row.ListTitle -TrimUseListPolicy -confirm:$false
        
        # Add to our tracking array with an initial status
        $trackedJobs += [PSCustomObject]@{
            SiteUrl                = $row.SiteUrl
            ListTitle              = $row.ListTitle
            Status                 = "InProgress" 
            StorageReleasedInBytes = 0
        }
    }
    catch {
        Write-Host "Failed to queue $($row.ListTitle): $($_.Exception.Message)" -ForegroundColor Red
        $trackedJobs += [PSCustomObject]@{
            SiteUrl                = $row.SiteUrl
            ListTitle              = $row.ListTitle
            Status                 = "FailedToQueue"
            StorageReleasedInBytes = 0
        }
    }
}


# ==========================================
# PHASE 2: The Watchdog Monitoring & Retry Loop
# ==========================================
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "     MONITORING & RETRY LOOP" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

$allJobsFinished = $false
$pollingIntervalSeconds = 60 # How long to wait between checks

while (-not $allJobsFinished) {
    $allJobsFinished = $true
    $activeCount = 0

    foreach ($job in $trackedJobs) {
        # ONLY skip the job if it reached a definitive, terminal completion state
        if ($job.Status -match "CompleteSuccess|CompletedWithErrors|Cancelled") {
            continue
        }

        # If it failed to queue initially, try to queue it again right now
        if ($job.Status -eq "FailedToQueue") {
            try {
                Write-Host "Retrying queue for: $($job.ListTitle)..." -ForegroundColor Yellow
                New-SPOListFileVersionBatchDeleteJob -Site $job.SiteUrl -List $job.ListTitle -TrimUseListPolicy -confirm:$false
                
                # If it succeeds, update the status so it can be monitored normally below
                $job.Status = "NotStarted" 
                Write-Host "Successfully queued on retry: $($job.ListTitle)" -ForegroundColor Green
            }
            catch {
                # Still failing to queue, we will try again on the next loop iteration
                $allJobsFinished = $false
                $activeCount++
                continue 
            }
        }

        # Now, check the progress of the successfully queued jobs
        try {
            $currentStatus = Get-SPOListFileVersionBatchDeleteJobProgress -Site $job.SiteUrl -List $job.ListTitle
            
            # Update our tracking object with the fresh data from the backend
            $job.Status = $currentStatus.Status
            $job.StorageReleasedInBytes = $currentStatus.StorageReleasedInBytes

            # Check if it hit a terminal state
            if ($job.Status -match "CompleteSuccess|CompletedWithErrors|Cancelled") {
                Write-Host "Finished: $($job.ListTitle) [$($job.Status)]" -ForegroundColor Green
            } else {
                # It's InProgress, NotStarted, or Failed (backend error). Keep looping.
                $allJobsFinished = $false
                $activeCount++
            }
        }
        catch {
            Write-Host "Error fetching status for $($job.ListTitle). Will retry next loop." -ForegroundColor DarkGray
            $allJobsFinished = $false
            $activeCount++
        }
    }

    # If there are still active or unqueued jobs, sleep the script before checking again
    if (-not $allJobsFinished) {
        Write-Host "Waiting on $activeCount job(s)... Sleeping for $pollingIntervalSeconds seconds." -ForegroundColor DarkGray
        Start-Sleep -Seconds $pollingIntervalSeconds
    }
}

Write-Host "`nAll jobs have successfully finished processing!" -ForegroundColor Green
# ==========================================
# PHASE 3: Multi-Site Storage Report (Console)
# ==========================================
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "     BATCH JOB STORAGE REPORT" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

# Group the results by the Site URL
$groupedBySite = $trackedJobs | Group-Object -Property SiteUrl

foreach ($group in $groupedBySite) {
    $siteBytes = ($group.Group | Measure-Object -Property StorageReleasedInBytes -Sum).Sum
    if ($null -eq $siteBytes) { $siteBytes = 0 }
    
    $siteGB = [math]::Round(($siteBytes / 1GB), 4)
    
    Write-Host "Site: $($group.Name)" -ForegroundColor Yellow
    Write-Host " -> Storage Released: $siteGB GB" -ForegroundColor White
}

$totalBytes = ($trackedJobs | Measure-Object -Property StorageReleasedInBytes -Sum).Sum
if ($null -eq $totalBytes) { $totalBytes = 0 }

$totalGB = [math]::Round(($totalBytes / 1GB), 4)

Write-Host "---------------------------------------" -ForegroundColor Cyan
Write-Host "GRAND TOTAL RELEASED: $totalGB GB" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan


# ==========================================
# PHASE 4: Export to CSV
# ==========================================
Write-Host "`nGenerating Final CSV Output..." -ForegroundColor Cyan

$csvData = foreach ($job in $trackedJobs) {
    $bytes = $job.StorageReleasedInBytes
    if ($null -eq $bytes) { $bytes = 0 }
    
    [PSCustomObject]@{
        SiteUrl              = $job.SiteUrl
        ListTitle            = $job.ListTitle
        Status               = $job.Status
        StorageReleasedBytes = $bytes
        StorageReleasedGB    = [math]::Round(($bytes / 1GB), 4)
    }
}

$csvData | Export-Csv -Path $resultsCsvPath -NoTypeInformation -Force

Write-Host "Detailed results successfully exported to: $resultsCsvPath" -ForegroundColor Green
# ==========================================
# PHASE 3: Multi-Site Storage Report (Console)
# ==========================================
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "     BATCH JOB STORAGE REPORT" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

# Group the results by the Site URL
$groupedBySite = $allJobsProgress | Group-Object -Property SiteUrl

# Calculate and display the storage freed PER SITE
foreach ($group in $groupedBySite) {
    $siteBytes = ($group.Group | Measure-Object -Property StorageReleasedInBytes -Sum).Sum
    if ($null -eq $siteBytes) { $siteBytes = 0 }
    
    $siteGB = [math]::Round(($siteBytes / 1GB), 4)
    
    Write-Host "Site: $($group.Name)" -ForegroundColor Yellow
    Write-Host " -> Storage Released: $siteGB GB" -ForegroundColor White
}

# Calculate the GRAND TOTAL across all sites
$totalBytes = ($allJobsProgress | Measure-Object -Property StorageReleasedInBytes -Sum).Sum
if ($null -eq $totalBytes) { $totalBytes = 0 }

$totalGB = [math]::Round(($totalBytes / 1GB), 4)

Write-Host "---------------------------------------" -ForegroundColor Cyan
Write-Host "GRAND TOTAL RELEASED: $totalGB GB" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan

# ==========================================
# PHASE 4: Export to CSV
# ==========================================
Write-Host "`nGenerating CSV Output..." -ForegroundColor Cyan

$csvData = foreach ($job in $allJobsProgress) {
    # Ensure bytes is treated as a number
    $bytes = $job.StorageReleasedInBytes
    if ($null -eq $bytes) { $bytes = 0 }
    
    [PSCustomObject]@{
        SiteUrl              = $job.SiteUrl
        ListTitle            = $job.List
        Status               = $job.Status
        StorageReleasedBytes = $bytes
        StorageReleasedGB    = [math]::Round(($bytes / 1GB), 4)
    }
}

# Export the formatted data
$csvData | Export-Csv -Path $resultsCsvPath -NoTypeInformation -Force

Write-Host "Detailed results successfully exported to: $resultsCsvPath" -ForegroundColor Green

# Optional: Clean up the temp handoff file 
# Remove-Item -Path $importPath -ErrorAction SilentlyContinue

# ==========================================
# PHASE 3: Calculate Storage Released
# ==========================================
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host "        BATCH JOB SUMMARY" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

$totalBytesReleased = ($allJobsProgress | Measure-Object -Property StorageReleasedInBytes -Sum).Sum

if ($null -eq $totalBytesReleased) { 
    $totalBytesReleased = 0 
}

$totalGBReleased = [math]::Round(($totalBytesReleased / 1GB), 4)

Write-Host "Total storage released across all lists: $totalGBReleased GB" -ForegroundColor Green

# Clean up the unique temp file
#Remove-Item -Path $importPath -ErrorAction SilentlyContinue
