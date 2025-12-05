 
  #Connect to Microsoft Graph
# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

#Extract the access token from the AzAccount authentication context and use it to connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token

$securetoken = ConvertTo-SecureString -String $token -ASPLAINTEXT -force
Connect-MgGraph -AccessToken $token
Get-mgcontext | Select -expandproperty Scopes 

 #StorageAccountVariables
$StorageAccountName = ''
$StorageAccountKey = ""
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$FileName = 'EnterpriseAppsAssignments.csv'
$ContainerName  = ''

$AllAppUsers = @()

Measure-command {
# Get all service principals (Enterprise Apps)
$ServicePrincipals = Get-MgServicePrincipal -All

foreach ($ServicePrincipal in $ServicePrincipals) {
    $isManagedIdentity = $false
    if ($ServicePrincipal.ServicePrincipalType -eq "ManagedIdentity") {
        $isManagedIdentity = $true
    }

    Write-Host "🔎 Processing App: $($ServicePrincipal.DisplayName) (Managed Identity: $isManagedIdentity)"

    # Get all assignments for this app
    $Assignments = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $ServicePrincipal.Id -All

    foreach ($Assignment in $Assignments) {
        $ptype = $Assignment.PrincipalType.ToLower()

        if ($ptype -eq "user") {
            # Direct user
            $User = Get-MgUser -UserId $Assignment.PrincipalId -ErrorAction SilentlyContinue
            if ($User) {
                $AllAppUsers += [PSCustomObject]@{
                    AppName           = $ServicePrincipal.DisplayName
                    AppID             = $ServicePrincipal.id
                    ManagedIdentity   = $isManagedIdentity
                    AssignmentSource  = "Direct"
                    GroupName         = ""
                    DisplayName       = $User.DisplayName
                    UserPrincipalName = $User.UserPrincipalName
                    ObjectId          = $User.Id
                }
            }
        }
        elseif ($ptype -eq "group") {
            # Group assignment
            $Group = Get-MgGroup -GroupId $Assignment.PrincipalId -ErrorAction SilentlyContinue
            if ($Group) {
                Write-Host "📂 Expanding group: $($Group.DisplayName) for app $($ServicePrincipal.DisplayName)"
                $Members = Get-MgGroupMember -GroupId $Group.Id -All
                foreach ($Member in $Members) {
                    if ($Member.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.user") {
                        $AllAppUsers += [PSCustomObject]@{
                            AppName           = $ServicePrincipal.DisplayName
                            AppID             = $ServicePrincipal.id
                            ManagedIdentity   = $isManagedIdentity
                            AssignmentSource  = "Group"
                            GroupName         = $Group.DisplayName
                            DisplayName       = $Member.AdditionalProperties.displayName
                            UserPrincipalName = $Member.AdditionalProperties.userPrincipalName
                            ObjectId          = $Member.Id
                        }
                    }
                }
            }
        }
    }
}
#Export Output
$excelfilename = "$Env:temp/EnterpriseAppsAssignments.csv"
$allappusers | Export-csv "$Env:temp/EnterpriseAppsAssignments.csv" -notypeinformation
}
 #Export to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File $excelfilename  -Blob $FileName -Force
