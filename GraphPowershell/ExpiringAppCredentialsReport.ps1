<#
.SYNOPSIS
    Identifies expiring credentials for non-Microsoft applications, validating existence against live Directory data.

.DESCRIPTION
    Fixes "Ghost Notifications" by strictly validating that both the App and the Key exist in the live directory
    and that the Service Principal is Enabled before sending alerts.
#>
param (
    [int]$ThresholdDays = 30,
    [int[]]$NotificationIntervals = @(30, 15, 7, 1),
    [string]$StorageAccountName = "",
    [string]$ResourceGroupName = "",
    [string]$StorageContainerName = "",
    [string]$StorageAccountKey = "",
    [string]$BlobName = "ExpiringCredentialsApplications.csv",
    [string]$HistoryBlobName = "notification_history.json",
    [string[]]$NotificationEmail = @(),
    [string]$FromEmail = ""
)

try {
    $NotificationIntervals = $NotificationIntervals | Sort-Object -Descending
    $microsoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
    $knownMicrosoftAppIds = @('eec80dfe-eeff-4f61-9a69-ed6e023bb1aa', '9ca546c9-0197-4581-a01a-84315da49a4d')
    $today = Get-Date
    $startDate = $today.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endDate = $today.AddDays($ThresholdDays).ToString("yyyy-MM-ddTHH:mm:ssZ")

    # --- Authenticate ---
    Write-Output "Connecting to Azure and Microsoft Graph..."
    Connect-AzAccount -Identity -ErrorAction SilentlyContinue
    Connect-MgGraph -Identity -ErrorAction SilentlyContinue
    $StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey

    # --- Load Notification History ---
    $history = @{}
    Write-Output "Checking for previous notification history..."
    try {
        if (Get-AzStorageBlob -Container $StorageContainerName -Blob $HistoryBlobName -Context $StorageContext -ErrorAction SilentlyContinue) {
            $tempHistoryPath = Join-Path -Path $Env:temp -ChildPath "history_download.json"
            Get-AzStorageBlobContent -Container $StorageContainerName -Blob $HistoryBlobName -Context $StorageContext -Destination $tempHistoryPath -Force
            $historyJson = Get-Content -Path $tempHistoryPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($historyJson)) {
                $parsed = $historyJson | ConvertFrom-Json
                if ($parsed) {
                    foreach ($prop in $parsed.psobject.Properties) { $history[$prop.Name] = $prop.Value }
                }
            }
        }
    }
    catch { Write-Warning "Could not load history. Starting fresh for this run." }

    # --- Get Expiring Credentials (Historical Report) ---
    Write-Output "Fetching report for credentials expiring in next $ThresholdDays days..."
    $expiringCreds = Get-MgBetaReportAppCredentialSignInActivity -Filter "expirationDateTime le $endDate and expirationDateTime ge $startDate" -All

    if (-not $expiringCreds) { Write-Output "No expiring credentials found."; return }

    # --- VALIDATION: Live Lookup with Chunking and Existence Checks ---
    Write-Output "Validating $($expiringCreds.Count) credentials against LIVE directory..."
    
    $spLookupTable = @{}
    $liveAppIds = [System.Collections.Generic.HashSet[string]]::new()
    $validKeyIdHashSet = [System.Collections.Generic.HashSet[string]]::new()
    
    $uniqueAppIds = $expiringCreds | Select-Object -ExpandProperty AppId -Unique
    
    # Process lookups in chunks of 15 to prevent URL length errors (the "Ghost" cause)
    $batchSize = 15
    for ($i = 0; $i -lt $uniqueAppIds.Count; $i += $batchSize) {
        $chunk = $uniqueAppIds[$i..[math]::Min($i + $batchSize - 1, $uniqueAppIds.Count - 1)]
        $filterQuery = "appId in ('" + ($chunk -join "','") + "')"
        
        try {
            # 1. Check Service Principals (Enterprise Apps)
            # Added filter: accountEnabled eq true to skip disabled apps
            $sps = Get-MgServicePrincipal -Filter "($filterQuery) and accountEnabled eq true" -Property "appId,displayName,appOwnerOrganizationId,publisherName,keyCredentials,passwordCredentials,accountEnabled" -ExpandProperty "owners" -All
            
            foreach ($sp in $sps) {
                if (-not $spLookupTable.ContainsKey($sp.AppId)) { $spLookupTable.Add($sp.AppId, $sp) }
                $liveAppIds.Add($sp.AppId) | Out-Null
                if ($sp.KeyCredentials) { foreach ($k in $sp.KeyCredentials) { $validKeyIdHashSet.Add($k.KeyId.ToString()) | Out-Null } }
                if ($sp.PasswordCredentials) { foreach ($p in $sp.PasswordCredentials) { $validKeyIdHashSet.Add($p.KeyId.ToString()) | Out-Null } }
            }

            # 2. Check App Registrations (for keys that might exist on the App object but not SP)
            $apps = Get-MgApplication -Filter $filterQuery -Property "appId,keyCredentials,passwordCredentials" -All
            foreach ($app in $apps) {
                # We consider the app "Live" if the App Registration exists, even if SP is missing
                $liveAppIds.Add($app.AppId) | Out-Null
                if ($app.KeyCredentials) { foreach ($k in $app.KeyCredentials) { $validKeyIdHashSet.Add($k.KeyId.ToString()) | Out-Null } }
                if ($app.PasswordCredentials) { foreach ($p in $app.PasswordCredentials) { $validKeyIdHashSet.Add($p.KeyId.ToString()) | Out-Null } }
            }
        }
        catch {
            Write-Warning "Failed to lookup batch starting with $($chunk[0]). Details: $($_.Exception.Message)"
        }
    }

    # --- Filter and Process ---
    $finalCredentialList = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($cred in $expiringCreds) {
        # Filter 1: Microsoft Known Apps
        if ($knownMicrosoftAppIds -contains $cred.AppId) { continue }

        # Filter 2: Live Existence Check (Stops reporting on deleted apps)
        if (-not $liveAppIds.Contains($cred.AppId)) {
            # Write-Verbose "Skipping $($cred.AppId): App not found in live directory (likely deleted)."
            continue
        }

        # Filter 3: Microsoft Publisher Check
        $servicePrincipal = $spLookupTable[$cred.AppId]
        if ($servicePrincipal) {
            if ($servicePrincipal.AppOwnerOrganizationId -eq $microsoftTenantId) { continue }
            if ($servicePrincipal.PublisherName -match "Microsoft" -and $null -ne $servicePrincipal.PublisherName) { continue }
        }

        # Filter 4: Valid Key Check (Stops reporting on deleted secrets)
        if (-not $validKeyIdHashSet.Contains($cred.KeyId.ToString())) {
            # Write-Verbose "Skipping $($cred.AppId): Key $($cred.KeyId) not found on live app."
            continue
        }

        # --- Notification Logic ---
        $daysRemaining = [math]::Floor(($cred.ExpirationDateTime - (Get-Date)).TotalDays)
        $lastReportedStage = if ($history.ContainsKey($cred.KeyId)) { $history[$cred.KeyId] } else { [int]::MaxValue }
        
        $nextStage = $NotificationIntervals | Where-Object { $daysRemaining -le $_ -and $_ -lt $lastReportedStage } | Select-Object -First 1
        
        if ($null -eq $nextStage) { continue }

        # Resolve Names
        $appName = if ($servicePrincipal) { $servicePrincipal.DisplayName } else { $cred.AppDisplayName }
        if ([string]::IsNullOrWhiteSpace($appName)) { $appName = $cred.AppId }
        
        $ownerName = "Not found"
        if ($servicePrincipal -and $servicePrincipal.Owners) { 
            $ownerName = ($servicePrincipal.Owners.AdditionalProperties.displayName -join '; ') 
        }

        # Construct Object
        $cred | Add-Member -MemberType NoteProperty -Name "ResolvedAppName" -Value $appName -Force
        $cred | Add-Member -MemberType NoteProperty -Name "ResolvedOwner" -Value $ownerName -Force
        $cred | Add-Member -MemberType NoteProperty -Name "NotificationStage" -Value $nextStage -Force
        $finalCredentialList.Add($cred)
    }

    if ($finalCredentialList.Count -gt 0) {
        Write-Output "Processing $($finalCredentialList.Count) valid expiring credentials..."
        
        # --- CSV Export ---
        $csvData = $finalCredentialList | Select-Object @{N='AppOwner';E={$_.ResolvedOwner}}, AppId, @{N='AppDisplayName';E={$_.ResolvedAppName}}, @{N='CredentialType';E={$_.KeyType}}, KeyId, @{N='Usage';E={$_.KeyUsage}}, CreatedDateTime, ExpirationDateTime
        $tempCsvPath = Join-Path -Path $Env:temp -ChildPath "ExpiringCredentialsApplications.csv"
        $csvData | Export-Csv -Path $tempCsvPath -NoTypeInformation -Encoding UTF8
        Set-AzStorageBlobContent -Container $StorageContainerName -Blob $BlobName -Context $StorageContext -File $tempCsvPath -Force

        # --- Email Notifications ---
        $grouped = $finalCredentialList | Group-Object ResolvedAppName
        foreach ($group in $grouped) {
            $appName = $group.Name
            $first = $group.Group[0]
            $recipients = @(foreach ($email in $NotificationEmail) { @{ EmailAddress = @{ Address = $email } } })
            
            # Build HTML
            $detailsHtml = ""
            foreach ($c in $group.Group) {
                $detailsHtml += @"
                <hr><p><strong>Key ID:</strong> $($c.KeyId)<br>
                <strong>Type:</strong> $($c.KeyType)<br>
                <strong>Expires:</strong> $($c.ExpirationDateTime.ToString("dd-MMM-yyyy"))</p>
"@
            }

            $body = @"
            <h3>Expiring Credentials Notice</h3>
            <p>Application: <b>$appName</b><br>Owner: $($first.ResolvedOwner)<br>App ID: $($first.AppId)</p>
            $detailsHtml
"@
            
            $emailParams = @{
                Message = @{
                    Subject = "Action Required: Credentials expiring for '$appName'"
                    Body = @{ ContentType = "HTML"; Content = $body }
                    ToRecipients = $recipients
                }
                SaveToSentItems = $true
            }
            try { Send-MgUserMail -UserId $FromEmail -Body $emailParams } catch { Write-Warning "Failed to send email for $appName" }
            Start-Sleep -Seconds 1
        }

        # --- Update History ---
        foreach ($cred in $finalCredentialList) { $history[$cred.KeyId] = $cred.NotificationStage }
    }

    # --- Cleanup History ---
    # Remove keys that are no longer in the current report (deleted or renewed)
    $reportKeyIds = $expiringCreds | Select-Object -ExpandProperty KeyId -Unique
    $keysToRemove = $history.Keys | Where-Object { $reportKeyIds -notcontains $_ }
    foreach ($k in $keysToRemove) { $history.Remove($k) }

    # Save History
    $history | ConvertTo-Json -Depth 5 | Out-File (Join-Path $Env:temp $HistoryBlobName) -Encoding utf8
    Set-AzStorageBlobContent -Container $StorageContainerName -Blob $HistoryBlobName -Context $StorageContext -File (Join-Path $Env:temp $HistoryBlobName) -Force

    Write-Output "Done."
}
catch {
    Write-Error $_.Exception.Message
}
