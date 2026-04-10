# The value of $AppId is the application identifier for the app or service principal that you're assigning the permission to
$Application = @{}
$Application.Add("id", "")
$Application.Add("displayName","")
$SiteID = ""
$RequestedRole = "write"

$Status = New-MgSitePermission -SiteId $Siteid -Roles $RequestedRole -GrantedToIdentities @{"application" = $Application}
If ($Status.id) { 
   Write-Host ("{0} permission granted to site {1}" -f $RequestedRole, $Site.DisplayName )
}


[array]$Permissions = Get-MgSitePermission -SiteId $Siteid
ForEach ($Permission in $Permissions){
   $Data = Get-MgSitePermission -PermissionId $Permission.Id -SiteId $SiteID -Property Id, Roles, GrantedToIdentitiesV2
   Write-Host ("{0} permission available to {1}" -f ($Data.Roles -join ","), $Data.GrantedToIdentitiesV2.Application.DisplayName)
}
