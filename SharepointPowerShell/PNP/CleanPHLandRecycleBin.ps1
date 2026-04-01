$SiteURL = ""
$ListName = "Preservation Hold Library" #$ListName = "Permanentes Dokumentarchiv"
  
#Connect to PnP Online
connect-pnpOnline -Url $siteurl -Interactive -ClientId 58e57837-f5c6-4558-8cff-df7b45d77624

 
#Delete all files from the library
Get-PnPList -Identity $ListName | Get-PnPListItem -PageSize 100 -ScriptBlock {
    Param($items) Invoke-PnPQuery } | ForEach-Object { $_.Recycle() | Out-Null
}

$deleteitems = Get-PnPRecycleBinItem | where-object {$_.deletedbyemail -eq ""}
$deleteitems | Clear-PnpRecycleBinItem -force
# Loop through your existing variable
$sizeReport = foreach ($item in $deleteItems) {
    
    # Grab the Size attribute you found
    # Note: Depending on the object type, it might be $item.Size instead of $item["Size"]. 
    # Try $item["Size"] first, and if it's blank, swap it to $item.Size
    $bytes = $item.size
    
    # Ensure it is treated as a number to avoid math errors
    if ($null -eq $bytes) { 
        $bytes = 0 
    } else {
        $bytes = [double]$bytes
    }

    [PSCustomObject]@{
        FileName = $item. Title
        SizeKB   = [math]::Round(($bytes / 1KB), 2)
        SizeMB   = [math]::Round(($bytes / 1MB), 2)
		SizeGB   = [math]::Round(($bytes / 1GB), 2)
    }
}

# Display the results, sorted by the largest files first
$sizeReport | Sort-Object SizeMB -Descending | Format-Table -AutoSize

# Measure the sum of the SizeGB column from your report
$totalStats = $sizeReport | Measure-Object -Property SizeGB -Sum

# Output the grand total clearly
Write-Host "Total storage consumed by these files: $($totalStats.Sum) GB" -ForegroundColor Green
