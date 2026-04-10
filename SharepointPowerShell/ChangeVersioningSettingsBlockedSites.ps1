# Define your SharePoint Admin Center URL
$AdminCenterUrl = ""

# Connect to SharePoint Online
Write-Host "Connecting to SharePoint Admin Center..." -ForegroundColor Cyan
Connect-SPOService -Url $AdminCenterUrl
# Retrieve only sites that are currently in a ReadOnly state
Write-Host "Retrieving ReadOnly sites..." -ForegroundColor Cyan
$sites = Get-SPOSite -Limit All | Where-Object {$_.LockState -eq "NoAccess"}

# Validate that sites were found before proceeding
if ($sites.Count -eq 0 -or $null -eq $sites) {
    Write-Host "No ReadOnly sites found. Exiting script." -ForegroundColor Yellow
    exit
}

Write-Host "Found $($sites.Count) NoAccess sites. Starting update process...`n" -ForegroundColor Yellow

foreach ($site in $sites) {
    Write-Host "Processing: $($site.Url)" -ForegroundColor Cyan
    
    try {
        # 1. Unlock the site (We know it is ReadOnly based on the initial filter)
        Write-Host "  [-] Site is currently NoAccess. Unlocking..." -ForegroundColor DarkGray
        Set-SPOSite -Identity $site.Url -LockState Unlock
        
        # Brief pause to allow the backend state change to propagate
        Start-Sleep -Seconds 10 

        # 2. Apply the versioning settings
        Write-Host "  [-] Applying versioning limits..." -ForegroundColor DarkGray
        Set-SPOSite -Identity $site.Url `
            -EnableAutoExpirationVersionTrim $false `
            -MajorVersionLimit 50 `
            -MajorWithMinorVersionsLimit 50 `
            -ExpireVersionsAfterDays 30 `
            -Confirm:$false
            
        Write-Host "  [SUCCESS] Settings applied." -ForegroundColor Green
        
        # 3. Restore the site to ReadOnly
        Write-Host "  [-] Restoring lock state to NoAccess..." -ForegroundColor DarkGray
        Set-SPOSite -Identity $site.Url -LockState NoAccess
    }
    catch {
        Write-Host "  [ERROR] Failed to process site: $($_.Exception.Message)" -ForegroundColor Red
        
        # Failsafe: Attempt to restore the ReadOnly lock state even if the versioning update failed
        Write-Host "  [!] Attempting to restore NoAccess lock state after failure..." -ForegroundColor Yellow
        try { Set-SPOSite -Identity $site.Url -LockState NoAccess } catch {}
    }
    
    Write-Host "" # Empty line for readability between iterations
}

Write-Host "Process completed." -ForegroundColor Green
