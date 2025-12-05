# ==============================================================================
# INTUNE HOSTS FILE COLLECTOR
# Logic: Parses local hosts file -> CSV -> Uploads to Azure Blob
# Fixes applied: Removed 'AllDevices' merging to prevent race conditions/data loss.
# ==============================================================================

# --- CONFIGURATION ---
$StorageAccountName = ""
$ContainerName      = ""
# SAS Token: Ensure this token has permission to Write/Create blobs in the container.
$RawSasToken        = ""

# Decode SAS Token
$SasToken = $RawSasToken -replace '&amp;amp;', '&' -replace '&amp;', '&'
$SasToken = '?' + ($SasToken.TrimStart('?'))

# Paths
$WorkDir            = "C:\Windows\Temp\IntuneLogs" # Safer than C:\Temp for System context
$LocalDeviceCsvPath = "$WorkDir\Hosts-$($env:COMPUTERNAME).csv"

# --- HELPER FUNCTIONS ---
function Build-BlobUrl {
    param([string]$account,[string]$container,[string]$blob,[string]$sas)
    return "https://$account.blob.core.windows.net/$container/$blob$sas"
}

# --- EXECUTION ---
try {
    # 1. Prepare Workspace
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

    # 2. Identify Device & User
    # Note: If running as SYSTEM, Win32_ComputerSystem usually grabs the console user.
    $sysInfo    = Get-WmiObject -Class Win32_ComputerSystem    
    $DeviceNameRaw = $env:COMPUTERNAME
    $UserName      = if ($sysInfo.UserName) { $sysInfo.UserName } else { "SYSTEM/NoUser" }
    
    # Sanitize filename
    $DeviceName     = ($DeviceNameRaw -replace '[^a-zA-Z0-9\-_.]', '-')
    $DeviceBlobName = "$DeviceName.csv"
    $DeviceBlobUrl  = Build-BlobUrl -account $StorageAccountName -container $ContainerName -blob $DeviceBlobName -sas $SasToken

    Write-Host "Processing Host file for: $DeviceName ($UserName)"

    # 3. Parse Hosts File
    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    $hostsContent = Get-Content $hostsPath | Where-Object { 
        ($_ -notmatch '^\s*#') -and ($_ -match '^\s*\d{1,3}(\.\d{1,3}){3}\s+') 
    }

    $csvData = @()

    foreach ($line in $hostsContent) {
        $parts = ($line -split '\s+') | Where-Object { $_ -ne '' }
        if ($parts.Count -ge 2) {
            $ip = $parts[0]
            # Handle multiple aliases on one line (e.g. 127.0.0.1 localhost myapp.local)
            foreach ($dns in $parts[1..($parts.Count-1)]) {
                $csvData += [PSCustomObject]@{
                    Timestamp   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                    DeviceName  = $DeviceNameRaw
                    UserName    = $UserName
                    HostEntryIP = $ip
                    HostEntryDNS= $dns
                }
            }
        }
    }

    # 4. Generate CSV
    # If hosts file is empty/clean, we still upload a "blank" or skip. 
    # Here we upload mostly to confirm the device checked in, even if 0 entries.
    if ($csvData.Count -eq 0) {
        Write-Host "No custom host entries found."
        # Create a dummy object to ensure CSV structure exists if you require a file upload
        $csvData += [PSCustomObject]@{
            Timestamp   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            DeviceName  = $DeviceNameRaw
            UserName    = $UserName
            HostEntryIP = "NONE"
            HostEntryDNS= "NONE"
        }
    }

    $csvData | Export-Csv -Path $LocalDeviceCsvPath -NoTypeInformation -Encoding UTF8

    # 5. Upload to Blob (Overwrite specific device file)
    # Using 'Put' allows us to simply overwrite the old file for this specific device.
    # No need to download -> merge -> upload.
    Invoke-WebRequest -Uri $DeviceBlobUrl -Method Put -InFile $LocalDeviceCsvPath -Headers @{
        "x-ms-blob-type" = "BlockBlob"
        "Content-Type"   = "text/csv"
    } -UseBasicParsing -ErrorAction Stop

    Write-Host "Upload Successful: $DeviceBlobName"
    
    # Cleanup
    Remove-Item $LocalDeviceCsvPath -Force -ErrorAction SilentlyContinue

    # Exit Success for Intune
    Exit 0

} catch {
    Write-Error "Script Failed: $($_.Exception.Message)"
    # Exit Failure for Intune (triggers retry based on settings)
    Exit 1
}
