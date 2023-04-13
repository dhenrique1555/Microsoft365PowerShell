#Graph Permissions needed in App: "Policy.Read.All" for Get-MgIdentityConditionalAccessPolicy,"User.Read.All" for Get-mgUser

#ConnectGraph
$ApplicationID = read-host "Insert App ID"
$TenatDomainName = read-host "Insert Tenant Root Domain"
$AccessSecret = read-host "Insert App Secret"



$Body = @{    
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    client_Id     = $ApplicationID
    Client_Secret = $AccessSecret
}



$ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenatDomainName/oauth2/v2.0/token" -Method POST -Body $Body
$token = $ConnectGraph.access_token



Connect-mggraph -accesstoken $token

Get-date

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

#Extract the access token from the AzAccount authentication context and use it to connect to Microsoft Graph
$token = (Get-AzAccessToken -ResourceTypeName MSGraph).token
Connect-MgGraph -AccessToken $token
gET-MGCONTEXT | SELECT -EXPANDPROPERTY scoPES   


#GetPoliciesandScopedUsers
$nestedgroup = @()
$resultincludedusers = @()
$resultexcludedusers = @()
$resultincludedgroups = @()
$resultexcludedgroups = @()
$resultgroupmembers = @()
$ResultIncludedGroupsMembers = @()
$ResultNestedIncludedGroupMembers = @()
$idtype = @()
$Policies = (Get-MgIdentityConditionalAccessPolicy).id
foreach($policy in $policies){
$policyname = (Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy).displayname
#start-sleep -seconds 10
$IDUserInclude = (Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy).conditions.users.includeusers
#start-sleep -seconds 10
$IDUserExclude =(Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy).conditions.users.excludeusers
#start-sleep -seconds 10
$IDGroupInclude = (Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy).conditions.users.includegroups
#start-sleep -seconds 10
$IDGroupExclude = (Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy).conditions.users.excludegroups
#start-sleep -seconds 10

#Narrow Down Scoped Objects and Assigned Policy
foreach($id in $iduserinclude){
$userpolicy = get-mguser -userid $id
$ResultIncludedUsers += New-Object PSObject -property $([ordered]@{
ID = $id
UserPrincipalName = $Userpolicy.userPrincipalName
Username = $userpolicy.Displayname
Policy = $policyname
})
}
foreach($id in $iduserexclude){
$userpolicy = get-mguser -userid $id
$ResultexcludedUsers += New-Object PSObject -property $([ordered]@{
ID = $id
UserPrincipalName = $Userpolicy.userPrincipalName
Username = $userpolicy.Displayname
Policy = $policyname
})
}
foreach($id in $idgroupinclude){
$grouppolicy = get-mggroup -groupid $id
$ResultIncludedGroups += New-Object PSObject -property $([ordered]@{
ID = $id
Groupname = $grouppolicy.Displayname
Policy = $policyname
})
}
foreach($id in $idgroupexclude){
$grouppolicy = get-mggroup -groupid $id
$ResultExcludedGroups += New-Object PSObject -property $([ordered]@{
ID = $id
Groupname = $grouppolicy.Displayname
Policy = $policyname
})
}


#Get Members from Scoped Policy Groups


foreach($group in $resultincludedgroups.id){
$Groupmembersid = get-mggroupmember -GroupId $group -all
$IDTYPE += New-object PSObject -Property $([ordered]@{
	ID = $groupmembersid.id
	MemberType = $groupmembersid.additionalproperties.'@odata.type'
})
}

$Groupname = (get-mggroup -groupid $group).displayname
foreach($user in $groupmembersid.id){

$Userinfo =	get-mguser -userid $user

$ResultIncludedGroupsMembers += New-Object PSObject -property $([ordered]@{
ID = $userinfo.id
UserPrincipalName = $userinfo.userPrincipalName
DisplayName = $userinfo.DisplayName
GroupName = $groupname
Policy = $policyname
})
}

}



#Get Members from scoped policy nested groups(NotFinished)
Foreach($ngroup in $nestedgroup)
{
$nestedgroupmemberdsid = get-mggroupmember -groupid $ngroup -all
$nestedgroupname = (get-mggroup -groupid $ngroup).displayname
foreach($user in $nestedgroupmemberdsid.id){
	$NestedUserinfo = get-mguser -userid $user
	$ResultNestedIncludedGroupMembers += New-Object PSObject -property $([ordered]@{
		ID = $nesteduserinfo.id
		UserPrincipalName = $nesteduserinfo.userPrincipalName
		DisplayName = $nesteduserinfo.DisplayName
		GroupName = $nestedgroupmembername
		Policy = $PolicyName
	})
}
}

#ExporttoCSV
$resultincludedusers | Export-Csv $Env:temp/ResultIncludedUsersConditionalAccessPolicies.csv -NoTypeInformation
$resultexcludedusers | Export-Csv $Env:temp/ResultExcludedUsersConditionalAccessPolicies.csv -NoTypeInformation
$resultincludedgroups | Export-Csv $Env:temp/ResultIncludedGroupsConditionalAccessPolicies.csv -NoTypeInformation
$resultexcludedgroups |Export-Csv $Env:temp/ResultExcludedGroupsConditionalAccessPolicies.csv -NoTypeInformation
$resultincludedgroupsmembers |Export-Csv $Env:temp/ResultIncludedGroupsMembersConditionalAccessPolicies.csv -NoTypeInformation
$ResultNestedIncludedGroupMembers |Export-Csv $Env:temp/ResultNestedIncludedGroupMembersconditionalaccesspolicies.csv -NoTypeInformation

#Storage Account Properties for Azure Automation 
$StorageAccountName = read-host "Insert Storage Account Name"
$StorageAccountKey = read-host "Insert Storage Account Key"
$StorageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $StorageAccountKey
$ContainerName  = read-host "Insert Container Name"
$FileName = 'ResultIncludedUsersConditionalAccessPolicies.csv'
$filename1 = 'ResultExcludedUsersConditionalAccessPolicies.csv'
$filename2 =  'ResultIncludedGroupsConditionalAccessPolicies.csv'
$filename3 =  'ResultExcludedGroupsConditionalAccessPolicies.csv'
$filename4 = 'ResultIncludedGroupsMembersConditionalAccessPolicies.csv'
$filename5 = 'ResultNestedIncludedGroupMembersconditionalaccesspolicies.csv'

#SaveFiles to Storage Account
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/ResultExcludedUsersConditionalAccessPolicies.csv" -Blob $FileName1 -Force
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/ResultIncludedGroupsConditionalAccessPolicies.csv" -Blob $FileName2 -Force
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/ResultExcludedGroupsConditionalAccessPolicies.csv" -Blob $FileName3 -Force
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/ResultIncludedGroupsMembersConditionalAccessPolicies.csv" -Blob $FileName4 -Force
Set-AzStorageBlobContent -Context $StorageContext -Container $ContainerName -File "$Env:temp/ResultNestedIncludedGroupMembersconditionalaccesspolicies.csv" -Blob $FileName5 -Force
Get-date
