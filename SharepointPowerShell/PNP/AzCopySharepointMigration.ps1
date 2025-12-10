# ==============================================================================
# SCRIPT: LOCAL REMEDIATION (Graph API + Detailed Progress)
# PURPOSE: Uses Microsoft Graph with detailed progress monitoring.
# ==============================================================================
# --- 1. CONFIGURATION ---
$localRootPath     = "C:\Temp\Staging_LargeFiles"      # Ensure this drive has space!
$csvReportPath     = Join-Path $localRootPath "LargeFilesSkipped.csv"
$stagingPath       = Join-Path $localRootPath "Staging"
$azCopyPath        = "C:\AzCopy\azcopy.exe"       
$sharePointSiteUrl = ""
$containerName     = ""
$storageAccount    = "" # Fixed variable name usage below
$storageAccountKey = ""

# --- 2. SETUP & CHECKS ---
Write-Host "--- INITIALIZING LOCAL TEST ---" -ForegroundColor Cyan

# Create Directories
if (!(Test-Path $stagingPath)) { New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null }

# Checks
if (!(Test-Path $azCopyPath)) { Write-Error "AzCopy not found at $azCopyPath"; return }
if (!(Test-Path $csvReportPath)) { Write-Error "CSV Report not found at $csvReportPath."; return }


