# --- Configuration ---
$AdminSiteURL = "https://YOURTENANT-admin.sharepoint.com"

# --- Connect to Services ---
Write-Host "Connecting to SharePoint Online..." -ForegroundColor Cyan
Connect-SPOService -Url $AdminSiteURL

Write-Host "Connecting to Microsoft Graph (Entra ID)..." -ForegroundColor Cyan
# We need Group.Read.All to check if the group exists
Connect-MgGraph -Scopes "Group.Read.All", "Directory.Read.All"

# --- Execution ---
Write-Host "Fetching all 'GROUP#0' SharePoint sites..." -ForegroundColor Cyan
# Filter specifically for sites created with the M365 Group template
$Sites = Get-SPOSite -Template "GROUP#0" -Limit All

Write-Host "Fetching all Active Microsoft 365 Groups..." -ForegroundColor Cyan
# Get all active Unified Groups (M365 Groups) IDs into a hash set for fast lookup
$ActiveGroups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All | Select-Object -ExpandProperty Id
$ActiveGroupSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$ActiveGroups)

$OrphanedSites = @()

Write-Host "Analyzing $($Sites.Count) sites for missing groups..." -ForegroundColor Yellow

foreach ($Site in $Sites) {
    # Check if the site has a connected GroupId
    if ($Site.GroupId -ne [Guid]::Empty) {
        $GroupIdStr = $Site.GroupId.ToString()

        # Check if this Group ID exists in our list of Active Azure AD Groups
        if (-not $ActiveGroupSet.Contains($GroupIdStr)) {
            
            # OPTIONAL: Check if it is in the "Soft Deleted" recycle bin
            $SoftDeleted = Get-MgDirectoryDeletedItem -DirectoryObjectId $GroupIdStr -ErrorAction SilentlyContinue

            $Status = if ($SoftDeleted) { "Group Soft-Deleted (Restorable)" } else { "Group Hard-Deleted (Gone)" }

            Write-Host "Found Orphaned Site: $($Site.Url) [$Status]" -ForegroundColor Red
            
            $OrphanedSites += [PSCustomObject]@{
                SiteName      = $Site.Title
                Url           = $Site.Url
                GroupId       = $GroupIdStr
                StorageUsedGB = [Math]::Round($Site.StorageUsageCurrent / 1024, 2)
                GroupStatus   = $Status
            }
        }
    }
}

# --- Output ---
Write-Host "--------------------------------------------------"
Write-Host "Scan Complete. Found $($OrphanedSites.Count) orphaned sites." -ForegroundColor Green

if ($OrphanedSites.Count -gt 0) {
    $OrphanedSites | Format-Table -AutoSize
    
    # Export to CSV
    $CsvPath = "$home\Desktop\OrphanedSPOSites.csv"
    $OrphanedSites | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host "Results exported to: $CsvPath" -ForegroundColor Cyan
}
