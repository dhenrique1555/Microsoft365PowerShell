#Requires -Modules Microsoft.Online.SharePoint.PowerShell

<#
.SYNOPSIS
    Joins all SharePoint OneDrive personal sites with the manually
    downloaded Unlicensed OneDrive accounts CSV. https://tenantname-admin.sharepoint.com/_layouts/15/online/AdminHome.aspx#/oneDriveAccounts

.DESCRIPTION
    - Matches records using the normalized OneDrive URL.
    - Reads the actual "Unlicensed on" value from the CSV.
    - Reads the actual "Deletion scheduled on" value when populated.
    - Calculates estimated read-only, archive, eDiscovery-loss, and
      deletion-risk dates, aligned to the official published timeline in
      "Manage unlicensed OneDrive user accounts":
      https://learn.microsoft.com/en-us/sharepoint/unlicensed-onedrive-accounts

      That page publishes this canonical milestone table for the
      cumulative nonpayment clock:
        Day 1   - The clock begins. For accounts already unlicensed and
                  unpaid on July 1, 2026, it began that day. For accounts
                  that become unlicensed after July 1, 2026, it begins on
                  the date the license is removed or the user is deleted
                  in Entra ID.
        Day 60  - The account is placed in read-only mode.
        Day 93  - The account is archived (or moved to the recycle bin,
                  depending on account and retention state).
        Day 275 - The account is no longer available in eDiscovery.
        Day 365 - The account is subject to deletion (365 cumulative
                  unpaid days).

      Two enforcement start dates matter and are NOT the same thing:
        * The 93-day archive/60-day read-only mechanism itself began
          rolling out January 27, 2025 (per Microsoft message center
          MC836942 / community guidance). Accounts already unlicensed
          BEFORE February 17, 2025 were migrated on a ONE-TIME FIXED
          schedule (read-only by April 25, 2025, archived by May 16,
          2025) instead of their own +60/+93 day math. This backlog
          migration is now historical/complete, but is kept here so the
          reported basis for older accounts' archive dates is accurate.
        * The 365-day cumulative NONPAYMENT clock only started
          tenant-wide on July 1, 2026 (a few months before this script
          was last updated). Per the Day 1 definition above, accounts
          already unlicensed before that date do NOT get credit for time
          before enforcement began - their clock starts July 1, 2026, not
          their original unlicensed date.
    - The 365-day clock counts CUMULATIVE unpaid days, not consecutive
      calendar days: enabling billing for a period pauses the count, and
      disabling it resumes the count. This script cannot see billing
      history from the CSV, so EstimatedDeletionDate assumes continuous
      nonpayment from the calculated Day 1 and should be treated as a
      worst-case estimate, not a guaranteed date.
    - All calculated dates are ESTIMATES. Real-world rollout has been
      gradual per tenant, so the NativeArchiveStatus field (read directly
      from Get-SPOSite) remains the ground truth for current state.
    - Exports match and date-parsing diagnostics.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$UnlicensedCsvPath = "C:\temp\UnlicensedOneDrives.csv",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "C:\temp\All_OneDrives_Inventory.csv",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SharePointAdminUrl = "https://kscsglobal-admin.sharepoint.com",

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$ReadOnlyAfterDays = 60,

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$ArchiveAfterDays = 93,

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$EDiscoveryLossAfterDays = 275,

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$EstimatedDeletionAfterDays = 365,

    # Accounts unlicensed BEFORE this date were migrated on Microsoft's
    # fixed rollout schedule instead of their own +60/+93 day clock.
    # Source: Microsoft message center / support thread MC836942.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ArchiveEnforcementCutoverDate = "2025-02-17",

    # Fixed dates Microsoft used to migrate the pre-cutover backlog of
    # already-unlicensed accounts. These are NOT calculated per account.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FixedReadOnlyDateForPreCutoverAccounts = "2025-04-25",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FixedArchiveDateForPreCutoverAccounts = "2025-05-16",

    # The 365-day cumulative nonpayment deletion clock only started
    # tenant-wide on this date. Accounts already unlicensed before this
    # date have their clock start here, not on their original unlicensed
    # date. Source: Microsoft Learn "Manage unlicensed OneDrive user
    # accounts" and Message Center MC1381110.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DeletionClockEnforcementStartDate = "2026-07-01"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-RequiredDate {
    param (
        [Parameter(Mandatory)]
        [string]$DateText,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    try {
        return [DateTime]::ParseExact(
            $DateText.Trim(),
            "yyyy-MM-dd",
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch {
        throw "The value '$DateText' for -$ParameterName is not a valid yyyy-MM-dd date."
    }
}

# Parse the enforcement milestone parameters once up front so a typo
# fails fast instead of silently breaking every row's calculation.
$archiveEnforcementCutover = ConvertTo-RequiredDate -DateText $ArchiveEnforcementCutoverDate -ParameterName "ArchiveEnforcementCutoverDate"
$fixedReadOnlyDateForPreCutover = ConvertTo-RequiredDate -DateText $FixedReadOnlyDateForPreCutoverAccounts -ParameterName "FixedReadOnlyDateForPreCutoverAccounts"
$fixedArchiveDateForPreCutover = ConvertTo-RequiredDate -DateText $FixedArchiveDateForPreCutoverAccounts -ParameterName "FixedArchiveDateForPreCutoverAccounts"
$deletionClockEnforcementStart = ConvertTo-RequiredDate -DateText $DeletionClockEnforcementStartDate -ParameterName "DeletionClockEnforcementStartDate"

function Test-StringEmpty {
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    return [string]::IsNullOrWhiteSpace($Value)
}

function Normalize-OneDriveUrl {
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Url
    )

    if (Test-StringEmpty -Value $Url) {
        return $null
    }

    $trimmed = $Url.Trim()
    $trimmed = $trimmed.TrimEnd('/')
    return $trimmed.ToLowerInvariant()
}

function Remove-InvisibleCharacters {
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if (Test-StringEmpty -Value $Value) {
        return $Value
    }

    # Strip BOM leftovers, zero-width spaces, and normalize non-breaking
    # spaces to regular spaces. These are invisible in a console/editor
    # but silently break exact-format date parsing.
    $cleaned = $Value -replace [char]0xFEFF, ""
    $cleaned = $cleaned -replace [char]0x200B, ""
    $cleaned = $cleaned -replace [char]0x00A0, " "
    return $cleaned.Trim()
}

function Get-DiagnosticCharCodes {
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "<null>"
    }

    if ($Value.Length -eq 0) {
        return "<empty>"
    }

    $codes = foreach ($ch in $Value.ToCharArray()) {
        "{0}(U+{1:X4})" -f $ch, [int]$ch
    }

    return ($codes -join " ")
}

