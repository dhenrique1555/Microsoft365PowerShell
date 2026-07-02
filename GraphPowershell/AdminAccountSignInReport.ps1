#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Az.Accounts, Az.Storage

<#
.SYNOPSIS
    Collects Entra ID (Azure AD) sign-in logs for admin (adm_*) accounts for the
    current month and writes them to Azure Blob Storage in TWO forms:
        * a single CONSOLIDATED CSV  (AdminAccounts_SignIn_Report.csv) - full history
        * one MONTH-PARTITIONED CSV  (AdminAccounts_SignIn_Report_YYYY-MM.csv) per month
    Both are deduplicated on the unique sign-in 'id'.
#>

# =====================================================================================
#  Helper: merge a set of formatted records into one blob (download -> dedup -> upload)
# =====================================================================================
function Merge-SignInsIntoBlob {
    param(
        [Parameter(Mandatory)]                         $StorageContext,
        [Parameter(Mandatory)] [string]                $ContainerName,
        [Parameter(Mandatory)] [string]                $BlobName,
        [Parameter(Mandatory)] [string[]]              $ColumnOrder,
        [Parameter(Mandatory)] [AllowEmptyCollection()][array] $NewRecords # Changed from [object[]] to [array] for safer binding
    )

    $localPath = Join-Path $Env:temp $BlobName
    if (Test-Path $localPath) { Remove-Item $localPath -Force }   # always start clean

    # Download the existing blob (the authoritative copy) if present.
    $existingData = @()
    # FIX: Use static constructor to avoid New-Object type resolution issues
    $knownIds     = [System.Collections.Generic.HashSet[string]]::new()

    $existingBlob = Get-AzStorageBlob -Container $ContainerName -Blob $BlobName -Context $StorageContext -ErrorAction SilentlyContinue
    if ($null -ne $existingBlob) {
        Get-AzStorageBlobContent -Container $ContainerName -Blob $BlobName -Destination $localPath -Context $StorageContext -Force | Out-Null
        $existingData = @(Import-Csv -Path $localPath)
        foreach ($row in $existingData) {
            $rid = [string]$row.id
            if (-not [string]::IsNullOrEmpty($rid)) { [void]$knownIds.Add($rid) }
        }
    }

    # Keep only records whose id is not already stored (and unique within this batch).
    $dup = 0
    $toAdd = foreach ($rec in $NewRecords) {
        $rid = [string]$rec.id
        if ($knownIds.Contains($rid)) { $dup++; continue }
        [void]$knownIds.Add($rid)
        $rec
    }
    $toAdd = @($toAdd)

    if ($toAdd.Count -eq 0) {
        return [pscustomobject]@{ Blob = $BlobName; Added = 0; Skipped = $dup; Total = $existingData.Count; Uploaded = $false }
    }

    # Merge, normalise columns, sort chronologically, then overwrite the blob.
    $combined  = @($existingData) + $toAdd
    
    # FIX: createdDateTime is already normalised to an ISO 8601 string by the schema below. 
    # We can sort natively without an expression cast.
    $finalData = $combined | Select-Object -Property $ColumnOrder | Sort-Object -Property createdDateTime
    $finalData | Export-Csv -Path $localPath -NoTypeInformation -Encoding UTF8
    Set-AzStorageBlobContent -File $localPath -Container $ContainerName -Blob $BlobName -Context $StorageContext -Force | Out-Null

    return [pscustomobject]@{ Blob = $BlobName; Added = $toAdd.Count; Skipped = $dup; Total = $finalData.Count; Uploaded = $true }
}

# =====================================================================================
#  Helper: derive the YYYY-MM partition key from a createdDateTime value (UTC)
# =====================================================================================
function Get-SignInMonthKey {
    param($CreatedDateTime)
    if ($CreatedDateTime -is [datetime]) {
        return $CreatedDateTime.ToUniversalTime().ToString('yyyy-MM')
    }
    if ($CreatedDateTime -is [System.DateTimeOffset]) {
        return $CreatedDateTime.UtcDateTime.ToString('yyyy-MM')
    }
    $s = [string]$CreatedDateTime
    if ($s.Length -ge 7) { return $s.Substring(0, 7) }
    return $s
}

