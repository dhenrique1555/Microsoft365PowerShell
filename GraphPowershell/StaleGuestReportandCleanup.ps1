# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context
Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

# Extract token and connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token
Connect-MgGraph -AccessToken $token

# Storage Account Variables
$StorageAccountName = ''
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = "StaleGuestsReport" + (Get-Date -Format 'yyyyMMdd_HHmm') + ".csv"
$ContainerName = ''

# === CONFIGURATION ===
$logFile = "C:\Logs\DeletedGuestUsers.log"
$archiveFile = "C:\Logs\DeletedGuestUsersArchive.csv"
$sendEmail = $true
$dryRun = $false # Change to $false to enable deletion

# Email settings
[string[]]$emailTo = @()
$emailFrom = ""

# === INITIALIZE ===
if (!(Test-Path $logFile)) { New-Item -Path $logFile -ItemType File -Force }
if (!(Test-Path $archiveFile)) {
    "DisplayName,UserPrincipalName,CreatedDateTime,LastSignInDateTime,Reason,DeletionDate" | Out-File -FilePath $archiveFile
}

$createdThreshold = (Get-Date).AddDays(-60)
$signInThreshold = (Get-Date).AddDays(-90)
$deletedUsers = @()

# === PROCESS USERS ===
$guests = Get-MgUser -Filter "userType eq 'Guest'" -Property "signInActivity,ExternalUserState,userPrincipalName,createdDateTime" -All

foreach ($guest in $guests) {
    $shouldDelete = $false
    $reasons = @()

    # Rule 1: Pending Acceptance (or never signed in) + Created > 60 days
    if ((($guest.ExternalUserState -eq "PendingAcceptance") -or (-not $guest.SignInActivity.LastSignInDateTime)) -and $guest.CreatedDateTime -lt $createdThreshold) {
        $shouldDelete = $true
        $reasons += "Pending Acceptance & Created > 60 days"
    }

    # Rule 2: Last Sign-In > 90 days
    if ($guest.SignInActivity.LastSignInDateTime -ne $null -and $guest.SignInActivity.LastSignInDateTime -lt $signInThreshold) {
        $shouldDelete = $true
        $reasons += "Last Sign-In > 90 days"
    }

    # Rule 3: Never signed in AND Created > 90 days
    if (-not $guest.SignInActivity.LastSignInDateTime -and $guest.CreatedDateTime -lt $signInThreshold) {
        $shouldDelete = $true
        $reasons += "Never Signed In & Created > 90 days"
    }

    if ($shouldDelete) {
        $reasonText = $reasons -join " + "
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Deleting guest user: $($guest.DisplayName) ($($guest.UserPrincipalName)) - Reason: $reasonText"
        Write-Host $logEntry
        Add-Content -Path $logFile -Value $logEntry

        if (-not $dryRun) {
            Remove-MgUser -UserId $guest.Id
        }

        # Archive user details
        "$($guest.DisplayName),$($guest.UserPrincipalName),$($guest.CreatedDateTime),$($guest.SignInActivity.LastSignInDateTime),$reasonText,$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content -Path $archiveFile

        # Track for email summary
        $deletedUsers += [PSCustomObject]@{
            DisplayName = $guest.DisplayName
            UserPrincipalName = $guest.UserPrincipalName
            CreatedDateTime = $guest.CreatedDateTime
            LastSignInDateTime = $guest.SignInActivity.LastSignInDateTime
            Reason = $reasonText
        }
    }
}

# Upload report to Azure Storage
Set-AzStorageBlobContent -File $archiveFile -Container $ContainerName -Blob $FileName -Context $StorageContext

# === SUMMARY COUNT ===
$totalCount = $deletedUsers.Count
Write-Host "`nTotal users matching deletion criteria: $totalCount`n"

# === EMAIL SUMMARY ===
if ($sendEmail -and $totalCount -gt 0) {
    $htmlBody = @"
<html>
<head>
<style>
    body { font-family: Arial; color: #333; }
    h2 { color: #2F4F4F; }
    p { font-size: 14px; }
    table { border-collapse: collapse; width: 100%; }
    th { background-color: #4CAF50; color: white; padding: 8px; }
    td { border: 1px solid #ddd; padding: 8px; }
    tr:nth-child(even) { background-color: #f2f2f2; }
</style>
</head>
<body>
    <h2>Guest User Cleanup Report</h2>
    <p>Hello Team,</p>
    <p>The following guest accounts meet the cleanup criteria and would be deleted (dry-run mode is currently <strong>$dryRun</strong>):</p>
    <p><strong>Total Users Matching Criteria:</strong> $totalCount</p>
    <table>
        <tr>
            <th>Display Name</th>
            <th>User Principal Name</th>
            <th>Created Date</th>
            <th>Last Sign-In</th>
            <th>Reason</th>
        </tr>
"@

    foreach ($user in $deletedUsers) {
        $htmlBody += @"
        <tr>
            <td>$($user.DisplayName)</td>
            <td>$($user.UserPrincipalName)</td>
            <td>$($user.CreatedDateTime)</td>
            <td>$($user.LastSignInDateTime)</td>
            <td>$($user.Reason)</td>
        </tr>
"@
    }

    $htmlBody += @"
    </table>
    <p>For full details, see the attached CSV report or check the Azure Storage container: <strong>$ContainerName</strong>.</p>
    <p>Regards,<br>M365 Automation</p>
</body>
</html>
"@

    # Prepare recipients
    $recipients = @()
    foreach ($address in $emailTo) {
        $recipients += @{ EmailAddress = @{ Address = $address } }
    }

    # Read CSV file for attachment
    $fileBytes = [System.IO.File]::ReadAllBytes($archiveFile)
    $encodedFile = [System.Convert]::ToBase64String($fileBytes)

    # Send email using Microsoft Graph with attachment
    $emailParams = @{
        Message = @{
            Subject = "Guest User Deletion Summary - $totalCount Users"
            Body = @{
                ContentType = "HTML"
                Content = $htmlBody
            }
            ToRecipients = $recipients
            Attachments = @(
                @{
                    "@odata.type" = "#microsoft.graph.fileAttachment"
                    Name = $FileName
                    ContentBytes = $encodedFile
                }
            )
        }
        SaveToSentItems = $true
    }

    Send-MgUserMail -UserId $emailFrom -BodyParameter $emailParams
}