# Collects raw values that could not be parsed by any strategy below, for
# later diagnostic export. Capped so a bad file does not blow up memory.
$script:DateParseFailures = [System.Collections.Generic.List[object]]::new()
$script:DateParseFailureCap = 50

function Add-DateParseFailure {
    param (
        [Parameter(Mandatory)]
        [string]$SiteUrl,

        [Parameter(Mandatory)]
        [string]$ColumnName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$RawValue
    )

    if ($script:DateParseFailures.Count -ge $script:DateParseFailureCap) {
        return
    }

    $script:DateParseFailures.Add(
        [PSCustomObject][ordered]@{
            SiteUrl      = $SiteUrl
            ColumnName   = $ColumnName
            RawValue     = $RawValue
            RawLength    = $RawValue.Length
            CharCodes    = Get-DiagnosticCharCodes -Value $RawValue
        }
    )
}

function ConvertFrom-SharePointDate {
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DateText
    )

    if (Test-StringEmpty -Value $DateText) {
        return $null
    }

    $textToParse = Remove-InvisibleCharacters -Value $DateText

    if (Test-StringEmpty -Value $textToParse) {
        return $null
    }

    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    $parsedDate = New-Object DateTime

    # Strategy 1: exact formats covering dot, slash, dash and ISO
    # separators, day-first and month-first, with and without seconds,
    # with and without leading zeros.
    $exactFormats = @(
        "dd.MM.yyyy HH:mm:ss",
        "d.M.yyyy HH:mm:ss",
        "dd.MM.yyyy H:mm:ss",
        "d.M.yyyy H:mm:ss",
        "dd/MM/yyyy HH:mm:ss",
        "d/M/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm:ss",
        "M/d/yyyy HH:mm:ss",
        "MM/dd/yyyy h:mm:ss tt",
        "M/d/yyyy h:mm:ss tt",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-ddTHH:mm:ss",
        "yyyy/MM/dd HH:mm:ss",
        "dd-MM-yyyy HH:mm:ss",
        "d-M-yyyy HH:mm:ss",
        "dd.MM.yyyy",
        "d.M.yyyy",
        "MM/dd/yyyy",
        "yyyy-MM-dd"
    )

    $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

    $success = [DateTime]::TryParseExact(
        $textToParse,
        $exactFormats,
        $invariantCulture,
        $styles,
        [ref]$parsedDate
    )

    if ($success) {
        return $parsedDate
    }

    # Strategy 2: culture-aware generic parsing. Covers common cases where
    # the exported file uses a full culture-specific format we did not
    # anticipate (for example a locale that spells the month name).
    $culturesToTry = @(
        "en-US",
        "de-DE",
        "pt-BR",
        "en-GB"
    )

    foreach ($cultureName in $culturesToTry) {
        try {
            $cultureInfo = [System.Globalization.CultureInfo]::GetCultureInfo($cultureName)
        }
        catch {
            continue
        }

        $success = [DateTime]::TryParse(
            $textToParse,
            $cultureInfo,
            $styles,
            [ref]$parsedDate
        )

        if ($success) {
            return $parsedDate
        }
    }

    # Strategy 2b: invariant-culture generic parsing as a final built-in
    # attempt before falling back to manual digit extraction.
    $success = [DateTime]::TryParse(
        $textToParse,
        $invariantCulture,
        $styles,
        [ref]$parsedDate
    )

    if ($success) {
        return $parsedDate
    }

    # Strategy 3: manual digit extraction. Tolerant of any non-digit
    # separator (including corrupted or unexpected characters), and
    # disambiguates day vs month using the fact that a month cannot
    # exceed 12.
    $digitPattern = '(\d{1,4})\D+(\d{1,2})\D+(\d{2,4})(?:\D+(\d{1,2})\D+(\d{1,2})(?:\D+(\d{1,2}))?)?'
    $match = [regex]::Match($textToParse, $digitPattern)

    if ($match.Success) {
        $part1 = [int]$match.Groups[1].Value
        $part2 = [int]$match.Groups[2].Value
        $part3 = [int]$match.Groups[3].Value

        $hour = 0
        $minute = 0
        $second = 0

        if ($match.Groups[4].Success) { $hour = [int]$match.Groups[4].Value }
        if ($match.Groups[5].Success) { $minute = [int]$match.Groups[5].Value }
        if ($match.Groups[6].Success) { $second = [int]$match.Groups[6].Value }

        # Determine which numeric group is the 4-digit year.
        $year = $null
        $day = $null
        $month = $null

        if ($part1 -gt 31 -or ($match.Groups[1].Value.Length -eq 4)) {
            $year = $part1
            if ($part2 -gt 12) { $day = $part2; $month = $part3 }
            else { $month = $part2; $day = $part3 }
        }
        elseif ($part3 -gt 31 -or ($match.Groups[3].Value.Length -eq 4)) {
            $year = $part3
            if ($part1 -gt 12) { $day = $part1; $month = $part2 }
            else { $month = $part1; $day = $part2 }
        }

        if ($null -ne $year -and $null -ne $day -and $null -ne $month) {
            if ($year -lt 100) { $year += 2000 }

            try {
                return New-Object DateTime($year, $month, $day, $hour, $minute, $second)
            }
            catch {
                return $null
            }
        }
    }

    return $null
}