# =====================================================================================
#  Output schema (defined once). Must match the columns already stored in the report.
# =====================================================================================
$schemaProperties = @(
    @{Name='id'; Expression={$_.id}},
    @{Name='createdDateTime'; Expression={
        $cdt = $_.createdDateTime
        if ($cdt -is [datetime]) { $cdt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        elseif ($cdt -is [System.DateTimeOffset]) { $cdt.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') }
        else { [string]$cdt }
    }},
    @{Name='userPrincipalName'; Expression={$_.userPrincipalName}},
    @{Name='userDisplayName'; Expression={$_.userDisplayName}},
    @{Name='userId'; Expression={$_.userId}},
    @{Name='appId'; Expression={$_.appId}},
    @{Name='appDisplayName'; Expression={$_.appDisplayName}},
    @{Name='isInteractive'; Expression={$_.isInteractive}},
    @{Name='clientAppUsed'; Expression={$_.clientAppUsed}},
    @{Name='conditionalAccessStatus'; Expression={$_.conditionalAccessStatus}},
    
    # FIX: Replaced .Where({}) intrinsic methods with pipeline | Where-Object to prevent type-binding errors on API HashTables.
    @{Name='AppliedCAPolicyNames'; Expression={(@($_.appliedConditionalAccessPolicies) | Where-Object {$_.result -eq 'success' -or $_.result -eq 'failure'}).displayName -join '; '}},
    @{Name='AppliedCAPolicyResults'; Expression={(@($_.appliedConditionalAccessPolicies) | Where-Object {$_.result -eq 'success' -or $_.result -eq 'failure'}).result -join '; '}},
    @{Name='AppliedCAEnforcedSessionControls'; Expression={(@($_.appliedConditionalAccessPolicies) | Where-Object {$_.result -eq 'success' -or $_.result -eq 'failure'}).enforcedSessionControls -join '; '}},
    @{Name='AppliedCAEnforcedGrantControls'; Expression={(@($_.appliedConditionalAccessPolicies) | Where-Object {$_.result -eq 'success' -or $_.result -eq 'failure'}).enforcedGrantControls -join '; '}},
    @{
        Name = 'AppliedCAIncludeRulesSatisfied';
        Expression = {
            $enforcedPolicies = @($_.appliedConditionalAccessPolicies) | Where-Object {$_.result -eq 'success' -or $_.result -eq 'failure'}
            $allPolicyRules = foreach ($policy in $enforcedPolicies) {
                $rulesForThisPolicy = $policy.includeRulesSatisfied | ForEach-Object {"[$($_.conditionalAccessCondition):$($_.ruleSatisfied)]"}
                "($($rulesForThisPolicy -join ', '))"
            }
            $allPolicyRules -join '; '
        }
    },
    @{Name='correlationId'; Expression={$_.correlationId}},
    @{Name='resourceId'; Expression={$_.resourceId}},
    @{Name='resourceDisplayName'; Expression={$_.resourceDisplayName}},
    
    # FIX: Graph API returns riskEventTypes_v2 as an array. It must be joined so it doesn't print as "System.Object[]" in CSV.
    @{Name='riskEventTypes_v2'; Expression={$_.riskEventTypes_v2 -join ', '}},
    @{Name='riskLevelDuringSignIn'; Expression={$_.riskLevelDuringSignIn}},
    @{Name='riskDetail'; Expression={$_.riskDetail}},
    @{Name='StatusErrorCode'; Expression={$_.Status.ErrorCode}},
    @{Name='StatusFailureReason'; Expression={$_.Status.FailureReason}},
    @{Name='IPAddress'; Expression={$_.IpAddress}},
    @{Name='City'; Expression={$_.Location.City}},
    @{Name='State'; Expression={$_.Location.State}},
    @{Name='Country'; Expression={$_.Location.CountryOrRegion}},
    @{Name='Latitude'; Expression={$_.Location.GeoCoordinates.Latitude}},
    @{Name='Longitude'; Expression={$_.Location.GeoCoordinates.Longitude}},
    @{Name='DeviceID'; Expression={$_.DeviceDetail.DeviceId}},
    @{Name='DeviceDisplayName'; Expression={$_.DeviceDetail.DisplayName}},
    @{Name='DeviceOS'; Expression={$_.DeviceDetail.OperatingSystem}},
    @{Name='DeviceBrowser'; Expression={$_.DeviceDetail.Browser}},
    @{Name='DeviceIsCompliant'; Expression={$_.DeviceDetail.IsCompliant}},
    @{Name='DeviceIsManaged'; Expression={$_.DeviceDetail.IsManaged}},
    @{Name='DeviceTrustType'; Expression={$_.DeviceDetail.TrustType}},
    @{Name='signInTokenProtectionStatus'; Expression={$_.signInTokenProtectionStatus}},
    @{Name='signInSessionStatus'; Expression={$_.tokenProtectionStatusDetails.signInSessionStatus}},
    @{Name='signInSessionStatusCode'; Expression={$_.tokenProtectionStatusDetails.signInSessionStatusCode}},
    @{Name='authenticationRequirement'; Expression={$_.authenticationRequirement}}
)

$columnOrder = @(
    'id','createdDateTime','userPrincipalName','userDisplayName','userId','appId',
    'appDisplayName','isInteractive','clientAppUsed','conditionalAccessStatus',
    'AppliedCAPolicyNames','AppliedCAPolicyResults','AppliedCAEnforcedSessionControls',
    'AppliedCAEnforcedGrantControls','AppliedCAIncludeRulesSatisfied','correlationId',
    'resourceId','resourceDisplayName','riskEventTypes_v2','riskLevelDuringSignIn',
    'riskDetail','StatusErrorCode','StatusFailureReason','IPAddress','City','State',
    'Country','Latitude','Longitude','DeviceID','DeviceDisplayName','DeviceOS',
    'DeviceBrowser','DeviceIsCompliant','DeviceIsManaged','DeviceTrustType',
    'signInTokenProtectionStatus','signInSessionStatus','signInSessionStatusCode',
    'authenticationRequirement'
)

# =====================================================================================
#  Main Execution Block
# =====================================================================================
try {
    $startTime = Get-Date
    Write-Host "Script started at $startTime" -ForegroundColor Cyan

    Write-Host "Step 1: Authenticating to Azure and Microsoft Graph..."
    Connect-AzAccount -Identity
    Connect-MgGraph -Identity

    $storageAccountName = ''
    $containerName      = ''
    $blobNamePrefix     = 'AdminAccounts_SignIn_Report'

    $WriteConsolidated  = $true  
    $WriteMonthly       = $true  
    $SafetyOverlapDays  = 2

    $storageContext     = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount

    $nowUtc         = $startTime.ToUniversalTime()
    $monthStartUtc  = $nowUtc.Date.AddDays(1 - $nowUtc.Day)
    $windowStartUtc = $monthStartUtc.AddDays(-$SafetyOverlapDays)
    $apiStartTime   = $windowStartUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")

    Write-Host "Step 2: Fetching 'adm_*' sign-in logs created on/after $apiStartTime..."
	$filter = "createdDateTime ge $apiStartTime and (startsWith(userPrincipalName, 'adm_') or startsWith(userPrincipalName, 'adm-'))"
	$Url = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter&`$top=1000"

    $results = @()
    do {
        if ($results.Count -gt 0) {
            Write-Host "Fetched $($results.Count) logs so far. Checking for the next page..."
        }
        $response = Invoke-MgGraphRequest -Uri $Url -Method GET
        if ($null -ne $response.value) { $results += $response.value }
        $Url = $response.'@odata.nextLink'
    } while ($Url)

    Write-Host "Finished fetching. Total logs returned for the window: $($results.Count)"

    if ($results.Count -eq 0) {
        Write-Host "No admin sign-ins returned for the window. Nothing to do." -ForegroundColor Yellow
    }
    else {
        Write-Host "Step 3: Formatting $($results.Count) record(s)..."
        $allFormatted = @($results | Select-Object -Property $schemaProperties)

        if ($WriteConsolidated) {
            $fullBlobName = "$blobNamePrefix.csv"
            Write-Host "Step 4: Updating consolidated report -> $fullBlobName"
            $consolidatedParams = @{
                StorageContext = $storageContext
                ContainerName  = $containerName
                BlobName       = $fullBlobName
                ColumnOrder    = $columnOrder
                NewRecords     = $allFormatted
            }
            $r = Merge-SignInsIntoBlob @consolidatedParams
            if ($r.Uploaded) {
                Write-Host "  Consolidated: +$($r.Added) new ($($r.Skipped) already present), $($r.Total) total rows." -ForegroundColor Green
            } else {
                Write-Host "  Consolidated already up to date ($($r.Skipped) already present)." -ForegroundColor Yellow
            }
        }

        if ($WriteMonthly) {
            Write-Host "Step 5: Updating month-partitioned reports..."
            $byMonth = @{}
            foreach ($rec in $allFormatted) {
                $mk = Get-SignInMonthKey $rec.createdDateTime
                if (-not $byMonth.ContainsKey($mk)) {
                    # FIX: Use explicit static constructor instead of New-Object with alias string
                    $byMonth[$mk] = [System.Collections.Generic.List[psobject]]::new()
                }
                $byMonth[$mk].Add($rec)
            }

            foreach ($monthKey in ($byMonth.Keys | Sort-Object)) {
                $monthBlobName = "$($blobNamePrefix)_$monthKey.csv"
                $monthParams = @{
                    StorageContext = $storageContext
                    ContainerName  = $containerName
                    BlobName       = $monthBlobName
                    ColumnOrder    = $columnOrder
                    NewRecords     = @($byMonth[$monthKey])
                }
                $r = Merge-SignInsIntoBlob @monthParams
                if ($r.Uploaded) {
                    Write-Host "  [$monthKey] +$($r.Added) new ($($r.Skipped) already present), $($r.Total) total rows." -ForegroundColor Green
                } else {
                    Write-Host "  [$monthKey] already up to date ($($r.Skipped) already present)." -ForegroundColor Yellow
                }
            }
        }
    }

    $endTime = Get-Date
    Write-Host "Script finished successfully at $endTime." -ForegroundColor Green
    Write-Host "Total execution time: $($endTime - $startTime)"
}
catch {
    Write-Host "================ ERROR DIAGNOSTICS ================" -ForegroundColor Red
    Write-Host "Message        : $($_.Exception.Message)"
    Write-Host "Exception type : $($_.Exception.GetType().FullName)"
    Write-Host "Failing line no: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host "Failing command: $($_.InvocationInfo.MyCommand)"
    Write-Host "Failing source : $(($_.InvocationInfo.Line).Trim())"
    Write-Host "Position       : $($_.InvocationInfo.PositionMessage)"
    Write-Host "Script stack   :`n$($_.ScriptStackTrace)"
    if ($_.Exception.InnerException) {
        Write-Host "Inner message  : $($_.Exception.InnerException.Message)"
        Write-Host "Inner type     : $($_.Exception.InnerException.GetType().FullName)"
    }
    Write-Host "===================================================" -ForegroundColor Red
    Write-Error "An error occurred: $($_.Exception.Message)"
}
