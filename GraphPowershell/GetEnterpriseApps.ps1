$EAs = Get-MgBetaServicePrincipal -All -Filter "tags/any(t:t eq 'WindowsAzureActiveDirectoryIntegratedApp')"

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

$finaloutput = $eaoutput + $MicrosoftAppoutput + $ManagedIdentityoutput + $CopilotAppsoutput + $UndefinedAppsOutput