function Get-OptionalCsvValue {
    param (
        [Parameter(Mandatory)]
        [psobject]$Row,

        [Parameter(Mandatory)]
        [string]$ColumnName,

        [Parameter()]
        [string]$DefaultValue = "N/A"
    )

    if ($Row.PSObject.Properties.Name -notcontains $ColumnName) {
        return $DefaultValue
    }

    $rawValue = $Row.PSObject.Properties[$ColumnName].Value
    $textValue = [string]$rawValue

    if (Test-StringEmpty -Value $textValue) {
        return $DefaultValue
    }

    return $textValue.Trim()
}

Write-Host "Validating input and output paths..." -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $UnlicensedCsvPath -PathType Leaf)) {
    throw "The unlicensed OneDrive CSV was not found: $UnlicensedCsvPath"
}

$exportDirectory = Split-Path -Path $ExportPath -Parent

if (Test-StringEmpty -Value $exportDirectory) {
    throw "The export path must include a directory: $ExportPath"
}

if (-not (Test-Path -LiteralPath $exportDirectory -PathType Container)) {
    Write-Host "Creating export directory: $exportDirectory" -ForegroundColor Yellow
    New-Item -Path $exportDirectory -ItemType Directory -Force | Out-Null
}

Write-Host "Importing the unlicensed OneDrive CSV..." -ForegroundColor Cyan

