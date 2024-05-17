#Get user list to be assigned ObjectID
$users = @()
#Get Role Definitions(need RoledefinitionId)
$roles = Get-MgRoleManagementDirectoryRoleDefinition | select displayname,description,isbuiltin,isenabled,id

foreach($user in get-content c:\temp\users.txt){
$users += get-mguser -Userid $user}


#Check Desired Role
$roles
$rolesassigned = @()
foreach($user in $users){
$id = $user.id
$params = @{
  "PrincipalId" = $id
  #Change for the Needed Role ID
  "RoleDefinitionId" = "7be44c8a-adaf-4e2a-84d6-ab2649e08a13"
  #Input Justification
  "Justification" = ""
  "DirectoryScopeId" = "/"
  "Action" = "AdminAssign"
  "ScheduleInfo" = @{
    "StartDateTime" = Get-Date
    "Expiration" = @{
      "Type" = "AfterDateTime"
	  #Define Expiration Date
      "endDateTime" = [System.DateTime]::Parse("2024-10-30T00:00:00Z")
      }
    }
   }

New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter $params | 
  Format-List Id, Status, Action, AppScopeId, DirectoryScopeId, RoleDefinitionId, IsValidationOnly, Justification, PrincipalId, CompletedDateTime, CreatedDateTime
  

#Roles assigned to each User
$rolesassigned += Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$id'" 
}
#Join Assignments and User Information
$joinroleanduser = Join-Object -Left $rolesassigned -Right $users -LeftJoinProperty principalid -RightJoinProperty id -ExcludeLeftProperties id,additionalproperties -RightProperties displayname,userprincipalname 

#Join Assignment Role Information
$joinfull = Join-Object -Left $joinroleanduser -Right $roles -LeftJoinProperty roledefinitionid -RightJoinProperty id -RightMultiMode SubGroups
 $joinfull | ft displayname,userprincipalname,startdatetime,enddatetime,principalid,roledefinitionid,rightgroup
