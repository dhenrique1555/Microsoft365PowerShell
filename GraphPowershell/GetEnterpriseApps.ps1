
# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

#Extract the access token from the AzAccount authentication context and use it to connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token

$RequiredScopes = @(
"Directory.ReadWrite.All"
"AuditLog.Read.All"
"Organization.Read.All"
"User.Read.All"
"UserAuthenticationMethod.ReadWrite.All"
)
$securetoken = ConvertTo-SecureString -String $token -ASPLAINTEXT -force
Connect-MgGraph -AccessToken $token
Get-mgcontext | Select -expandproperty Scopes 

$EAs = Get-MgServicePrincipal -All -Filter "tags/any(t:t eq 'WindowsAzureActiveDirectoryIntegratedApp')"
#StorageAccountProperties to Save File
$excelfilename = "$Env:temp/GetEnterpriseAppList.csv"
$StorageAccountName = ''
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = "GetEnterpriseAppList.csv"
$ContainerName  = ''

$eaoutput = @()
foreach($ea in $EAs){
    $eaoutput += New-object PSObject -property $([ordered]@{
    DisplayName = $ea.DisplayName
    ObjectId = $ea.id
    AppId = $ea.AppID
    SingleSignOn = $ea.PreferredSingleSignOnMode
    ReplyUrl = $ea.replyurls -join ","
    LoginURL = $ea.LoginURl
    LogoutURL = $ea.LogoutURL
    SSOCertificateExpirationDate = $ea.PreferredTokenSigningKeyEndDateTime
    SignInAudience = $ea.SignInAudience
    HomepageURL = $ea.Homepage
    AppRoleAssignmentRequired = $ea.AppRoleAssignmentRequired
    AccountEnabled = $ea.AccountEnabled
    ServicePrincipalType = "EnterpriseApplication"
    }
    )
}


$MicrosoftApps = Get-MgBetaServicePrincipal -All -Filter "startswith(Publishername,'Microsoft')"

$MicrosoftAppoutput = @()
foreach($MicrosoftApp in $MicrosoftApps){
    $MicrosoftAppoutput += New-object PSObject -property $([ordered]@{
    DisplayName = $MicrosoftApp.DisplayName
    ObjectId = $MicrosoftApp.id
    AppId = $MicrosoftApp.AppID
    SingleSignOn = $MicrosoftApp.PreferredSingleSignOnMode
    ReplyUrl = $MicrosoftApp.replyurls -join ","
    LoginURL = $MicrosoftApp.LoginURl
    LogoutURL = $MicrosoftApp.LogoutURL
    SSOCertificateExpirationDate = $MicrosoftApp.PreferredTokenSigningKeyEndDateTime
    SignInAudience = $MicrosoftApp.SignInAudience
    HomepageURL = $MicrosoftApp.Homepage
    AppRoleAppAssignmentRequired = $MicrosoftApp.AppRoleAppAssignmentRequired
    AccountEnabled = $MicrosoftApp.AccountEnabled
    ServicePrincipalType = "MicrosoftApplication"
    }
    )
}


$ManagedIdentitys = Get-MgBetaServicePrincipal -All -Filter "ServicePrincipalType eq 'ManagedIdentity'"
$ManagedIdentityoutput = @()
foreach($managedidentity in $ManagedIdentitys){
    $ManagedIdentityoutput += New-object PSObject -property $([ordered]@{
    DisplayName = $ManagedIdentity.DisplayName
    ObjectId = $ManagedIdentity.id
    AppId = $ManagedIdentity.AppID
    SingleSignOn = $ManagedIdentity.PreferredSingleSignOnMode
    ReplyUrl = $ManagedIdentity.replyurls -join ","
    LoginURL = $ManagedIdentity.LoginURl
    LogoutURL = $ManagedIdentity.LogoutURL
    SSOCertificateExpirationDate = $ManagedIdentity.PreferredTokenSigningKeyEndDateTime
    SignInAudience = $ManagedIdentity.SignInAudience
    HomepageURL = $ManagedIdentity.Homepage
    AppRolManagedIdentityssignmentRequired = $ManagedIdentity.AppRolManagedIdentityppAssignmentRequired
    AccountEnabled = $ManagedIdentity.AccountEnabled
    ServicePrincipalType = "ManagedIdentity"
    }
    )
}


