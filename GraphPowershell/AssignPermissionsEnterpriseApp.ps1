#Requires -Module Microsoft.Graph.Authentication
#Requires -Module Microsoft.Graph.Applications

function Add-EnterpriseAppPermissions{
    <#
    .SYNOPSIS
        Provides specified API permissions to the Enterprise Application/Service Principal specified

    .DESCRIPTION
        Provides specified API permissions to the Enterprise Application/Service Principal specified.
        Primarily developed to provide managed identities with API permissions.

    .PARAMETER Permissions
        The specific API permissions you'd like to grant. E.g. Mail.Send, DeviceManagement.ManagedDevices.ReadWrite.All

    .PARAMETER APIName
        The display name of the API you'd like to grant permissions to. E.g. 'Microsoft Graph'

    .PARAMETER EnterpriseApp
        The Enterprise Application/Service Principal you'd like to have the permissions

    .PARAMETER AppId
        The Enterprise Application's Application ID. Use this parameter ONLY if you have duplicate enterprise app names. Please continue to use the EnterpriseApp parameter 
           
    .EXAMPLE
        Add-EnterpriseAppPermissions -Permissions "DeviceManagementManagedDevices.ReadWrite.All","Mail.Send" -APIName "Microsoft Graph" -EnterpriseApp "VMTest001"
        The command above provides system managed identity VMTest001 with permissions to send mail, and read/write to all devices in the Microsoft Graph API

    .EXAMPLE
        Add-EnterpriseAppPermissions -Permissions "MailboxSettings.Read" -APIName "Office 365 Exchange Online" -EnterpriseApp "Automation-Account-001"
        The command above provides managed identity "Automation-Account-001" with permissions to read Exchange mailboxes.

    .EXAMPLE
        $Permissions = @(
        "Application.Read.All"
        "Device.ReadWrite.All"
        "Directory.Read.All"
        )

        Add-EnterpriseAppPermissions -Permissions $Permissions -APIName "Windows Azure Active Directory" -EnterpriseApp "VMTest001"
        This example just shows a different method of entering the permissions, rather than using a comma separated list inline with the cmdlet.

    .NOTES
        Author: Glenn Senior
        Created: April 2023
        LinkedIn: https://linkedin/glenn-senior-it4u    

    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage="The specific API permissions you'd like to grant. E.g. Mail.Send, DeviceManagement.ManagedDevices.ReadWrite.All")]
        [string[]]$Permissions,

        [Parameter(Mandatory=$true,HelpMessage="The display name of the API you'd like to grant permissions to. E.g. 'Microsoft Graph'")]
        [string]$APIName,

        [Parameter(Mandatory=$true,HelpMessage="The Enterprise Application/Service Principal you'd like to have the permissions")]
        [string]$EnterpriseApp,

        [Parameter(HelpMessage="The Enterprise Application's Application ID. Use this parameter ONLY if you have duplicate enterprise app names. Please continue to use the EnterpriseApp parameter")]
        [string]$AppId
    )

    if (!(Get-MgContext)){
        Write-Warning "Please connect to MgGraph (Connect-MgGraph). You'll need scopes Application.ReadWrite.All and AppRoleAssignment.ReadWrite.All"
        return
    }

    $EA = Get-MgServicePrincipal -Filter "displayName eq '$EnterpriseApp'"
    if (!$EA){
        Write-Warning "Could not find an Enterprise Application with this name. Please check, and try again. Also check Get-MgContext with whether you're in the right tenant."
        return
    }

    if ($EA.count -gt 1){
        if ($AppId){
            $EA = $EA | Where-Object {$_.AppId -eq $AppId}
        }
        else {
            Write-Warning "There is more than one Enterprise App named '$EnterpriseApp' in your tenant. Sorry to be a pain, but can you find the Application ID and use that with -AppId"
            return
        }
    }

    $API = Get-MgServicePrincipal -Filter "displayName eq '$APIName'"
    if (!$API){
        Write-Warning "Could not find an API with this name. Please check and try again. Also check Get-MgContext with whether you're in the right tenant. Note, this needs to have Application Permissions"
        return
    }

    ForEach ($Permission in $Permissions){
        if ($Permission -notin $API.AppRoles.Value){
            Write-Warning "Permission: $Permission was not found in API $($APIName.DisplayName). Please check and adjust accordingly."
            return
        }
    }
    $AppRoles = $API.AppRoles | Where-Object {($_.Value -in $Permissions) -and ($_.AllowedMemberTypes -contains "Application")}
    
    if (!$AppRoles){
        Write-Warning "No permissions were found matching what was requested against this API. Please check whether you have the correct permissions for this API."
        return
    }

    ForEach($Role in $AppRoles){
        Write-Host "Adding the following:"
        Write-Host "API Name: $($API.DisplayName) (ID: $($API.Id)"
        Write-Host "Permission Name: $($Role.Value)"
        Write-Host "Permission Description: $($Role.Description)"
        Write-Host "------------------------------------------------------------"
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $EA.Id -PrincipalId $EA.Id -AppRoleId $Role.Id -ResourceId $API.Id
    }
}
