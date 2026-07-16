# Define the Site ID (Format: tenant.sharepoint.com,site-collection-id,site-id)
# $siteId = "your-site-id-here"

# Retrieve all permissions for the specific Site
$permissions = Get-MgBetaSitePermission -SiteId $siteId

# Process each permission to flatten the nested properties
$flattenedPermissions = foreach ($perm in $permissions) {
    
    $identityType = "Unknown/Link"
    $identityName = $null
    $identityId   = $null

    # Check if the .Id property is populated to determine identity type
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
$flattenedPermissions | Format-Table -AutoSize