try {
    $unlicensedData = @(Import-Csv -LiteralPath $UnlicensedCsvPath)
}
catch {
    throw "Failed to import '$UnlicensedCsvPath'. Error: $($_.Exception.Message)"
}

if ($unlicensedData.Count -eq 0) {
    throw "The unlicensed OneDrive CSV does not contain any data rows."
}

$requiredColumns = @(
    "URL",
    "Unlicensed on",
    "Deletion scheduled on"
)

$availableColumns = @($unlicensedData[0].PSObject.Properties.Name)

$missingColumns = @(
    foreach ($requiredColumn in $requiredColumns) {
        if ($availableColumns -notcontains $requiredColumn) {
            $requiredColumn
        }
    }
)

if ($missingColumns.Count -gt 0) {
    $missingText = $missingColumns -join ", "
    $availableText = $availableColumns -join ", "

    throw "The CSV is missing required columns. Missing: $missingText | Available: $availableText"
}

Write-Host "Creating the URL lookup..." -ForegroundColor Cyan

$unlicensedLookup = @{}
$sourceRowsWithoutUrl = 0
$duplicateSourceUrls = 0

foreach ($row in $unlicensedData) {
    $normalizedUrl = Normalize-OneDriveUrl -Url $row.URL

    if ($null -eq $normalizedUrl) {
        $sourceRowsWithoutUrl++
        continue
    }

    if ($unlicensedLookup.ContainsKey($normalizedUrl)) {
        $duplicateSourceUrls++
    }

    # If duplicates exist, the last row for that URL is retained.
    $unlicensedLookup[$normalizedUrl] = $row
}

Write-Host "CSV rows imported: $($unlicensedData.Count)"
Write-Host "Unique URLs in lookup: $($unlicensedLookup.Count)"

if ($sourceRowsWithoutUrl -gt 0) {
    Write-Warning "$sourceRowsWithoutUrl CSV rows had an empty URL and were skipped."
}

if ($duplicateSourceUrls -gt 0) {
    Write-Warning "$duplicateSourceUrls duplicate URLs were found. The last occurrence was used."
}

Write-Host "Connecting to SharePoint Online..." -ForegroundColor Cyan

try {
    Connect-SPOService -Url $SharePointAdminUrl
}
catch {
    throw "Failed to connect to SharePoint Online. Error: $($_.Exception.Message)"
}

Write-Host "Retrieving all OneDrive personal sites..." -ForegroundColor Cyan

