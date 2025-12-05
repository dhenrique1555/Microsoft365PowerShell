#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Az.Accounts, Az.Storage

# --- Main Execution Block ---
try {
    $startTime = Get-Date
    Write-Host "Script started at $startTime" -ForegroundColor Cyan

    # --- 1. Configuration & Authentication ---
    Write-Host "Step 1: Authenticating to Azure and Microsoft Graph..."
    
    # Using Managed Identity for authentication
    Connect-AzAccount -Identity
    Connect-MgGraph -Identity
    
    # --- File and Storage Configuration ---
    # IMPORTANT: Ensure the path 'C:\Reports' exists on the machine running the script.
    $localReportPath = "$Env:temp/AdminAccounts_SignIn_Report.csv" # Changed to .csv
    
    # Storage Account Variables
    $storageAccountName = ''
    $StorageAccountKey  = ""
    $containerName      = ''
    $blobName           = 'AdminAccounts_SignIn_Report.csv' 
    
    Write-Host "Local report will be appended to: $localReportPath"

    # --- 2. Fetch Sign-In Logs from Graph API ---
    Write-Host "Step 2: Fetching sign-in logs for 'adm_*' users in the last 24 hours..."
    
    $apiStartTime = (Get-Date).AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $filter = "createdDateTime ge $apiStartTime and startsWith(userPrincipalName, 'adm_')"
    $Url = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter"

    # Loop through all pages of results
    $results = @()
    do {
        if ($results.Count -gt 0) {
            Write-Host "Fetched $($results.Count) logs so far. Checking for the next page..."
        }
        $response = Invoke-MgGraphRequest -Uri $Url -Method GET
        if ($null -ne $response.value) {
            $results += $response.value
        }
        $Url = $response.'@odata.nextLink'
    } while ($Url)

    Write-Host "Finished fetching. Total logs matching filter: $($results.Count)"

    # --- 3. Process and Format the Log Data ---
    if ($results.Count -eq 0) {
        Write-Host "No new sign-in logs found matching the criteria. Skipping report update for today."
        return
    }

    Write-Host "Step 3: Processing and formatting the log data..."
    $reportData = $results | Select-Object -Property @(
         @{Name='id'; Expression={$_.id}},
    @{Name='createdDateTime'; Expression={$_.createdDateTime}},
    @{Name='userPrincipalName'; Expression={$_.userPrincipalName}},
    @{Name='userDisplayName'; Expression={$_.userDisplayName}},
    @{Name='userId'; Expression={$_.userId}},
    @{Name='appId'; Expression={$_.appId}},
    @{Name='appDisplayName'; Expression={$_.appDisplayName}},
    @{Name='isInteractive'; Expression={$_.isInteractive}},
    @{Name='clientAppUsed'; Expression={$_.clientAppUsed}},
    @{Name='conditionalAccessStatus'; Expression={$_.conditionalAccessStatus}},
	 @{Name='AppliedCAPolicyNames'; Expression={($_.appliedConditionalAccessPolicies.Where({$_.result -eq 'success' -or $_.result -eq 'failure'})).displayName -join '; '}},
        @{Name='AppliedCAPolicyResults'; Expression={($_.appliedConditionalAccessPolicies.Where({$_.result -eq 'success' -or $_.result -eq 'failure'})).result -join '; '}},
        @{Name='AppliedCAEnforcedSessionControls'; Expression={($_.appliedConditionalAccessPolicies.Where({$_.result -eq 'success' -or $_.result -eq 'failure'})).enforcedSessionControls -join '; '}},
        @{Name='AppliedCAEnforcedGrantControls'; Expression={($_.appliedConditionalAccessPolicies.Where({$_.result -eq 'success' -or $_.result -eq 'failure'})).enforcedGrantControls -join '; '}},
        @{
            Name = 'AppliedCAIncludeRulesSatisfied';
            Expression = {
                $enforcedPolicies = $_.appliedConditionalAccessPolicies.Where({$_.result -eq 'success' -or $_.result -eq 'failure'});
                $allPolicyRules = foreach ($policy in $enforcedPolicies) {
                    $rulesForThisPolicy = $policy.includeRulesSatisfied | ForEach-Object {"[$($_.conditionalAccessCondition):$($_.ruleSatisfied)]"}
                    "($($rulesForThisPolicy -join ', '))"
                }
                $allPolicyRules -join '; '
            }
        }
    @{Name='correlationId'; Expression={$_.correlationId}},
    @{Name='resourceId'; Expression={$_.resourceId}},
    @{Name='resourceDisplayName'; Expression={$_.resourceDisplayName}},
    @{Name='riskEventTypes_v2'; Expression={$_.riskEventTypes_v2}},
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
    Write-Host "Data processing complete."

    # --- 4. Export Data to CSV (Appending rows) ---
    Write-Host "Step 4: Appending data to '$localReportPath'..."
    
    # Check if the file already exists to handle the CSV header correctly
    if (Test-Path $localReportPath) {
        # If file exists, append the new data without adding a new header
        $reportData | Export-Csv -Path $localReportPath -Append -NoTypeInformation
    } else {
        # If file doesn't exist, create it and write the header
        $reportData | Export-Csv -Path $localReportPath -NoTypeInformation
    }
    
    # --- 5. Upload Report to Azure Storage ---
    Write-Host "Step 5: Uploading updated report to Azure Storage Account '$storageAccountName'..."
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    Set-AzStorageBlobContent -File $localReportPath -Container $containerName -Blob $blobName -Context $storageContext -Force
    Write-Host "Upload complete."

    $endTime = Get-Date
    Write-Host "Script finished successfully at $endTime." -ForegroundColor Green
    Write-Host "Total execution time: $($endTime - $startTime)"
}
catch {
    Write-Error "An error occurred: $_"
    Write-Error "At line: $($_.InvocationInfo.ScriptLineNumber)"
}
