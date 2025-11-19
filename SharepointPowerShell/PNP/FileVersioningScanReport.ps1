Measure-command {
# Parameters
$SiteURL = ""
$MaxVersions = 25
$MinFileSize = 1048576   # 1MB in byte
$OutputPathDetailed = "C:\Temp\FilesList_Detailed.csv"
$OutputPathSummary = "C:\Temp\FilesList_Summary.csv"
$ReauthInterval = 10     # minutes

# Initial authentication
Connect-PnPOnline -Url $SiteURL -Interactive
$LastAuthTime = Get-Date

# Get all document libraries
$Libraries = Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 }

$AllResults = @()
$SummaryResults = @()
$TotalLibraries = $Libraries.Count
$LibraryIndex = 0

foreach ($Library in $Libraries) {
    $LibraryIndex++
    Write-Host "[$LibraryIndex/$TotalLibraries] Processing Library: $($Library.Title)"

    # ✅ Re-authenticate if 10 minutes passed
    if (((Get-Date) - $LastAuthTime).TotalMinutes -ge $ReauthInterval) {
        Write-Host "Re-authenticating to keep session alive..."
        Connect-PnPOnline -Url $SiteURL -Interactive
        $LastAuthTime = Get-Date
    }

    # Get items
    $Files = Get-PnPListItem -List $Library.Title -PageSize 500 -Fields "FileLeafRef","FileRef","File_x0020_Size","Modified","Editor"
    $LargeFiles = $Files | Where-Object { $_.FileSystemObjectType -eq "File" -and $_["File_x0020_Size"] -gt $MinFileSize }

    $TotalFiles = $LargeFiles.Count
    $ProgressActivity = "Processing files in $($Library.Title)"

   

$Results = $LargeFiles | ForEach-Object -Parallel {
    $FileUrl = $_.FieldValues["FileRef"]
    $FileSize = $_.FieldValues["File_x0020_Size"]
    $FileName = $_.FieldValues["FileLeafRef"]
Write-host "Processing file $FileURL" -foregroundcolor Green -backgroundcolor White
    # Directly use FileRef without encoding
    $Versions = Get-PnPFileVersion -Url $FileUrl -ErrorAction Continue

    if ($Versions -and $Versions.Count -gt $using:MaxVersions) {
        $TotalVersionSize = ($Versions | Measure-Object -Property Size -Sum).Sum

        [pscustomobject]@{
            Library         = $using:Library.Title
            Filename        = $FileName
            URL             = $FileUrl
            VersionCount    = $Versions.Count
            FileSizeKB      = [math]::Round($FileSize / 1024, 2)
            TotalVersionsKB = [math]::Round($TotalVersionSize / 1024, 2)
            LastModified    = $_.FieldValues["Modified"]
            ModifiedBy      = $_.FieldValues["Editor"].Email
        }
    }
} -ThrottleLimit 8



    # Collect results
    $AllResults += $Results

    # Summary for this library
    if ($Results.Count -gt 0) {
        $LibraryTotalSize = ($Results | Measure-Object -Property FileSizeKB -Sum).Sum
        $LibraryTotalVersionsSize = ($Results | Measure-Object -Property TotalVersionsKB -Sum).Sum
        $SummaryResults += [pscustomobject]@{
            Library             = $Library.Title
            FilesOverThreshold  = $Results.Count
            TotalFileSizeMB     = [math]::Round($LibraryTotalSize / 1024, 2)
            TotalVersionsSizeMB = [math]::Round($LibraryTotalVersionsSize / 1024, 2)
        }
    }
}

# Overall summary
$OverallFileSize = ($AllResults | Measure-Object -Property FileSizeKB -Sum).Sum
$OverallVersionsSize = ($AllResults | Measure-Object -Property TotalVersionsKB -Sum).Sum
$SummaryResults += [pscustomobject]@{
    Library             = "TOTAL"
    FilesOverThreshold  = $AllResults.Count
    TotalFileSizeMB     = [math]::Round($OverallFileSize / 1024, 2)
    TotalVersionsSizeMB = [math]::Round($OverallVersionsSize / 1024, 2)
}

# Export reports
$AllResults | Export-Csv -Path $OutputPathDetailed -NoTypeInformation
$SummaryResults | Export-Csv -Path $OutputPathSummary -NoTypeInformation

Write-Host "Export completed:"
Write-Host "Detailed report: $OutputPathDetailed"
Write-Host "Summary report:  $OutputPathSummary"
}