try {
    $allOneDrives = @(Get-SPOSite -IncludePersonalSite $true -Template "SPSPERS" -Limit All)
}
catch {
    throw "Failed to retrieve OneDrive sites. Error: $($_.Exception.Message)"
}

Write-Host "OneDrive sites retrieved: $($allOneDrives.Count)"

$currentDate = Get-Date
$report = [System.Collections.Generic.List[object]]::new()

$matchedSites = 0
$unmatchedSites = 0
$emptyUnlicensedDates = 0
$invalidUnlicensedDates = 0
$processedSites = 0
$totalSites = $allOneDrives.Count

foreach ($site in $allOneDrives) {
    $processedSites++

    $showProgress = ($processedSites % 100 -eq 0) -or ($processedSites -eq $totalSites)

    if ($showProgress) {
        if ($totalSites -gt 0) {
            $ratio = $processedSites / $totalSites
            $percentComplete = [Math]::Round($ratio * 100)
        }
        else {
            $percentComplete = 100
        }

        Write-Progress -Activity "Processing OneDrive sites" -Status "$processedSites of $totalSites" -PercentComplete $percentComplete
    }

    $normalizedSiteUrl = Normalize-OneDriveUrl -Url $site.Url

    if ($null -ne $site.StorageUsageCurrent) {
        $storageInGB = [Math]::Round(($site.StorageUsageCurrent / 1024), 2)
    }
    else {
        $storageInGB = 0
    }

    if ($null -ne $site.StorageQuota) {
        $quotaInGB = [Math]::Round(($site.StorageQuota / 1024), 2)
    }
    else {
        $quotaInGB = 0
    }

    # Default values for a site that is not found in the CSV.
    $csvMatchStatus = "Not found in CSV"
    $dateParseStatus = "Not applicable"

    $sourceOwnerEmail = "N/A"
    $unlicensedDueTo = "N/A"
    $deletionBlockedBy = "N/A"
    $accountProvisionedForUpn = "N/A"

    $unlicensedDateRaw = "Not found in CSV"
    $unlicensedDate = "N/A"

    $readOnlyDate = "N/A"
    $archiveDate = "N/A"
    $archiveDateBasis = "N/A"
    $calculatedArchiveStatus = "Not evaluated"

    $deletionClockStartDate = "N/A"
    $deletionClockBasis = "N/A"
    $estimatedEDiscoveryLossDate = "N/A"
    $scheduledDeletionDate = "N/A"
    $estimatedDeletionDate = "N/A"

    $lifecyclePath = "N/A"

    $hasMatch = ($null -ne $normalizedSiteUrl) -and $unlicensedLookup.ContainsKey($normalizedSiteUrl)

    if ($hasMatch) {
        $matchedSites++
        $csvMatchStatus = "Matched"

        $csvRow = $unlicensedLookup[$normalizedSiteUrl]

        $sourceOwnerEmail = Get-OptionalCsvValue -Row $csvRow -ColumnName "Owner email"
        $unlicensedDueTo = Get-OptionalCsvValue -Row $csvRow -ColumnName "Unlicensed due to"
        $deletionBlockedBy = Get-OptionalCsvValue -Row $csvRow -ColumnName "Deletion blocked by" -DefaultValue "Not blocked or not reported"
        $accountProvisionedForUpn = Get-OptionalCsvValue -Row $csvRow -ColumnName "Account provisioned for (UPN)"

        # "Owner deleted from Entra ID" accounts follow the standard
        # OneDrive retention-and-deletion process (retention period, then
        # retention policies, then holds) rather than the unlicensed
        # 93-day archive / 365-day nonpayment clock. Flag this so the
        # calculated dates below are not misread as applying to them.
        if ($unlicensedDueTo -eq "Owner deleted from Entra ID") {
            $lifecyclePath = "Standard OneDrive deletion process (owner deleted from Entra ID) - governed by OneDrive retention period, retention policies, and holds, not the unlicensed archive/365-day clock"
        }
        else {
            $lifecyclePath = "Unlicensed OneDrive lifecycle (read-only/archive/365-day nonpayment clock applies)"
        }

        # This is the correct source column name from the downloaded CSV.
        $unlicensedDateRaw = [string]$csvRow.'Unlicensed on'

        if (Test-StringEmpty -Value $unlicensedDateRaw) {
            $emptyUnlicensedDates++
            $unlicensedDateRaw = "Empty in CSV"
            $unlicensedDate = "N/A"
            $dateParseStatus = "Empty"
            $calculatedArchiveStatus = "Unknown"
        }
        else {
            $parsedUnlicensedDate = ConvertFrom-SharePointDate -DateText $unlicensedDateRaw

            if ($null -ne $parsedUnlicensedDate) {
                $dateParseStatus = "Parsed"
                $unlicensedDate = $parsedUnlicensedDate.ToString("yyyy-MM-dd HH:mm:ss")

                # --- Archive / read-only milestone ---
                # Accounts unlicensed before the cutover were migrated on
                # Microsoft's fixed rollout schedule, not their own
                # +60/+93 day math.
                if ($parsedUnlicensedDate -lt $archiveEnforcementCutover) {
                    $readOnlyDateObject = $fixedReadOnlyDateForPreCutover
                    $archiveDateObject = $fixedArchiveDateForPreCutover
                    $archiveDateBasis = "Fixed migration timeline (account was already unlicensed before $($archiveEnforcementCutover.ToString('yyyy-MM-dd')))"
                }
                else {
                    $readOnlyDateObject = $parsedUnlicensedDate.AddDays($ReadOnlyAfterDays)
                    $archiveDateObject = $parsedUnlicensedDate.AddDays($ArchiveAfterDays)
                    $archiveDateBasis = "Individual unlicensed-date clock (+$ArchiveAfterDays days)"
                }

                $readOnlyDate = $readOnlyDateObject.ToString("yyyy-MM-dd")
                $archiveDate = $archiveDateObject.ToString("yyyy-MM-dd")

                if ($currentDate -ge $archiveDateObject) {
                    $calculatedArchiveStatus = "Archive threshold reached"
                }
                elseif ($currentDate -ge $readOnlyDateObject) {
                    $calculatedArchiveStatus = "Read-only threshold reached"
                }
                else {
                    $calculatedArchiveStatus = "Pending archive threshold"
                }

                # --- 365-day cumulative nonpayment deletion clock ---
                # The clock only started tenant-wide on the enforcement
                # start date. Accounts already unlicensed before that
                # date do not get credit for the time before enforcement
                # began.
                if ($parsedUnlicensedDate -lt $deletionClockEnforcementStart) {
                    $deletionClockStartObject = $deletionClockEnforcementStart
                    $deletionClockBasis = "Tenant-wide enforcement start ($($deletionClockEnforcementStart.ToString('yyyy-MM-dd'))) - account was already unlicensed before enforcement began, so the clock does not start on its original unlicensed date"
                }
                else {
                    $deletionClockStartObject = $parsedUnlicensedDate
                    $deletionClockBasis = "Individual unlicensed-date clock (account became unlicensed on/after enforcement start)"
                }

                $deletionClockStartDate = $deletionClockStartObject.ToString("yyyy-MM-dd")

                # Day 275 on the official timeline: the account is no
                # longer available in eDiscovery.
                $eDiscoveryLossDateObject = $deletionClockStartObject.AddDays($EDiscoveryLossAfterDays)
                $estimatedEDiscoveryLossDate = $eDiscoveryLossDateObject.ToString("yyyy-MM-dd")

                # Day 365 on the official timeline: subject to deletion
                # after 365 cumulative unpaid days.
                $estimatedDeletionDateObject = $deletionClockStartObject.AddDays($EstimatedDeletionAfterDays)
                $estimatedDeletionDate = $estimatedDeletionDateObject.ToString("yyyy-MM-dd")
            }
            else {
                $invalidUnlicensedDates++
                $dateParseStatus = "Invalid format"
                $unlicensedDate = "Invalid Data"
                $readOnlyDate = "Invalid Data"
                $archiveDate = "Invalid Data"
                $archiveDateBasis = "Invalid Data"
                $deletionClockStartDate = "Invalid Data"
                $deletionClockBasis = "Invalid Data"
                $estimatedEDiscoveryLossDate = "Invalid Data"
                $estimatedDeletionDate = "Invalid Data"
                $calculatedArchiveStatus = "Unknown"

                Add-DateParseFailure -SiteUrl $site.Url -ColumnName "Unlicensed on" -RawValue $unlicensedDateRaw
            }
        }

        # Read the actual scheduled deletion date reported by SharePoint.
        $scheduledDeletionRaw = [string]$csvRow.'Deletion scheduled on'

        if (-not (Test-StringEmpty -Value $scheduledDeletionRaw)) {
            $parsedScheduledDeletionDate = ConvertFrom-SharePointDate -DateText $scheduledDeletionRaw

            if ($null -ne $parsedScheduledDeletionDate) {
                $scheduledDeletionDate = $parsedScheduledDeletionDate.ToString("yyyy-MM-dd HH:mm:ss")
            }
            else {
                # Preserve the raw source value for investigation.
                $scheduledDeletionDate = $scheduledDeletionRaw.Trim()
                Add-DateParseFailure -SiteUrl $site.Url -ColumnName "Deletion scheduled on" -RawValue $scheduledDeletionRaw
            }
        }
    }
    else {
        $unmatchedSites++
    }

    if ($null -ne $site.LastContentModifiedDate) {
        try {
            $lastModifiedDate = ([datetime]$site.LastContentModifiedDate).ToString("yyyy-MM-dd")
        }
        catch {
            $lastModifiedDate = [string]$site.LastContentModifiedDate
        }
    }
    else {
        $lastModifiedDate = "N/A"
    }

    if (($site.PSObject.Properties.Name -contains "ArchiveStatus") -and ($null -ne $site.ArchiveStatus)) {
        $nativeArchiveStatus = [string]$site.ArchiveStatus
    }
    else {
        $nativeArchiveStatus = "Property unavailable"
    }

    if (Test-StringEmpty -Value $site.Owner) {
        $siteOwner = "N/A"
    }
    else {
        $siteOwner = [string]$site.Owner
    }

    if ($null -eq $site.Status) {
        $siteStatus = "N/A"
    }
    else {
        $siteStatus = [string]$site.Status
    }

    if ($null -eq $site.LockState) {
        $lockState = "N/A"
    }
    else {
        $lockState = [string]$site.LockState
    }

    $reportRow = [PSCustomObject][ordered]@{
        SiteUrl                  = $site.Url
        Owner                    = $siteOwner
        SourceOwnerEmail         = $sourceOwnerEmail
        Status                   = $siteStatus
        LockState                = $lockState
        NativeArchiveStatus      = $nativeArchiveStatus
        CalculatedArchiveStatus  = $calculatedArchiveStatus
        LifecyclePath            = $lifecyclePath
        CsvMatchStatus           = $csvMatchStatus
        DateParseStatus          = $dateParseStatus
        StorageGB                = $storageInGB
        StorageQuotaGB           = $quotaInGB
        UnlicensedDateRaw        = $unlicensedDateRaw
        UnlicensedDate           = $unlicensedDate
        ReadOnlyDate             = $readOnlyDate
        ArchiveDate              = $archiveDate
        ArchiveDateBasis         = $archiveDateBasis
        DeletionClockStartDate   = $deletionClockStartDate
        DeletionClockBasis       = $deletionClockBasis
        EstimatedEDiscoveryLossDate = $estimatedEDiscoveryLossDate
        ScheduledDeletionDate    = $scheduledDeletionDate
        EstimatedDeletionDate    = $estimatedDeletionDate
        UnlicensedDueTo          = $unlicensedDueTo
        DeletionBlockedBy        = $deletionBlockedBy
        AccountProvisionedForUPN = $accountProvisionedForUpn
        LastModifiedDate         = $lastModifiedDate
    }

    $report.Add($reportRow)
}

