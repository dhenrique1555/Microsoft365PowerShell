# Install Microsoft Graph module if not installed
Install-Module Microsoft.Graph -Scope CurrentUser

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All"

# Source group ID and new group name
$SourceGroupId = ""
$NewGroupName = ""

# Get source group details
$SourceGroup = Get-MgGroup -GroupId $SourceGroupId

# Create new group with same properties (adjust as needed)
$NewGroup = New-MgGroup -DisplayName $NewGroupName -SecurityEnabled $SourceGroup.SecurityEnabled 

   
  

Write-Host "New group created: $($NewGroup.Id)"

# Get members of source group
$Members = Get-MgGroupMember -GroupId $SourceGroupId -All

foreach ($Member in $Members) {
    try {
        # Add each member to new group
        New-MgGroupMember -GroupId "" -DirectoryObjectId $Member.Id
        Write-Host "Added member: $($Member.Id)"
    }
    catch {
        Write-Host "Failed to add member $($Member.Id): $_"
    }
}