# --- 3. GENERATE SAS TOKEN (FIXED) ---
Write-Host "1. Generating Azure SAS Token..." -ForegroundColor Cyan
try {
    # Create Context
    # FIXED: Changed $storageAccountName to $storageAccount to match config
    $ctx = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageAccountKey

    # Generate Token
    # FIXED: Kept the -StartTime fix here
    $sasToken = New-AzStorageContainerSASToken `
        -Name $containerName `
        -Permission "rwdl" `
        -Context $ctx `
        -StartTime (Get-Date).AddMinutes(-15) `
        -ExpiryTime (Get-Date).AddHours(24)

    # Clean up token format
    if ($sasToken.StartsWith("?")) { $sasToken = $sasToken.Substring(1) }

    Write-Host "   > SAS Token Ready." -ForegroundColor Green
}
catch {
    Write-Error "Failed to generate SAS token. Detailed error: $_"
    throw
}


# --- 4. CONNECT SHAREPOINT ---
Write-Host "2. Connecting to SharePoint..." -ForegroundColor Cyan
try {
    Connect-PnPOnline -Url $sharePointSiteUrl -Interactive -ErrorAction Stop
    $siteId = (Get-PnPSite -Includes Id).Id
    Write-Host "   > Connected to Site ID: $siteId" -ForegroundColor Green
    
    $graphToken = Get-PnPAccessToken
    if ([string]::IsNullOrWhiteSpace($graphToken)) { throw "Could not get Graph Token." }
    $tokenExpires = (Get-Date).AddMinutes(50)
    Write-Host "   > Graph Token Acquired." -ForegroundColor Green
    
} catch { throw "Connection Failed: $($_.Exception.Message)" }


# --- 5. LOAD REPORT ---
$filesToMigrate = Import-Csv $csvReportPath
Write-Host "3. Loaded $($filesToMigrate.Count) large files." -ForegroundColor Cyan

# Cache
$listIdCache = @{}
$libraryUrlCache = @{}
$counter = 0

# --- 6. MIGRATION LOOP ---
foreach ($row in $filesToMigrate) {
    $counter++
    $libTitle = $row.Library
    $relPath  = $row.Path
    $fileName = $row.FileName
    
    # --- RESOLVE LIST ID ---
    if (-not $listIdCache.ContainsKey($libTitle)) {
        try {
            $list = Get-PnPList -Identity $libTitle -Includes Id -ErrorAction Stop
            $listIdCache[$libTitle] = $list.Id
            $libraryUrlCache[$libTitle] = $list.RootFolder.ServerRelativeUrl
        } catch {
            Write-Error "   [!] Could not find library '$libTitle'. Skipping."
            continue
        }
    }
    
    $listId = $listIdCache[$libTitle]
    $fullServerUrl = "$($libraryUrlCache[$libTitle])/$relPath".Replace("//", "/")
    $blobPath = "$libTitle/$relPath".Replace("//", "/").Replace("\", "/")
    
    Write-Host "`n[$counter/$($filesToMigrate.Count)] PROCESSING: $fileName" -ForegroundColor Yellow
    
    $localFilePath = Join-Path $stagingPath $fileName
    
    try {
        if (Test-Path $localFilePath) { Remove-Item $localFilePath -Force }

        # STEP A: RESOLVE ITEM ID
        Write-Host "   [A] Resolving Item..." -NoNewline -ForegroundColor Cyan
        try {
            $item = Get-PnPFile -Url $fullServerUrl -AsListItem -ErrorAction Stop
            $itemId = $item.Id
            $totalSize = [long]$item["SMTotalFileStreamSize"]
            Write-Host " Found (ID: $itemId | Size: $("{0:N2} GB" -f ($totalSize/1GB)))" -ForegroundColor Green
        } catch {
             Write-Error "`n       [!] Could not find file at: $fullServerUrl"
             continue
        }

        # STEP B: DOWNLOAD STREAM
        Write-Host "   [B] Graph Downloading..." -ForegroundColor Cyan
        
        $downloadUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$itemId/driveItem/content"
        
        $client = [System.Net.Http.HttpClient]::new()
        $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $graphToken)
        $client.Timeout = [TimeSpan]::FromMinutes(120) 

        $fs = [System.IO.File]::Create($localFilePath)
        
        try {
            if ((Get-Date) -gt $tokenExpires) {
                 Write-Host "       [!] Refreshing Token..." -ForegroundColor DarkGray
                 $graphToken = Get-PnPAccessToken 
                 $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $graphToken)
                 $tokenExpires = (Get-Date).AddMinutes(50)
            }

            $retry = 0; $success = $false
            while (-not $success -and $retry -lt 3) {
                try {
                    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $downloadUrl)
                    $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                    
                    if (!$resp.IsSuccessStatusCode) { 
                        throw "HTTP $($resp.StatusCode) - $($resp.ReasonPhrase)" 
                    }
                    
                    $netStream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                    
                    $buffer = New-Object byte[] 81920 
                    $totalRead = 0
                    $lastPercent = 0
                    
                    do {
                        $bytesRead = $netStream.Read($buffer, 0, $buffer.Length)
                        if ($bytesRead -gt 0) {
                            $fs.Write($buffer, 0, $bytesRead)
                            $totalRead += $bytesRead
                            
                            $percent = [Math]::Floor(($totalRead / $totalSize) * 100)
                            
                            if ($percent -ne $lastPercent) {
                                Write-Progress -Activity "Downloading: $fileName" -Status "$percent% Complete" -PercentComplete $percent
                                if ($percent % 10 -eq 0 -and $percent -gt 0) {
                                    Write-Host "       > $percent% ..." -ForegroundColor DarkGray
                                }
                                $lastPercent = $percent
                            }
                        }
                    } while ($bytesRead -gt 0)
                    
                    $success = $true
                    Write-Progress -Activity "Downloading: $fileName" -Completed
                    
                } catch { 
                    $retry++
                    Write-Host "       [!] Retry $retry : $($_.Exception.Message)" -ForegroundColor Red 
                    Start-Sleep -Seconds 5
                }
            }
            if (!$success) { throw "Graph Download failed." }
        }
        finally {
            $fs.Close(); $fs.Dispose(); $client.Dispose()
            Write-Progress -Activity "Downloading: $fileName" -Completed
        }
        Write-Host "       > Download Complete." -ForegroundColor Green

        # STEP C: UPLOAD (AzCopy)
        Write-Host "   [C] Uploading via AzCopy..." -ForegroundColor Cyan
        
        # FIXED: Added the '?' before the SAS Token
        $destUrl = "https://$storageAccount.blob.core.windows.net/$containerName/$blobPath`?$sasToken"
        
        $azArgs = @(
            "copy", "`"$localFilePath`"", "`"$destUrl`"",
            "--overwrite=true", "--block-size-mb=100", "--log-level=ERROR"
        )
        
        $process = Start-Process -FilePath $azCopyPath -ArgumentList $azArgs -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "       > Success." -ForegroundColor Green
            Remove-Item $localFilePath -Force
        } else {
            Write-Error "       > AzCopy Failed (Code: $($process.ExitCode))"
        }

    }
    catch {
        Write-Error "`n   > FAILED: $($_.Exception.Message)"
        if (Test-Path $localFilePath) { Remove-Item $localFilePath -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "`n--- LOCAL TEST COMPLETE ---" -ForegroundColor Cyan