Write-Progress -Activity "Processing OneDrive sites" -Completed

Write-Host "Exporting the combined report..." -ForegroundColor Cyan

try {
    $report | Sort-Object -Property SiteUrl | Export-Csv -LiteralPath $ExportPath -NoTypeInformation -Encoding UTF8
}
catch {
    throw "Failed to export '$ExportPath'. Error: $($_.Exception.Message)"
}

$storageMeasurement = $report | Measure-Object -Property StorageGB -Sum
$quotaMeasurement = $report | Measure-Object -Property StorageQuotaGB -Sum

if ($null -eq $storageMeasurement.Sum) {
    $totalStorageGB = 0
}
else {
    $totalStorageGB = [Math]::Round($storageMeasurement.Sum, 2)
}

if ($null -eq $quotaMeasurement.Sum) {
    $totalQuotaGB = 0
}
else {
    $totalQuotaGB = [Math]::Round($quotaMeasurement.Sum, 2)
}

$nativeArchivedSites = @($report | Where-Object { $_.NativeArchiveStatus -in @("FullyArchived", "RecentlyArchived", "Archived") }).Count

if ($script:DateParseFailures.Count -gt 0) {
    $diagnosticsPath = Join-Path -Path $exportDirectory -ChildPath "DateParseFailures_Diagnostic.csv"

    try {
        $script:DateParseFailures |
            Export-Csv -LiteralPath $diagnosticsPath -NoTypeInformation -Encoding UTF8

        Write-Host ""
        Write-Warning "Some date values could not be parsed by any strategy. Diagnostic details written to: $diagnosticsPath"
    }
    catch {
        Write-Warning "Failed to write date-parse diagnostics file. Error: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Sample raw values that failed to parse (showing up to 5):" -ForegroundColor Yellow

    $sampleFailures = $script:DateParseFailures | Select-Object -First 5

    foreach ($failure in $sampleFailures) {
        Write-Host "  Column: $($failure.ColumnName)"
        Write-Host "  Site:   $($failure.SiteUrl)"
        Write-Host "  Raw:    '$($failure.RawValue)'  (length: $($failure.RawLength))"
        Write-Host "  Codes:  $($failure.CharCodes)"
        Write-Host ""
    }
}

Write-Host ""
Write-Host "Export completed successfully." -ForegroundColor Green
Write-Host "Export path: $ExportPath"
Write-Host "Total OneDrive sites: $($report.Count)"
Write-Host "Matched against unlicensed CSV: $matchedSites"
Write-Host "Not found in unlicensed CSV: $unmatchedSites"
Write-Host "Native archived or recently archived: $nativeArchivedSites"
Write-Host "Empty unlicensed dates: $emptyUnlicensedDates"
Write-Host "Invalid unlicensed date formats: $invalidUnlicensedDates"
Write-Host "Total storage used: $totalStorageGB GB"
Write-Host "Total storage quota: $totalQuotaGB GB"
Write-Host ""
Write-Host "Note: CalculatedArchiveStatus, ArchiveDate, EstimatedEDiscoveryLossDate, and" -ForegroundColor Yellow
Write-Host "EstimatedDeletionDate are ESTIMATES based on the published timeline at:" -ForegroundColor Yellow
Write-Host "https://learn.microsoft.com/en-us/sharepoint/unlicensed-onedrive-accounts" -ForegroundColor Yellow
Write-Host "The 365-day clock counts CUMULATIVE unpaid days (pauses while billing is" -ForegroundColor Yellow
Write-Host "enabled), and real-world rollout has been gradual per tenant. Treat" -ForegroundColor Yellow
Write-Host "NativeArchiveStatus (read directly from Get-SPOSite) as the ground truth." -ForegroundColor Yellow
