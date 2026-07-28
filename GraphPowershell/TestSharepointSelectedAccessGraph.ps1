# 1. App Registration Details (Client Credentials)
$tenantId     = ""
$clientId     = ""
$clientSecret = ""

# 2. Granular Target Details
# Since the app can no longer browse the site to find libraries, provide the IDs directly.
$driveId  = "b!k0"
$folderId = "01S" # If you granted access to the library root, change this to "root"

try {
    # ---------------------------------------------------------
    # STEP A: Get the Access Token as the App
    # ---------------------------------------------------------
    $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    $tokenBody = @{
        grant_type    = "client_credentials"
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody -ErrorAction Stop
    $accessToken = $tokenResponse.access_token

    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Accept"        = "application/json"
    }

    # ---------------------------------------------------------
    # STEP B: Fetch the files INSIDE the specific folder
    # ---------------------------------------------------------
    # The '/children' appended to the folder ID returns what is inside it
    $listItemsUrl = "https://graph.microsoft.com/v1.0/drives/$driveId/items/$folderId/children?expand=listItem"
    
    $listResponse = Invoke-RestMethod -Uri $listItemsUrl -Headers $headers -Method Get
    
    Write-Host "Success! Read access is working for the folder contents." -ForegroundColor Green
    Write-Host "---------------------------------------------------"
    
    if ($listResponse.value.Count -eq 0) {
        Write-Host "The folder is currently empty." -ForegroundColor Cyan
    } else {
# Displaying the files/folders and revealing the DriveItemID
        $listResponse.value | Select-Object name, 
            @{Name="Type"; Expression={if ($_.folder) {"Folder"} else {"File"}}}, 
            @{Name="DriveItemID"; Expression={$_.id}}, # <--- Added this to get the Graph ID
            lastModifiedDateTime,
            @{Name="Size(KB)"; Expression={[math]::Round($_.size / 1KB, 2)}} | Format-Table -AutoSize
    }
}
catch {
    Write-Host "Action Failed: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.ErrorDetails) {
        Write-Host "Graph Details: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
    } elseif ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $errorResponse = $reader.ReadToEnd() | ConvertFrom-Json
        Write-Host "Graph Details: $($errorResponse.error.message)" -ForegroundColor Yellow
    } else {
        Write-Host "Details: $_" -ForegroundColor Yellow
    }
}
