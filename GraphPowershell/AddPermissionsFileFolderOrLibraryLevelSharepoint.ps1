
Import-Module Microsoft.Graph.Beta.Sites
#Add Permission
$siteid = ""
$listid = ""
$listitemId = ""
$params = @{
	grantedToV2 = @{
		application = @{
			id = ""
			displayName = ""
		}
	}
	roles = @(
	"write"
	"read"
)
}

New-MgBetaSiteListItemPermission -SiteId $siteid -ListId $listid -ListItemId $listitemId -BodyParameter $params

#Get List
Get-MgSiteList -SiteId $siteid
#Get List Item
Get-MgSiteListItem  -SiteId $siteId -ListId $listid 

#Get Permission
Get-MgBetaSiteListItemPermission -SiteId $siteid -ListId $listid -ListItemId $listemid | 
    Select-Object Id, 
                  @{Name="Roles"; Expression={$_.Roles -join ", "}}, 
                  @{Name="AppDisplayName"; Expression={$_.GrantedToV2.Application.DisplayName}},
                  @{Name="AppId"; Expression={$_.GrantedToV2.Application.Id}}
				  
				  # Retrieve all permissions for the specific list item
$permissions = Get-MgBetaSiteListItemPermission -SiteId $siteid -ListId $listid -ListItemId $listitemId
# Process each permission to flatten the nested properties
$flattenedPermissions = foreach ($perm in $permissions) {
    
    $identityType = "Unknown/Link"
    $identityName = $null
    $identityId   = $null

    # FIX: We now check if the .Id property is populated, rather than just the parent object.
    if ($perm.GrantedToV2) {
        if ($perm.GrantedToV2.Application.Id) {
            $identityType = "Application"
            $identityName = $perm.GrantedToV2.Application.DisplayName
            $identityId   = $perm.GrantedToV2.Application.Id
        } elseif ($perm.GrantedToV2.User.Id) {
            $identityType = "User"
            $identityName = $perm.GrantedToV2.User.DisplayName
            $identityId   = $perm.GrantedToV2.User.Id
        } elseif ($perm.GrantedToV2.Group.Id) {
            $identityType = "Group"
            $identityName = $perm.GrantedToV2.Group.DisplayName
            $identityId   = $perm.GrantedToV2.Group.Id
        } elseif ($perm.GrantedToV2.SiteGroup.Id) {
            $identityType = "SiteGroup"
            $identityName = $perm.GrantedToV2.SiteGroup.DisplayName
            $identityId   = $perm.GrantedToV2.SiteGroup.Id
        } elseif ($perm.GrantedToV2.SiteUser.Id) {
            $identityType = "SiteUser"
            $identityName = $perm.GrantedToV2.SiteUser.DisplayName
            $identityId   = $perm.GrantedToV2.SiteUser.Id
        } elseif ($perm.GrantedToV2.Device.Id) {
            $identityType = "Device"
            $identityName = $perm.GrantedToV2.Device.DisplayName
            $identityId   = $perm.GrantedToV2.Device.Id
        }
    }

    $linkType  = if ($perm.Link) { $perm.Link.Type } else { "N/A" }
    $linkScope = if ($perm.Link) { $perm.Link.Scope } else { "N/A" }
    $isInherited = if ($perm.InheritedFrom) { $true } else { $false }

    [PSCustomObject]@{
        PermissionId       = $perm.Id
        Roles              = if ($perm.Roles) { $perm.Roles -join ", " } else { "None" }
        IdentityType       = $identityType
        IdentityName       = $identityName
        IdentityId         = $identityId
        Expiration         = if ($perm.ExpirationDateTime) { $perm.ExpirationDateTime.ToString() } else { "Never" }
        HasPassword        = if ($null -ne $perm.HasPassword) { $perm.HasPassword } else { $false }
        IsInherited        = $isInherited
        ShareId            = $perm.ShareId
        LinkType           = $linkType
        LinkScope          = $linkScope
    }
}

# Display the results
$flattenedPermissions | Format-Table