$CopilotApps = Get-MgBetaServicePrincipal -All -Filter "endswith(Displayname,'(Microsoft Copilot Studio)')" -consistencylevel Eventual
$CopilotAppsoutput = @()
foreach($CopilotApp in $CopilotApps){
    $CopilotAppsoutput += New-object PSObject -property $([ordered]@{
    DisplayName = $CopilotApp.DisplayName
    ObjectId = $CopilotApp.id
    AppId = $CopilotApp.AppID
    SingleSignOn = $CopilotApp.PreferredSingleSignOnMode
    ReplyUrl = $CopilotApp.replyurls -join ","
    LoginURL = $CopilotApp.LoginURl
    LogoutURL = $CopilotApp.LogoutURL
    SSOCertificateExpirationDate = $CopilotApp.PreferredTokenSigningKeyEndDateTime
    SignInAudience = $CopilotApp.SignInAudience
    HomepageURL = $CopilotApp.Homepage
    AppRoleAppAssignmentRequired = $CopilotApp.AppRoleAppAssignmentRequired
    AccountEnabled = $CopilotApp.AccountEnabled
    ServicePrincipalType = "CopilotApp"
    }
    )
}

$output = $eaoutput + $MicrosoftAppoutput + $ManagedIdentityoutput + $CopilotAppsoutput


$appsnotdefined = @()
$serviceprincipals = Get-MgBetaServicePrincipal -All
foreach($sp in $serviceprincipals){
    if($sp.id -notin $output.Objectid){
        $appsnotdefined += $sp
    }
}
$UndefinedAppsOutput = @()
foreach($undefinedapp in $AppsnotDefined){
    $UndefinedAppsOutput += New-object PSObject -property $([ordered]@{
    DisplayName = $UndefinedApp.DisplayName
    ObjectId = $UndefinedApp.id
    AppId = $UndefinedApp.AppID
    SingleSignOn = $UndefinedApp.PreferredSingleSignOnMode
    ReplyUrl = $UndefinedApp.replyurls -join ","
    LoginURL = $UndefinedApp.LoginURl
    LogoutURL = $UndefinedApp.LogoutURL
    SSOCertificateExpirationDate = $UndefinedApp.PreferredTokenSigningKeyEndDateTime
    SignInAudience = $UndefinedApp.SignInAudience
    HomepageURL = $UndefinedApp.Homepage
    AppRoleAppAssignmentRequired = $UndefinedApp.AppRoleAppAssignmentRequired
    AccountEnabled = $UndefinedApp.AccountEnabled
    ServicePrincipalType = "UndefinedApp"
    }
    )
}

$prefixoutput = $eaoutput + $MicrosoftAppoutput + $ManagedIdentityoutput + $CopilotAppsoutput + $UndefinedAppsOutput
# --------------------------
# Manual dedupe (keep first occurrence) using IF/hashtable
# --------------------------
$seenAppIds = @{}                # hashtable to track seen AppIds
$finaloutput = @()               # array to collect unique items
$duplicatesCount = 0

foreach ($item in $prefixoutput) {
    # Normalize AppId to a string (case-insensitive)
    $appIdRaw = $null
    if ($item.PSObject.Properties.Match('AppId')) { $appIdRaw = $item.AppId }

    if ($appIdRaw -ne $null -and $appIdRaw.ToString().Trim() -ne '') {
        $appId = $appIdRaw.ToString().ToLower().Trim()
        if (-not $seenAppIds.ContainsKey($appId)) {
            # first time: keep it
            $seenAppIds[$appId] = $true
            $finaloutput += $item
        } else {
            # duplicate: skip it
            $duplicatesCount++
        }
    } else {
        # item has no AppId — keep it (you can change this behaviour if desired)
        $finaloutput += $item
    }
}

# Report duplicates (group by AppId to show counts)
$dupeGroups = $prefixoutput | Group-Object -Property AppId | Where-Object { $_.Count -gt 1 }
if ($dupeGroups) {
    Write-Host "⚠️ Removed $duplicatesCount duplicate entries (based on AppId)."
    $dupeGroups | ForEach-Object {
        Write-Host "Duplicate AppId: $($_.Name) - Count: $($_.Count)"
    }
} else {
    Write-Host "No duplicate AppIds found."
}

# Export final CSV and upload to storage
$finaloutput | Export-CSV "$Env:temp/GetEnterpriseAppList.csv" -NoTypeInformation -Encoding utf8
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/GetEnterpriseAppList.csv" -Blob $FileName -Force
